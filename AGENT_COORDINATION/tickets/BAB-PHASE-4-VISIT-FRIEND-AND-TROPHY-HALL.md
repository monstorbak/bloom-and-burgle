# BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL: cross-server presence + invite-friend teleport + Trophy Hall top-100

**Owner:** unassigned
**State:** inbox (design — implementation-ready)
**Priority:** P1 (network-effect virality; subsumes the broader scope of `BAB-MARKETPLACE-HALL-OF-SALES.md`)
**Supersedes:** [`BAB-MARKETPLACE-HALL-OF-SALES.md`](BAB-MARKETPLACE-HALL-OF-SALES.md) (the leaderboard plaque is one fixture inside the broader Trophy Hall this ticket builds)

**Files touched (planned):**

Hatchery (`src/`):
- new `src/ServerScriptService/PresenceBroadcast.server.luau` (subscribe to `bab-presence-v1` MessagingService topic; maintain in-memory map of online friends + their server jobIds)
- new `src/ServerScriptService/VisitFriendHandler.server.luau` (RemoteEvent listener: client requests visit; server invokes TeleportService:TeleportToPlaceInstanceAsync to friend's running job)
- new `src/ServerScriptService/TrophyHallScript.server.luau` (builds the physical Trophy Hall in the Cogworks plaza)
- new `src/StarterPlayerScripts/FriendsListHUD.client.luau` (slide-out list of online friends with "Visit" buttons)
- modify `src/StarterPlayerScripts/CashHUD.client.luau` (add the Trophy Hall pointer when player has a top-100-eligible critter)
- new `src/ReplicatedStorage/Modules/TrophyData.luau` (DataStore wrapper for the 4 leaderboards)
- new `src/ReplicatedStorage/RemoteEvents/{VisitFriend,TrophyData}.model.json`
- new MessagingService topics: `bab-presence-v1`, `bab-trophy-update-v1`

## Problem

BAB has zero **network-effect** loops today:
1. A player can't see what their Roblox friends are up to in BAB.
2. A player can't visit their friend's hatchery to admire / steal / coordinate.
3. There's no permanent recognition vector — every hatch is local + ephemeral; none of it surfaces to other players in other servers.

Every successful Roblox sim has these three loops cranked: Adopt Me's
"sleepover" mechanic, Pet Simulator X's friend-trading-portal, Royale
High's "campus visit." Without them BAB caps at solo-engagement metrics.

This phase ships the smallest viable version of all three.

## Approach

### Cross-server presence (`PresenceBroadcast`)

Each Hatchery server publishes a heartbeat once per 30s to the
`bab-presence-v1` MessagingService topic:

```
{
    userId = 7965127581,
    displayName = "piddlywinx",
    plotIndex = 5,
    class = "hexer",
    placeId = 93948369125480,        -- always Hatchery; never Marketplace/Corridors
    jobId = "abc123-def456-...",      -- this server's job
    ts = os.time(),
}
```

Subscriber maintains an in-memory map; entries older than 90s expire.

This costs **2 messages per server per minute per online friend
relationship** at peak — well within MessagingService's 600 msg/min/topic
limit until DAU > ~5000.

### Visit-a-friend flow

Client opens the `FriendsListHUD` (toggle key, e.g. F5 or a HUD button).
List shows online friends + "Visit" button. On click:

1. Client fires `VisitFriend:FireServer({ targetUid = 7965127581 })`.
2. Server checks `PresenceBroadcast.findFriend(targetUid)` for the friend's `jobId`.
3. Calls `TeleportService:TeleportToPlaceInstanceAsync(hatcheryPlaceId, jobId, player)`.
4. Friend's server's `PlayerAdded` handler reads `teleportData = { fromUid = visitorUid }` and shows them as a guest with a "👋 visitor" badge.

If the friend's job is full (50 CCU cap), fallback to:
1. Try sibling jobs running the same place (use `MessagingService:PublishAsync("bab-visit-request-v1", ...)` for cross-server discovery — defer if too brittle for v1).
2. Or default to a fresh job (loses the friend-coupling but preserves the "I tried to visit" moment).

### "Bring a friend" boost

When a player teleports IN to another player's server (visitor) and stays > 60s, both players get a **+10% scrap value for 5 minutes** boost — written to leaderstats as a temp attribute. Spec §13's growth-loop hook.

Telemetry: `friend_visit_started`, `friend_visit_settled` (after 60s), `visit_boost_consumed` (when a sell fires during the boost window).

### Trophy Hall (subsumes BAB-MARKETPLACE-HALL-OF-SALES)

A physical building in the Cogworks plaza opposite the spawn — brass-and-steam architecture per §1.1. Inside, **4 leaderboards** displayed as physical plaques:

| Plaque | Source | Update cadence |
|---|---|---|
| **Hall of Sales** | Top 10 single-transaction sells globally | Every 60s server-aggregated |
| **Mythic Hatchers** | Top 10 lifetime Mythic hatches per player | Every 60s |
| **Plot Champions** | Top 10 lifetime cash earned | Daily UTC reset |
| **Class Loyalty** | Top 1 per class (5 plaques) — most-rep with each NPC merchant | Daily UTC reset |

DataStore: single key `BloomAndBurgleTrophy_v1`, structured as
`{ category → [{playerName, displayName, value, timestamp}] }`. Updates
via the `bab-trophy-update-v1` MessagingService topic (every notable-sell
broadcast pings the topic; an aggregator server reads + writes to the
DataStore once per 60s).

Plaque rendering: SurfaceGui with a TextLabel list. On player approach
(< 12 studs), highlight + show a tooltip "Walk into the plaque to share
this hall on Roblox feed." (Phase 5 territory — for now, just a click-to-copy-link.)

## Acceptance

- [ ] Online friends in BAB appear in the friends list within 90s of their join.
- [ ] Click "Visit" on a friend → teleport lands you in their job; visitor badge shows.
- [ ] If friend's job is full, visitor lands in a sibling job or fresh job (no error).
- [ ] Both visitor + host get the +10% scrap boost after 60s of presence.
- [ ] Trophy Hall renders 4 plaques with correct top-N data on join.
- [ ] Plaques update within 60s of a globally notable sell.
- [ ] No PII leaked: only displayName + value + timestamp in plaque payload.
- [ ] No regression on the existing portal/teleport flow.
- [ ] `Telemetry.track("friend_visit_started", ...)` fires per visit attempt.

## Open questions

1. **Roblox friends API.** `Player:GetFriendsAsync()` requires HttpService access. Verify the Hatchery has it enabled.
2. **Visit cooldown.** Cap visits to 1 per friend per 30 min to avoid harassment / spam-teleport via a hostile player. Is 30 min right?
3. **Plot pre-existing state.** When a visitor joins a friend's server, do they see the friend's plot or their own? **Their own plot is loaded as a separate slot in the same place; the visitor doesn't share the host's plot.** This matches Pet Sim X behavior. Document for clarity.
4. **Cross-class plot visibility.** Do visitors see asset/liability badges from THEIR class or the host's? — Their own class. The visit is to admire/coordinate; class lookup remains visitor-side.
5. **Trophy Hall placement.** Cogworks plaza is already crowded (Marketplace portal at +X, Steal portal at -X, NPC stalls coming?). Recommend the Trophy Hall sit at +Z behind the spawn (the "north" wall of the plaza). Reserve -Z for future content.

## Defer

- Cross-place presence (Marketplace + Corridors). Hatchery-only for v1.
- "Visit a stranger" — only Roblox-friends list for v1; later open to "popular hatchery" recommendations.
- Trophy Hall self-photo automation (auto-screenshot + share). Manual screenshot is fine.

## Log

- 2026-05-08 — Direction shift session; folded into prioritized roadmap. Drafted ticket. Supersedes the narrower BAB-MARKETPLACE-HALL-OF-SALES.
