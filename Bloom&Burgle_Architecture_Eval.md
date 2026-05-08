# Bloom & Burgle — Architecture Evaluation

**Date:** 2026-05-07
**Scope:** Roblox place — server scripts, client scripts, shared modules, persistence, build/deploy.
**Goal:** Assess the current architecture against the **$10K/month + viral starting point** product goal and surface the highest-leverage improvements.

## Snapshot

- **5,042 lines of Luau** across 13 server scripts, 8 client scripts, and 3 shared modules.
- **13 RemoteEvents** — all live as `.model.json` files synced via Rojo or hand-created via the Studio MCP bridge.
- **Single DataStore** (`BloomAndBurgleData_v1`), keyed `player_<UserId>`.
- **Tooling:** Rojo 7.6.1, Mantle 0.11.18 (broken upstream — replaced by `scripts/publish.sh` Open Cloud), a custom Studio MCP bridge at `127.0.0.1:7878`, and a 16-subcommand `dbg` CLI for autonomous debugging.
- **Live-state today:** sell / scrap pads, hatcheries, Class Hall picker, day/night cycle, and the headline harvest loop are all functional. PR [#1](https://github.com/monstorbak/bloom-and-burgle/pull/1) carries the steampunk pivot.

```
                   ┌────────────────────────────────┐
                   │   Roblox Client (LocalPlayer)  │
                   │ ┌─────┐ ┌─────────┐ ┌────────┐ │
                   │ │ HUD │ │ Picker  │ │ Waypt  │ │
                   │ └─────┘ └─────────┘ └────────┘ │
                   └──────┬──────────────┬──────────┘
                          │ RemoteEvents │     uses Modules
                          ▼              ▼
                   ┌──────────────────────────────┐
                   │       ReplicatedStorage      │
                   │   BrandColors • ClassData    │
                   │       • PlantData            │
                   └──────────────────────────────┘
                          ▲              ▲
                          │ require      │
                   ┌──────┴──────────────┴──────────┐
                   │            Server              │
                   │ ┌──────────────────────────────┐│
                   │ │ PlantHandler (620 LOC,       ││
                   │ │  monolithic — plant/grow/    ││
                   │ │  harvest/sell/scrap/persist) ││
                   │ └──────────────────────────────┘│
                   │ PlotMgr • SeedShop • Steal      │
                   │ Class • Lighting • Datastore    │
                   │ Devmode • Devproduct • Gamepass │
                   │ Leaderstats (orchestrator)      │
                   └──────────┬──────────────────────┘
                              │
                              ▼
                       Roblox DataStore
```

## What's working

| Area | Why it works |
| --- | --- |
| **Server-authoritative currency** | `Cash` and `CogParts` only mutate inside server `.server.luau` scripts after RemoteEvent validation. Client never writes leaderstats directly. |
| **DataStore reliability** | Retry-with-exponential-backoff (3 attempts) + deep-merge `backfill` on load means new schema fields don't nuke older saves. Critical for the steampunk pivot. |
| **Centralized brand assets** | `BrandColors.luau` + `ClassData.luau` + `PlantData.luau` are pure data modules — easy to evolve, easy to mock, easy to test. |
| **Two-layer touch handling** | Sell/scrap pads use both `.Touched` AND a 4 Hz server-side proximity pulse. Roblox's `.Touched` is famously flaky on Anchored sensors after teleport / respawn — the proximity pulse closes that gap. (Verified: cog parts went 108 → 246 via `Humanoid:MoveTo`.) |
| **Worktree + `dbg` CLI** | `scripts/debug/dbg` plus `DebugHooks.server.luau` give us live introspection without leaving the conversation. Force-injecting state, screenshotting, syncing files, and end-to-end smoke tests all work from the terminal. |
| **Atomic plot rebuild** | `PlotManager.rebuildFromSave` recovers from cold join. Slot tracking is per-server but falls back to "first empty" if the saved slot is taken. |
| **HttpService enabled in project.json** | Pre-wired for telemetry / analytics — just needs a sink. |

## What's hurting us — ranked by blast radius

### 🔴 P0 — viral-launch blockers (revenue + retention risk)

#### 1. **Server `_G` registry is the only bridge between server scripts**
`LeaderstatsScript` calls `_G.PlantHandler.snapshot(player)` and `_G.PlotManager.rebuildFromSave(player, slot)` because PlantHandler / PlotManager are `.server.luau` Scripts (not `ModuleScript`s) and Rojo refuses to load them as modules. Today this works because `LeaderstatsScript` polls `_G[name]` for up to 5s with `waitForGlobal`. It's a load-order race waiting to happen, has no type safety, and breaks every time `push-to-studio.sh` destroys+recreates a Script during Play (we hit this twice during the steampunk pivot).

**Impact**: silent save drops if PlantHandler crashes mid-snapshot, no IDE jump-to-def, hostile to onboarding new contributors, and the root cause of the "mid-play sync turns the game into a brick" bug.

#### 2. **No anti-exploit on the auto-harvest+sell loop**
The proximity pulse fires every 0.25s when the player's HRP is inside the pad's AABB. Per-pad cooldown is 0.5s. An exploiter who scripts `HumanoidRootPart.CFrame = sellPad.Position` in a tight loop trivially walks past the cooldown by alternating `SellPad → ScrapPad → SellPad` (each pad has its own cooldown), or by injecting fake ripe pods via `SetAttribute` calls on planters they don't own (we *do* gate this with `OwnerUserId`, but no rate limit on harvest count or velocity).

**Impact**: economy inflation on Day 1, Robux refund storm, leaderboard becomes meaningless. Top simulators get botted within hours of breakout. We have to ship with rate limits or eat economy reset.

#### 3. **Zero telemetry**
`HttpService.HttpEnabled = true` is set, but no script calls `HttpService:RequestAsync`. We can't measure: D1/D7/D30 retention, harvest-to-sell conversion, average session length per class, drop-off step in the 90s onboarding hook, or `dev product` purchase funnel. Without this we can't tune the economy, can't iterate the onboarding to hit the 90-second mark for "every player reaches first sell," and can't justify ad spend.

**Impact**: blind iteration. The single biggest predictor of long-tail Roblox revenue is **fast feedback loops on funnel data** — and we have none.

#### 4. **Material discipline already drifting**
`Bloom&Burgle_Design_Spec.md` §1.5 explicitly bans `SmoothPlastic`, `Plastic`, `Glass`, `Foil`. `PlantVisuals.luau` uses `SmoothPlastic` on critter Body / Head / Wings / Tail / Segment parts (5 occurrences). Visually small, but signals to reviewers that the spec's anti-pattern table isn't enforced — and the pastel-banned rule will drift next.

**Impact**: aesthetic erosion. Per spec §11 anti-patterns, this regresses the "this isn't another simulator" thumbnail moment.

### 🟡 P1 — friction that compounds with each new feature

#### 5. **`PlantHandler.server.luau` is 620 LOC doing seven jobs**
Planting, growing-tick, harvest-on-touch, sell-pad wiring, scrap-pad wiring, proximity pulse, persistence snapshot/restore, mutation rolls, *and* the in-flight class auto-harvest helper — all in one Script. The two sell paths (`.Touched` + proximity pulse) are now copy-pasted four times (once each for sell/scrap × Touched/pulse). Any new mechanic (e.g. NURTURE → stable) means a fifth and sixth copy.

**Impact**: every feature touches this file, every PR has merge conflicts here, and the `_G` API surface (`snapshot`, `restore`, `snapshotStable`) is invisibly entangled.

#### 6. **Semantic drift: "Plant" vs "Critter"**
The game is now critter-hatching but the modules / scripts / tags / DataStore keys all say "Plant" (`PlantData.luau`, `PlantHandler`, `PlantVisuals`, tag `"Planter"`, attribute `"PlantedSpecies"`). Every new contributor has to internalize this Hungarian-notation lie. Compounds bug #5 — the file name doesn't tell you what's inside.

#### 7. **Hand-rolled `Instance.new` UI**
`CashHUD` is 379 lines of imperative UI mutation. No component reuse, no diff-based updates, no easy way to A/B test variants. The new `ClassPickerUI` (270 lines) and `SellWaypointHUD` (210 lines) duplicate the same UICorner / UIStroke / TextLabel construction patterns. The UI layer is the highest-touch surface (every viral hook lives here) and the most expensive to iterate.

#### 8. **Push-to-studio destroys+recreates Scripts during Play**
`scripts/push-to-studio.sh` step 1 always `Destroy()`s the target Instance, step 2 creates fresh + writes content. During Play mode, step 1 propagates to the runtime DataModel but step 2 only lands in Edit. Net result: live game loses the script and silently breaks (we hit this with `DebugHooks` and `PlantHandler` during this session). We work around it by stopping Play before each sync.

#### 9. **Rojo + MCP-bridge sync paths are dual-tracked**
The repo uses Rojo 7.6.1 (`default.project.json`) for a `.rbxlx` build, but the dev loop uses `scripts/push-to-studio.sh` (MCP bridge) instead of `rojo serve`. RemoteEvents added during this session were created via `dbg eval` because `.model.json` files only land via a full Rojo build / re-open. Two parallel sync mechanisms guarantees confusion when contributors don't know which is canonical.

### 🟢 P2 — will start to bite at scale

#### 10. **Proximity pulse is O(players × pads) every 250 ms**
With 16 plots × 4 pads (Sell.Base, Sell.Sensor, Scrap.Base, Scrap.Sensor) × 30 players, that's 1,920 AABB checks per pulse, 7,680 per second. Functional today but doubles when we add Repair Bay and any new walk-on stations (§2 of the spec adds 6 more).

#### 11. **No spatial index for plot ownership**
`PlantHandler` enumerates `CollectionService:GetTagged("Planter")` on every grow tick and every harvest-all call. With 16 plots × 9 pods = 144 planters per server, that's 144 attribute lookups every Heartbeat (60 Hz). Acceptable now, will burn frames at scale.

#### 12. **Single-server world, no cross-server economy**
Spec §17 calls this out as an open question; we're shipping with instanced 16-plot servers and a per-server leaderboard. Trophy Hall (§2.7), trade economy, and visit-a-friend all need cross-server backing — none exists.

#### 13. **No transactional currency ledger**
Sell and scrap mutate `Cash.Value` and `CogParts` attribute directly. If a yield (`task.wait`) runs mid-mutation while a second pulse fires (race), or if save fails, we have no audit trail. For modest scale this is fine; for $10K/mo where any duplicate-payout exploit goes viral on TikTok, we need better.

#### 14. **No automated tests**
Pure data modules (`PlantData`, `ClassData`, `BrandColors`) are trivially testable in Lemur or TestEZ but have zero coverage. Asset/liability matrix in particular (60 cells) is brittle to regression — a stray edit could swap "asset" and "liability" for a class and we'd ship the bug.

## Recommended improvements — prioritized

### P0 — do these before public launch

#### ADR-1: Replace server `_G` registry with a typed Service module

**Status:** Proposed
**Decision:** Introduce `src/ServerScriptService/Services.luau` (ModuleScript) that holds typed references to each server subsystem. Each `.server.luau` Script calls `Services.register("PlantHandler", api)` on load, and consumers `await(Services.get("PlantHandler"))` instead of polling `_G`.

| Dimension | Today (`_G`) | Proposed (`Services` module) |
|---|---|---|
| Type safety | None | Strict mode + exported `type ServiceMap = {...}` |
| Load-order safety | Poll-with-timeout | Single `await` future per service |
| IDE support | None | Jump-to-def, autocomplete |
| Survives push-to-studio destroy | No (closure dies) | No (same problem) — but central `ServicesRegistry` is a pure Module that *can* survive a single-Script restart |
| Migration cost | — | ~80 LOC change, mechanical |

**Action:**
1. Create `Services.luau` with `register`/`await`/`get` and a typed `ServiceMap`.
2. Migrate `_G.PlantHandler` and `_G.PlotManager` callers in `LeaderstatsScript`.
3. Keep `_G.BabDebug` (debug-only, lives outside the production graph).

#### ADR-2: Anti-exploit pass on currency-mutating RemoteEvents and pads

**Decision:** Add a per-player rate limiter + sanity caps to every server entry point that touches `Cash` or `CogParts`.

| Entry point | Today | Add |
|---|---|---|
| `SellPad.Touched` / proximity | 0.5 s cooldown per player per pad | + max-per-minute (e.g. 12 sells/min) + max-payout-per-pulse (e.g. clamp at species top tier × 9 pods) |
| `ScrapPad.Touched` / proximity | 0.5 s | same |
| `BuySeed` RemoteEvent | none | rate limit 4/s, qty clamped 1..10 (already 1..100 — too loose) |
| `PlantInPlot` / `PlantSeed` | none | rate limit 9/s (one per pod) |
| `StealAttempt` | exists in StealHandler — verify | per-target-per-minute cap |

**Action:** A single `RateLimiter.luau` ModuleScript exposing `RateLimiter.tryConsume(userId, key, perSecond, burst)` token-bucket. Apply at the top of every `OnServerEvent` handler and every Touched closure. Log violations as `[BAB-EXPLOIT]` so `dbg errors` surfaces them.

#### ADR-3: Telemetry skeleton via HttpService

**Decision:** Wire a `Telemetry.luau` ModuleScript that batches events to a single HTTP endpoint. Buffer 30s or 50 events, whichever first. PostHog / a self-hosted collector / a $5/mo Cloudflare Worker — all viable.

**Required events at launch:**
| Event | When | Why |
|---|---|---|
| `session_start` | PlayerAdded | DAU |
| `class_picked` | ClassHandler | Class distribution + balance |
| `pod_loaded` | plantSeedAt | Engagement depth |
| `pod_ripened` | grow tick | Loop health |
| `harvest_decision` | (eventually HarvestModal) | The viral hook |
| `sell_payout` | sell logic — include amount, mutations, species mix | Economy tuning |
| `scrap_payout` | scrap logic | Cog parts balance |
| `gamepass_purchased` | GamepassHandler | Conversion |
| `dev_product_purchased` | DevProductHandler | ARPPU |
| `error_caught` | ScriptContext.Error | Crash rate |

Half a day of work, infinite leverage.

#### Material discipline fix

**Action:** Replace 5 `SmoothPlastic` usages in `PlantVisuals.luau` with `Metal` (body, head, segments) and `Marble` or `CorrodedMetal` (wings, tail). Add a CI grep step to `scripts/build.sh` that fails the build if any banned material appears outside an allowlist (only legal in `StarterPlayerScripts/PlanterUI` etc.).

### P1 — do these in the next sprint

#### ADR-4: Split `PlantHandler` into focused modules

**Decision:** Migrate `.server.luau` Script → `.luau` ModuleScript wherever possible, extract by responsibility:

```
src/ServerScriptService/Critter/
  CritterRegistry.luau   — module-local inventory[userId][species:mutation]
  GrowLoop.server.luau   — Heartbeat tick, ripen attribute, pod glow
  HarvestFlow.luau       — harvestPlanter, harvestAllRipeForPlayer (used by sell+scrap)
  EconomyPad.luau        — shared sell+scrap entry: takes a "convert(inv) -> payout" fn
  SellPad.server.luau    — wires SellPad tag, calls EconomyPad.convert(inv, sellRule)
  ScrapPad.server.luau   — same shape
  ProximityPulse.server.luau — single 4Hz loop, fans out to pad handlers
  Persistence.luau       — snapshot/restore (keeps the `Services.register` pattern)
```

This makes the four-copy harvest+sell duplication into a single `EconomyPad.convert` call site. It also lets us unit-test `HarvestFlow.luau` without spinning up a Roblox runtime.

#### ADR-5: Rename `Plant*` → `Critter*` (with backward-compat shim)

**Decision:** Rename the modules + tags in code, *but* keep `data.plot.planters` and the `"Planter"` CollectionService tag as DataStore-key compatibility shims. Add comments explaining the legacy.

```
PlantData.luau   → CritterData.luau (re-export from old name for one release)
PlantHandler     → CritterHandler (after split per ADR-4)
PlantVisuals     → CritterVisuals
"Planter" tag stays — it's load-bearing in saves.
```

Mechanical refactor, ~2 hours, eliminates future onboarding tax.

#### ADR-6: UI framework — Fusion 0.3+ for new screens

**Decision:** Adopt **Fusion** (Roblox-native reactive framework) for new UI surfaces (HarvestModal, Stable, Repair Bay). Don't rewrite existing UIs immediately — let them age out.

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Status quo (Instance.new)** | Zero learning curve, no deps | 379-LOC HUDs, no diffing, no reuse | ❌ |
| **Roact 1.4** | Mature, Anthropic-internal precedent | Component churn, JSX-style verbose | OK |
| **Fusion 0.3** | Reactive primitives match Roblox object model, minimal boilerplate, native to Luau | Newer, smaller community | ✅ |
| **Custom mini-framework** | Full control | We become framework maintainers | ❌ |

**Action:**
1. Add Fusion to Wally / via Rojo as a Package.
2. Build the next new UI (HarvestModal) in Fusion as the precedent.
3. Migrate `ClassBadgeHUD` next (small, persistent, attribute-bound — perfect for reactive).

#### Fix push-to-studio for Play mode

**Action:** Update `scripts/push-to-studio.sh` to detect Play state via the bridge's `execute_luau "RunService:IsRunning()"`. If Play is running and the file is a server `.server.luau`, **refuse** the sync with a clear error: "Stop Play first; server scripts cannot be hot-reloaded." Better: add an Edit-mode-only `dbg sync` that pre-flights this. Best: use `rojo serve` for Edit-time sync (live and well-supported), keep MCP bridge for runtime introspection only.

### P2 — within the first month after launch

7. **Spatial index** — Group pads by `slotIndex` so the proximity pulse only iterates the player's own plot.
8. **Cross-server economy** — MessagingService for top-N leaderboards, OrderedDataStore for global "Greatest Menagerie."
9. **Currency ledger** — Append-only `transactions: { ts, type, delta, reason }` array per player. Saves with the rest of the data. Audit trail for support, anti-fraud, balance changes.
10. **Test coverage on data modules** — TestEZ + a `tests/` folder. Top targets: `PlantData.affinityFor` (60 cells), `PlantData.rollMutation` distribution, `ClassData.list` ordering, `BrandColors.lerpToWhite/Black` clamping.
11. **Asset preload pipeline** — `ContentProvider:PreloadAsync` on join with the launch SFX library + critter meshes when those land.
12. **Live-ops remote config** — `MessagingService:SubscribeAsync("LiveOps")` to flip event flags (`bee_swarm_active`, `mythic_chance_multiplier`) without re-publishing the place.

## Trade-offs we're explicitly accepting

- **Single-DataStore single-write** (no OrderedDataStore yet, no UpdateAsync optimistic concurrency). Acceptable until cross-server features land.
- **No client-side prediction** — every harvest+sell waits a server roundtrip (~150 ms median in Roblox). Fine for a slow loop game; would not be fine for combat (defer to spec §11 combat work).
- **No automated load tests** — Roblox Studio's Local Server multi-player test is a poor proxy for production load. Acceptable for now; revisit if we get a CCU spike from a viral clip.

## Action item summary

- [ ] **P0** Replace server `_G` registry with `Services.luau` ([ADR-1](#adr-1))
- [ ] **P0** Add `RateLimiter.luau` + clamp every currency-mutating handler ([ADR-2](#adr-2))
- [ ] **P0** Wire `Telemetry.luau` to a collector with the 10 launch events ([ADR-3](#adr-3))
- [ ] **P0** Replace 5 `SmoothPlastic` usages in `PlantVisuals.luau`; add CI grep
- [ ] **P1** Split `PlantHandler` per [ADR-4](#adr-4)
- [ ] **P1** Rename `Plant*` → `Critter*` with backward-compat shim ([ADR-5](#adr-5))
- [ ] **P1** Adopt Fusion for new UI; build `HarvestModal` as the precedent ([ADR-6](#adr-6))
- [ ] **P1** Add Play-mode safety to `push-to-studio.sh`; document `rojo serve` as the Edit-time sync of record
- [ ] **P2** Spatial index for proximity pulse
- [ ] **P2** Cross-server economy (MessagingService + OrderedDataStore)
- [ ] **P2** Currency transaction ledger
- [ ] **P2** TestEZ harness on data modules
- [ ] **P2** ContentProvider:PreloadAsync on join
- [ ] **P2** Live-ops remote config via MessagingService

The four P0 items are the difference between a clean public-launch and one that catches fire: they protect the economy (anti-exploit), make iteration possible (telemetry), make the codebase survive its second contributor (`_G` → Services), and protect the visual identity that justifies the design spec (material discipline). None take more than a day; together they're about three days of work.
