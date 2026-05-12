# Bloom & Burgle — Live-Service Features Design

**Date:** 2026-05-11
**Status:** Design doc. No code in this PR. Subsequent tickets will track
implementation against the priorities in §9.
**Reader:** the next 2 weeks of BAB roadmap work. Successor to (and
extension of) `Bloom&Burgle_Design_Critique_2026-05-10.md`.

---

## TL;DR

This doc designs five interlocking systems that the game needs to land
**before** a public-listing push — or it'll fail the new-player retention
test on day one.

1. **Seed AI characters** — bots that fill empty servers so new players
   land in a populated world. Ship first; nothing else helps if the world
   feels dead.
2. **Plot expansion gamepass** — tiered upsell (12 / 16 / 25 planters)
   timed to milestones. Highest-yield monetization touchpoint after the
   Tinkerer's Pass.
3. **Marketplace ambient NPCs** — wandering merchants + customer crowd.
   Cheap; makes the plaza feel like a market, not a stall lineup.
4. **Raid gameplay** — what actually happens when a Corridors visitor
   lands on your plot. Notifications, theft, damage, defenses,
   alliances.
5. **Engagement + virality playbook** — the standard Roblox toolkit
   adapted to BAB.

**Ship order (defended in §9):**
Seed AI → Plot expansion → Ambient NPCs → Raid v1 (steal-only) →
Alliances + Raid v2 (damage/fight) → Engagement systems.

---

## 1. Seed AI Characters

### Goal
The game has launched but our user base is small. A new player joining
an empty Hatchery server sees no other plots growing, no players in the
plaza, no activity at all → bounces in 30 seconds. We need an artificial
liveliness layer that disappears as real player density grows.

### Requirements

**Functional:**
- Each Hatchery server boots with N AI agents (N scales inverse to real
  player count: maybe 5 when real = 0, 0 when real ≥ 6).
- Each AI claims a plot, plants critters, harvests them, sells (visible
  in Hall of Sales), occasionally raids (visible to defenders).
- Some AI are merchants in the marketplace plaza (walking customers).
- AI has a stable personality — class affiliation, preferred critter,
  trade quirks. A new player who meets the same AI twice should
  recognize them.
- AI is **disclosed** as bots (Roblox TOS § "deceptive content").
  Standard: prefix display name with `🤖 ` or a class emoji. Players
  shouldn't believe they're playing against humans they aren't.

**Non-functional:**
- Cheap. AI must not 10× server CPU. Target: <100ms total Heartbeat
  cost across all AI agents.
- Doesn't pollute the cross-server `bab-presence-v1` MessagingService
  topic (AI presence is server-local; never shows up in real players'
  Friends panel).
- Doesn't pollute real DataStore keys. AI data uses a separate prefix
  (`ai_<agentId>` rather than `player_<userId>`).

### Industry examples

| Game | Pattern | Takeaway |
|---|---|---|
| **Adopt Me!** | Pre-populated trade plaza, NPC tutorial dialog, recent-trades ticker (some fake/aggregated) | Liveliness signal > literal player presence. Players don't fact-check who's "real". |
| **MeepCity** | Pre-decorated NPC houses visible from spawn before any real player loads in | The visible-environment hack: bots can be static set-dressing instead of full agents. |
| **Welcome to Bloxburg** | NPC visitors that show up at your house with dialogue, leave reviews | Asymmetric AI — they DO something, but the player is the protagonist. |
| **Vampire Hunters 3** | Bot fill in matches during low-pop times, disclosed in match summary | Disclosed bots are a UX accelerant, not a stigma. |
| **Pet Simulator 99** (BIG Games) | Heavy environmental NPCs + simulated leaderboards + recent-event tickers; the actual player count is enormous, but the simulation is dialed up | Even at scale, simulation matters. Plan for it from day one. |
| **Genshin Impact** | Solo overworld populated with NPCs always doing routines | Routine-driven NPCs feel alive even if you never talk to them. |
| **Animal Crossing** | NPC villagers with daily routines, mood, gifts, requests | The "they have lives" trick: they don't just react to you, they exist. |

### Recommended design

**Two-tier AI:**

#### Tier 1: Plot Agents (Hatchery)
- 3–6 AI per server when real player count < 6, fewer as real count climbs
- Each agent owns a plot in the existing 16-slot rotation (same `PlotManager`)
- Server-local — no DataStore round-trip; their plot resets when the server restarts
- Each agent has a `personality` (one of 5 archetypes, see below) which drives:
  - Class (Knight / Tinkerer / Sky Pirate / Alchemist / Hexer)
  - Preferred critter species
  - Raid frequency
  - Chat archetype ("greeter", "trader", "rival", "silent", "quester")
- AI plot growth uses the **same code path** as real players — they call into `Critter/PlantingFlow.luau`, `Critter/GrowLoop.server.luau`, etc., with an `IsAI = true` attribute. No parallel pipeline.

