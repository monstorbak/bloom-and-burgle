--!strict
-- PlantHandler: planting, growing, harvesting, selling, mutations.
-- Server is authoritative. Clients fire PlantSeed and SellPlants RemoteEvents;
-- the server validates and pays out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local PlantData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlantData"))

local SellPlantsRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SellPlants") :: RemoteEvent
local PlantSeedRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlantSeed") :: RemoteEvent

-- inventory[userId][speciesId .. ":" .. (mutationId or "")] = count
local inventory: { [number]: { [string]: number } } = {}

local function getInv(player: Player): { [string]: number }
	local uid = player.UserId
	if not inventory[uid] then
		inventory[uid] = {}
	end
	return inventory[uid]
end

local function plantSeedAt(player: Player, planter: BasePart, speciesId: string, freebie: boolean?)
	if planter:GetAttribute("OwnerUserId") ~= player.UserId then return false end
	if not planter:GetAttribute("IsEmpty") then return false end

	local species = PlantData.get(speciesId)
	if not species then return false end

	if not freebie then
		local ls = player:FindFirstChild("leaderstats")
		if not ls then return false end
		local cash = ls:FindFirstChild("Cash") :: IntValue?
		if not cash then return false end
		if cash.Value < species.seedCost then return false end
		cash.Value = cash.Value - species.seedCost
	end

	planter:SetAttribute("IsEmpty", false)
	planter:SetAttribute("PlantedSpecies", species.id)
	planter:SetAttribute("PlantedAt", os.time())
	planter:SetAttribute("GrowSeconds", species.growSeconds)

	-- Visual seedling
	local existing = planter:FindFirstChild("Plant")
	if existing then existing:Destroy() end
	local sprout = Instance.new("Part")
	sprout.Name = "Plant"
	sprout.Size = Vector3.new(1, 0.5, 1)
	sprout.Position = planter.Position + Vector3.new(0, 1.5, 0)
	sprout.Anchored = true
	sprout.CanCollide = false
	sprout.Material = Enum.Material.Neon
	sprout.Color = Color3.new(species.color[1], species.color[2], species.color[3])
	sprout.TopSurface = Enum.SurfaceType.Smooth
	sprout.Parent = planter
	return true
end

-- Grow tick: scale sprouts, auto-harvest when ripe
RunService.Heartbeat:Connect(function()
	local now = os.time()
	for _, planter in CollectionService:GetTagged("Planter") do
		if planter:GetAttribute("IsEmpty") then continue end
		if not planter:IsA("BasePart") then continue end
		local plantedAt = planter:GetAttribute("PlantedAt") or 0
		local growSeconds = planter:GetAttribute("GrowSeconds") or 60
		local elapsed = now - plantedAt
		local progress = math.clamp(elapsed / growSeconds, 0, 1)

		local sprout = planter:FindFirstChild("Plant") :: BasePart?
		if sprout then
			local h = 0.5 + progress * 5.0
			sprout.Size = Vector3.new(1 + progress * 1.5, h, 1 + progress * 1.5)
			sprout.Position = planter.Position + Vector3.new(0, 0.75 + h / 2, 0)
		end

		if progress >= 1.0 then
			local speciesId = planter:GetAttribute("PlantedSpecies") :: string
			local species = PlantData.get(speciesId)
			local ownerId = planter:GetAttribute("OwnerUserId") :: number
			local owner = Players:GetPlayerByUserId(ownerId)
			if owner and species then
				-- Roll mutation
				local mutationId = ""
				if math.random() <= species.mutationChance then
					local mut = PlantData.rollMutation()
					if mut then
						mutationId = mut.id
					end
				end
				local key = speciesId .. ":" .. mutationId
				local inv = getInv(owner)
				inv[key] = (inv[key] or 0) + 1
				owner:SetAttribute("PlantsHarvested", (owner:GetAttribute("PlantsHarvested") or 0) + 1)
			end

			planter:SetAttribute("IsEmpty", true)
			planter:SetAttribute("PlantedSpecies", nil)
			planter:SetAttribute("PlantedAt", nil)
			planter:SetAttribute("GrowSeconds", nil)
			if sprout then sprout:Destroy() end
		end
	end
end)

-- Wire SellPad on a per-instance basis (handles plots created mid-game)
local function wireSellPad(sellPad: Instance)
	if not sellPad:IsA("BasePart") then return end
	if sellPad:GetAttribute("WiredSell") then return end
	sellPad:SetAttribute("WiredSell", true)
	sellPad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		if sellPad:GetAttribute("OwnerUserId") ~= player.UserId then return end

		local inv = getInv(player)
		local total = 0
		local soldDetails: { [string]: number } = {}
		for key, count in inv do
			if count <= 0 then continue end
			local sep = string.find(key, ":") or 0
			local sId = string.sub(key, 1, sep - 1)
			local mId = string.sub(key, sep + 1)
			local spec = PlantData.get(sId)
			if not spec then continue end
			local mult = 1
			if mId ~= "" then
				for _, m in PlantData.MUTATIONS do
					if m.id == mId then mult = m.multiplier; break end
				end
			end
			local subtotal = count * spec.baseValue * mult
			total += subtotal
			soldDetails[key] = count
			inv[key] = 0
		end
		if total <= 0 then return end

		local cashMult = player:GetAttribute("CashMultiplier") or 1
		total = math.floor(total * cashMult)
		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local cash = ls:FindFirstChild("Cash") :: IntValue?
			if cash then
				cash.Value = cash.Value + total
			end
		end
		-- Track lifetime earnings (used for shop unlocks)
		local lifetime = (player:GetAttribute("LifetimeCash") or 0) + total
		player:SetAttribute("LifetimeCash", lifetime)
		SellPlantsRE:FireClient(player, total)
	end)
end

for _, sellPad in CollectionService:GetTagged("SellPad") do wireSellPad(sellPad) end
CollectionService:GetInstanceAddedSignal("SellPad"):Connect(wireSellPad)

-- Client-initiated planting (touch a planter via UI)
PlantSeedRE.OnServerEvent:Connect(function(player, planterRef, speciesId)
	if typeof(planterRef) ~= "Instance" or not planterRef:IsA("BasePart") then return end
	if not planterRef:HasTag("Planter") then return end
	if typeof(speciesId) ~= "string" then return end
	plantSeedAt(player, planterRef, speciesId, false)
end)

-- Starter pack: free sunblooms on first plot
Players.PlayerAdded:Connect(function(player)
	getInv(player)
	task.spawn(function()
		while not player:GetAttribute("PlotClaimed") do
			task.wait(0.5)
			if not player.Parent then return end
		end
		task.wait(2)
		for _, planter in CollectionService:GetTagged("Planter") do
			if planter:IsA("BasePart")
				and planter:GetAttribute("OwnerUserId") == player.UserId
				and planter:GetAttribute("IsEmpty") then
				plantSeedAt(player, planter, "sunbloom", true)
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	inventory[player.UserId] = nil
end)
