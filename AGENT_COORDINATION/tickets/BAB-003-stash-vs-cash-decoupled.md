# BAB-003: Harvested plants don't go in stash — sell flow assumes auto-cash

**Owner:** G-Tard Lin
**State:** inbox
**Priority:** P0
**Files touched:** `src/ServerScriptService/PlantHandler.server.luau`, `src/ServerScriptService/SeedShop.server.luau`, `src/StarterPlayerScripts/PlanterUI.client.luau`

## Problem

Reading `PlantHandler.luau` and `StealHandler.luau`:
- `PlantHandler` has a comment hinting at an `inventory` table keyed by `userId × speciesId × mutation`.
- `StealHandler` directly awards cash on steal (no stash insertion).
- `SellPlantsRE` is wired but unclear whether the inventory table is actually populated on harvest, or if harvest auto-converts to cash.

The spec's selling/flexing loop requires:
> "Harvest → see your stash of rare plants → walk to SellPad → choose how many to sell → cash"

So players can flex/screenshot rare mutations and trade them. If we auto-cash on harvest, **the entire collectible flex layer disappears** — that's a major retention/virality loss.

## Approach

1. Confirm what `PlantHandler` currently does on auto-harvest (when grow timer hits 100%).
2. If it auto-cashes: change to push into `inventory[userId][speciesId..":"..mutationId]` instead.
3. SellPlants RE should accept an optional list of `{species, mutation, count}` to sell, or "sell all".
4. Stash persists in DataStore (see BAB-002).
5. Client-side: PlanterUI shows a "Stash: 3 Sunbloom (1 Glowing)" ribbon when the player has unsold plants.

## Acceptance

- [ ] Harvest → leaderstat cash unchanged, stash count goes up
- [ ] Walk on SellPad → stash converts to cash, stash empty
- [ ] Stolen plants from BAB-???/StealHandler also drop into thief's stash (not direct cash) — separate ticket if needed
- [ ] Mutations visible in stash UI

## Log

- 2026-05-06 — G-Tard filed during initial triage
