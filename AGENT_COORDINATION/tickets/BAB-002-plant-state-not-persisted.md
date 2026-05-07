# BAB-002: Plant grow state lost on server restart (no DataStore persistence)

**Owner:** G-Tard Lin
**State:** in-review
**Priority:** P0
**Files touched:** `src/ServerScriptService/DataStore.luau`, `src/ServerScriptService/PlantHandler.server.luau`, `src/ServerScriptService/LeaderstatsScript.server.luau`

## Problem

The spec REQUIRES idle/offline progression:
> "Plants keep growing/mutating/selling while offline (up to 24h cap). Return = big payout. This drives daily logins and whales who hate missing out."

Currently:
- `DataStore.luau` saves `cash`, `rebirths`, `multiplier`, `plotClaimed`, `plotPosition`, `plantsHarvested`, `mutationsFound`, `lastSeen`.
- It **does NOT save planter state** (`PlantedSpecies`, `PlantedAt`, `GrowSeconds`, mutation rolls).
- `PlantHandler.server.luau` keeps inventory in a server-local Lua table that vanishes on server restart.

Net effect: a player plants Mythic Sunbloom, server cycles, plant is gone. **This kills retention** — the entire idle pillar is broken.

## Approach

1. Extend `DEFAULT_DATA` in `DataStore.luau`:
   ```lua
   plot = {
     planters = {                  -- per-planter state, indexed by relative slot id 1..9
       [1] = { species = "sunbloom", plantedAt = 1234567890, growSeconds = 60 },
       ...
     },
     stash = { sunbloom = 3, ... }, -- harvested-but-unsold inventory
   }
   ```
2. On `LeaderstatsScript` load, after building the plot, replay each saved planter into the `Planter` parts (set attributes, build sprout part).
3. On every harvest / plant-action, set a dirty flag → autosave loop already exists, just include `plot` in the snapshot.
4. **Offline catchup:** on load, if `os.time() - PlantedAt >= GrowSeconds`, mark instantly ripe (visual sprout at full size). Cap at `lastSeen + 24h` to prevent infinite-AFK exploits.

## Acceptance

- [ ] Plant Sunbloom, server-cycle (kick all players or `:Shutdown()`), rejoin → plant is there at correct grow stage
- [ ] AFK overnight, return next day → all plants ripe, harvest works
- [ ] Stash (unsold harvested plants) persists across sessions
- [ ] DataStore migration is backward compatible (existing players don't get wiped)

## Log

- 2026-05-06 — G-Tard filed during initial triage
- 2026-05-06 — Lin claimed. Plan: extend `DataStore` with `plot.planters` + `plot.stash`, add inventory getters/setters in `PlantHandler`, replay-on-join, 24h offline catchup cap. Also patching `PlotManager` to rebuild plot on rejoin (latent bug — `plotClaimed=true` saved but plot never reconstructed).
- 2026-05-06 — Lin: in-review. Implementation:
  - `DataStore.luau`: added `plot = { planters = {}, stash = {} }`, `plotSlotIndex`, `lifetimeCash`, `starterPackGranted` to `DEFAULT_DATA`. Replaced shallow backfill with a recursive deep merge so existing saves get the new nested keys without wiping stored fields.
  - `PlantHandler.server.luau`: exposed `_G.PlantHandler = { snapshot, restore }`. Snapshot walks tagged Planters owned by the player + the in-memory inventory and emits the `plot` shape. Restore walks the saved `plot` data, finds matching planter parts via `findPlanterForSlot` (decoded from `Planter_X_Z` name), then either restores mid-grow attributes + sprout part at the correct progress, or runs `harvestOffline` and frees the planter. Effective elapsed time is capped at `lastSeen + 24h` so AFK >24h doesn’t mass-grant infinitely. Also fixed a related exploit: starter-pack free Sunblooms now only grant once per account (persisted as `starterPackGranted`) so logging out and back in can’t re-fill empty planters.
  - `PlotManager.server.luau`: exposed `_G.PlotManager = { rebuildFromSave }` so a returning player whose `plotClaimed=true` can have their plot rebuilt at their saved `plotSlotIndex` (with first-empty-slot fallback if their original slot was claimed by someone else this server).
  - `LeaderstatsScript.server.luau`: load order is now exactly `DataStore.loadData → PlotManager.rebuildFromSave → PlantHandler.restore`, with `waitForGlobal` guards in case of script load races. Snapshot pulls `plot` from PlantHandler so the autosave loop persists plant state.
  - Rojo build is clean (`/tmp/bb-bab002.rbxlx`).
  - `STATUS.md` flagged the place/universe IDs in the file mismatching MEMORY.md — may be stale from neon-forge.
