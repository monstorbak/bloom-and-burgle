# BAB-PHASE-3-MYTHIC-CEREMONY-AND-ADVISORY: cinematic Mythic hatch + class-advisory copy in the harvest modal

**Owner:** unassigned
**State:** inbox (design — implementation-ready; depends on Phase 1 rigs for the ceremony to feel cinematic)
**Priority:** P1 (the "I just got a Mythic!" share moment — a TikTok template per spec §15.O)

**Files touched (planned):**

- modify `src/ServerScriptService/Critter/HarvestFlow.luau` (detect Mythic, fire ceremony RemoteEvent)
- new `src/StarterPlayerScripts/MythicCeremony.client.luau` (the cinematic — screen flash, light pillar, freeze-frame, bloom boost)
- modify `src/StarterPlayerScripts/HarvestModal.client.luau` (wire `CritterData.advisoryFor()` line into the modal)
- modify `src/ReplicatedStorage/RemoteEvents/` (new `MythicCeremony` RemoteEvent)
- modify `src/ReplicatedStorage/Modules/CritterData.luau` (verify `advisoryFor` covers all 60 cells; tighten the copy if needed)
- new `tests/critter/advisory_copy.test.luau` (verify each (species, class) returns ≤60-char copy with the right asset/liability marker)

## Problem

Two related gaps left over from PR #7 (Critter split + Plant→Critter rename):

1. **Mythic hatch is silent.** Mutation rolling exists (`CritterData.rollMutation` per `CritterData.luau:321`), 0.5% Celestial mutation gives 100× value, but the *moment* of getting one is invisible — no fanfare, no freeze-frame, no share-prompt. The single rarest event in the loop has the dullest UX. Spec §1.2 calls out the rarity ladder, §3.2 calls out toast as the standard celebration mechanism, but neither is wired for Mythic.

2. **Class advisory line exists but isn't shown.** `CritterData.advisoryFor(speciesId, classId)` (CritterData.luau:357) returns class-aware copy like "✓ Hexers thrive with Patina Toads. Strong asset if nurtured." It's a function call away from being the centerpiece of every harvest modal but it's not being called. The asset/liability differentiator — the entire **brand moat** — is invisible at the most important UI surface.

Together these are the "first 1000 hours of word-of-mouth" payload: every Mythic hatch becomes a screenshot, every harvest tells the player WHY their critter matters for their class.

## Approach

### Mythic ceremony

When `HarvestFlow.harvestPlanter` returns a Mythic-rarity result (rolled
mutation: `celestial` per `CritterData.luau:305`, OR base species with
rarity == "Mythic"), fire a new `MythicCeremony` RemoteEvent:

```lua
MythicCeremonyRE:FireClient(player, {
    species = "coal_drake",
    speciesName = "Coal Drake",
    speciesEmoji = "🐉",
    mutationId = "celestial",
    mutationName = "Celestial",
    mutationEmoji = "💫",
    rarityRank = 6,         -- 1=Common, 6=Mythic
    plotPosition = ...,     -- so client can frame the camera
})
```

Client (`MythicCeremony.client.luau`) plays the ceremony:

1. **t=0.0s** — Screen overlay flashes white at 60% alpha for 0.15s, decays.
2. **t=0.0s** — `Lighting.Bloom` intensity ramps from 0.5 → 1.4 over 0.3s (LightingService property tween).
3. **t=0.1s** — A vertical light pillar (Beam + ParticleEmitter) anchors at the planter location, color-tinted to the mutation color (Celestial = `Color3.fromRGB(153, 230, 255)`).
4. **t=0.3s** — Camera tilts to a 45°-up-3-stud-back shot of the pod (handed off from `CritterCameraHooks` per Phase 1).
5. **t=0.6s — 1.6s** — Freeze-frame on the rig at full reveal. Holding for 1s gives the player time to take a screenshot.
6. **t=1.6s** — Bloom decays back to default; camera control returns to player.
7. **t=2.0s** — Standard `+$cash` toast fires with a Mythic-tinted variant ("💫 CELESTIAL Coal Drake! +$30,000").

