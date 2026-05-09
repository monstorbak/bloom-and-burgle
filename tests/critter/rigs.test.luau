--!strict
-- rigs.test.luau — pure-logic regression test for CritterRigs.luau
--
-- BAB-PHASE-1-CRITTER-RIGS (2026-05-09).
--
-- Mirrors `CritterRigs.formForProgress` per the established BAB convention
-- (see tests/critter/economy_logic.test.luau and tests/marketplace/pricing.test.luau).
-- Production code lives at src/ReplicatedStorage/Modules/CritterRigs.luau and
-- requires Roblox runtime APIs we can't import from Lune. The structural
-- test (scripts/test/critter-rigs-static.sh) verifies the mirror's
-- pinned thresholds match prod.
--
-- Run:
--     lune run tests/critter/rigs.test.luau

-- ── Pinned constants (must match production) ──────────────────────────
local HATCH_CUTE_END = 0.25
local JUVENILE_END = 0.75

-- ── Mirror: formForProgress ──────────────────────────────────────────
local function formForProgress(progress: number): string
	if progress >= JUVENILE_END then return "adult" end
	if progress >= HATCH_CUTE_END then return "juvenile" end
	return "hatchCute"
end

-- ── Test runner ──────────────────────────────────────────────────────
local failures = 0
local passes = 0
local function check(name: string, condition: boolean, msg: string?)
	if condition then
		passes += 1
		print("  ✅ " .. name)
	else
		failures += 1
		print("  ❌ " .. name .. (msg and (" — " .. msg) or ""))
	end
end

print("── formForProgress: 3 forms ──")
do
	check("0.0 → hatchCute", formForProgress(0.0) == "hatchCute")
	check("0.1 → hatchCute", formForProgress(0.1) == "hatchCute")
	check("0.249 → hatchCute", formForProgress(0.249) == "hatchCute")
	check("0.25 → juvenile (boundary lo)", formForProgress(0.25) == "juvenile")
	check("0.5 → juvenile", formForProgress(0.5) == "juvenile")
	check("0.749 → juvenile", formForProgress(0.749) == "juvenile")
	check("0.75 → adult (boundary lo)", formForProgress(0.75) == "adult")
	check("1.0 → adult", formForProgress(1.0) == "adult")
	check("1.5 → adult (clamp upper)", formForProgress(1.5) == "adult")
end

print("── formForProgress: monotonicity ──")
do
	-- Form sequence as progress goes 0 → 1 should be hatchCute → juvenile → adult,
	-- never going backwards.
	local prev = "hatchCute"
	local order = { hatchCute = 1, juvenile = 2, adult = 3 }
	for i = 0, 100 do
		local p = i / 100
		local cur = formForProgress(p)
		check(string.format("p=%.2f form is non-decreasing", p),
			order[cur] >= order[prev],
			"prev=" .. prev .. " cur=" .. cur)
		prev = cur
	end
end

print("── formForProgress: form coverage ──")
do
	-- All 3 forms must be reachable in [0, 1].
	local seen = { hatchCute = false, juvenile = false, adult = false }
	for i = 0, 100 do
		local p = i / 100
		seen[formForProgress(p)] = true
	end
	check("hatchCute reachable", seen.hatchCute)
	check("juvenile reachable", seen.juvenile)
	check("adult reachable", seen.adult)
end

-- ── Tally ────────────────────────────────────────────────────────────
print("")
print(string.format("Results: %d passed, %d failed", passes, failures))
if failures > 0 then
	error(string.format("%d test(s) failed", failures), 0)
end
