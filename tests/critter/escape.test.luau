--!strict
-- escape.test.luau — pure-logic regression for the escape behavior catalog.
--
-- BAB-CRITTER-ESCAPE Phase 2.A (2026-05-09).
--
-- Mirrors EscapeBehaviors.luau's catalog SHAPE — that module requires
-- Roblox runtime APIs (CollectionService, Players) that Lune doesn't
-- provide, so per the established BAB convention we mirror the data
-- shape here and pin invariants. The structural test
-- (scripts/test/critter-escape-static.sh) verifies the mirror.
--
-- Run:
--     lune run tests/critter/escape.test.luau

-- ── Pinned invariants (must match production) ────────────────────────
-- These are pinned in BOTH this test and EscapeBehaviors.luau. The
-- structural test verifies they don't drift.

-- Total catalogued behaviors at Phase 2.A launch. Ticket asks for 12+ at
-- minimum; we ship 15 (4 fully-implemented Coal Forge / Drake Strafe variants
-- across 2 classes each + 11 catalog-only stubs across 7 species).
local EXPECTED_TOTAL = 15

-- Species that have at least one behavior registered. Order doesn't
-- matter for the test — we sort before comparing.
local EXPECTED_SPECIES = {
	"aether_hummingbird",
	"brass_beetle",
	"coal_drake",
	"fire_salamander",
	"iron_hydra",
	"mech_hound",
	"patina_toad",
	"sky_wyvern",
}

-- Fully-implemented behaviors (vs catalog-only stubs). These are the
-- ones the ticket calls out by name and require real game-state effects.
local EXPECTED_FULLY_IMPLEMENTED = {
	"coal_forge_skyPirate",
	"coal_forge_hexer",
	"drake_strafe_knight",
	"drake_strafe_tinkerer",
}

-- Mirror of the catalog shape. NOT the actual behavior fns — just enough
-- structure for shape tests. Real behavior fns are in EscapeBehaviors.luau.
local CATALOG = {
	coal_drake = {
		skyPirate = { id = "coal_forge_skyPirate", name = "Coal Forge", affinity = "asset", durationSeconds = 240 },
		hexer = { id = "coal_forge_hexer", name = "Coal Forge", affinity = "asset", durationSeconds = 240 },
		knight = { id = "drake_strafe_knight", name = "Drake Strafe", affinity = "liability", durationSeconds = 240, targetsRaiders = true },
		tinkerer = { id = "drake_strafe_tinkerer", name = "Drake Strafe", affinity = "liability", durationSeconds = 240, targetsRaiders = true },
	},
	mech_hound = {
		knight = { id = "brass_hound_patrol", affinity = "asset", durationSeconds = 180 },
		tinkerer = { id = "cog_patrol", affinity = "asset", durationSeconds = 180 },
	},
	iron_hydra = {
		knight = { id = "hydra_coil", affinity = "liability", durationSeconds = 240, targetsRaiders = true },
		hexer = { id = "hydra_hatchery", affinity = "asset", durationSeconds = 240 },
	},
	fire_salamander = {
		alchemist = { id = "salamander_brew", affinity = "asset", durationSeconds = 180 },
		hexer = { id = "salamander_pact", affinity = "asset", durationSeconds = 180 },
	},
	patina_toad = {
		alchemist = { id = "sacred_echo_alchemist", affinity = "asset", durationSeconds = 180 },
		hexer = { id = "sacred_echo_hexer", affinity = "asset", durationSeconds = 180 },
	},
	aether_hummingbird = {
		alchemist = { id = "aether_pulse", affinity = "asset", durationSeconds = 180 },
	},
	sky_wyvern = {
		skyPirate = { id = "sky_boost", affinity = "asset", durationSeconds = 240 },
	},
	brass_beetle = {
		tinkerer = { id = "beetle_swarm", affinity = "asset", durationSeconds = 240 },
	},
}