#### Tier 2: Ambient NPCs (Marketplace, Plaza)
- 8–15 wandering "customer" NPCs in the marketplace plaza
- 1 wandering humanoid for each merchant (Brass Bart paces behind his stall, etc.)
- Pure decoration — no Player object, no DataStore, no Plot
- See §3 for marketplace ambient design

#### AI Personality archetypes

| Archetype | Behavior | Class affinity | Encounter feel |
|---|---|---|---|
| **Greeter** | Approaches new players on spawn, says hello, points to plot | Tinkerer | "There's someone here who notices me" |
| **Trader** | Lingers at marketplace stalls, has critters they "want" | Alchemist | "Someone trades — maybe I can too?" |
| **Rival** | Maintains a competitive plot, occasionally raids the player | Sky Pirate | "Someone to beat" |
| **Silent** | Just grows their plot, no chat, no raid | Knight | "Background activity" |
| **Quester** | Drops mini-quests in chat ("first to harvest 10 Cogwork Rats this round wins") | Hexer | "Someone gives me a goal" |

3-of-5 archetype mix per server (rotate the 2 omitted ones each session).

#### Naming + disclosure

Format: `🤖 <archetype-prefix><number>`. Examples:
- `🤖 Coghand47` (Tinkerer Greeter)
- `🤖 Brass-Trader12` (Alchemist Trader)
- `🤖 Skyhawk09` (Sky Pirate Rival)

Each name persisted per (server-job, agent-slot) so the same AI agent
keeps its name through a server's lifetime. Different servers can recycle
agent numbers — collisions across servers are fine because AI is server-
local anyway.

**Disclosure:** the 🤖 prefix is sufficient per Roblox guidelines. Add a
one-time tooltip on first encounter: "🤖 marks AI players — they help
fill empty servers."

### Implementation sketch

```
src/ServerScriptService/
  AiAgents/
    AgentSpawner.server.luau      -- boot: spawn N agents based on real-player count
    AgentBrain.luau                -- per-agent state machine
    AgentPersonalities.luau        -- archetype table + name templates
    AgentPlotProxy.luau            -- shim that calls into existing PlantingFlow/HarvestFlow
    AgentChat.luau                 -- archetype-tagged chat lines

src/ReplicatedStorage/Modules/
  AiData.luau                      -- shared types: AgentId, Archetype, etc.
```

**Spawner heartbeat** (every 15s):
```lua
local realPlayers = #Players:GetPlayers()
local targetAi = math.max(0, 6 - realPlayers)
local currentAi = #agentRegistry
if currentAi < targetAi then
    spawnAgent()
elseif currentAi > targetAi + 1 then  -- +1 hysteresis to avoid flap
    despawnIdleAgent()
end
```

**AgentBrain state machine** (per-agent, runs in `task.spawn`):
- `idle` → `plant` → `wait_grow` → `harvest` → `sell` → `idle`
- Optional branches: `chat_with_nearby_player`, `travel_to_marketplace`, `raid_player`
- Branch probabilities driven by archetype config

**Visual representation:**
- Each agent's body is a regular Humanoid NPC with an `Animate` script.
- Class-specific accessory pack (Knight helmet, Tinkerer goggles, etc.)
- BillboardGui above head shows `🤖 Coghand47` with a colored badge for archetype.

### Trade-offs

| Decision | Pro | Con | Mitigation |
|---|---|---|---|
| Server-local AI (vs cross-server persistence) | Simple, cheap, no DataStore writes | AI plots vanish on server restart | Acceptable — players don't expect AI continuity. Spawn fresh AI each session feels normal. |
| AI uses existing PlantingFlow code (vs parallel pipeline) | Single source of truth — bugs found once, fixed once | Risk: AI behavior coupled to player flow's quirks | Worth it. The `IsAI = true` attribute lets us branch on the rare cases that need different handling (e.g. skip rate-limiter checks). |
| 🤖 prefix for disclosure | Clear, no UI cost | Slight friction ("aw they're not real") | Better than a TOS violation. Add a "this is intentional" tooltip on first encounter. |
| AI cap at 6 / server (not e.g. 12) | Cheap | Empty servers still feel light at 6 | 6 is enough for "plaza never empty + ~3 plots active at once". Tune later via telemetry. |

### Open questions
- Should AI raids count toward real players' `times_raided` telemetry? **Recommendation: yes**, so we can A/B test whether raid frequency drives retention.
- Should AI buy gamepasses? **No**. AI ignores Robux. (Reduces complexity.)
- Should AI appear on the Trophy Hall? **No** for v1. Pollutes the social proof. Real players only.

---

## 2. Plot Expansion Gamepass(es)

### Goal
Players hit the 9-pod ceiling within their first session and want more.
Monetize the wanting. Plot expansion is the **highest-utility purchase**
in the game — it directly accelerates the core loop.

### Current state
- Every plot has exactly 9 planter pods (3×3 grid).
- No expansion mechanism exists. Plot size is hardcoded in PlotManager.

### Industry examples

