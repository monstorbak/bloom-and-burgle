# BAB-010: Leaderboards not implemented (Richest Garden / Rarest Mutation / Most Stolen From)

**Owner:** G-Tard Lin
**State:** inbox
**Priority:** P1 (huge social/competitive virality lever)
**Files touched:** new `src/ServerScriptService/LeaderboardHandler.server.luau`, new `src/Workspace/LeaderboardKiosks.model.json`

## Problem

Spec:
> "Leaderboards for 'Richest Garden,' 'Rarest Mutation,' 'Most Stolen From.'"

Currently zero leaderboards. Players have no reason to brag, no reason to grind for #1, no reason to defend top spot. **No competitive layer = no whale spend ceiling.**

## Approach

1. `LeaderboardHandler.server.luau`: hooks into `OrderedDataStore` for each metric.
2. Push updates on each cash gain, mutation roll, theft event (debounced — every 60s, not on every change).
3. Three SurfaceGui kiosks in the town square, each showing top 10.
4. Player names colored gold for #1, silver #2, bronze #3.
5. Optional: weekly reset for "Top Earner This Week" leaderboard → drives login frequency.

## Acceptance

- [ ] Cash leaderboard updates within 60s of a change
- [ ] Mutation leaderboard tracks player's rarest mutation found (Mythic > Legendary > etc)
- [ ] "Most stolen from" leaderboard works (uses `PlantsStolenFrom` attribute already set in `StealHandler.luau`)
- [ ] Surfaces render correctly on mobile aspect ratios

## Log

- 2026-05-06 — G-Tard filed during initial triage
