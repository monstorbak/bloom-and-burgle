--!strict
-- EscapeBehaviors — registry of "what happens when a critter escapes its pod."
--
-- BAB-CRITTER-ESCAPE Phase 2.A (2026-05-09).
--
-- Per the design ticket, when a player misses the ripe-window harvest, the
-- escaped critter triggers a class-aware behavior on the plot:
--   - **asset** affinity → beneficial passive (e.g. all pods grow 1.5×)
--   - **liability** affinity → harmful passive (e.g. drake torches pods)
--   - **neutral** affinity → silent despawn
--
-- This module is INTENTIONALLY pure data + stateless activate functions.
-- The timer + dispatch lives in EscapeWindow.server.luau. Persistence
-- lives in Persistence.luau. This module just defines what a behavior
-- DOES when activated.
--
-- ── Affinity → behavior matrix ────────────────────────────────────────
-- Per spec §8 there are 12 species × 5 classes = 60 cells. Most cells are
-- "neutral" (no behavior). Phase 2.A ships 12 catalogued behaviors:
--
--   Class      Asset behaviors                    Liability behaviors
--   knight     mech_hound (Brass Hound Patrol)    coal_drake (Drake Strafe ★)
--                                                  iron_hydra (Hydra Coil)
--   alchemist  patina_toad (Sacred Echo)
--              fire_salamander (Salamander Brew)
--              aether_hummingbird (Aether Pulse)
--   skyPirate  coal_drake (Coal Forge ★)
--              sky_wyvern (Sky Boost)
--   tinkerer   mech_hound (Cog Patrol)
--              brass_beetle (Beetle Swarm)
--   hexer      iron_hydra (Hydra Hatchery)
--              coal_drake (Coal Forge — same as sky_pirate)
--
--   ★ = fully mechanically implemented in Phase 2.A.
--   All others are CATALOGUED with toasts + telemetry but produce no
--   actual game-state effect yet. Live ops and follow-up PRs flesh them
--   out via the existing dispatch — no schema changes required.
--
-- ── Plot Defense Layer (folded in from BAB-COMBAT-LATER) ─────────────
-- Liability behaviors with `targetsRaiders = true` damage non-owner
-- players standing on the plot. Phase 2.A ships the SCHEMA flag — actual
-- raider detection requires plot-bounds + PvP zones, which come in a
-- follow-up. For now, `targetsRaiders` is informational only.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local M = {}

export type AffinityKind = "asset" | "liability" | "neutral"

export type EscapeBehavior = {
	-- Display
	id: string,
	name: string,                              -- short label for telemetry/UI ("Coal Forge")
	flavor: string,                            -- player-facing one-liner ("Pods on the plot ripen 50% faster.")
	emoji: string,
	affinity: AffinityKind,
	-- Tuning
	durationSeconds: number,                   -- how long the behavior runs
	sfxId: string?,                            -- optional one-shot SFX assetId
	-- Plot Defense Layer flag (BAB-CRITTER-ESCAPE Plot Defense, 2026-05-08).
	-- True → behavior also damages raiders on the plot. Phase 2.A: schema
	-- only; raider detection lands in a follow-up.
	targetsRaiders: boolean?,
	-- Activator. Returns a cleanup fn called on duration expiry / plot
	-- destroy / player leave. nil-cleanup is OK (idempotent).
	activate: (player: Player, plot: any?) -> (() -> ())?,
}

-- ── Helpers (used by behaviors) ──────────────────────────────────────

-- Find all planters owned by the player.
local function ownedPlanters(player: Player): { BasePart }
	local out: { BasePart } = {}
	for _, p in CollectionService:GetTagged("Planter") do
		if p:IsA("BasePart") and p:GetAttribute("OwnerUserId") == player.UserId then
			table.insert(out, p)
		end
	end
	return out
end

-- Pick a random planter that's currently growing or ripe (eligible for
-- liability "torch" behaviors).
local function randomActivePlanter(player: Player): BasePart?
	local planters = ownedPlanters(player)
	local active: { BasePart } = {}
	for _, p in planters do
		if not p:GetAttribute("IsEmpty") then table.insert(active, p) end
	end
	if #active == 0 then return nil end
	return active[math.random(#active)]
end

-- Apply an "ember" particle burst to a planter — used when a liability
-- behavior torches a pod. Self-cleaning via task.delay.
local function torchPodEffect(planter: BasePart)
	local attach = Instance.new("Attachment")
	attach.Position = Vector3.new(0, 1, 0)
	attach.Parent = planter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 106, 31))   -- EmberOrange
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Size = NumberSequence.new(0.6, 1.4)
	emitter.Parent = attach
	emitter:Emit(20)
	task.delay(2.0, function() if attach.Parent then attach:Destroy() end end)
end

