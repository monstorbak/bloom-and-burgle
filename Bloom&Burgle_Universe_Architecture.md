# Bloom & Burgle — Universe Architecture

How the three places of the BAB universe are organized, what code is
shared between them, how they communicate, and where state lives.

**Reader:** any new contributor or future Claude session that needs to
add a feature, debug a cross-place bug, or understand "where does X go?"

**Date of last audit:** 2026-05-11. When the place IDs, project files, or
DataStore keys below change, update this doc.

---

## TL;DR

```
   Universe 10130205713 (Bloom & Burgle)
   ┌─────────────────────────────────────────────────────────────────┐
   │                                                                 │
   │   ┌──────────────┐    teleport    ┌──────────────┐              │
   │   │  Hatchery    │ ─────────────► │ Marketplace  │              │
   │   │ 9394836...   │ ◄───────────── │ 9050737...   │              │
   │   │ (start)      │                │              │              │
   │   └──────┬───────┘                └──────────────┘              │
   │          │                                                      │
   │          │ teleport                                             │
   │          ▼                                                      │
   │   ┌──────────────┐                                              │
   │   │  Corridors   │                                              │
   │   │ 9019010...   │                                              │
   │   └──────────────┘                                              │
   │                                                                 │
   │   All three share:                                              │
   │     • DataStore  BloomAndBurgleData_v1     (cash, stash, plot)  │
   │     • DataStore  BloomAndBurgleTrophy_v1   (leaderboards)       │
   │     • DataStore  BAB_DailyReward_v1        (cooldown timestamps)│
   │     • DataStore  BloomAndBurgle_Receipts_v1 (DevProduct idempotency)│
   │     • MessagingService  bab-presence-v1    (cross-server who's-online)│
   │     • ReplicatedStorage.Modules.* (Luau code shared by all 3)   │
   │                                                                 │
   └─────────────────────────────────────────────────────────────────┘
```

- **One Roblox universe**, three places. Same `UniverseId` → same DataStore
  scope → players keep their cash, plot, and stash across all three.
- **Hatchery is the start place.** New players land there. The other two
  are teleport destinations only.
- **No client-only shared modules** — anything in `src/ReplicatedStorage/`
  is server-and-client visible in all 3 places. Anything in
  `src/ServerScriptService/` is Hatchery-only; the other two pick the
  subset they need via explicit project.json bindings.

---

## Places + IDs

The canonical source for these is `src/ReplicatedStorage/Modules/BabPlaces.luau`.

| Place | ID | Project file | Source dirs |
|---|---|---|---|
| Hatchery (start) | `93948369125480` | `default.project.json` | `src/` |
| Marketplace | `90507376043667` | `default-marketplace.project.json` | `src-marketplace/` + selected `src/` files |
| Corridors | `90190105638268` | `default-corridors.project.json` | `src-corridors/` + selected `src/` files |
| Universe | `10130205713` | — | — |

**Override pattern** (per `BabPlaces.luau`): set
`Workspace:SetAttribute("MarketplacePlaceId", <id>)` to redirect a single
teleport without rebuilding the place. Used for staging. The compile-time
constants are the production values.

**Never change the place IDs without filing a P0** — losing the Hatchery
ID means `TeleportService:TeleportAsync(hatcheryId, ...)` returns players
to a non-existent place.

---

## Source layout

