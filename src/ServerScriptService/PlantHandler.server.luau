--!strict
-- PlantHandler: planting, growing, harvesting, selling, mutations.
-- Server is authoritative. Clients fire PlantSeed and SellPlants RemoteEvents;
-- the server validates and pays out.
--
-- BAB-002: Plant + stash state lives in DataStore (`plot.planters`, `plot.stash`).
-- This module exposes a small ModuleScript-style API on _G.PlantHandler so
-- LeaderstatsScript can snapshot/restore without us having to migrate this
-- whole file to a ModuleScript right now (.server.luau is locked in by Rojo
-- for the planting/grow loops). The shared table is keyed by UserId.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local PlantData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlantData"))
local ServerScriptService = game:GetService("ServerScriptService")
local PlantVisuals = require(ServerScriptService:WaitForChild("PlantVisuals") :: ModuleScript)

local SellPlantsRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SellPlants") :: RemoteEvent
local PlantSeedRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlantSeed") :: RemoteEvent

local MAX_OFFLINE_SECONDS = 24 * 60 * 60  -- BAB-002: cap offline grow at 24h

-- inventory[userId][speciesId .. ":" .. (mutationId or "")] = count
local inventory: { [number]: { [string]: number } } = {}

local function getInv(player: Player): { [string]: number }
	local uid = player.UserId
	if not inventory[uid] then
		inventory[uid] = {}
	end
	return inventory[uid]
end

-- Resolve a planter Part for a given owner + slot index (1..9, 3x3 grid order).
-- Slot mapping matches PlotManager: slot N corresponds to Planter_(x+2)_(z+2)
-- where x,z ∈ {-1,0,1}. We iterate the tagged set since it's small (≤9 per
-- player) and avoids hard-coding plot model paths.
local function findPlanterForSlot(player: Player, slot: number): BasePart?
	local x = ((slot - 1) % 3) - 1      -- -1, 0, 1
	local z = math.floor((slot - 1) / 3) - 1
	local targetName = ("Planter_%d_%d"):format(x + 2, z + 2)
	for _, planter in CollectionService:GetTagged("Planter") do
		if not planter:IsA("BasePart") then continue end
		if planter:GetAttribute("OwnerUserId") ~= player.UserId then continue end
		if planter.Name == targetName then return planter end
	end
	return nil
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

	-- BAB-011: Build a real plant model (stem + leaves + flower) instead of a yellow box.
	PlantVisuals.create(planter, species)
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

		local plantModel = planter:FindFirstChild("Plant") :: Model?
		if plantModel and plantModel:IsA("Model") then
			PlantVisuals.update(plantModel, progress)
		end

		if progress >= 1.0 and not planter:GetAttribute("Ripe") then
			-- BAB-011: Plants now STAY ripe (waiting for player to walk over).
			-- Just mark them ripe; auto-harvest only happens via planter Touched (below)
			-- or via offline catch-up (handled in PlantHandler.restore).
			planter:SetAttribute("Ripe", true)
			if plantModel and plantModel:IsA("Model") then
				PlantVisuals.markRipe(plantModel, true)
			end
		end
		
		-- BAB-011: Update planter border visibility (hide when planted)
		local border = planter:FindFirstChild("EmptyBorder") :: BasePart?
		if border then
			if planter:GetAttribute("IsEmpty") then
				border.Transparency = 0  -- visible
			else
				border.Transparency = 1  -- hidden
			end
		end
	end
end)

-- Per-player debounce shared across all SellPad parts (base + invisible sensor
-- both touch on a single walk-over, so we only want to actually run sell logic
-- and fire the toast once per ~0.5s window).
local sellCooldown: { [number]: number } = {}

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

		local now = os.clock()
		if sellCooldown[player.UserId] and now - sellCooldown[player.UserId] < 0.5 then return end
		sellCooldown[player.UserId] = now

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

-- BAB-011: Harvest a single ripe planter for the player. Adds to stash.
-- Returns true if something was actually harvested.
local HarvestPopupRE = ReplicatedStorage:WaitForChild("RemoteEvents"):FindFirstChild("HarvestPopup")
if not HarvestPopupRE then
	HarvestPopupRE = Instance.new("RemoteEvent")
	HarvestPopupRE.Name = "HarvestPopup"
	HarvestPopupRE.Parent = ReplicatedStorage:WaitForChild("RemoteEvents")
