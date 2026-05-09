# BAB-MARKETPLACE-NPC-REPUTATION: per-NPC reputation, unlocks, and lore reveals

**Owner:** unassigned
**State:** inbox (design — capture only; ship after BAB-MARKETPLACE-NPC-ROTATION lands)
**Priority:** P2 (engagement layer; depth beyond rotating prefs)
**Extends:** [BAB-MARKETPLACE-NPC-ROTATION.md](BAB-MARKETPLACE-NPC-ROTATION.md)

## Hook (one-line pitch)

Selling to an NPC builds *standing* with that NPC; high standing unlocks bigger orders, exclusive cosmetics, dialogue/lore reveals, and class-themed pod skins.

## Why it matters

- **Progression beyond cash.** Cash is fungible and inflates over time. NPC standing is unique to *who you are* — gives the marketplace a non-cash progression vector that doesn't deflate.
- **Drives class-loyalty playstyles.** A Hexer who specializes in selling to Hexerine builds her standing fast → unlocks alchemy-themed plot cosmetics → reinforces class identity.
- **Lore vehicle.** Each rep tier reveals a chunk of NPC backstory (Stitches's body-mod history, Verda's airship-fleet wars, Bart's exile from his clan). Players read the world through who they sell to.

## Sketch

- **Reputation per (player, NPC)** stored in DataStore key `BloomAndBurgle_Reputation_v1`.
- Per-sell increment proportional to total sale value with NPC.
- 5 tiers per NPC (Stranger → Acquaintance → Regular → Trusted → Patron).
- Each tier unlocks: 1 lore dialogue line + 1 cosmetic (pod skin, hat, plot decoration) + 1 mechanical perk (e.g., +5% prices, see daily special 1 hour early, etc).
- UI surface: per-NPC stall has a small "rep meter" near the buy menu.

## Files touched (planned)

- new `src-marketplace/ServerScriptService/Reputation.server.luau`
- new shared `src/ReplicatedStorage/Modules/ReputationTiers.luau`
- modify `src-marketplace/ServerScriptService/NPCMerchants.server.luau` (rep gain hooks)
- modify `src-marketplace/StarterPlayerScripts/MarketplaceUI.client.luau` (rep meter UI)

## Open questions

- Reputation decay or permanent? Permanent for v1 — easier to communicate.
- Cross-character reputation? No — class-tied. Hexer-Anna and Knight-Anna have separate reps.
- Anti-grind? Cap rep gain per UTC day to prevent infinite-stash dump farming the meter.

## Log

- 2026-05-08 — Captured from strategy brainstorm.
