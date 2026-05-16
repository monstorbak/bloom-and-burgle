#!/usr/bin/env bash
# ai-agents-static.sh — structural regression for BAB-LIVE-FEATURES Block 1
# (Seed AI v1, 2026-05-11).
#
# Verifies:
#   1. All 6 new files exist (AiTypes + 5 server-side modules)
#   2. AgentPersonalities ships exactly 3 v1 archetypes (Greeter, Trader, Silent)
#   3. AgentVisuals builds the 3-layer diegetic disclosure (rig + name + proximity label)
#   4. AgentPlots builds the AgentDistrict at z=-120 (south of plaza)
#   5. AgentBrain implements the idle/plant/wait/harvest state machine
#   6. init.server.luau spawns N agents at boot via task.defer
#   7. The locked disclosure decision is respected: NO 🤖 prefix in name generation
#   8. Name format uses U+00B7 · separator (the diegetic disclosure marker)
#   9. AI is NOT registered as a Roblox Player (uses Humanoid model only)
#  10. Planters built by AgentPlots get the "Planter" CollectionService tag
#      so GrowLoop picks them up automatically
#
# Run:
#     bash scripts/test/ai-agents-static.sh

set -uo pipefail
cd "$(dirname "$0")/../.."

failures=0
fail() { echo "❌ $1"; failures=$((failures + 1)); }
ok()   { echo "✅ $1"; }

check_grep() {
    local pattern="$1" path="$2" what="$3"
    if grep -q -- "$pattern" "$path" 2>/dev/null; then
        ok "$what"
    else
        fail "$what — pattern not found: $pattern  in  $path"
    fi
}

check_file() {
    local path="$1"
    if [ -f "$path" ]; then ok "exists: $path"; else fail "missing: $path"; fi
}

check_no_match() {
    local pattern="$1" path="$2" what="$3"
    if grep -q -- "$pattern" "$path" 2>/dev/null; then
        fail "$what — pattern FOUND (should NOT be present): $pattern  in  $path"
    else
        ok "$what"
    fi
}

echo "── 1. New files exist ──"
check_file src/ReplicatedStorage/Modules/AiTypes.luau
check_file src/ServerScriptService/AiAgents/AgentPersonalities.luau
check_file src/ServerScriptService/AiAgents/AgentVisuals.luau
check_file src/ServerScriptService/AiAgents/AgentPlots.luau
check_file src/ServerScriptService/AiAgents/AgentBrain.luau
check_file src/ServerScriptService/AiAgents/init.server.luau

echo
echo "── 2. AgentPersonalities ships exactly 3 v1 archetypes ──"
check_grep 'Greeter = {' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "AgentPersonalities defines Greeter archetype"
check_grep 'Trader = {' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "AgentPersonalities defines Trader archetype"
check_grep 'Silent = {' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "AgentPersonalities defines Silent archetype"
check_grep '"Greeter", "Trader", "Silent"' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "archetypeIds() returns exactly the 3 v1 archetypes"

echo
echo "── 3. AgentVisuals builds the 3-layer diegetic disclosure ──"
check_grep 'attachHeadAccessory' \
    src/ServerScriptService/AiAgents/AgentVisuals.luau \
    "Layer 1: class-themed head accessory (rig distinction)"
check_grep 'attachChestAccessory' \
    src/ServerScriptService/AiAgents/AgentVisuals.luau \
    "Layer 1: class-themed chest accessory (rig distinction)"
check_grep '"NameLabel"' \
    src/ServerScriptService/AiAgents/AgentVisuals.luau \
    "Layer 2: always-visible stylized name BillboardGui"
check_grep '"RoleLabel"' \
    src/ServerScriptService/AiAgents/AgentVisuals.luau \
    "Layer 3: proximity-revealed RoleLabel (Artificial X)"
check_grep 'MaxDistance = 20' \
    src/ServerScriptService/AiAgents/AgentVisuals.luau \
    "Layer 3: RoleLabel MaxDistance = 20 studs (proximity reveal)"

echo
echo "── 4. AgentPlots builds the AgentDistrict ──"
check_grep 'DISTRICT_ANCHOR = Vector3.new(0, 0, -120)' \
    src/ServerScriptService/AiAgents/AgentPlots.luau \
    "AgentDistrict anchored at z=-120 (south of plaza)"
check_grep '"AgentDistrict"' \
    src/ServerScriptService/AiAgents/AgentPlots.luau \
    "AgentDistrict Model named correctly"
