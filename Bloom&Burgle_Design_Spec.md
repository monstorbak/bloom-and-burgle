# Bloom & Burgle — Design Spec

**Purpose**: This document defines every design criterion that must be locked before launch to give the game the highest probability of breaking $10K/month and going viral. Pair with `Bloom&Burgle_Spec.md` (mechanics + monetization) — this file owns **look, feel, sound, flow, and the systems that make the player choices interesting**.

The product thesis: **"a steampunk hatchery where you grow cute critters that may save you, ignore you, or kill you — and the only way to know is who you are."**

Every design choice below ladders to one of three repeatable, top-Roblox-game emotions:

1. **Cuteness panic** (you hatched something adorable; you have ~30 seconds to decide its fate) — drives Day-1 retention and screenshot virality.
2. **Identity drama** (your class makes one creature an asset and another a death sentence) — drives forum/Discord theory-crafting and replay value.
3. **Live spectacle** (a dragon you should have sold yesterday is now burning down your hatchery while your mech-hound rushes to defend you) — drives short-clip virality on TikTok/Shorts.

Anything that does not serve one of those three is cut.

---

## 1. Visual Identity

### 1.1 Mood board, in one sentence
**"Studio Ghibli's Howl's Moving Castle engine room, lit by a forge at golden hour, with cute little brass-and-cogwork critters tumbling out of incubator pods."**

Reference look-and-feel: Howl's Moving Castle + Castle in the Sky (warm industrial whimsy) + Bioshock Infinite (kid-friendly slice — the Columbia daytime palette, never the violence) + Final Fantasy IX (Lindblum's airships) + Adopt Me's hatching-moment cuteness, transposed into brass.

The aesthetic must read as **"Roblox doesn't have a top-100 game that looks like this"** in the first thumbnail second.

### 1.2 Color system (locked, used everywhere)

| Token              | Hex / RGB              | Use                                                                              |
| ------------------ | ---------------------- | -------------------------------------------------------------------------------- |
| `Brass`            | `#C8923F` (200,146,63)  | Kiosks, signage, currency icons, primary brand accent, CTA stroke                |
| `Copper Patina`    | `#4FA88F` (79,168,143)  | Aged metal accents, alchemy glow, magic-friendly assets, "good outcome" toasts   |
| `Oil Black`        | `#1A1410` (26,20,16)    | Plot bases (Hatchery floor), deep UI surfaces, contrast text                     |
| `Ember Orange`     | `#FF6A1F` (255,106,31)  | Forge glow, Pawn Forge (sell pad), fire VFX, danger highlights, dragon breath    |
| `Steam Cream`      | `#F2E4C9` (242,228,201) | UI text on dark, steam puffs, daytime sky band, paper UI surfaces                |
| `Ironwork Charcoal`| `#2E2A2A` (46,42,42)    | Secondary surfaces, machinery housing, fence tiers                               |
| `Aether Cyan`      | `#4FE3FF` (79,227,255)  | Magical glow, alchemist auras, Mythic rim, blueprint UI                          |
| `Valve Red`        | `#C13C2A` (193,60,42)   | Alarms, raid sirens, liability warnings, jail UI                                 |
| `Goggle Gold`      | `#E8C547` (232,197,71)  | Premium currency, gamepass UI, Mythic borders, sunbeams through clouds           |

**Rule**: every UI surface, every Part color, every particle is one of these nine tokens (or a 0–25% lerp toward white/black). No hand-picked one-offs. **No pastels** — anything candy-pink or mint-soft was the previous direction and must be removed on sight during code review.

**Rarity ladder** (locked, must be visually distinct at thumbnail size):

- Common — `Brass` rim, dull
- Uncommon — `Copper Patina` rim
- Rare — `Aether Cyan` rim glow + sparkline particles
- Epic — `Ember Orange` rim glow + smoke puff
- Legendary — `Goggle Gold` rim glow + slow rotation auto-orbit on hatch
- Mythic — animated cyan→gold flame rim + screen flash on hatch + 1.5s freeze-frame

### 1.3 Typography
- **Display / numbers / signage**: `FredokaOne` retained for friendly chunkiness — works against the heavy industrial backgrounds without going full Victorian unreadable.
- **Body / prompts**: `GothamBold`. Don't introduce a third font.
- **Stylized signage on world surfaces** (Pawn Forge, Egg Emporium, Class Hall): `Antique` (Roblox built-in) used **only** on engraved plaque elements, max 1 use per kiosk to avoid Olde-Tyme parody.
- **Stroke**: every text on a 3D world surface gets a 1–2px `Oil Black` stroke at 70% opacity. Non-negotiable on mobile in bright forge light.

### 1.4 Lighting & atmosphere
- **Day cycle**: 18-minute real-time loop. Two highlight beats:
  - **Forge Hour** (~6 of 18 minutes): warm orange ambient, brass surfaces glow, the screenshot moment.
  - **Aether Hour** (~3 of 18 minutes): cyan night, magical critters glow, alchemists +20% scrap value. The TikTok hook.
- `Lighting.Technology = Future`. `Atmosphere` enabled with a brass-tinted haze (`Color = #C8923F`, `Density = 0.25`). `Bloom` on, `Intensity = 0.8`.
- **Color correction**: warm tilt by default (saturation +0.1, tint Ember Orange at 8%); cool cyan tilt during Aether Hour.
- **Volumetric steam vents** on every plot and at every Cogworks anchor — `ParticleEmitter` Steam variant, low rate (5/s), high lifetime (3s). This is the single biggest "wow this game is alive" cue.

### 1.5 Material discipline
- Critter shells & mech bodies: `Metal` + `CorrodedMetal` for variation.
- Plot base ("Hatchery floor"): `WoodPlanks` with iron rivets (decals).
- Incubator pods (replaces planters): `Marble` rim + `Neon` aether window.
- Pawn Forge (sell pad): `Brick` body + `Neon` ember-orange top.
- Cogworks plaza floor: `Cobblestone`.
- Buildings: `Brick`, `Concrete`, `WoodPlanks`, `Metal`. Add visible rivets and gear decals as Decals (cheaper than parts).
- **Never** use `SmoothPlastic` (too clean), `Plastic` (too cheap), `Glass` (too pristine), `ForceField`, `Foil`. They break the world.