local function lookup(speciesId: string, classId: string)
	local bySpecies = CATALOG[speciesId]
	if not bySpecies then return nil end
	return bySpecies[classId]
end

local function count(): number
	local n = 0
	for _, byClass in CATALOG do
		for _ in byClass do n += 1 end
	end
	return n
end

local function registeredSpecies(): { string }
	local out: { string } = {}
	for sid in CATALOG do table.insert(out, sid) end
	table.sort(out)
	return out
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

local function arrEq(a: { string }, b: { string }): boolean
	if #a ~= #b then return false end
	for i, v in a do
		if v ~= b[i] then return false end
	end
	return true
end

print("── Catalog shape ──")
check(string.format("count == %d", EXPECTED_TOTAL), count() == EXPECTED_TOTAL,
	string.format("got %d", count()))

local got = registeredSpecies()
check("registered species set matches expected", arrEq(got, EXPECTED_SPECIES),
	"got " .. table.concat(got, ","))

print("── Seed entries (ticket's named examples) ──")
do
	-- coal_drake × sky_pirate / hexer = asset, "Coal Forge"
	local b1 = lookup("coal_drake", "skyPirate")
	check("coal_drake × skyPirate exists", b1 ~= nil)
	check("coal_drake × skyPirate is asset", b1 and b1.affinity == "asset")
	check("coal_drake × skyPirate name is Coal Forge", b1 and b1.name == "Coal Forge")

	local b2 = lookup("coal_drake", "hexer")
	check("coal_drake × hexer exists", b2 ~= nil)
	check("coal_drake × hexer is asset", b2 and b2.affinity == "asset")

	-- coal_drake × knight / tinkerer = liability, "Drake Strafe"
	local b3 = lookup("coal_drake", "knight")
	check("coal_drake × knight exists", b3 ~= nil)
	check("coal_drake × knight is liability", b3 and b3.affinity == "liability")
	check("coal_drake × knight has targetsRaiders flag", b3 and b3.targetsRaiders == true)
	check("coal_drake × knight name is Drake Strafe", b3 and b3.name == "Drake Strafe")

	local b4 = lookup("coal_drake", "tinkerer")
	check("coal_drake × tinkerer exists", b4 ~= nil)
	check("coal_drake × tinkerer is liability", b4 and b4.affinity == "liability")
end

print("── Unregistered cells return nil ──")
do
	check("unknown species → nil", lookup("brass_giraffe", "knight") == nil)
	check("known species + neutral class → nil", lookup("coal_drake", "alchemist") == nil)
	check("known species + nonexistent class → nil", lookup("coal_drake", "ranger") == nil)
end

print("── Per-class minimum coverage ──")
do
	-- Per ticket: minimum 2-3 behaviors per class at launch (12+ total).
	-- Verify each of the 5 classes has at least 1 behavior registered.
	local classCovered: { [string]: number } = {}
	for _, byClass in CATALOG do
		for classId in byClass do
			classCovered[classId] = (classCovered[classId] or 0) + 1
		end
	end
	for _, class in { "knight", "alchemist", "skyPirate", "tinkerer", "hexer" } do
		check(string.format("class %s has ≥1 behavior", class),
			(classCovered[class] or 0) >= 1,
			string.format("count = %d", classCovered[class] or 0))
	end
end

print("── Liability invariants ──")
do
	-- Liability behaviors should specify durationSeconds (no infinite havoc).
	for _, byClass in CATALOG do
		for _, b in byClass do
			if b.affinity == "liability" then
				check(string.format("liability %s has finite duration", b.id),
					b.durationSeconds and b.durationSeconds > 0 and b.durationSeconds <= 600)
			end
		end
	end
end

-- ── Tally ────────────────────────────────────────────────────────────
print("")
print(string.format("Results: %d passed, %d failed", passes, failures))
if failures > 0 then
	error(string.format("%d test(s) failed", failures), 0)
end
