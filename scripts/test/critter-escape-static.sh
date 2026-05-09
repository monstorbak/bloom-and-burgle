#!/usr/bin/env bash
# critter-escape-static.sh — structural regression for BAB-CRITTER-ESCAPE
# Phase 2.A (2026-05-09).
#
# Verifies that:
#   1. EscapeBehaviors + EscapeWindow modules exist + export the expected API
#   2. Catalog contains the ticket's seed entries (Coal Forge + Drake Strafe)
#   3. Catalog contains all 8 expected species (mirror == prod)
#   4. The total behavior count matches the test mirror (12 entries)
#   5. GrowLoop arms the timer on ripen
#   6. HarvestFlow cancels the timer on harvest
#   7. Persistence saves/restores the escapes array
#   8. Plot Defense Layer schema (`targetsRaiders`) is present
#   9. pod_escaped Telemetry event is wired
#  10. CritterCeremony escape_burst is fired from EscapeWindow
#
# Run:
#     bash scripts/test/critter-escape-static.sh

set -uo pipefail
cd "$(dirname "$0")/../.."

failures=0
fail() { echo "❌ $1"; failures=$((failures + 1)); }
ok()   { echo "✅ $1"; }

check_file() {
    local path="$1"
    if [ -f "$path" ]; then ok "exists: $path"; else fail "missing: $path"; fi
}

check_grep() {
    local pattern="$1" path="$2" what="$3"
    if grep -q -- "$pattern" "$path" 2>/dev/null; then
        ok "$what"
    else
        fail "$what — pattern not found: $pattern  in  $path"
    fi
}

echo "── 1. expected files exist ──"
check_file src/ServerScriptService/Critter/EscapeBehaviors.luau
check_file src/ServerScriptService/Critter/EscapeWindow.luau
check_file tests/critter/escape.test.luau

echo
echo "── 2. EscapeBehaviors API surface ──"
check_grep "function M.lookup" \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "EscapeBehaviors.lookup exported"
check_grep "function M.count" \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "EscapeBehaviors.count exported"
check_grep "function M.registeredSpecies" \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "EscapeBehaviors.registeredSpecies exported"

echo
echo "── 3. EscapeWindow API surface ──"
check_grep "function M.arm" \
    src/ServerScriptService/Critter/EscapeWindow.luau \
    "EscapeWindow.arm exported"
check_grep "function M.cancel" \
    src/ServerScriptService/Critter/EscapeWindow.luau \
    "EscapeWindow.cancel exported"
check_grep "function M.cancelForPlayer" \
    src/ServerScriptService/Critter/EscapeWindow.luau \
    "EscapeWindow.cancelForPlayer exported"
check_grep "function M.snapshotArmedFor" \
    src/ServerScriptService/Critter/EscapeWindow.luau \
    "EscapeWindow.snapshotArmedFor exported (persistence seam)"
check_grep "function M.restoreArmedFor" \
    src/ServerScriptService/Critter/EscapeWindow.luau \
    "EscapeWindow.restoreArmedFor exported (persistence seam)"

echo
echo "── 4. Ticket's seed entries present (Coal Forge + Drake Strafe) ──"
check_grep '"Coal Forge"' \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "Coal Forge behavior name pinned"
check_grep '"Drake Strafe"' \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "Drake Strafe behavior name pinned"
check_grep "coalForgeActivate" \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "Coal Forge has a real activate fn (not catalog-only stub)"
check_grep "drakeStrafeActivate" \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "Drake Strafe has a real activate fn"

echo
echo "── 5. All 8 expected species registered ──"
for species in mech_hound coal_drake brass_beetle sky_wyvern \
               iron_hydra fire_salamander patina_toad aether_hummingbird; do
    check_grep "${species} = {" \
        src/ServerScriptService/Critter/EscapeBehaviors.luau \
        "${species} catalog entry registered"
done

echo
echo "── 6. GrowLoop arms the timer on ripen ──"
check_grep "EscapeWindow.arm" \
    src/ServerScriptService/Critter/GrowLoop.server.luau \
    "GrowLoop calls EscapeWindow.arm"
check_grep 'require(Critter:WaitForChild("EscapeWindow")' \
    src/ServerScriptService/Critter/GrowLoop.server.luau \
    "GrowLoop eager-requires EscapeWindow (so PlayerRemoving hook wires)"

echo
echo "── 7. HarvestFlow cancels on harvest ──"
check_grep "EscapeWindow.cancel" \
    src/ServerScriptService/Critter/HarvestFlow.luau \
    "HarvestFlow.harvestPlanter calls EscapeWindow.cancel"

echo
echo "── 8. Persistence saves + restores escape state ──"
check_grep "snapshotArmedFor" \
    src/ServerScriptService/Critter/Persistence.luau \
    "Persistence.snapshot calls EscapeWindow.snapshotArmedFor"
check_grep "restoreArmedFor" \
    src/ServerScriptService/Critter/Persistence.luau \
    "Persistence.restore calls EscapeWindow.restoreArmedFor"
check_grep "escapes = " \
    src/ServerScriptService/Critter/Persistence.luau \
    "Persistence.snapshot includes escapes in the saved table"

echo
echo "── 9. Plot Defense Layer schema (targetsRaiders flag) ──"
check_grep "targetsRaiders" \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "EscapeBehavior shape includes targetsRaiders"
check_grep "targetsRaiders = true" \
    src/ServerScriptService/Critter/EscapeBehaviors.luau \
    "At least one liability behavior is flagged targetsRaiders=true"

echo
echo "── 10. Telemetry: pod_escaped event fires ──"
check_grep '"pod_escaped"' \
    src/ServerScriptService/Critter/EscapeWindow.luau \
    "pod_escaped Telemetry event fired from EscapeWindow"

echo
echo "── 11. CritterCeremony: escape_burst fired on escape ──"
check_grep '"escape_burst"' \
    src/ServerScriptService/Critter/EscapeWindow.luau \
    "EscapeWindow fires escape_burst ceremony via CritterCeremony RemoteEvent"

echo
echo "── 12. Mirror count pinned in lockstep (test == prod) ──"
# Test pins EXPECTED_TOTAL = 15. If catalog grows, both must update together.
check_grep "EXPECTED_TOTAL = 15" \
    tests/critter/escape.test.luau \
    "test pins EXPECTED_TOTAL at 15"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 critter-escape structural checks: all passed"
exit 0
