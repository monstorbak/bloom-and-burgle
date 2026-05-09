--!strict
-- pricing.test.luau — pure-logic regression test for MerchantPricing math.
--
-- BAB-MARKETPLACE-NPC-ROTATION (2026-05-08).
--
-- ── Why mirror, not require? ─────────────────────────────────────────
-- MerchantPricing.luau requires `CritterData` via `script.Parent:WaitForChild`,
-- which is a Roblox runtime API that Lune doesn't provide. Per the
-- established convention in tests/critter/economy_logic.test.luau, we
-- mirror the math here and pin constants. The structural test
-- (scripts/test/marketplace-static.sh) verifies the mirror's pinned
-- constants match prod.
--
-- ⚠️  When MerchantPricing.luau changes (formula constants, cap,
--     personality shape), update this file in lockstep. The structural
--     test will catch silent divergence.
--
-- Run:
--     lune run tests/marketplace/pricing.test.luau

-- ── Pinned constants (must match production) ──────────────────────────
-- MerchantPricing.MULTIPLIER_CAP — pinned in scripts/test/marketplace-static.sh
local MULTIPLIER_CAP = 3.0

-- ── Mirror: mutationMultiplier ───────────────────────────────────────
local MUTATIONS = {
	{ id = "polished",  multiplier = 2.0 },
	{ id = "gilded",    multiplier = 5.0 },
	{ id = "aether",    multiplier = 12.0 },
	{ id = "ember",     multiplier = 30.0 },
	{ id = "celestial", multiplier = 100.0 },
}

local function mutationMultiplier(mutationId: string): number
	if mutationId == "" then return 1 end
	for _, m in MUTATIONS do
		if m.id == mutationId then return m.multiplier end
	end
	return 1
end

-- ── Mirror: speciesInPreference ──────────────────────────────────────
local function inSet(needle: string?, haystack: { string }): boolean
	if not needle then return false end
	for _, v in haystack do
		if v == needle then return true end
	end
	return false
end

local function speciesInPreference(personality, species): boolean
	if inSet(species.hatchArchetype, personality.preferredHatchArchetypes) then return true end
	if inSet(species.archetype, personality.preferredVisualArchetypes) then return true end
	if species.tag and inSet(species.tag, personality.preferredTags) then return true end
	return false
end

-- ── Mirror: priceLine ─────────────────────────────────────────────────
local function priceLine(p, s, mutId, count, playerAffinity, isSpecial)
	if s.tag == "Contraband" then return 0, 0, false end
	local mut = mutationMultiplier(mutId)
	local basePayout = count * s.baseValue * mut
	local inPref = speciesInPreference(p, s)
	local prefFit = inPref and 1.0 or p.nonPreferenceMultiplier
	local arbitrageBonus = 0
	if (p.arbitrageProfile == "asset" and playerAffinity == "asset")
		or (p.arbitrageProfile == "liability" and playerAffinity == "liability")
	then
		arbitrageBonus = p.arbitrageBonus
	end
	local specialBonus = isSpecial and 1.0 or 0
	local rawMultiplier = p.basePremium * prefFit * (1 + arbitrageBonus + specialBonus)
	local wasCapped = rawMultiplier > MULTIPLIER_CAP
	local multiplier = wasCapped and MULTIPLIER_CAP or rawMultiplier
	return basePayout * multiplier, multiplier, wasCapped
end

-- ── Mirror: NPCRotation seed function ────────────────────────────────
local function rotationPick(npcId: string, pool: { string }, utcYday: number): string?
	if #pool == 0 then return nil end
	local first = string.byte(npcId, 1) or 0
	local seed = (utcYday * 2654435761 + first * 7919) % #pool + 1
	return pool[seed]
end

-- ── Test fixtures ────────────────────────────────────────────────────

local BART = {
	id = "bart",
	basePremium = 1.2,
	nonPreferenceMultiplier = 1.0,
	arbitrageProfile = "liability",
	arbitrageBonus = 0.2,
	preferredHatchArchetypes = { "cogworkPet", "predator" },
	preferredTags = {},
	preferredVisualArchetypes = {},
	specialRotationPool = { "mech_hound", "cogwork_rat", "iron_hydra" },
}

local HEXERINE = {
	id = "hexerine",
	basePremium = 1.0,
	nonPreferenceMultiplier = 1.0,
	arbitrageProfile = "asset",
	arbitrageBonus = 0.3,
	preferredHatchArchetypes = { "magicalFamiliar", "magicalCritter" },
	preferredTags = { "Sacred" },
	preferredVisualArchetypes = {},
	specialRotationPool = { "patina_toad", "ember_imp" },
}

