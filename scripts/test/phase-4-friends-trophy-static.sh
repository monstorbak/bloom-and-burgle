#!/usr/bin/env bash
# phase-4-friends-trophy-static.sh — structural regression for
# BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL (2026-05-10).
#
# Verifies that:
#   1. All 5 new files exist (TrophyData, PresenceBroadcast, VisitFriendHandler,
#      TrophyHallScript, FriendsListHUD).
#   2. PresenceBroadcast publishes/subscribes on bab-presence-v1 + exposes
#      findFriend / allOnline.
#   3. VisitFriendHandler validates Roblox friendship via GetFriendsAsync,
#      gates with RateLimiter, and calls TeleportToPlaceInstanceAsync.
#   4. TrophyData wraps DataStore key BloomAndBurgleTrophy_v1, exposes
#      submit + read, and dedupes mythic_hatch one-entry-per-user.
#   5. TrophyHallScript builds 2 plaques (Hall of Sales + Mythic Hatchers)
#      at HALL_POSITION (0, 4, 100).
#   6. MerchantSellFlow posts notable sells (>= HALL_OF_SALES_THRESHOLD)
#      to TrophyData.
#   7. HarvestFlow posts mythic hatches to TrophyData and persists the
#      MythicHatches counter via LeaderstatsScript.
#   8. FriendsListHUD wires VisitFriend RemoteEvent + GetOnlinePresence
#      RemoteFunction.
#
# Run:
#     bash scripts/test/phase-4-friends-trophy-static.sh

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

echo "── 1. New Phase 4 files exist ──"
check_file src/ReplicatedStorage/Modules/TrophyData.luau
check_file src/ServerScriptService/PresenceBroadcast.luau
check_file src/ServerScriptService/VisitFriendHandler.server.luau
check_file src/ServerScriptService/TrophyHallScript.server.luau
check_file src/StarterPlayerScripts/FriendsListHUD.client.luau

echo
echo "── 2. PresenceBroadcast cross-server map ──"
check_grep "bab-presence-v1" \
    src/ServerScriptService/PresenceBroadcast.luau \
    "PresenceBroadcast uses topic bab-presence-v1"
check_grep "MessagingService" \
    src/ServerScriptService/PresenceBroadcast.luau \
    "PresenceBroadcast uses MessagingService"
check_grep "function M.findFriend" \
    src/ServerScriptService/PresenceBroadcast.luau \
    "PresenceBroadcast exposes findFriend(targetUid)"
check_grep "function M.allOnline" \
    src/ServerScriptService/PresenceBroadcast.luau \
    "PresenceBroadcast exposes allOnline(excludeUid)"

echo
echo "── 3. VisitFriendHandler ──"
check_grep "GetFriendsAsync" \
    src/ServerScriptService/VisitFriendHandler.server.luau \
    "VisitFriendHandler validates Roblox friendship via GetFriendsAsync"
check_grep "RateLimiter" \
    src/ServerScriptService/VisitFriendHandler.server.luau \
    "VisitFriendHandler gates visit attempts with RateLimiter"
check_grep "TeleportToPlaceInstanceAsync" \
    src/ServerScriptService/VisitFriendHandler.server.luau \
    "VisitFriendHandler calls TeleportToPlaceInstanceAsync for jobId teleport"
check_grep "VisitFriend" \
    src/ServerScriptService/VisitFriendHandler.server.luau \
    "VisitFriendHandler creates VisitFriend RemoteEvent"
check_grep "GetOnlinePresence" \
    src/ServerScriptService/VisitFriendHandler.server.luau \
    "VisitFriendHandler creates GetOnlinePresence RemoteFunction"
check_grep "friend_visit_started" \
    src/ServerScriptService/VisitFriendHandler.server.luau \
    "VisitFriendHandler emits friend_visit_started Telemetry event"

echo
echo "── 4. TrophyData ──"
check_grep "BloomAndBurgleTrophy_v1" \
    src/ReplicatedStorage/Modules/TrophyData.luau \
    "TrophyData uses BloomAndBurgleTrophy_v1 DataStore key"
