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
	rebirths = 0,
	multiplier = 1,
	plotClaimed = false,
	plotPosition = nil,               -- assigned on first claim
	plantsHarvested = 0,
	mutationsFound = 0,
	lastSeen = 0,                     -- os.time() of last save (for offline income)
}

local M = {}

local function key(player: Player): string
	return "player_" .. tostring(player.UserId)
end

function M.loadData(player: Player): { [string]: any }
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			if result == nil then
				-- New player, return defaults
				local data = table.clone(DEFAULT_DATA)
				return data
			end
			-- Backfill any newly added fields with defaults
			for k, v in DEFAULT_DATA do
				if result[k] == nil then
					result[k] = v
				end
			end
			return result
		end
		warn(("[DataStore] load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(result)))
		task.wait(2 ^ attempt)
	end
	warn(("[DataStore] all load attempts failed for %s — using defaults"):format(player.Name))
	return table.clone(DEFAULT_DATA)
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
