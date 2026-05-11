--!strict
-- VisitFriendHandler — receives VisitFriend RemoteEvent + teleports the
-- player to the target friend's running Hatchery server job.
--
-- BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL (2026-05-10).
--
-- Flow:
--   1. Client clicks "Visit" in FriendsListHUD → fires VisitFriendRE with
--      { targetUid }.
--   2. Server validates: are they Roblox friends? Is the target online?
--      Is the visitor not already in a teleport (rate limit)?
--   3. If yes: TeleportService:TeleportToPlaceInstanceAsync(placeId, jobId, player)
--      with TeleportData = { fromUid = visitor.UserId, isVisitor = true }
--   4. The destination server's PlayerAdded handler reads TeleportData
--      and tags the visitor (visitor badge — deferred to Phase 4.B).
--
-- Eager-requires PresenceBroadcast so its heartbeat + subscriber loops
-- run on server boot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local PresenceBroadcast = require(ServerScriptService:WaitForChild("PresenceBroadcast") :: ModuleScript)

-- Optional Telemetry require — graceful when unavailable.
local Telemetry: any = nil
do
	local tm = ServerScriptService:FindFirstChild("Telemetry")
	if tm and tm:IsA("ModuleScript") then
		local ok, mod = pcall(require, tm)
		if ok then Telemetry = mod end
	end
end

-- Optional RateLimiter — server-side anti-spam on visit requests.
local RateLimiter: any = nil
do
	local rl = ServerScriptService:FindFirstChild("RateLimiter")
	if rl and rl:IsA("ModuleScript") then
		local ok, mod = pcall(require, rl)
		if ok then RateLimiter = mod end
	end
end

-- ── Lazy-create RemoteEvent + RemoteFunction ────────────────────────
local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local VisitFriendRE = remotes:FindFirstChild("VisitFriend")
if not VisitFriendRE then
	local re = Instance.new("RemoteEvent")
	re.Name = "VisitFriend"
	re.Parent = remotes
	VisitFriendRE = re
end
assert(VisitFriendRE)

-- RemoteFunction for client to query the cross-server presence map.
-- Client calls :InvokeServer() (no args) → returns the full list of
-- presence entries currently in any BAB Hatchery server. Client filters
-- locally against their own GetFriendsAsync result.
local PresenceFn = remotes:FindFirstChild("GetOnlinePresence")
if not PresenceFn then
	local fn = Instance.new("RemoteFunction")
	fn.Name = "GetOnlinePresence"
	fn.Parent = remotes
	PresenceFn = fn
end
assert(PresenceFn)
;(PresenceFn :: RemoteFunction).OnServerInvoke = function(player)
	-- Per-call rate limit (cheap — just an in-memory lookup, but don't
	-- let a misbehaving client spam-poll).
	if RateLimiter then
		if not RateLimiter.tryConsume(player.UserId, "GetOnlinePresence", 1, 3) then
			return {}
		end
	end
	return PresenceBroadcast.allOnline(player.UserId)
end

-- ── Validate: visitor + target are Roblox friends ────────────────────
-- Per the ticket open question 1: GetFriendsAsync is the way. Caches
-- per-player for 60s to avoid hammering the API on repeat clicks.

local friendCache: { [number]: { friends: { [number]: boolean }, expiresAt: number } } = {}

local function fetchFriendIds(player: Player): { [number]: boolean }
	local now = os.time()
	local cached = friendCache[player.UserId]
	if cached and cached.expiresAt > now then
		return cached.friends
	end
	local set: { [number]: boolean } = {}
	local ok, pages = pcall(function() return Players:GetFriendsAsync(player.UserId) end)
	if ok and pages then
		while true do
			for _, info in pages:GetCurrentPage() do
				if typeof(info.Id) == "number" then set[info.Id] = true end
			end
			if pages.IsFinished then break end
			pages:AdvanceToNextPageAsync()
		end
	end
	friendCache[player.UserId] = { friends = set, expiresAt = now + 60 }
	return set
end

local function isFriend(visitor: Player, targetUid: number): boolean
	return fetchFriendIds(visitor)[targetUid] == true
end

Players.PlayerRemoving:Connect(function(player)
	friendCache[player.UserId] = nil
end)

-- ── Visit handler ────────────────────────────────────────────────────

VisitFriendRE.OnServerEvent:Connect(function(visitor: Player, payload: any)
	if typeof(payload) ~= "table" then return end
	local targetUid = payload.targetUid
	if typeof(targetUid) ~= "number" then return end

	-- Anti-spam: 1 visit attempt per 5s.
	if RateLimiter then
		if not RateLimiter.tryConsume(visitor.UserId, "VisitFriend", 0.2, 1) then
			return
		end
	end

	-- Friendship check.
	if not isFriend(visitor, targetUid) then
		warn(("[VisitFriend] %s is not friends with %d"):format(visitor.Name, targetUid))
		return
	end

	-- Look up the target's current server.
	local target = PresenceBroadcast.findFriend(targetUid)
	if not target then
		warn(("[VisitFriend] target %d is not online in any BAB Hatchery"):format(targetUid))
		return
	end

	-- Telemetry per ADR-3.
	if Telemetry then
		pcall(function()
			Telemetry.track("friend_visit_started", {
				visitorUid = visitor.UserId,
				targetUid = targetUid,
				targetClass = target.class,
			}, visitor)
		end)
	end

	-- Teleport. TeleportToPlaceInstanceAsync drops the visitor into the
	-- specific JobId (= Roblox server instance), not just any instance
	-- of the place. If full or invalid, Roblox falls back to a fresh job.
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		fromUid = visitor.UserId,
		isVisitor = true,
		hostUid = targetUid,
	})
	local ok, err = pcall(function()
		TeleportService:TeleportToPlaceInstanceAsync(target.placeId, target.jobId, { visitor }, "", options)
	end)
	if not ok then
		warn(("[VisitFriend] teleport failed for %s → %d: %s"):format(visitor.Name, targetUid, tostring(err)))
	end
end)

print("[BAB-LIFE] VisitFriendHandler online")
