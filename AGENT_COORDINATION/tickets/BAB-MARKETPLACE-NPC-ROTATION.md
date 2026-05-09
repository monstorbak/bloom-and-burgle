# BAB-MARKETPLACE-NPC-ROTATION: 3 NPCs + daily rotating preferences + asset/liability arbitrage pricing

**Owner:** unassigned
**State:** inbox (design — ready to implement; this is the next Marketplace PR after the v1 scaffold)
**Priority:** P1 (engagement-foundational; without this, players have no reason to revisit the marketplace)
**Extends:** [BAB-MARKETPLACE-HUB.md](BAB-MARKETPLACE-HUB.md) — fills in the NPC merchant section v1 left as a stub ("Brass Bart at 1.2×; pending the other 2 NPCs + rotation").

**Files touched (planned):**

Marketplace place (`src-marketplace/`):
- modify `src-marketplace/ServerScriptService/BrassBart.server.luau` → refactor into the generic NPC merchant interface or fold into `NPCMerchants.server.luau`
- new `src-marketplace/ServerScriptService/NPCMerchants.server.luau` — boots and wires all 3 stalls
- new `src-marketplace/ServerScriptService/NPCRotation.server.luau` — daily rotation engine (UTC-aligned, deterministic across servers)
- modify `src-marketplace/StarterPlayerScripts/MarketplaceUI.client.luau` — render "today's special" banner per NPC + asset/liability icons + premium-reason tooltip

Shared (`src/ReplicatedStorage/Modules/`):
- new `MerchantPersonalities.luau` — preference profiles, dialogue lines, visual identity per NPC (mounted into both Hatchery + Marketplace via Rojo `$path`)
- new `CritterAffinity.luau` (or extend existing if present) — single source of truth for "is species X an asset or liability for class Y?"

