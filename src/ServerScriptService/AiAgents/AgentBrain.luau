--!strict
-- AgentBrain — per-agent state machine that drives the plant/grow/harvest
-- loop and basic wandering.
--
-- BAB-LIVE-FEATURES Block 1 (2026-05-11).
--
-- ── State machine ────────────────────────────────────────────────────
--    idle
--      ↓ (every plantIntervalSeconds, if any empty planter)
--    walking_to_planter
--      ↓ (Humanoid reaches planter)
--    planting (0.6s pause for "anim")
--      ↓ (set planter attributes — GrowLoop takes over from here)
--    waiting
--      ↓ (planter.Ripe == true)
--    walking_to_ripe
--      ↓ (Humanoid reaches ripe planter)
--    harvesting (0.6s pause)
--      ↓ (clear planter attributes)
--    idle
--
-- The "wander" branch can interleave: when in idle, with low probability,
-- the agent walks to a random point on its plot floor and back. Pure
-- ambient activity; gives the world its "lived-in" feel even when no
-- pods are ripe.
--
-- ── Why no LocalPlayer / Player object ───────────────────────────────
-- Agents are NPC humanoids, NOT Roblox Players. They don't appear in
-- Players:GetPlayers() — that's an operational disclosure layer + a
-- side effect of not being able to spawn fake Players on Roblox.
-- For the rare callsite that needs a player-like handle (telemetry,
-- analytics), pass nil — the existing pcall-wrapped Telemetry.track
-- calls already tolerate that.

local AgentPersonalities = require(script.Parent:WaitForChild("AgentPersonalities"))
local AgentPlots = require(script.Parent:WaitForChild("AgentPlots"))

local M = {}

-- ── Per-agent state ─────────────────────────────────────────────────
type Brain = {
	id: string,
	archetype: string,
	classId: string,
	displayName: string,
	humanoidModel: Model,
	plotFloor: BasePart,
	planters: { BasePart },
	state: string,
	-- Timestamps drive transitions without a heartbeat-coupled tick.
	nextActionAt: number,
	targetPlanter: BasePart?,
	-- Watchdog: if we get stuck in a transition state for > 30s, force
	-- back to idle. Roblox PathfindingService can hang if the target is
	-- unreachable.
	stateEnteredAt: number,
}

local brains: { Brain } = {}

-- ── Helpers ─────────────────────────────────────────────────────────

local function getHumanoid(model: Model): Humanoid?
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum
end