-- Clear a planter (becomes EMPTY, sprout destroyed). Used by Drake Strafe.
local function clearPlanter(planter: BasePart)
	local plant = planter:FindFirstChild("Plant")
	if plant then plant:Destroy() end
	planter:SetAttribute("IsEmpty", true)
	planter:SetAttribute("Ripe", false)
	planter:SetAttribute("PlantedSpecies", nil)
	planter:SetAttribute("PlantedAt", nil)
	planter:SetAttribute("GrowSeconds", nil)
end

-- ── Fully-implemented behaviors ──────────────────────────────────────

-- COAL FORGE: per the ticket's spec — every pod on the plot grows 50%
-- faster for the duration. Implementation: subtract from PlantedAt on
-- activation (effectively shifting the timer); restore on cleanup if
-- behavior ends mid-grow. We use the additive-timer-shift approach
-- (vs scaling growSeconds) so player-side math stays consistent with
-- the existing GrowLoop's clamp.
local function coalForgeActivate(player: Player, _plot: any?): (() -> ())?
	local affected: { [BasePart]: { originalPlantedAt: number } } = {}
	for _, planter in ownedPlanters(player) do
		if planter:GetAttribute("IsEmpty") then continue end
		local plantedAt = planter:GetAttribute("PlantedAt") :: number?
		local growSeconds = planter:GetAttribute("GrowSeconds") :: number?
		if not (plantedAt and growSeconds) then continue end
		-- Shift PlantedAt back by 50% of remaining grow time (= speed up by 1.5×).
		local now = os.time()
		local elapsed = now - plantedAt
		local remaining = math.max(0, growSeconds - elapsed)
		local shift = remaining * (1 - 1/1.5)   -- 33% reduction in remaining time
		planter:SetAttribute("PlantedAt", plantedAt - shift)
		affected[planter] = { originalPlantedAt = plantedAt }
	end
	-- Cleanup — restore original PlantedAt for any planter that's still
	-- mid-grow at end of behavior. Already-ripe pods stay ripe.
	return function()
		for planter, state in affected do
			if not planter.Parent then continue end
			if planter:GetAttribute("IsEmpty") then continue end
			-- Only restore if not yet ripe (otherwise leave the speed boost in).
			if planter:GetAttribute("Ripe") then continue end
			planter:SetAttribute("PlantedAt", state.originalPlantedAt)
		end
	end
end

-- DRAKE STRAFE: every 8s, picks one ripe-or-incubating pod owned by the
-- player and sets it on fire — pod becomes EMPTY, in-progress incubation
-- lost. Behavior runs for `durationSeconds` or until the plot has no more
-- pods to torch.
local function drakeStrafeActivate(player: Player, _plot: any?): (() -> ())?
	local cancelled = false
	task.spawn(function()
		while not cancelled do
			task.wait(8)
			if cancelled then break end
			local target = randomActivePlanter(player)
			if not target then break end   -- no more pods, behavior self-ends
			torchPodEffect(target)
			clearPlanter(target)
		end
	end)
	return function() cancelled = true end
end

-- Generic catalog-only behavior — emits a toast + telemetry but no
-- mechanical effect. Used for the 10 stub behaviors. Real implementations
-- replace this in follow-up PRs.
local function catalogOnlyActivate(_player: Player, _plot: any?): (() -> ())?
	-- No-op cleanup. Behavior duration runs out; nothing to undo.
	return nil
end

-- ── Behavior registry ────────────────────────────────────────────────
-- Keyed by [speciesId][classId] → EscapeBehavior. Lookup gracefully
-- returns nil for un-registered cells (defaults to silent escape).

