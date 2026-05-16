#!/usr/bin/env bash
# tier-2-static.sh — structural regression for BAB-DESIGN-CRITIQUE Tier 2
# (2026-05-10): Brass Clocktower + Tinkerer's Pass + UIComponents.
#
# Verifies that:
#   1. UIComponents module exists + exposes buildButton/buildPanel/buildHeader/buildBody/buildWorldSign + Font tokens.
#   2. ClocktowerScript builds at Cogworks plaza center (0, 0, 0), has
#      animated faces, and replaces the deleted Fountain.
#   3. TinkererPass module exposes hasPass + payoutMultiplier + GAMEPASS_ID.
#   4. DailyRewardChest server script exists + uses TinkererPass for 2× and DataStore for cooldown.
#   5. build.sh emits GamepassConfig.luau from BB_TINKERER_PASS_ID env var.
#   6. TownSquare.model.json no longer ships the Fountain.
#
# Run:
#     bash scripts/test/tier-2-static.sh

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
        fail "$what — pattern STILL FOUND: $pattern  in  $path"
    else
        ok "$what"
    fi
}

echo "── 1. UIComponents module ──"
check_file src/ReplicatedStorage/Modules/UIComponents.luau
check_grep "function M.buildButton" \
    src/ReplicatedStorage/Modules/UIComponents.luau \
    "UIComponents exposes buildButton"
check_grep "function M.buildPanel" \
    src/ReplicatedStorage/Modules/UIComponents.luau \
    "UIComponents exposes buildPanel"
check_grep "function M.buildHeader" \
    src/ReplicatedStorage/Modules/UIComponents.luau \
    "UIComponents exposes buildHeader"
check_grep "function M.buildBody" \
    src/ReplicatedStorage/Modules/UIComponents.luau \
    "UIComponents exposes buildBody"
check_grep "function M.buildWorldSign" \
    src/ReplicatedStorage/Modules/UIComponents.luau \
    "UIComponents exposes buildWorldSign"
check_grep "HudHeading" \
    src/ReplicatedStorage/Modules/UIComponents.luau \
    "UIComponents defines Font.HudHeading token"
check_grep "WorldSign" \
    src/ReplicatedStorage/Modules/UIComponents.luau \
    "UIComponents defines Font.WorldSign token (Antique for in-world)"

echo
echo "── 2. Brass Clocktower ──"
check_file src/ServerScriptService/ClocktowerScript.server.luau
check_grep "BrassClocktower" \
    src/ServerScriptService/ClocktowerScript.server.luau \
    "ClocktowerScript names the model BrassClocktower"
check_grep "BASE_POS = Vector3.new(0, 0, 0)" \
    src/ServerScriptService/ClocktowerScript.server.luau \
    "Clocktower positioned at Cogworks plaza center (0,0,0)"
check_grep "ClockHead" \
    src/ServerScriptService/ClocktowerScript.server.luau \
    "Clocktower builds the ClockHead cube"
check_grep "updateHands" \
    src/ServerScriptService/ClocktowerScript.server.luau \
    "Clocktower animates hour + minute hands"
check_grep "os.time()" \
    src/ServerScriptService/ClocktowerScript.server.luau \
    "Clocktower hand rotation tied to os.time() (real clock)"
check_grep 'f:Destroy()' \
    src/ServerScriptService/ClocktowerScript.server.luau \
    "Clocktower destroys legacy Fountain if present in workspace"

echo
echo "── 3. Tinkerer's Pass module ──"
check_file src/ServerScriptService/TinkererPass.luau
check_grep "function M.hasPass" \
    src/ServerScriptService/TinkererPass.luau \
    "TinkererPass exposes hasPass(player)"
check_grep "function M.payoutMultiplier" \
    src/ServerScriptService/TinkererPass.luau \
    "TinkererPass exposes payoutMultiplier(player)"
check_grep "UserOwnsGamePassAsync" \
    src/ServerScriptService/TinkererPass.luau \
    "TinkererPass uses MarketplaceService:UserOwnsGamePassAsync"
check_grep "PromptGamePassPurchaseFinished" \
    src/ServerScriptService/TinkererPass.luau \
    "TinkererPass invalidates cache on mid-session purchase"

echo
echo "── 4. Daily Reward Chest ──"
check_file src/ServerScriptService/DailyRewardChest.server.luau
check_grep "BAB_DailyReward_v1" \
    src/ServerScriptService/DailyRewardChest.server.luau \
    "DailyRewardChest uses BAB_DailyReward_v1 DataStore key"
check_grep "COOLDOWN_SECONDS = 24 \* 60 \* 60" \
    src/ServerScriptService/DailyRewardChest.server.luau \
    "DailyRewardChest enforces 24-hour cooldown"
check_grep "TinkererPass.payoutMultiplier" \
    src/ServerScriptService/DailyRewardChest.server.luau \
    "DailyRewardChest reads TinkererPass for 2× payout"
check_grep "UpdateAsync" \
    src/ServerScriptService/DailyRewardChest.server.luau \
    "DailyRewardChest uses UpdateAsync for atomic claim"
check_grep "daily_reward_claimed" \
    src/ServerScriptService/DailyRewardChest.server.luau \
    "DailyRewardChest emits daily_reward_claimed telemetry"

echo
echo "── 5. build.sh gamepass config injection ──"
check_grep "GamepassConfig.luau" \
    scripts/build.sh \
    "build.sh writes GamepassConfig.luau"
check_grep "BB_TINKERER_PASS_ID" \
    scripts/build.sh \
    "build.sh reads BB_TINKERER_PASS_ID env var"
check_grep "GamepassConfig.luau" \
    .gitignore \
    ".gitignore excludes GamepassConfig.luau (generated, not tracked)"

echo
echo "── 6. Fountain removed from TownSquare ──"
check_no_match '"name": "Fountain"' \
    src/Workspace/TownSquare.model.json \
    "TownSquare no longer ships the off-brand marble Fountain"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 tier-2 structural checks: all passed"
exit 0
