--!strict
-- AgentPersonalities — registry of archetypes + class affinity +
-- name pools for the Seed AI system.
--
-- BAB-LIVE-FEATURES Block 1 (2026-05-11).
--
-- Pure module. No Roblox API calls — testable from Lune. The actual
-- world-state mutation (spawning humanoids, planting critters) lives
-- in AgentVisuals/AgentBrain/AgentPlots.

local M = {}

-- ── Archetype config ─────────────────────────────────────────────────
-- The 3 archetypes shipped at v1. Each maps to:
--   • a default class (the "I usually play this class" stereotype)
--   • a preferred critter species id (drives what they plant)
--   • plant cadence — how often they replant after harvest
--   • a name pool — first-names that thematically match the archetype

export type ArchetypeConfig = {
	id: string,
	defaultClass: string,
	preferredCritter: string,          -- species id from CritterData
	plantIntervalSeconds: number,      -- how soon to replant after harvest
	wanderSpeed: number,               -- walking speed
	worldLabel: string,                -- proximity-revealed label text
}

local ARCHETYPES: { [string]: ArchetypeConfig } = {
	Greeter = {
		id = "Greeter",
		defaultClass = "Tinkerer",
		-- Cogwork Rat — common, cheap, fast-growing. Fits the
		-- "always-something-happening" greeter vibe.
		preferredCritter = "cogwork_rat",
		plantIntervalSeconds = 8,
		wanderSpeed = 12,
		worldLabel = "Artificial Tinkerer",
	},
	Trader = {
		id = "Trader",
		defaultClass = "Alchemist",
		-- Brass Beetle — slightly higher value, suits a trader stereotype.
		preferredCritter = "brass_beetle",
		plantIntervalSeconds = 12,
		wanderSpeed = 10,
		worldLabel = "Artificial Alchemist",
	},
	Silent = {
		id = "Silent",
		defaultClass = "Knight",
		-- Mech-Hound — high-value common, fits the "patient methodical
		-- Knight" stereotype.
		preferredCritter = "mech_hound",
		plantIntervalSeconds = 15,
		wanderSpeed = 8,
		worldLabel = "Artificial Knight",
	},
}

-- ── Name pools ───────────────────────────────────────────────────────
-- Stylized first-names per archetype. Combined with the class name at
-- runtime via the · separator: "Coghand · Tinkerer".
--
-- Design constraint (Bloom&Burgle_Live_Features_Design_2026-05-11.md §1
-- "Naming + disclosure"): the · separator is the visual diegetic tell —
-- real Roblox usernames don't contain U+00B7. Names should sound like
-- steampunk-village-NPC first names, NOT like Roblox usernames.

local NAME_POOLS: { [string]: { string } } = {
	Greeter = {
		"Coghand", "Brassmend", "Sprocketsmith", "Vellumkey",
		"Trimwell", "Filemaker", "Pennysharp", "Brassfit",
	},
	Trader = {
		"Vialspeak", "Alembic", "Resin", "Tincture",
		"Vellum-Wright", "Quicksilver", "Hallmark", "Decanter",
	},
	Silent = {
		"Ironhand", "Coldsteel", "Battlement", "Greaves",
		"Anvilkin", "Stonewatch", "Halberd", "Visorin",
	},
}

-- ── Public API ───────────────────────────────────────────────────────

-- Returns the canonical list of archetype ids shipped in v1.
-- Pinned for test invariants; do not return more than 3 from this fn.
function M.archetypeIds(): { string }
	return { "Greeter", "Trader", "Silent" }
end

function M.config(archetypeId: string): ArchetypeConfig?
	return ARCHETYPES[archetypeId]
end

-- Generate a stylized name for an archetype + class. Uses the
-- (archetype, index) tuple to pick a deterministic name from the pool,
-- so the same agent slot always gets the same name within a server.
--
-- Format: "<First> · <Class>" — the · separator is load-bearing for the
-- locked disclosure decision. See AiTypes.luau.
function M.generateName(archetypeId: string, classId: string, slotIndex: number): string
	local pool = NAME_POOLS[archetypeId]
	if not pool or #pool == 0 then
		return string.format("Agent · %s", classId)
	end
	-- Mod into pool — if more agents than names, names recycle. That's
	-- fine; AI is server-local and 6 agents max, both pools have ≥ 6 entries.
	local idx = ((slotIndex - 1) % #pool) + 1
	return string.format("%s · %s", pool[idx], classId)
end

-- Validate the (archetype, name) tuple looks diegetic. Used by the
-- structural test to guard against drift toward Roblox-username-shaped
-- names creeping in.
function M.isDiegeticName(name: string): boolean
	-- Must contain the · separator (U+00B7).
	return string.find(name, " · ") ~= nil
end

return M
