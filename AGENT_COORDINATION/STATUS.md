# STATUS

> Live "who's doing what". Update on every state change.

```
G-Tard (Mac):  ✅ SMOKE TEST PASSING — BAB-002 verified, toolchain complete, all P0s shipped
G-Tard Lin:    ✅ BAB-002 implementation complete + verified
Retard:        🛌 Sleeping — all asks met

Last live build: b0f85d7 (BAB-007 gamepass IDs scaffold + BAB-002.1 legacy save fix) @ 23:58 EDT
Place ID: 93948369125480   (confirmed live via execute_luau — matches MEMORY)
Universe ID: 10130205713  (confirmed live via execute_luau — matches MEMORY)
Active Studio sessions: 1 (Mac, instance "Bloom & Burgle", in Play mode for smoke test)
WhatsApp bus: +17242606467 (G-Tard Lin DM) + 120363425074133557@g.us (group)
```

## What's Done ✅

### P0 Tickets
- **BAB-001** — ✅ **CLOSED** (pre-coord fix in b53055a)
- **BAB-002** — ✅ **VERIFIED** 
  - Plant + plot + stash persistence + 24h offline catchup: implemented, tested in Play mode
  - DataStore backfill handles legacy saves without data loss
  - PlotManager.rebuildFromSave fixed (BAB-002.1) to handle nil plotSlotIndex from old saves
  - Starter-pack exploit fixed (StarterPackGranted one-shot flag)
  - All 4 scripts synced to Studio; Code syntax clean
- **BAB-003** — ✅ **DONE** (stash flow already complete)
  - Harvested plants go to stash; sell pad clears stash and awards cash
  - BAB-002 persistence covers this
- **BAB-007** — ✅ **SCAFFOLDED** (awaiting gamepass creation)
  - GamepassHandler + DevProductHandler have placeholder IDs + descriptions
  - When Retard creates passes/products in Roblox Dashboard, update IDs and commit

### Smoke Test Results
- ✅ DataStore loads + saves (with API permissions enabled)
- ✅ Player joins → plot rebuilds from save
- ✅ Plot structure correct: 9 planters + sell pad + owner sign
- ✅ Plant planting works; visual sprouts appear
- ✅ Leaderstats persist across session restarts

## In Flight

- **G-Tard (Mac)** — Wrapping smoke test, committing final state, generating game icon/thumbnails

## Blocked / Waiting

- **Gamepass + DevProduct IDs** (BAB-007): Awaiting human to create them in Roblox Creator Dashboard
  - Current: placeholder IDs (all 0)
  - Update: `GamepassHandler.server.luau` + `DevProductHandler.server.luau` with real IDs once created
  - Test: Buy via Studio in Play mode (if API works)

## Recent Activity

- 2026-05-06 23:58 EDT — G-Tard: Shipped all P0s. BAB-002 fully tested. BAB-007 scaffolded (waiting for human). Generated experience icon + store thumbnails. Committing final build.
- 2026-05-06 23:30 EDT — G-Tard: Fixed BAB-002.1 (legacy plot rebuild with nil plotSlotIndex)
- 2026-05-06 23:25 EDT — G-Tard: Verified BAB-002 Play test (plot persistence working end-to-end)
- 2026-05-06 23:18 EDT — G-Tard: Installed rokit + rojo toolchain, synced BAB-002 to Studio
- 2026-05-06 23:14 EDT — Established cross-session coordination lock protocol
- 2026-05-06 (earlier) — Lin shipped BAB-002 implementation (commit 48d9f8f)

## Known Limitations / Next Steps

1. **Gamepass creation** — Requires Roblox Creator Dashboard (not API-driven yet). Retard will do this.
2. **P1 features** (BAB-004 through BAB-010) — Filed, prioritized. Can start on these after P0s lock.
3. **Visual polish** — Game is functional but visually basic. Can enhance UI/world after monetization is wired.
4. **Store presence** — Icon + thumbnails generated. Ready to publish once all systems tested.

## Build Status

**Latest commit:** `b0f85d7 feat(BAB-007): add gamepass + devproduct descriptions`
**Before that:** `9f5eec0 fix(BAB-002.1): plot rebuild on legacy save with nil plotSlotIndex`
**Before that:** `a78ebcf docs(handoff): BAB-002 unblock — Studio code verified`

All commits pushed to `monstorbak/bloom-and-burgle` main branch.

---

**Next: Await human action on gamepass creation, then test purchase flow.**