local VERDA = {
	id = "verda",
	basePremium = 1.3,
	nonPreferenceMultiplier = 0.8,
	arbitrageProfile = "liability",
	arbitrageBonus = 0.4,
	preferredHatchArchetypes = { "skyMount" },
	preferredTags = {},
	preferredVisualArchetypes = { "winged" },
	specialRotationPool = { "sky_wyvern", "coal_drake" },
}

local SPECIES = {
	mech_hound = {
		id = "mech_hound", baseValue = 40, archetype = "quad",
		hatchArchetype = "cogworkPet", tag = nil,
	},
	cogwork_rat = {
		id = "cogwork_rat", baseValue = 20, archetype = "bug",
		hatchArchetype = "cogworkPet", tag = nil,
	},
	coal_drake = {
		id = "coal_drake", baseValue = 300, archetype = "winged",
		hatchArchetype = "predator", tag = nil,
	},
	patina_toad = {
		id = "patina_toad", baseValue = 70, archetype = "bug",
		hatchArchetype = "magicalCritter", tag = "Sacred",
	},
	ember_imp = {
		id = "ember_imp", baseValue = 100, archetype = "winged",
		hatchArchetype = "magicalCritter", tag = "Contraband",
	},
	sky_wyvern = {
		id = "sky_wyvern", baseValue = 120, archetype = "winged",
		hatchArchetype = "skyMount", tag = nil,
	},
	steam_stallion = {
		id = "steam_stallion", baseValue = 90, archetype = "quad",
		hatchArchetype = "mount", tag = nil,
	},
}

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

local function approxEq(a: number, b: number): boolean
	return math.abs(a - b) < 0.001
end

print("── priceLine: Bart ──")
do
	-- Knight (liability for coal_drake) sells coal_drake to Bart, no special.
	-- Expected: 1.2 × 1.0 × (1 + 0.2 + 0) = 1.44×; basePayout 1*300*1=300; total 432.
	local payout, mult, capped = priceLine(BART, SPECIES.coal_drake, "", 1, "liability", false)
	check("knight×coal_drake×bart×nospecial: multiplier 1.44", approxEq(mult, 1.44))
	check("knight×coal_drake×bart×nospecial: payout 432", approxEq(payout, 432))
	check("knight×coal_drake×bart×nospecial: not capped", not capped)
