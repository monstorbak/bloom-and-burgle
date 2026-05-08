# P1 — Critter split + rename + push-to-studio safety + Fusion adoption

> Handoff for the Mac (G-Tard) operator. CI tests cover what can be tested
> without Studio; this doc lists what needs eyes-on verification in a
> running Play session before merging.

## What shipped

| Item | What changed | CI test |
|---|---|---|
| **P1.4** Push-to-studio Play-mode safety + canonical-sync docs | `scripts/push-to-studio.sh` now refuses server `Script` pushes during Play; `--force` bypass; bridge-down fail-closed. `scripts/README.md` and `AGENTS.md` document `rojo serve` as canonical Edit-time sync. | `bash scripts/push-to-studio.test.sh` — 5 scenarios via mocked MCP bridge |
| **P1.1** PlantHandler split (ADR-4) | `src/ServerScriptService/PlantHandler.server.luau` (637 LOC) → `src/ServerScriptService/Critter/` (9 focused files). Sell+scrap dedup'd into `EconomyPad.convert(player, kind, source)`. | `scripts/build.sh` (rojo build = syntax check); `lune run tests/critter/economy_logic.test.luau`; `bash scripts/test/critter-static.sh` |
| **P1.2** Rename `Plant*` → `Critter*` (ADR-5) | `PlantData.luau` → `CritterData.luau`; `PlantVisuals.luau` → `CritterVisuals.luau`; legacy filenames kept as 1-line require-shims for one release. `Services.register("CritterHandler", ...)` + `Services.register("PlantHandler", ...)` both registered. LeaderstatsScript prefers `CritterHandler`. Load-bearing `"Planter"` CollectionService tag and `data.plot.planters/stash` DataStore keys preserved. | `bash scripts/test/rename-shim.sh` |
| **P1.3** Fusion + HarvestModal (ADR-6) | Vendored a minimal Fusion-API-compatible module at `src/ReplicatedStorage/Modules/Fusion/init.luau` (Value, Computed, New, Children, OnEvent). `HarvestModal.client.luau` built in Fusion as the precedent — opens on Mythic OR mutation drops; common drops still use CashHUD's floating label. | `lune run tests/fusion/reactive_primitives.test.luau`; `bash scripts/test/fusion-static.sh` |

> P1.2 + P1.3 rows will be filled in by the next two commits as those land.

## P1.4 — push-to-studio.sh runtime check

CI covers:
- Edit + Script → success
- Play + Script → refused (exit 2)
- Play + Script + `--force` → success
- Play + LocalScript → success with warn
- Bridge unreachable → refused (exit 3)

Manual sanity check (one-time, do it once after merge):
1. Open Studio with the MCP bridge running. **Do not press Play.**
2. Make a tiny edit to `src/ServerScriptService/Critter/EconomyPad.luau`.
3. Run:
   ```bash
   echo "src/ServerScriptService/Critter/EconomyPad.luau::game.ServerScriptService.Critter.EconomyPad::ModuleScript" \
     | scripts/push-to-studio.sh
   ```
   Expect: probe finds Edit mode, sync succeeds, `✨ done`.
4. Press Play. Re-run the same command. Expect: probe finds Play, refusal
   (exit 2), pointer to `rojo serve`. Press `--force` to verify the
   override path still works.
5. Stop Studio. Re-run. Expect: probe fails, exit 3 with the fail-closed
   message.

## P1.1 — Critter split

### What was extracted from `PlantHandler.server.luau`

| Old location | New module | Type |
|---|---|---|
| inventory[uid][key] table + getInv + findPlanterForSlot | `Critter/CritterRegistry.luau` | ModuleScript |
| harvestPlanter / harvestAllRipeForPlayer / harvestOffline / buildSproutFor | `Critter/HarvestFlow.luau` | ModuleScript |
| _doSellInventory + _doScrapInventory + cooldown tables (4 callsites collapsed) | `Critter/EconomyPad.luau` | ModuleScript |
| API.snapshot / API.restore + Services.register("PlantHandler", ...) | `Critter/Persistence.luau` | ModuleScript |
| Heartbeat grow loop + ripen + EmptyBorder pulse + per-pod .Touched harvest | `Critter/GrowLoop.server.luau` | Script |
| SellPad tag wiring + .Touched listener | `Critter/SellPad.server.luau` | Script |
| ScrapPad tag wiring + .Touched listener | `Critter/ScrapPad.server.luau` | Script |
| 4Hz proximity pulse for both pads | `Critter/ProximityPulse.server.luau` | Script |
| plantSeedAt + PlantSeed RE listener + starter pack + lifecycle | `Critter/PlantingFlow.server.luau` | Script |

