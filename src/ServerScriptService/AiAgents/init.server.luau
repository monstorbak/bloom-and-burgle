--!strict
-- AiAgents/init — boot orchestrator + heartbeat for the Seed AI system.
--
-- BAB-LIVE-FEATURES Block 1 (2026-05-11).
-- See Bloom&Burgle_Live_Features_Design_2026-05-11.md §1 + §9 Block 1.
--
-- ── What this does ──────────────────────────────────────────────────
-- On server boot:
--   1. Builds the Agent District (6 mini-plots south of the plaza).
--   2. Spawns N AI agents (default: 4) with rotating archetypes.
--   3. Starts the brain tick loop (RunService.Heartbeat, throttled to
--      0.5s cadence — the brains don't need 60Hz).
--
-- v1 is FIXED COUNT for simplicity. The "spawner heartbeat that scales
-- with real player count" described in the design doc is deferred to
-- v1.1 — gathering telemetry on whether AI count is too high or low
-- will inform the right scaling curve.
--
-- ── Disclosure ──────────────────────────────────────────────────────
-- Per the locked 2026-05-11 decision (Bloom&Burgle_Live_Features_Design
-- §1 "Naming + disclosure"), AI is disclosed via 3 diegetic layers
-- (distinct rig + stylized name + proximity label) plus 1 operational
-- layer (not in Players:GetPlayers). All four are owned by:
--   • AgentVisuals.luau (rig + BillboardGui)
--   • AgentPersonalities.luau (name)
--   • the fact that NPCs aren't Players (automatic)
--   • this boot script fires the first-encounter chat hint on first-spawn

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AgentPersonalities = require(script:WaitForChild("AgentPersonalities"))
local AgentPlots = require(script:WaitForChild("AgentPlots"))
local AgentVisuals = require(script:WaitForChild("AgentVisuals"))
local AgentBrain = require(script:WaitForChild("AgentBrain"))

-- ── Config ──────────────────────────────────────────────────────────
local TARGET_AGENT_COUNT = 4   -- v1: fixed; tune via telemetry in v1.1
local BRAIN_TICK_INTERVAL = 0.5
local FIRST_ENCOUNTER_HINT = "🌸 The villagers you see are artificial residents — they keep the world lively when servers are quiet."

-- Spawn one agent: build the brain + the rig + the plot. Returns the
-- agent's display name for boot logging.
local function spawnAgent(slotIndex: number): string?
	-- Rotate through archetypes deterministically — at TARGET=4 and
	-- ARCHETYPES=3, the first 3 are unique and the 4th repeats the
	-- first. Good enough variety for v1.
	local archetypeIds = AgentPersonalities.archetypeIds()
	local archetypeId = archetypeIds[((slotIndex - 1) % #archetypeIds) + 1]
	local cfg = AgentPersonalities.config(archetypeId)
	if not cfg then return nil end

	local classId = cfg.defaultClass
	local agentId = string.format("agent_%d", slotIndex)
	local displayName = AgentPersonalities.generateName(archetypeId, classId, slotIndex)

	-- Claim a plot in the district
	local floor, planters = AgentPlots.claim(agentId)
	if not floor or not planters then
		warn("[AiAgents] no plot available for " .. displayName)
		return nil
	end

	-- Spawn the humanoid in the center of the plot, 4 studs above the floor
	local spawnPos = floor.Position + Vector3.new(0, floor.Size.Y / 2 + 4, 0)
	local model = AgentVisuals.buildAgent({
		classId = classId,
		displayName = displayName,
		worldLabel = cfg.worldLabel,
		spawnPosition = spawnPos,
		walkSpeed = cfg.wanderSpeed,
	})
	model.Parent = Workspace

	-- Register the brain
	local brain = AgentBrain.newBrain(agentId, archetypeId, classId, displayName)
	brain.humanoidModel = model
	brain.plotFloor = floor
	brain.planters = planters
	AgentBrain.register(brain)

	return displayName
end

-- ── Boot ────────────────────────────────────────────────────────────

-- Defer to next tick so any DataStore + service registration scripts
-- have a chance to settle. Cheap.
task.defer(function()
	local plotCount = AgentPlots.buildDistrict()
	print(string.format("[BAB-LIFE] AgentDistrict built — %d mini-plots", plotCount))

	local spawned = {}
	for i = 1, TARGET_AGENT_COUNT do
		local name = spawnAgent(i)
		if name then table.insert(spawned, name) end
	end
	print(string.format(
		"[BAB-LIFE] AiAgents online — %d agents: %s",
		#spawned, table.concat(spawned, ", ")
	))
end)

-- ── Brain tick loop ─────────────────────────────────────────────────
-- Heartbeat-driven but throttled to BRAIN_TICK_INTERVAL. Roblox
-- Heartbeat fires at ~60Hz; we tick brains at 2Hz. Cheap.
local lastTick = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastTick < BRAIN_TICK_INTERVAL then return end
	lastTick = now
	AgentBrain.tick()
end)

-- ── First-encounter chat hint (deferred to v1.1) ────────────────────
-- Per the locked disclosure decision, the design called for a one-time
-- chat hint on first encounter as a 4th safety-valve disclosure layer
-- (after the 3 diegetic visual layers).
--
-- StarterGui:SetCore("ChatMakeSystemMessage", ...) is client-only, so
-- this needs a client-side handler reading from a RemoteEvent fired by
-- the server. Out of scope for v1; the visual tells (distinct rig +
-- stylized · name + proximity "Artificial X" label) already exceed the
-- Roblox TOS bar on their own.
--
-- v1.1 task: add an AiFirstEncounterHint RemoteEvent + a client handler
-- that calls StarterGui:SetCore on receipt.
_ = FIRST_ENCOUNTER_HINT   -- kept declared; referenced when v1.1 lands
_ = Players                -- keep service handle warm for v1.1 wiring
