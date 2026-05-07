# BAB-009: Pets system entirely missing (spec calls them out for stealing + monetization)

**Owner:** G-Tard Lin
**State:** inbox
**Priority:** P1 (heavy retention + monetization driver)
**Files touched:** new `src/ServerScriptService/PetHandler.server.luau`, new `src/ReplicatedStorage/Modules/PetData.luau`, new `src/StarterPlayerScripts/PetUI.client.luau`

## Problem

Spec calls pets out repeatedly:
> "Pets/guards can raid neighbors."
> "Plot expansion → tool upgrades → pet collection → mutation hunting."
> "Exclusive Pet Line (stealing-specialized or ultra-rare mutations)" → gamepass tier.

No pet system exists. **This is the second-highest monetization driver after gamepasses.** Every Roblox top-earner has pets (Adopt Me made an empire on it).

## Approach (v0.3 scope)

1. `PetData.luau` ModuleScript: catalog of ~12 pets across rarities (Common → Mythic), each with:
   - `id`, `name`, `emoji`, `rarity`, `passive` (e.g., +5% grow speed, +1 plant per harvest)
   - Visual: a basic mesh or model placeholder (use `generate_mesh` from Studio MCP for AI-gen art)
2. Egg system: buy eggs from a kiosk near spawn, hatch animation, RNG drop.
3. Following pet: pet model orbits player.
4. Equip system: 1 active pet at start, 3 with VIP gamepass.
5. Persistence in DataStore (`pets`, `equippedPet` fields).

## Acceptance

- [ ] Player can buy egg → hatch → equip → pet visually follows them
- [ ] Pet passive applies (e.g., grow speed visibly faster on planters)
- [ ] Pets persist across sessions
- [ ] At least one Mythic pet exists for flex / rare-drop excitement

## Monetization tie-in (separate tickets)

- `EXCLUSIVE_PET_LINE` gamepass — guarantees first hatch is Rare+
- Devproduct: `EGG_BUNDLE_5` (5 eggs at discount)
- Devproduct: `MYTHIC_LUCK_BOOST` (10x rare-pet odds for 30 min)

## Log

- 2026-05-06 — G-Tard filed during initial triage