| Game | Pattern | Price band |
|---|---|---|
| **Build A Boat for Treasure** | "Bigger Plot" gamepass — 449 R | Single gamepass; doubles plot |
| **Bloxburg** | Premium upgrades unlock new plot tiers | Cumulative cost — encourages whales |
| **Pet Simulator 99** | "More Inventory Slots" gamepasses — 99 / 199 / 499 R | Tiered series — anchor + premium |
| **Adopt Me!** | VIP perks include house size bumps | Bundled with broader benefits, not standalone |

**Key takeaway:** ~~"one big expansion gamepass"~~ vs. **a series of tiered expansions**. Series wins:
- Lower barrier to first purchase (199 R is easier than 599 R)
- Whales spend more total (cumulative is higher than any single tier)
- Each tier creates a new milestone moment ("I unlocked the Master's Estate")

### Recommended design

Three tiered gamepasses, each granting an additional row of planters:

| Tier | Name | Adds | Total pods | Price | When the upsell fires |
|---|---|---|---|---|---|
| 1 | 🔧 **Workshop Annex** | +3 planters (3×4 grid) | 12 | 199 R | First time the player fills all 9 pods AND harvests at least once |
| 2 | ⚙️ **Tinkerer's Hall** | +4 planters (4×4 grid) | 16 | 399 R | Player has spent the Annex AND has > 50K cash lifetime |
| 3 | 👑 **Master's Estate** | +9 planters (5×5 grid) | 25 | 799 R | Player has spent both AND has 5+ Mythic hatches lifetime |

Total stack: 1397 R for the full unlock path. Comparable to other top
Roblox economy games' deepest gamepass stacks.

#### Why milestone-gated upsells

Don't show the SHOP button screaming "BUY MORE PODS" on minute one. Show
each tier's offer *only when the player has experienced the constraint
the tier solves*. From Pet Simulator's growth team's GDC talk: gated
upsells convert 3-5× better than always-on upsells in this genre.

**Trigger logic:**

```lua
-- pseudo-code, server-side
local function maybeShowExpansionToast(player)
    local pods = #player:GetPlot().planters
    local owned = TinkererPass.ownsExpansion(player, "annex")
    if pods == 9 and not owned and player:GetAttribute("PlantsHarvested") >= 1 then
        showToast(player, "Out of pods? 🔧 Workshop Annex available in the shop")
    end
    -- similar for tier 2 + 3
end
```

Cooldown: same toast shows max once per 10 minutes per session.

#### How expansion is added to a plot

- New planters spawn as additional rows behind the existing 3×3
- Each new pod has the same visual style as existing pods
- Class-themed variant (Knight iron, Tinkerer copper, etc — listed in
  Tier 3 of the design critique) applies to NEW pods too
- Players visiting your plot SEE the bigger plot → social proof for the
  upsell

#### Mechanics

- Each gamepass grants a permanent attribute: `PlotTier = 1 | 2 | 3`
- `PlotManager.server.luau` reads `PlotTier` on `PlayerAdded` and adds
  the appropriate row of planters
- Existing 9 pods keep their state; new pods spawn empty
- Idempotent — re-running on rejoin doesn't duplicate pods

### Trade-offs

| Decision | Pro | Con | Mitigation |
|---|---|---|---|
| 3 tiered gamepasses (vs 1 single expansion) | Higher total revenue from whales; lower first-purchase barrier | More UI complexity; 3 separate Roblox gamepass assets to create | Build all 3 gamepass IDs at once in `GamepassConfig.luau`; UI is one repeated component |
| Milestone-gated upsell (vs always-shown) | 3-5× conversion lift per Pet Sim data | Players may not discover the upsell exists if they never hit the milestone | Mitigated by SeedShop including an "Expand your plot" tab with all 3 tiers visible at all times |
| Permanent attribute (vs consumable expansion) | Simple, fair, no "did I lose my pods?" support tickets | No way to upsell expansion again | Acceptable. Re-monetization comes from rebirth-related cosmetic gamepasses (later). |

### Open questions
- Should expansion gamepasses be **purchasable in-game with cash** as a fallback for non-spenders? Pattern from Adopt Me: yes, but at a huge cash cost (e.g. 500K cash) that only whales-by-grinding ever reach. Recommendation: **not in v1** — keep the gamepass purchase clean.
- Should there be a 4th tier (e.g. 6×6 = 36 pods)? Recommendation: **defer until telemetry shows people hitting the 25-pod ceiling**. Don't over-monetize before there's a demonstrated ceiling.

---

## 3. Marketplace Ambient NPCs

### Goal
The marketplace plaza has 3 static merchants and otherwise feels like a
ghost town. Make it feel like a market — wandering customers, browsing
NPCs, merchants who pace their stalls.

### Current state
- 3 merchant NPCs (BrassBart, Hexerine, Verda) — all static Parts with
  Humanoid heads stuck on. They don't move.
- No customer NPCs at all.
- The recent `ClickDetector` fix made them mobile-tappable, but they're
  still cardboard cutouts visually.

### Industry examples

