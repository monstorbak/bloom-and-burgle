--!strict
-- Services: typed registry that replaces the server-side _G handle pattern
-- per ADR-1 (Bloom&Burgle_Architecture_Eval.md).
--
-- Why this exists: PlantHandler / PlotManager / DebugHooks are .server.luau
-- Scripts (Rojo locks them in as Scripts because they need top-level event
-- subscriptions like Players.PlayerAdded), so they can't be require()'d
-- directly. The legacy bridge was `_G.PlantHandler = api`; consumers
-- polled `_G.PlantHandler` with task.wait. Three problems:
--   1. No type safety — `_G.PlantHandler.snapshot` had no autocomplete.
--   2. Load-order race — polling `_G[name]` for up to 5s on cold boot.
--   3. push-to-studio destroys + recreates Scripts mid-Play, leaving _G
--      with a dangling table whose closures point at a dead Script.
--
-- This module fixes (1) and (2). It does NOT fix (3) — that's a tooling
-- bug in push-to-studio.sh that needs a Play-mode safety check (P1 item).
--
-- Usage:
--   -- in PlantHandler.server.luau, after building API:
--   local Services = require(game.ServerScriptService:WaitForChild("Services"))
--   Services.register("PlantHandler", api)
--
--   -- in LeaderstatsScript:
--   local plantHandler = Services.await("PlantHandler", 5)
--   if plantHandler then plantHandler.snapshot(player) end

local Services = {}

export type PlantHandlerAPI = {
	snapshot: (Player) -> { [string]: any },
	restore: (Player, { [string]: any }?, number?) -> (),
	snapshotStable: ((Player) -> { any })?,
}

export type PlotManagerAPI = {
	rebuildFromSave: (Player, number) -> Model?,
}

export type ServiceMap = {
	PlantHandler: PlantHandlerAPI?,
	PlotManager: PlotManagerAPI?,
}

-- Backing storage. Keyed by service name.
local registry: { [string]: any } = {}
-- Per-name BindableEvent so awaiters wake instantly on register.
local events: { [string]: BindableEvent } = {}

local function getEvent(name: string): BindableEvent
	if not events[name] then
		local e = Instance.new("BindableEvent")
		e.Name = "Service_" .. name
		events[name] = e
	end
	return events[name]
end

-- Register a service by name. Wakes any pending await calls.
-- Idempotent on re-registration (warns + overwrites).
function Services.register(name: string, api: any)
	if registry[name] then
		warn(string.format("[Services] %s re-registered — overwriting", name))
	end
	registry[name] = api
	-- Fire any sleeping awaits. Wrap in pcall in case the BindableEvent
	-- has been GC'd (shouldn't happen — events table holds a reference).
	pcall(function() getEvent(name):Fire(api) end)
	print(string.format("[BAB-LIFE] Services.register %s", name))
end

-- Synchronous get. Returns nil if not registered.
function Services.get(name: string): any
	return registry[name]
end

-- Yields the calling thread until the service registers OR timeout
-- expires. Returns the API (or nil on timeout). Defaults to 10s timeout.
function Services.await(name: string, timeoutSeconds: number?): any
	if registry[name] then return registry[name] end
	local timeout = timeoutSeconds or 10
	local event = getEvent(name)
	local result: any = nil
	local done = false
	local conn: RBXScriptConnection?
	conn = event.Event:Connect(function(api)
		result = api
		done = true
	end)
	local deadline = os.clock() + timeout
	while not done and os.clock() < deadline do
		task.wait(0.05)
	end
	if conn then conn:Disconnect() end
	-- Final check in case it registered between the connect and the loop.
	return result or registry[name]
end

-- Returns a snapshot of currently-registered service names. Useful for
-- debug introspection via _G.BabDebug.services().
function Services.list(): { string }
	local out: { string } = {}
	for name in pairs(registry) do table.insert(out, name) end
	table.sort(out)
	return out
end

return Services
