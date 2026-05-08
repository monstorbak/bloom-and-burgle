--!strict
-- Persistence — DataStore snapshot/restore for critter inventory + plot state.
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). Keeps the
-- `Services.register("PlantHandler", api)` shape for backward compatibility
-- with LeaderstatsScript and any out-of-tree consumers (e.g. dbg toolkit).
--
-- ADR-5 (P1.2) renames `PlantHandler` → `CritterHandler` in the registry —
-- but the DataStore key shape `{ planters = {...}, stash = {...} }` and the
-- `"Planter"` CollectionService tag stay (load-bearing in saves).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local Services = require(ServerScriptService:WaitForChild("Services") :: ModuleScript)
local CritterRegistry = require(script.Parent:WaitForChild("CritterRegistry") :: ModuleScript)
local HarvestFlow = require(script.Parent:WaitForChild("HarvestFlow") :: ModuleScript)

local MAX_OFFLINE_SECONDS = 24 * 60 * 60  -- BAB-002: cap offline grow at 24h

local Persistence = {}

-- Snapshot the per-player plant state for DataStore persistence. Returns
-- a shape compatible with `data.plot` in DataStore.luau's DEFAULT_DATA:
-- `{ planters = { ["slot"] = { species, plantedAt, growSeconds } }, stash = { [key] = count } }`.
function Persistence.snapshot(player: Player): { [string]: any }
	local planters: { [string]: any } = {}
	for _, planter in CollectionService:GetTagged("Planter") do
		if not planter:IsA("BasePart") then continue end
		if planter:GetAttribute("OwnerUserId") ~= player.UserId then continue end
		if planter:GetAttribute("IsEmpty") then continue end
		local slot = CritterRegistry.slotForPlanterName(planter.Name)
		if not slot then continue end
		planters[tostring(slot)] = {
			species = planter:GetAttribute("PlantedSpecies"),
			plantedAt = planter:GetAttribute("PlantedAt"),
			growSeconds = planter:GetAttribute("GrowSeconds"),
		}
	end

	local stash: { [string]: number } = {}
	for key, count in CritterRegistry.getInv(player) do
		if count > 0 then stash[key] = count end
	end

	return { planters = planters, stash = stash }
end

-- Restore plant + stash state after PlotManager has rebuilt the plot.
-- `plot` shape: { planters = { ["slot"] = {species, plantedAt, growSeconds} },
--                 stash = { [key] = count } }
-- `lastSeen` is os.time() of last save; we cap offline elapsed at 24h.
function Persistence.restore(player: Player, plotData: { [string]: any }?, lastSeen: number?)
	if not plotData then return end
	local now = os.time()
	local cap = lastSeen and (lastSeen + MAX_OFFLINE_SECONDS) or now

	-- Stash first (safe regardless of plot existence)
	local stash = plotData.stash
	if typeof(stash) == "table" then
		for key, count in stash do
			if typeof(count) == "number" and count > 0 then
				CritterRegistry.addToInventory(player, key, count)
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

		local species = CritterData.get(speciesId)
		if not species then continue end

		local planter = CritterRegistry.findPlanterForSlot(player, slot)
		if not planter then continue end

		-- Cap effective "now" at lastSeen+24h so AFK whales can't collect 30d offline.
		local effectiveNow = math.min(now, cap)
		local elapsed = math.max(0, effectiveNow - plantedAt)

		if elapsed >= growSeconds then
			-- Offline ripen → harvest straight into stash. Free the planter so
			-- the player can re-plant immediately on rejoin.
			HarvestFlow.harvestOffline(player, speciesId, species)
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
			HarvestFlow.buildSproutFor(planter, species, progress)
		end
	end
end

-- ADR-5 (P1.2): register under both "CritterHandler" (canonical) and
-- "PlantHandler" (legacy alias kept for one release). Same API table is
-- exposed under both names so consumers don't need to migrate atomically.
-- _G.PlantHandler is preserved for the dbg toolkit + any out-of-tree
-- consumer that doesn't go through Services.
local API = { snapshot = Persistence.snapshot, restore = Persistence.restore }
Services.register("CritterHandler", API)
Services.register("PlantHandler", API)
_G.CritterHandler = API
_G.PlantHandler = API

-- Make sure leaving players don't leak inventory state. PlantingFlow.server.luau
-- also clears EconomyPad cooldowns on the same event; we keep this here so the
-- two cleanup paths stay independent (this module owns inventory state).
Players.PlayerRemoving:Connect(function(player)
	CritterRegistry.clearInventoryFor(player)
end)

return Persistence
