# BAB-MARKETPLACE-LIVE-AUCTION: Friday auction — NPC posts a wanted critter, players bid live

**Owner:** unassigned
**State:** inbox (design — capture only; high-virality but moderation-heavy)
**Priority:** P2 (virality layer; ship after engagement layer is solid)

## Hook (one-line pitch)

Once per real-week (e.g., Friday 8pm UTC), Brass Bart hosts a 30-second live auction for ONE rare critter: highest bidder wins, cash atomically transferred. Cross-server visible. The 0.2-seconds-left snipe is the TikTok clip.

## Why it matters

- **Real-time stakes** are the highest-engagement, highest-clip-able mechanic in modern social games. Pet Simulator X built virality on this.
- **Forces concurrent presence.** Players have to be online together → social moments → friends gathering → habit formation around a fixed weekly time.
- **Free-form pricing.** Bypasses the usual formula entirely; lets the market discover absolute value of a hot critter.

## Sketch

- **Trigger:** weekly cron (e.g., Friday 20:00 UTC) via MessagingService global broadcast.
- **Item:** rotates from a curated rare-critter pool; chosen deterministically per ISO week number.
- **Bidding:** 30-second timer, anti-snipe rule (last bid within 5s of close extends the timer 5s, capped at +60s — standard eBay anti-snipe).
- **Bid increment:** 5% minimum increment.
- **Cross-server:** all servers globally see the same auction; bids relayed via MessagingService. Authoritative bid state on a designated "auction host" server (first-to-claim pattern, or a dedicated cloud-hosted server in the future).
- **Settlement:** winning player teleported their winnings via DataStore inventory write; their cash atomically debited; broadcast announces the winner globally for social proof.

## Files touched (planned)

- new `src-marketplace/ServerScriptService/Auction/AuctionHost.server.luau`
- new `src-marketplace/ServerScriptService/Auction/AuctionClient.server.luau` (per-server, relays player bids to host)
- new `src/ReplicatedStorage/Modules/AuctionSchedule.luau` (weekly schedule + curated pool)
- new `src-marketplace/StarterPlayerScripts/AuctionUI.client.luau` (timer + bid UI)
- MessagingService topic: `bab-auction-v1`

## Risks

- **Exploit surface is wide.** Bid spam, cross-server clock skew, MessagingService loss → require all the standard mitigations (per-player bid rate limit via `RateLimiter`, signed bid timestamps, idempotent settlement).
- **MessagingService quotas.** 1 message/sec/topic/server. Need batched bid relay.
- **Weekly cadence may be too sparse.** Consider daily mini-auctions in addition to the weekly headline event.

## Open questions

- Authoritative auction host server selection (Roblox doesn't have a "primary server" concept). Options: lock via `MemoryStoreService` or run an external Cloud Function as the host.
- What if the winning player goes offline mid-settlement? Hold winnings in escrow DataStore key, deliver on next login.
- Anti-collusion (player A bids fake to pump, player B wins at inflated price)? Hard to detect cleanly; document as known limitation for v1.

## Log

- 2026-05-08 — Captured from strategy brainstorm.