local function getRoot(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function distanceXZ(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function pickEmptyPlanter(planters: { BasePart }): BasePart?
	for _, p in planters do
		if p:GetAttribute("IsEmpty") == true then return p end
	end
	return nil
end

local function pickRipePlanter(planters: { BasePart }): BasePart?
	for _, p in planters do
		if p:GetAttribute("Ripe") == true then return p end
	end
	return nil
end

local function pickWanderPoint(plotFloor: BasePart): Vector3
	local center = plotFloor.Position
	local size = plotFloor.Size
	local dx = (math.random() - 0.5) * (size.X - 4)
	local dz = (math.random() - 0.5) * (size.Z - 4)
	return center + Vector3.new(dx, plotFloor.Size.Y / 2 + 3, dz)
end

local function moveTowards(brain: Brain, dest: Vector3)
	local hum = getHumanoid(brain.humanoidModel)
	if not hum then return end
	-- Move-to without pathfinding (cheaper). Agents stay on small flat
	-- mini-plots; complex navigation isn't needed.
	hum:MoveTo(dest)
end

-- ── State transitions ───────────────────────────────────────────────

local function enterState(brain: Brain, newState: string)
	brain.state = newState
	brain.stateEnteredAt = os.clock()
end

local function startPlant(brain: Brain)
	local target = pickEmptyPlanter(brain.planters)
	if not target then
		-- Plot is full — wait for something to ripen or chill
		brain.nextActionAt = os.clock() + 2
		return
	end
	brain.targetPlanter = target
	enterState(brain, "walking_to_planter")
	moveTowards(brain, target.Position + Vector3.new(0, 3, 0))
end

local function finishPlant(brain: Brain)
	local target = brain.targetPlanter
	if not target then enterState(brain, "idle"); return end
	local cfg = AgentPersonalities.config(brain.archetype)
	local speciesId = cfg and cfg.preferredCritter or "cogwork_rat"
	-- Set planter attributes — GrowLoop will pick this up on next
	-- Heartbeat and start the ripen progression.
	target:SetAttribute("IsEmpty", false)
	target:SetAttribute("PlantedSpecies", speciesId)
	target:SetAttribute("PlantedAt", os.time())
	target:SetAttribute("GrowSeconds", 60)   -- AI critters grow in 60s for visual variety
	target:SetAttribute("Ripe", false)
	-- Build the visible plant on the planter
	AgentPlots.buildPlantOn(target, speciesId)
	brain.targetPlanter = nil
	brain.nextActionAt = os.clock() + 1
	enterState(brain, "waiting")
end

local function startHarvest(brain: Brain)
	local target = pickRipePlanter(brain.planters)
	if not target then
		enterState(brain, "idle")
		brain.nextActionAt = os.clock() + 2
		return
	end
	brain.targetPlanter = target
	enterState(brain, "walking_to_ripe")
	moveTowards(brain, target.Position + Vector3.new(0, 3, 0))
end

local function finishHarvest(brain: Brain)
	local target = brain.targetPlanter
	if not target then enterState(brain, "idle"); return end
	-- Clear planter — same shape as HarvestFlow.harvestPlanter does for
	-- players, without the FireClient popup + inventory add.
	local plantModel = target:FindFirstChild("Plant")
	if plantModel and plantModel.Parent then plantModel:Destroy() end
	target:SetAttribute("IsEmpty", true)
	target:SetAttribute("Ripe", false)
	target:SetAttribute("PlantedSpecies", nil)
	target:SetAttribute("PlantedAt", nil)
	target:SetAttribute("GrowSeconds", nil)
	local border = target:FindFirstChild("EmptyBorder") :: BasePart?
	if border then border.Transparency = 0.85 end
	brain.targetPlanter = nil
	local cfg = AgentPersonalities.config(brain.archetype)
	brain.nextActionAt = os.clock() + (cfg and cfg.plantIntervalSeconds or 10)
	enterState(brain, "idle")
end

local function startWander(brain: Brain)
	enterState(brain, "wander")
	local dest = pickWanderPoint(brain.plotFloor)
	moveTowards(brain, dest)
	brain.nextActionAt = os.clock() + 5
end

-- ── Tick ────────────────────────────────────────────────────────────
-- Called from the spawner's heartbeat (every ~0.5s). Cheap O(N×planters)
-- per call; with N=6 agents and 4 planters each that's 24 attribute reads.

local function tickBrain(brain: Brain)
	local now = os.clock()
	-- Watchdog: stuck-state recovery
	if now - brain.stateEnteredAt > 30 then
		brain.targetPlanter = nil
		enterState(brain, "idle")
	end

	if brain.state == "idle" then
		if now >= brain.nextActionAt then
			-- 80% chance plant if any empty pod, else wander
			if pickEmptyPlanter(brain.planters) and math.random() < 0.8 then
				startPlant(brain)
			else
				startWander(brain)
			end
		end
	elseif brain.state == "walking_to_planter" or brain.state == "walking_to_ripe" then
		-- Check if humanoid reached target (within 4 studs XZ)
		local root = getRoot(brain.humanoidModel)
		local target = brain.targetPlanter
		if not root or not target then enterState(brain, "idle"); return end
		if distanceXZ(root.Position, target.Position) < 5 then
			enterState(brain, brain.state == "walking_to_planter" and "planting" or "harvesting")
			brain.nextActionAt = os.clock() + 0.8
		end
	elseif brain.state == "planting" then
		if now >= brain.nextActionAt then finishPlant(brain) end
	elseif brain.state == "harvesting" then
		if now >= brain.nextActionAt then finishHarvest(brain) end
	elseif brain.state == "waiting" then
		-- Check if anything is ripe yet. Also wander while waiting so
		-- the agent isn't statue-still.
		if pickRipePlanter(brain.planters) then
			startHarvest(brain)
		elseif now >= brain.nextActionAt then
			startWander(brain)
		end
	elseif brain.state == "wander" then
		if now >= brain.nextActionAt then
			-- Check if a planter is ripe (priority over more wandering)
			if pickRipePlanter(brain.planters) then
				startHarvest(brain)
			else
				enterState(brain, "idle")
				brain.nextActionAt = os.clock() + 1
			end
		end
	end
end

-- ── Public API ──────────────────────────────────────────────────────

function M.register(brain: Brain)
	table.insert(brains, brain)
	enterState(brain, "idle")
	brain.nextActionAt = os.clock() + math.random(1, 4)
end

function M.tick()
	for _, brain in brains do
		tickBrain(brain)
	end
end

function M.count(): number
	return #brains
end

function M.list(): { Brain }
	return brains
end

-- Build a Brain descriptor (caller fills humanoidModel + plotFloor + planters)
function M.newBrain(id: string, archetype: string, classId: string, displayName: string): Brain
	return {
		id = id,
		archetype = archetype,
		classId = classId,
		displayName = displayName,
		humanoidModel = nil :: any,
		plotFloor = nil :: any,
		planters = {},
		state = "idle",
		nextActionAt = 0,
		targetPlanter = nil,
		stateEnteredAt = os.clock(),
	}
end

return M