end

local function harvestPlanter(player: Player, planter: BasePart): boolean
	if not planter:GetAttribute("Ripe") then return false end
	if planter:GetAttribute("OwnerUserId") ~= player.UserId then return false end
	local speciesId = planter:GetAttribute("PlantedSpecies") :: string
	local species = PlantData.get(speciesId)
	if not species then return false end

	-- Roll mutation
	local mutationId = ""
	if math.random() <= species.mutationChance then
		local mut = PlantData.rollMutation()
		if mut then mutationId = mut.id end
	end
	local key = speciesId .. ":" .. mutationId
	local inv = getInv(player)
	inv[key] = (inv[key] or 0) + 1
	player:SetAttribute("PlantsHarvested", (player:GetAttribute("PlantsHarvested") or 0) + 1)

	-- Fire popup to client
	HarvestPopupRE:FireClient(player, {
		species = speciesId,
		mutation = mutationId,
		emoji = species.emoji,
		name = species.displayName,
		position = planter.Position + Vector3.new(0, 5, 0),
	})

	-- Clear planter
	local plantModel = planter:FindFirstChild("Plant")
	if plantModel and plantModel.Parent then plantModel:Destroy() end
	planter:SetAttribute("IsEmpty", true)
	planter:SetAttribute("Ripe", false)
	planter:SetAttribute("PlantedSpecies", nil)
	planter:SetAttribute("PlantedAt", nil)
	planter:SetAttribute("GrowSeconds", nil)
	local border = planter:FindFirstChild("EmptyBorder") :: BasePart?
	if border then border.Transparency = 0 end
	return true
end

-- Wire harvest-on-touch for any planter
local function wirePlanterHarvest(planter: Instance)
	if not planter:IsA("BasePart") then return end
	if planter:GetAttribute("WiredHarvest") then return end
	planter:SetAttribute("WiredHarvest", true)
	local cooldown = {}
	planter.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		local now = os.clock()
		if cooldown[player.UserId] and now - cooldown[player.UserId] < 0.5 then return end
		cooldown[player.UserId] = now
		harvestPlanter(player, planter)
	end)
end
for _, p in CollectionService:GetTagged("Planter") do wirePlanterHarvest(p) end
CollectionService:GetInstanceAddedSignal("Planter"):Connect(wirePlanterHarvest)

-- Client-initiated planting (touch a planter via UI)
PlantSeedRE.OnServerEvent:Connect(function(player, planterRef, speciesId)
	if typeof(planterRef) ~= "Instance" or not planterRef:IsA("BasePart") then return end
	if not planterRef:HasTag("Planter") then return end
	if typeof(speciesId) ~= "string" then return end
	plantSeedAt(player, planterRef, speciesId, false)
end)

