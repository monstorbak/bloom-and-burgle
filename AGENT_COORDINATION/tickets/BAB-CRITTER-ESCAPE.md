# BAB-CRITTER-ESCAPE: Ripe-window timer + escape mechanic + asset/liability behaviors

**Owner:** unassigned
**State:** inbox (design)
**Priority:** P1 (post-P1-arch — direction shift)
**Files touched (planned):**
- new `src/ServerScriptService/Critter/EscapeWindow.server.luau`
- new `src/ServerScriptService/Critter/EscapeBehaviors.luau`
- modify `src/ServerScriptService/Critter/GrowLoop.server.luau` (start escape timer on ripen)
- modify `src/ServerScriptService/Critter/HarvestFlow.luau` (cancel escape timer on harvest)
- modify `src/ServerScriptService/CritterVisuals.luau` (warning pulse as timer drains)
- modify `src/ReplicatedStorage/Modules/CritterData.luau` (mark `escapeBehavior` per species)
- modify `src/ServerScriptService/DataStore.luau` (persist escape state)
- new `src/StarterPlayerScripts/EscapeWarningHUD.client.luau` (alarm-pylon visual)

## Problem

Today the harvest loop is forgiving to a fault: when a pod ripens, the
ripe state persists indefinitely until the player walks over the pad
(BAB-011 changed the legacy auto-disappear to "stays ripe forever"
because auto-disappear was disliked). That's safe but flat: there's no
risk-pressure on the loop, no consequence for forgetting, and no opening
for the asset/liability dynamic that **§8 of `Bloom&Burgle_Design_Spec.md`**
calls "the heart of the design."

The new direction adds a **second timer that starts when the critter
ripens**: equal in duration to the ripening time itself. If the player
doesn't return inside that window, the critter **escapes the pod**,
producing one of two outcomes:

- **Asset critter** (per the player's class affinity in §8): the escaped
  critter helps the player — runs a beneficial passive behavior on the
  plot for some duration.
- **Liability critter** (per affinity): wreaks havoc — runs a damaging
  passive behavior against the player's plot.

This restores the design's economic tension (every minute matters again
for active players, but offline progression still works because the
behavior catalog includes both upsides and downsides), opens a
content-rich design surface (per-class × per-species behavior catalog),
and dovetails with §2.3's "Combat & raid lanes" (the alarm pylons are
already in the spec and now have a second trigger besides theft —
"liability went feral").

## Approach

### Timer ratio

> User decision (2026-05-08): **1:1 with grow time.** A species that takes
> 240s to ripen has a 240s escape window after ripening.

Rationale: this maps the player's "I planted this 4 minutes ago, I have
~4 minutes to come collect" to a single learnable rule. No per-species
or per-rarity tuning curve to balance up front. We can revisit if a
particular species feels too forgiving or too punishing.

State machine per planter:

```
EMPTY → INCUBATING → RIPE (timer T_escape = T_grow start) → ESCAPED → BEHAVIOR_ACTIVE → DESPAWNED → EMPTY
                       ↑                                       ↓
                       └── HARVESTED (player walks over) ──────┘
```

The `RIPE → HARVESTED` transition is the existing happy path
(`HarvestFlow.harvestPlanter`). The new code only adds the
`RIPE → ESCAPED → BEHAVIOR_ACTIVE → DESPAWNED → EMPTY` track.

### Server-side ownership

A new module **`Critter/EscapeWindow.server.luau`** runs the timer:

