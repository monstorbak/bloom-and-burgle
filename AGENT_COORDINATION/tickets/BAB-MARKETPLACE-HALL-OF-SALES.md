# BAB-MARKETPLACE-HALL-OF-SALES: persistent leaderboard of all-time biggest sells

**Owner:** unassigned
**State:** **superseded** — folded into [`BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL.md`](BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL.md)
**Priority:** n/a — see successor ticket
**Successor:** Phase 4's Trophy Hall includes Hall of Sales as one of 4 plaques (Hall of Sales, Mythic Hatchers, Plot Champions, Class Loyalty). Consolidating into a single physical hall keeps the Cogworks plaza from getting cluttered and reuses the same DataStore + MessagingService infrastructure.

## Hook (one-line pitch)

A physical leaderboard plaque in the Marketplace plaza listing the all-time top 10 single-transaction sells (per species, or globally), with player name, NPC, payout, and date. Permanent flex. Stash-flexing screenshots = organic marketing.

## Why it matters

- **Permanent record** — virality moments fade in 24h. The Hall is permanent recognition.
- **Competitive driver** — concrete target ("beat #3"), unlike vague "make more money."
- **Screenshot-friendly** — players photograph the board to brag in Discord/TikTok with their plot in the background.

## Sketch

- DataStore key `BloomAndBurgle_HallOfSales_v1` — append-only-ish (top-N kept, older entries pruned).
- 4 boards in the plaza:
  - **Biggest single sell** (any species, any NPC) — top 10
  - **Per-NPC biggest sells** — top 5 each (3 NPCs × 5 = 15 entries)
  - **Biggest arbitrage win** (highest multiplier × × payout) — top 10
  - **Most species sold** (kind diversity) — top 10
- Each entry: `{ playerName, displayName, species, npcId, payout, multiplier, isAsset, timestamp }`.
- Update on every notable-threshold sell (overlap with BAB-MARKETPLACE-CROSS-SERVER-TOASTS — probably share the threshold logic).

## Files touched (planned)

- new `src-marketplace/ServerScriptService/HallOfSales.server.luau`
- new `src-marketplace/Workspace/HallOfSales/` (the physical plaque models)
- new `src/ReplicatedStorage/Modules/HallOfSalesData.luau` (DataStore wrapper)
- modify `src-marketplace/StarterPlayerScripts/MarketplaceUI.client.luau` (proximity to plaque → highlight UI)

## Risks

- **DataStore consistency.** Cross-server writes to a single key need `UpdateAsync` to avoid lost updates. At high traffic the per-key throttle is the constraint — batch updates server-side and write once per minute, not per-sell.
- **Anti-exploit overlap.** A duped/exploited big sell would land on the leaderboard. Tie to trade ledger so only validated transactions qualify; rolling window for retroactive removal.

## Open questions

- **Per-class boards** in addition to global? Knights vs Hexers vs Sky-Pirates — three separate Halls? Defer; could be a later expansion.
- **Time-windowed boards** (this-week / this-month) in addition to all-time? Standard pattern, easy add. Defer.

## Log

- 2026-05-08 — Captured from strategy brainstorm.