| Game | Pattern |
|---|---|
| **Adopt Me! nursery** | 6-8 NPC babies + 2 wandering nurses in animation routines |
| **MeepCity Plaza** | 10-15 wandering NPCs with random walk paths |
| **Welcome to Bloxburg town** | Ambient citizens with destinations (mall, gas station, etc.) |
| **Theme Park Tycoon 2** | Visitors with personality types (kid, adult, photographer) and emotion states |

### Recommended design

**Two categories of NPC for the Marketplace:**

#### A. Merchant pacing
- BrassBart, Hexerine, Verda each get a Humanoid + Animator
- Each paces a small zone behind their counter (10-stud radius)
- Idle animations: arm-cross, hand-wave, lean-on-counter
- ProximityPrompt and ClickDetector follow the merchant's body

#### B. Customer crowd
- 8–15 wandering NPCs in the plaza
- Each has a "browsing routine":
  - Walk to a random merchant's stall
  - Stand for 5-15s with a "thinking" emote
  - Walk to another stall
  - Occasionally leave plaza (despawn at edge) and a new one spawns
- Some have hover BillboardGui chatter: "Brass Bart's prices today? 1.4× — not bad" (social proof, makes pricing feel real)
- Customer NPCs have BAB class accessories (helmet/goggles/scarf) to fit
  the world's vibe

#### Personality fragments

| Customer type | Visual | Chatter examples |
|---|---|---|
| **Tourist** | Camera, sun hat | "Look at all the gears!" |
| **Trader** | Backpack, ledger | "I'll watch the rotation today, see what's cheap" |
| **Critter walker** | Has a small Brass Beetle or Cogwork Rat at heel | (no speech, just walks with critter) |
| **Engineer** | Goggles, oversized wrench | "I'd buy more Mech-Hounds if I had the cash" |

Animate these via Roblox's stock NPC animations + a custom walk speed.

### Implementation sketch

```
src-marketplace/ServerScriptService/
  AmbientCrowd.server.luau         -- spawns + manages customer NPCs
  MerchantAnimator.server.luau     -- adds pacing routine to BrassBart/Hexerine/Verda
  CustomerPersonalities.luau       -- customer type registry
```

**Pathfinding:**
- Use `PathfindingService:CreatePath()` for each customer's wander route
- Recompute path every time a customer reaches its destination
- Spawn waypoints in a `NavPoints` model under the plaza floor

**Population control:**
- Target customer count: `floor(realPlayers × 1.5) + 8` (more customers when more real players, so even busy plazas feel crowded)
- Cap at 15 to avoid pathfinding overhead

### Trade-offs

| Decision | Pro | Con | Mitigation |
|---|---|---|---|
| Per-server ambient crowd (vs persistent) | Simple, cheap, restarts on respawn | Customer crowd looks "different" each session | Acceptable — customers are background noise, not characters |
| 8-15 customers (not e.g. 50) | Light on pathfinding cost | Plaza may feel sparse at 8 with no real players | Tune via telemetry. Start at 10. |
| Wandering routines (vs scripted scene NPCs) | Reusable, feels organic | Less narrative, less memorable | NPCs don't need to be memorable; the merchants are. Customer crowd is set dressing. |

### Open questions
- Should customer NPCs occasionally interact with the player (e.g. "Sorry, where's the Hatchery again?")? **Stretch goal v2.** Adds delight but adds latency-sensitive chat code.
- Should they have buyable items? E.g. tap a Critter walker and you can buy their critter as a backup. **Probably not** — competes with the actual merchant system.

---

## 4. Raid Gameplay (Corridors → Plot)

### Goal
The Corridors place currently teleports a player to a stub. We need
actual raid gameplay: notifications, theft, defense, alliances. This is
the **PvP loop** that drives long-term engagement (per the Spec doc's
"viral engine" framing — though raiding is asymmetric, not direct combat).

### Industry examples

| Game | Raid pattern | Lessons |
|---|---|---|
| **Plants vs Zombies 2** | Asymmetric — defenders auto, attackers manual | One-side-active works fine; defender doesn't need to be present |
| **Hay Day / FarmVille** | "Visit a friend's farm" — limited steal mechanics, no damage | Pure-steal raid > damage raid for casual audience |
| **Clash of Clans** | Time-limited raid window + replay system | Replay is the social hook ("look what they did to my base!") |
| **Roblox: Lumber Tycoon 2** | Persistent theft + player ownership disputes | Persistent loot loss is engaging IF the loss isn't existential |
| **Roblox: Adopt Me trading** | NO raids; trading-only economy | Some games skip PvP entirely. Bigger audience but less retention hook. |
| **Roblox: Murder Mystery 2** | Direct PvP with role asymmetry | Real-time PvP is hard to balance on Roblox latency; we should NOT go this route. |

**Synthesis:** asynchronous, time-limited, steal-heavy, defender-optional
raids beat real-time PvP for an audience of 8-14-year-olds on mobile.
This is what Hay Day, Clash of Clans, and Plants vs Zombies optimized
toward. We follow that pattern.

### Recommended design

