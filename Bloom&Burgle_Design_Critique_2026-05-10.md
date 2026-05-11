# Bloom & Burgle — Design Critique (Phase 4 Launch Build)

**Date:** 2026-05-10
**Build:** post-Phase 4 (commit `e92f538`), Hatchery in-Studio Play session
**Captured by:** Claude via `scripts/debug/dbg shot` against a running Studio MCP bridge
**Captures dir:** `scripts/debug/captures/`

This doc is the persistent record of the 2026-05-10 audit. It feeds future
tickets and exists so neither a human nor a future Claude session has to
re-derive the same findings. **It is opinionated** — every finding is
tagged with severity, and every recommendation includes a virality or
revenue rationale where applicable.

---

## TL;DR

**The systems work; the brand doesn't ship yet.** Steampunk-Ghibli identity
is in the code (`BrandColors`, banned `SmoothPlastic`/`Glass`, `Antique`
font) but on screen the game reads as a generic Roblox simulator template:
hot-pink Fredoka bottom nav, cylindrical concrete planters, "$$$ SELL"
carnival sign, sparse grass world.

Two structural bottlenecks:

1. **Virality is bottlenecked by the world not being screenshotable.** No
   hero landmark. Aerial views would lose to any cottagecore farm sim.
2. **Revenue is bottlenecked by gamepass invisibility.** Zero upsell
   touchpoints in any of the six captures.

Tier 1 fixes (this commit) address Trophy Hall legibility, bottom-nav
brand drift, and Friends-panel empty state. Tier 2 (next 2 weeks) is the
hero Brass Clocktower + Tinkerer's Pass gamepass. Tier 3 (quarter polish)
is class-themed planters, on-spawn quest chain, Mythic display pedestal,
time-of-day cycle.

---

## Captured shots

| Shot | File | What's in it |
|---|---|---|
| Plaza overview | `scripts/debug/captures/plaza-overview.png` | Player at spawn, Trophy Hall distant, full HUD |
| Trophy Hall close | `scripts/debug/captures/trophy-hall-close.png` | Both plaques, empty state |
| Plot overview | `scripts/debug/captures/plot-overview.png` | 9 empty planters, PAWN FORGE sign visible |
| Sell pad | `scripts/debug/captures/sell-pad.png` | "$$$ SELL" wood sign + orange glow beacon |
| Friends panel open | `scripts/debug/captures/friends-panel-open.png` | Slide-out HUD, empty list, overlaps PLOT button |
| World aerial | `scripts/debug/captures/world-aerial.png` | Egg Emporium + sparse grass + floating banner |

**Not captured** (separate `.rbxlx` files, would need re-opening Studio):
Marketplace (BrassBart / Hexerine / Verda NPCs + quote modal), Corridors
(Steal-portal stub), Mythic ceremony in motion (eval blocked by client/
server context — needs `/devmode on` + `/testmythic` + mid-bloom capture).

---

## Findings by area

### Trophy Hall (just-shipped, highest-leverage)

| Finding | Severity | Recommendation | Owner |
|---|---|---|---|
| Plaque body (`IronworkCharcoal`) bleeds into back wall (same color) — plaques don't read as separate trophy slabs | 🔴 Critical | Recolor plaque body to a brass-stained-wood tone; add 1-stud inset shadow | **Tier 1 (this commit)** |
| Empty state ("— No entries yet —") tells player it's broken instead of aspirational | 🔴 Critical | Pre-render 10 rank-slot placeholders ("1. —", "2. —", …) + criteria footer | **Tier 1** |
| No celebration cues — plaques are flat text on slabs | 🟡 Moderate | Add a `PointLight` (Brass color, range 12) above each plaque | **Tier 1** |
| Right plaque partially obscured by SEED BAG HUD widget | 🟡 Moderate | Auto-fade HUD widgets within `TrophyHall.MagnitudeRadius`, or move SEED BAG down 50px | Tier 2 |
| Hall is 1D — flat slab, no podiums, no avatars, no anchoring | 🟡 Moderate | Two `HumanoidDescription:GetFromUserId`-loaded avatar busts for the rank-1 holders | Tier 2 |
| No spawn-side prompt that the hall exists | 🟢 Minor | "🏆 Check the Trophy Hall +Z" first-spawn toast | Tier 3 |

#### Virality (Trophy Hall)
**The hall is your single best shareable moment. Right now it shines for nobody.**
Add a `📸 Share Rank` button next to rank-1 entries → fires server screenshot
service or deep-link. Whoever hits #1 will screenshot themselves there.
Free organic growth, zero ad spend.

#### Revenue (Trophy Hall)
Rank-1 holders get a brass crown floating above their character in-world.
Gate that crown via Gamepass: **"🏆 Trophy Hall Plus" (199 Robux)** — keeps
the crown PERMANENTLY even when they fall off rank-1. Whales pay to immortalize.

