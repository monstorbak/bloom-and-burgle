--!strict
-- EscapeWindow — owns the post-ripen escape timer + dispatch to behaviors.
--
-- BAB-CRITTER-ESCAPE Phase 2.A (2026-05-09).
--
-- ── State machine ────────────────────────────────────────────────────
--
-- EMPTY → INCUBATING → RIPE (timer T_escape = T_grow start) → ESCAPED → BEHAVIOR_ACTIVE → DESPAWNED → EMPTY
--                       ↑                                       ↓
--                       └── HARVESTED (player walks over) ──────┘
--
-- The RIPE → HARVESTED transition is handled by HarvestFlow (existing).
-- This module only adds the RIPE → ESCAPED → BEHAVIOR_ACTIVE → DESPAWNED
-- → EMPTY track.
--
-- ── Timer ratio ──────────────────────────────────────────────────────
-- 1:1 with grow time per the ticket (user decision 2026-05-08): a species
-- that takes 240s to ripen has a 240s escape window after ripening.
-- Single learnable rule, no per-species tuning curve to balance up front.
--
-- ── Cancellation ─────────────────────────────────────────────────────
-- Per-planter token check (no hot loop). Each arm() generates a unique
-- token; cancel() bumps the token; the scheduled task aborts if its
-- captured token doesn't match the current one. This lets us cancel
-- without hijacking task.delay's coroutine.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))

-- Late-require sibling Critter modules — this script lives next to them.
local Critter = ServerScriptService:WaitForChild("Critter")
local EscapeBehaviors = require(Critter:WaitForChild("EscapeBehaviors") :: ModuleScript)
local CritterRegistry = require(Critter:WaitForChild("CritterRegistry") :: ModuleScript)

