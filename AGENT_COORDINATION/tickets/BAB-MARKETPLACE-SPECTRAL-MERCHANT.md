# BAB-MARKETPLACE-SPECTRAL-MERCHANT: limited-time ghost merchant — "The Cogworks Wraith"

**Owner:** unassigned
**State:** inbox (design — capture only)
**Priority:** P2 (virality + brand-distinctiveness layer)

## Hook (one-line pitch)

A spectral steampunk merchant ("The Cogworks Wraith") appears at random server hours, stays for 5 minutes, pays 5× formula, and accepts only an exclusive currency (`Aether Shards`) that's earned by class-aligned harvests. Drives habit formation + "did you SEE them?!" social cascade.

## Why it matters

- **Habit formation** — spawn windows are unannounced, so players check in opportunistically, building a daily-visit reflex.
- **Brand distinctiveness** — steampunk fits ghost-merchant aesthetic perfectly, reinforces world identity in a way generic auction mechanics don't.
- **Counters whale economies.** Aether-Shards-only payout means cash whales can't buy the spectral inventory; only active class-aligned players can. Levels the playing field for skill/dedication vs spend.

## Sketch

- **Spawn:** random per server, ~1 in 4 hours (so most servers see them daily). MessagingService announces server-wide ("👻 The Cogworks Wraith has appeared at [Marketplace]!").
- **Stay:** 5 minutes, then dissolves with a particle effect.
- **Buys:** any species at 5× formula. Pays in Aether Shards (new currency).
- **Aether Shards uses:** unlock spectral cosmetics (ghostly pod skins, particle trails, Wraith-themed plot decorations). Cosmetics-only, no power.
- **Earns Aether Shards by:**
  - Harvesting an asset critter (the natural class-aligned action)
  - Selling to the Wraith (recursive — the more you sell, the more you can show off)

## Files touched (planned)

- new `src-marketplace/ServerScriptService/SpectralMerchant.server.luau`
- new `src/ReplicatedStorage/Modules/AetherShards.luau` (currency module)
- new `src-marketplace/StarterPlayerScripts/SpectralMerchantUI.client.luau`
- modify `src-marketplace/ServerScriptService/MarketplaceBoot.server.luau` to register the spawn timer
- new MessagingService topic: `bab-wraith-spawn-v1`
- new shared cosmetic-unlocks module + DataStore key for owned cosmetics

## Visual

Translucent figure (Transparency=0.6, Neon material), flickering BrandColors.AetherViolet, slow drift animation. Sold-to-her stalls dissipate with particle smoke when she leaves.

## Open questions

- **Pre-announce the spawn window?** Telegraphing it kills surprise but builds anticipation. Compromise: 30-second pre-spawn shimmer at the spawn point.
- **Aether Shards drop rate.** Need to tune so cosmetics feel earnable but not trivial. Defer to playtest.
- **First-time-seen tutorial.** When a player encounters the Wraith for the first time, brief pop-up explains the mechanic. Standard onboarding pattern.

## Log

- 2026-05-08 — Captured from strategy brainstorm. Brand-distinctive option vs the generic-auction option in BAB-MARKETPLACE-LIVE-AUCTION; recommended to ship one (not both) initially.
