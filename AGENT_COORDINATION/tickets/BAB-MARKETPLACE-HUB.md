# BAB-MARKETPLACE-HUB: Sell portal → separate Place ID marketplace + P2P trade

**Owner:** unassigned
**State:** inbox (design)
**Priority:** P1 (post-P1-arch — direction shift)
**Files touched (planned):**

Hatchery side (existing place):
- new `src/ServerScriptService/MarketplacePortal.server.luau` (TeleportService entry)
- new `src/Workspace/Cogworks/MarketplacePortal.model.json` (visible portal)
- modify `src/ServerScriptService/Critter/EconomyPad.luau` (Pawn Forge stays as fast-sell-to-merchant; opt-out from portal-required-for-sell)

Marketplace place (new universe place ID):
- new `src/Workspace/MarketplaceHub/` (entire scene)
- new `src/ServerScriptService/MarketplaceServer/` folder:
    - `NPCMerchant.server.luau` (3 named merchant NPCs with rotating
      buy lists)
    - `TradeWindowHandler.server.luau` (P2P 2-pane trade)
    - `MarketplacePersistence.server.luau` (read inventory from BAB
      DataStore on entry; write back on exit)
    - `ReturnPortalWatcher.server.luau` (detects player walking through
      return portal → TeleportService back to Hatchery place)
- new `src/StarterPlayerScripts/MarketplaceUI/` (the trade UI, NPC
  conversation UI, marketplace map)
- new shared module in ReplicatedStorage so both places agree on the
  inventory schema

Roblox-side:
- new published Roblox Place inside the existing universe (not a new
  universe — shares DataStore + PlaceID is just another place under the
  game). Required for `TeleportService:TeleportAsync(placeId, ...)`.
- a new `default-marketplace.project.json` Rojo project for the
  marketplace place's tree.

## Problem