The `"Planter"` CollectionService tag, the `Planter_X_Z` Part naming, and
the DataStore `plot.{planters,stash}` shape are all preserved unchanged
(load-bearing in saves; ADR-5 calls these out as compatibility shims).

`Services.register("PlantHandler", ...)` keeps the legacy name so
`LeaderstatsScript` doesn't change. ADR-5 (P1.2) renames this.

### Manual Studio smoke test (~10 min)

Open Studio against the freshly-built `BloomAndBurgle.rbxlx`.

1. **Service bootstrap.** Watch the output panel — should see, in order:
   ```
   [BAB-LIFE] Services.register PlantHandler
   [BAB-LIFE] Critter/GrowLoop online (Heartbeat tick + per-pod harvest fallback)
   [BAB-LIFE] Critter/ProximityPulse online (4Hz fallback for .Touched)
   ```
   If any of those don't appear, the new file's require chain has a
   missing dependency.

2. **Press Play. Claim a plot.** Run via `dbg`:
   ```bash
   ./scripts/debug/dbg eval 'local Services = require(game.ServerScriptService.Services); return Services.list()'
   ```
   Expect `PlantHandler` in the list (registered by Persistence).

3. **Plant + grow.** Pick a sunbloom seed, plant it in any pod. Verify:
   - Pod becomes non-empty within ~1s.
   - Output panel shows `pod_loaded` telemetry batched (or buffered if
     no collector wired — that's fine, just check the
     `Telemetry._buffer` count via dbg eval).
   - After grow seconds elapse, pod ripens and EmptyBorder pulses.

4. **Walk-to-sell (single-walk auto-harvest).** Step on the SellPad with
   ripe pods. Verify:
   - All ripe pods harvest first (HarvestFlow.harvestAllRipeForPlayer).
   - Cash increments by the sum of `species.baseValue * count *
     mutationMult` per held critter.
   - SellPlants RE fires the popup once.
   - `sell_payout` telemetry event fires with `source=touched` (not
     `proximity` — the .Touched path won the race).

5. **Cooldown shared with proximity.** Step off and back on within 0.5s.
   Should NOT re-fire (shared cooldown table works).

6. **Scrap pad / Sacred-skip.** Plant a Sacred-tagged species (use
   `dbg eval "_G.PlantHandler.snapshot(...)"` to confirm inventory has
   one), step on ScrapPad. Verify:
   - Sacred is skipped (ScrapPlants RE fires with skipped > 0).
   - CogParts increments only for non-Sacred.

7. **Persistence round-trip.** Stop Play, restart Play, verify your
   inventory restored (look for the second `_G.PlantHandler.snapshot`
   matching pre-restart shape).

8. **Backward-compat: `_G.PlantHandler` still works.** Run:
   ```bash
   ./scripts/debug/dbg eval 'return type(_G.PlantHandler.snapshot) == "function"'
   ```
   Expect `true`. The `dbg` toolkit and any out-of-tree consumer of `_G`
   continue to work.

### Risk inventory (P1.1)

- **Module-load-order race.** `GrowLoop.server.luau` eagerly requires
  `Persistence` so the `Services.register("PlantHandler", ...)` call
  happens during boot — but Roblox runs Scripts in unspecified order. If
  `LeaderstatsScript` is the first to call `Services.await("PlantHandler", 5)`
  on PlayerAdded, it'll wait up to 5s for Persistence to register. Same
  semantics as the legacy `_G.PlantHandler` polling, but worth checking
  cold-boot logs.
- **HarvestPopup RemoteEvent lazy-create.** HarvestFlow creates the
  RemoteEvent on require if it doesn't exist. The `.model.json` file at
  `src/ReplicatedStorage/RemoteEvents/HarvestPopup.model.json` defines
  it formally — both paths converge on the same Instance.
