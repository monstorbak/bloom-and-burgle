--!strict
-- PresenceBroadcast — cross-server presence map for the Visit-a-Friend flow.
--
-- BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL (2026-05-10).
--
-- Each Hatchery server publishes a heartbeat to the `bab-presence-v1`
-- MessagingService topic every 30s for every active player. Subscribers
-- (= every Hatchery server) maintain an in-memory map of online players
-- across all servers, keyed by userId.
--
-- ── Cost ─────────────────────────────────────────────────────────────
-- 2 messages / server / minute / player at peak. MessagingService limit
-- is 600 msgs/min/topic. We won't approach that until concurrent player
-- count × server count >> 1000 — well above the BAB roadmap horizon.
--
-- ── Entry expiry ─────────────────────────────────────────────────────
-- Entries older than 90s are dropped (3× the heartbeat). If a server
-- dies without sending a final "leave" message, its players naturally
-- expire from the map within 90s. Clients see the same.
--
-- ── Cross-place scope ────────────────────────────────────────────────
-- Hatchery-only at v1. The Marketplace + Corridors places aren't
-- visit-targets — visiting friends is about admiring/coordinating at
-- their plot. If a friend is currently in the Marketplace, the
-- presence map shows their LAST Hatchery jobId; visiting teleports
-- them via that route.

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local M = {}

local TOPIC = "bab-presence-v1"
local HEARTBEAT_INTERVAL = 30   -- seconds
local ENTRY_TTL = 90            -- 3× heartbeat

export type PresenceEntry = {
	userId: number,
	displayName: string,
	plotIndex: number?,
	class: string?,
	placeId: number,
	jobId: string,
	ts: number,                  -- last-heartbeat os.time()
}

-- userId → entry. Mutated by the subscriber.
local presenceByUid: { [number]: PresenceEntry } = {}

-- ── Publish ──────────────────────────────────────────────────────────

local function publishHeartbeat()
	for _, player in Players:GetPlayers() do
		local entry: PresenceEntry = {
			userId = player.UserId,
			displayName = player.DisplayName,
			plotIndex = player:GetAttribute("PlotIndex"),
			class = player:GetAttribute("Class"),
			placeId = game.PlaceId,
			jobId = game.JobId,
			ts = os.time(),
		}
		pcall(function()
			MessagingService:PublishAsync(TOPIC, entry)
		end)
	end
end

-- ── Subscribe ────────────────────────────────────────────────────────

pcall(function()
	MessagingService:SubscribeAsync(TOPIC, function(message)
		local entry = message.Data
		if typeof(entry) ~= "table" then return end
		if typeof(entry.userId) ~= "number" then return end
		if typeof(entry.jobId) ~= "string" then return end
		presenceByUid[entry.userId] = entry :: any
	end)
end)

-- ── GC: prune expired entries ────────────────────────────────────────

task.spawn(function()
	while true do
		task.wait(15)
		local now = os.time()
		for uid, entry in presenceByUid do
			if now - entry.ts > ENTRY_TTL then
				presenceByUid[uid] = nil
			end
		end
	end
end)

-- ── Heartbeat loop ───────────────────────────────────────────────────

task.spawn(function()
	-- Wait briefly so the script has time to finish loading before the
	-- first publish. MessagingService is fine with empty player lists.
	task.wait(5)
	while true do
		publishHeartbeat()
		task.wait(HEARTBEAT_INTERVAL)
	end
end)

-- ── Public API ───────────────────────────────────────────────────────

-- Find a friend's current presence by userId. Returns nil if not online
-- in any BAB Hatchery server within the last 90s.
function M.findFriend(targetUid: number): PresenceEntry?
	local entry = presenceByUid[targetUid]
	if not entry then return nil end
	if os.time() - entry.ts > ENTRY_TTL then
		presenceByUid[targetUid] = nil
		return nil
	end
	return entry
end

-- Return all currently-online presence entries (for the friends list HUD
-- to filter against the player's Roblox friends list). Excludes the
-- caller's own entry (a player doesn't want to see themselves).
function M.allOnline(excludeUid: number?): { PresenceEntry }
	local now = os.time()
	local out: { PresenceEntry } = {}
	for uid, entry in presenceByUid do
		if uid == excludeUid then continue end
		if now - entry.ts > ENTRY_TTL then continue end
		table.insert(out, entry)
	end
	return out
end

-- Diagnostic: count of entries in the map.
function M.size(): number
	local n = 0
	for _ in presenceByUid do n += 1 end
	return n
end

print(("[BAB-LIFE] PresenceBroadcast online (topic=%s, heartbeat=%ds, ttl=%ds)"):format(
	TOPIC, HEARTBEAT_INTERVAL, ENTRY_TTL))

return M