Today the only way to monetize a critter is the **Pawn Forge** (sell pad
on the player's plot). Players sell to a faceless merchant at a fixed
formula: `count × baseValue × class-aware-multiplier × CashMultiplier`.
The fixed-formula nature has two consequences:

1. **No emergent prices.** A coal_drake is worth the same to every
   player, so there's no asset/liability arbitrage opportunity. A knight
   who hatched a coal_drake (liability) gets the same payout selling
   it as a sky_pirate would (asset). The pirate would happily pay
   *more* than the formula to acquire it; the knight's only option is
   the formula.
2. **No social/destination commerce.** Selling is a one-tap private
   experience on the player's own plot. There's no player-to-player
   visibility, no merchant personalities, no haggle moments — none of
   the social-flexing virality that the §2.1 Cogworks is supposed to
   enable.

The fix the user described: a **physical Sell portal** on the Hatchery
that teleports the player into a **separate Roblox place** — a
Marketplace Hub — where:
- 3 named NPC merchants offer fixed buy-prices (the floor — same as
  Pawn Forge today, just relocated for atmosphere).
- Other players are visible. Player-to-player trade UIs let pirate-A
  buy coal_drakes from knight-B at whatever price they negotiate.
- A return portal sends the player back to the Hatchery place.

Reference: existing **BAB-008-trading-economy** ticket already filed
P2P trading as a P1. This ticket supersedes it (P2P trade is now part
of the Marketplace, not on the player's plot).

## Approach

### Architecture: separate Place ID, shared DataStore

> User decision (2026-05-08): **Heavier lift — separate Place ID.**

Roblox `TeleportService:TeleportAsync(placeId, players, options)` is the
canonical hub-pattern API. Both places live under the same Universe (so
they share `DataStoreService` keys: `BloomAndBurgleData_v1`,
`BloomAndBurgle_Receipts_v1`, etc — see `AGENTS.md` "Don't break"
section).

```
Universe: BAB
  ├── Place A: "Bloom & Burgle (Hatchery)"   -- existing place ID 93948369125480
  └── Place B: "Bloom & Burgle (Marketplace)"  -- NEW place ID, to be allocated
```

Both places read from the same DataStore. Writes are append-only-ish
(transaction ledger per [P2 #11 in eval](Bloom%26Burgle_Architecture_Eval.md)) so cross-place contention
on the same key is avoidable.

### Sell-portal entry flow

1. Player walks onto a brass-and-steam **portal pad** in the Cogworks
   (visible from the public hub — see §2.1 of Design Spec).
2. Server-side `MarketplacePortal.server.luau` validates: player has
   non-zero stash inventory OR opts in to "browsing" (no inventory
   needed for browsing). Otherwise toast "Bring something to sell."
3. `Persistence.snapshot` runs (existing; just to flush state to
   DataStore so the marketplace place reads fresh data).
4. `TeleportService:TeleportAsync(MARKETPLACE_PLACE_ID, {player},
   teleportOptions)` with `setTeleportData({fromPlot = slotIndex,
   carriedClass = player:GetAttribute("Class")})` so the marketplace
   server has fast-path identity.

### Inside the Marketplace

#### Scene
A market plaza, brass and lamplight, ~120×120 studs:

- Center: a fountain of slowly-pouring brass coins (the destination
  fantasy).
- North: 3 NPC merchant stalls (steamcloak named characters; designed
  per §1 Visual Identity).
- East/West: 4 player-trade booths — physical 2-seat tables where
  players can sit opposite each other and a TradeUI auto-attaches.
- South: the **return portal** (mirror of the Cogworks side).

#### NPC merchants
Three personalities, each with a rotating preference (changes daily via
live ops per §13):

| NPC | Personality | Buys at premium | Buys at discount |
|---|---|---|---|
| **Hexerine "Stitches"** (alchemist) | Eccentric witch | Sacred-tagged, mutated criters | Mythic combat critters (she "doesn't fight") |
| **Brass Bart** (mech-trader) | Gruff dwarf-coded | Mythic combat critters, scrap drakes | Sacred (he scoffs) |
| **Sky Captain Verda** (sky pirate) | Cocky pilot | Winged species (drakes, wyverns, hummingbirds) | quad/multi (she can't load them) |

Each merchant has a 5-line rotating dialogue + a 4-button buy menu
(filtered to their preferences). Their offers are 1.0×–1.4× the Pawn
Forge formula depending on preference fit (so a knight selling a
coal_drake to Sky Captain Verda gets 1.4× the Pawn Forge payout — an
arbitrage win for the knight).

NPC merchant offers cap at **2× Pawn Forge** to keep player-to-player
trade still attractive for the rare cases.

#### Player-to-player trade

A physical-table interaction. Players sit opposite each other in a
2-seat booth; a Fusion-built TradeUI mounts:

- Left and right pane: each player's stash, drag-to-add to "offer" tray.
- Cash slot on each side (in addition to critters).
- Each side must hit "Lock" twice (anti-misclick per
  BAB-008-trading-economy lessons).
- 3-second hold-to-confirm on the final acceptance to defeat trade-scam
  swap-out attacks.
- Both players' inventory deltas + the agreed-upon cash flow logged
  to a new DataStore key `BloomAndBurgle_Trades_v1` for moderation.

The killer feature (asset/liability arbitrage) is realized here:

- Knight has a coal_drake (liability for him): Pawn Forge would pay
  ~1000g. Brass Bart at the marketplace offers ~1100g. **Sky-pirate
  player Pat is online, browsing, and pays him 2500g** because the
  coal_drake is a class-asset for Pat (per §8 affinity matrix).
- Both walk away winners. The arbitrage *is* the social-economic loop.

#### Marketplace persistence

Inventory is read from the shared DataStore on entry. Trades commit
through `MarketplacePersistence.server.luau` which uses
`UpdateAsync` for atomic inventory swaps (anti-dupe). On exit, fresh
state is written to the same DataStore key the Hatchery place reads.

Race-condition mitigation: a player can only be in **one** place per
universe at a time (Roblox-enforced). So when Hatchery-Anna teleports
to Marketplace, her Hatchery server snapshots her data and her
Hatchery presence ends. No two-server-writes-to-same-key window.

### Return portal

Walking through the south portal:
1. Server snapshots inventory (now reflecting trades).
2. `TeleportService:TeleportAsync(HATCHERY_PLACE_ID, {player}, opts)`
   with `setTeleportData({returnFromMarketplace = true, lastSlot =
   N})` so the Hatchery's `LeaderstatsScript` can shortcut the slot
   re-allocation and respawn the player at their plot.

If the player disconnects from the marketplace mid-trip (rare), Roblox
re-spawns them in the universe's start place (Hatchery) on next login.
DataStore state is consistent because trades are atomic.

## Acceptance

- [ ] Sell portal exists in Cogworks, visible from spawn, with a brass
  archway + steam particles.
- [ ] Walking through teleports the player to the marketplace place
  (Roblox-internal — a Studio publish must happen first to allocate
  the placeId; this is a one-time setup task per `AGENTS.md` Mac flow).
- [ ] Marketplace scene loads: fountain, 3 NPC stalls, 4 player tables,
  return portal.
- [ ] At least one NPC merchant has a working buy menu that matches a
  player's stash and pays out via the standard Cash IntValue flow.
- [ ] Two players can sit at a player-trade booth, swap one critter +
  some cash, and both walk away with the trade reflected in their
  stash + cash. Both players' DataStore writes are atomic.
- [ ] Return portal teleports back to the player's Hatchery plot, not
  the spawn ring. Inventory state matches what they walked away from
  the marketplace with.
- [ ] Trade log persists in `BloomAndBurgle_Trades_v1` with both UIDs,
  inventory deltas, cash flow, and timestamp.
- [ ] Anti-dupe: hammering the trade-confirm button or
  disconnecting-mid-trade does not duplicate inventory.
- [ ] On-plot Pawn Forge still works for the no-portal fast-sell path
  (so players don't HAVE to teleport — the marketplace is the
  destination commerce, not the only commerce).

## Open questions

1. **Will the marketplace place support 30+ players?** Default Roblox
  per-place CCU is 50; with 4 trade booths + browsing space this seems
  fine. Live ops may need to scale or shard.
2. **NPC merchant inventory** — do the merchants ever sell items, or
  are they buy-only? Proposed: buy-only at launch. Gives players a
  reason to enter without tempting them to spend cash on impulse-buys
  (savings get banked toward upgrades per §10).
3. **How does the return portal handle a teleport failure** (Roblox is
  unreliable here historically)? Need a retry + an error toast.
  Standard `TeleportService` patterns apply.
4. **DataStore quota.** Each marketplace round-trip is 2× UpdateAsync
  (read on entry, write on exit) plus the trade-commit writes. At
  heavy use we'll burn through the per-key 1/min throttle. Mitigation:
  batch entry-snapshot with a write-back-only-if-changed.
5. **First-launch placeId allocation.** The marketplace place must be
  created in Roblox Studio (manual step). Add a runbook entry to
  `AGENTS.md` and document the placeId override pattern (e.g., a
  `Workspace.Marketplace.PlaceID` attribute, like the
  `BB_GAMEPASS_*` overrides per `AGENTS.md` "Don't break").
6. **Asset/liability hint to the buyer.** When sky-pirate-Pat browses
  knight-Anna's offered critters, do we surface "✨ this is an asset
  for you, will likely sell well" inline? Yes — read from existing
  `CritterData.affinityFor` and overlay a badge. This is what makes
  the arbitrage loop legible.

## Defer

- Auction-house / buy-now-listing UI — start with synchronous
  face-to-face trades.
- Cross-shard merchant inventory (live ops daily-rotation can be
  driven from `MessagingService:SubscribeAsync` per
  P2 #12 in eval).
- Cross-place chat (let it happen via Roblox's built-in TextChatService
  for now).

## Supersedes

- `BAB-008-trading-economy.md` — that ticket's P2P trading is now
  scoped inside this marketplace. Close BAB-008 with a pointer.

## Log

- 2026-05-08 — User direction shift; Claude drafted ticket.