#### Raid flow at a glance

```
   ┌────────────────────┐         ┌────────────────────┐
   │  Raider (player A) │         │  Owner  (player B) │
   │  in Hatchery       │         │  in Hatchery       │
   └────────┬───────────┘         └─────────┬──────────┘
            │ walks Steal portal (-100g)    │
            ▼                                │ 1. Receives "🚨 RAID INCOMING" toast +
   ┌────────────────────┐                    │    map ping
   │  Corridors place   │                    │ 2. Optional: smash "DEFEND PLOT" button
   │  (raider browses   │                    │    → teleports back to own plot
   │  active plots)     │                    │
   └────────┬───────────┘                    │
            │ picks a target plot            │
            ▼                                │
   ┌────────────────────┐    teleport         │
   │  TARGET'S          │───────────────────►│ 3. Toast: "👹 PLAYER_A is raiding!
   │  Hatchery jobId    │                    │    45s remaining"
   │  (raider arrives)  │                    │
   └────────┬───────────┘                    │
            │ 60-second raid window          │
            │ - steal ripe critters          │
            │ - smash UNripe critters        │
            │ - (if defender present)        │
            │   fight/get-stunned mechanic   │
            ▼                                │
   ┌────────────────────┐                    │
   │  Raid ends         │                    │ 4. Summary toast:
   │  raider auto-tp    │                    │    "🛡 PLAYER_A stole 2 Brass Beetles"
   │  back to their     │                    │    "Mark as 🤝 ALLY / ⚔ ENEMY"
   │  Hatchery          │                    │
   └────────────────────┘                    │
                                              ▼
                              ┌─────────────────────────────┐
                              │  Both players get telemetry │
                              │  event: raid_completed      │
                              └─────────────────────────────┘
```

#### Notification timing — answer to "does owner get notified?"

**Yes, but tactically.** Two options:

- **Option A (recommended): notify on arrival.** Owner gets the toast
  when the raider physically arrives on their plot, not when they enter
  Corridors. This gives raiders ~10 seconds of stealth (Corridors browse
  → portal teleport latency) before defense kicks in.
- **Option B: notify on Corridors entry.** Maximum defender advantage.
  Discourages raiding because owner has 20+ seconds to teleport home.

Go with A. Hay Day-style "raid in progress" beats Clash of Clans-style
"raid imminent" for our pace. Raiders need to feel sneaky.

#### What the raider can do (on someone else's plot)

| Action | Mechanic | Cost to raider | Owner reaction |
|---|---|---|---|
| **Steal ripe critter** | Walk to ripe pod, hold E for 3s, critter goes to raider's stash | Free (raid cost was 100g entry) | Lose 1 critter from stash |
| **Smash unripe critter** | Walk to non-ripe pod, hold E for 5s, planter goes empty (critter destroyed) | Free | Plant progress lost |
| **(Defender present) Stun** | Equip combat tool (gamepass-gated), tap owner | Cooldown: 10s | Owner is move-locked for 5s |
| **(Defender present) Take dropped cash** | If owner harvests during raid, brief 2s window where cash drops as a pickup | Free | Lose ~5% of harvest payout |

**Per-raid hard limit:** raider can steal up to **3 critters** OR smash
up to **2 pods**, whichever comes first. Prevents wipe-out of a plot.

**Looted critters sell at 50% value** at any merchant. Disincentivizes
farming raids as primary income; raid is opportunistic, not strategic.

#### Defenses

| Defense | How it works | Acquisition |
|---|---|---|
| **Alarm Pylons** (from earlier critique) | Plot edges have brass pylons that emit a strobe + ping when raider crosses. Owner gets the toast slightly earlier (5s warning) | Built into all plots; free |
| **Aether Barriers** | Slow raider movement to 50% within plot for 15s | Gamepass: 🛡 **Plot Defender** — 299 R |
| **Class-specific autodefense** | Knights: 1 auto-stun turret. Tinkerers: 1 trap that snares for 3s. Sky Pirates: faster portal back to defend (3s vs 10s). Hexers: critters defend themselves (1-in-5 chance to "fight back" — costs raider 5s stun). Alchemists: critters become invulnerable for 30s post-harvest | Tied to class pick; free |
| **Trusted-list / Alliance** | Players marked as 🤝 Ally cannot raid. Mutual mark required | Free; managed via Friends panel extension |
| **Daily raid cap on defender** | A plot can only be raided once per defender per 1 hour | Built-in; free; can't be circumvented |

#### Alliances

This is the **social hook** that turns raids into a relationship system,
not pure griefing.

- Player marks another as "Ally" via Friends panel (extends existing UI)
- Mutual mark unlocks ally features:
  - Visit each other's plot anytime (already exists via visit-friend)
  - Cannot raid each other
  - Mutual +10% growth speed when both are online
  - Joint plot decoration (Tier 3 — stretch)
- Player marks another as "Enemy" via post-raid toast
  - Enemy can be raided once per 30 minutes (vs 1 hour default)
  - Enemy raids show in a "Recent Beef" feed for both sides
  - Resolves to neutral after 7 IRL days

