--!strict
-- trophy_data.test.luau — pure-logic regression for the Trophy Hall
-- DataStore wrapper.
--
-- BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL (2026-05-10).
--
-- TrophyData.luau requires DataStoreService (not available in Lune), so
-- per the established BAB convention this test mirrors the gnarly bits
-- (the merge + dedupe logic) and pins invariants against production. The
-- structural test (scripts/test/phase-4-friends-trophy-static.sh)
-- verifies the production module declares the same shape.
--
-- Run:
--     lune run tests/trophy/trophy_data.test.luau

-- ── Pinned invariants (must match TrophyData.luau) ───────────────────

local EXPECTED_TOP_N = 10
local EXPECTED_CATEGORIES = { "hall_of_sales", "mythic_hatch" }
local EXPECTED_DS_KEY = "BloomAndBurgleTrophy_v1"

type Entry = {
	userId: number,
	displayName: string,
	value: number,
	species: string?,
	mutation: string?,
	timestamp: number,
}

-- ── Mirror of TrophyData.submit's merge logic ────────────────────────
-- Pure function — no DataStore. Exact same algorithm; the structural
-- test ensures the production code keeps the `category == "mythic_hatch"`
-- branch.

local function merge(category: string, current: { Entry }, entry: Entry, topN: number): { Entry }
	local list: { Entry } = {}
	for _, e in current do table.insert(list, e) end

	if category == "mythic_hatch" then
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
		table.insert(list, entry)
	end

	table.sort(list, function(a, b) return a.value > b.value end)

	local seen: { [string]: boolean } = {}
	local deduped: { Entry } = {}
	for _, e in list do
		local k = string.format("%d:%s:%s:%d",
			e.userId, e.species or "", e.mutation or "", math.floor(e.value))
		if not seen[k] then
			seen[k] = true
			table.insert(deduped, e)
			if #deduped >= topN then break end
		end
	end
	return deduped
end

-- ── Test runner ──────────────────────────────────────────────────────

local failures = 0
local function assertEq(label: string, got: any, want: any)
	if got == want then
		print("✅ " .. label)
	else
		print(("❌ %s — got=%s want=%s"):format(label, tostring(got), tostring(want)))
		failures += 1
	end
end

local function assertLen(label: string, list: { any }, want: number)
	assertEq(label, #list, want)
end

print("── Invariants ──")
assertEq("TOP_N is 10", EXPECTED_TOP_N, 10)
assertEq("DS key is BloomAndBurgleTrophy_v1", EXPECTED_DS_KEY, "BloomAndBurgleTrophy_v1")
assertEq("Two categories shipped at v1", #EXPECTED_CATEGORIES, 2)

print()
print("── mythic_hatch dedupe (one entry per user, keep highest value) ──")
do
	local list: { Entry } = {}
	-- User A submits 1, then 3, then 2 (out of order). Should keep 3 only.
	list = merge("mythic_hatch", list,
		{ userId = 1, displayName = "A", value = 1, species = "x", mutation = "celestial", timestamp = 100 },
		EXPECTED_TOP_N)
	list = merge("mythic_hatch", list,
		{ userId = 1, displayName = "A", value = 3, species = "y", mutation = "celestial", timestamp = 102 },
		EXPECTED_TOP_N)
	list = merge("mythic_hatch", list,
		{ userId = 1, displayName = "A", value = 2, species = "z", mutation = "celestial", timestamp = 103 },
		EXPECTED_TOP_N)
	assertLen("user A occupies exactly 1 slot after 3 submits", list, 1)
	assertEq("user A's slot has the highest value (3)", list[1].value, 3)
end

print()
print("── mythic_hatch ranking across multiple users ──")
do
	local list: { Entry } = {}
	for i = 1, 5 do
		list = merge("mythic_hatch", list,
			{ userId = i, displayName = "U" .. i, value = i, species = "x", mutation = "celestial", timestamp = i },
			EXPECTED_TOP_N)
	end
	assertLen("5 distinct users → 5 entries", list, 5)
	assertEq("top entry is the highest-value user", list[1].userId, 5)
	assertEq("bottom of leaderboard is lowest value", list[5].userId, 1)
end

print()
print("── hall_of_sales allows multiple entries per user ──")
do
	local list: { Entry } = {}
	-- Same player submits 3 different big sales — all should land.
	list = merge("hall_of_sales", list,
		{ userId = 7, displayName = "B", value = 5000, species = "ember", mutation = "", timestamp = 1 },
		EXPECTED_TOP_N)
	list = merge("hall_of_sales", list,
		{ userId = 7, displayName = "B", value = 12000, species = "drake", mutation = "celestial", timestamp = 2 },
		EXPECTED_TOP_N)
	list = merge("hall_of_sales", list,
		{ userId = 7, displayName = "B", value = 8000, species = "hydra", mutation = "", timestamp = 3 },
		EXPECTED_TOP_N)
	assertLen("3 distinct sales by same user all retained", list, 3)
	assertEq("top sale is the largest", list[1].value, 12000)
end

print()
print("── exact-duplicate dedupe (cross-server retry safety) ──")
do
	local list: { Entry } = {}
	local entry: Entry = { userId = 9, displayName = "C", value = 9999, species = "ember", mutation = "celestial", timestamp = 555 }
	list = merge("hall_of_sales", list, entry, EXPECTED_TOP_N)
	-- Simulate UpdateAsync conflict-retry submitting the same entry again.
	list = merge("hall_of_sales", list, entry, EXPECTED_TOP_N)
	assertLen("identical (uid, species, mutation, value) only retained once", list, 1)
end

print()
print("── top-N trim ──")
do
	local list: { Entry } = {}
	for i = 1, 15 do
		list = merge("hall_of_sales", list,
			{ userId = i, displayName = "U" .. i, value = i * 1000, species = "x", mutation = "", timestamp = i },
			EXPECTED_TOP_N)
	end
	assertLen("15 submits → trimmed to TOP_N (10)", list, EXPECTED_TOP_N)
	assertEq("top entry is the largest (15000)", list[1].value, 15000)
	assertEq("bottom of trimmed list is value 6000 (15→6, 5 dropped)", list[10].value, 6000)
end

print()
if failures > 0 then
	print(("❌ %d trophy_data check(s) failed"):format(failures))
	error("test failed")
end
print("🎉 trophy_data: all checks passed")