-- Starter pack: free sunblooms on first plot. BAB-002: only fire once per
-- account; flagged on the player via attribute `StarterPackGranted` which
-- LeaderstatsScript persists. Without this, every login refills empties with
-- free sunblooms = trivial farming exploit.
Players.PlayerAdded:Connect(function(player)
	getInv(player)
	task.spawn(function()
		while not player:GetAttribute("PlotClaimed") do
			task.wait(0.5)
			if not player.Parent then return end
		end
		if player:GetAttribute("StarterPackGranted") then return end
		task.wait(2)
		for _, planter in CollectionService:GetTagged("Planter") do
			if planter:IsA("BasePart")
				and planter:GetAttribute("OwnerUserId") == player.UserId
				and planter:GetAttribute("IsEmpty") then
				plantSeedAt(player, planter, "sunbloom", true)
			end
		end
		player:SetAttribute("StarterPackGranted", true)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	inventory[player.UserId] = nil
	sellCooldown[player.UserId] = nil
end)

-- ============================================================================
-- BAB-002 public API (consumed by LeaderstatsScript via _G.PlantHandler)
-- ============================================================================

local function buildSproutFor(planter: BasePart, species: any, progressOverride: number?)
	-- BAB-011: Build a real plant model at the saved progress.
	local model = PlantVisuals.create(planter, species)
	PlantVisuals.update(model, progressOverride or 0)
end

local function harvestOffline(player: Player, speciesId: string, species: any)
	-- Same logic as the live grow tick "if progress >= 1.0" branch but writes
	-- to the loaded inventory table directly.
	local mutationId = ""
	if math.random() <= species.mutationChance then
		local mut = PlantData.rollMutation()
		if mut then mutationId = mut.id end
	end
	local key = speciesId .. ":" .. mutationId
	local inv = getInv(player)
	inv[key] = (inv[key] or 0) + 1
	player:SetAttribute("PlantsHarvested", (player:GetAttribute("PlantsHarvested") or 0) + 1)
	if mutationId ~= "" then
		player:SetAttribute("MutationsFound", (player:GetAttribute("MutationsFound") or 0) + 1)
	end
end

local API = {}

-- Snapshot the per-player plant state for DataStore persistence. Returns a
-- shape compatible with `data.plot` in DataStore.luau's DEFAULT_DATA.
function API.snapshot(player: Player): { [string]: any }
	local planters: { [string]: any } = {}
	for _, planter in CollectionService:GetTagged("Planter") do
		if not planter:IsA("BasePart") then continue end
		if planter:GetAttribute("OwnerUserId") ~= player.UserId then continue end
		if planter:GetAttribute("IsEmpty") then continue end
		-- Decode slot from name `Planter_X_Z` (1..3, 1..3) -> 1..9
		local sx, sz = string.match(planter.Name, "Planter_(%d+)_(%d+)")
		if not (sx and sz) then continue end
		local slot = (tonumber(sz) - 1) * 3 + tonumber(sx)
		planters[tostring(slot)] = {
			species = planter:GetAttribute("PlantedSpecies"),
			plantedAt = planter:GetAttribute("PlantedAt"),
			growSeconds = planter:GetAttribute("GrowSeconds"),
		}
	end

	local stash: { [string]: number } = {}
	for key, count in getInv(player) do
		if count > 0 then stash[key] = count end
	end

	return { planters = planters, stash = stash }
end

-- Restore plant + stash state after PlotManager has rebuilt the plot.
-- `plot` shape: { planters = { ["slot"] = {species, plantedAt, growSeconds} }, stash = { [key] = count } }
-- `lastSeen` is os.time() of last save; we cap offline elapsed at 24h.
function API.restore(player: Player, plotData: { [string]: any }?, lastSeen: number?)
	if not plotData then return end
	local now = os.time()
	local cap = lastSeen and (lastSeen + MAX_OFFLINE_SECONDS) or now

	-- Stash first (safe regardless of plot existence)
	local stash = plotData.stash
	if typeof(stash) == "table" then
		local inv = getInv(player)
		for key, count in stash do
			if typeof(count) == "number" and count > 0 then
				inv[key] = (inv[key] or 0) + count
			end
		end
	end

	-- Planters
	local planters = plotData.planters
	if typeof(planters) ~= "table" then return end

	for slotStr, p in planters do
		local slot = tonumber(slotStr)
		if not slot then continue end
		if typeof(p) ~= "table" then continue end
		local speciesId = p.species
		local plantedAt = p.plantedAt
		local growSeconds = p.growSeconds
		if typeof(speciesId) ~= "string" then continue end
		if typeof(plantedAt) ~= "number" or typeof(growSeconds) ~= "number" then continue end

		local species = PlantData.get(speciesId)
		if not species then continue end

		local planter = findPlanterForSlot(player, slot)
		if not planter then continue end

		-- Cap effective "now" at lastSeen+24h so AFK whales can't collect 30d offline.
		local effectiveNow = math.min(now, cap)
		local elapsed = math.max(0, effectiveNow - plantedAt)

		if elapsed >= growSeconds then
			-- Offline ripen → harvest straight into stash. Free the planter so
			-- the player can re-plant immediately on rejoin.
			harvestOffline(player, speciesId, species)
			planter:SetAttribute("IsEmpty", true)
			planter:SetAttribute("PlantedSpecies", nil)
			planter:SetAttribute("PlantedAt", nil)
			planter:SetAttribute("GrowSeconds", nil)
		else
			-- Mid-grow → restore attributes + sprout visual at correct progress.
			planter:SetAttribute("IsEmpty", false)
			planter:SetAttribute("PlantedSpecies", speciesId)
			planter:SetAttribute("PlantedAt", plantedAt)
			planter:SetAttribute("GrowSeconds", growSeconds)
			local progress = math.clamp(elapsed / growSeconds, 0, 1)
			buildSproutFor(planter, species, progress)
		end
	end
end

_G.PlantHandler = API