### 1.6 Skybox
Custom skybox required pre-launch:
- **Day**: warm overcast with airships and a distant brass moon. Goggle Gold sunbeams.
- **Aether Hour**: cyan-indigo with a copper moon, a cog-shaped constellation, and one floating airship silhouette.
Avoid the default Roblox sky — the #1 "low-effort game" tell on TikTok.

---

## 2. World Architecture

### 2.1 The Cogworks (town square / social hub)
- **Footprint**: 220×220 stud plaza, pedestrian only.
- **Anchors** (all visible from spawn within 3 seconds):
  - **Central Engine Tower** — animated brass tower with a slowly rotating clock face and exposed pistons. Top-of-tower leaderboard pillar shows top 10 "Greatest Menagerie" wealth ranking.
  - ⚙ **Egg Emporium** — domed brass kiosk for buying egg/spore/cocoon stock (replaces Seed Shop).
  - 🛡 **Class Hall** — pillared building where new players choose a class and existing players can respec for a fee.
  - 💎 **Premium Forge** — gamepass kiosk, hovering gold-rim showcase plinth.
  - 🔧 **Repair Bay** — paid station for restoring upgrade durability after combat damage.
  - 🎩 **Wardrobe & Costumery** — class outfits + critter cosmetic mods (cog implants, oil-coats).
  - 🏆 **Trophy Hall** — wall of recent Mythic hatches + recent raid victories, video-loop screens.
  - 🚪 **Visit Hub** — teleport pad to friends' Hatcheries.
  - 💰 **Marketplace Portal** — gold-rim brass archway with steam pouring from the keystone. Walking through teleports the player to a separate **Marketplace** Roblox place (own placeId, shared DataStore) — a destination commerce hub with NPC merchants and player-to-player trade booths. See `AGENT_COORDINATION/tickets/BAB-MARKETPLACE-HUB.md`.
  - 🥷 **Steal Portal** — dim red archway, smoke coiling from the threshold, deliberately positioned across the plaza from the Marketplace Portal to read as moral foil. Walking through (after a small entry fee) teleports the player to a separate **Corridors** Roblox place — a procedurally-generated maze of doors, each leading to another player's Hatchery for a stealing run. See `AGENT_COORDINATION/tickets/BAB-STEAL-CORRIDORS.md`.
- **Visual rule**: the Cogworks reads as **the warm public workshop**. Plots read as **personal, modified, dangerous**. The boundary is psychologically important. The two portals (gold for commerce, red for crime) are the same kind of boundary — visible threshold to a different kind of play.

### 2.2 Hatchery ring (plots)
- 16 plots in a ring at radius 220 (existing — keep).
- Each plot reskinned as a **Hatchery**: `WoodPlanks` floor with brass trim, 9 incubator pods (replaces planters), an owner sign engraved in `Antique` font, a wrought-iron perimeter fence (upgradeable).
- **Pod spacing**: pods are arranged on a 3×3 grid with **10-stud center-to-center** spacing (was 8; bumped 2026-05-08 to give wandering escape-mechanic critters room to do their thing without visually overlapping pods, see §9.6).
- Each plot is its own visible biome at distance — players can spot "the rich whale's hatchery" by silhouette: more pods, taller fences, glowing critters in their stable.
- **Fence tiers** (whale-driven cosmetic + raid defense):
  Wood Picket → Wrought Iron → Brass Battlements → Aether-Caged → Mythic Cogworks. Each tier visible from 50+ studs.
- **Plot is always lit** so the harvest-decision moment is always playable. Spookiness lives at the perimeter and on the streets, not on the work surface.

