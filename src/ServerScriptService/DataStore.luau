--!strict
-- DataStore: Wrapper around DataStoreService with retry logic.
-- ModuleScript (must be `.luau` NOT `.server.luau` — Rojo treats `.server.luau`
-- as a Script which can't be require()'d).

local DataStoreService = game:GetService("DataStoreService")

local DATA_STORE_NAME = "BloomAndBurgleData_v1"
local MAX_RETRIES = 3

local store = DataStoreService:GetDataStore(DATA_STORE_NAME)

local DEFAULT_DATA = {
	cash = 100,                       -- starter cash so player can buy first seed
	cogParts = 0,                     -- BAB-STEAMPUNK: secondary currency from SCRAP, used for upgrades
	rebirths = 0,
	multiplier = 1,
	plotClaimed = false,
	plotPosition = nil,               -- assigned on first claim
	plotSlotIndex = nil,              -- which slot (1..NUM_PLOT_SLOTS) the player owns
	plantsHarvested = 0,
	mutationsFound = 0,
	lastSeen = 0,                     -- os.time() of last save (for offline income)
	lifetimeCash = 0,                 -- progressive shop unlock budget
	starterPackGranted = false,       -- one-shot free-seed starter (BAB-002)
	-- BAB-STEAMPUNK: class identity. nil → first-run forces ClassPickerUI.
	-- One of: "knight", "alchemist", "skyPirate", "tinkerer", "hexer".
	class = nil,
	-- BAB-STEAMPUNK: stable of nurtured critters. Each entry is the persistent
	-- record of a critter the player chose to NURTURE at harvest time.
	-- { id = "uuid", species = "mech_hound", mutation = "", name = "Cogsworth",
	--   hp = 100, slots = {armor=nil, power=nil, speed=nil, special=nil},
	--   bondedAt = os.time(), feralAt = nil }
	stable = {},
	stableCapacity = 6,               -- expandable via gamepass / cog parts
	-- BAB-002: per-incubator-pod grow state + hatched-but-undecided inventory.
	-- planters key = pod slot index 1..9 (3x3 grid order). String keys because
	-- DataStore JSON arrays drop nil holes.
	plot = {
		planters = {},                -- { ["5"] = { species = "mech_hound", plantedAt = 1000, growSeconds = 30 } }
		stash = {},                   -- { ["mech_hound:"] = 3, ["coal_drake:ember"] = 1 }
	},
}

-- Deep-merge defaults into a loaded blob so newly added nested fields
-- (like `plot.planters`) backfill correctly without nuking the player's data.
local function backfill(target: { [string]: any }, source: { [string]: any })
	for k, v in source do
		if target[k] == nil then
			if typeof(v) == "table" then
				target[k] = table.clone(v)
			else
				target[k] = v
			end
		elseif typeof(v) == "table" and typeof(target[k]) == "table" then
			backfill(target[k], v)
		end
	end
end

local M = {}

local function key(player: Player): string
	return "player_" .. tostring(player.UserId)
end

local function freshDefaults(): { [string]: any }
	-- table.clone is shallow; build a deep copy so callers can mutate without
	-- aliasing the module-level DEFAULT_DATA tables.
	local d = table.clone(DEFAULT_DATA)
	d.plot = { planters = {}, stash = {} }
	d.stable = {}
	return d
end

function M.loadData(player: Player): { [string]: any }
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			if result == nil then
				-- New player, return defaults
				return freshDefaults()
			end
			-- Backfill any newly added fields (deep) so old saves get nested
			-- defaults like `plot.planters = {}` instead of nil-blasting on access.
			backfill(result, DEFAULT_DATA)
			return result
		end
		warn(("[DataStore] load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(result)))
		task.wait(2 ^ attempt)
	end
	warn(("[DataStore] all load attempts failed for %s — using defaults"):format(player.Name))
	return freshDefaults()
end

function M.saveData(player: Player, data: { [string]: any }): boolean
	data.lastSeen = os.time()
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			store:SetAsync(key(player), data)
		end)
		if ok then
			return true
		end
		warn(("[DataStore] save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
		task.wait(2 ^ attempt)
	end
	warn(("[DataStore] all save attempts failed for %s"):format(player.Name))
	return false
end

return M
