--!strict
-- TelemetryBoot — wires the Telemetry endpoint + ingest key at server start.
--
-- BAB-PHASE-0-TELEMETRY-WIRING (2026-05-09).
--
-- Reads from Workspace attributes set by the publish scripts via the .env
-- (BB_TELEMETRY_ENDPOINT, BB_TELEMETRY_KEY). If neither is present at
-- boot, Telemetry runs in "buffer + drop" mode (queue grows briefly, then
-- gets cleared on each flush) — useful for Studio Play where we don't
-- want to ship dev events to prod.
--
-- Live override path (per ops):
--   Workspace.TelemetryEndpoint  → setEndpoint
--   Workspace.TelemetryIngestKey → setIngestKey
-- These can be set at runtime via dbg eval / Studio attributes; subsequent
-- flushes pick up the new values immediately.

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Telemetry = require(ServerScriptService:WaitForChild("Telemetry") :: ModuleScript) :: any

-- Boot-time config discovery, in priority order:
--   1. Generated TelemetryConfig.luau (gitignored, written by publish.sh
--      from .env BB_TELEMETRY_ENDPOINT + BB_TELEMETRY_KEY before build)
--   2. Workspace.<Name> string attribute (live ops override)
--   3. Workspace.<Name> StringValue child (legacy / dbg eval override)
-- Studio Play with none of these → Telemetry buffers + drops, no shipping.

local endpoint = ""
local ingestKey = ""

-- Source 1: generated config file. Use FindFirstChild (not WaitForChild)
-- so a missing file doesn't hang server startup forever.
local configModule = ServerScriptService:FindFirstChild("TelemetryConfig")
if configModule and configModule:IsA("ModuleScript") then
	local ok, config = pcall(require, configModule)
	if ok and typeof(config) == "table" then
		if typeof(config.endpoint) == "string" then endpoint = config.endpoint end
		if typeof(config.ingestKey) == "string" then ingestKey = config.ingestKey end
	end
end

-- Source 2 + 3: Workspace overrides (only if not already set by config file).
local function readWorkspace(attrName: string, valName: string): string
	local attr = Workspace:GetAttribute(attrName)
	if typeof(attr) == "string" and attr ~= "" then return attr end
	local v = Workspace:FindFirstChild(valName)
	if v and v:IsA("StringValue") and v.Value ~= "" then return v.Value end
	return ""
end

if endpoint == "" then endpoint = readWorkspace("TelemetryEndpoint", "TelemetryEndpoint") end
if ingestKey == "" then ingestKey = readWorkspace("TelemetryIngestKey", "TelemetryIngestKey") end

if endpoint ~= "" then
	Telemetry.setEndpoint(endpoint)
end
if ingestKey ~= "" then
	Telemetry.setIngestKey(ingestKey)
end

if endpoint == "" then
	print("[BAB-LIFE] TelemetryBoot: no endpoint configured — events will buffer + drop. Set Workspace.TelemetryEndpoint to ship.")
elseif ingestKey == "" then
	warn("[TelemetryBoot] endpoint is set but no ingest key — Worker will reject with 401")
else
	print("[BAB-LIFE] TelemetryBoot: endpoint configured, ingest key set, ready to ship.")
end
