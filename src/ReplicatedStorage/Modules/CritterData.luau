--!strict
-- CritterData: critter species registry.
--
-- Renamed from PlantData per ADR-5 (P1.2 / 2026-05-08). The "Plant"
-- terminology was a Hungarian-notation lie inherited from the pre-pivot
-- design — every "plant" is actually a critter (egg → creature). The
-- legacy name `PlantData.luau` is kept as a one-release shim so out-of-tree
-- consumers don't break instantly.
--
-- Each species has:
--   - cost / value / scrap economics
--   - grow time (incubation seconds)
--   - rarity + cuteness archetype + visual color
--   - per-class affinity matrix (asset / liability / neutral)
--   - special tag (Contraband / Sacred / Mythic / nil)

local M = {}

export type Affinity = "asset" | "liability" | "neutral"

export type Tag = "Contraband" | "Sacred" | "Mythic" | nil

export type CritterSpec = {
	id: string,
	displayName: string,
	emoji: string,
	-- shape archetype used by CritterVisuals to render the cute critter:
	--   "quad"   = 4-legged ground critter (hound, stallion, salamander, drake)
	--   "winged" = small flying (wyvern, hummingbird, imp)
	--   "bug"    = small ground bug (beetle, rat, toad, cat)
	--   "multi"  = multi-segment serpent/hydra
	archetype: "quad" | "winged" | "bug" | "multi",
	-- archetype tag used by ClassData hatchBias matching
	hatchArchetype: "mount" | "skyMount" | "cogworkPet" | "magicalFamiliar" | "magicalCritter" | "predator",
	color: { number },          -- Color3 [r,g,b] floats 0-1 (steampunk-tinted)
	growSeconds: number,        -- incubation time in pod
	baseValue: number,          -- gold from SELL
	scrapValue: number,         -- cog parts from SCRAP
	seedCost: number,           -- price at Egg Emporium (egg, not seed)
	rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic",
	mutationChance: number,     -- 0-1 chance any harvest is mutated
	unlockCash: number,         -- min lifetime cash to unlock at Emporium
	tag: Tag,                   -- Contraband / Sacred / Mythic
	-- Affinity per class id. Read by HarvestModal advisory line + Stable bonus engine.
	affinity: { [string]: Affinity },
}

-- Affinity table copy-pasted from spec §8 to make the data easy to audit.
-- A = asset, L = liability, n = neutral.
-- Columns: knight, alchemist, skyPirate, tinkerer, hexer

local function mkAff(K: string, A: string, S: string, T: string, H: string): { [string]: Affinity }
	local map = { K = "asset", A = "asset", L = "liability", n = "neutral" }
	local function decode(s: string): Affinity
		if s == "A" then return "asset"
		elseif s == "L" then return "liability"
		else return "neutral" end
	end
	return {
		knight    = decode(K),
		alchemist = decode(A),
		skyPirate = decode(S),
		tinkerer  = decode(T),
		hexer     = decode(H),
	}
end

