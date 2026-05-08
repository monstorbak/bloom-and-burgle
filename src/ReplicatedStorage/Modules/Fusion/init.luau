--!strict
-- Fusion — minimal reactive UI primitives, API-compatible with Fusion 0.3.
--
-- Why this exists (P1.3 / ADR-6 / Architecture Eval §7): the legacy
-- Instance.new + manual mutation pattern (CashHUD = 379 LOC, ClassPickerUI =
-- 270, SellWaypointHUD = 210) is the highest-touch surface in the codebase
-- and the most expensive to iterate on. Adopting a reactive framework for
-- new UI gives us:
--   - Diff-based updates instead of imperative mutation
--   - Component reuse (a "labeled metal panel" used 6× = one component, not 6 copy-pastes)
--   - Easy A/B testing of variants
--
-- This is a hand-rolled minimal subset — NOT the real Fusion library. The
-- public surface matches Fusion 0.3 (`New`, `Value`, `Computed`, `Children`,
-- `OnEvent`) so the eventual switch to real Fusion via Wally is a
-- ModuleScript swap, not a code rewrite.
--
-- Roadmap to real Fusion: add Wally to the toolchain, depend on
-- `dphfox/fusion@0.3.x`, then `init.luau` becomes a re-export shim:
--    return require(game:GetService("ReplicatedStorage").Packages.Fusion)
--
-- ── Public API ─────────────────────────────────────────────────────────────
--
-- Fusion.Value(initial)       → reactive cell with :get() / :set(v)
-- Fusion.Computed(fn, {deps}) → derived cell, recomputes when any dep changes
-- Fusion.New(className)       → returns f(props) → Instance
--   props supports:
--     [propName] = value     -- direct property
--     [propName] = Value     -- reactive: subscribes, updates on change
--     [Fusion.OnEvent(name)] = handler
--     [Fusion.Children]      = { Instance, ... } | Instance
--
-- ── Example ────────────────────────────────────────────────────────────────
--
--   local Fusion = require(... .Fusion)
--   local cash = Fusion.Value(0)
--   local label = Fusion.New "TextLabel" {
--       Size = UDim2.fromOffset(200, 40),
--       Text = Fusion.Computed(function() return "$" .. cash:get() end, {cash}),
--       [Fusion.OnEvent("MouseButton1Click")] = function() cash:set(cash:get() + 1) end,
--   }
--   cash:set(42)  -- label.Text auto-updates to "$42"

local Fusion = {}

-- ── Value: reactive cell ──────────────────────────────────────────────────
local Value = {}
Value.__index = Value

function Value.new(initial: any)
	local self = setmetatable({
		_value = initial,
		_subs = {},
	}, Value)
	return self
end

function Value:get(): any
	return self._value
end

function Value:set(new_value: any)
	if self._value == new_value then return end  -- no-op: don't notify
	self._value = new_value
	for _, sub in self._subs do
		sub(new_value)
	end
end

-- internal: register a subscriber that fires on every set()
function Value:_subscribe(fn: (any) -> ())
	table.insert(self._subs, fn)
end

-- ── Computed: derived reactive cell ───────────────────────────────────────
local Computed = {}
Computed.__index = Computed

function Computed.new(fn: () -> any, deps: { any })
	local self = setmetatable({
		_fn = fn,
		_value = fn(),
		_subs = {},
	}, Computed)
	for _, dep in deps do
		if type(dep) == "table" and (getmetatable(dep) == Value or getmetatable(dep) == Computed) then
			(dep :: any):_subscribe(function()
				local new_value = self._fn()
				if self._value ~= new_value then
					self._value = new_value
					for _, sub in self._subs do
						sub(new_value)
					end
				end
			end)
		end
	end
	return self
end

function Computed:get(): any
	return self._value
end

function Computed:_subscribe(fn: (any) -> ())
	table.insert(self._subs, fn)
end

-- ── Sigils ────────────────────────────────────────────────────────────────
-- Children sigil: a unique table used as a property key. We use a plain
-- table with a known ID so the equality check in `New` is fast.
Fusion.Children = { __sigil = "Children" }

-- OnEvent sigil: returns a unique-per-event-name table key. Cached so
-- multiple `OnEvent("Activated")` references hash to the same key.
local OnEventCache: { [string]: any } = {}
function Fusion.OnEvent(eventName: string): any
	if not OnEventCache[eventName] then
		OnEventCache[eventName] = { __sigil = "OnEvent", name = eventName }
	end
	return OnEventCache[eventName]
end

-- ── Public constructors ───────────────────────────────────────────────────
function Fusion.Value(initial: any)
	return Value.new(initial)
end

function Fusion.Computed(fn: () -> any, deps: { any })
	return Computed.new(fn, deps)
end

local function isReactive(v: any): boolean
	if type(v) ~= "table" then return false end
	local mt = getmetatable(v)
	return mt == Value or mt == Computed
end

-- ── New: instance factory ─────────────────────────────────────────────────
function Fusion.New(className: string)
	return function(props: { [any]: any }): Instance
		local inst = Instance.new(className)

		-- Apply children FIRST so reactive Visibility/Size etc. take effect
		-- after layout (matches Fusion 0.3 semantics).
		local children = props[Fusion.Children]
		if children ~= nil then
			if typeof(children) == "Instance" then
				children.Parent = inst
			elseif type(children) == "table" then
				for _, c in children do
					if typeof(c) == "Instance" then c.Parent = inst end
				end
			end
		end

		for key, value in props do
			if key == Fusion.Children then
				continue  -- already handled
			end

			-- Sigil keys: tables with __sigil
			if type(key) == "table" and (key :: any).__sigil == "OnEvent" then
				local sig = (inst :: any)[(key :: any).name]
				if sig then
					(sig :: RBXScriptSignal):Connect(value)
				end
				continue
			end

			-- Property key (string)
			if typeof(key) == "string" then
				if isReactive(value) then
					(inst :: any)[key] = (value :: any):get();
					(value :: any):_subscribe(function(new_value: any)
						-- pcall: if Instance was destroyed, suppress the error.
						pcall(function() (inst :: any)[key] = new_value end)
					end)
				else
					(inst :: any)[key] = value
				end
			end
		end

		return inst
	end
end

-- Test seam: expose the metatables so unit tests can identify primitives
-- without poking at __index. Not for runtime use.
Fusion._ValueMT = Value
Fusion._ComputedMT = Computed

return Fusion
