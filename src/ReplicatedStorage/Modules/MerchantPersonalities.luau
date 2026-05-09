--!strict
-- MerchantPersonalities — pure-data registry of marketplace NPC profiles.
--
-- BAB-MARKETPLACE-NPC-ROTATION (2026-05-08). Each NPC has:
--   - Pricing axis: basePremium, nonPreferenceMultiplier, arbitrageProfile
--   - Preference rules: hatchArchetype + tag + visualArchetype OR-of-OR matching
--   - Dialogue lines (round-robin per visit)
--   - Special rotation pool (curated list of species that can be today's special)
--
-- This module is INTENTIONALLY pure data (no Roblox runtime calls, no Color3,
-- no Instance access). That keeps it Lune-requireable so the pricing test
-- can import it directly instead of mirroring it. Visual identity (colors,
-- positions, models) lives in each NPC's own server script.
--
-- ── Coexistence with BrassBart v1 ────────────────────────────────────
-- BrassBart.server.luau before this PR hardcoded `BRASS_BART_MULTIPLIER = 1.2`.
-- The bart entry below preserves that 1.2× as `basePremium`, so pricing for
-- a "no preference fit, no arbitrage, no special" sale still equals the v1
-- behavior (1.2 × 1.0 × (1 + 0 + 0) = 1.2×). The v1→v2 jump only adds
-- bonuses on top, never removes the floor.

local M = {}

export type ArbitrageProfile = "asset" | "liability" | "none"

export type Personality = {
	id: string,
	displayName: string,
	emoji: string,
	actionText: string,                 -- ProximityPrompt.ActionText
	objectText: string,                 -- ProximityPrompt.ObjectText

	-- Pricing axis
	basePremium: number,                -- baseline multiplier on pawn-forge formula (1.0–1.3 typical)
	nonPreferenceMultiplier: number,    -- multiplier for off-preference species (default 1.0; 0.8 = "scoff")
	arbitrageProfile: ArbitrageProfile,
	arbitrageBonus: number,             -- bonus added to multiplier when arbitrage profile fires (e.g. 0.2)

	-- Preference matching (any-of: archetype OR tag OR visual-archetype hits → in preference)
	preferredHatchArchetypes: { string },
	preferredTags: { string },
	preferredVisualArchetypes: { string },

	-- Dialogue (≥5 lines; consumer should round-robin per visit)
	dialogue: { string },

	-- Today's-special rotation pool — curated species ids that may rotate as
	-- today's special preference. Curated rather than auto-derived from
	-- preference rules so game design can hand-pick rotation variety.
	specialRotationPool: { string },
}

-- ── Personality registry ─────────────────────────────────────────────

M.PERSONALITIES = {
	-- Brass Bart — gruff dwarf-coded mech-trader. Likes mechanical/predatory.
	-- Pays liability premium (he'll buy what other classes don't want to keep).
	-- v1 multiplier preserved as basePremium 1.2× for backwards-compat.
	bart = {
		id = "bart",
		displayName = "Brass Bart",
		emoji = "⚙",
		actionText = "Sell to Brass Bart",
		objectText = "⚙ Brass Bart",

		basePremium = 1.2,
		nonPreferenceMultiplier = 1.0,        -- no scoff; takes anything at base rate
		arbitrageProfile = "liability",
		arbitrageBonus = 0.2,

		preferredHatchArchetypes = { "cogworkPet", "predator" },
		preferredTags = {},
		preferredVisualArchetypes = {},

		dialogue = {
			"Brass Bart Steamhammer at yer service. What's in the sack?",
			"Aye, I'll take that. Mech-bits or beasts, gold's gold.",
			"Don't try to haggle, lad. Prices are prices.",
			"Saw a sky-pirate try to sell me a wyvern yesterday. Didn't take it.",
			"Five years in the cogworks taught me one thing: predators pay.",
		},

		specialRotationPool = {
			"mech_hound", "cogwork_rat", "brass_beetle",
			"iron_hydra", "fire_salamander", "coal_drake",
		},
	} :: Personality,

	-- Hexerine "Stitches" — eccentric witch-alchemist. Likes magical/sacred.
	-- Pays asset premium (rewards class-aligned harvests; "the resonance
	-- sharpens" as her dialogue puts it).
	hexerine = {
		id = "hexerine",
		displayName = "Hexerine \"Stitches\"",
		emoji = "🜍",                          -- alchemical sulfur
		actionText = "Trade with Hexerine",
		objectText = "🜍 Hexerine \"Stitches\"",

		basePremium = 1.0,
		nonPreferenceMultiplier = 1.0,
		arbitrageProfile = "asset",
		arbitrageBonus = 0.3,

		preferredHatchArchetypes = { "magicalFamiliar", "magicalCritter" },
		preferredTags = { "Sacred" },
		preferredVisualArchetypes = {},

		dialogue = {
			"Stitches doesn't haggle. Stitches measures... essence.",
			"A sacred toad? Oh, my dear. I've been waiting.",
			"Hold still — the alembic wants a sniff.",
			"Class affinity sharpens the resonance. You know what to bring me.",
			"Brass Bart called me eccentric. I called him predictable.",
		},

		specialRotationPool = {
			"aether_hummingbird", "patina_toad", "ember_imp", "cogwork_cat",
			"fire_salamander",   -- alchemically interesting (fire essence)
		},
	} :: Personality,

	-- Sky Captain Verda — cocky airship pilot. Likes winged.
	-- Pays liability premium for winged species (loves things ground-bound
	-- classes can't keep). Scoffs at non-winged stock at 0.8× base.
	verda = {
		id = "verda",
		displayName = "Sky Captain Verda",
		emoji = "✈",
		actionText = "Trade with Captain Verda",
		objectText = "✈ Sky Captain Verda",

		basePremium = 1.3,
		nonPreferenceMultiplier = 0.8,        -- scoffs at ground-bound stock
		arbitrageProfile = "liability",
		arbitrageBonus = 0.4,

		preferredHatchArchetypes = { "skyMount" },
		preferredTags = {},
		preferredVisualArchetypes = { "winged" },

		dialogue = {
			"If it flies, I want it. If it doesn't... why are you here?",
			"I've crewed three airships. Three. I know my winged stock.",
			"Coal Drake? Magnificent. The wyverns will be jealous.",
			"Ground-bound creatures bore me. But fine, half-price.",
			"The Cloud Garrison pays me 20% above scale. Verda doesn't undercut.",
		},

		specialRotationPool = {
			"sky_wyvern", "aether_hummingbird", "ember_imp", "coal_drake",
		},
	} :: Personality,
}

-- ── API ──────────────────────────────────────────────────────────────

function M.get(npcId: string): Personality?
	return M.PERSONALITIES[npcId]
end

function M.list(): { Personality }
	local out: { Personality } = {}
	for _, p in M.PERSONALITIES do
		table.insert(out, p)
	end
	-- Stable order for deterministic iteration in tests + UI.
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- Test/diagnostic seam — return the count so callers can pin "we have N NPCs"
-- in structural tests without needing to know each id.
function M.count(): number
	local n = 0
	for _ in M.PERSONALITIES do n += 1 end
	return n
end

return M