M.SPECIES = {
	-- ── MOUNTS ────────────────────────────────────────────────────────────
	mech_hound = {
		id = "mech_hound",
		displayName = "Mech-Hound",
		emoji = "🐕",
		archetype = "quad",
		hatchArchetype = "cogworkPet",
		color = {0.78, 0.57, 0.25},  -- brass
		growSeconds = 30,
		baseValue = 40,
		scrapValue = 12,
		seedCost = 25,
		rarity = "Common",
		mutationChance = 0.02,
		unlockCash = 0,
		tag = nil,
		affinity = mkAff("A","n","n","A","n"),
	} :: CritterSpec,

	steam_stallion = {
		id = "steam_stallion",
		displayName = "Steam Stallion",
		emoji = "🐴",
		archetype = "quad",
		hatchArchetype = "mount",
		color = {0.85, 0.65, 0.30},  -- polished brass
		growSeconds = 90,
		baseValue = 90,
		scrapValue = 25,
		seedCost = 60,
		rarity = "Uncommon",
		mutationChance = 0.04,
		unlockCash = 200,
		tag = nil,
		affinity = mkAff("A","n","L","n","n"),
	} :: CritterSpec,

	sky_wyvern = {
		id = "sky_wyvern",
		displayName = "Sky Wyvern",
		emoji = "🐲",
		archetype = "winged",
		hatchArchetype = "skyMount",
		color = {0.31, 0.66, 0.56},  -- copper patina
		growSeconds = 180,
		baseValue = 120,
		scrapValue = 30,
		seedCost = 110,
		rarity = "Rare",
		mutationChance = 0.06,
		unlockCash = 500,
		tag = nil,
		affinity = mkAff("L","n","A","n","n"),
	} :: CritterSpec,

	-- ── PETS ──────────────────────────────────────────────────────────────
	cogwork_rat = {
		id = "cogwork_rat",
		displayName = "Cogwork Rat",
		emoji = "🐀",
		archetype = "bug",
		hatchArchetype = "cogworkPet",
		color = {0.91, 0.77, 0.28},  -- goggle gold
		growSeconds = 25,
		baseValue = 20,
		scrapValue = 30,             -- scrap > sell — design tension
		seedCost = 18,
		rarity = "Common",
		mutationChance = 0.02,
		unlockCash = 0,
		tag = nil,
		affinity = mkAff("n","A","A","A","A"),
	} :: CritterSpec,

	brass_beetle = {
		id = "brass_beetle",
		displayName = "Brass Beetle",
		emoji = "🪲",
		archetype = "bug",
		hatchArchetype = "cogworkPet",
		color = {0.78, 0.57, 0.25},
		growSeconds = 20,            -- starter — fast loop
		baseValue = 35,
		scrapValue = 18,
		seedCost = 15,
		rarity = "Common",
		mutationChance = 0.02,
		unlockCash = 0,
		tag = nil,
		affinity = mkAff("A","n","n","A","n"),
	} :: CritterSpec,

	aether_hummingbird = {
		id = "aether_hummingbird",
		displayName = "Aether Hummingbird",
		emoji = "🐦",
		archetype = "winged",
		hatchArchetype = "magicalFamiliar",
		color = {0.31, 0.89, 1.00},  -- aether cyan
		growSeconds = 120,
		baseValue = 80,
		scrapValue = 22,
		seedCost = 70,
		rarity = "Uncommon",
		mutationChance = 0.05,
		unlockCash = 300,
		tag = nil,
		affinity = mkAff("n","A","A","n","A"),
	} :: CritterSpec,

	-- ── PREDATORS ─────────────────────────────────────────────────────────
	iron_hydra = {
		id = "iron_hydra",
		displayName = "Iron Hydra",
		emoji = "🐍",
		archetype = "multi",
		hatchArchetype = "predator",
		color = {0.18, 0.16, 0.16},  -- ironwork charcoal
		growSeconds = 360,
		baseValue = 200,
		scrapValue = 45,
		seedCost = 200,
		rarity = "Epic",
		mutationChance = 0.07,
		unlockCash = 1500,
		tag = nil,
		affinity = mkAff("L","n","L","L","A"),
	} :: CritterSpec,

	fire_salamander = {
		id = "fire_salamander",
		displayName = "Fire Salamander",
		emoji = "🦎",
		archetype = "quad",
		hatchArchetype = "predator",
		color = {1.00, 0.42, 0.12},  -- ember orange
		growSeconds = 240,
		baseValue = 150,
		scrapValue = 35,
		seedCost = 140,
		rarity = "Rare",
		mutationChance = 0.06,
		unlockCash = 800,
		tag = nil,
		affinity = mkAff("L","A","n","L","A"),
	} :: CritterSpec,

	coal_drake = {
		id = "coal_drake",
		displayName = "Coal Drake",
		emoji = "🐉",
		archetype = "winged",
		hatchArchetype = "predator",
		color = {0.10, 0.08, 0.06},  -- coal black
		growSeconds = 600,
		baseValue = 300,
		scrapValue = 60,
		seedCost = 320,
		rarity = "Legendary",
		mutationChance = 0.09,
		unlockCash = 4000,
		tag = nil,                    -- NOT contraband — sellable
		affinity = mkAff("L","n","A","L","n"),
	} :: CritterSpec,

	-- ── MAGICAL ───────────────────────────────────────────────────────────
	ember_imp = {
		id = "ember_imp",
		displayName = "Ember Imp",
		emoji = "👹",
		archetype = "winged",
		hatchArchetype = "magicalCritter",
		color = {1.00, 0.42, 0.12},
		growSeconds = 180,
		baseValue = 100,
		scrapValue = 40,
		seedCost = 90,
		rarity = "Rare",
		mutationChance = 0.06,
		unlockCash = 600,
		tag = "Contraband",           -- can't sell — must scrap or nurture
		affinity = mkAff("L","A","n","L","A"),
	} :: CritterSpec,

	patina_toad = {
		id = "patina_toad",
		displayName = "Patina Toad",
		emoji = "🐸",
		archetype = "bug",
		hatchArchetype = "magicalCritter",
		color = {0.31, 0.66, 0.56},
		growSeconds = 90,
		baseValue = 70,
		scrapValue = 28,
		seedCost = 55,
		rarity = "Uncommon",
		mutationChance = 0.05,
		unlockCash = 250,
		tag = "Sacred",               -- can't scrap — only sell or nurture
		affinity = mkAff("n","A","n","n","A"),
	} :: CritterSpec,

	cogwork_cat = {
		id = "cogwork_cat",
		displayName = "Cogwork Cat",
		emoji = "🐈",
		archetype = "bug",
		hatchArchetype = "magicalCritter",
		color = {0.95, 0.89, 0.79},  -- steam cream
		growSeconds = 120,
		baseValue = 90,
		scrapValue = 32,
		seedCost = 75,
		rarity = "Uncommon",
		mutationChance = 0.05,
		unlockCash = 350,
		tag = nil,
		affinity = mkAff("n","A","n","A","A"),
	} :: CritterSpec,
}