---

### Plaza & Bottom Nav (brand-identity emergency)

| Finding | Severity | Recommendation | Owner |
|---|---|---|---|
| Bottom nav breaks every brand rule — hot pink/cyan Fredoka, looks pasted from a starter kit | 🔴 Critical | Brass-bordered `OilBlack` panel, FredokaOne kept but on-brand. Rename PLOT → "🔧 MY WORKSHOP"; keep "🌱 SEED SHOP" (the panel it opens is literally titled that) | **Tier 1** |
| Floating "🌸 Bloom & Burgle 💰" world-text in TownSquare reads as a title-screen leak | 🔴 Critical | Delete `TownSquare.WelcomeArch` entirely — branding belongs on a future clocktower, not floating mid-air | **Tier 1** |
| Plaza ground is undifferentiated cobblestone circle in tan, fading into grass | 🟡 Moderate | Add cobblestone radial pattern; 4 brass lampposts (cardinal directions) | Tier 2 |
| Sky is locked at sunset | 🟢 Minor | Time-of-day cycle (10-min loop dusk→night→dawn); lampposts light up at night | Tier 3 |

#### Virality (Plaza)
**A distinctive world is screenshotable. A generic world is not.** TikTok
is dominated by "look at this aesthetic" sweeps. Right now your aerial
loses to any cottagecore sim. Build the **Brass Clocktower** as the hero
landmark — 60-stud-tall structure at Cogworks center, gear-faced clock
that actually ticks. One hero asset, one screenshot frame everyone reuses.

#### Revenue (Plaza)
Replace the floating banner slot with a rotating Featured Item chip:
"TODAY: 🐉 Coal Drake Egg — 30% off." Tapping it teleports to the
Marketplace's relevant NPC. Direct conversion from plaza idle to spend.

---

### Plot

| Finding | Severity | Recommendation | Owner |
|---|---|---|---|
| Planters are featureless concrete cylinders | 🔴 Critical | Brass rim mesh + soil divot; per-class variants (Knight iron, Tinkerer copper, Sky Pirate scrap) | Tier 3 |
| "Load Egg" ProximityPrompt is generic Roblox gray pill | 🟡 Moderate | `Style = Custom` BillboardGui template with brass border (~50 LOC global override) | Tier 2 |
| Sell sign reads "PAWN FORGE" tiny up top + huge red "$$$ SELL" — the high-quality framing is buried under casino stamp | 🟡 Moderate | Drop the SELL slab. "PAWN FORGE / Cog & Quill, est. 1882" engraved-brass plate + aether rune at the foot | Tier 2 |
| Empty pods show nothing about what's loaded — no preview of planted egg | 🟢 Minor | 30%-opaque class emoji on loaded pods during grow cycle | Tier 3 |

#### Virality (Plot)
Mythic critter screenshots are your shareable moment. The ceremony fades
after 3s and the trophy disappears. **Persist Mythic critters as small
brass-pedestal displays at the plot edge for 24h** (server-side
`os.time()` gate). Friends visiting see your trophies → flex content.

#### Revenue (Plot)
HUD shows `$10K` floating alone. **Show two currencies always** — Cash +
Cog Parts. Players who see Cog Parts on every screen get curious → check
their use → see they fuel premium upgrades → spend.

---

### Friends Panel (newly shipped)

| Finding | Severity | Recommendation | Owner |
|---|---|---|---|
| Empty state is literally nothing — vast dead air | 🔴 Critical | Empty-state Frame with "💤 No friends online — invite some?" + `SocialService:PromptGameInvite` button | **Tier 1** |
| Header doesn't show count | 🟡 Moderate | "👋 FRIENDS ONLINE (3)" — turns header into status line | **Tier 1** |
| No close affordance; F5 only | 🟡 Moderate | Add ✕ button top-right | **Tier 1** |
| Panel overlaps bottom PLOT button | 🟡 Moderate | Either shrink height or lift Y position | **Tier 1** |
| Background too opaque — hides world | 🟢 Minor | `BackgroundTransparency = 0.2` | **Tier 1** |

#### Virality (Friends Panel)
**Highest-leverage UX moment in the entire build.** Every player who
clicks FRIENDS and sees nothing is a player who *would* invite if asked.
Current panel says "you're alone." Good panel says "let's fix that —
one tap." Use `SocialService:PromptGameInvite(player)` — native Roblox
share UI, no friction. Lifts k-factor measurably.

#### Revenue (Friends Panel)
Reserve bottom strip of panel for static upsell:
"💎 Premium friends visit your plot 2× faster."
Repeated exposure → eventual conversion.

---

### World density / aerial

