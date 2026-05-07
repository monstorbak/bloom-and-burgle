# BAB-008: Player-to-player trading not implemented (spec-required virality engine)

**Owner:** G-Tard Lin
**State:** inbox
**Priority:** P1 (post-MVP retention boost)
**Files touched:** new `src/ServerScriptService/TradeHandler.server.luau`, new `src/StarterPlayerScripts/TradeUI.client.luau`, new RemoteEvents

## Problem

Spec calls out trading as a core virality driver:
> "Trading Economy: Player-to-player pet/plant trading (creates emergent content and keeps players logging in)."

Without it: no emergent economy, no Discord trade channel content, no viral "I traded Mythic Sunbloom for 5 Glowing Roses" TikTok content.

## Approach (MVP)

1. Two-way trade: player A right-clicks/taps player B → "Request Trade" → B gets prompt → both see a 2-pane trade UI.
2. Each side adds plants from stash (server-validated each add).
3. Both must hit "Confirm" twice (anti-misclick).
4. Server atomically swaps inventory entries.
5. Cooldown: 30s between trades per player to throttle scams.
6. **Anti-scam:** every trade logged with both parties' inventory deltas to a DataStore for moderation.

## Acceptance

- [ ] Two players can trade plants successfully
- [ ] Cancellation works at any point pre-confirm
- [ ] Cannot trade plants you don't own
- [ ] Cannot duplicate by spamming confirm
- [ ] Trade log persists for moderation review

## Defer to v0.4

- Pet trading (no pets yet)
- Cash trading (separate ticket if needed)
- Trade-restriction gamepass (paid feature for safer trades — possible monetization angle)

## Log

- 2026-05-06 — G-Tard filed during initial triage