```
bloom-and-burgle/
├── default.project.json              # Hatchery
├── default-marketplace.project.json  # Marketplace
├── default-corridors.project.json    # Corridors
│
├── src/                              # Hatchery source + shared
│   ├── ReplicatedStorage/
│   │   ├── Modules/                  # SHARED ACROSS ALL 3 PLACES
│   │   │   ├── BabPlaces.luau            # place ID source of truth
│   │   │   ├── BrandColors.luau          # design tokens
│   │   │   ├── CritterData.luau          # species catalog (emoji, prices)
│   │   │   ├── CritterRigs.luau          # rig form profiles
│   │   │   ├── ClassData.luau            # class definitions
│   │   │   ├── MerchantPersonalities.luau
│   │   │   ├── MerchantPricing.luau      # pure-function pricing math
│   │   │   ├── NPCRotation.luau          # daily special rotation
│   │   │   ├── PlantData.luau            # legacy plants (pre-Critter)
│   │   │   ├── TrophyData.luau           # trophy-hall DataStore wrapper
│   │   │   ├── UIComponents.luau         # shared UI primitives
│   │   │   └── Fusion/                   # vendored reactive UI lib
│   │   └── RemoteEvents/                 # SHARED, model.json defs
│   │       └── *.model.json              # see RemoteEvents catalog below
│   │
│   ├── ServerScriptService/          # Hatchery-only (mostly)
│   │   ├── DataStore.luau                # primary store wrapper
│   │   ├── PresenceBroadcast.luau        # MessagingService heartbeat
│   │   ├── PlotManager.server.luau
│   │   ├── ClassHandler.server.luau
│   │   ├── SeedShop.server.luau
│   │   ├── StealPortal.server.luau       # Hatchery → Corridors teleport
│   │   ├── MarketplacePortal.server.luau # Hatchery → Marketplace teleport
│   │   ├── VisitFriendHandler.server.luau
│   │   ├── TrophyHallScript.server.luau
│   │   ├── ClocktowerScript.server.luau
│   │   ├── DailyRewardChest.server.luau
│   │   ├── TinkererPass.luau             # gamepass check module
│   │   ├── CritterVisuals.luau           # rig builder
│   │   ├── Telemetry.luau                # shared by all 3 via project.json
│   │   ├── TelemetryBoot.server.luau     # shared
│   │   ├── TelemetryConfig.luau          # generated by build.sh; gitignored
│   │   ├── GamepassConfig.luau           # generated by build.sh; gitignored
│   │   ├── RateLimiter.luau              # shared by all 3
│   │   ├── Services.luau                 # shared by all 3 (registry)
│   │   ├── DevMode.luau                  # admin chat commands
│   │   ├── DevProductHandler.server.luau
│   │   ├── GamepassHandler.server.luau
│   │   ├── DebugHooks.server.luau
│   │   ├── LeaderstatsScript.server.luau
│   │   ├── LightingBoot.server.luau
│   │   ├── StealHandler.server.luau
│   │   └── Critter/                      # nested per-feature subdir
│   │       ├── HarvestFlow.luau
│   │       ├── PlantingFlow.server.luau
│   │       ├── GrowLoop.server.luau
│   │       ├── EconomyPad.luau
│   │       ├── EscapeWindow.luau
│   │       ├── EscapeBehaviors.luau
│   │       ├── CritterRegistry.luau
│   │       └── Persistence.luau
│   │
│   ├── StarterPlayerScripts/         # Hatchery-only client scripts
│   │   ├── CashHUD.client.luau           # leaderstats, bottom nav
│   │   ├── ClassPickerUI.client.luau
│   │   ├── ClassBadgeHUD.client.luau
│   │   ├── HarvestModal.client.luau
│   │   ├── SeedShopUI.client.luau
│   │   ├── PlanterUI.client.luau
│   │   ├── FriendsListHUD.client.luau
│   │   ├── CritterCameraHooks.client.luau (Mythic ceremony etc)
│   │   ├── EscapeWarningHUD.client.luau
│   │   └── StealUI.client.luau
│   │
│   └── Workspace/
│       └── TownSquare.model.json         # Cogworks plaza geometry
│
├── src-marketplace/                  # Marketplace place exclusive
│   ├── ServerScriptService/
│   │   ├── MarketplaceBoot.server.luau   # builds plaza + return portal
│   │   ├── MerchantSellFlow.luau         # shared NPC flow
│   │   ├── BrassBart.server.luau
│   │   ├── Hexerine.server.luau
│   │   └── Verda.server.luau
│   └── StarterPlayerScripts/
│       └── MarketplaceUI.client.luau     # quote modal
│
└── src-corridors/                    # Corridors place exclusive
    ├── ServerScriptService/
    │   └── CorridorsBoot.server.luau     # whole place lives here (v1 stub)
    └── StarterPlayerScripts/
        └── CorridorsUI.client.luau
```

---

## What each place ships (per project.json)

### Hatchery (`default.project.json`)

Mounts everything under `src/` as-is:

```
ReplicatedStorage
  Modules         ← src/ReplicatedStorage/Modules
  RemoteEvents    ← src/ReplicatedStorage/RemoteEvents
ServerScriptService ← src/ServerScriptService  (entire directory)
ServerStorage       ← src/ServerStorage
StarterPlayer.StarterPlayerScripts ← src/StarterPlayerScripts
StarterGui          ← src/StarterGui
Workspace.TownSquare ← src/Workspace/TownSquare.model.json
Workspace.Baseplate  (4096×4096 Grass)
```

