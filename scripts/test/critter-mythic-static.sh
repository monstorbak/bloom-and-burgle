#!/usr/bin/env bash
# critter-mythic-static.sh — structural regression for BAB-PHASE-3-MYTHIC-
# CEREMONY-AND-ADVISORY (2026-05-09).
#
# Verifies that:
#   1. HarvestFlow detects Mythic + fires the CritterCeremony event.
#   2. CritterCameraHooks ceremonyMythic includes screen flash + light
#      pillar + walk lock + toast.
#   3. HarvestModal upgraded from affinityFor → advisoryFor.
#   4. mythic_hatch Telemetry event fires from HarvestFlow.
#   5. Advisory copy templates pinned in lockstep across prod + mirror.
#
# Run:
#     bash scripts/test/critter-mythic-static.sh

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

echo "── 1. HarvestFlow fires Mythic ceremony ──"
check_grep '"mythic_hatch"' \
    src/ServerScriptService/Critter/HarvestFlow.luau \
    "HarvestFlow fires CritterCeremony with type=mythic_hatch"
check_grep "celestial" \
    src/ServerScriptService/Critter/HarvestFlow.luau \
    "Mythic detection includes celestial mutation"
check_grep 'Telemetry.track("mythic_hatch"' \
    src/ServerScriptService/Critter/HarvestFlow.luau \
    "mythic_hatch Telemetry event fires"

echo
echo "── 2. CritterCameraHooks Mythic ceremony elements ──"
check_grep "screenFlash" \
    src/StarterPlayerScripts/CritterCameraHooks.client.luau \
    "screenFlash overlay implemented"
check_grep "lightPillar" \
    src/StarterPlayerScripts/CritterCameraHooks.client.luau \
    "lightPillar visual implemented"
check_grep "lockWalkSpeed" \
    src/StarterPlayerScripts/CritterCameraHooks.client.luau \
    "lockWalkSpeed during freeze implemented"
check_grep "mythicToast" \
    src/StarterPlayerScripts/CritterCameraHooks.client.luau \
    "mythicToast at t+2.0s implemented"

echo
echo "── 3. HarvestModal upgraded to advisoryFor ──"
check_grep "advisoryFor" \
    src/StarterPlayerScripts/HarvestModal.client.luau \
    "HarvestModal calls CritterData.advisoryFor (richer template)"
check_grep "affinityColor" \
    src/StarterPlayerScripts/HarvestModal.client.luau \
    "HarvestModal uses class-accent color for the advisory line"

echo
echo "── 4. Advisory copy templates pinned in mirror ──"
check_file tests/critter/advisory_copy.test.luau
check_grep "thrive with" \
    src/ReplicatedStorage/Modules/CritterData.luau \
    "production asset template contains 'thrive with'"
check_grep "thrive with" \
    tests/critter/advisory_copy.test.luau \
    "test mirror's asset template contains 'thrive with'"
check_grep "may turn on you" \
    src/ReplicatedStorage/Modules/CritterData.luau \
    "production liability template contains 'may turn on you'"
check_grep "may turn on you" \
    tests/critter/advisory_copy.test.luau \
    "test mirror's liability template contains 'may turn on you'"
check_grep "Mild bonus if nurtured" \
    src/ReplicatedStorage/Modules/CritterData.luau \
    "production neutral template contains 'Mild bonus if nurtured'"
check_grep "Mild bonus if nurtured" \
    tests/critter/advisory_copy.test.luau \
    "test mirror's neutral template contains 'Mild bonus if nurtured'"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 critter-mythic structural checks: all passed"
exit 0
