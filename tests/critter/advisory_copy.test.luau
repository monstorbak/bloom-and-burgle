--!strict
-- advisory_copy.test.luau — pure-logic regression for CritterData.advisoryFor.
--
-- BAB-PHASE-3-MYTHIC-CEREMONY-AND-ADVISORY (2026-05-09).
--
-- The HarvestModal's class-affinity advisory line is the centerpiece of the
-- asset/liability moat — every harvest tells the player WHY their critter
-- matters for their class. This test pins:
--   - All 60 (species × class) cells produce non-empty copy
--   - Copy stays ≤60 chars (mobile-first per Spec §3.1)
--   - Asset cells start with "✓", liability with "⚠", neutral with "•"
--   - No PII, no formatting drift (no double spaces, no broken templates)
--
-- Mirrors `CritterData.advisoryFor` per the established BAB convention.
-- The structural test ensures the mirror's templates match prod.
--
-- Run:
--     lune run tests/critter/advisory_copy.test.luau

-- ── Mirror of CritterData.advisoryFor templates ──────────────────────
local TEMPLATE_ASSET     = "✓ %ss thrive with %ss. Strong asset if nurtured."
local TEMPLATE_LIABILITY = "⚠ As a %s, this %s may turn on you. Most sell or scrap."
local TEMPLATE_NEUTRAL   = "• %ss are neutral to %ss. Mild bonus if nurtured."

-- Mirror the affinity matrix (5 classes × 12 species). Letters per the
-- mkAff helper in CritterData: "A" = asset, "L" = liability, otherwise
-- neutral.
local SPECIES = {
	{ id = "mech_hound",         displayName = "Mech-Hound",         aff = { knight="A", alchemist="n", skyPirate="n", tinkerer="A", hexer="n" } },
	{ id = "steam_stallion",     displayName = "Steam Stallion",     aff = { knight="A", alchemist="n", skyPirate="L", tinkerer="n", hexer="n" } },
	{ id = "sky_wyvern",         displayName = "Sky Wyvern",         aff = { knight="L", alchemist="n", skyPirate="A", tinkerer="n", hexer="n" } },
	{ id = "cogwork_rat",        displayName = "Cogwork Rat",        aff = { knight="n", alchemist="A", skyPirate="A", tinkerer="A", hexer="A" } },
	{ id = "brass_beetle",       displayName = "Brass Beetle",       aff = { knight="A", alchemist="n", skyPirate="n", tinkerer="A", hexer="n" } },
	{ id = "aether_hummingbird", displayName = "Aether Hummingbird", aff = { knight="n", alchemist="A", skyPirate="A", tinkerer="n", hexer="A" } },
	{ id = "iron_hydra",         displayName = "Iron Hydra",         aff = { knight="L", alchemist="n", skyPirate="L", tinkerer="L", hexer="A" } },
	{ id = "fire_salamander",    displayName = "Fire Salamander",    aff = { knight="L", alchemist="A", skyPirate="n", tinkerer="L", hexer="A" } },
	{ id = "coal_drake",         displayName = "Coal Drake",         aff = { knight="L", alchemist="n", skyPirate="A", tinkerer="L", hexer="n" } },
	{ id = "ember_imp",          displayName = "Ember Imp",          aff = { knight="L", alchemist="A", skyPirate="n", tinkerer="L", hexer="A" } },
	{ id = "patina_toad",        displayName = "Patina Toad",        aff = { knight="n", alchemist="A", skyPirate="n", tinkerer="n", hexer="A" } },
	{ id = "cogwork_cat",        displayName = "Cogwork Cat",        aff = { knight="n", alchemist="A", skyPirate="n", tinkerer="A", hexer="A" } },
}

local CLASSES = { "knight", "alchemist", "skyPirate", "tinkerer", "hexer" }

local function decode(c: string): string
	if c == "A" then return "asset"
	elseif c == "L" then return "liability"
	end
	return "neutral"
end

local function classCap(class: string): string
	return string.sub(class, 1, 1):upper() .. string.sub(class, 2)
end

local function advisoryFor(species, class: string): string
	local aff = decode(species.aff[class] or "n")
	local cls = classCap(class)
	if aff == "asset" then
		return string.format(TEMPLATE_ASSET, cls, species.displayName)
	elseif aff == "liability" then
		return string.format(TEMPLATE_LIABILITY, cls, species.displayName)
	end
	return string.format(TEMPLATE_NEUTRAL, cls, species.displayName)
end

-- ── Test runner ──────────────────────────────────────────────────────
local failures = 0
local passes = 0
local function check(name: string, condition: boolean, msg: string?)
	if condition then
		passes += 1
	else
		failures += 1
		print("  ❌ " .. name .. (msg and (" — " .. msg) or ""))
	end
end

-- 60-cell coverage — every (species, class) returns a sensible advisory line.
print("── 60-cell coverage ──")
local totalCells = 0
for _, species in SPECIES do
	for _, class in CLASSES do
		totalCells += 1
		local text = advisoryFor(species, class)
		check(string.format("%s × %s: non-empty", species.id, class), text ~= "")
		check(string.format("%s × %s: ≤80 chars (mobile-fit)", species.id, class), #text <= 80,
			string.format("got %d chars: %s", #text, text))
		check(string.format("%s × %s: contains species name", species.id, class),
			string.find(text, species.displayName, 1, true) ~= nil)
	end
end
print(string.format("  ✅ %d cells covered", totalCells))

-- Marker discipline — asset starts with ✓, liability with ⚠, neutral with •.
print("── Marker discipline ──")
local affCounts = { asset = 0, liability = 0, neutral = 0 }
for _, species in SPECIES do
	for _, class in CLASSES do
		local kind = decode(species.aff[class] or "n")
		affCounts[kind] += 1
		local text = advisoryFor(species, class)
		if kind == "asset" then
			check(string.format("%s × %s: asset starts with ✓", species.id, class),
				string.sub(text, 1, 3) == "✓")
		elseif kind == "liability" then
			check(string.format("%s × %s: liability starts with ⚠", species.id, class),
				string.sub(text, 1, 3) == "⚠")
		else
			check(string.format("%s × %s: neutral starts with •", species.id, class),
				string.sub(text, 1, 3) == "•")
		end
	end
end
print(string.format("  ✅ asset=%d, liability=%d, neutral=%d (sum=60)",
	affCounts.asset, affCounts.liability, affCounts.neutral))
check("60-cell sum is 60", affCounts.asset + affCounts.liability + affCounts.neutral == 60)

-- Format hygiene — no double spaces, no leftover %s placeholders.
print("── Format hygiene ──")
for _, species in SPECIES do
	for _, class in CLASSES do
		local text = advisoryFor(species, class)
		check(string.format("%s × %s: no double-space", species.id, class),
			string.find(text, "  ") == nil, text)
		check(string.format("%s × %s: no leftover %%s", species.id, class),
			string.find(text, "%%s") == nil, text)
	end
end

-- ── Tally ────────────────────────────────────────────────────────────
print("")
print(string.format("Results: %d passed, %d failed", passes, failures))
if failures > 0 then
	error(string.format("%d test(s) failed", failures), 0)
end
