#!/usr/bin/env bash
# fusion-static.sh — structural regression check for the P1.3 / ADR-6 adoption.
#
# Asserts:
#   1. Fusion module exists with the canonical API surface.
#   2. HarvestModal exists and uses Fusion (not Instance.new mutation).
#   3. The reactive-primitives test mirrors the production primitives' shape
#      (so refactors of Fusion that change the metatables flag here too).
#
# Run:
#     bash scripts/test/fusion-static.sh

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

echo "── 1. Fusion module exists with canonical API ──"
check_file src/ReplicatedStorage/Modules/Fusion/init.luau
check_grep "function Fusion.New" \
    src/ReplicatedStorage/Modules/Fusion/init.luau "Fusion.New exported"
check_grep "function Fusion.Value" \
    src/ReplicatedStorage/Modules/Fusion/init.luau "Fusion.Value exported"
check_grep "function Fusion.Computed" \
    src/ReplicatedStorage/Modules/Fusion/init.luau "Fusion.Computed exported"
check_grep "function Fusion.OnEvent" \
    src/ReplicatedStorage/Modules/Fusion/init.luau "Fusion.OnEvent exported"
check_grep "Fusion.Children = " \
    src/ReplicatedStorage/Modules/Fusion/init.luau "Fusion.Children sigil exported"

echo
echo "── 2. HarvestModal exists and uses Fusion ──"
check_file src/StarterPlayerScripts/HarvestModal.client.luau
check_grep 'require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Fusion"))' \
    src/StarterPlayerScripts/HarvestModal.client.luau \
    "HarvestModal requires the Fusion module"
check_grep "local New = Fusion.New" \
    src/StarterPlayerScripts/HarvestModal.client.luau "HarvestModal pulls in Fusion.New"
check_grep "local Value = Fusion.Value" \
    src/StarterPlayerScripts/HarvestModal.client.luau "HarvestModal pulls in Fusion.Value"
check_grep "local Computed = Fusion.Computed" \
    src/StarterPlayerScripts/HarvestModal.client.luau "HarvestModal pulls in Fusion.Computed"

echo
echo "── 3. HarvestModal uses reactive bindings (not direct mutation) ──"
# A reactive binding is `Property = someValueOrComputed`. Smoke-check that
# at least one prop binding references our reactive cells.
check_grep "Text = titleText" \
    src/StarterPlayerScripts/HarvestModal.client.luau "Title bound reactively"
check_grep "Text = rarityText" \
    src/StarterPlayerScripts/HarvestModal.client.luau "Rarity bound reactively"
check_grep "Enabled = visible" \
    src/StarterPlayerScripts/HarvestModal.client.luau "Visibility bound to reactive cell"

echo
echo "── 4. HarvestModal listens to HarvestPopup but filters for rare drops ──"
check_grep "HarvestPopupRE.OnClientEvent:Connect" \
    src/StarterPlayerScripts/HarvestModal.client.luau "subscribes to HarvestPopup"
# isRare is the local filter — common drops fall through to CashHUD.
check_grep "local function isRare" \
    src/StarterPlayerScripts/HarvestModal.client.luau "rare-drop filter present"

echo
echo "── 5. test mirrors production primitive shape ──"
check_file tests/fusion/reactive_primitives.test.luau
check_grep "function Value.new" \
    tests/fusion/reactive_primitives.test.luau "test mirrors Value constructor"
check_grep "function Computed.new" \
    tests/fusion/reactive_primitives.test.luau "test mirrors Computed constructor"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures fusion-static check(s) failed"
    exit 1
fi
echo "🎉 fusion-static checks: all passed"
exit 0
