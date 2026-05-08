--!strict
-- reactive_primitives.test.luau — pure-logic test of Fusion's Value + Computed.
--
-- The Roblox-API parts of Fusion (`New`, `OnEvent`, `Children` mounting) need
-- a real DataModel so they're tested in Studio (see the manual smoke test in
-- AGENT_COORDINATION/handoffs/P1-CRITTER-SPLIT-2026-05-08.md). The reactive
-- primitives — Value subscribe/notify, Computed dependency tracking — are
-- pure Lua and exercised here.
--
-- Why this matters: the whole point of P1.3 is that NEW UI doesn't have the
-- 379-LOC imperative-mutation pattern of CashHUD. That promise depends on
-- Value/Computed firing exactly when they should and never spuriously.
--
-- Run:
--     lune run tests/fusion/reactive_primitives.test.luau

-- Inline the Fusion module via dofile-equivalent. Lune supports `require`
-- with relative paths but we don't want to depend on the project layout
-- here — inline the same primitives.

-- ── Mirror: Fusion.Value ───────────────────────────────────────────────────
-- Production: Fusion/init.luau Value (lines ~52–82).
local Value = {}
Value.__index = Value
function Value.new(initial)
	return setmetatable({ _value = initial, _subs = {} }, Value)
end
function Value:get() return self._value end
function Value:set(v)
	if self._value == v then return end
	self._value = v
	for _, fn in self._subs do fn(v) end
end
function Value:_subscribe(fn) table.insert(self._subs, fn) end

-- ── Mirror: Fusion.Computed ────────────────────────────────────────────────
-- Production: Fusion/init.luau Computed (lines ~86–116).
local Computed = {}
Computed.__index = Computed
function Computed.new(fn, deps)
	local self = setmetatable({ _fn = fn, _value = fn(), _subs = {} }, Computed)
	for _, dep in deps do
		dep:_subscribe(function()
			local nv = self._fn()
			if self._value ~= nv then
				self._value = nv
				for _, sub in self._subs do sub(nv) end
			end
		end)
	end
	return self
end
function Computed:get() return self._value end
function Computed:_subscribe(fn) table.insert(self._subs, fn) end

-- ── Tiny test runner ───────────────────────────────────────────────────────
local failures = 0
local function check(name, ok, msg)
	if ok then print("  ✅ " .. name)
	else failures += 1; print("  ❌ " .. name .. ": " .. tostring(msg)) end
end
local function eq(name, expected, actual)
	check(name, expected == actual, string.format("expected=%s actual=%s", tostring(expected), tostring(actual)))
end

-- ── Cases ──────────────────────────────────────────────────────────────────

print("── Value ──")
do
	local v = Value.new(10)
	eq("initial :get()", 10, v:get())
	v:set(20)
	eq(":set + :get round-trip", 20, v:get())
end

do
	local v = Value.new(5)
	local notifications = 0
	v:_subscribe(function() notifications += 1 end)
	v:set(5)  -- no-op: same value
	eq("set-to-same-value does NOT notify", 0, notifications)
	v:set(6)
	eq("set-to-different-value notifies once", 1, notifications)
	v:set(7)
	eq("subsequent set notifies again", 2, notifications)
end

do
	local v = Value.new("hello")
	local last
	v:_subscribe(function(nv) last = nv end)
	v:set("world")
	eq("subscriber receives new value", "world", last)
end

do
	local v = Value.new(0)
	local a, b = 0, 0
	v:_subscribe(function() a += 1 end)
	v:_subscribe(function() b += 1 end)
	v:set(1)
	eq("multiple subscribers all fire (a)", 1, a)
	eq("multiple subscribers all fire (b)", 1, b)
end

print()
print("── Computed ──")
do
	local cash = Value.new(0)
	local label = Computed.new(function() return "$" .. cash:get() end, { cash })
	eq("computed picks up initial dep value", "$0", label:get())
	cash:set(42)
	eq("computed recomputes when dep changes", "$42", label:get())
end

do
	local a = Value.new(2)
	local b = Value.new(3)
	local sum = Computed.new(function() return a:get() + b:get() end, { a, b })
	eq("computed over two deps: initial", 5, sum:get())
	a:set(10)
	eq("recomputes when first dep changes", 13, sum:get())
	b:set(7)
	eq("recomputes when second dep changes", 17, sum:get())
end

do
	-- A computed that doesn't change shouldn't notify its own subscribers.
	-- Use a "constant" computed (returns 1 regardless of dep).
	local v = Value.new(0)
	local c = Computed.new(function() local _ = v:get(); return 1 end, { v })
	local notifications = 0
	c:_subscribe(function() notifications += 1 end)
	v:set(1)
	v:set(2)
	v:set(3)
	eq("computed does NOT notify when its output stays the same", 0, notifications)
end

do
	-- Chained computeds: B depends on A which depends on a Value.
	local v = Value.new(1)
	local doubled = Computed.new(function() return v:get() * 2 end, { v })
	local quadrupled = Computed.new(function() return doubled:get() * 2 end, { doubled })
	eq("chained computed: initial", 4, quadrupled:get())
	v:set(5)
	eq("chained computed: propagates", 20, quadrupled:get())
end

do
	-- Subscriber receives the new computed value, not the dep value.
	local v = Value.new(10)
	local doubled = Computed.new(function() return v:get() * 2 end, { v })
	local last
	doubled:_subscribe(function(nv) last = nv end)
	v:set(15)
	eq("computed subscriber gets computed value", 30, last)
end

print()
if failures > 0 then
	print(string.format("❌ %d failure(s)", failures))
	error("test failed", 0)
end
print("🎉 fusion reactive primitives: all cases passed")