### Marketplace (`default-marketplace.project.json`)

Mounts `src-marketplace/` PLUS explicit selections from `src/`:

```
ReplicatedStorage.Modules       ← src/ReplicatedStorage/Modules     (shared)
ReplicatedStorage.RemoteEvents  ← src/ReplicatedStorage/RemoteEvents (shared)

ServerScriptService.* ← src-marketplace/ServerScriptService           (full)
ServerScriptService.Services        ← src/ServerScriptService/Services.luau
ServerScriptService.RateLimiter     ← src/ServerScriptService/RateLimiter.luau
ServerScriptService.Telemetry       ← src/ServerScriptService/Telemetry.luau
ServerScriptService.TelemetryBoot   ← src/ServerScriptService/TelemetryBoot.server.luau
ServerScriptService.TelemetryConfig ← src/ServerScriptService/TelemetryConfig.luau
ServerScriptService.DataStore       ← src/ServerScriptService/DataStore.luau

StarterPlayer.StarterPlayerScripts ← src-marketplace/StarterPlayerScripts (full)
Workspace.Baseplate (400×400 Cobblestone)
```

### Corridors (`default-corridors.project.json`)

Same shape as Marketplace, but uses `src-corridors/` as the place-
exclusive root.

### What this means in practice

- **Adding a new shared module:** drop it in `src/ReplicatedStorage/Modules/`.
  All 3 places see it automatically.
- **Adding a new server module that should be shared:** add the file under
  `src/ServerScriptService/`, then explicitly mount it in
  `default-marketplace.project.json` and `default-corridors.project.json`
  (otherwise only the Hatchery sees it).
- **Adding a new RemoteEvent:** add a `.model.json` in
  `src/ReplicatedStorage/RemoteEvents/`. All 3 places see it.
- **Adding a Marketplace-only feature:** put it in `src-marketplace/`.
  No project.json edits needed.

---

## DataStores

All four DataStores are scoped by `UniverseId = 10130205713`, so any place
in the universe reads/writes the same per-player data.

| Key | Wrapper | Shape | Written from |
|---|---|---|---|
| `BloomAndBurgleData_v1` | `src/ServerScriptService/DataStore.luau` | `{ cash, lifetimeCash, plot { stash, …, planters }, class, … }` per `player_<userId>` | Hatchery: any handler that mutates cash. Marketplace: `MerchantSellFlow` |
| `BloomAndBurgleTrophy_v1` | `src/ReplicatedStorage/Modules/TrophyData.luau` | `{ [category] = { Entry, Entry, … } }` (top N) | Hatchery: `HarvestFlow` (mythic_hatch). Marketplace: `MerchantSellFlow` (hall_of_sales) |
| `BAB_DailyReward_v1` | inline in `src/ServerScriptService/DailyRewardChest.server.luau` | `{ lastClaimSec }` per `player_<userId>` | Hatchery: `DailyRewardChest` |
| `BloomAndBurgle_Receipts_v1` | inline in `src/ServerScriptService/DevProductHandler.server.luau` | dev-product receipt ledger for idempotency | Hatchery: `DevProductHandler` |

### Concurrency

`BloomAndBurgleData_v1` is written by **all 3 places** for the same
player's `player_<userId>` key. Cross-server writes use `UpdateAsync` with
the standard merge pattern. Specifically, the marketplace `MerchantSellFlow`
calls `dataStore:UpdateAsync(dataKey(player), function(data) ...)` so
concurrent writes (e.g. player on Hatchery harvests while their
Marketplace transaction commits) retry safely.

Same pattern for `BloomAndBurgleTrophy_v1`.

⚠ **Never use `SetAsync` for player data.** Cross-place writes will race.

---

## MessagingService topics

| Topic | Direction | Payload | Used by |
|---|---|---|---|
| `bab-presence-v1` | Every Hatchery server publishes heartbeat for each player every 30s; every Hatchery server subscribes | `{ userId, displayName, plotIndex, class, placeId, jobId, ts }` | `src/ServerScriptService/PresenceBroadcast.luau` |

Presence entries expire after 90s (3× heartbeat). Drives the Friends-
panel "who's online in any BAB server?" check and the visit-friend
teleport target lookup.