#### Plot Owner notification (the question asked)

Three notification surfaces, all when raid arrives at the plot:

1. **Toast on screen** — full-width, red, "🚨 PIDDLYWINX is raiding your plot! 45s remaining" + ⏱ countdown
2. **Sound** — alarm pylon strobe + low warning tone (subtle, not jarring — accessibility)
3. **HUD Defend button** — pulses on the bottom nav for 10s after toast. Tapping teleports the owner home (with 2× walkspeed buff for 30s if returning to active defense)

If owner is offline:
- Push notification via Roblox's Game Invite system (opt-in, doesn't pollute notifications for users who decline)
- Email summary digest (gamepass-gated — "Plot Watch Daily Digest" — 99 R/month or 299 R one-time). Pattern from Clash of Clans' "village watch" upsell.

### Implementation sketch

```
src/ServerScriptService/Raid/
  RaidManager.server.luau           -- master state machine for ongoing raids
  RaidNotification.server.luau      -- toast + sound triggers
  RaidLootCalculator.luau           -- enforces 50% sell penalty on raided critters
  RaidDefenseTimers.luau            -- defender cooldown enforcement
  AllianceLedger.luau               -- ally/enemy state with DataStore persistence

src-corridors/ServerScriptService/
  CorridorsRaidPicker.server.luau   -- browse + teleport-to-target flow

src/ReplicatedStorage/RemoteEvents/
  RaidIncoming.model.json           -- server → defender's client
  RaidEnded.model.json              -- server → both clients
  MarkAlly.model.json               -- client → server
```

**State machine** in `RaidManager`:
- `none` → `raid_active` (timestamp, raider, target)
- After 60s: auto-transition to `raid_ended`
- Tracks: critters stolen, pods smashed, defender presence

**Data persistence:**
- Add to `BloomAndBurgleData_v1`: `raid_history[]` per player (last 20 raids — who attacked, when, what they stole)
- Add new DataStore: `BloomAndBurgleAlliances_v1` — per player a `{allies, enemies}` list

### Telemetry

Critical events to track from day one:

- `raid_started` (raider uid, target uid, raider class, target class)
- `raid_action_taken` (action="steal_critter"|"smash_pod"|"stun_defender", species)
- `raid_ended` (durationSec, crittersStolen, podsSmashed, defenderPresent, defenderArrivedAtSec)
- `alliance_marked` (uid, target, type="ally"|"enemy")

Lets us tune raid balance via data.

### Trade-offs