-- Telemetry (optional — graceful in case it hasn't loaded yet)
local Telemetry: any = nil
do
	local tm = ServerScriptService:FindFirstChild("Telemetry")
	if tm and tm:IsA("ModuleScript") then
		local ok, mod = pcall(require, tm)
		if ok then Telemetry = mod end
	end
end

-- CritterCeremony RemoteEvent — Phase 1 created it server-side in
-- CritterVisuals.luau. We FireAllClients on escape so any nearby player's
-- camera hook can fire the escape_burst ceremony.
local function ceremonyRE(): RemoteEvent?
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local re = remotes:FindFirstChild("CritterCeremony")
	if re and re:IsA("RemoteEvent") then return re end
	return nil
end

local M = {}

-- ── Per-planter timer state ──────────────────────────────────────────
-- armed[planter] = { token: number, ripeAt: number, escapeAt: number, ownerId: number, speciesId: string }
type ArmedState = {
	token: number,
	ripeAt: number,
	escapeAt: number,
	ownerId: number,
	speciesId: string,
}
local armed: { [BasePart]: ArmedState } = {}
local nextToken = 1

-- Active behavior cleanups, keyed by (userId, behaviorId). On player
-- leave or behavior expiry, run the cleanup fn.
type ActiveBehavior = {
	userId: number,
	behaviorId: string,
	cleanup: (() -> ())?,
	expiresAt: number,
}
local activeBehaviors: { [string]: ActiveBehavior } = {}

local function activeKey(userId: number, behaviorId: string): string
	return tostring(userId) .. ":" .. behaviorId
end

-- ── Public API ───────────────────────────────────────────────────────

-- Arm the escape timer on a freshly-ripe planter. Called from GrowLoop
-- right after the pod_ripened telemetry fires. Idempotent — re-arming
-- the same planter cancels the previous arm.
function M.arm(planter: BasePart)
	if not planter:IsA("BasePart") then return end
	local ownerId = planter:GetAttribute("OwnerUserId") :: number?
	local speciesId = planter:GetAttribute("PlantedSpecies") :: string?
	local growSeconds = planter:GetAttribute("GrowSeconds") :: number?
	if not (ownerId and speciesId and growSeconds) then return end

	-- Per the ticket: T_escape = T_grow (1:1).
	local escapeAt = os.time() + growSeconds
	local token = nextToken
	nextToken += 1

	armed[planter] = {
		token = token,
		ripeAt = os.time(),
		escapeAt = escapeAt,
		ownerId = ownerId,
		speciesId = speciesId,
	}

	-- Mirror to a planter attribute for client-side HUD reading + persistence.
	planter:SetAttribute("EscapeArmedAt", os.time())
	planter:SetAttribute("EscapeAt", escapeAt)

	-- Schedule the escape via a captured-token check.
	task.delay(growSeconds, function()
		local state = armed[planter]
		if not state or state.token ~= token then return end   -- cancelled / re-armed
		if not planter.Parent then return end
		M._fireEscape(planter)
	end)
end

-- Cancel the timer (player harvested in time, or plot was destroyed).
function M.cancel(planter: BasePart)
	armed[planter] = nil
	if planter.Parent then
		planter:SetAttribute("EscapeArmedAt", nil)
		planter:SetAttribute("EscapeAt", nil)
	end
end

-- Cancel all timers for a given player (called on PlayerRemoving).
function M.cancelForPlayer(player: Player)
	for planter, state in armed do
		if state.ownerId == player.UserId then
			armed[planter] = nil
			if planter.Parent then
				planter:SetAttribute("EscapeArmedAt", nil)
				planter:SetAttribute("EscapeAt", nil)
			end
		end
	end
	-- Also clean up any active behaviors for this player.
	for key, ab in activeBehaviors do
		if ab.userId == player.UserId then
			if ab.cleanup then pcall(ab.cleanup) end
			activeBehaviors[key] = nil
		end
	end
end

-- Read state for HUD / persistence. Returns nil if not armed.
function M.stateFor(planter: BasePart): ArmedState?
	return armed[planter]
end

-- ── Behavior dispatch ────────────────────────────────────────────────

-- Internal: fired when the timer elapses. Per the state machine:
--   1. Clear the planter (escape consumes the critter — inventory does
--      NOT receive it; it's gone).
--   2. Look up the (species, class) → behavior in EscapeBehaviors.
--   3. Activate the behavior; register cleanup.
--   4. Fire pod_escaped telemetry.
--   5. Fire CritterCeremony "escape_burst" so nearby clients see it.
function M._fireEscape(planter: BasePart)
	local state = armed[planter]
	if not state then return end
	armed[planter] = nil

	local owner = Players:GetPlayerByUserId(state.ownerId)
	local classId = owner and owner:GetAttribute("Class") or "knight"
	if typeof(classId) ~= "string" or classId == "" then classId = "knight" end

	-- Compute affinity for telemetry/ceremony payload.
	local affinity = CritterData.affinityFor(state.speciesId, classId)

	-- Look up the behavior (nil if neutral / un-registered cell).
	local behavior = EscapeBehaviors.lookup(state.speciesId, classId)

	-- Clear the planter — escape consumes the critter. Per the ticket:
	-- "On escape: clears the planter as if harvested (inventory does NOT
	-- receive the critter — it's gone)".
	local plant = planter:FindFirstChild("Plant")
	if plant then plant:Destroy() end
	planter:SetAttribute("IsEmpty", true)
	planter:SetAttribute("Ripe", false)
	planter:SetAttribute("PlantedSpecies", nil)
	planter:SetAttribute("PlantedAt", nil)
	planter:SetAttribute("GrowSeconds", nil)
	planter:SetAttribute("EscapeArmedAt", nil)
	planter:SetAttribute("EscapeAt", nil)

	-- Activate behavior + schedule cleanup.
	if behavior and owner then
		local cleanup = behavior.activate(owner, nil)
		local key = activeKey(owner.UserId, behavior.id)
		activeBehaviors[key] = {
			userId = owner.UserId,
			behaviorId = behavior.id,
			cleanup = cleanup,
			expiresAt = os.time() + behavior.durationSeconds,
		}
		task.delay(behavior.durationSeconds, function()
			local ab = activeBehaviors[key]
			if not ab then return end
			activeBehaviors[key] = nil
			if ab.cleanup then pcall(ab.cleanup) end
		end)
	end

	-- pod_escaped telemetry per ADR-3.
	if Telemetry then
		pcall(function()
			Telemetry.track("pod_escaped", {
				species = state.speciesId,
				class = classId,
				affinity = affinity,
				behavior = behavior and behavior.id or "silent",
				behaviorName = behavior and behavior.name or nil,
				slotPos = { x = planter.Position.X, y = planter.Position.Y, z = planter.Position.Z },
			}, owner)
		end)
	end

	-- Fire ceremony event — Phase 1 set up the seam, Phase 2.A fires it.
	-- All nearby clients see the bloom flash even if they're not the owner.
	-- (FireAllClients is fine for now — escape events are rare; if traffic
	-- spikes we can switch to range-filtered later.)
	local re = ceremonyRE()
	if re then
		local payload = {
			type = "escape_burst",
			position = planter.Position,
			duration = 0.6,
			speciesId = state.speciesId,
			affinity = affinity,
			behaviorName = behavior and behavior.name or nil,
		}
		pcall(function() re:FireAllClients(payload) end)
	end

	print(("[BAB-LIFE] pod_escaped: species=%s class=%s affinity=%s behavior=%s"):format(
		state.speciesId, classId, affinity, behavior and behavior.id or "silent"))
end

-- ── Persistence helpers ──────────────────────────────────────────────
-- Snapshot/restore for in-progress escape behaviors. Persistence calls
-- these to survive logout per the ticket's "Persistence" section.

-- Returns serializable list of currently-armed escapes for the given player.
function M.snapshotArmedFor(player: Player): { any }
	local out: { any } = {}
	for planter, state in armed do
		if state.ownerId ~= player.UserId then continue end
		if not planter.Parent then continue end
		local slot = CritterRegistry.slotForPlanterName(planter.Name)
		if not slot then continue end
		table.insert(out, {
			slot = slot,
			species = state.speciesId,
			ripeAt = state.ripeAt,
			escapeAt = state.escapeAt,
		})
	end
	return out
end

-- Restore any armed-escape state for the player. Called by Persistence.restore
-- after planters are rebuilt. Only restores entries that haven't already
-- elapsed (those got their escape consumed offline — silent loss).
function M.restoreArmedFor(player: Player, escapesData: { any }?)
	if not escapesData then return end
	for _, entry in escapesData do
		if typeof(entry) ~= "table" then continue end
		local slot = entry.slot
		local speciesId = entry.species
		local escapeAt = entry.escapeAt
		if typeof(slot) ~= "number" or typeof(speciesId) ~= "string" or typeof(escapeAt) ~= "number" then continue end

		local now = os.time()
		if escapeAt <= now then
			-- Escape already elapsed offline — silently consume.
			-- (Behavior cleanup similarly elapsed; nothing to restore.)
			continue
		end

		local planter = CritterRegistry.findPlanterForSlot(player, slot)
		if not planter then continue end

		-- Re-arm with the original escapeAt timestamp.
		local growSeconds = planter:GetAttribute("GrowSeconds") :: number?
		if not growSeconds then continue end
		local remaining = escapeAt - now

		local token = nextToken
		nextToken += 1
		armed[planter] = {
			token = token,
			ripeAt = entry.ripeAt or now,
			escapeAt = escapeAt,
			ownerId = player.UserId,
			speciesId = speciesId,
		}
		planter:SetAttribute("EscapeArmedAt", entry.ripeAt)
		planter:SetAttribute("EscapeAt", escapeAt)

		task.delay(remaining, function()
			local state = armed[planter]
			if not state or state.token ~= token then return end
			if not planter.Parent then return end
			M._fireEscape(planter)
		end)
	end
end

-- ── Cleanup hooks ────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(player)
	M.cancelForPlayer(player)
end)

print("[BAB-LIFE] Critter/EscapeWindow online (T_escape = T_grow)")

return M
