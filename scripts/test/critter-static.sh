#!/usr/bin/env bash
# critter-static.sh — structural regression check for the P1.1 / ADR-4 split.
#
# Verifies that:
#   1. Each expected module / Script file exists.
#   2. Each module exports the function names other modules require().
#   3. EconomyPad's payout-cap constants match what economy_logic.test.luau
#      pins (so the logic test stays in lockstep).
#   4. The legacy PlantHandler.server.luau is gone.
#   5. Persistence still registers the "PlantHandler" service name (the
#      Services.luau type binding for LeaderstatsScript callers).
#
# Run:
#     bash scripts/test/critter-static.sh

set -uo pipefail

cd "$(dirname "$0")/../.."

failures=0
fail() {
    echo "❌ $1"
    failures=$((failures + 1))
}
ok() {
    echo "✅ $1"
}

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

check_no_grep() {
    local pattern="$1" path="$2" what="$3"
    if [ ! -e "$path" ]; then
        ok "$what (file absent)"
        return
    fi
    if grep -q -- "$pattern" "$path" 2>/dev/null; then
        fail "$what — unwanted pattern found: $pattern  in  $path"
    else
        ok "$what"
    fi
}

echo "── 1. expected files exist ──"
check_file src/ServerScriptService/Critter/CritterRegistry.luau
check_file src/ServerScriptService/Critter/HarvestFlow.luau
check_file src/ServerScriptService/Critter/EconomyPad.luau
check_file src/ServerScriptService/Critter/Persistence.luau
check_file src/ServerScriptService/Critter/GrowLoop.server.luau
check_file src/ServerScriptService/Critter/SellPad.server.luau
check_file src/ServerScriptService/Critter/ScrapPad.server.luau
check_file src/ServerScriptService/Critter/ProximityPulse.server.luau
check_file src/ServerScriptService/Critter/PlantingFlow.server.luau

echo
echo "── 2. legacy PlantHandler.server.luau removed ──"
if [ -f src/ServerScriptService/PlantHandler.server.luau ]; then
    fail "legacy PlantHandler.server.luau still exists — should have been deleted by P1.1"
else
    ok "legacy PlantHandler.server.luau removed"
fi

echo
echo "── 3. CritterRegistry exports ──"
check_grep "function CritterRegistry.getInv" \
    src/ServerScriptService/Critter/CritterRegistry.luau "getInv exported"
check_grep "function CritterRegistry.findPlanterForSlot" \
    src/ServerScriptService/Critter/CritterRegistry.luau "findPlanterForSlot exported"
check_grep "function CritterRegistry.slotForPlanterName" \
    src/ServerScriptService/Critter/CritterRegistry.luau "slotForPlanterName exported"
check_grep "function CritterRegistry.addToInventory" \
    src/ServerScriptService/Critter/CritterRegistry.luau "addToInventory exported"
check_grep "function CritterRegistry.clearInventoryFor" \
    src/ServerScriptService/Critter/CritterRegistry.luau "clearInventoryFor exported"

echo
echo "── 4. HarvestFlow exports ──"
check_grep "function HarvestFlow.harvestPlanter" \
    src/ServerScriptService/Critter/HarvestFlow.luau "harvestPlanter exported"
check_grep "function HarvestFlow.harvestAllRipeForPlayer" \
    src/ServerScriptService/Critter/HarvestFlow.luau "harvestAllRipeForPlayer exported"
check_grep "function HarvestFlow.harvestOffline" \
    src/ServerScriptService/Critter/HarvestFlow.luau "harvestOffline exported"
check_grep "function HarvestFlow.buildSproutFor" \
    src/ServerScriptService/Critter/HarvestFlow.luau "buildSproutFor exported"

echo
echo "── 5. EconomyPad exports + invariants ──"
check_grep "function EconomyPad.convert" \
    src/ServerScriptService/Critter/EconomyPad.luau "convert exported"
check_grep "function EconomyPad.checkSellCooldown" \
    src/ServerScriptService/Critter/EconomyPad.luau "checkSellCooldown exported"
check_grep "function EconomyPad.checkScrapCooldown" \
    src/ServerScriptService/Critter/EconomyPad.luau "checkScrapCooldown exported"
check_grep "function EconomyPad.clearCooldownsFor" \
    src/ServerScriptService/Critter/EconomyPad.luau "clearCooldownsFor exported"

# Pinned constants — economy_logic.test.luau hard-codes these. If they
# diverge from EconomyPad.luau the test goes stale silently. Re-pin both
# atomically when the cap changes.
check_grep "MAX_SELL_PAYOUT = 5000000" \
    src/ServerScriptService/Critter/EconomyPad.luau "MAX_SELL_PAYOUT pinned at 5,000,000"
check_grep "MAX_SCRAP_PAYOUT = 100000" \
    src/ServerScriptService/Critter/EconomyPad.luau "MAX_SCRAP_PAYOUT pinned at 100,000"
check_grep "MAX_SELL_PAYOUT  = 5000000" \
    tests/critter/economy_logic.test.luau "test mirrors MAX_SELL_PAYOUT"
check_grep "MAX_SCRAP_PAYOUT = 100000" \
    tests/critter/economy_logic.test.luau "test mirrors MAX_SCRAP_PAYOUT"

echo
echo "── 6. Persistence registers both CritterHandler + PlantHandler services (P1.2/ADR-5) ──"
check_grep "Services.register(\"CritterHandler\"" \
    src/ServerScriptService/Critter/Persistence.luau \
    "Persistence registers CritterHandler (canonical)"
check_grep "Services.register(\"PlantHandler\"" \
    src/ServerScriptService/Critter/Persistence.luau \
    "Persistence registers PlantHandler (legacy alias)"
check_grep "snapshot = Persistence.snapshot" \
    src/ServerScriptService/Critter/Persistence.luau "snapshot exported in API"
check_grep "restore = Persistence.restore" \
    src/ServerScriptService/Critter/Persistence.luau "restore exported in API"

echo
echo "── 7. GrowLoop eagerly loads Persistence (so registration runs on boot) ──"
check_grep "require(Critter:WaitForChild(\"Persistence\")" \
    src/ServerScriptService/Critter/GrowLoop.server.luau \
    "GrowLoop requires Persistence eagerly"

echo
echo "── 8. Pad scripts call EconomyPad.convert with the right kind ──"
check_grep "EconomyPad.convert(player, \"sell\", \"touched\")" \
    src/ServerScriptService/Critter/SellPad.server.luau "SellPad uses sell+touched"
check_grep "EconomyPad.convert(player, \"scrap\", \"touched\")" \
    src/ServerScriptService/Critter/ScrapPad.server.luau "ScrapPad uses scrap+touched"
check_grep "EconomyPad.convert(player, \"sell\", \"proximity\")" \
    src/ServerScriptService/Critter/ProximityPulse.server.luau "ProximityPulse fires sell+proximity"
check_grep "EconomyPad.convert(player, \"scrap\", \"proximity\")" \
    src/ServerScriptService/Critter/ProximityPulse.server.luau "ProximityPulse fires scrap+proximity"

echo
echo "── 9. PlantingFlow wires PlantSeed RemoteEvent + starter pack ──"
check_grep "PlantSeedRE.OnServerEvent:Connect" \
    src/ServerScriptService/Critter/PlantingFlow.server.luau "PlantSeed listener present"
check_grep "StarterPackGranted" \
    src/ServerScriptService/Critter/PlantingFlow.server.luau "starter pack one-shot guard present"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 critter structural checks: all passed"
exit 0
