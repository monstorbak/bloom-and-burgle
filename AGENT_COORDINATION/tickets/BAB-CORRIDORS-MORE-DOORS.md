# BAB-CORRIDORS-MORE-DOORS: scale up corridors v1 from 3 doors to procedural multi-room layout

**Owner:** unassigned
**State:** inbox (design — capture from playtest feedback; concrete next step toward the broader BAB-STEAL-CORRIDORS work)
**Priority:** P1 (immediate playtest gap — current 3-door room reads as too sparse)
**Extends:** [BAB-STEAL-CORRIDORS.md](BAB-STEAL-CORRIDORS.md) — concrete deliverable for the "procedural multi-room layouts" pending work in that ticket.

## Playtest signal

User feedback on the v1 Corridors scaffold (2026-05-08): *"The corridor has 3 doors. We will need more."*

The 1-room / 3-door scaffold was always intended as a v1 placeholder — see [BAB-STEAL-CORRIDORS.md](BAB-STEAL-CORRIDORS.md) Defer block. This ticket scopes the v2 expansion as the next focused PR.

## Approach

### Procedural multi-room layout

- Generate **N rooms** (target 4-6) connected by hallways, on enter.
- Each room has 3-5 doors. Total doors per visit: 12-25.
- Layout uses a deterministic seed per (player UID, ISO week number) so the same player sees a consistent map for a week (recognizability) but it changes weekly (novelty + anti-route-memorization for grief patterns).
- Visual variation per room: 3-4 styled themes (boilerwork tunnel / aether-conduit / collapsed-shaft / cogwork-junction) cycling deterministically.

### Door routing (keep the v1 pattern)

- Same as v1 — each door routes to a randomly-selected active player's hatchery via `TeleportService:TeleportAsync(hatcheryPlaceId, ...)` with the target player's UID in `TeleportData`.
- v2 layer (in scope here): probability-weighted by *which* player. Closer-to-player-class targets show up more often (matching steal economics). A hexer corridor-runner is more likely to land in another hexer's plot, where the steal targets are class-asset critters worth more.

### Map UI + nav

- Mini-map UI in the corner showing visited rooms + door labels.
- Click-to-snap nav (tap a door on the map → character path-walks to it).
- Per-player door-discovery persistence: doors you've previously walked through stay highlighted on subsequent visits. Reinforces the "this is YOUR corridor" feeling.

## Files touched (planned)

- modify `src-corridors/ServerScriptService/CorridorsBoot.server.luau` (procgen layout)
- new `src-corridors/ServerScriptService/CorridorsLayout.server.luau` (deterministic seeded room+door generator)
- new `src-corridors/ServerScriptService/DoorRouter.server.luau` (player-class-weighted target selection)
- modify `src-corridors/StarterPlayerScripts/CorridorsUI.client.luau` (mini-map + click-to-snap)
- new shared `src/ReplicatedStorage/Modules/CorridorsLayoutSchema.luau` (room/door types)
- new DataStore key `BloomAndBurgle_CorridorsDiscovered_v1` for per-player door discovery

## Acceptance

- [ ] On entry, a fresh visit shows 4-6 rooms with 12-25 total doors.
- [ ] Layout is deterministic per (UID, ISO week) — same player re-entering in the same week sees same layout.
- [ ] Each door teleports to a random active player's hatchery, weighted by class match.
- [ ] Mini-map UI shows visited rooms + door highlights.
- [ ] Per-player door-discovery persists across sessions.
- [ ] No regression on entry fee + return-portal flow from v1.
- [ ] Every door teleport is gated by `RateLimiter` per ADR-2.
- [ ] Corridor place builds + publishes cleanly.

## Open questions

- **MessagingService for "who's currently online" routing.** Need a presence-broadcast topic so the Corridors place knows which Hatchery servers are routable RIGHT NOW. Per BAB-STEAL-CORRIDORS open question.
- **Empty-target fallback.** If no other Hatchery servers are running (low-pop hours), what do doors route to? Options: a "ghost server" (placeholder NPC plot to steal from), or a "come back later" toast. Defer choice to playtest.
- **Maximum visits/day.** Without a cap, a determined player could exhaust most online Hatcheries' steal cooldowns. The 100g entry fee is the soft cap; reassess after playtest.

## Defer

- Cross-corridor PvP (multiple players in same corridor instance) — corridor stays single-player for now per BAB-STEAL-CORRIDORS.
- Lore reveals tied to door-discovery progress (à la BAB-MARKETPLACE-NPC-REPUTATION).

## Log

- 2026-05-08 — User playtest feedback: 3 doors too sparse. Scoped this ticket as the concrete next-step toward BAB-STEAL-CORRIDORS' "procedural multi-room layouts" deferred work.