end
do
	-- Hexer (asset for coal_drake — actually neutral; let's say neutral).
	-- coal_drake hatchArchetype=predator (in Bart's prefs), no liability fire,
	-- no special. Expected: 1.2 × 1.0 × (1 + 0 + 0) = 1.2×; 1*300*1*1.2 = 360.
	local payout, mult, _ = priceLine(BART, SPECIES.coal_drake, "", 1, "neutral", false)
	check("neutral×coal_drake×bart: multiplier 1.2", approxEq(mult, 1.2))
	check("neutral×coal_drake×bart: payout 360", approxEq(payout, 360))
end
do
	-- Knight sells cogwork_rat to Bart, today's special: rat. Liability for
	-- knight? No — affinity for cogwork_rat × knight = neutral. So no
	-- liability arbitrage. Multiplier: 1.2 × 1.0 × (1 + 0 + 1.0) = 2.4×.
	-- basePayout 5 × 20 × 1 = 100; total 240.
	local payout, mult, _ = priceLine(BART, SPECIES.cogwork_rat, "", 5, "neutral", true)
	check("rat×bart×special: multiplier 2.4", approxEq(mult, 2.4))
	check("rat×bart×special: payout 240", approxEq(payout, 240))
end

print("── priceLine: Verda + cap ──")
do
	-- Knight sells coal_drake to Verda, today's special: coal_drake.
	-- Verda prefers winged (coal_drake.archetype=winged ✓), liability for knight.
	-- Raw: 1.3 × 1.0 × (1 + 0.4 + 1.0) = 3.12 → capped at 3.0.
	local payout, mult, capped = priceLine(VERDA, SPECIES.coal_drake, "", 1, "liability", true)
	check("knight×coal_drake×verda×special: capped at 3.0", approxEq(mult, 3.0))
	check("knight×coal_drake×verda×special: payout 900 (300×3.0)", approxEq(payout, 900))
	check("knight×coal_drake×verda×special: capped flag set", capped)
end
do
	-- Knight sells steam_stallion (quad, NOT winged) to Verda, no special.
	-- Off-pref: prefFit = 0.8. Liability for knight (steam_stallion: skyPirate=L, knight=A).
	-- Wait — affinity is per the test fixture playerAffinity arg. Use "asset" for knight.
	-- Verda's arbitrage is "liability" — only fires on liability. Asset gives 0.
	-- 1.3 × 0.8 × (1 + 0 + 0) = 1.04×; 1*90*1*1.04 = 93.6.
	local payout, mult, _ = priceLine(VERDA, SPECIES.steam_stallion, "", 1, "asset", false)
	check("stallion×verda×asset: scoff multiplier 1.04", approxEq(mult, 1.04))
	check("stallion×verda×asset: payout 93.6", approxEq(payout, 93.6))
end

print("── priceLine: Hexerine + Sacred + asset arbitrage ──")
do
	-- Hexer sells patina_toad (Sacred, magicalCritter) to Hexerine, no special.
	-- Sacred ∈ Hexerine.preferredTags ✓. Hexer-affinity for toad = asset.
	-- Hexerine arbitrage = asset → fires.
	-- 1.0 × 1.0 × (1 + 0.3 + 0) = 1.3×; 1*70*1*1.3 = 91.
	local payout, mult, _ = priceLine(HEXERINE, SPECIES.patina_toad, "", 1, "asset", false)
	check("hexer×patina×hexerine: multiplier 1.3", approxEq(mult, 1.3))
	check("hexer×patina×hexerine: payout 91", approxEq(payout, 91))
end

print("── priceLine: Contraband refused ──")
do
	-- Anyone sells ember_imp (Contraband) to anyone — payout 0.
	local payout, _, _ = priceLine(BART, SPECIES.ember_imp, "", 5, "asset", true)
	check("ember_imp×bart: contraband refused, payout 0", payout == 0)
	local p2, _, _ = priceLine(HEXERINE, SPECIES.ember_imp, "", 5, "asset", true)
	check("ember_imp×hexerine: contraband refused, payout 0", p2 == 0)
end

print("── priceLine: mutations multiply base ──")
do
	-- Knight sells 2 polished coal_drakes (×2 mutation) to Bart, no special.
	-- basePayout = 2 × 300 × 2.0 = 1200; multiplier 1.44; total 1728.
	local payout, mult, _ = priceLine(BART, SPECIES.coal_drake, "polished", 2, "liability", false)
	check("polished coal_drake×2×bart: multiplier 1.44", approxEq(mult, 1.44))
	check("polished coal_drake×2×bart: payout 1728", approxEq(payout, 1728))
end
do
	-- Knight sells 1 ember-mutated coal_drake (×30) to Verda, special.
	-- basePayout = 30 × 300 = 9000; multiplier capped at 3.0; total 27000.
	local payout, mult, capped = priceLine(VERDA, SPECIES.coal_drake, "ember", 1, "liability", true)
	check("ember coal_drake×verda×special: capped at 3.0", approxEq(mult, 3.0))
	check("ember coal_drake×verda×special: payout 27000", approxEq(payout, 27000))
	check("ember coal_drake×verda×special: capped flag set", capped)
end

print("── priceLine: nonPreferenceMultiplier == 1.0 means no scoff ──")
do
	-- Bart's nonPreferenceMultiplier is 1.0 — selling a steam_stallion (mount,
	-- not in Bart's pref) should still pay base 1.2× with no penalty.
	-- 1.2 × 1.0 × (1 + 0 + 0) = 1.2×; 1*90*1.2 = 108.
	local payout, mult, _ = priceLine(BART, SPECIES.steam_stallion, "", 1, "asset", false)
	check("stallion×bart×nonpref: no scoff, mult 1.2", approxEq(mult, 1.2))
	check("stallion×bart×nonpref: payout 108", approxEq(payout, 108))
end

print("── NPCRotation: deterministic same-day, different-day ──")
do
	local pool = { "a", "b", "c", "d" }
	local d1 = rotationPick("bart", pool, 100)
	local d1b = rotationPick("bart", pool, 100)
	check("same NPC + same yday → same pick", d1 == d1b, "got " .. tostring(d1) .. " vs " .. tostring(d1b))
	local d2 = rotationPick("bart", pool, 101)
	check("same NPC + next yday → different pick (small pool)",
		d1 ~= d2, "got " .. tostring(d1) .. " vs " .. tostring(d2))
	local h1 = rotationPick("hexerine", pool, 100)
	check("different NPC + same yday → may differ (no collision guaranteed)",
		h1 ~= nil)
end

print("── NPCRotation: empty pool returns nil ──")
do
	local r = rotationPick("bart", {}, 100)
	check("empty pool returns nil", r == nil)
end

print("── NPCRotation: deterministic across yday wraparound ──")
do
	-- yday 366 (leap year end) and yday 1 (next year start) — should
	-- still return a valid pool entry, no division-by-zero.
	local pool = { "x", "y", "z" }
	local r366 = rotationPick("bart", pool, 366)
	local r1 = rotationPick("bart", pool, 1)
	check("yday 366 returns valid entry", r366 == "x" or r366 == "y" or r366 == "z")
	check("yday 1 returns valid entry", r1 == "x" or r1 == "y" or r1 == "z")
end

-- ── Tally ────────────────────────────────────────────────────────────
print("")
print(string.format("Results: %d passed, %d failed", passes, failures))
if failures > 0 then
	error(string.format("%d test(s) failed", failures), 0)
end
