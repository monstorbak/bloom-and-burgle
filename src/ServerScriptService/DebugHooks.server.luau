--!strict
-- DebugHooks: server-side runtime observer used by scripts/debug/dbg.
--
-- Subscribes to LogService.MessageOut + ScriptContext.Error so we capture
-- every error and warning produced by either server or replicated client
-- scripts during a Play session, with full stack traces. Exposes a small
-- _G.BabDebug API the dbg CLI shells into via execute_luau.
--
-- Tagged log lines (prefixed with [BAB-ERR] / [BAB-LIFE]) are easy to grep
-- out of the bridge's get_console_output stream from the Mac side.
--
-- This script is always active — overhead is two event hooks and a 200-entry
-- ring buffer. No remote events, no HTTP, no hot path.

local LogService = game:GetService("LogService")
local ScriptContext = game:GetService("ScriptContext")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local MAX_BUFFER = 200
local errors: { { ts: number, message: string, level: string, trace: string? } } = {}

local function push(entry: { ts: number, message: string, level: string, trace: string? })
	table.insert(errors, entry)
	while #errors > MAX_BUFFER do table.remove(errors, 1) end
end

-- LogService.MessageOut fires for every print/warn/error in any script.
LogService.MessageOut:Connect(function(message: string, msgType: Enum.MessageType)
	if msgType == Enum.MessageType.MessageError then
		push({ ts = os.time(), message = message, level = "error" })
		print(string.format("[BAB-ERR] %s", message))
	elseif msgType == Enum.MessageType.MessageWarning then
		push({ ts = os.time(), message = message, level = "warn" })
	end
end)

-- ScriptContext.Error gives us the full call stack for uncaught script errors.
ScriptContext.Error:Connect(function(message: string, stack: string, _src: LuaSourceContainer)
	push({ ts = os.time(), message = message, level = "error", trace = stack })
	print(string.format("[BAB-ERR] %s\n[BAB-TRACE]\n%s", message, stack))
end)

-- Lifecycle markers — useful when correlating console output with player
-- actions. Tagged so grep on [BAB-LIFE] gives a clean event timeline.
Players.PlayerAdded:Connect(function(p)
	print(string.format("[BAB-LIFE] join uid=%d name=%s", p.UserId, p.Name))
	p.CharacterAdded:Connect(function(_)
		print(string.format("[BAB-LIFE] spawn uid=%d", p.UserId))
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	print(string.format("[BAB-LIFE] leave uid=%d name=%s", p.UserId, p.Name))
end)

-- ── Public API consumed by `dbg state` and ad-hoc execute_luau probes ──
local API = {}

function API.recentErrors(limit: number?): { any }
	local n = limit or 20
	local out = {}
	for i = math.max(1, #errors - n + 1), #errors do
		table.insert(out, errors[i])
	end
	return out
end

function API.clearErrors()
	errors = {}
end

-- Snapshot a single player's full debuggable state (cash, attributes, plot,
-- planters, sell-pad mechanical health). Called by dbg sell-test and friends.
function API.playerSnapshot(player: Player): { [string]: any }
	local snap: { [string]: any } = { name = player.Name, userId = player.UserId, attributes = {} }
	for k, v in player:GetAttributes() do snap.attributes[k] = v end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash")
		if cash then snap.cash = (cash :: IntValue).Value end
	end

	local planters = {}
	for _, planter in CollectionService:GetTagged("Planter") do
		if planter:IsA("BasePart") and planter:GetAttribute("OwnerUserId") == player.UserId then
			table.insert(planters, {
				name = planter.Name,
				empty = planter:GetAttribute("IsEmpty"),
				ripe = planter:GetAttribute("Ripe"),
				species = planter:GetAttribute("PlantedSpecies"),
				plantedAt = planter:GetAttribute("PlantedAt"),
				growSeconds = planter:GetAttribute("GrowSeconds"),
			})
		end
	end
	snap.planters = planters

	local pads = {}
	for _, pad in CollectionService:GetTagged("SellPad") do
		if pad:IsA("BasePart") and pad:GetAttribute("OwnerUserId") == player.UserId then
			table.insert(pads, {
				name = pad.Name,
				canTouch = pad.CanTouch,
				canCollide = pad.CanCollide,
				wired = pad:GetAttribute("WiredSell"),
				size = string.format("%.1fx%.1fx%.1f", pad.Size.X, pad.Size.Y, pad.Size.Z),
				pos = string.format("%.1f,%.1f,%.1f", pad.Position.X, pad.Position.Y, pad.Position.Z),
			})
		end
	end
	snap.sellPads = pads

	return snap
end

-- One-shot probe: are this plot's sell pads mechanically healthy?
-- Returns "ok" or a list of failures. The dbg CLI uses this as a fast
-- regression check after editing PlotManager / PlantHandler.
function API.checkSellPads(): { ok: boolean, problems: { string } }
	local problems: { string } = {}
	local count = 0
	for _, pad in CollectionService:GetTagged("SellPad") do
		count = count + 1
		if not pad:IsA("BasePart") then
			table.insert(problems, ("pad %s is not a BasePart"):format(pad:GetFullName())); continue
		end
		if not pad.CanTouch then
			table.insert(problems, ("pad %s has CanTouch=false"):format(pad:GetFullName()))
		end
		if not pad:GetAttribute("WiredSell") then
			table.insert(problems, ("pad %s missing WiredSell attribute (PlantHandler never connected)"):format(pad:GetFullName()))
		end
		if not pad:GetAttribute("OwnerUserId") then
			table.insert(problems, ("pad %s missing OwnerUserId"):format(pad:GetFullName()))
		end
	end
	if count == 0 then table.insert(problems, "no SellPad tagged parts in workspace") end
	return { ok = #problems == 0, problems = problems }
end

_G.BabDebug = API

print("[BAB-LIFE] DebugHooks online")
