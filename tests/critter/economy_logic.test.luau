--!strict
-- economy_logic.test.luau — pure-logic regression test for EconomyPad math.
--
-- Why this exists: EconomyPad.luau lives inside the Roblox runtime (uses
-- game:GetService, RemoteEvents, Player:GetAttribute), so it can't be
-- require'd from Lune directly. The MATH inside EconomyPad — value-of
-- functions, clamp logic, Sacred-skip rule — is pure Luau though, and
-- any bug there is a money bug. So we re-implement that math here and
-- assert representative outputs.
--
-- ⚠️  When EconomyPad.luau changes, update this file in lockstep.
--    The structural test (scripts/test/critter-static.sh) checks that the
--    constants and rule names match what's in EconomyPad.
--
-- Run:
--     lune run tests/critter/economy_logic.test.luau
--
-- Mirrors src/ServerScriptService/Critter/EconomyPad.luau:
--   - sellValueOf  (lines ~80–88)
--   - scrapValueOf (lines ~92–94)
--   - applyRule's clamp + Sacred-skip + cashMult floor (lines ~135–195)

-- ── Mirror: sellValueOf ────────────────────────────────────────────────────
-- Production: count * baseValue * (mutation multiplier or 1)
local function sellValueOf(species, mutationId, count, mutationsTable)
	local mult = 1
	if mutationId ~= "" then
		for _, m in mutationsTable do
			if m.id == mutationId then
				mult = m.multiplier
				break
			end
		end
	end
	return count * species.baseValue * mult
end

-- ── Mirror: scrapValueOf ───────────────────────────────────────────────────
-- Production: count * scrapValue (no mutation modifier)
local function scrapValueOf(species, _mutationId, count)
	return count * species.scrapValue
end

-- ── Mirror: clampPayout ────────────────────────────────────────────────────
-- Production: if total > maxPayout, returns (maxPayout, true) and the
-- caller logs a violation. Otherwise (total, false).
local function clampPayout(total, maxPayout)
	if total > maxPayout then return maxPayout, true end
	return total, false
end

-- ── Mirror: applyCashMultFloor ─────────────────────────────────────────────
-- Production (sell only): math.floor(total * cashMult)
local function applyCashMultFloor(total, cashMult)
	return math.floor(total * cashMult)
end

-- ── Test fixtures ──────────────────────────────────────────────────────────

local SPECIES_SUNBLOOM = {
	id = "sunbloom",
	baseValue = 10,
	scrapValue = 2,
	rarity = "Common",
	tag = nil,
}
local SPECIES_COAL_DRAKE = {
	id = "coal_drake",
	baseValue = 100000,
	scrapValue = 500,
	rarity = "Mythic",
	tag = nil,
}
local SPECIES_SACRED = {
	id = "celestial",
	baseValue = 50000,
	scrapValue = 1000,
	rarity = "Mythic",
	tag = "Sacred",
}

local MUTATIONS = {
	{ id = "celestial", multiplier = 100 },
	{ id = "shiny",     multiplier = 5 },
}

-- Match the production EconomyPad constants exactly. The structural test
-- pins these to the values in EconomyPad.luau.
local MAX_SELL_PAYOUT  = 5000000
local MAX_SCRAP_PAYOUT = 100000

-- ── Tiny test runner ───────────────────────────────────────────────────────

local failures = 0
local function check(name, ok, msg)
	if ok then
		print("  ✅ " .. name)
	else
		failures += 1
		print("  ❌ " .. name .. ": " .. tostring(msg))
	end
end

local function assertEq(name, expected, actual)
	check(name, expected == actual, string.format("expected=%s actual=%s", tostring(expected), tostring(actual)))
end

-- ── Cases ──────────────────────────────────────────────────────────────────

print("── sellValueOf ──")
assertEq("plain sunbloom × 1 → baseValue 10", 10,
	sellValueOf(SPECIES_SUNBLOOM, "", 1, MUTATIONS))
assertEq("sunbloom × 5 → 50", 50,
	sellValueOf(SPECIES_SUNBLOOM, "", 5, MUTATIONS))