- **SeedShop bridge.** `src/ServerScriptService/SeedShop.server.luau`
  has a comment "Reuse PlantHandler via the existing PlantSeed
  RemoteEvent path" — that path now lives in `PlantingFlow.server.luau`
  but the RemoteEvent surface is unchanged, so SeedShop just keeps firing
  PlantSeed and the wired listener handles it.

## P1.2 — Plant → Critter rename

### What changed

| Old | New | Strategy |
|---|---|---|
| `src/ReplicatedStorage/Modules/PlantData.luau` | `CritterData.luau` (canonical) + `PlantData.luau` (1-line shim) | shim does `return require(script.Parent:WaitForChild("CritterData"))` |
| `src/ServerScriptService/PlantVisuals.luau` | `CritterVisuals.luau` (canonical) + `PlantVisuals.luau` (1-line shim) | same pattern |
| `Services.register("PlantHandler", ...)` (P1.1 default) | Now registers BOTH `"CritterHandler"` and `"PlantHandler"` with the same API table | `_G.CritterHandler` + `_G.PlantHandler` also both set |
| `LeaderstatsScript`: `Services.await("PlantHandler", ...)` | `Services.await("CritterHandler", ...) or Services.get("PlantHandler")` | Prefers canonical, falls back to legacy if a future drop removes the alias |

### What did NOT change (load-bearing)

- The `"Planter"` `CollectionService` tag — every plot Part is tagged this
  way and the tag is referenced in saves indirectly (rebuilt plots
  re-apply the tag). Renaming would orphan existing plots.
- The `Planter_X_Z` Part naming convention — encodes 1..9 slot index;
  parsed by `CritterRegistry.slotForPlanterName` for save round-trip.
- The `data.plot.planters` and `data.plot.stash` DataStore key shapes —
  these go through `BloomAndBurgleData_v1` and are read by every existing
  player's save.

### Manual Studio smoke test for P1.2 (~5 min)

1. **Both names register on boot.** Run via `dbg`:
   ```bash
   ./scripts/debug/dbg eval 'local s = require(game.ServerScriptService.Services); local out = s.list(); table.sort(out); return table.concat(out, ",")'
   ```
   Expect both `CritterHandler` and `PlantHandler` in the list.

2. **Both `_G` handles are live.**
   ```bash
   ./scripts/debug/dbg eval 'return _G.CritterHandler == _G.PlantHandler'
   ```
   Expect `true` (same API table under both names).

3. **Legacy require shims work.** From a fresh Studio session:
   ```bash
   ./scripts/debug/dbg eval 'return require(game.ReplicatedStorage.Modules.PlantData) == require(game.ReplicatedStorage.Modules.CritterData)'
   ```
   Expect `true`.
   ```bash
   ./scripts/debug/dbg eval 'return require(game.ServerScriptService.PlantVisuals) == require(game.ServerScriptService.CritterVisuals)'
   ```
   Expect `true`.

4. **Existing player save round-trips.** Open a Studio Play session,
   join, plant a sunbloom, walk away. Stop Play. Restart Play. Verify
   the sunbloom restores at the correct grow progress (this exercises
   the unchanged DataStore shape going through the renamed
   `Persistence.luau`).

### Risk inventory (P1.2)

- **One-release window.** The legacy shims (`PlantData.luau`,
  `PlantVisuals.luau`) and the legacy service name (`PlantHandler`) are
  scheduled for removal one release after 2026-05-08. Before deletion:
  ```bash
  grep -rn '"PlantData"\|"PlantVisuals"\|"PlantHandler"\|_G.PlantHandler' src/ scripts/ AGENT_COORDINATION/
  ```
  Every hit must be migrated to the new name first. Search for these in
  both the in-tree code AND any out-of-tree consumers (Studio plugins,
  hot-patched scripts in `dbg eval` history).
- **Type-name confusion.** `Services.luau` exports both `CritterHandlerAPI`
  (canonical) and `PlantHandlerAPI` (alias for the same shape). New code
  should use `CritterHandlerAPI`.

## P1.3 — Fusion adoption + HarvestModal

### What shipped