Topic is Hatchery-only. Marketplace + Corridors don't publish presence
(those aren't visit-destinations).

If a future feature needs cross-server pub/sub, **add the topic name to
this table when you create it.** The MessagingService rate-limit is
~600 msgs/min/topic — knowing existing usage helps you avoid stepping on
the limit.

---

## RemoteEvents

The 12 named RemoteEvents shipped at startup live in
`src/ReplicatedStorage/RemoteEvents/*.model.json`. Below is the catalog
plus lazy-created ones (the kind you find at runtime via `FindFirstChild`
+ `Instance.new` in some boot script).

### Pre-declared (model.json definitions, all 3 places see them)

| RemoteEvent | Server-side handler | Client-side caller / consumer |
|---|---|---|
| `BuySeed` | `SeedShop.server.luau` | `SeedShopUI.client.luau` |
| `OpenShop` | `SeedShop.server.luau` | `CashHUD.client.luau` |
| `PlantSeed` | `Critter/PlantingFlow.server.luau` | `PlanterUI.client.luau` |
| `PlantInPlot` | `SeedShop.server.luau` (auto-plant flow) | client |
| `SellPlants` | `Critter/EconomyPad.luau` | client (Touched-driven server side) |
| `ScrapPlants` | `Critter/EconomyPad.luau` | `ClassBadgeHUD.client.luau` |
| `HarvestPopup` | `Critter/HarvestFlow.luau` (server fires to client) | `HarvestModal.client.luau` |
| `PickClass` | `ClassHandler.server.luau` | `ClassPickerUI.client.luau` |
| `PlotClaimed` | `PlotManager.server.luau` | `CashHUD.client.luau` |
| `ReturnToPlot` | `PlotManager.server.luau` | `CashHUD.client.luau` |
| `StealAttempt` | `StealHandler.server.luau` | `StealUI.client.luau` |
| `StealNotification` | `StealHandler.server.luau` (fires to victim) | `StealUI.client.luau` |

### Lazy-created (Instance.new on server boot)

| RemoteEvent | Created by | Listeners |
|---|---|---|
| `CritterCeremony` | `CritterVisuals.luau` | `CritterCameraHooks.client.luau` |
| `VisitFriend` | `VisitFriendHandler.server.luau` | `FriendsListHUD.client.luau` |
| `MarketplaceSell` | `MerchantSellFlow.luau` (Marketplace place) | `MarketplaceUI.client.luau` |

### Lazy-created RemoteFunctions

| RemoteFunction | Created by | Consumers |
|---|---|---|
| `GetOnlinePresence` | `VisitFriendHandler.server.luau` (Hatchery) | `FriendsListHUD.client.luau` |

If you add a new RemoteEvent: prefer a `.model.json` declaration in
`src/ReplicatedStorage/RemoteEvents/` over `Instance.new` at boot. The
declarative path is grep-able and survives Studio Edit-mode inspection;
lazy creation is invisible until a Play session runs.

---

## Cross-place teleport flow

### Hatchery → Marketplace

```
src/ServerScriptService/MarketplacePortal.server.luau
  player.Touched on the brass arch
    → critterHandler.snapshot(player)        # flush DataStore early
    → TeleportOptions:SetTeleportData({
        from = "hatchery",
        hatcheryPlaceId = BabPlaces.hatchery(),
        carriedClass = player:GetAttribute("Class"),
        teleportedAt = os.time(),
      })
    → TeleportService:TeleportAsync(marketplacePlaceId, { player }, options)
```

### Hatchery → Corridors

```
src/ServerScriptService/StealPortal.server.luau
  player.Touched on the steal arch (after 100g fee)
    → similar SetTeleportData + TeleportAsync(corridorsPlaceId, ...)
```

### Marketplace → Hatchery

```
src-marketplace/ServerScriptService/MarketplaceBoot.server.luau
  return portal player.Touched
    → TeleportAsync(hatcheryPlaceId, ...)
```

### Corridors → Hatchery

```
src-corridors/ServerScriptService/CorridorsBoot.server.luau
  same pattern.
```

### Visit-a-Friend (Hatchery → specific Hatchery JobId)

```
src/ServerScriptService/VisitFriendHandler.server.luau
  VisitFriendRE.OnServerEvent
    → validate Roblox friendship (GetFriendsAsync, cached 60s)
    → look up target.jobId from PresenceBroadcast.findFriend(targetUid)
    → TeleportService:TeleportToPlaceInstanceAsync(target.placeId, target.jobId, …)
```

The `JobId` is the specific Hatchery **server instance** — not just any
Hatchery. This is how visiting friends lands you in their world rather
than a fresh server.

### TeleportData consumption

The destination place reads `Player:GetJoinData().TeleportData` on
`PlayerAdded` to discover where the player came from and any context the
sender baked in (e.g. `carriedClass` so the Marketplace can show class-
specific pricing without a DataStore round-trip).

⚠ **TeleportData is client-trusted on arrival**, so don't put security-
sensitive flags there. Anything truly authoritative (cash, inventory)
must round-trip through the shared DataStore.

---

## Build pipeline

Three independent build scripts, one per place. All auto-source `.env`
for the `BB_*` env-var-driven config generation (TelemetryConfig +
GamepassConfig).

```bash
bash scripts/build.sh             # Hatchery        → BloomAndBurgle.rbxlx
bash scripts/build-marketplace.sh # Marketplace     → Marketplace.rbxlx
bash scripts/build-corridors.sh   # Corridors       → Corridors.rbxlx
```

Each build:

1. Sources `.env`.
2. Runs material discipline check (banned: `SmoothPlastic`, `Plastic`,
   `Glass`, `Foil`, `ForceField` — see Bloom&Burgle_Design_Spec.md §1.5).
3. Generates `src/ServerScriptService/TelemetryConfig.luau` from
   `$BB_TELEMETRY_ENDPOINT` + `$BB_TELEMETRY_KEY` (gitignored, regenerated
   every build).
4. Generates `src/ServerScriptService/GamepassConfig.luau` from
   `$BB_TINKERER_PASS_ID` (Hatchery only, gitignored).
5. `rojo build -o <out>.rbxlx <project-file>`.

Publish scripts (`scripts/publish.sh`, `scripts/publish-marketplace.sh`,
`scripts/publish-corridors.sh`) wrap the build + upload to Roblox Open
Cloud using `$ROBLOX_API_KEY` + `$BB_*_PLACE_ID`.

For the Open Cloud API conflict pattern + Studio-vs-disk gotcha, see
**`scripts/debug/README.md` → `sync` section**.

---

## Cross-place invariants (the rules that hold the universe together)

Break any of these and the cross-place loop fails:

1. **Same `UniverseId`.** Verified live via Creator Hub; pinned in
   `BabPlaces.luau`. The DataStore sharing depends on this.
2. **Identical `BabPlaces.luau` across all 3 places.** Since it lives in
   `src/ReplicatedStorage/Modules/` and is auto-mounted by all 3
   project.json files, this is enforced by Rojo. Just don't fork it.
3. **`Player.UserId` is the universal key.** All DataStore keys are
   `player_<userId>`. Never use `Player.Name` (changeable) or
   `Player.DisplayName` (non-unique).
4. **`Class` attribute survives teleports.** Roblox carries `Player`
   attributes across `TeleportAsync` automatically; class-pick flow
   relies on this.
5. **TeleportData is hint, not authority.** Treat `from`, `carriedClass`,
   etc. as a UX shortcut. Verify anything currency-related via DataStore.
6. **`MessagingService` topic name is versioned.** `bab-presence-v1`
   includes `-v1` so a future format change can switch to `-v2` without
   crashing old-version servers (mixed cluster during rollout).

---

## Where to read next

- **Adding a feature?** Check `CLAUDE.md` for general rules, then
  `AGENTS.md` for the multi-machine workflow.
- **Want to test in-Studio?** `scripts/debug/README.md`.
- **Brand / palette / material rules?** `Bloom&Burgle_Design_Spec.md`.
- **What got built and why?**
  - `Bloom&Burgle_Spec.md` — game mechanics + monetization
  - `Bloom&Burgle_Architecture_Eval.md` — P0/P1/P2 ADRs
  - `Bloom&Burgle_Design_Critique_2026-05-10.md` — current design tier-list
- **Past decisions and conversations** — query the chat history per
  `CLAUDE.md`'s "persistent chat history" section before reaching for
  the user.

---

## Maintenance

Update this doc when:

- Place IDs change → fix `BabPlaces.luau` AND this doc's "Places + IDs"
  table on the same PR.
- A new DataStore key is added → add a row to the DataStores table.
- A new MessagingService topic is added → add a row to the topics table.
- A new shared `src/` directory mounts into multiple places → update the
  "What each place ships" section.
- A teleport flow changes shape → update "Cross-place teleport flow".
