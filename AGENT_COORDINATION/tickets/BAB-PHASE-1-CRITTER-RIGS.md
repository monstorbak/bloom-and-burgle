# BAB-PHASE-1-CRITTER-RIGS: R15 character rigs + 3-form lifecycle for the 4 headline species

**Owner:** unassigned
**State:** inbox (design — code-ready; mesh authoring is parallel non-code work)
**Priority:** P1 (precondition for any clip-driven virality — escape mechanic, mythic ceremony, marketing thumbnails)

**Files touched (planned):**

- new `src/ReplicatedStorage/Modules/CritterRigs.luau` (registry of meshIds + rig parameters per species/form)
- modify `src/ServerScriptService/CritterVisuals.luau` (swap from procedural Parts to MeshPart+Humanoid for the 4 supported species; fall back to current Parts for the other 8)
- new `src/ServerScriptService/Critter/CritterAnimations.server.luau` (idle / juvenile-bounce / hatch-ceremony / ripe-pulse / escape-spawn loops)
- new `src/StarterPlayerScripts/CritterCameraHooks.client.luau` (orbit cam for hatch + escape moments — clip-friendly framing)
- modify `src/ReplicatedStorage/Modules/CritterData.luau` (add `rigSupport: bool` flag per species so unsupported ones stay on the legacy renderer)
- assets (outside-of-code; tracked here for visibility):
  - `rbxassetid://...` MeshIds for 4 species × 3 forms = 12 meshes
  - 4 idle animations × 3 forms = 12 animations
  - 4 hatch-ceremony animations
  - 4 escape-spawn animations

## Problem

Per `Bloom&Burgle_Design_Spec.md` §617 (launch checklist):
"All 12 species modeled at hatch-cute, juvenile, and adult forms" is
called out as a launch requirement. We currently have **0 of 36** —
every critter is rendered as procedural Parts + ball heads via
`CritterVisuals.luau`, which is a placeholder.

Concrete consequence: a player cannot post a screenshot of a Brass
Beetle today and have it look anything like the spec's brand-art
references. The aesthetic moat (steampunk-Ghibli, single-of-kind on
Roblox) collapses to "looks like every other Studio scratch project"
in a 1-second TikTok thumbnail.

This phase ships R15-style rigs for the **4 headline species** that
drive the brand's marketing matrix:

| Species | Why it's headline |
|---|---|
| **Mech-Hound** (cogworkPet, Common) | Starter pet — every player meets it within 3 minutes. The "first cute moment." |
| **Coal Drake** (predator, Legendary) | The class-arbitrage poster child (asset for sky-pirate/hexer, liability for knight/tinkerer). The "I tried to raise a Coal Drake as a Knight" headline matchup. |
| **Brass Beetle** (cogworkPet, Common) | 20s grow loop — appears in every onboarding clip. |
| **Sky Wyvern** (skyMount, Rare) | Visual reach — winged silhouette over the steampunk plaza is the ideal marketing thumbnail. |

The other 8 species stay on the existing procedural renderer until
Phase-1.B (deferred). Code paths must support the mixed mode.

## Approach

### Rig structure (per species, per form)

Each rig is a Model containing:
- `HumanoidRootPart` (anchored, drives positioning)
- `Humanoid` (rig type R15 — even for non-humanoid critters; gives free idle animation + accessory attach)
- 1 mesh `Part` per body region (3-6 parts depending on species)
- `Animation` instances pre-loaded for the 4 lifecycle moments

Spec §1.1 visual identity: brass / iron-charcoal / aether-cyan palette
applied via `BrandColors`-driven Color3 properties on the meshes
(meshes shipped greyscale + tinted at runtime — fewer asset uploads,
brand consistency enforced at load).

### 3-form lifecycle

| Form | When | Visual |
|---|---|---|
| **Hatch-cute** | t = 0 to 25% of growSeconds | Tiny, oversized eyes, exaggerated head-to-body ratio. Spec §1.1 cuteness target. |
| **Juvenile** | 25% to 75% | Mid-size, proportions normalizing, occasional bounce. |
| **Adult** | 75% to ripe | Final scale + production-rate behavior. The form that goes in the marketing thumbnail. |

Form transition is a swap (hide old rig, show new rig at same anchor)
not a tween — Roblox MeshPart morphing is brittle and a clean cut sells
better cinematically anyway. Each transition emits a `pop` particle and
a brief sparkle.

### Mixed-mode renderer

`CritterVisuals.luau` checks `species.rigSupport` (new field):
- `true` → use new `CritterRigs.spawn(species, form, anchor)` path
- `false` → existing procedural Parts code (unchanged)

This lets us ship the 4 supported species without breaking the 8
unsupported ones. Each unsupported species gets a follow-up ticket
when its rig lands.

### Camera framing for clip moments

Hatch ceremony (Mythic only — spec §1.2 + Phase 3 work):
- Camera orbits to a 45°-elevated 3-stud distance shot of the pod
- 0.5s freeze-frame at full reveal
- Subtle bloom + 1.2× saturation boost during the freeze (LightingService property tween)
- Auto-restore camera control after 1.5s