| Decision | Pro | Con | Mitigation |
|---|---|---|---|
| Steal-heavy, no real PvP | Easier to balance, mobile-friendly, fits casual audience | Reduces depth for hardcore players | Class-specific defenses add depth without real-time PvP |
| Notify on plot arrival (not Corridors entry) | Sneakier raid feel, more raider engagement | Defenders feel ambushed | Alarm Pylons are free → +5s warning for everyone |
| 50% sell penalty on raided critters | Discourages farming raids | Raids feel less rewarding economically | The point of raids is social drama + occasional gain, not primary income |
| Async raid (defender doesn't have to be present) | Works on mobile, low latency | Less satisfying when defender absent | Toast + replay system gives defender vicarious experience |

### Open questions
- Should raids cost the raider 100g to enter Corridors (existing fee)? **Yes** — keeps casual griefing in check.
- Should the raider's IDENTITY be visible to the defender (vs anonymous)? **Visible.** Anonymous raids reduce the alliance/enemy social loop.
- Should there be a "skip raid notification" gamepass? **NO** — that's pay-to-win. Hard line.
- Should defender's stolen critter be replaced from their stash automatically if they have spare? **No** — the loss is the engagement hook.

---

## 5. Engagement + Virality Playbook

A cataloged list of patterns that work in this genre, tagged with
**effort** (S/M/L) and **expected virality lift** (low/med/high).

### Daily mechanics (retention)

| Mechanic | Effort | Lift | Status |
|---|---|---|---|
| Daily reward chest | — | high | ✅ Shipped (Tier 2) |
| Daily quest (3 simple goals) | M | high | Not built |
| Login streak with escalating rewards | S | med | Partial — `plantsHarvested` exists; needs streak logic |
| Weekly themed challenges ("Mythic Week") | M | high | Not built — fits Phase 5 live-event template |

### Social mechanics (virality)

| Mechanic | Effort | Lift | Status |
|---|---|---|---|
| Trophy Hall leaderboards | — | high | ✅ Shipped (Phase 4) |
| Visit-a-Friend | — | med | ✅ Shipped (Phase 4) |
| Friend invite CTA in empty-state | — | high | ✅ Shipped (Tier 1) |
| "Your friend hatched a Mythic!" cross-server notification | M | high | Not built — uses MessagingService |
| Plot-of-the-day spotlight in main plaza | M | high | Not built |
| Mythic critter persistent display pedestal at plot | S | high | Listed in design critique Tier 3 — high-leverage |
| Share-rank screenshot button at Trophy Hall | S | very high | Listed in design critique — never built |

### Progression mechanics (depth)

| Mechanic | Effort | Lift | Status |
|---|---|---|---|
| Rebirth system (reset for permanent multiplier) | M | high | Not built |
| Class mastery cosmetics | M | med | Not built |
| Critter affinity unlocks | S | med | Not built — leverages existing affinity matrix |
| Plot decoration (Tier 3 from critique) | L | med | Not built |

### Viral content moments

| Mechanic | Effort | Lift | Status |
|---|---|---|---|
| Mythic ceremony (clip-worthy cinematic) | — | very high | ✅ Shipped (Phase 3) |
| Plot-of-week feature (random plot in plaza monument) | M | high | Not built |
| Tournament weekends (race-to-first-species, leaderboard event) | L | high | Not built — fits Phase 5 live-event template |
| Promo codes for season events | S | high | Not built |

### Roblox-platform-specific

| Mechanic | Effort | Lift | Status |
|---|---|---|---|
| Group membership bonus (join group → +10% growth) | S | very high | Not built — biggest organic-reach signal on Roblox |
| Player-to-player critter trading | L | very high | Not built — major depth feature |
| Showoff feature (Twitter/TikTok-friendly screenshot template) | M | high | Not built |
| Roblox Studio teaser shorts (developer-side, not in-game) | S | med | Marketing-not-engineering scope |

### Recommendation: highest-ROI engagement items not yet shipped

In priority order, items that are cheap and high-impact:

1. **Group membership bonus** — 1 day of work. Players join your Roblox group → server attribute flips → +10% growth. Standard onboarding flow → massive organic group growth.
2. **Promo codes** — 2 days of work. Twitter/TikTok-shareable. Use for launch + each milestone.
3. **Mythic display pedestal at plot** — 2 days. Persistent flex content visible during visits.
4. **Share-rank screenshot button at Trophy Hall** — 1 day. Direct viral conversion at the highest-emotion UX moment.
5. **Friend-hatched-Mythic notification** — 3 days (cross-server). Social FOMO → re-engagement.
6. **Daily quest system** — 4 days. Standard retention hook.
7. **Rebirth system** — 1-2 weeks. Endgame hook.

---

## 6. Cross-feature dependencies

Several of these features depend on others. Build order matters:

```
                            ┌────────────────────────┐
                            │  Telemetry (Phase 0)   │  ← already shipped
                            └───────────┬────────────┘
                                        │
              ┌─────────────────────────┼─────────────────────────┐
              ▼                         ▼                         ▼
   ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
   │  Seed AI         │      │  Plot Expansion  │      │  Ambient NPCs    │
   │  (Plot Agents)   │      │  Gamepasses      │      │  (Marketplace)   │
   └────────┬─────────┘      └────────┬─────────┘      └────────┬─────────┘
            │                          │                          │
            └────────────┬─────────────┘                          │
                         ▼                                        │
              ┌──────────────────┐                                │
              │  Raid v1         │                                │
              │  (steal-only)    │                                │
              └────────┬─────────┘                                │
                       │                                          │
                       ▼                                          │
              ┌──────────────────┐                                │
              │  Alliances +     │                                │
              │  Raid v2         │                                │
              │  (damage/fight)  │                                │
              └────────┬─────────┘                                │
                       │                                          │
                       └────────┬─────────────────────────────────┘
                                ▼
                     ┌──────────────────┐
                     │ Engagement +     │
                     │ Virality Layer   │
                     └──────────────────┘
```

Critical dependencies:
- **Raid needs Seed AI**: raids in an empty server feel pointless. AI agents are valid raid targets (and raiders).
- **Plot Expansion is independent** but creates content density that makes Raids more interesting (bigger plots = more loot).
- **Ambient NPCs are independent** of everything else.
- **Engagement layer** assumes Raid + AI + Expansion exist (e.g. "friend hatched a Mythic" presumes density of activity).

---

## 7. Scale estimation

If we reach **1,000 concurrent players** (the realistic 6-month goal):

- ~10 servers each with ~100 players (Roblox typical Hatchery cap)
- Seed AI overhead: 0–5 per server × 10 servers = 0–50 AI agents universe-wide. Negligible DataStore traffic since AI is server-local.
- Plot Expansion: 25-pod plots × 1000 plots = 25K planters. GrowLoop Heartbeat cost grows linearly. At 25K planters Roblox Heartbeat will start to strain — we'll need to chunked-iteration the loop (already a 2026 ADR backlog item).
- Raid system: <1 raid/sec universe-wide. MessagingService load trivial.
- DataStore: each player ~1 write/min from autosave + ~0.2 writes/min raid logs = ~1.2 writes/min/player. 1000 × 1.2 = 1200 writes/min vs. Roblox's 1000 writes/min/key limit. Each player has their own key → no contention.

Scaling is fine for v1. Revisit if we 10× to 10K concurrent.

---

## 8. Trade-off summary across all five features

The hard trade-offs that span multiple systems:

| Trade-off | Decision | Rationale |
|---|---|---|
| Disclose AI vs. hide it | **Disclose (🤖 prefix)** | TOS + trust. Players figure it out eventually anyway. |
| Real-time PvP raids vs. async | **Async** | Mobile-first, latency-tolerant, broader audience |
| Single big expansion vs. tiered | **Tiered (3 gamepasses)** | Higher total spend per Pet Sim data |
| Server-local AI vs. cross-server persistent | **Server-local** | Cheaper, simpler, AI doesn't need continuity |
| Ambient NPC narrative depth vs. set-dressing | **Set-dressing** | Memorable NPCs are merchants; crowd is wallpaper |
| Notify defender on plot arrival vs. Corridors entry | **Plot arrival** | Stealthier raid feel, more raider engagement |
| Raid loot at 100% vs. 50% sell penalty | **50%** | Discourages farming raids; preserves social-drama purpose |
| Visible raider identity vs. anonymous | **Visible** | Alliance/enemy system depends on it |

---

## 9. Recommended sequencing (the ship order)

Each block is 1–2 weeks of work. Total: ~10 weeks for the whole stack.

### Block 1 (Week 1–2): **Seed AI v1 — Plot Agents only**
- Spawner heartbeat + 3 archetypes (Greeter, Trader, Silent)
- AI grows plots using existing code path
- Disclosure (🤖 prefix)
- **Ships before:** anything else. Most leveraged because every other
  feature degrades on empty servers.

### Block 2 (Week 3): **Plot Expansion (3 gamepasses)**
- Create 3 Roblox gamepass assets manually
- Wire to `GamepassConfig.luau` (same pattern as Tinkerer's Pass)
- Milestone-gated upsell toast logic
- New planter spawn logic in `PlotManager.server.luau`
- **Why now:** revenue-impacting, independent, fastest ROI.

### Block 3 (Week 4): **Ambient NPCs (Marketplace)**
- Merchant pacing animation
- Customer crowd via PathfindingService
- 4 customer archetype variants
- **Why now:** independent + low-risk + visible improvement to plaza.

### Block 4 (Week 5–6): **Raid v1 — Steal-only**
- Corridors raid picker UI (browse active plots)
- Plot-arrival notification + defend HUD
- Steal-critter mechanic (3 max per raid, 50% sell penalty)
- Daily raid cap (1/hour per target)
- Alarm Pylons (default defense)
- **Why now:** AI is in place → raids on AI plots work even with low real-player density. Test the raid loop with synthetic targets first.

### Block 5 (Week 7–8): **Alliances + Raid v2**
- Smash unripe critters (damage mechanic)
- Combat tools (gamepass-gated stun)
- Class-specific defenses
- Alliance ledger + Ally/Enemy marking
- Aether Barriers gamepass
- **Why now:** depth layer on top of working raid v1.

### Block 6 (Week 9–10): **Engagement layer**
In priority order from §5:
- Group membership bonus
- Promo codes
- Mythic display pedestal at plot
- Share-rank screenshot button
- Friend-hatched-Mythic cross-server notification
- Daily quest system (start)
- **Why last:** assumes density. Engagement features compound on top of
  populated worlds + raid drama + plot depth.

---

## 10. What to revisit as the system grows

**Don't optimize for these now. Re-audit at 1K, 10K, 100K concurrent.**

- **Seed AI moving to cross-server persistent** if we want AI characters
  with continuity ("you fought 🤖 Skyhawk09 last week — they want revenge")
- **Plot Expansion tier 4 (6×6 grid)** if telemetry shows 25-pod ceiling friction
- **Real-time PvP combat** if/when audience skews older. NOT before then.
- **Trade system** for player-to-player critter swaps. Big feature, defer
  until raids prove out the social loop.
- **Cross-place merchant economy** (NPCs that trade with each other)
- **Rebirth / prestige system** for endgame
- **Cosmetic gamepass economy** beyond Tinkerer's Pass + Plot Expansion

---

## Appendix A: Open design questions for follow-up

These need user input before implementation locks in:

1. **AI disclosure:** is 🤖 prefix acceptable, or do we want a softer
   tell (e.g. NPCs with `_NPC` suffix the player learns to recognize)?
2. **Raid loot %:** 50% feels right for v1 — confirm.
3. **Combat tool gamepass:** is PvP-tool-as-gamepass acceptable (could
   feel pay-to-win)? Alternative: tools earned via grinding.
4. **Group bonus magnitude:** +10% growth is standard. Higher (+25%)
   would convert harder but reduces in-game upsell incentive.
5. **Plot Expansion tier pricing:** 199/399/799 R. Confirm or tune.

---

## Maintenance

This doc gets updated when:
- A block in §9 is shipped → mark with ✅ in the title; archive details
- A trade-off in §8 is revisited or revoked → strike-through + note
- Telemetry data invalidates an assumption (e.g. raid frequency is way
  off prediction) → add a "Reality check" subsection per affected feature

Successor docs should reference this one rather than restating.
