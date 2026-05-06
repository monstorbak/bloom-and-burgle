--!strict
-- PlantHandler: handles planting, growing, harvesting, selling.
-- Server is authoritative. Clients fire PlantSeed and SellPlants RemoteEvents;
-- the server validates and pays out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local PlantData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlantData"))

local SellPlantsRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SellPlants") :: RemoteEvent
local PlantSeedRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlantSeed") :: RemoteEvent

-- Track each player's harvested-but-unsold plant inventory
local inventory: { [number]: { [string]: number } } = {} -- userId → speciesId → count

local function getInv(player: Player): { [string]: number }
	local uid = player.UserId
	if not inventory[uid] then
		inventory[uid] = {}
	end
	return inventory[uid]
end

-- Try to plant a seed on `planter` for `player`
local function plantSeed(player: Player, planter: Part, speciesId: string)
	if planter:GetAttribute("OwnerUserId") ~= player.UserId then return end
	if not planter:GetAttribute("IsEmpty") then return end

	local species = PlantData.get(speciesId)
	if not species then return end

	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local cash = ls:FindFirstChild("Cash") :: IntValue?
	if not cash then return end
	if cash.Value < species.seedCost then return end
	cash.Value = cash.Value - species.seedCost

	planter:SetAttribute("IsEmpty", false)
	planter:SetAttribute("PlantedSpecies", species.id)
	planter:SetAttribute("PlantedAt", os.time())
	planter:SetAttribute("GrowSeconds", species.growSeconds)

	-- Visual: spawn a "seedling" part on top
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
end

-- Tick every second: grow each planted plant; auto-harvest when ripe; restock planter
RunService.Heartbeat:Connect(function()
	local now = os.time()
	for _, planter in CollectionService:GetTagged("Planter") do
		if planter:GetAttribute("IsEmpty") then continue end
		local plantedAt = planter:GetAttribute("PlantedAt") or 0
		local growSeconds = planter:GetAttribute("GrowSeconds") or 60
		local elapsed = now - plantedAt
		local progress = math.clamp(elapsed / growSeconds, 0, 1)

		-- Animate growth: scale the sprout part
		local sprout = planter:FindFirstChild("Plant") :: Part?
		if sprout then
			local h = 0.5 + progress * 4.5
			sprout.Size = Vector3.new(1 + progress, h, 1 + progress)
			sprout.Position = planter.Position + Vector3.new(0, 0.75 + h / 2, 0)
		end

		-- Auto-harvest when fully grown (1.0+); stash in player's inventory
		if progress >= 1.0 then
			local speciesId = planter:GetAttribute("PlantedSpecies") :: string
			local ownerId = planter:GetAttribute("OwnerUserId") :: number
			local owner = Players:GetPlayerByUserId(ownerId)
			if owner then
				local inv = getInv(owner)
				inv[speciesId] = (inv[speciesId] or 0) + 1
				owner:SetAttribute("PlantsHarvested", (owner:GetAttribute("PlantsHarvested") or 0) + 1)
			end

			-- Reset planter so player can replant
			planter:SetAttribute("IsEmpty", true)
			planter:SetAttribute("PlantedSpecies", nil)
			planter:SetAttribute("PlantedAt", nil)
			planter:SetAttribute("GrowSeconds", nil)
			if sprout then sprout:Destroy() end
		end
	end
end)

-- Sell pad: when player touches their sell pad, convert inventory → cash
for _, sellPad in CollectionService:GetTagged("SellPad") do
	sellPad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		if sellPad:GetAttribute("OwnerUserId") ~= player.UserId then return end

		local inv = getInv(player)
		local total = 0
		for speciesId, count in inv do
			local spec = PlantData.get(speciesId)
			if spec then
				total += count * spec.baseValue
			end
			inv[speciesId] = 0
		end
		if total <= 0 then return end

		local mult = player:GetAttribute("CashMultiplier") or 1
		total = math.floor(total * mult)
		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local cash = ls:FindFirstChild("Cash") :: IntValue?
			if cash then
				cash.Value = cash.Value + total
			end
		end
		-- Notify client for sound effect / floating text
		SellPlantsRE:FireClient(player, total)
	end)
end

-- Listen for client plant requests (clicked a planter in-world)
PlantSeedRE.OnServerEvent:Connect(function(player, planterRef, speciesId)
	if typeof(planterRef) ~= "Instance" or not planterRef:IsA("BasePart") then return end
	if not planterRef:HasTag("Planter") then return end
	if typeof(speciesId) ~= "string" then return end
	plantSeed(player, planterRef, speciesId)
end)

-- New player → empty inventory, auto-plant first sunbloom on each empty planter
-- as a "starter pack" so first 60s feels productive
Players.PlayerAdded:Connect(function(player)
	getInv(player)
	-- Wait until they claim their plot; PlotManager raises a flag
	task.spawn(function()
		while not player:GetAttribute("PlotClaimed") do
			task.wait(0.5)
			if not player.Parent then return end
		end
		-- Find their planters and seed them with a free sunbloom each (one-time gift)
		task.wait(2)  -- let plot finish spawning
		for _, planter in CollectionService:GetTagged("Planter") do
			if planter:GetAttribute("OwnerUserId") == player.UserId
				and planter:GetAttribute("IsEmpty") then
				-- Plant for free (skip cash check)
				planter:SetAttribute("IsEmpty", false)
				planter:SetAttribute("PlantedSpecies", "sunbloom")
				planter:SetAttribute("PlantedAt", os.time())
				planter:SetAttribute("GrowSeconds", 60)
				local sprout = Instance.new("Part")
				sprout.Name = "Plant"
				sprout.Size = Vector3.new(1, 0.5, 1)
				sprout.Position = planter.Position + Vector3.new(0, 1.5, 0)
				sprout.Anchored = true
				sprout.CanCollide = false
				sprout.Material = Enum.Material.Neon
				sprout.Color = Color3.fromRGB(255, 218, 50)
				sprout.Parent = planter
			end
		end
	end)
end)
