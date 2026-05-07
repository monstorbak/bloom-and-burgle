# BAB-002: Plant grow state lost on server restart (no DataStore persistence)

**Owner:** G-Tard Lin
**State:** inbox
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