Escape moment (Phase 2 — the chaos generator):
- Quick cut to wide shot of the plot
- 0.3s slow-mo on the escape particle
- Then back to normal control

Both implemented in `CritterCameraHooks.client.luau`; trigger via
`RemoteEvent` fired by server when the moment starts.

## Acceptance

- [ ] All 4 species (`mech_hound`, `coal_drake`, `brass_beetle`, `sky_wyvern`) render as R15 rigs in their hatch / juvenile / adult forms.
- [ ] Form transitions visually feel like a "moment" (pop particle + sparkle); no flicker.
- [ ] The other 8 species still render correctly via the procedural fallback (no regression).
- [ ] Hatch ceremony fires for Mythic-rarity hatches (rare; testable via DevMode override that forces a Mythic roll).
- [ ] Escape camera cut fires when an `EscapeBehavior` activates (testable post-Phase 2; this PR ships the hook + stubs the trigger).
- [ ] Rigs respect `BrandColors` palette — no hand-rolled Color3.
- [ ] Brand-discipline check: all rigs use approved materials (no `SmoothPlastic`, `Plastic`, `Glass`, `Foil` per `AGENTS.md`).
- [ ] `Telemetry.track("rig_form_transition", ...)` emitted on each hatch/juvenile/adult flip (for Phase 0 funnel).
- [ ] Idle animation plays automatically; runs without a server task (animation attached to the Humanoid).

## Open questions

1. **Mesh authoring source.** Studio modeling vs commissioning vs Roblox marketplace. Recommend in-house if anyone has the bandwidth, otherwise commission via the Roblox developer marketplace; budget ~$300-800 per species for cute-but-brand-on rigs.
2. **Animation library.** Each species needs minimum 4 animations (idle, juvenile-bounce, hatch-ceremony, ripe-pulse). Use Roblox's free animator or commission. Rough budget: 16 animations × $30-80 = $500-1300.
3. **Asset id placeholders.** During development we'll use Roblox public marketplace pet meshes as stand-ins (free tier — exact match doesn't matter; the LOOK matters at launch). Track the swap-out as a launch-checklist item.
4. **Animation streaming.** Roblox Humanoid loads animations on demand. For a cold-start join, the first hatch may have a 0.5s animation-load delay — minor but worth noting.
5. **R15 for non-humanoid creatures.** Roblox's R15 rig is humanoid-shaped by default. We'll use it as a skeletal substrate but rig non-humanoid bodies (drake, hummingbird) as accessory chains rather than fighting the default rig. This is normal practice for Roblox pets.

## Defer

- Rigs for the remaining 8 species (one ticket per launch wave; ship in pairs as art lands).
- Rig customization per mutation (Polished / Gilded / Aether / Ember / Celestial). Mutations stay as particle overlays on the base rig for now.
- Adopt-Me-style critter equipping (carrying a critter on your back). Out of scope.

## Log

- 2026-05-08 — Direction shift session; folded into prioritized roadmap. Drafted ticket.
- 2026-05-09 — Phase 1 code scaffolding shipped (~900 LOC). Includes:
  - `src/ReplicatedStorage/Modules/CritterRigs.luau` (new) — pure-data registry with form thresholds (HATCH_CUTE_END=0.25, JUVENILE_END=0.75) + per-species feature lists
  - `src/ReplicatedStorage/Modules/CritterData.luau` — added `rigSupport: boolean?` field; opted in mech_hound, coal_drake, brass_beetle, sky_wyvern
  - `src/ServerScriptService/CritterVisuals.luau` — added rig builder branch with per-species feature builders (ears, horns, wings, shell, antennae, longNeck, chestPlate, tail variants); form transitions tween scale + emit pop particle + fire `rig_form_transition` Telemetry; egg made semi-transparent (0.35) so the rig is visible inside from t=0
  - `src/StarterPlayerScripts/CritterCameraHooks.client.luau` (new) — listens on `CritterCeremony` RemoteEvent (lazy-created server-side); ships `mythic_hatch` (1.6s freeze + orbit + bloom 1.4×) and `escape_burst` (0.6s bloom flash) ceremony handlers; Phase 1 doesn't fire either, Phase 2 fires escape_burst, Phase 3 fires mythic_hatch
  - `tests/critter/rigs.test.luau` — 113 lune cases (formForProgress thresholds, monotonicity, form coverage)
  - `scripts/test/critter-rigs-static.sh` — 24 structural checks (mirror constants pinned, all 4 species registered + opted in, dispatch wiring intact)
- 2026-05-09 — Tests: 113/113 lune + all 8 structural-check sections pass. All 3 places build clean (Hatchery 296K → 332K, Marketplace 132K → 144K, Corridors 88K → 100K — growth is the rig builder code mounted via Rojo `$path` from src/ReplicatedStorage/Modules + src/StarterPlayerScripts).
- 2026-05-09 — **Real meshes still pending** — current rigs are placeholder procedural Parts (richer than archetype baseline but not the Steampunk-Ghibli target). Open Question 1 (mesh authoring) tracked separately. When meshes land, swap `meshId` on each form profile in CritterRigs.RIGS — geometry builder will pick them up via the existing dispatch.