- Subscribes to the existing `Ripe` attribute change on every planter
  (or hooks into `GrowLoop`'s ripen branch to start a tracked task).
- On ripen, schedules `task.delay(growSeconds, doEscape, planter)`.
- On harvest (planter's `Ripe` attribute flips false), cancels the
  pending escape via a per-planter token check (no hot loop).
- On escape: clears the planter as if harvested (inventory does **not**
  receive the critter — it's gone), emits `pod_escaped` telemetry, then
  hands control to `EscapeBehaviors`.

### Behavior catalog: `Critter/EscapeBehaviors.luau`

Pure module. Exports a registry keyed by `(speciesId, classAffinity)`,
with `affinity` ∈ `{"asset", "liability", "neutral"}`. Each entry is a
struct:

```luau
type EscapeBehavior = {
    name: string,                            -- short label for telemetry/UI
    durationSeconds: number,                 -- how long the behavior runs
    sfx: string?,                            -- one-shot SFX on spawn
    -- Server fn that runs the behavior; returns a cleanup fn called on
    -- behavior expiry, plot-destroy, or player leave.
    activate: (player: Player, plot: Model) -> (() -> ())?,
}
```

The `activate` fn parents an Instance.new("Model") to the plot, hooks
its own task loop, etc. The cleanup fn unhooks everything.

### Behavior examples (user-confirmed seed entries)

User specified these two as the baseline:

| Species | Class | Affinity | Behavior |
|---|---|---|---|
| coal_drake | sky_pirate / hexer | asset | "Coal Forge: heats every incubator pod 1.5× — all pods on the plot ripen 50% faster for `durationSeconds`." |
| coal_drake | knight / tinkerer | liability | "Drake Strafe: every 8s, picks one ripe-or-incubating pod owned by the player and sets it on fire — pod becomes EMPTY, in-progress incubation lost. Behavior runs for `durationSeconds` or until the plot has no more pods to torch." |

Per §8 of `Bloom&Burgle_Design_Spec.md`, the affinity matrix has 12
species × 5 classes = 60 cells. Most cells are "neutral" (no
behavior — escape just despawns silently with a steam-puff). We need
**at minimum 2–3 behaviors per class** at launch (so each class has
a recognizable asset moment and a liability moment). Open question:
catalog is in this ticket as a follow-on table.

### Persistence

Escape state survives logout. New `data.plot.escapes` array on the
DataStore record:

```luau
escapes = {
    {
        slot = 5,                 -- 1..9 planter index
        species = "coal_drake",
        startedAt = 1778260280,   -- os.time() escape was triggered
        durationSeconds = 240,    -- how long the behavior runs
        affinity = "asset" | "liability",
    },
    ...
}
```

On `Persistence.restore`, behaviors with `startedAt + durationSeconds <
os.time()` are silently expired; in-progress ones get re-activated for
their remaining duration.

### Player-facing UX

While in the escape window:

- Pod's existing `EmptyBorder` aether window (currently pulses cyan when
  Ripe per `GrowLoop` line ~67) shifts hue toward **`ValveRed`** as the
  timer drains. At <25% remaining, it strobes red + the plot's alarm
  pylon (per §2.3 Design Spec) lights up.
- A new client-side **`EscapeWarningHUD`** shows a stacked list of "🐉
  Coal Drake — 1:34 to escape!" entries, sorted by time-remaining-asc.
  Mobile-first per §3.1.
- On escape: client-side BAB-STEAMPUNK toast: "💥 Coal Drake escaped! Your
  pods are on fire." (liability) or "✨ Coal Drake forged free! Pods will
  ripen 50% faster." (asset). Per §3.2 Toasts.

### Cancellation paths

The escape timer is cancelled by:
1. Player harvests the pod (existing `HarvestFlow.harvestPlanter`).
2. Player leaves the server (the cleanup fn runs on `PlayerRemoving`;
   on rejoin, persistence restores state).
3. Plot is destroyed (e.g., owner-change edge case).
4. `EscapeBehaviors` config has no entry for `(species, affinity)` —
   the escape becomes a silent no-op after the despawn (still emits
   telemetry).

## Acceptance

- [ ] Plant a brass_beetle (20s grow), don't harvest. After 40s total
  (20s grow + 20s escape window), pod is empty + escape behavior fires
  (or no-op for unconfigured species).
- [ ] Plant a coal_drake as a sky_pirate, miss the harvest window.
  Expect "Coal Forge" asset behavior — all 9 pods' grow timers tick at
  1.5× speed for the configured duration.
- [ ] Plant a coal_drake as a knight, miss the window. Expect "Drake
  Strafe" — periodic pod-on-fire events every 8s.
- [ ] Quit Studio mid-escape, rejoin. Behavior continues from its remaining
  duration (or expires cleanly if duration elapsed offline).
- [ ] Aether window strobes red in the last 25% of the escape window.
- [ ] EscapeWarningHUD shows stacked countdown for every escape-armed pod.
- [ ] `pod_escaped` telemetry event fires with `{species, class, affinity,
  behavior}` for analytics on which species/class combos go feral most.
- [ ] No regression on the existing harvest loop — measured by re-running
  the live verification from PR #7's handoff doc (cash math exact).

## Open questions

1. **Behavior visibility off-plot.** If a player is in the Cogworks (not
  on their plot) when escape fires, do they see the toast? Yes, but
  with a "(at your hatchery)" suffix.
2. **Multiple concurrent escapes.** Player ignores 9 pods, all 9 escape
  in close succession. Do behaviors stack or queue? Proposed: stack
  with diminishing returns (each additional same-behavior copy at 70%
  effect of the prior).
3. **Combat hooks.** §11 of Design Spec describes a combat system. Does
  a liability behavior count as combat for the purposes of upgrade
  durability damage (§10.4 + §11.4)? Proposed: yes — liability ferals
  damage upgrade slots, asset ferals do not.
4. **Cosmetic/SFX inventory.** Each escape needs at least 1 SFX. §4.1
  audio library doesn't list "feral spawn" or "drake fire". File a
  follow-on for audio design.
5. **Anti-grief.** A wealthy player could intentionally let liabilities
  go feral on weak players via raid mechanics? No — escape is on the
  *owner's* plot only. Raids are a separate path (§2.3).

## Defer

- The full 60-cell behavior catalog. Ship with 2–3 per class (12+ total),
  expand via live ops (§13).
- Stable-spawned behaviors (NURTURE'd liabilities going feral) — that's
  a separate ticket; this one is just "missed-harvest escape."

## Log

- 2026-05-08 — User direction shift; Claude drafted ticket.