| Finding | Severity | Recommendation | Owner |
|---|---|---|---|
| World is empty — no hero piece, no skyline | 🔴 Critical | Brass Clocktower 60+ studs tall at Cogworks center, ticking clock face | Tier 2 |
| Egg Emporium is a generic timber-roof house | 🟡 Moderate | Reskin: copper-roof Victorian conservatory + stained glass + wrought-iron "MOLLY'S EGG EMPORIUM" | Tier 3 |
| No portal/marketplace visibility from spawn | 🟡 Moderate | Two stone-arch portals at ±X with swirling aether (Beam + Trail) | Tier 2 |

#### Virality (World)
One iconic landmark is what people screenshot. Pet Sim has the treasure
room. Adopt Me has the nursery castle. **Bloom & Burgle's move is the
Brass Clocktower.** Animated gears + sunset Roblox screenshot reads as
"this is a real game with craft behind it" — exactly the signal that
converts views to plays.

#### Revenue (World)
Daily-reward chest at the clocktower base; gated by **🎩 Tinkerer's Pass
(299 Robux)** for 2× rewards forever. Habit-forming retention + monetization
in one structure.

---

### Cross-cutting issues

| Issue | Severity | Why it matters | Fix |
|---|---|---|---|
| Font soup (Fredoka, Antique, FredokaOne, GothamBold, SourceSansItalic, Roblox default) | 🟡 Moderate | Inconsistent type kills brand recognition | Pick TWO: Fredoka for HUD, Antique for in-world signage |
| Three competing button shapes (rounded squircle, pill, cartoon) | 🟡 Moderate | Same operation, different visual rules | Build one `ButtonComponent` — 12px corner, 2px Brass stroke, OilBlack fill, SteamCream text |
| Cash and class badge equally weighted in HUD; class is informational, cash is action driver | 🟢 Minor | Wrong emphasis | Cash 32pt→48pt; class shrinks to shield-icon only |
| No tutorial after "press E" | 🟡 Moderate | New players bounce when loop isn't obvious | 3-step on-spawn quest: plant → harvest → sell |
| Static sunset lighting | 🟢 Minor | Limits visual variety | Time-of-day cycle |

---

## Priority Tiers

### Tier 1 — Ship before public listing (this commit)

1. **Trophy Hall legibility** — recolor plaque body, 10 rank-slot placeholders + criteria footer, PointLight spotlights, header text emoji clarification. (`TrophyHallScript.server.luau`)
2. **Bottom nav rebrand** — brass-bordered OilBlack panels, BrandColors tokens, rename PLOT→"🔧 MY WORKSHOP", keep "🌱 SEED SHOP" with new styling. (`CashHUD.client.luau`)
3. **Delete WelcomeArch banner** — drop the floating "🌸 Bloom & Burgle 💰" world-text. (`TownSquare.model.json`)
4. **Friends panel polish** — `SocialService:PromptGameInvite` empty-state CTA, count in header, ✕ close button, lift above PLOT button, transparency 0.2. (`FriendsListHUD.client.luau`)

### Tier 2 — Within 2 weeks (post-launch polish)

5. Brass Clocktower at Cogworks center (hero landmark; ticking face).
6. Daily-reward chest at clocktower base + Tinkerer's Pass gamepass (299 R).
7. Standardize fonts + button components (`UIComponents.luau` module).
8. Avatar busts for Trophy Hall rank-1 holders.
9. ProximityPrompt global brass restyling.
10. PAWN FORGE sign rebuild (drop "$$$ SELL").
11. Two portal arches at ±X with aether swirl.

### Tier 3 — Quarter-long polish (post-data)

12. Class-themed planters (Knight iron / Tinkerer copper / Sky Pirate scrap).
13. 3-step on-spawn quest chain.
14. Mythic display pedestal at plot for 24h.
15. Time-of-day cycle with lit lampposts at night.
16. Egg Emporium reskin (Victorian conservatory).
17. Class-badge → icon-only in HUD; cash size bumped.

---

## Open questions / followups

- **Marketplace + Corridors not captured this pass.** Need a follow-up
  audit with those `.rbxlx` files loaded in Studio. Specifically: the
  3 NPC merchants' visual identities, the sell-quote modal hierarchy,
  the Steal-portal stub UI.
- **Mythic ceremony mid-animation not captured.** Bridge `eval` is
  client-context only; can't `FireClient` from there. Next audit should
  use `/devmode on` + `/testmythic` triggered by a human in-Studio, then
  burst-capture via `dbg shot` mid-bloom.
- **No telemetry data yet from live users.** All recommendations above
  are designer-judgement; should be re-evaluated against funnel data once
  Phase 0 ingest sees 100+ unique players.

---

## Maintenance

This doc is a snapshot. When Tier 1 items ship, update the table at the
top of each section. When Tier 2 lands, archive the corresponding rows
and write a new audit. Keep one of these per major release so the design
trajectory is legible to future contributors.
