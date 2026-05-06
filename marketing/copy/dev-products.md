# Bloom & Burgle — Developer Products (Consumables)

> Create these in create.roblox.com → Monetization → Developer Products.
> Repeatable purchases — these drive 30-40% of total revenue at scale.
> Each one gets handled in `src/ServerScriptService/DevProductHandler.server.luau` (TODO bead bab-???).

---

## 🌱 1. Insta-Grow

**Price:** 49 Robux
**Description:** Skip the wait — instantly ripen ALL your planted plants right now. Best when used after planting Mythic seeds.

---

## 🌈 2. Mutation Booster (15 min)

**Price:** 99 Robux
**Description:** 5x mutation chance on every plant grown for the next 15 minutes. Stack with Mythic Hunter for an INSANE 50x mutation rate.

---

## 💸 3. Big Bucks Bag

**Price:** 199 Robux
**Description:** Instant 50,000 Bloom Bucks delivered straight to your wallet. Skip the early grind — start with a real garden.

---

## 🚪 4. Jail Escape Token

**Price:** 79 Robux
**Description:** Caught stealing? Skip the 10-minute jail sentence INSTANTLY. Get back to thieving immediately. The most-bought item in stealing tycoons.

---

## 🌟 5. Premium Seed Pack (5x)

**Price:** 149 Robux
**Description:** 5 random RARE seeds (no Commons). Guaranteed at least one Epic. Perfect for filling out your collection.

---

## ☘️ 6. Lucky Charm (1 hour)

**Price:** 249 Robux
**Description:** 8x luck for ALL drops, mutations, and rare events for 1 full hour. THE pre-event purchase.

---

## 🏠 7. Extra Plot Slot

**Price:** 499 Robux
**Description:** Permanently unlock a 2nd garden plot at a different location in town. Twice the gardens, twice the income, twice the targets for thieves.

---

## Notes on consumable design

- **Jail Escape Token** is the killer SKU here — it's TIED to the stealing mechanic and creates 10x more sales than passive boosters because **it solves an immediate frustration**. Steal a Brainrot makes 70%+ of revenue from this exact mechanic.
- Trigger pop-up sales:
  - "You just got jailed! Skip for 79 Robux?" → instant 80%+ click rate
  - "You found a Rare seed! Boost mutation chance for 99 Robux to make it Mythic?" → 30% click rate
- Always offer a **bundle**: "Buy 5 Insta-Grows for 199 Robux" (saves 46 Robux — anchors value, lifts AOV).

---

## Implementation TODO (filed as bead bab-???)

```lua
-- src/ServerScriptService/DevProductHandler.server.luau
-- MarketplaceService.ProcessReceipt = function(info) ... end
-- Switch on info.ProductId, apply effect, return Enum.ProductPurchaseDecision.PurchaseGranted
```
