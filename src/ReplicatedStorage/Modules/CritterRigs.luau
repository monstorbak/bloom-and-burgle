--!strict
-- CritterRigs — per-species rig profiles for the 4 headline species.
--
-- BAB-PHASE-1-CRITTER-RIGS (2026-05-09).
--
-- Pure data registry. Each species supported here gets dedicated
-- placeholder geometry in CritterVisuals (a richer silhouette than the
-- archetype-default Parts), plus form-based scaling (hatch-cute /
-- juvenile / adult) that progresses with the grow timer.
--
-- ── Why placeholder vs real meshes ────────────────────────────────────
-- Real R15 mesh authoring is the long pole for Phase 1 (commissioning
-- estimate $1.5-2k per species). This module ships the SCAFFOLDING and
-- placeholder geometry built from BrandColors-tinted Roblox primitives,
-- so the form-transition logic + telemetry + camera hooks are wired and
-- visible. When real meshes land, set `meshId = "rbxassetid://..."` on
-- the form profile and the geometry builder swaps to MeshPart.
--
-- ── Form thresholds ──────────────────────────────────────────────────
-- Same for all rigSupport species — keeps the player's mental model
-- consistent: hatch-cute first quarter, juvenile through three quarters,
-- adult final quarter. (Spec §617 launch checklist.)

local M = {}

export type FormName = "hatchCute" | "juvenile" | "adult"

export type FormProfile = {
	scale: number,           -- overall scale multiplier
	headRatio: number,       -- head size relative to body (cute = head ≫ body, adult = head < body)
	-- Optional mesh override per form. nil → procedural placeholder.
	-- When real authored meshes land, populate this and the builder
	-- swaps from procedural Parts to MeshPart.
	meshId: string?,
}

export type RigProfile = {
	speciesId: string,
	forms: { [FormName]: FormProfile },
	-- Distinctive features beyond the archetype baseline. Used by
	-- CritterVisuals.createRig(...) as a hint list — each known feature
	-- has its own geometry-builder branch.
	features: { string },
}

-- Form-progress thresholds. Same across all species.
M.HATCH_CUTE_END = 0.25
M.JUVENILE_END = 0.75
-- (adult runs JUVENILE_END → 1.0)

function M.formForProgress(progress: number): FormName
	if progress >= M.JUVENILE_END then return "adult" end
	if progress >= M.HATCH_CUTE_END then return "juvenile" end
	return "hatchCute"
end

-- Per-species rig registry. Phase 1 ships 4 entries — the headline
-- matchups that drive the marketing thumbnail style:
--
--   mech_hound  — starter pet, every player meets within 3 minutes
--   coal_drake  — class-arbitrage poster (asset for sky-pirate/hexer,
--                 liability for knight/tinkerer)
--   brass_beetle — 20s grow loop, in every onboarding clip
--   sky_wyvern  — winged silhouette, ideal marketing thumbnail
--
-- Other 8 species fall through to CritterVisuals' archetype renderer.

M.RIGS = {
	mech_hound = {
		speciesId = "mech_hound",
		forms = {
			hatchCute = { scale = 0.6, headRatio = 1.5 },  -- oversized head, tiny body
			juvenile  = { scale = 0.85, headRatio = 1.05 }, -- normalizing
			adult     = { scale = 1.0, headRatio = 0.85 }, -- proportioned
		},
		features = {
			"ears",         -- floppy brass ears on top of head
			"fourLegs",     -- 4 legs spread radially
			"tail",         -- short curled tail
			"chestPlate",   -- brassy chest plate (the "mech" read)
		},
	} :: RigProfile,

	coal_drake = {
		speciesId = "coal_drake",
		forms = {
			hatchCute = { scale = 0.6, headRatio = 1.4 },
			juvenile  = { scale = 0.85, headRatio = 1.0 },
			adult     = { scale = 1.0, headRatio = 0.8 },
		},
		features = {
			"horns",        -- two small horns on head
			"wings",        -- the menace silhouette — Marble for translucence
			"tail",
			"tailSpike",    -- stinger tip on tail end
			"fourLegs",
		},
	} :: RigProfile,

	brass_beetle = {
		speciesId = "brass_beetle",
		forms = {
			hatchCute = { scale = 0.5, headRatio = 1.3 },
			juvenile  = { scale = 0.75, headRatio = 1.0 },
			adult     = { scale = 1.0, headRatio = 0.9 },
		},
		features = {
			"shell",        -- domed shell on top of body
			"sixLegs",      -- 6 thin radial legs
			"antennae",     -- two thin antennae
		},
	} :: RigProfile,

	sky_wyvern = {
		speciesId = "sky_wyvern",
		forms = {
			hatchCute = { scale = 0.5, headRatio = 1.5 },  -- baby wyvern, all eyes
			juvenile  = { scale = 0.85, headRatio = 1.0 },
			adult     = { scale = 1.0, headRatio = 0.8 },
		},
		features = {
			"wings",        -- HUGE wings, the silhouette feature for thumbnails
			"longNeck",     -- elongated neck (3 stacked head-spheres) — distinguishes from drake
			"twoLegs",      -- raptor-like, only 2 legs
			"tail",
			"tailFan",      -- fan-shaped tail tip
		},
	} :: RigProfile,
}

-- API — used by CritterVisuals to dispatch on rigSupport species.

function M.has(speciesId: string): boolean
	return M.RIGS[speciesId] ~= nil
end

function M.get(speciesId: string): RigProfile?
	return M.RIGS[speciesId]
end

function M.profile(speciesId: string, form: FormName): FormProfile?
	local rig = M.RIGS[speciesId]
	if not rig then return nil end
	return rig.forms[form]
end

-- Whether a species has a specific feature in its rig. Used by the
-- geometry builder to skip un-needed branches.
function M.hasFeature(speciesId: string, feature: string): boolean
	local rig = M.RIGS[speciesId]
	if not rig then return false end
	for _, f in rig.features do
		if f == feature then return true end
	end
	return false
end

-- Test/diagnostic seam.
function M.count(): number
	local n = 0
	for _ in M.RIGS do n += 1 end
	return n
end

return M
