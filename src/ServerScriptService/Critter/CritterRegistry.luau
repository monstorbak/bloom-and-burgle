--!strict
-- CritterRegistry — module-local inventory state, slot resolution, and
-- pure helpers shared across the Critter/* modules.
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). Holds:
--   - inventory[userId][speciesId..":"..mutationId] = count
--   - findPlanterForSlot(player, slot) → BasePart? — used by Persistence
--   - clearInventoryFor(player) — called from Players.PlayerRemoving
--
-- Why a Module: the legacy PlantHandler.server.luau couldn't be require'd
-- (it was a Script). The ADR-4 split makes state a regular ModuleScript so
-- HarvestFlow / EconomyPad / Persistence can share it via require().
--
-- Naming note: filename is "CritterRegistry" per ADR-4 even though the
-- DataStore key (`stash`, `planters`) and CollectionService tag ("Planter")
-- still use the legacy "Plant" terminology — those are load-bearing in
-- saves, see ADR-5 (P1.2) for details.

local CollectionService = game:GetService("CollectionService")

local CritterRegistry = {}

-- Per-user inventory of held critters, keyed by `speciesId .. ":" .. mutationId`.
-- The empty mutation slug is `""` (e.g. "sunbloom:" for a plain sunbloom).
local inventory: { [number]: { [string]: number } } = {}

-- Get-or-create the inventory bag for a player. Always returns a fresh
-- table on first call so harvest paths can safely += into it.
function CritterRegistry.getInv(player: Player): { [string]: number }
	local uid = player.UserId
	if not inventory[uid] then
		inventory[uid] = {}
	end
	return inventory[uid]
end

-- Drop a player's inventory bag entirely. Called from Players.PlayerRemoving
-- so we don't leak per-player state across sessions.
function CritterRegistry.clearInventoryFor(player: Player)
	inventory[player.UserId] = nil
end

-- Resolve a planter Part for a given owner + slot index (1..9, 3x3 grid order).
-- Slot mapping matches PlotManager: slot N corresponds to Planter_(x+2)_(z+2)
-- where x,z ∈ {-1,0,1}. We iterate the tagged set since it's small (≤9 per
-- player) and avoids hard-coding plot model paths.
function CritterRegistry.findPlanterForSlot(player: Player, slot: number): BasePart?
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

-- Decode a planter's `Planter_X_Z` name into a 1..9 slot index, or nil if
-- the name doesn't match the format. Used by Persistence.snapshot.
function CritterRegistry.slotForPlanterName(name: string): number?
	local sx, sz = string.match(name, "Planter_(%d+)_(%d+)")
	if not (sx and sz) then return nil end
	local sxn, szn = tonumber(sx), tonumber(sz)
	if not (sxn and szn) then return nil end
	return (szn - 1) * 3 + sxn
end

-- Add `count` of one critter key to a player's inventory. Returns the new
-- count. Used by HarvestFlow.harvestPlanter and Persistence.harvestOffline.
function CritterRegistry.addToInventory(player: Player, key: string, count: number): number
	local inv = CritterRegistry.getInv(player)
	inv[key] = (inv[key] or 0) + count
	return inv[key]
end

return CritterRegistry
