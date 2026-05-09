--!strict
-- Telemetry: batched event shipper per ADR-3 (Bloom&Burgle_Architecture_Eval.md).
--
-- Server-only. Batches events in memory and ships them via HttpService to
-- a single configured collector endpoint. Designed to be drop-in cheap:
-- Telemetry.track("sell_payout", { amount = 360, mutations = 1 }) is the
-- entire API surface for the call sites.
--
-- Endpoint configuration is read from `Workspace.TelemetryEndpoint` (a
-- StringValue) so live ops can flip / disable shipping without re-publishing
-- the place. Empty / missing endpoint = silent drop (events still buffered
-- briefly so flipping it back on captures recent activity).
--
-- Why batch? Roblox HTTP requests have non-trivial overhead and a per-server
-- request cap. Batching 50 events / 30s collapses ~3000 req/min down to
-- ~2 req/min per server with 30 active players.
--
-- Required launch events (see eval doc §P0/ADR-3):
--   session_start  • class_picked  • pod_loaded      • pod_ripened
--   harvest_decision • sell_payout • scrap_payout    • gamepass_purchased
--   dev_product_purchased            • error_caught

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Telemetry = {}

-- Tunables. Conservative defaults; live ops can override via attributes.
local BATCH_SIZE = 50
local BATCH_INTERVAL_SEC = 30
local MAX_QUEUE = 500
local SHIP_TIMEOUT_SEC = 5

-- ── State ──────────────────────────────────────────────────────────
local queue: { { name: string, ts: number, userId: number?, props: { [string]: any } } } = {}
local lastFlushAt = os.clock()
local serverStart = os.time()
local sessionId = HttpService:GenerateGUID(false)

-- ── Endpoint discovery ─────────────────────────────────────────────
-- Read from Workspace.TelemetryEndpoint (StringValue). Returns "" if not set.
local function getEndpoint(): string
	local v = Workspace:FindFirstChild("TelemetryEndpoint")
	if v and v:IsA("StringValue") then return v.Value end
	return ""
end

-- Read the ingest auth secret from Workspace.TelemetryIngestKey (StringValue).
-- Sent as `X-Bab-Ingest-Key` on every flush. Empty/missing → header omitted
-- and the Worker rejects with 401, which keeps malformed configs visible
-- (the warn() in flushNow logs the failure instead of silently storing junk).
local function getIngestKey(): string
	local v = Workspace:FindFirstChild("TelemetryIngestKey")
	if v and v:IsA("StringValue") then return v.Value end
	return ""
end

