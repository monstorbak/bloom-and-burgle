#!/usr/bin/env bash
# visibility-mobile-fixes-static.sh — structural regression for the
# 2026-05-11 visibility + Android-tap fix pair.
#
# Verifies that:
#   1. CritterVisuals has a single buildRipeIndicator helper (no duplicate
#      inline indicator builders left over).
#   2. The indicator uses light TextColor3 with a dark stroke (was default
#      black-on-black, swallowed by Aether Hour ambient).
#   3. The species displayName is included as a fallback for missing emoji
#      glyphs on Android.
#   4. RipeGlow brightness is bumped 2 → 5 when ripe.
#   5. MerchantSellFlow.attachNPC wires ClickDetectors on the NPC's stall
#      model so mobile players who tap the 3D NPC body fire the quote.
#
# Run:
#     bash scripts/test/visibility-mobile-fixes-static.sh

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

check_count() {
    local pattern="$1" path="$2" expected="$3" what="$4"
    local actual
    actual=$(grep -c -- "$pattern" "$path" 2>/dev/null || echo 0)
    if [ "$actual" = "$expected" ]; then
        ok "$what (count=$actual)"
    else
        fail "$what — pattern '$pattern' count mismatch: expected $expected, got $actual"
    fi
}

echo "── 1. CritterVisuals: single ripe-indicator builder ──"
check_grep "local function buildRipeIndicator" \
    src/ServerScriptService/CritterVisuals.luau \
    "CritterVisuals has buildRipeIndicator helper"
check_count 'buildRipeIndicator(body, species)' \
    src/ServerScriptService/CritterVisuals.luau 2 \
    "both rig + archetype paths use the shared helper"

echo
echo "── 2. Indicator visibility (TextColor + stroke + display name) ──"
check_grep 'TextColor3 = Color3.fromRGB(242, 228, 201)' \
    src/ServerScriptService/CritterVisuals.luau \
    "Indicator emoji uses SteamCream text (was default black, invisible)"
check_grep 'TextStrokeTransparency = 0' \
    src/ServerScriptService/CritterVisuals.luau \
    "Indicator emoji has solid dark stroke for contrast in any lighting"
check_grep 'species.displayName or species.id' \
    src/ServerScriptService/CritterVisuals.luau \
    "Indicator shows species displayName as Android-emoji-fallback"

echo
echo "── 3. RipeGlow brightness bumped ──"
check_grep 'glow.Brightness = 5' \
    src/ServerScriptService/CritterVisuals.luau \
    "RipeGlow brightness 5 when ripe (was 2 — swallowed by Aether Hour)"

echo
echo "── 4. MerchantSellFlow ClickDetector mobile fallback ──"
check_grep "ClickDetector" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow.attachNPC creates ClickDetector for mobile tap"
check_grep "MouseClick:Connect" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "ClickDetector wires MouseClick to the quote flow"
check_grep "BAB-ANDROID-TAP-FIX" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow tags the change with BAB-ANDROID-TAP-FIX"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 visibility + mobile-tap fixes: all checks passed"
exit 0
