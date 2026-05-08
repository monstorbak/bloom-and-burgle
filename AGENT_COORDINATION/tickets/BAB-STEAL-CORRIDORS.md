# BAB-STEAL-CORRIDORS: Steal portal → procedural corridor system + map UI + click-to-snap nav

**Owner:** unassigned
**State:** inbox (design)
**Priority:** P1 (post-P1-arch — direction shift)
**Files touched (planned):**

Hatchery side (existing place):
- new `src/ServerScriptService/StealPortal.server.luau` (TeleportService entry; checks player has cash for the entry fee)
- new `src/Workspace/Cogworks/StealPortal.model.json` (visible portal, dim red glow opposite the gold marketplace portal)
- modify `src/ServerScriptService/StealHandler.server.luau` (existing StealHandler — its prompt-based steal is the *target-side* code that fires when a corridor door delivers a thief into someone's hatchery)

Steal place (new universe place ID):
- new `src/Workspace/CorridorScene/` — base geometry: spawn lobby + corridor seed
- new `src/ServerScriptService/CorridorServer/` folder:
    - `CorridorGenerator.server.luau` (procedural layout per visit;
      see "Generation" below)
    - `DoorRouter.server.luau` (when a player walks through a door,
      routes them via TeleportService to the target player's Hatchery
      server with `setTeleportData({asThief = true})`)
    - `CorridorPersistence.server.luau` (loads + saves
      `data.corridors.discoveredDoors` keyed by player UID)
    - `MapStreamer.server.luau` (sends the player's revealed-map data
      to the client over a RemoteFunction)
- new `src/StarterPlayerScripts/CorridorUI/`:
    - `MapHUD.client.luau` (Fusion-driven minimap; player position
      blue, visited doors gold, unvisited gray)
    - `ClickToSnap.client.luau` (the "click on the map to teleport
      character to a known waypoint" feature)
    - `DoorPrompt.client.luau` (the Enter-this-door interaction)

Roblox-side:
- new published Place inside the existing universe (separate from
  Hatchery + Marketplace).
- new `default-corridors.project.json` Rojo project.

## Problem

Today the existing StealHandler exists but the "where do you steal
from" UX is missing. The §2.3 Design Spec describes "Combat & raid
lanes" but currently the only raid path is the implicit
"a-corridor-system-doesn't-exist-yet" fallback.

The user described a portal-based stealing experience patterned on
Steal a Brainrot's "wandering corridor of doors" hook:

- A **Steal portal** in the Cogworks (paired with the Sell portal —
  see `BAB-MARKETPLACE-HUB.md`) teleports the player into a
  procedurally-generated corridor.
- The corridor is filled with **doors** — each one leads to a *different
  player's hatchery* (the target of the steal).
- Doors are initially **unlabeled** — first visit is a guessing game.
- After a player has been through a door, **their personal instance of
  Bloom & Burgle remembers** what's behind it, surfaces the name, and
  the door becomes a known destination.
- A **map** shows the player's location in the corridor + the doors
  they've visited.
- A **click-to-snap navigation system** lets the player jump to a known
  point on the map without walking forever.

This solves several gameplay problems at once:

1. The current StealHandler has no discovery layer — players don't
  know what they're attacking. The corridor IS the discovery.
2. The map + door-memory creates a **personal cartographic
  collectible** — every player's map is unique. (TikTok content:
  "look at how many hatcheries I've mapped.")
3. Click-to-snap solves the "Roblox open-world walking sucks on
  mobile" problem for endgame stealers who already know their
  targets.
4. Procedural-per-visit means even regulars can't memorize a fixed
  layout — they have to use the map as the abstraction layer, which
  is the point.

## Approach

### Architecture: separate Place ID, shared DataStore

> User decision (2026-05-08): same heavier-lift pattern as the
> Marketplace — separate place, shared universe.

```
Universe: BAB
  ├── Place A: "Bloom & Burgle (Hatchery)"      -- existing
  ├── Place B: "Bloom & Burgle (Marketplace)"   -- per BAB-MARKETPLACE-HUB
  └── Place C: "Bloom & Burgle (Corridors)"     -- THIS ticket
```

### Procedural generation

> User decision (2026-05-08): **OK to proceed with procedural random
> layout per visit. We'll think through the labeling later.**

Per-visit generation. Each time a player teleports into the corridor
place, the server allocates them a fresh corridor instance (or reuses a
shared instance with all-fresh doors per player — see open question
below).

Layout generation per-instance:
- A **branching tree of corridor segments**. Each segment is 24×8
  studs, brass walls, dim cyan aether-lighting. Connect with
  90-degree turn pieces and 4-way junctions.
- Random parameters: `depth ∈ [4, 8]`, `branching_factor ∈ [2, 4]`,
  `door_density ∈ [0.4, 0.7]` (doors per segment-edge slot).
- Each room has 0–2 doors per wall (random); each door routes to a
  random *active* player's hatchery sampled from
  `MessagingService:PublishAsync` cross-server presence.
- Spawn lobby is at the root (always visible on map at center);
  return portal is placed at a leaf chosen at distance ≥4 from spawn.

Pseudocode:
```luau
function generateCorridor(seed: number)
    local rng = Random.new(seed)
    local rootRoom = Room.new()
    rootRoom.position = Vector3.new(0, 0, 0)
    local frontier = {rootRoom}
    while #frontier > 0 do
        local room = table.remove(frontier, 1)
        if room.depth >= rng:NextInteger(4, 8) then continue end
        for i = 1, rng:NextInteger(2, 4) do
            local child = room:spawnChildIn(rng)
            for _, wallSlot in child:walls() do
                if rng:NextNumber() < doorDensity then
                    local door = Door.new()
                    door.targetUid = sampleActivePlayer(rng)
                    door:attachTo(wallSlot)
                end
            end
            table.insert(frontier, child)
        end
    end
    placeReturnPortal(rng)
end
```

The generator is deterministic given `seed`, so we can replay a
player's last corridor for debugging — but the seed is fresh per
visit (no two visits the same).

### Door discovery + persistence

`DoorRouter` server-side handles the Touched/Prompt event on each
door. Sequence:

1. Player approaches door → prompt "Enter this door."
2. On confirm, `DoorRouter`:
    - Looks up `door.targetUid`.
    - Adds `(door.id, target.username)` to the player's
      `data.corridors.discoveredDoors` set in DataStore (de-duped).
    - Calls `TeleportService:TeleportToPlaceInstance(HATCHERY_PLACE_ID,
      targetServerJobId, {player}, ...)` to drop the thief into the
      victim's running server.
3. On the Hatchery side, the existing `StealHandler` runs as today —
   thief tries to steal; victim's alarm pylons fire (§2.3).

`data.corridors.discoveredDoors` schema:
```luau
{
    [doorIdAsHash] = {
        targetUid = 7965127581,
        targetUsername = "piddlywinx",
        firstVisitedAt = 1778260280,
        visitCount = 3,
    },
    ...
}
```

The hash key (instead of e.g. an array) lets us look up "have I been
through THIS specific door before?" in O(1) — but the doors aren't
re-instanced between visits because the corridor regenerates. So the
hash needs to be `target_uid + door_layout_seed_class` so the
"I recognize this door" check holds across regenerations.

Pragmatic v1: just use `targetUid` as the key. "I've been to this
hatchery before" is a sufficient first-pass for player intuition. We
can add door-fingerprinting later if it matters.

### Map UI

A Fusion-built minimap at the top-right of the screen (mobile-first
per §3.1):

- Player's current room: highlighted in `AetherCyan`.
- Discovered rooms (visited at least once this corridor instance):
  outlined `Brass`.
- Undiscovered rooms (in the player's line-of-sight or inside their
  knowledge boundary, e.g., 1 segment away): outlined dim gray.
- Beyond knowledge boundary: not drawn at all (the corridor extends
  beyond the visible map fog-of-war style).
- Doors:
    - Visited doors (player has walked through it once or more):
      labeled `"@ piddlywinx"` in `GoggleGold`.
    - Unvisited doors: small `?` glyph.

The map updates reactively via `Fusion.Value` cells that the server
streams to the client over `MapStreamer.MapUpdated:FireClient(player,
mapDelta)`. Fusion's diff-on-set is what makes this performant —
re-rendering 50 doors on every tick would tank mobile.

### Click-to-snap navigation

The map is interactive:

- **Click any visited room:** if the room is reachable from the
  player's current position via a path entirely through visited
  rooms, character "snaps" (`TweenService` 0.6s walk-arc) to the
  center of that room.
- **Click any visited door:** snaps the player adjacent to the door,
  facing it. One more confirm-tap enters.
- **Right-click (long-press on mobile)** on a visited room: pops a
  tooltip with the player names of any doors in that room.
- Snap is server-validated: client requests `SnapTo(roomId)` via
  RemoteEvent; server confirms target is reachable + visited, then
  teleports the character via `humanoid:MoveTo(...)` or a direct
  CFrame set.

Anti-exploit: the snap is rate-limited (1/sec) and validates that
the destination is a room the player has actually visited. No
free-form teleport.

### Return portal

Same shape as the marketplace's: a south-end portal sends the player
back to their own Hatchery via `TeleportService:TeleportAsync(
HATCHERY_PLACE_ID, ...)`.

### Entry fee

To prevent corridor-spam griefing, charge a small cash entry fee
(say, 100g per corridor session; configurable). Player who can't pay
gets a toast "Need 100g to rent a hat-and-mask." Telemetry event
`steal_corridor_entry_attempted` and `steal_corridor_entered`.

## Acceptance

- [ ] Steal portal exists in Cogworks, visible from spawn, dim red
  archway opposite the gold marketplace portal.
- [ ] Walking through deducts the entry fee + teleports to the
  corridor place.
- [ ] Corridor is freshly generated per visit (different seed each
  teleport-in).
- [ ] Layout is procedural — branches, has 4–8 depth, has multiple
  doors per room.
- [ ] Doors all route to **active** other-player hatcheries (no dead
  doors at minimum CCU).
- [ ] Map UI shows current room + visited rooms + visible doors.
  Updates as the player explores.
- [ ] Click-to-snap on a visited room walks the character there. Snap
  is rate-limited and validated.
- [ ] Walking through a door teleports the player into the target
  player's running Hatchery server, where the existing
  `StealHandler.server.luau` activates.
- [ ] After visiting a door, the player's local
  `discoveredDoors[targetUid]` is updated. Re-entering the corridor
  later, that door is labeled with the target's username.
- [ ] Return portal sends the player back to their own Hatchery.
- [ ] Telemetry: `steal_corridor_entered`, `steal_corridor_door_visited`,
  `steal_corridor_target_reached`, `steal_corridor_returned`.

## Open questions

1. **Per-player corridor or shared corridor?** Per-player (each
  thief gets their own private place instance) is simpler but
  expensive at scale. Shared (a corridor place hosts 8–12 thieves at
  once, all seeing different doors-on-the-same-walls) is more social
  but requires per-client door rendering. Proposed: **per-player at
  launch** for simplicity, switch to shared in live ops if CCU pain
  emerges.
2. **What if no other players are online?** Edge case at low CCU.
  Three options: (a) doors route to "ghost" hatcheries (saved player
  states with no live owner), (b) doors route to NPC-defended dummy
  hatcheries, (c) corridor has fewer/no doors and player gets a
  refund. Proposed: **(a)** — saved hatchery state is interesting
  even without the live player.
3. **Asynchronous defense.** When a thief enters a victim's
  hatchery, is the victim notified mid-attack? Yes — alarm pylons
  per §2.3. But what if the victim is offline? Open question — do
  the steal mechanics scale damages down for offline victims, or
  do we just preserve the raid as if the victim is "passively
  defending"? Proposed: scale damages down by 50% for
  asynchronous-victim raids; document in the existing
  StealHandler.
4. **Door labeling.** User said "we'll think through the labeling
  later." So initial implementation: doors are visually identical
  (no label) until visited; visited doors show the target's username
  in the map but not on the door itself. Iterate from there.
5. **Map fog-of-war range.** How far ahead can a player see
  unvisited rooms? Proposed: 1 segment in line-of-sight from any
  visited room. This makes "scouting" a real activity.
6. **Map persistence.** Does `discoveredDoors` persist across
  sessions (yes, per the user's description) or only across the
  current corridor visit? **Per the user**: persists across
  sessions. The map is a personal cartographic collection.
7. **Steal-back loop.** If knight-Anna gets stolen from while
  thief-Bob is in her hatchery, can Anna pursue Bob through the
  corridors? Open — interesting design question for v0.4+. Out of
  scope for v1.

## Defer

- Door labeling beyond username (e.g., "Anna's Hatchery — 3 mythic
  drakes spotted"). Wait for player feedback on what they actually
  want labeled.
- Cross-corridor messaging ("Bob is hunting!"). Live ops feature.
- Trap-laying inside corridors (defenders can sabotage the corridor
  layout to make it harder for thieves). Big design surface; out
  of scope.

## Log

- 2026-05-08 — User direction shift; Claude drafted ticket.
