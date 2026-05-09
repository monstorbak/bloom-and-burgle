# BAB-PHASE-5-EVENT-TEMPLATE-AETHER-BLOOM: live-ops event runtime + first event (Aether Bloom)

**Owner:** unassigned
**State:** inbox (design — implementation-ready)
**Priority:** P1 (per spec §13: "the single biggest predictor of long-tail revenue")

**Files touched (planned):**

- new `src/ServerScriptService/Events/EventRuntime.server.luau` (reads schedule, applies modifier flips, broadcasts via MessagingService)
- new `src/ServerScriptService/Events/EventModifiers.luau` (pure-data registry of modifier types: spawnRateMultiplier, classFeature, payoutMultiplier, etc.)
- new `src/ReplicatedStorage/Modules/EventSchedule.luau` (parsed event manifest — single file = single source of truth for which events run when)
- new `tools/events/event-manifest.json` (the live-ops-friendly schedule file — flat JSON the team edits without touching code)
- new `src/StarterPlayerScripts/EventBannerHUD.client.luau` (top-screen banner during active events)
- modify `src/ServerScriptService/Critter/PlantingFlow.server.luau` (apply event spawn-rate modifiers)
- modify `src/ServerScriptService/Critter/EconomyPad.luau` (apply event payout modifiers)
- modify `src-marketplace/ServerScriptService/MerchantPersonalities.luau` (mark NPC stalls with featured-class banner during events)

## Problem

Live ops is the long-tail revenue driver per spec §13. We have **zero
infrastructure** for running events today:
- No schedule format
- No modifier system (×2 spawn rate, class-X-featured, etc.)
- No client UI for "an event is running"
- No telemetry seam to measure event lift

Without all four, every event would be a hand-coded one-off. The whole
point of live ops is **cheap-to-author cadence**: ship the runtime once,
then tweak `event-manifest.json` weekly to crank events forever.

## Approach

### Event manifest (`tools/events/event-manifest.json`)

Flat JSON, edited by the live-ops team without code review:

```json
{
  "events": [
    {
      "id": "aether_bloom_2026_05",
      "displayName": "Aether Bloom",
      "subtitle": "Hexers featured · Magical critters spawn 2× as often",
      "startUtc": "2026-05-15T18:00:00Z",
      "endUtc":   "2026-05-17T22:00:00Z",
      "modifiers": [
        { "type": "spawnRateMultiplier", "filter": { "hatchArchetype": ["magicalFamiliar", "magicalCritter"] }, "value": 2.0 },
        { "type": "classFeature",        "class": "hexer" },
        { "type": "payoutMultiplier",    "filter": { "tag": "Sacred" }, "value": 1.3 }
      ],
      "bannerColor": "AetherCyan",
      "bannerEmoji": "🜍"
    }
  ]
}
```

`EventSchedule.luau` parses this and exports:
- `EventSchedule.activeEvents(now: number): { Event }` — events whose
  startUtc ≤ now < endUtc
- `EventSchedule.modifiers(): { Modifier }` — flattened list of active
  modifiers across all active events

### Modifier types (initial set)

| Type | Effect | Where applied |
|---|---|---|
| `spawnRateMultiplier` | Multiplies the rate at which a filtered species shows up at the Egg Emporium | PlantingFlow.luau when stocking the seed shop |
| `payoutMultiplier` | Multiplies the sell payout for a filtered species | EconomyPad.luau / MerchantSellFlow.luau |
| `growSpeedMultiplier` | Speeds up grow time for a filtered species | GrowLoop.luau |
| `classFeature` | Marks a class as "featured" — used by NPC stalls + UI banner | MerchantPersonalities + UI |

The pure-data nature lets us add modifiers without touching the runtime
— each new type adds one switch case in `EventRuntime.applyModifiers()`.

### EventRuntime

Server-side `EventRuntime.server.luau` boots, polls `EventSchedule` once
per minute, applies modifiers via `Workspace.EventModifier_*` attributes
(so they're observable from client + server). Broadcasts a state change
via `bab-event-state-v1` MessagingService topic so all servers update
within 60s of an event starting/ending.

Cleanup on event end: clear all attributes; emit
`Telemetry.track("event_ended", { eventId, durationSeconds, ... })`.

### Client UX

`EventBannerHUD.client.luau` listens for the `bab-event-state-v1` topic
and renders a top-screen banner during active events:

```
🜍  AETHER BLOOM  ·  Hexers featured · 2× magical · 1d 4h left
```

Banner fades in on event start, fades out on event end. Color from
`bannerColor` field, emoji from `bannerEmoji`. Tap-through to a small
modal explaining the event's modifiers in plain language.

### First event: Aether Bloom

Per the manifest above:
- 52-hour window (Friday 6pm UTC → Sunday 10pm UTC) — the standard
  "weekend takeover" cadence.
- Magical species (`magicalFamiliar` + `magicalCritter`) spawn 2× more
  often at the Egg Emporium.
- Hexer class featured — NPC stalls show a "🜍 HEXERS WELCOME" sub-banner.
- Sacred-tagged critters (Patina Toad currently) get a 1.3× payout
  multiplier across all merchants.

Designed to onboard the Hexer class into a focused playthrough. Event
ends, modifiers clear, but Hexer players have a cohort of cool critters
in their stable.

## Acceptance

- [ ] `event-manifest.json` parsed correctly; invalid manifest fails fast at boot with a clear error.
- [ ] Active event modifiers apply within 60s of startUtc.
- [ ] Modifiers cleared within 60s of endUtc.
- [ ] Cross-server consistency: all servers globally see the same active events.
- [ ] EventBannerHUD shows the correct banner during the event.
- [ ] During Aether Bloom, magical critters appear at 2× rate at the Egg Emporium.
- [ ] During Aether Bloom, Sacred critters sold to any NPC get the 1.3× event multiplier (stacks with NPC's own multiplier, capped at the standard 3.0× cap).
- [ ] `Telemetry.track("event_started" / "event_ended", ...)` fires for each event.
- [ ] Schedule edit (push to `event-manifest.json`) propagates after a place republish — no code change required.

## Open questions

1. **Modifier stacking.** If two events run simultaneously and both touch the same multiplier (e.g., one is "+50% sell" and another is "+30% sell magical"), do they stack additive or multiplicative? Recommend **additive** (1 + 0.5 + 0.3 = 1.8) — easier to reason about; cap at the existing 3.0× ceiling.
2. **Manifest hot-reload.** Currently a publish is required to pick up manifest edits. Hot-reload via Workspace attribute override is possible but adds complexity. Defer.
3. **Per-class events.** Aether Bloom features Hexers. Should other events feature other classes on a rotation (Knight week, Sky-Pirate week)? Yes — recommend a 5-week rotation as the baseline cadence post-launch.
4. **Audio cue.** A class-themed musical sting on event start would be perfect virality bait. Out of scope for this phase; flagged for an audio-design pass post-launch.
5. **Reward redemption.** Post-event, do players get a one-time "thanks for playing during the event" reward? Recommend a small stash gift (1 random Sacred critter) — tracked in DataStore via `data.events.aether_bloom_2026_05.rewardClaimed`. Add later.

## Defer

- Per-event quests / objectives ("hatch 5 magical critters during Aether Bloom"). Phase 5.B.
- Limited-edition cosmetic rewards. Requires the cosmetic-unlock infra from later tickets.
- Live-ops dashboard for ops-team scheduling. CLI-edit-the-JSON is fine until DAU > 1000.

## Log

- 2026-05-08 — Direction shift session; folded into prioritized roadmap. Drafted ticket.
