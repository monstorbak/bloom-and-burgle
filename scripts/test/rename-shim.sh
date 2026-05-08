#!/usr/bin/env bash
# rename-shim.sh — verify the P1.2 / ADR-5 rename + backward-compat shim layout.
#
# Asserts:
#   1. CritterData + CritterVisuals exist as the canonical files.
#   2. PlantData.luau + PlantVisuals.luau exist as one-line shims that
#      forward to the canonical names (so out-of-tree callers don't break).
#   3. No production module require()s the legacy name — the shim is for
#      consumers we can't see, not for in-tree code that we can update.
#   4. The "Planter" CollectionService tag and the `data.plot.planters`
#      DataStore key are NOT renamed (load-bearing in saves per ADR-5).
#   5. Both CritterHandler and PlantHandler service names are registered
#      (covered separately in critter-static.sh, but we cross-check here).
#
# Run:
#     bash scripts/test/rename-shim.sh

set -uo pipefail

cd "$(dirname "$0")/../.."

failures=0
fail() { echo "❌ $1"; failures=$((failures + 1)); }
ok()   { echo "✅ $1"; }

check_file() {
    if [ -f "$1" ]; then ok "exists: $1"; else fail "missing: $1"; fi
}

check_grep() {
    if grep -q -- "$1" "$2" 2>/dev/null; then ok "$3"
    else fail "$3 — pattern not found: $1  in  $2"; fi
}

check_no_grep_in_set() {
    local pattern="$1" what="$2"; shift 2
    local hits=""
    for f in "$@"; do
        if [ -f "$f" ] && grep -q -- "$pattern" "$f" 2>/dev/null; then
            hits="$hits\n  $f"
        fi
    done
    if [ -z "$hits" ]; then
        ok "$what"
    else
        fail "$what — pattern '$pattern' found in:$(printf "$hits")"
    fi
}

echo "── 1. canonical files exist ──"
check_file src/ReplicatedStorage/Modules/CritterData.luau
check_file src/ServerScriptService/CritterVisuals.luau

echo
echo "── 2. legacy shims exist + forward correctly ──"
check_file src/ReplicatedStorage/Modules/PlantData.luau
check_file src/ServerScriptService/PlantVisuals.luau
check_grep 'require(script.Parent:WaitForChild("CritterData"))' \
    src/ReplicatedStorage/Modules/PlantData.luau \
    "PlantData.luau is a shim that requires CritterData"
check_grep 'require(script.Parent:WaitForChild("CritterVisuals"))' \
    src/ServerScriptService/PlantVisuals.luau \
    "PlantVisuals.luau is a shim that requires CritterVisuals"

echo
echo "── 3. no production code uses the legacy require paths ──"
# All in-tree consumers should use CritterData/CritterVisuals directly.
# The shims exist for out-of-tree callers we can't see.
check_no_grep_in_set 'require.*"PlantData"' \
    "no in-tree require of legacy PlantData" \
    src/ReplicatedStorage/Modules/CritterData.luau \
    src/ServerScriptService/Critter/*.luau \
    src/ServerScriptService/*.luau \
    src/ServerScriptService/*.server.luau \
    src/StarterPlayerScripts/*.luau
check_no_grep_in_set 'require.*"PlantVisuals"' \
    "no in-tree require of legacy PlantVisuals" \
    src/ServerScriptService/Critter/*.luau \
    src/ServerScriptService/Critter/*.server.luau \
    src/ServerScriptService/*.luau \
    src/ServerScriptService/*.server.luau

echo
echo "── 4. load-bearing legacy names preserved (ADR-5) ──"
# The "Planter" CollectionService tag is in DataStore saves; renaming it
# would orphan every existing player's plot.
check_grep 'CollectionService:GetTagged("Planter")' \
    src/ServerScriptService/Critter/CritterRegistry.luau \
    "Planter tag still in CritterRegistry"
check_grep 'CollectionService:GetTagged("Planter")' \
    src/ServerScriptService/Critter/HarvestFlow.luau \
    "Planter tag still in HarvestFlow"
# The `Planter_X_Z` Part name format is the slot-encoding used by saves.
check_grep "Planter_%d_%d" \
    src/ServerScriptService/Critter/CritterRegistry.luau \
    "Planter_X_Z naming preserved"
# DataStore key shape `plot.planters` and `plot.stash` stay.
check_grep "plotData.planters" \
    src/ServerScriptService/Critter/Persistence.luau \
    "DataStore plot.planters key preserved"
check_grep "plotData.stash" \
    src/ServerScriptService/Critter/Persistence.luau \
    "DataStore plot.stash key preserved"

echo
echo "── 5. dual service registration ──"
check_grep "Services.register(\"CritterHandler\"" \
    src/ServerScriptService/Critter/Persistence.luau \
    "CritterHandler registered (canonical)"
check_grep "Services.register(\"PlantHandler\"" \
    src/ServerScriptService/Critter/Persistence.luau \
    "PlantHandler registered (legacy alias)"
check_grep "CritterHandler: CritterHandlerAPI?" \
    src/ServerScriptService/Services.luau \
    "Services.luau ServiceMap exposes CritterHandler"
check_grep "PlantHandler: PlantHandlerAPI?" \
    src/ServerScriptService/Services.luau \
    "Services.luau ServiceMap still exposes PlantHandler (alias)"

echo
echo "── 6. LeaderstatsScript prefers CritterHandler with PlantHandler fallback ──"
check_grep 'Services.get("CritterHandler") or Services.get("PlantHandler")' \
    src/ServerScriptService/LeaderstatsScript.server.luau \
    "synchronous get prefers CritterHandler"
check_grep 'Services.await("CritterHandler", 5) or Services.get("PlantHandler")' \
    src/ServerScriptService/LeaderstatsScript.server.luau \
    "await also prefers CritterHandler"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures rename-shim check(s) failed"
    exit 1
fi
echo "🎉 rename-shim checks: all passed"
exit 0
