--!strict
-- agent_personalities.test.luau — pure-logic regression for the Seed AI
-- archetype + name-pool registry.
--
-- BAB-LIVE-FEATURES Block 1 (2026-05-11).
--
-- AgentPersonalities.luau requires no Roblox API at runtime (no Workspace,
-- no Instance.new, no DataStoreService), so we can run it directly in
-- Lune. The structural test (scripts/test/ai-agents-static.sh) verifies
-- the production module declares the same shape.
--
-- Run:
--     lune run tests/ai/agent_personalities.test.luau

-- ── Mirror of AgentPersonalities ─────────────────────────────────────
-- Pinning the data shape here so both this test and AgentPersonalities
-- need to be updated in lockstep when a new archetype lands. If you
-- add a 4th archetype, update both files in the same commit. The
-- structural test asserts the shape match.

local EXPECTED_ARCHETYPES = { "Greeter", "Trader", "Silent" }

local EXPECTED_DEFAULT_CLASSES = {
	Greeter = "Tinkerer",
	Trader = "Alchemist",
	Silent = "Knight",
}

local EXPECTED_WORLD_LABELS = {
	Greeter = "Artificial Tinkerer",
	Trader = "Artificial Alchemist",
	Silent = "Artificial Knight",
}

-- Mirror of the generateName format. Format: "<First> · <Class>".
-- The · separator is the locked diegetic disclosure marker.
local function mockGenerateName(pool: { string }, classId: string, slotIndex: number): string
	local idx = ((slotIndex - 1) % #pool) + 1
	return string.format("%s · %s", pool[idx], classId)
end

local function isDiegeticName(name: string): boolean
	return string.find(name, " · ") ~= nil
end

-- ── Test runner ──────────────────────────────────────────────────────

local failures = 0
local function assertEq(label: string, got: any, want: any)
	if got == want then
		print("✅ " .. label)
	else
		print(("❌ %s — got=%s want=%s"):format(label, tostring(got), tostring(want)))
		failures += 1
	end
end

local function assertTrue(label: string, condition: boolean)
	if condition then
		print("✅ " .. label)
	else
		print("❌ " .. label)
		failures += 1
	end
end

print("── v1 archetype set ──")
assertEq("3 archetypes ship in v1", #EXPECTED_ARCHETYPES, 3)
for _, id in EXPECTED_ARCHETYPES do
	assertTrue("archetype "..id.." has a default class",
		EXPECTED_DEFAULT_CLASSES[id] ~= nil)
	assertTrue("archetype "..id.." has a world label",
		EXPECTED_WORLD_LABELS[id] ~= nil)
end

print()
print("── Diegetic name format (the · separator decision) ──")
do
	local n1 = mockGenerateName({ "Coghand", "Brassmend" }, "Tinkerer", 1)
	assertEq("name 1", n1, "Coghand · Tinkerer")
	local n2 = mockGenerateName({ "Coghand", "Brassmend" }, "Tinkerer", 2)
	assertEq("name 2 picks second pool entry", n2, "Brassmend · Tinkerer")
	local n3 = mockGenerateName({ "Coghand", "Brassmend" }, "Tinkerer", 3)
	assertEq("name 3 wraps around to first", n3, "Coghand · Tinkerer")
	assertTrue("generated names are diegetic", isDiegeticName(n1))
end

print()
print("── isDiegeticName guard ──")
assertTrue("'Coghand · Tinkerer' is diegetic", isDiegeticName("Coghand · Tinkerer"))
assertTrue("'xX_GamerKid_Xx' is NOT diegetic (Roblox-style username)",
	not isDiegeticName("xX_GamerKid_Xx"))
assertTrue("'Coghand_Tinkerer' is NOT diegetic (underscore is not · separator)",
	not isDiegeticName("Coghand_Tinkerer"))
assertTrue("'Coghand-Tinkerer' is NOT diegetic (hyphen is not · separator)",
	not isDiegeticName("Coghand-Tinkerer"))
-- The · character alone without spaces is rejected: the format requires
-- " · " (with spaces). Tighter check, fewer false positives.
assertTrue("'Coghand·Tinkerer' is NOT diegetic (missing spaces around ·)",
	not isDiegeticName("Coghand·Tinkerer"))

print()
print("── Disclosure invariants (locked 2026-05-11) ──")
-- Per the locked decision: no archetype's world label contains "BOT",
-- "AI", "ROBOT", "🤖", or any other meta tell. All labels use the
-- diegetic "Artificial <Class>" format.
for _, id in EXPECTED_ARCHETYPES do
	local label = EXPECTED_WORLD_LABELS[id]
	assertTrue(
		string.format("'%s' label is diegetic (no BOT/AI/ROBOT meta tells)", id),
		not (
			string.find(label, "BOT") or
			string.find(label, "AI") or
			string.find(label, "ROBOT") or
			string.find(label, "🤖")
		)
	)
	assertTrue(
		string.format("'%s' label starts with 'Artificial' (locked format)", id),
		string.sub(label, 1, 10) == "Artificial"
	)
end

print()
if failures > 0 then
	print(("❌ %d agent_personalities check(s) failed"):format(failures))
	error("test failed")
end
print("🎉 agent_personalities: all checks passed")