-- Mutation registry — tuned to feel celebratory but rare per spec §1.2.
export type MutationSpec = {
	id: string,
	displayName: string,
	emoji: string,
	multiplier: number,
	chance: number,                  -- relative weight; sampled inside species mutationChance roll
	color: { number },
}

M.MUTATIONS = {
	{ id = "polished",  displayName = "Polished",  emoji = "✨", multiplier = 2.0,  chance = 0.50, color = {1.0, 0.96, 0.78} } :: MutationSpec,
	{ id = "gilded",    displayName = "Gilded",    emoji = "🥇", multiplier = 5.0,  chance = 0.25, color = {0.91, 0.77, 0.28} } :: MutationSpec,
	{ id = "aether",    displayName = "Aether",    emoji = "💎", multiplier = 12.0, chance = 0.15, color = {0.31, 0.89, 1.00} } :: MutationSpec,
	{ id = "ember",     displayName = "Ember",     emoji = "🔥", multiplier = 30.0, chance = 0.08, color = {1.00, 0.42, 0.12} } :: MutationSpec,
	{ id = "celestial", displayName = "Celestial", emoji = "💫", multiplier = 100.0,chance = 0.02, color = {0.6,  0.9,  1.0}  } :: MutationSpec,
}

function M.get(id: string): CritterSpec?
	return M.SPECIES[id]
end

function M.list(): { CritterSpec }
	local out = {}
	for _, p in M.SPECIES do
		table.insert(out, p)
	end
	table.sort(out, function(a, b) return a.seedCost < b.seedCost end)
	return out
end

function M.rollMutation(): MutationSpec?
	local roll = math.random()
	local cumulative = 0
	for _, mut in M.MUTATIONS do
		cumulative += mut.chance
		if roll <= cumulative then
			return mut
		end
	end
	return M.MUTATIONS[1]
end

-- Steampunk rarity colors — kept compatible with the old PlantData.rarityColor
-- API but now sourcing from BrandColors via inline RGB so this module has no
-- runtime require dependency.
function M.rarityColor(rarity: string): { number }
	if rarity == "Common"    then return { 200/255, 146/255, 63/255  }   -- Brass
	elseif rarity == "Uncommon"  then return { 79/255,  168/255, 143/255 } -- CopperPatina
	elseif rarity == "Rare"      then return { 79/255,  227/255, 255/255 } -- AetherCyan
	elseif rarity == "Epic"      then return { 255/255, 106/255, 31/255  } -- EmberOrange
	elseif rarity == "Legendary" then return { 232/255, 197/255, 71/255  } -- GoggleGold
	elseif rarity == "Mythic"    then return { 79/255,  227/255, 255/255 } -- AetherCyan (animated rim at runtime)
	end
	return {1, 1, 1}
end

-- Affinity helper — returns "asset" / "liability" / "neutral" for a given
-- (species, class) pair. Used by the HarvestModal advisory line and the
-- Stable bonus engine.
function M.affinityFor(speciesId: string, classId: string): Affinity
	local s = M.SPECIES[speciesId]
	if not s then return "neutral" end
	return s.affinity[classId] or "neutral"
end

-- Class-aware advisory copy for HarvestModal. Single line, ≤60 chars.
function M.advisoryFor(speciesId: string, classId: string): string
	local aff = M.affinityFor(speciesId, classId)
	local s = M.SPECIES[speciesId]
	if not s then return "" end
	local class = classId:gsub("^%l", string.upper)
	if aff == "asset" then
		return string.format("✓ %ss thrive with %ss. Strong asset if nurtured.", class, s.displayName)
	elseif aff == "liability" then
		return string.format("⚠ As a %s, this %s may turn on you. Most sell or scrap.", class, s.displayName)
	else
		return string.format("• %ss are neutral to %ss. Mild bonus if nurtured.", class, s.displayName)
	end
end

return M