check_grep '"ARTIFICIAL VILLAGERS' \
    src/ServerScriptService/AiAgents/AgentPlots.luau \
    "District has Antique-font 'ARTIFICIAL VILLAGERS' sign (4th disclosure layer)"
check_grep 'CollectionService:AddTag(body, "Planter")' \
    src/ServerScriptService/AiAgents/AgentPlots.luau \
    "Agent planters tagged 'Planter' so GrowLoop picks them up"
check_grep 'OwnerAgentId' \
    src/ServerScriptService/AiAgents/AgentPlots.luau \
    "Agent planters use OwnerAgentId (not OwnerUserId — blocks player harvest)"

echo
echo "── 5. AgentBrain state machine ──"
check_grep 'function tickBrain' \
    src/ServerScriptService/AiAgents/AgentBrain.luau \
    "AgentBrain has tickBrain function (state machine dispatch)"
check_grep '"walking_to_planter"' \
    src/ServerScriptService/AiAgents/AgentBrain.luau \
    "AgentBrain state machine includes walking_to_planter"
check_grep '"planting"' \
    src/ServerScriptService/AiAgents/AgentBrain.luau \
    "AgentBrain state machine includes planting"
check_grep '"waiting"' \
    src/ServerScriptService/AiAgents/AgentBrain.luau \
    "AgentBrain state machine includes waiting (grow phase)"
check_grep '"harvesting"' \
    src/ServerScriptService/AiAgents/AgentBrain.luau \
    "AgentBrain state machine includes harvesting"
check_grep 'function M.tick' \
    src/ServerScriptService/AiAgents/AgentBrain.luau \
    "AgentBrain.tick() is the heartbeat entrypoint"

echo
echo "── 6. init.server.luau spawns agents at boot ──"
check_grep 'TARGET_AGENT_COUNT = 4' \
    src/ServerScriptService/AiAgents/init.server.luau \
    "init spawns TARGET_AGENT_COUNT = 4 agents (v1 fixed count)"
check_grep 'task.defer' \
    src/ServerScriptService/AiAgents/init.server.luau \
    "init deferred to next tick (lets DataStore/Services settle)"
check_grep 'AgentPlots.buildDistrict()' \
    src/ServerScriptService/AiAgents/init.server.luau \
    "init builds the district before spawning agents"
check_grep 'RunService.Heartbeat:Connect' \
    src/ServerScriptService/AiAgents/init.server.luau \
    "init wires the brain tick loop to Heartbeat"
check_grep 'BRAIN_TICK_INTERVAL = 0.5' \
    src/ServerScriptService/AiAgents/init.server.luau \
    "init throttles brain ticks to 0.5s (2Hz, not 60Hz)"

echo
echo "── 7. Locked decision: NO 🤖 prefix in v1 disclosure ──"
check_no_match '🤖' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "AgentPersonalities does NOT use 🤖 prefix (dropped 2026-05-11)"
check_no_match '🤖' \
    src/ServerScriptService/AiAgents/AgentVisuals.luau \
    "AgentVisuals does NOT use 🤖 prefix"
check_no_match '🤖' \
    src/ServerScriptService/AiAgents/init.server.luau \
    "init.server does NOT use 🤖 prefix"

echo
echo "── 8. Name format uses · separator (U+00B7, the diegetic marker) ──"
check_grep ' · ' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "Name format uses the · separator (U+00B7)"
check_grep 'function M.isDiegeticName' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "Name validator (isDiegeticName) is exported"

echo
echo "── 9. AI is NOT a Roblox Player ──"
check_no_match 'Players:CreatePlayer' \
    src/ServerScriptService/AiAgents/AgentVisuals.luau \
    "AgentVisuals does NOT try to fake a Roblox Player object"
check_grep 'Instance.new("Humanoid")' \
    src/ServerScriptService/AiAgents/AgentVisuals.luau \
    "Agent is a Humanoid NPC (not a Player)"

echo
echo "── 10. Diegetic disclosure invariants ──"
check_grep '"Artificial Tinkerer"' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "Greeter archetype proximity label is 'Artificial Tinkerer'"
check_grep '"Artificial Alchemist"' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "Trader archetype proximity label is 'Artificial Alchemist'"
check_grep '"Artificial Knight"' \
    src/ServerScriptService/AiAgents/AgentPersonalities.luau \
    "Silent archetype proximity label is 'Artificial Knight'"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 ai-agents structural checks: all passed"
exit 0