M.BEHAVIORS = {
	coal_drake = {
		-- Sky Pirate / Hexer treat the drake as an asset
		skyPirate = {
			id = "coal_forge_skyPirate",
			name = "Coal Forge",
			flavor = "Pods on the plot ripen 50% faster for the next 4 minutes.",
			emoji = "🔥",
			affinity = "asset",
			durationSeconds = 240,
			activate = coalForgeActivate,
		} :: EscapeBehavior,
		hexer = {
			id = "coal_forge_hexer",
			name = "Coal Forge",
			flavor = "Pods on the plot ripen 50% faster for the next 4 minutes.",
			emoji = "🔥",
			affinity = "asset",
			durationSeconds = 240,
			activate = coalForgeActivate,
		} :: EscapeBehavior,
		-- Knight / Tinkerer treat it as a liability
		knight = {
			id = "drake_strafe_knight",
			name = "Drake Strafe",
			flavor = "The drake torches one pod every 8 seconds. Pods become EMPTY.",
			emoji = "💥",
			affinity = "liability",
			durationSeconds = 240,
			targetsRaiders = true,
			activate = drakeStrafeActivate,
		} :: EscapeBehavior,
		tinkerer = {
			id = "drake_strafe_tinkerer",
			name = "Drake Strafe",
			flavor = "The drake torches one pod every 8 seconds. Pods become EMPTY.",
			emoji = "💥",
			affinity = "liability",
			durationSeconds = 240,
			targetsRaiders = true,
			activate = drakeStrafeActivate,
		} :: EscapeBehavior,
	},

	-- ── Catalog-only behaviors (Phase 2.A: toast + telemetry, no mechanics) ──
	-- These ship to populate the catalog so the player sees variety. Live
	-- ops and follow-up PRs replace `catalogOnlyActivate` with real effects.
	mech_hound = {
		knight = {
			id = "brass_hound_patrol",
			name = "Brass Hound Patrol",
			flavor = "The hound patrols the plot. Sells get +5% for 3 minutes.",
			emoji = "🐕",
			affinity = "asset",
			durationSeconds = 180,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
		tinkerer = {
			id = "cog_patrol",
			name = "Cog Patrol",
			flavor = "The cogwork hound patrols. Cog-tagged species sell +5% for 3 minutes.",
			emoji = "⚙",
			affinity = "asset",
			durationSeconds = 180,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
	},

	iron_hydra = {
		knight = {
			id = "hydra_coil",
			name = "Hydra Coil",
			flavor = "The hydra coils around the pods, slowing growth to 50% for 4 minutes.",
			emoji = "🐍",
			affinity = "liability",
			durationSeconds = 240,
			targetsRaiders = true,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
		hexer = {
			id = "hydra_hatchery",
			name = "Hydra Hatchery",
			flavor = "Each pod that ripens has +1 mutation chance for 4 minutes.",
			emoji = "🐉",
			affinity = "asset",
			durationSeconds = 240,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
	},

	fire_salamander = {
		alchemist = {
			id = "salamander_brew",
			name = "Salamander Brew",
			flavor = "Mutations are 20% more likely to roll for the next 3 minutes.",
			emoji = "🦎",
			affinity = "asset",
			durationSeconds = 180,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
		hexer = {
			id = "salamander_pact",
			name = "Salamander Pact",
			flavor = "Mutations are 20% more likely to roll for the next 3 minutes.",
			emoji = "🦎",
			affinity = "asset",
			durationSeconds = 180,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
	},

	patina_toad = {
		alchemist = {
			id = "sacred_echo_alchemist",
			name = "Sacred Echo",
			flavor = "All sells are +10% for the next 3 minutes.",
			emoji = "🐸",
			affinity = "asset",
			durationSeconds = 180,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
		hexer = {
			id = "sacred_echo_hexer",
			name = "Sacred Echo",
			flavor = "All sells are +10% for the next 3 minutes.",
			emoji = "🐸",
			affinity = "asset",
			durationSeconds = 180,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
	},

	aether_hummingbird = {
		alchemist = {
			id = "aether_pulse",
			name = "Aether Pulse",
			flavor = "Magical critters ripen 30% faster for the next 3 minutes.",
			emoji = "🐦",
			affinity = "asset",
			durationSeconds = 180,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
	},

	sky_wyvern = {
		skyPirate = {
			id = "sky_boost",
			name = "Sky Boost",
			flavor = "Winged species ripen 100% faster for the next 4 minutes.",
			emoji = "🐲",
			affinity = "asset",
			durationSeconds = 240,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
	},

	brass_beetle = {
		tinkerer = {
			id = "beetle_swarm",
			name = "Beetle Swarm",
			flavor = "Beetles auto-collect one ripe pod every 30 seconds for 4 minutes.",
			-- BAB-EMOJI-FIX (2026-05-11): see CritterData.brass_beetle —
			-- 🪲 was missing from Roblox's font; 🐞 is universally supported.
			emoji = "🐞",
			affinity = "asset",
			durationSeconds = 240,
			activate = catalogOnlyActivate,
		} :: EscapeBehavior,
	},
}

-- ── API ──────────────────────────────────────────────────────────────

-- Look up the escape behavior for a (species, class) pair. Returns nil if
-- there's no registered behavior (default → silent escape with steam puff).
function M.lookup(speciesId: string, classId: string): EscapeBehavior?
	local bySpecies = M.BEHAVIORS[speciesId]
	if not bySpecies then return nil end
	return bySpecies[classId]
end

-- All species ids that have at least one behavior registered. Used by tests.
function M.registeredSpecies(): { string }
	local out: { string } = {}
	for sid in M.BEHAVIORS do table.insert(out, sid) end
	table.sort(out)
	return out
end

-- Total catalog size — useful for structural tests + analytics.
function M.count(): number
	local n = 0
	for _, byClass in M.BEHAVIORS do
		for _ in byClass do n += 1 end
	end
	return n
end

return M
