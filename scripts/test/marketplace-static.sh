#!/usr/bin/env bash
# marketplace-static.sh — structural regression for the marketplace NPC system
# (BAB-MARKETPLACE-NPC-ROTATION, 2026-05-08).
#
# Verifies that:
#   1. Foundation modules exist (MerchantPersonalities, NPCRotation, MerchantPricing)
#   2. The mirror in tests/marketplace/pricing.test.luau pins the same
#      MULTIPLIER_CAP as the production module.
#   3. Each of the 3 NPC server scripts exists and consumes the shared
#      pricing module (no re-implemented multiplier math).
#   4. MerchantPersonalities exports all 3 expected NPC ids.
#
# Run:
#     bash scripts/test/marketplace-static.sh

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
check_file src/ReplicatedStorage/Modules/MerchantPersonalities.luau
check_file src/ReplicatedStorage/Modules/NPCRotation.luau
check_file src/ReplicatedStorage/Modules/MerchantPricing.luau
check_file tests/marketplace/pricing.test.luau

echo
echo "── 2. mirror constants pinned in lockstep ──"
check_grep "MULTIPLIER_CAP = 3.0" \
    src/ReplicatedStorage/Modules/MerchantPricing.luau \
    "MerchantPricing pins MULTIPLIER_CAP at 3.0"
check_grep "MULTIPLIER_CAP = 3.0" \
    tests/marketplace/pricing.test.luau \
    "test mirrors MULTIPLIER_CAP at 3.0"

echo
echo "── 3. MerchantPersonalities exports the 3 NPC ids ──"
check_grep "bart = {" \
    src/ReplicatedStorage/Modules/MerchantPersonalities.luau \
    "Bart personality registered"
check_grep "hexerine = {" \
    src/ReplicatedStorage/Modules/MerchantPersonalities.luau \
    "Hexerine personality registered"
check_grep "verda = {" \
    src/ReplicatedStorage/Modules/MerchantPersonalities.luau \
    "Verda personality registered"

echo
echo "── 4. NPCRotation exports the deterministic seed function ──"
check_grep "function M.todaysSpecial" \
    src/ReplicatedStorage/Modules/NPCRotation.luau \
    "NPCRotation.todaysSpecial exported"
check_grep "function M._utcYday" \
    src/ReplicatedStorage/Modules/NPCRotation.luau \
    "NPCRotation._utcYday exported (test seam)"
# The Knuth golden-ratio multiplicative-hash constant — pin so a casual edit
# can't silently change today's-special globally.
check_grep "2654435761" \
    src/ReplicatedStorage/Modules/NPCRotation.luau \
    "NPCRotation seed uses Knuth multiplicative hash constant"

echo
echo "── 5. MerchantPricing exports priceLine + priceStash ──"
check_grep "function M.priceLine" \
    src/ReplicatedStorage/Modules/MerchantPricing.luau \
    "MerchantPricing.priceLine exported"
check_grep "function M.priceStash" \
    src/ReplicatedStorage/Modules/MerchantPricing.luau \
    "MerchantPricing.priceStash exported"

echo
echo "── 6. shared sell-flow helper exists + has the right hooks ──"
check_file src-marketplace/ServerScriptService/MerchantSellFlow.luau
check_grep "MerchantPricing" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow requires MerchantPricing"
check_grep "RateLimiter.tryConsume" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow gates with RateLimiter.tryConsume (ADR-2)"
check_grep "Telemetry.track" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow emits Telemetry.track (ADR-3)"
check_grep "function M.attachNPC" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow.attachNPC exported"

echo
echo "── 7. each NPC server script attaches via MerchantSellFlow ──"
for npc in BrassBart Hexerine Verda; do
    path="src-marketplace/ServerScriptService/${npc}.server.luau"
    check_file "$path"
    if [ -f "$path" ]; then
        check_grep "MerchantSellFlow" "$path" "$npc requires MerchantSellFlow"
        check_grep "attachNPC" "$path" "$npc calls MerchantSellFlow.attachNPC"
    fi
done

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 marketplace structural checks: all passed"
exit 0
