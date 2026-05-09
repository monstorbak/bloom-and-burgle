#!/usr/bin/env bash
# critter-rigs-static.sh — structural regression for the rig system
# (BAB-PHASE-1-CRITTER-RIGS, 2026-05-09).
#
# Verifies that:
#   1. CritterRigs module exists + exports the expected API.
#   2. The 4 headline species in CritterData have rigSupport = true.
#   3. CritterVisuals dispatches to the rig builder via the rigSupport flag.
#   4. CritterCameraHooks + the CritterCeremony RemoteEvent wiring exists.
#   5. The mirror in tests/critter/rigs.test.luau pins the same form
#      thresholds as the production module.
#
# Run:
#     bash scripts/test/critter-rigs-static.sh

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
check_file src/ReplicatedStorage/Modules/CritterRigs.luau
check_file src/StarterPlayerScripts/CritterCameraHooks.client.luau
check_file tests/critter/rigs.test.luau

echo
echo "── 2. CritterRigs API surface ──"
check_grep "function M.formForProgress" \
    src/ReplicatedStorage/Modules/CritterRigs.luau \
    "CritterRigs.formForProgress exported"
check_grep "function M.has" \
    src/ReplicatedStorage/Modules/CritterRigs.luau \
    "CritterRigs.has exported"
check_grep "function M.profile" \
    src/ReplicatedStorage/Modules/CritterRigs.luau \
    "CritterRigs.profile exported"
check_grep "function M.hasFeature" \
    src/ReplicatedStorage/Modules/CritterRigs.luau \
    "CritterRigs.hasFeature exported"

echo
echo "── 3. Form-progress thresholds pinned in lockstep (mirror == prod) ──"
check_grep "M.HATCH_CUTE_END = 0.25" \
    src/ReplicatedStorage/Modules/CritterRigs.luau \
    "production HATCH_CUTE_END pinned at 0.25"
check_grep "M.JUVENILE_END = 0.75" \
    src/ReplicatedStorage/Modules/CritterRigs.luau \
    "production JUVENILE_END pinned at 0.75"
check_grep "HATCH_CUTE_END = 0.25" \
    tests/critter/rigs.test.luau \
    "test mirrors HATCH_CUTE_END at 0.25"
check_grep "JUVENILE_END = 0.75" \
    tests/critter/rigs.test.luau \
    "test mirrors JUVENILE_END at 0.75"

echo
echo "── 4. CritterRigs.RIGS registers the 4 headline species ──"
for species in mech_hound coal_drake brass_beetle sky_wyvern; do
    check_grep "${species} = {" \
        src/ReplicatedStorage/Modules/CritterRigs.luau \
        "${species} rig profile registered"
done

echo
echo "── 5. CritterData has rigSupport = true on the same 4 species ──"
for species in mech_hound coal_drake brass_beetle sky_wyvern; do
    # Pull the species block + look for rigSupport=true within it.
    block=$(awk -v sp="${species} = {" '$0 ~ sp,/^\t} :: CritterSpec,/' \
        src/ReplicatedStorage/Modules/CritterData.luau)
    if echo "$block" | grep -q "rigSupport = true"; then
        ok "${species} has rigSupport = true in CritterData"
    else
        fail "${species} block in CritterData does NOT have rigSupport = true"
    fi
done

echo
echo "── 6. CritterVisuals dispatches to rig builder for opted-in species ──"
check_grep "species.rigSupport" \
    src/ServerScriptService/CritterVisuals.luau \
    "CritterVisuals.create checks species.rigSupport"
check_grep "CritterRigs.has" \
    src/ServerScriptService/CritterVisuals.luau \
    "CritterVisuals.create dispatches via CritterRigs.has"
check_grep "RigSupport" \
    src/ServerScriptService/CritterVisuals.luau \
    "CritterVisuals sets RigSupport attribute on rig models"
check_grep "CritterRigs.formForProgress" \
    src/ServerScriptService/CritterVisuals.luau \
    "CritterVisuals.update detects form transitions via formForProgress"

echo
echo "── 7. Telemetry: rig_form_transition event fires on transition ──"
check_grep '"rig_form_transition"' \
    src/ServerScriptService/CritterVisuals.luau \
    "rig_form_transition Telemetry event fired"

echo
echo "── 8. CritterCeremony RemoteEvent + camera hooks wiring ──"
check_grep "CritterCeremony" \
    src/ServerScriptService/CritterVisuals.luau \
    "CritterVisuals lazy-creates CritterCeremony RemoteEvent"
check_grep "CritterCeremony" \
    src/StarterPlayerScripts/CritterCameraHooks.client.luau \
    "CritterCameraHooks listens on CritterCeremony"
check_grep "mythic_hatch" \
    src/StarterPlayerScripts/CritterCameraHooks.client.luau \
    "CritterCameraHooks handles mythic_hatch ceremony"
check_grep "escape_burst" \
    src/StarterPlayerScripts/CritterCameraHooks.client.luau \
    "CritterCameraHooks handles escape_burst ceremony"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 critter-rigs structural checks: all passed"
exit 0