-- ── Flush ──────────────────────────────────────────────────────────
local function flushNow()
	if #queue == 0 then return end
	if not RunService:IsServer() then queue = {}; return end
	local endpoint = getEndpoint()
	if endpoint == "" then
		-- Drop silently to bound memory under no-collector configs. Without
		-- this, queue would grow forever on dev machines.
		queue = {}
		lastFlushAt = os.clock()
		return
	end
	local batch = queue
	queue = {}
	lastFlushAt = os.clock()

	local payload = HttpService:JSONEncode({
		placeId = game.PlaceId,
		jobId = game.JobId,
		sessionId = sessionId,
		serverStart = serverStart,
		shipTs = os.time(),
		events = batch,
	})

	local headers: { [string]: string } = {
		["Content-Type"] = "application/json",
	}
	local key = getIngestKey()
	if key ~= "" then
		headers["X-Bab-Ingest-Key"] = key
	end

	-- Run the HTTP request off the calling thread so flush() never blocks.
	task.spawn(function()
		local ok, err = pcall(function()
			HttpService:RequestAsync({
				Url = endpoint,
				Method = "POST",
				Headers = headers,
				Body = payload,
			})
		end)
		if not ok then
			-- Don't re-queue (avoid retry storms). Log so the operator notices.
			warn(string.format("[Telemetry] ship failed: %s (events=%d, dropped)", tostring(err), #batch))
		end
	end)
end

-- ── Public API ─────────────────────────────────────────────────────

-- Track an event. Server-only. Player optional (e.g. server lifecycle events).
function Telemetry.track(eventName: string, props: { [string]: any }?, player: Player?)
	if not RunService:IsServer() then return end
	if typeof(eventName) ~= "string" or eventName == "" then return end

	if #queue >= MAX_QUEUE then
		-- Drop oldest. Better than blocking new events under a stuck flush.
		table.remove(queue, 1)
	end

	local entry: any = {
		name = eventName,
		ts = os.time(),
		props = props or {},
	}
	if player then entry.userId = player.UserId; entry.userName = player.Name end
	table.insert(queue, entry)

	-- Eager flush when batch fills.
	if #queue >= BATCH_SIZE then
		task.spawn(flushNow)
	end
end

-- Flush on demand (e.g. before BindToClose).
function Telemetry.flush()
	flushNow()
end

-- Returns current queue depth — useful for dbg state diagnostics.
function Telemetry.queueDepth(): number
	return #queue
end

-- Set endpoint at runtime (creates the StringValue if missing).
-- Note: the `(v :: StringValue).X = Y` pattern is avoided because Lua's lack
-- of statement separators makes `local v = expr; (cast).X = Y` parse as a
-- function call (`expr(cast).X`).
function Telemetry.setEndpoint(url: string)
	local existing = Workspace:FindFirstChild("TelemetryEndpoint")
	local v: StringValue
	if existing and existing:IsA("StringValue") then
		v = existing
	else
		if existing then existing:Destroy() end
		v = Instance.new("StringValue")
		v.Name = "TelemetryEndpoint"
		v.Parent = Workspace
	end
	v.Value = url
end

-- Set the ingest auth key at runtime. Sent as `X-Bab-Ingest-Key` header
-- on every flush. Stored in Workspace.TelemetryIngestKey StringValue so
-- it's discoverable from `dbg state` and live-overridable for hotfixes.
function Telemetry.setIngestKey(key: string)
	local existing = Workspace:FindFirstChild("TelemetryIngestKey")
	local v: StringValue
	if existing and existing:IsA("StringValue") then
		v = existing
	else
		if existing then existing:Destroy() end
		v = Instance.new("StringValue")
		v.Name = "TelemetryIngestKey"
		v.Parent = Workspace
	end
	v.Value = key
end

-- ── Periodic flush + lifecycle hooks ───────────────────────────────
task.spawn(function()
	while true do
		task.wait(BATCH_INTERVAL_SEC)
		flushNow()
	end
end)

-- Auto-emit session lifecycle events.
Players.PlayerAdded:Connect(function(player)
	Telemetry.track("session_start", {
		joinTime = os.time(),
	}, player)
end)

Players.PlayerRemoving:Connect(function(player)
	Telemetry.track("session_end", {
		leaveTime = os.time(),
		cash = (function()
			local ls = player:FindFirstChild("leaderstats")
			if not ls then return nil end
			local c = ls:FindFirstChild("Cash")
			return c and (c :: IntValue).Value
		end)(),
		class = player:GetAttribute("Class"),
		plantsHarvested = player:GetAttribute("PlantsHarvested"),
	}, player)
end)

-- Capture uncaught errors. Wraps the same ScriptContext.Error that
-- DebugHooks already listens on — both are independent listeners.
game:GetService("ScriptContext").Error:Connect(function(message, stack, _src)
	Telemetry.track("error_caught", {
		message = string.sub(message, 1, 500),
		stackHead = string.sub(stack, 1, 500),
	})
end)

-- Flush remaining events on shutdown. BindToClose has up to 30s grace.
game:BindToClose(function()
	flushNow()
	-- Give the HTTP request a fighting chance to land before the server dies.
	task.wait(2)
end)

print("[BAB-LIFE] Telemetry online — batch=" .. BATCH_SIZE .. " interval=" .. BATCH_INTERVAL_SEC .. "s endpoint=" .. (getEndpoint() == "" and "<unset>" or "<configured>"))

return Telemetry
