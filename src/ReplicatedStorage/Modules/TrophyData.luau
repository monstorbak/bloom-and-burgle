--!strict
-- TrophyData — DataStore wrapper for the Trophy Hall leaderboards.
--
-- BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL (2026-05-10).
--
-- ── Categories shipped at v1 ──────────────────────────────────────────
-- Phase 4.A ships 2 leaderboards (the most-used). The other 2 from the
-- ticket (Plot Champions, Class Loyalty) are deferred to a follow-up
-- once we see if the format works:
--
--   "hall_of_sales" — top 10 single-transaction sells (any merchant).
--                     Updated on every notable sell server-side.
--   "mythic_hatch"   — top 10 lifetime Mythic hatches per player.
--                     Updated on every celestial mutation roll.
--
-- ── Storage shape ────────────────────────────────────────────────────
-- Single DataStore key `BloomAndBurgleTrophy_v1` holds:
--   { [category] = { entry, entry, ... } }
-- where entry = { displayName, value, species?, mutation?, timestamp }
--
-- Top-N maintained server-side via UpdateAsync. Reads are GetAsync.
--
-- ── Concurrency ──────────────────────────────────────────────────────
-- Cross-server writes use UpdateAsync with the standard merge pattern:
--     newList = sort(currentList + newEntry)[1..N]
-- This handles concurrent writes from multiple servers without lost
-- updates (one of them retries via Roblox's UpdateAsync conflict logic).

local DataStoreService = game:GetService("DataStoreService")

local M = {}

local DS_KEY = "BloomAndBurgleTrophy_v1"
local TOP_N = 10

-- Deferred-init so this module loads cleanly in environments without
-- DataStore access (Studio without API services, Lune tests, etc.).
local _store: DataStore? = nil
local function store(): DataStore?
	if _store then return _store end
	local ok, ds = pcall(function() return DataStoreService:GetDataStore(DS_KEY) end)
	if ok and ds then _store = ds end
	return _store
end

export type Entry = {
	userId: number,
	displayName: string,
	value: number,           -- the leaderboard sort key (cash, count, etc)
	species: string?,        -- relevant for hall_of_sales (which species)
	mutation: string?,       -- mutation id ("celestial", etc)
	timestamp: number,       -- os.time() when this entry was created
}

export type Snapshot = {
	hall_of_sales: { Entry },
	mythic_hatch: { Entry },
}

local CATEGORIES = { "hall_of_sales", "mythic_hatch" }

-- ── Read API ─────────────────────────────────────────────────────────

local function emptySnapshot(): Snapshot
	return {
		hall_of_sales = {},
		mythic_hatch = {},
	}
end

-- Returns the full snapshot. Returns empty snapshot if DataStore unavailable.
function M.read(): Snapshot
	local ds = store()
	if not ds then return emptySnapshot() end
	local ok, data = pcall(function() return ds:GetAsync("trophies") end)
	if not ok or typeof(data) ~= "table" then return emptySnapshot() end
	-- Defensive: ensure both categories exist + are arrays.
	for _, cat in CATEGORIES do
		if typeof(data[cat]) ~= "table" then data[cat] = {} end
	end
	return data :: any
end

-- ── Write API ────────────────────────────────────────────────────────

-- Insert a new entry into a category, then trim to top N. Idempotent
-- across concurrent calls thanks to UpdateAsync's retry semantics.
-- Returns true on success, false if DataStore is unavailable.
function M.submit(category: string, entry: Entry): boolean
	if entry.value <= 0 then return false end
	local ds = store()
	if not ds then return false end

	-- Dedupe strategy is per-category:
	--
	-- mythic_hatch ─ "highest lifetime mythic count per player". One slot
	--   per userId; a resubmit with a higher value REPLACES the prior
	--   entry. Without this, a player who hits 1, 2, 3, 4 mythics in one
	--   session would occupy 4 of the top 10 slots.
	--
	-- hall_of_sales ─ "biggest single sells, any player". Same player can
	--   appear multiple times if they have multiple monster sales — that's
	--   the point of the board (it's a hall of feats, not of players).
	--   Dedupe still drops exact duplicates from cross-server retries.
	local ok = pcall(function()
		ds:UpdateAsync("trophies", function(current)
			current = (typeof(current) == "table") and current or {}
			for _, cat in CATEGORIES do
				if typeof(current[cat]) ~= "table" then current[cat] = {} end
			end
			local list: { Entry } = current[category] or {}

			if category == "mythic_hatch" then
				-- One-entry-per-user merge: if this user already exists in
				-- the list, replace iff new value is higher; else insert.
				local replaced = false
				for i, e in list do
					if e.userId == entry.userId then
						if entry.value > e.value then
							list[i] = entry
						end
						replaced = true
						break
					end
				end
				if not replaced then table.insert(list, entry) end
			else
				-- hall_of_sales (and any future per-feat category): just
				-- insert; let the dedupe step below drop exact duplicates.
				table.insert(list, entry)
			end

			table.sort(list, function(a, b) return a.value > b.value end)

			-- Drop exact duplicates from cross-server UpdateAsync retries.
			-- Key includes value so legitimately repeated big sells from
			-- the same player still get separate slots in hall_of_sales.
			local seen: { [string]: boolean } = {}
			local deduped: { Entry } = {}
			for _, e in list do
				local k = string.format("%d:%s:%s:%d",
					e.userId, e.species or "", e.mutation or "", math.floor(e.value))
				if not seen[k] then
					seen[k] = true
					table.insert(deduped, e)
					if #deduped >= TOP_N then break end
				end
			end
			current[category] = deduped
			return current
		end)
	end)
	return ok
end

function M.categories(): { string }
	return { unpack(CATEGORIES) }
end

function M.topN(): number
	return TOP_N
end

return M