### 2.3 Combat & raid lanes
This game has emergent combat from kept liability critters, from raiders, **and from un-harvested critters that escape their pods past the harvest window** (§9.6). Required:
- Plot perimeters have **break-in points** (fence gaps) so the path of attack is legible to viewers of clips.
- **Alarm pylons** on every plot — go red and emit a steam-siren when:
  - an unauthorized harvest fires (raider stole a pod), OR
  - a kept liability goes feral (NURTURE'd liability turned), OR
  - **an un-harvested critter escapes** (§9.6) — the alarm pulse is colored differently (violet) so a player viewing a clip can read at a glance whether it's a raid or an escape.
  Pylons are visible 100+ studs.
- **Combat lanes**: streets between plots are wider than the plot interior. Chases look cinematic and have natural camera angles.
- **Public Arena** at the far edge of the Cogworks — opt-in 1v1 critter duels. Spectator stands. Generates clip content.
- Raid attacks are now **funneled through the Steal Portal** (Cogworks §2.1) → procedural corridor → target's Hatchery. There is no "walk directly across the world to a stranger's Hatchery" path; raids are gated on the corridor system. See `AGENT_COORDINATION/tickets/BAB-STEAL-CORRIDORS.md`.

### 2.4 Pawn Forge (sell pad on plot)
The on-plot sell pad is now: 12×0.4×12 ember-orange neon pad on the plot floor (post-fix verified live), brass post + sign, glow halo. The Pawn Forge is the **fast-sell-to-merchant** path — flat formula, no haggling, instant payout. For destination commerce (NPC merchants with personality, player-to-player trade, asset/liability arbitrage), players walk through the **Marketplace Portal** in the Cogworks (§2.1) — see `AGENT_COORDINATION/tickets/BAB-MARKETPLACE-HUB.md`. Both paths are first-class; the Pawn Forge is for "I just want this gone" and the Marketplace is for "I want top dollar."

**Required additions next iteration**:
- Coin-and-gear particle burst on successful sell, scaled to payout magnitude.
- Brass-bell SFX (3 variants).
- Camera shake on Mythic sell.
- Sign content adapts to stash: "💰 SELL 1 critter" → "💰 SELL 5 (incl. 1 Rare)" → "👑 MYTHIC READY!" — turns the sign into a status indicator.
- A second "SCRAP" pad next to it (smaller, `Valve Red` rim) for the recycle path — see §9.
- A **comparison sign** above the Pawn Forge: "Marketplace: avg 1.4× more for assets to your class →" — surfaces the arbitrage incentive at the moment of decision.

### 2.5 Egg Emporium (replaces Seed Shop)
Currently a green neon block. Replace with a **proper market stall**: striped awning (Brass + Goggle Gold), sandwich-board sign in Antique font, a slowly rotating glass cloche on a pedestal showing the rarest in-stock egg. Egg variants visible behind the counter as inventory parallax. Looks like a destination, not a hitbox.

### 2.6 Repair Bay (new)
A brass-and-glass workshop in the Cogworks. Players walk up with a damaged owned critter; UI shows current upgrade durabilities; a payment + animation restores them. Critical income sink → re-spend on upgrades after combat.

### 2.7 Class Hall (new)
Pillared building. Banner of the 5 class crests. Walking through teleports the player into a 360° stage where each class avatar performs a one-second signature animation (knight: shield-slam, alchemist: bottle-pour, sky pirate: pistol-spin, tinkerer: wrench-twirl, hexer: rune-flick). Hover/tap each for the class's full read. A free first-time pick; respecs cost 199 Robux (also gameplay-attractive — see Open Questions §17).

---

## 3. UI / HUD

### 3.1 HUD layout (mobile-first, 1080×2400 reference)

```
┌────────────────────────────────────────┐
│ [☰]  Top quest banner (1 line)   [💰] │  ← Top bar (cash always upper-right)
│                                        │
│ [🛡 KNIGHT]                            │  ← Class badge (left, persistent)
│                                        │
│           (gameplay viewport)          │
│                                        │
│ [🥚 EGG BAG: Brass Beetle ×3]          │  ← Egg stash chip (live)
│ [⚙ COG PARTS: 142]                     │  ← Secondary currency
│ [🐾 STABLE: 4 / 6]                     │  ← Owned critter count + capacity
│                                        │
│  [🏰 PLOT]                  [🛒 SHOP]  │  ← Bottom action bar
└────────────────────────────────────────┘
```

**Locked rules**:
- Bottom action bar buttons minimum **88×88pt**. Tap area extends 12pt beyond visible.
- Cash counter is **upper right, never moves**. Players' eyes lock to that corner.
- Class badge is **upper left, never moves**. Identity is HUD-permanent.
- Top quest banner is **one line, max 38 characters**. Longer messages → modal.

### 3.2 Toasts & feedback
Every meaningful event gets a feedback layer in this priority order:
1. **Camera shake** (Mythic hatch, raid alarm, big sell — preserve impact).
2. **Screen-edge pulse**, color-coded:
   - Ember Orange = sell-success or fire damage
   - Aether Cyan = mythic / mutation
   - Valve Red = raid / liability turning feral
   - Brass = neutral plot event (pod ready, repair complete)
3. **3D world particle** (gears, sparks, steam, embers).
4. **Toast** (top-center, auto-dismiss 2.5s).
5. **Sound** (mandatory for every event — silence reads as broken).

### 3.3 Empty-state design
Every empty state must teach + tease:
- Empty stable: "🥚 Hatch your first critter — pods are free for 60 seconds!"
- Empty wallet: "💰 Sell or scrap a critter to earn coin."
- No friends visiting: "🎩 Invite a friend — visitors get +10% scrap value all session."
- Class not chosen: "🛡 Pick a class at the Class Hall before your first hatch — it shapes which critters help you and which try to eat you."

### 3.4 Modals
- Centered, rounded corners 12px (more architectural than the prior 18px).
- 4px UIStroke in topic color (Goggle Gold for premium, Brass for friendly, Valve Red for warnings).
- Backdrop dim: 55% black with a 3% Ember Orange tint (warm forge feel).
- Auto-dismiss 8s for onboarding; **never auto-dismiss** for purchase confirmations or harvest decisions (§9).

### 3.5 Critter Card (new component)
Recurs everywhere a critter is shown (harvest moment, stable, combat, market, trade):

```
┌──────────────────────────────┐
│  [3D portrait, slow-rotate]  │
│  Brass Beetle                │  ← name (or "Unnamed #3" until nurtured)
│  ⭐ Uncommon                  │  ← rarity rim color
│  HP ████████░░  80/100       │  ← combat HP
│  Slots: [Armor][Pwr][Spd][?] │  ← upgrade slots (filled or empty)
│  Affinity: 🛡+ ⚗-  ✈n  🔧+ 🜏n │  ← class affinity row (asset/liability/neutral)
└──────────────────────────────┘
```

**Affinity row is the most important UI element in the entire game.** It tells the player, at-a-glance, whether keeping this critter is a good idea given their class.

---

## 4. Audio Design

### 4.1 Required SFX library (must ship at launch)
- Egg drop into pod (clink + pneumatic hiss)
- Pod active (looping low boiler hum)
- Pod ready / critter ready to hatch (rising whistle)
- Hatch — common (gentle pop + cute chirp)
- Hatch — rare (chord + glow whoosh)
- Hatch — Mythic (dramatic chord + freeze-frame stinger + steam burst)
- Sell (brass cash-register cha-ching, 3 variants)
- Big sell (>$500) — bell tower toll
- Scrap (saw + clatter, gear pieces hitting a tray)
- Nurture / send-to-stable (soft mechanical purr)
- Liability gone feral (warning klaxon, distant)
- Raid alarm (looping steam siren, distance-attenuated)
- Combat — critter on critter (clangs, hisses, sparks)
- Combat — critter on player (heavier impacts)
- Repair Bay tick (timer wind-up + final ding)
- Class-pick fanfare (one per class, 1.2s)
- Footsteps on plank, cobblestone, metal-grate (3 surfaces)
- Button tap (subtle clockwork tick on every UI interaction)

### 4.2 Music
- Loop A — **Cogworks daytime**: warm acoustic + light brass section, 84 BPM. The cozy default.
- Loop B — **Hatchery work**: lo-fi music-box + tinkerer percussion, 72 BPM.
- Loop C — **Aether Hour**: spectral synth + glass harmonica, 96 BPM, slight tension.
- Loop D — **Combat/Raid**: marching drums + brass stings, 130 BPM, kicks in only when an alarm or arena fight starts.
- Music **ducks 60%** during steam-siren alarms, mythic hatches, and modal opens.

### 4.3 Voice / stingers
Hard-no on TTS or full voice acting. Yes on **non-verbal stingers** — chirps, growls, mechanical squeaks, brass coughs — that translate cross-language. Each critter species needs:
- one idle chirp (used in stable + portrait card)
- one happy chirp (after upgrade installed)
- one angry growl (used when liability turns feral)

---

## 5. VFX & Game-Feel

### 5.1 Mandatory feedback particles

| Event                  | VFX                                                                           |
| ---------------------- | ----------------------------------------------------------------------------- |
| Egg loaded             | Steam puff out of pod (white particles, 0.5s)                                 |
| Pod incubating         | Small brass cog-spin overlay on pod lid                                        |
| Pod ready              | Twinkling cyan stars around pod lid (looping)                                  |
| Hatch — common         | Steam burst + cute critter pop animation                                      |
| Hatch — rare           | Sparkline gear particles + slow camera dolly-in                               |
| Hatch — Mythic         | Full screen ember-orange flash + cyan light pillar from pod + 1.5s freeze     |
| Sell                   | Coin-and-gear shower from Pawn Forge in arc → fly to cash counter             |
| Scrap                  | Saw shower + cog parts fly to Cog Parts counter                               |
| Nurture                | Brass leash animation (critter trots into stable on its own)                  |
| Upgrade installed      | Cog locks-in animation on slot + ring of sparks                                |
| Combat — critter       | Sparks on impact, brass-clang particles, steam puffs from damage              |
| Player damaged         | Red screen-edge pulse + camera shake 0.15                                      |
| Liability turns feral  | Pylon goes red + plume of black smoke from critter + valve-red world tint     |
| Repair complete        | Tinkerer-wrench animation + bright ding particle ring                          |

### 5.2 Camera
- Default: third-person follow with a subtle 5° tilt during Forge Hour.
- Auto-orbit during the **harvest decision moment** (3-second slow rotate around the critter while the SELL/SCRAP/NURTURE buttons are up). This is the single most-screenshotted moment in the game — must be cinematic.
- Auto-zoom 1.3x within 4 studs of an active combat (critter-on-critter or critter-on-player).
- Camera shake amplitude budget: 0 default, 0.05 big sell, 0.15 Mythic / player damaged, 0.25 raid alarm. Never higher (motion sickness on phones).

### 5.3 The "wow" frame
Every player must hit one of these visual peaks within their first 3 minutes:
1. **Class-pick reveal** — 360° avatar showcase in the Class Hall (§2.7).
2. **First hatch** — pod hisses, critter pops out, auto-orbit camera, three big buttons appear.
3. **First Mythic** (force at least one Rare in the starter pack, with ~5% Mythic upgrade) — light pillar, flash, and a cute critter that the player did NOT expect.

---

## 6. Avatar & Cosmetics (revenue layer)

Roblox players spend on **identity** before they spend on power. Required cosmetic categories at launch:
- **Class outfits** (one base set per class, 3–5 paid recolors each, 199–499 Robux): Knight plate, Alchemist apron, Sky Pirate coat, Tinkerer overalls, Hexer cloak.
- **Goggle racks** (head-slot cosmetics, 49–199 Robux): aviator goggles, monocle, brass crown, oil mask.
- **Backpacks** visible while working: tool satchel, alchemy rack, pet carrier, dragon harness.
- **Critter cosmetic mods** (applied to your owned critter, 99–499 Robux): brass implant, eye patch, rocket boosters, glowing oil-coat. Visible in stable + during combat.
- **Plot fences** (see §2.2 — the whale tier).
- **Trail effects** (steam trail, cog trail, ember trail) — 99 Robux.
- **Wardrobe seasonal drops**: Halloween mech-pumpkin armor, Winter brass-snow gear, Summer airship-deck kit, etc. Each season = thumbnail update + TikTok hook.

---

## 7. Class System (new — the identity layer)

Each player picks one of five classes at first run. Class is permanent until paid respec (199 Robux, recoverable through gameplay). Class shapes:
- **Affinity** to each critter species (asset / liability / neutral) — see §8.
- **Signature ability** triggered by a HUD button, with cooldown.
- **Combat baseline** (HP, damage type, speed).
- **Hatch bonus** — small bias toward favorable species.

| Class           | Crest | Combat baseline                | Signature ability                                     | Hatch bias                  |
| --------------- | ----- | ------------------------------ | ----------------------------------------------------- | --------------------------- |
| **Knight**      | 🛡     | High HP, melee, slow            | Shield Bash — stuns one critter 2s                    | +5% Mounts                  |
| **Alchemist**   | ⚗     | Medium HP, ranged poison, slow  | Brew Cloud — DOT poison cloud, 4s                     | +5% Magical familiars       |
| **Sky Pirate**  | ✈     | Low HP, ranged gun, fast, jump  | Grappling Hook — pull self/enemy 30 studs              | +5% Sky-type mounts         |
| **Tinkerer**    | 🔧    | Medium HP, deploy turrets       | Cog Turret — places auto-firing brass turret 8s        | +5% Cogwork pets            |
| **Hexer**       | 🜏     | Low HP, magic, fragile, fast    | Hex Bolt — single-target damage + slow 3s             | +5% Magical critters        |

**Class identity rule**: a class without a *visible* silhouette change at distance fails. Knights look like knights from 100 studs. Hexers look like Hexers from 100 studs. Class is the player's brand inside the game.

---

## 8. Critter Species & Asset/Liability Matrix (new — the heart of the design)

Each pod hatches one of 12 launch species. Each species has a base profile + an asset/liability flag for each class. **The matrix is the most important design table in this document — playtest it monthly.**

Legend: **A** = asset (gives bonus, fights for player), **L** = liability (eventually attacks player or plot), **n** = neutral (decorative, mild bonus).

| Species              | Cuteness at hatch                   | Sell value | Scrap value | Knight | Alchemist | Sky Pirate | Tinkerer | Hexer |
| -------------------- | ----------------------------------- | ---------- | ----------- | ------ | --------- | ---------- | -------- | ----- |
| **Mech-Hound**       | Cogwork puppy, big eyes              | $40         | 12 cp        | A     | n         | n          | A        | n     |
| **Steam Stallion**   | Brass colt, steam from nostrils      | $90         | 25 cp        | **A** | n         | L          | n        | n     |
| **Sky Wyvern**       | Tiny dragon, fluffy wings            | $120        | 30 cp        | **L** | n         | **A**      | n        | n     |
| **Cogwork Rat**      | Mech-rat, monocle                    | $20         | 30 cp        | n     | A         | A          | **A**    | A     |
| **Brass Beetle**     | Tiny beetle, polished shell          | $35         | 18 cp        | A     | n         | n          | A        | n     |
| **Aether Hummingbird**| Crystal-winged bird                  | $80         | 22 cp        | n     | **A**     | A          | n        | A     |
| **Iron Hydra**       | Three baby snake heads               | $200        | 45 cp        | **L** | n         | L          | L        | A     |
| **Fire Salamander**  | Tiny lizard with flame tail          | $150        | 35 cp        | **L** | A         | n          | L        | A     |
| **Coal Drake**       | Baby dragon, black scales, ember eyes| $300        | 60 cp        | **L** | n         | **A**      | L        | n     |
| **Ember Imp**        | Tiny fire spirit, mischievous        | $100        | 40 cp        | L     | **A**     | n          | L        | **A** |
| **Patina Toad**      | Copper-skinned magic toad            | $70         | 28 cp        | n     | A         | n          | n        | **A** |
| **Cogwork Cat**      | Mechanical cat, glowing eye          | $90         | 32 cp        | n     | A         | n          | A        | **A** |

**Reading the table**:
- A Knight should keep Mech-Hounds and Steam Stallions; sell or scrap dragons/hydras/imps.
- A Sky Pirate should keep Wyverns and Coal Drakes (sky synergy); sell Stallions (anchor weight).
- A Hexer thrives on Imps and Hydras and Cats; should sell Hounds (anti-magic).
- The **bold** entries are headline matchups — used in marketing thumbnails.

**Liability behavior**: a kept liability has a Bonding Timer (~12 minutes wall-clock) before it goes feral. It then begins attacking nearby pods or the player directly. The player must either fight it, sell it (still possible mid-bond at reduced value), or scrap it. **This is the source of the headline "I tried to raise a dragon as a knight" content.**

---

## 9. Harvest Decision (Sell / Scrap / Nurture)

The single highest-stakes UX moment in the game.

### 9.1 Trigger
When a pod completes incubation, the critter pops out into a small holding cage on the pod. Camera auto-orbits (§5.2). A modal opens with the Critter Card (§3.5) and three buttons.

### 9.2 The three buttons

| Button        | Color           | Reward                              | Side effect                                              |
| ------------- | --------------- | ----------------------------------- | -------------------------------------------------------- |
| 💰 **SELL**   | `Ember Orange`  | Full sell value (gold)              | Critter gone. Standard outcome.                          |
| ⚙ **SCRAP**  | `Brass`         | Half-value as Cog Parts (cp)        | Critter gone. Cp used for upgrades (§10).                |
| 🐾 **NURTURE**| `Copper Patina` | Critter joins your stable           | Costs 1 stable slot. May become asset OR liability.      |

### 9.3 Class-aware copy (REQUIRED)
The modal pre-reads the affinity row (§3.5) and surfaces a single advisory line at the bottom of the card. Do **not** disable buttons — the chaos of a bad choice is the content.

- A 🛡 Knight hatching a 🐉 Coal Drake sees: *"⚠ As a Knight, this Coal Drake may turn on you. Most knights sell or scrap."*
- A ✈ Sky Pirate hatching a 🐉 Coal Drake sees: *"✓ Sky Pirates ride Coal Drakes. Strong asset if you nurture."*
- A 🜏 Hexer hatching an Ember Imp sees: *"✓ Hexers and imps are old friends. Powerful familiar if nurtured."*

### 9.4 Decision pressure
- 30-second soft timer on the modal. After 30s, an idle hint pulses ("Pick one — your critter's getting impatient"). After 60s, the modal locks the SELL choice in by default. Pressure preserves pace; lock-in protects AFK farmers from accidental nurture of liabilities.
- This is the *modal*-level timer for an active player at the pod. The *macro*-level "you forgot about this critter entirely" timer is the **escape window** below.

### 9.5 Special tags
Some critters spawn tagged:
- **Contraband** (rare, ~3%) — cannot be sold (Merchants' Guild ban). Player must SCRAP or NURTURE. Often very high stat. Drives drama clips.
- **Sacred** (rare, ~2%) — cannot be scrapped. Hexers love this; Tinkerers groan.
- **Mythic** (very rare, ~0.5%) — see Rarity ladder. Strictly better stat profile; affinity rules still apply.

### 9.6 Escape window (the macro-timer)

If the player doesn't return to the pod within a window equal to the
species' grow time (1:1 ratio — a 240s grow ⇒ 240s window), the
critter **escapes the pod**. Escape is the **chaos generator** of the
loop — risk-pressure for the active player, content-generator for live
stream clips.

**State machine** (per pod):

```
EMPTY → INCUBATING → RIPE (escape timer T_escape = T_grow starts) → ESCAPED → BEHAVIOR_ACTIVE → DESPAWNED → EMPTY
                       ↑                                                ↓
                       └─── HARVESTED (player walks over) ──────────────┘
```

**Asset escapes** (per the §8 affinity matrix): the escaped critter
runs a **beneficial** passive behavior on the player's plot for a
configured duration. Example seed entry:
- **Coal Drake (asset for sky pirate / hexer)**: "Coal Forge" — every
  incubator pod heats 1.5×; all in-progress pods ripen 50% faster for
  the duration.

**Liability escapes**: a **damaging** passive behavior. Example:
- **Coal Drake (liability for knight / tinkerer)**: "Drake Strafe" —
  every 8s, picks one ripe-or-incubating pod and sets it on fire; the
  pod becomes EMPTY and any in-progress incubation is lost.

**UX during the escape window**:
- The pod's aether window pulse shifts hue from cyan → ember → red as
  the timer drains. At <25% remaining, it strobes red and the plot's
  alarm pylon (§2.3) lights up violet (so a clip viewer can read at a
  glance: violet = escape, red = raid).
- A new client-side **EscapeWarningHUD** stacks countdowns: "🐉 Coal
  Drake — 1:34 to escape!" Mobile-first per §3.1.

**On escape**:
- Toast (§3.2): "💥 Coal Drake escaped! Your pods are on fire." (liability)
  or "✨ Coal Drake forged free! Pods will ripen 50% faster." (asset).
- Telemetry: `pod_escaped` event with `{species, class, affinity,
  behavior}` for analytics tuning.

The escape mechanic ties directly to:
- **§2.3** Combat & raid lanes — alarm pylons fire violet.
- **§8** Critter affinity matrix — drives whether escape is asset or
  liability.
- **§10** Upgrade durability — liability ferals damage upgrade slots
  (per §10.4 + §11.4 mechanics).

Behavior catalog ships with **2–3 entries per class minimum** at
launch, expanded via live ops (§13). Full ticket:
`AGENT_COORDINATION/tickets/BAB-CRITTER-ESCAPE.md`.

---

## 10. Upgrade System (new — the cash sink)

Each owned critter has 4 upgrade slots: **Armor**, **Power**, **Speed**, **Special**. Buying an upgrade costs Gold and/or Cog Parts at the Egg Emporium / Premium Forge / Black Market.

### 10.1 Durability tiers

| Tier               | Lifetime                                  | Damage interaction                                  | Use                         |
| ------------------ | ----------------------------------------- | --------------------------------------------------- | --------------------------- |
| **Permanent (P)**  | Forever (unless removed by player)        | Unaffected by combat damage                         | Cosmetic mods, naming, color|
| **Semi-Perm (S)**  | Until durability hits 0%                  | Each major damage event drops durability ~25%       | Stat boosts, armor plating  |
| **Temporary (T)**  | Time-limited (10 / 30 / 60 minutes)       | Lost first under damage; expires on timer regardless| Battle stims, overclocks    |

### 10.2 Slot examples (must be implemented at launch — minimum 4 per slot per class-flavor)

**Armor slot**:
- *Brass Plating* (S, 80 cp) — +25 HP, +10% damage reduction
- *Aether Ward* (S, 120 cp + $200) — +30 HP, blocks first magic hit
- *Reinforced Bolts* (P, $400) — cosmetic + small visual + +5 HP
- *Combat Stim Vial* (T 30 min, $80) — +50% HP for the timer

**Power slot**:
- *Cog-Tooth Hammer* (S, $250) — +30% melee
- *Steam Vent Cannon* (S, $400) — +40% ranged
- *Overclocked Core* (T 10 min, $150) — +100% damage, ends explosively (10 self-damage)
- *Ember Coating* (S, 90 cp) — adds fire DOT to attacks

**Speed slot**:
- *Greased Joints* (S, 60 cp) — +20% move speed
- *Wind-up Spring* (S, $300) — +1 dodge per combat
- *Quicksilver Drip* (T 60 min, $200) — +50% speed for the timer

**Special slot** (class-tied):
- *Knight Bond* — your Knight gains +10 HP while this critter is in stable
- *Alchemist Catalyst* — potion crafting +1 effect tier while this critter is alive
- *Sky Pirate Co-Pilot* — your jump/glide range +30%
- *Tinkerer Auto-Repair* — this critter slowly regenerates HP out of combat
- *Hexer Familiar Link* — your Hex Bolt cooldown −2s

### 10.3 Visual feedback
- Each installed upgrade shows as a small icon below the critter portrait, with a colored border by tier (gold = P, brass = S, cyan = T).
- Durability is rendered as a thin ring around the icon.
- When an S upgrade falls below 25%, the ring pulses red — pre-warning to repair.

### 10.4 The economic loop
This is the **primary reason combat exists**. Combat → damaged upgrades → repair cost or replace cost → spend gold and Cog Parts → need more critters to sell/scrap → buy more eggs → hatch decisions → loop.

The loop must be tuned so a player who fights once per session needs ~30% of session-earned currency for repairs. Any more, retention bleeds. Any less, no spend pressure.

---

## 11. Combat & Damage System (new)

### 11.1 Combat triggers
1. **Liability goes feral** in a player's own plot (§8) — single-critter encounter.
2. **Raid attack** by another player or NPC — multiple combatants.
3. **Public Arena** opt-in 1v1 (§2.3).
4. **Boss event** (live ops weekly — see §13).

### 11.2 Combat model
Auto-resolved with visible action — players don't micromanage; they watch and intervene with their class signature ability. Each combatant has HP, DMG, SPD, and an elemental tag (Fire / Steam / Aether / None).

**Elemental rock-paper-scissors**:
- Fire > Steam (fire consumes water vapor)
- Steam > Aether (mechanical resists magic)
- Aether > Fire (water/magic dampens flame)
- None — neutral against all

### 11.3 Damage sources
- **Melee impact** — standard contact damage.
- **Fire** — applies a 4-second burning debuff (DOT). Triggered by Drake/Salamander/Imp.
- **Falls** — knockback off airship docks or arena edges.
- **Plot raid damage** — pods can be smashed (refundable repair).
- **Neglect** — if a stable is over capacity, all critters take 1 HP per minute of overflow.

### 11.4 Upgrade depletion (linked back to §10)
- Damage events apply in priority: T upgrades absorb first (one upgrade lost per event), then S upgrades degrade by 25%, then HP itself drops.
- P upgrades are never depleted.
- Once an S upgrade hits 0%, it visually shatters and is removed. Repair Bay (§2.6) restores at 50% of original cost.

### 11.5 Death
A critter at 0 HP is **incapacitated**, not deleted. It can be revived at the Repair Bay for 50% scrap value or scrapped on the spot. This avoids permadeath rage-quit.

The **player** at 0 HP respawns at the Cogworks fountain after 3 seconds. No item loss. Aggression timer on the offending liability resets so the player isn't infinitely chased on respawn.

---

## 12. Onboarding Flow (the 90-second hook, updated)

| Time     | Player sees                                                                                  | Designed feeling             |
| -------- | -------------------------------------------------------------------------------------------- | ---------------------------- |
| 0–3s     | Spawn at the Cogworks during Forge Hour, music swells, welcome modal fades in                | "This place is alive"        |
| 3–10s    | Welcome modal: 4 punch-line steps + "PICK YOUR CLASS" CTA                                    | Direction                    |
| 10–25s   | Class Hall — 5 avatars rotate, tap to select; brief 1-line description per class             | Identity                     |
| 25–35s   | Big purple arrow from Class Hall to nearest claim pad                                         | Path                         |
| 35–40s   | Touch claim pad → fanfare → teleport → camera reveal of personal Hatchery                    | "This is mine"               |
| 40–60s   | Free Brass Beetle egg auto-loaded into Pod 1; 20s incubation visible                          | Anticipation                 |
| 60–80s   | Pod ready, hatch ceremony plays, Critter Card pops, three buttons appear                     | The hook                     |
| 80–90s   | Player picks SELL → coin shower → cash counter ticks → tutorial complete + free Mythic egg coupon | Hook complete + return promise |

**Locked rule**: a player must close at least one full hatch-decide-collect loop in under 90 seconds. Tune `growSeconds` of the Brass Beetle starter to 20s. The free Mythic egg coupon is the **return-the-next-day** bait.

---

## 13. Content Cadence (live ops, themed)

The single biggest predictor of long-tail revenue. Steampunk-themed cadence:

- **Daily**: rotating Egg of the Day at the Emporium, login bonus = 1 random Cog Part bundle.
- **Weekly**: themed event:
  - "**Aether Bloom**" — magical critter spawn rate ×2, Hexers +20% scrap.
  - "**Forge Fest**" — fire critters ×2, Knights' bonded stallions get a free Ember Coating.
  - "**Sky Regatta**" — airship racing event in Public Arena, Sky Pirates featured.
  - "**The Great Heist**" — raids enabled with bonus loot, Tinkerer turrets +40% damage.
- **Monthly**: limited cosmetic drop tied to real-world holiday or trending meme (a brass jack-o'-lantern in October, a clockwork Santa in December).
- **Quarterly**: new biome unlocked at the Cogworks rim — Skyport District, Foundry Caverns, Misted Marsh — each with its own boss critter and ambient music.

**Aesthetic criterion**: every event must have a **single thumbnail-ready hero image** — a screenshot a player would post unprompted. If the dev team can't produce that hero image during planning, the event isn't ready.

---

## 14. Mobile Performance Budget

70%+ of Roblox traffic is mobile. Lock these:
- **Frame target**: 60 FPS on iPhone XS / Galaxy S9.
- **Part count budget**: ≤ 800 parts per Hatchery, ≤ 8,000 total in render distance.
- **Particle cap**: 250 simultaneous (steam vents are everywhere, budget bumped from 200). Per-event budgets in §5.1 — anything more, swap to a single mesh+animation.
- **Texture budget**: 2 MB total custom textures. Prefer solid colors + Neon for glows.
- **Streaming enabled**: yes. `StreamingMinRadius = 80`, `StreamingTargetRadius = 220`.
- **No live shadows on critters** — performance killer. Use a single baked oval Decal under each critter as ground-shadow.
- **Combat caps**: max 6 simultaneous active combatants per local plot, max 12 in arena. Beyond that, cull furthest.

---

## 15. Design Criteria Checklist (must-define-before-launch)

This is the single source of truth. Each line must have an owner and a "done" definition.

### A. Visual identity
- [ ] Color tokens (§1.2) exposed via `BrandColors.luau`
- [ ] Typography helpers via `BrandText.luau`
- [ ] Custom skybox (Forge / Aether)
- [ ] Lighting + Atmosphere profile version-controlled
- [ ] Rarity rim-glow shader pass implemented
- [ ] Material palette enforced — code review blocks `SmoothPlastic`, `Plastic`, `Glass`, `ForceField`, `Foil`

### B. World
- [ ] All 8 Cogworks anchors built and reachable from spawn within 3s
- [ ] Hatchery reskin (planters → incubator pods, sell pad → Pawn Forge) live
- [ ] Scrap pad (`Valve Red`) added next to Pawn Forge
- [ ] Repair Bay functional with durability UI
- [ ] Class Hall functional with 5 class previews + respec flow
- [ ] Plot fence tiers (5 tiers) modeled
- [ ] Alarm pylons + raid lanes on every plot
- [ ] Visit-a-friend teleport hub
- [ ] Trophy Hall renders top 100 cached cross-server

### C. UI / HUD
- [ ] Cash + Cog Parts + Stable + Class badge persistent on HUD
- [ ] Critter Card (§3.5) component with affinity row
- [ ] Toast queue + screen-edge pulse system (4 colors)
- [ ] Empty-state copy for all 10 known empty states
- [ ] Modal style guide (one component, all variants, with Valve Red warning variant)
- [ ] Class-aware advisory copy for harvest modal (§9.3)

### D. Audio
- [ ] All 18 SFX from §4.1 licensed/produced
- [ ] 4 music loops imported with ducking metadata
- [ ] Per-species idle/happy/angry chirps for all 12 species
- [ ] No-TTS rule documented for contributors

### E. VFX
- [ ] Mandatory particle list (§5.1) implemented behind a `Feedback.luau` API: `Feedback.fire("MythicHatch", position, payload)` — no designer touches particles directly
- [ ] Camera shake controller centralized (one entry point, amplitude budget enforced)
- [ ] Auto-orbit harvest moment verified on iPhone budget device
- [ ] "Wow frame" #1, #2, #3 verified via TestFlight or BrowserIDE

### F. Class system
- [ ] All 5 classes implemented with HP/DMG/SPD baselines
- [ ] All 5 signature abilities wired to HUD button + cooldown
- [ ] Class-pick + respec flow (gold + Robux paths)
- [ ] Class silhouette legible at 100 studs (silhouette test passes for each class)

### G. Critters & matrix
- [ ] All 12 species modeled at hatch-cute, juvenile, and adult forms
- [ ] Asset/Liability matrix data table version-controlled in `CritterMatrix.luau`
- [ ] Bonding Timer + feral behavior implemented + tested end-to-end
- [ ] Contraband / Sacred / Mythic tagging + UI

### H. Harvest decision
- [ ] SELL / SCRAP / NURTURE three-button modal with Critter Card embedded
- [ ] Class-aware advisory line surfaces correctly for all 5 × 12 = 60 combinations
- [ ] 30s/60s decision-pressure timers implemented
- [ ] Default-to-SELL lock-in for AFK protection

### I. Upgrades
- [ ] 4 slots × 4+ upgrades each = 16+ launch upgrades (and per-class Specials = 5 more)
- [ ] Tier visual differentiation (gold/brass/cyan ring colors)
- [ ] Durability ring rendering + repair flow at Repair Bay
- [ ] Pulse-red warning at <25% durability

### J. Combat & damage
- [ ] Auto-resolved combat with visible animations
- [ ] Elemental matchup rules (Fire/Steam/Aether/None) implemented
- [ ] Damage priority cascade: T → S → HP enforced
- [ ] Incapacitate-not-delete + Repair Bay revive flow
- [ ] Combat caps per plot/arena enforced

### K. Cosmetics
- [ ] Class outfit base set + 3 paid recolors per class
- [ ] Goggle racks (10 SKUs)
- [ ] Critter cosmetic mods (12 SKUs at launch)
- [ ] Plot fence tiers (5 SKUs)
- [ ] Seasonal calendar mapped for first year

### L. Onboarding
- [ ] 90-second hook tested with 5 first-time mobile players, every one reaches first sell
- [ ] Tutorial 3D arrow system (follows next action)
- [ ] Class-pick UX time-to-decision averages <10s in playtest

### M. Live ops
- [ ] Event template doc — designer can stand up a new weekly event in <8h
- [ ] Hero-image enforcement in event-spec template

### N. Performance
- [ ] StreamingEnabled + radii configured
- [ ] Plot part-count audit script in CI
- [ ] FPS test rig on minimum-spec device run weekly

### O. Marketing creative
- [ ] Thumbnail style guide (3 hooks: cute hatch, identity drama, combat spectacle)
- [ ] Vertical clip template (3s hook / 5s payoff / end-card)
- [ ] First 50 TikTok scripts drafted before public launch — at least 10 lean on the "Knight raises a dragon" headline matchup

---

## 16. Anti-Patterns (do not ship)

- Plain Baseplate sky → cut, custom Forge/Aether skybox required.
- Plastic-y `SmoothPlastic` everywhere → kills the steampunk feel; enforce Metal/CorrodedMetal/Wood/Brick palette.
- Pastels (mint, candy pink, lavender baby) → leftover from prior direction; remove on sight.
- Walls of text in modals → 1-line steps, max 4 steps, max 38 char advisory lines.
- Generic FredokaOne everywhere with no stroke → unreadable on bright phones.
- Click-to-claim flow → walk-on triggers the body, not the thumb.
- Dark patterns (fake gift boxes, fake rewards, free-Robux popups) → shadowbans the experience.
- Unfiltered chat input from minors → all routed through `Chat:FilterStringAsync`.
- Permadeath of nurtured critters → rage-quit. Use Incapacitate + Repair Bay (§11.5) instead.
- Class-locked content the player can't preview before committing → always show what each class is and isn't capable of in the Class Hall.

---

## 17. Open Design Questions (must resolve before vertical-slice review)

1. **Liability friction tuning** — Bonding Timer set at 12 minutes is a guess. Playtest must answer: do players panic-sell too fast, or never panic at all? The drama only works if the timer is felt.
2. **Class respec economy** — first respec free or paid from minute zero? Recommended: first free, gameplay-bought respec for 50,000 gold or 199 Robux. Keeps early experimentation cheap, monetizes late-game pivots.
3. **Trade economy scope** — full P2P critter trading at launch (toxicity + scam risk) or NPC-only at launch with P2P in v1.1? Recommended: NPC at launch.
4. **Plot raid opt-in** — does every player get raid-able by default, or is raid an opt-in? Recommended: VIP Plot gamepass = 199 Robux for raid immunity. Free players stay in the chaos for virality. Mirrors the previous answer; fits the new design unchanged.
5. **Mythic mutation rate** — set at 0.5%; any higher feels routine, any lower feels unreachable. Validate against actual session-length data after first month.
6. **Combat micro vs. macro** — auto-resolved with signature-ability nudge is the safe pick for mobile. Should there be a tap-combat opt-in? Recommended: not at launch; revisit after Month 2 retention data.

Resolve in the brand voice: **identity first, drama on opt-in, cuteness always.**

---

**This spec is the design contract.** If a feature doesn't have a corresponding criterion in §15, it isn't ready to ship. Update this file when criteria evolve — never hand-wave.