assertEq("shiny sunbloom × 1 → 10*5=50", 50,
	sellValueOf(SPECIES_SUNBLOOM, "shiny", 1, MUTATIONS))
assertEq("celestial coal_drake × 1 → 100000*100=10M (> sell cap, but the function returns raw)",
	10000000,
	sellValueOf(SPECIES_COAL_DRAKE, "celestial", 1, MUTATIONS))
assertEq("unknown mutation → multiplier 1 (defaults gracefully)", 100000,
	sellValueOf(SPECIES_COAL_DRAKE, "no_such_mutation", 1, MUTATIONS))

print()
print("── scrapValueOf ──")
assertEq("plain sunbloom × 1 → scrapValue 2", 2,
	scrapValueOf(SPECIES_SUNBLOOM, "", 1))
assertEq("sunbloom × 9 → 18", 18,
	scrapValueOf(SPECIES_SUNBLOOM, "", 9))
assertEq("scrap ignores mutation entirely", 2,
	scrapValueOf(SPECIES_SUNBLOOM, "celestial", 1))

print()
print("── clampPayout (sell cap = 5M) ──")
do
	local clamped, was = clampPayout(1000000, MAX_SELL_PAYOUT)
	assertEq("under cap stays unchanged", 1000000, clamped)
	check("under cap → was=false", was == false, was)
end
do
	local clamped, was = clampPayout(MAX_SELL_PAYOUT, MAX_SELL_PAYOUT)
	assertEq("at cap stays unchanged", MAX_SELL_PAYOUT, clamped)
	check("at cap → was=false", was == false, was)
end
do
	local clamped, was = clampPayout(MAX_SELL_PAYOUT + 1, MAX_SELL_PAYOUT)
	assertEq("over cap clamps to MAX_SELL_PAYOUT", MAX_SELL_PAYOUT, clamped)
	check("over cap → was=true (caller logs violation)", was == true, was)
end
do
	local clamped, was = clampPayout(10000000, MAX_SELL_PAYOUT)
	assertEq("celestial coal_drake (10M) clamps to 5M", MAX_SELL_PAYOUT, clamped)
	check("celestial coal_drake → was=true", was == true, was)
end

print()
print("── clampPayout (scrap cap = 100K) ──")
do
	local clamped, was = clampPayout(50000, MAX_SCRAP_PAYOUT)
	assertEq("under cap stays unchanged", 50000, clamped)
end
do
	local clamped, was = clampPayout(150000, MAX_SCRAP_PAYOUT)
	assertEq("over cap clamps to MAX_SCRAP_PAYOUT", MAX_SCRAP_PAYOUT, clamped)
	check("over → was=true", was == true, was)
end

print()
print("── applyCashMultFloor (gamepass 2x) ──")
assertEq("multiplier 1 leaves total unchanged", 1234,
	applyCashMultFloor(1234, 1))
assertEq("multiplier 2 doubles", 2468,
	applyCashMultFloor(1234, 2))
assertEq("multiplier 1.5 → floor(1851)", 1851,
	applyCashMultFloor(1234, 1.5))
assertEq("multiplier 1.5 truncates fractional cents", 18,
	applyCashMultFloor(12, 1.5))   -- 18.0 → 18

print()
print("── Sacred-skip rule (scrap-only) ──")
-- This isn't a function in production — it's an inline `if rule.skipSacred and species.tag == "Sacred"` —
-- but we mirror the same boolean logic so the rule's behavior is testable.
local function shouldSkip(rule, species)
	return rule.skipSacred and species.tag == "Sacred"
end
local SCRAP_RULE = { skipSacred = true }
local SELL_RULE  = { skipSacred = false }
check("scrap skips Sacred",          shouldSkip(SCRAP_RULE, SPECIES_SACRED) == true,  "should skip")
check("scrap keeps non-Sacred",      shouldSkip(SCRAP_RULE, SPECIES_SUNBLOOM) == false, "should not skip")
check("sell does NOT skip Sacred",   shouldSkip(SELL_RULE,  SPECIES_SACRED) == false, "should not skip")

print()
if failures > 0 then
	print(string.format("❌ %d failure(s)", failures))
	error("test failed", 0)
end
print("🎉 economy_logic: all cases passed")