check_grep "function M.submit" \
    src/ReplicatedStorage/Modules/TrophyData.luau \
    "TrophyData exposes submit(category, entry)"
check_grep "function M.read" \
    src/ReplicatedStorage/Modules/TrophyData.luau \
    "TrophyData exposes read() snapshot"
check_grep "hall_of_sales" \
    src/ReplicatedStorage/Modules/TrophyData.luau \
    "TrophyData ships hall_of_sales category"
check_grep "mythic_hatch" \
    src/ReplicatedStorage/Modules/TrophyData.luau \
    "TrophyData ships mythic_hatch category"
check_grep "UpdateAsync" \
    src/ReplicatedStorage/Modules/TrophyData.luau \
    "TrophyData uses UpdateAsync for atomic cross-server writes"
check_grep 'category == "mythic_hatch"' \
    src/ReplicatedStorage/Modules/TrophyData.luau \
    "TrophyData dedupes mythic_hatch one-entry-per-user"

echo
echo "── 5. TrophyHallScript ──"
check_grep "HALL_POSITION = Vector3.new(0, 4, 100)" \
    src/ServerScriptService/TrophyHallScript.server.luau \
    "TrophyHall positioned at (0, 4, 100) per ticket open question 5"
check_grep "HallOfSales" \
    src/ServerScriptService/TrophyHallScript.server.luau \
    "TrophyHall builds Hall of Sales plaque"
check_grep "MythicHatchers" \
    src/ServerScriptService/TrophyHallScript.server.luau \
    "TrophyHall builds Mythic Hatchers plaque"
check_grep "TrophyData.read" \
    src/ServerScriptService/TrophyHallScript.server.luau \
    "TrophyHall refreshes from TrophyData.read()"
check_grep "task.wait(60)" \
    src/ServerScriptService/TrophyHallScript.server.luau \
    "TrophyHall refreshes every 60s"

echo
echo "── 6. MerchantSellFlow posts notable sells ──"
check_grep "HALL_OF_SALES_THRESHOLD" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow defines HALL_OF_SALES_THRESHOLD"
check_grep 'TrophyData.submit("hall_of_sales"' \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow submits notable sells to hall_of_sales"
check_grep "topSpeciesId" \
    src-marketplace/ServerScriptService/MerchantSellFlow.luau \
    "MerchantSellFlow tracks dominant species per transaction"

echo
echo "── 7. HarvestFlow posts mythic hatches + LeaderstatsScript persists ──"
check_grep 'TrophyData.submit("mythic_hatch"' \
    src/ServerScriptService/Critter/HarvestFlow.luau \
    "HarvestFlow submits mythic hatches to mythic_hatch"
check_grep 'SetAttribute("MythicHatches"' \
    src/ServerScriptService/Critter/HarvestFlow.luau \
    "HarvestFlow increments MythicHatches lifetime counter"
check_grep "data.mythicHatches" \
    src/ServerScriptService/LeaderstatsScript.server.luau \
    "LeaderstatsScript loads MythicHatches from DataStore on PlayerAdded"
check_grep 'mythicHatches = player:GetAttribute("MythicHatches")' \
    src/ServerScriptService/LeaderstatsScript.server.luau \
    "LeaderstatsScript snapshots MythicHatches back to DataStore"

echo
echo "── 8. FriendsListHUD client UI ──"
check_grep "VisitFriend" \
    src/StarterPlayerScripts/FriendsListHUD.client.luau \
    "FriendsListHUD wires VisitFriend RemoteEvent"
check_grep "GetOnlinePresence" \
    src/StarterPlayerScripts/FriendsListHUD.client.luau \
    "FriendsListHUD invokes GetOnlinePresence RemoteFunction"
check_grep "GetFriendsAsync" \
    src/StarterPlayerScripts/FriendsListHUD.client.luau \
    "FriendsListHUD fetches Roblox friends via GetFriendsAsync"

echo
if [ "$failures" -gt 0 ]; then
    echo "❌ $failures structural check(s) failed"
    exit 1
fi
echo "🎉 phase-4-friends-trophy structural checks: all passed"
exit 0