Ceremony is **non-interactive** (player input is captured during the 1.6s) — this is part of the design. The freeze IS the share moment.

### Class advisory in the harvest modal

The harvest modal already shows post-harvest summary. Add one line:

```
─────────────────────────────────
🐀 Cogwork Rat × 5 — sell or scrap?
─────────────────────────────────
✓ Tinkerers thrive with Cogwork Rats. Strong asset if nurtured.
─────────────────────────────────
[ Sell ]  [ Scrap ]  [ Nurture (×3) ]
```

Implementation: in the existing `HarvestModal.client.luau`, the modal
populator gets the player's `Class` attribute, calls
`CritterData.advisoryFor(speciesId, classId)`, and renders the line in
class-accent color (per `BrandColors.classAccent(class)`). One TextLabel,
no new geometry.

### Advisory copy audit

Existing `advisoryFor` returns three template strings:

```luau
asset:     "✓ %ss thrive with %ss. Strong asset if nurtured."
liability: "⚠ As a %s, this %s may turn on you. Most sell or scrap."
neutral:   "• %ss are neutral to %ss. Mild bonus if nurtured."
```

Audit: all 60 (species × class) cells go through this template. Ship as-is
for v1; tune per-cell flavor in a follow-up if telemetry shows the
template feels formulaic. The tunable: each cell can override the
template via a per-cell entry in `CritterData.SPECIES[species].advisory`.

Test: `tests/critter/advisory_copy.test.luau` asserts:
- All 60 cells return a non-empty string ≤60 chars
- Asset cells start with "✓"
- Liability cells start with "⚠"
- Neutral cells start with "•"
- Asset cells contain the species displayName
- No PII in the copy

## Acceptance

- [ ] Hatching a Mythic-rarity critter (testable via DevMode `BB_FORCE_MUTATION=celestial`) triggers the full 1.6s ceremony.
- [ ] Screenshot key during the freeze-frame captures the rig at full reveal (no UI overlay obscuring it).
- [ ] Camera control returns smoothly (no jerk on hand-off).
- [ ] Player input is correctly suppressed during the ceremony (no accidental walk-off-plot mid-ceremony).
- [ ] Harvest modal shows class advisory line, color-coded per class.
- [ ] Advisory line updates correctly when the player's Class changes (rare — class rebirth event).
- [ ] All 60 cells pass the copy audit test.
- [ ] `Telemetry.track("mythic_hatch", ...)` fires per ceremony for Phase 0 funnel.
- [ ] No regression on the harvest loop (existing tests green).

## Open questions

1. **Performance on mobile.** Bloom + light pillar + freeze-frame on a 4-year-old phone — verify FPS doesn't tank. If it does, fallback to a lighter ceremony on `Lighting.Technology == "Compatibility"` clients.
2. **Concurrent ceremonies.** Two players in the same server hatch Mythics within 0.5s. Each player sees their own ceremony locally — server-side firing is per-player, no cross-talk needed.
3. **Streamer mode.** Some players will hate the input lock. Add an opt-out toggle? Defer; default-on for now.
4. **Music swell.** A 1-bar musical swell would ×10 the share factor. Out of scope (audio author needed); flagged for Phase 5 / live event work.

## Defer

- Per-rarity ceremonies (Legendary, Epic) — only Mythic gets the full ceremony at v1.
- Auto-share-to-Roblox-feed integration. Roblox API supports it but the UX is messy; let players screenshot manually.
- Per-species ceremony variants (a Coal Drake ceremony with fire particles vs a Patina Toad with copper vapor). Defer until Phase 1's full art set is in.

## Log

- 2026-05-08 — Direction shift session; folded into prioritized roadmap. Drafted ticket.