Hatchery side (`src/`):
- (none — this PR doesn't touch the Hatchery)

## Problem

The Marketplace v1 scaffold ([1bbb5ca](https://github.com/...)) ships with **one** static NPC merchant (Brass Bart at 1.2× formula). Three issues:

1. **No daily hook.** Without rotating preferences, there's no reason to log in *today* vs tomorrow. Modern Roblox sims (Adopt Me, Pet Simulator X, Bee Swarm) all use daily-rotating elements as the primary retention driver.
2. **NPC personality is wasted lift.** A single static merchant gives no atmospheric variation, no class-fit differentiation, no lore reveal opportunities.
3. **Asset/liability mechanic is invisible at the price layer.** BAB's signature differentiator (per `Bloom&Burgle_Spec.md` §8) is that critter species have *opposite* value to different classes. A coal_drake is a class-asset for a hexer (heat-loving) but a class-liability for a knight (the dragon torches the plot). Today both classes get the same Pawn Forge payout. The marketplace is the right surface to express this — make the knight's coal_drake worth *more* to NPC Bart (mech-trader who loves it) than the hexer's identical coal_drake (because the hexer should be growing, not selling, his asset).

The asset/liability arbitrage is **the moat**. No other Roblox sim has this dual-track mechanic.

## Approach

### NPC roster

Three personalities per [BAB-MARKETPLACE-HUB.md](BAB-MARKETPLACE-HUB.md) §"NPC merchants" — formalized here:

| NPC | Visual | Preference axis | Base × | Asset×Liability axis |
|---|---|---|---|---|
| **Brass Bart** (existing) | Gruff dwarf, brass apron, oil-stained | Mechanical / scrap-tagged | 1.2× | pays **liability premium**: when species is a liability for player class, +0.2× |
| **Hexerine "Stitches"** (new) | Eccentric witch, ragged stitches, glowing alembic | Sacred / mutated / alchemy-tagged | 1.0× base | pays **asset premium**: rewards class-aligned harvests, +0.3× when species is an asset for player class |
| **Sky Captain Verda** (new) | Cocky pilot, brass goggles, airship-cape | Winged species (drakes, wyverns, hummingbirds) | 1.3× base for winged only; 0.8× scoff price for non-winged | pays **liability premium for winged**: +0.4× when winged species is a liability for player class |

Each NPC has 5+ rotating dialogue lines stored in `MerchantPersonalities.luau`. Lines are picked round-robin per player visit (not random — predictability + recognition is part of personality reading).

### Daily rotation engine

Each NPC has a list of 4–8 "preferred species" within their preference axis. Once per UTC day, each NPC picks ONE as "today's special want" with a 2× multiplier on top of all other modifiers.

**Determinism is critical**: every server globally must agree on today's special so cross-server discoverability ("Friend on Discord said Hexerine is buying salamanders 5×!") works. Mechanism:

```luau
-- NPCRotation.server.luau
local function todaysSpecial(npcId: string): string
    local prefs = MerchantPersonalities.preferences(npcId)
    local utcDay = os.date("!*t", os.time()).yday  -- 1..366
    local seed = (utcDay * 2654435761 + npcId:byte(1) * 7919) % #prefs + 1
    return prefs[seed]
end
```

No MessagingService needed for rotation itself (deterministic). MessagingService is reserved for the cross-server broadcast tickets (see Defer).

### Pricing formula

Total payout per critter:

```
basePawnForge        = count × baseValue × class × CashMultiplier   -- existing formula
npcBase              = basePawnForge × NPC.basePremium               -- 1.0–1.3×
preferenceFit        = inPreferenceAxis(npc, species) and 1.0 or 0.8 -- non-fit penalty
arbitrageBonus       = npc.arbitrageProfile == "asset" and CritterAffinity.isAsset(class, species) and 0.3
                    or npc.arbitrageProfile == "liability" and CritterAffinity.isLiability(class, species) and 0.2
                    or 0
specialBonus         = (species == NPCRotation.todaysSpecial(npcId)) and 1.0 or 0  -- doubles on top
totalMultiplier      = NPC.basePremium × preferenceFit × (1 + arbitrageBonus + specialBonus)
totalPayout          = basePawnForge × min(totalMultiplier, 3.0)  -- cap to keep economy sane
```

Worked examples (knight class, all v1 species values):

| Scenario | Base PF | × | Why | Total |
|---|---|---|---|---|
| Knight sells cogwork_rat to Bart, today's special: rat | 100g | 1.2 × 1.0 × (1 + 0 + 1.0) = 2.4× | Bart's mech-trader, rat is mechanical (in-axis), but no liability premium for knights, special bonus 2× | 240g |
| Knight sells coal_drake to Bart, no special | 1000g | 1.2 × 1.0 × (1 + 0.2) = 1.44× | Bart loves mechanical (in-axis), liability premium fires for knight | 1440g |
| Knight sells coal_drake to Verda, today's special: coal_drake | 1000g | 1.3 × 1.0 × (1 + 0.4 + 1.0) = 3.12× → capped at 3.0× | Verda loves winged (in-axis), liability premium fires, special doubles, but cap | 3000g |
| Hexer sells coal_drake to Verda | 1000g | 1.3 × 1.0 × (1 + 0 + 0) = 1.3× | Hexer's asset; Verda has no asset-premium profile so no bonus, just base winged premium | 1300g |
| Knight sells fire_salamander to Hexerine, today's special: fire_salamander | 500g | 1.0 × 1.0 × (1 + 0.3 + 1.0) = 2.3× | Hexerine alchemy-axis (salamander qualifies), asset-premium would fire if it were an asset for knight (if not, bonus is 0), special × 2 | varies |

The cap at 3× ensures even a "perfect storm" combo can't break the cash economy. Pawn Forge floor remains at 1.0× so on-plot fast-sell stays the obvious lazy choice.

### UI hints (the legibility layer)

The arbitrage mechanic is only valuable if players *see* it. Per the BAB-MARKETPLACE-HUB ticket open question 6: "Asset/liability hint to the buyer."

In each NPC's buy menu, per-species row shows:

```
🐀 Cogwork Rat × 12          [⚠️ liability for you]   [✨ Bart's special today]
   500g base → 1200g (Bart pays you 2.4×: mechanical + liability + special)
   [Sell 1]  [Sell All]
```

- **Asset/liability badge**: pulled from `CritterAffinity` at render time. Tooltip explains: "Liability — this critter would damage your plot if it escaped. Selling is usually right."
- **Today's special banner** at the top of each stall: `"TODAY'S SPECIAL: 🐀 Cogwork Rat — 2.4×"`
- **Multiplier breakdown tooltip** on hover so players learn the system over time without needing a wiki.

### NPC stalls (visual)

Three brass-and-lamplight stalls in a semicircle in the Marketplace plaza, replacing the v1 single Bart stall:

- Bart at center (existing position)
- Hexerine to his left (cauldron + alembic visual)
- Verda to his right (small docked airship visual)

Each stall has its own SurfaceGui showing the NPC's portrait + today's special banner from across the plaza (legibility from a distance).

## Acceptance

- [ ] All 3 NPCs spawn in the Marketplace plaza on server boot, each with distinct visual identity.
- [ ] Each NPC has a working buy menu that lists species the player has, filtered/highlighted per the NPC's preference axis.
- [ ] Daily rotation works: `NPCRotation.todaysSpecial(npcId)` returns a deterministic value that changes at UTC midnight; same value across all servers globally.
- [ ] Pricing formula correctly applies base + preference fit + arbitrage bonus + special bonus, capped at 3.0×, with a unit test that exercises the worked examples above.
- [ ] Asset/liability badges render correctly in the buy menu per the player's class (`CritterAffinity.isAsset / isLiability`).
- [ ] Hover tooltip on the price shows the multiplier breakdown ("base 1.2× × liability 1.2× × special 2.0×").
- [ ] Sell event emits `Telemetry.track("marketplace_npc_sell", { npcId, species, class, count, multiplier, basePayout, totalPayout, isAsset, wasSpecial })` per ADR-3.
- [ ] Sell pipeline still gated by `RateLimiter.tryConsume(...)` per ADR-2 (anti-exploit; this is a currency-mutating handler).
- [ ] No regression on Pawn Forge (on-plot fast-sell still works at the legacy 1.0× formula).
- [ ] No banned materials (per material discipline CI gate).
- [ ] All 3 places (Hatchery, Marketplace, Corridors) build cleanly after the shared module addition.

## Open questions

1. **Where does `CritterAffinity.isAsset / isLiability` live today?** Per `Bloom&Burgle_Spec.md` §8 there's an affinity matrix but I haven't verified the module name. Need to grep `src/ReplicatedStorage/Modules/` for the existing affinity logic before deciding new vs extend.
2. **Cap at 3×** — does this leak into a per-class meta-arbitrage (knights farming coal_drakes specifically to dump on Verda)? Likely yes, and that's the *intended* behavior — class-driven economic specialization. Worth surfacing to the user before commit.
3. **Rotation reveal time.** Player sees "today's special" the moment they enter the Marketplace. Should there be a 5-second drumroll for hype? Defer.
4. **Dialogue rotation persistence.** Should each NPC remember which line they last said to a specific player (so they don't repeat) across sessions? Probably not — keep server-local state. Defer.
5. **First-launch atomicity.** When this PR ships, players who teleport to the Marketplace mid-session will see Brass Bart's old stall replaced. Acceptable since it's a v1→v2 jump; document in the deploy notes.

## Defer (separate tickets)

- **Auction mechanic** → [BAB-MARKETPLACE-LIVE-AUCTION.md](BAB-MARKETPLACE-LIVE-AUCTION.md)
- **NPC reputation grinding** → [BAB-MARKETPLACE-NPC-REPUTATION.md](BAB-MARKETPLACE-NPC-REPUTATION.md)
- **Cross-server "big sell" toasts** → [BAB-MARKETPLACE-CROSS-SERVER-TOASTS.md](BAB-MARKETPLACE-CROSS-SERVER-TOASTS.md)
- **Hall of Sales leaderboard** → [BAB-MARKETPLACE-HALL-OF-SALES.md](BAB-MARKETPLACE-HALL-OF-SALES.md)
- **Spectral merchant (limited-time)** → [BAB-MARKETPLACE-SPECTRAL-MERCHANT.md](BAB-MARKETPLACE-SPECTRAL-MERCHANT.md)
- **Player-to-player trade booths** → still in [BAB-MARKETPLACE-HUB.md](BAB-MARKETPLACE-HUB.md) Defer block (separate moderation/exploit problem).

## Log

- 2026-05-08 — Drafted from session strategy brainstorm. User confirmed top recommendations — engagement layer (rotation + reputation) before virality layer (auctions + spectral). This is the engagement-layer foundation.