- **Fusion module** at `src/ReplicatedStorage/Modules/Fusion/init.luau`
  (~190 LOC). Implements `Value`, `Computed`, `New`, `Children`, `OnEvent`
  with the Fusion 0.3 surface. **Not** the official Fusion library — a
  hand-rolled minimal subset. The public API matches so swapping in the
  real Fusion via Wally later is a one-line `init.luau` change.
- **HarvestModal** at `src/StarterPlayerScripts/HarvestModal.client.luau`
  — first UI built in Fusion. Listens to `HarvestPopupRE`, queries
  `CritterData.get(speciesId)` for rarity, opens the modal only when:
  - mutation present (any of `CritterData.MUTATIONS`), OR
  - rarity == "Mythic"

  Common drops continue to use the existing CashHUD floating-label
  (line ~167 in `CashHUD.client.luau`). Auto-dismisses after 4s, or click
  the "Awesome" button.

### Manual Studio smoke test for P1.3 (~5 min)

1. **Module loads.** `dbg eval`:
   ```bash
   ./scripts/debug/dbg eval 'local F = require(game.ReplicatedStorage.Modules.Fusion); return type(F.New) == "function" and type(F.Value) == "function"'
   ```
   Expect `true`.

2. **Reactive smoke test.** `dbg eval`:
   ```bash
   ./scripts/debug/dbg eval 'local F = require(game.ReplicatedStorage.Modules.Fusion); local v = F.Value(0); local c = F.Computed(function() return v:get() * 2 end, {v}); v:set(7); return c:get()'
   ```
   Expect `14`.

3. **HarvestModal mounts.** Press Play, join. The
   `[BAB-LIFE] HarvestModal online` log should appear. The modal
   ScreenGui should exist under `PlayerGui` but Enabled=false.

4. **Common drop = no modal.** Plant a sunbloom (Common rarity), wait
   for ripen, walk over it. The +1 floating label should appear (legacy
   path). HarvestModal should NOT pop up.

5. **Mythic drop = modal.** Plant a coal_drake (Mythic). Wait for
   ripen, walk over it. Modal should pop up showing emoji + name +
   rarity color (pink-ish). Auto-dismiss in 4s, or click "Awesome".

6. **Mutation drop = modal.** Force a mutation via `dbg`:
   ```bash
   ./scripts/debug/dbg eval 'game.ReplicatedStorage.RemoteEvents.HarvestPopup:FireClient(game.Players:GetPlayers()[1], {species="sunbloom", emoji="🌻", name="Sunbloom", mutation="celestial", position=Vector3.new(0,5,0)})'
   ```
   Modal should pop up with "✨ CELESTIAL mutation" subtitle.

7. **Class affinity advisory.** Set a class attribute on the local
   player and trigger a harvest. The "✨ asset for your class" or
   "⚠ liability for your class" line should appear when applicable.

### Risk inventory (P1.3)

- **Not the real Fusion.** This is a hand-rolled minimal subset. Edge
  cases that the real Fusion handles (Spring/Tween animations, observer
  cleanup on Instance:Destroy, scope-based cleanup) are NOT implemented.
  When the team adds Wally, replace the vendored `Fusion/init.luau` with
  `return require(... .Packages.Fusion)` and re-test HarvestModal.
- **Modal stacking.** If two rare drops fire within 4s of each other,
  the second overwrites the first (the auto-dismiss `task.delay` checks
  `current:get() == opened` to avoid closing the wrong one). No queue —
  acceptable for now since rare drops are rare by definition.
- **No persistence.** Closing the modal doesn't save state; if the
  player respawns mid-modal, it's gone. Fine — it's transient
  celebration, not a decision moment yet.

## How to run all CI tests for P1

```bash
# Push-to-studio Play-mode safety
bash scripts/push-to-studio.test.sh

# Critter split — structural + logic
bash scripts/test/critter-static.sh
lune run tests/critter/economy_logic.test.luau

# Plant → Critter rename + shims
bash scripts/test/rename-shim.sh

# Fusion adoption + HarvestModal precedent
bash scripts/test/fusion-static.sh
lune run tests/fusion/reactive_primitives.test.luau

# Build = syntax check (catches Luau syntax errors across all the new modules)
bash scripts/build.sh
```

All seven should exit 0 cleanly. Then proceed to the per-item manual
Studio smoke tests above.
