# BAB-MARKETPLACE-CROSS-SERVER-TOASTS: server-spanning broadcast for big sells

**Owner:** unassigned
**State:** inbox (design — capture only)
**Priority:** P2 (virality, low-risk, low-effort)

## Hook (one-line pitch)

When a player completes a "notable" sell (above a configurable threshold or with rare modifiers — asset/liability arbitrage, today's special × NPC max, mythic species), a toast broadcasts globally across all BAB servers via MessagingService: *"piddlywinx just sold a Coal-Drake-as-Liability to Brass Bart for 47K!"*.

## Why it matters

- **Free social proof** — players see other players' big moments without needing to be in the same server.
- **Aspiration loop** — "I want to do that someday." Drives skill-building and class-specialization.
- **Cheapest virality lever in the brainstorm** — leverages existing infrastructure (MessagingService, sell pipeline, ToastService). Probably 1-2 days of dev.

## Sketch

- **Threshold logic** in `MarketplacePersistence.server.luau` (or wherever the sell finalizes): if `totalPayout >= NOTABLE_THRESHOLD` or `multiplier >= 2.5×`, post a `MessagingService:PublishAsync` to topic `bab-notable-sells-v1`.
- **Subscriber** in every place's boot routine: subscribe to the topic, render the toast via the standard `ToastService`.
- **Rate limit** — at most 1 broadcast per player per 60 seconds (anti-spam) and at most 1 broadcast per server per 5 seconds (anti-flood).
- **Filter** — players can opt out via a setting (off by default; most players will leave it on for the dopamine).

## Files touched (planned)

- modify wherever sells finalize (likely `src-marketplace/ServerScriptService/NPCMerchants.server.luau` once it exists, plus `src/ServerScriptService/Critter/EconomyPad.luau` for Pawn Forge sells if we extend to those)
- new `src/ReplicatedStorage/Modules/NotableSell.luau` (threshold logic + MessagingService wrapper)
- modify all 3 places' boot scripts to subscribe to `bab-notable-sells-v1`
- ToastService should already render text toasts (verify before designing UI)

## Open questions

- **Threshold tuning.** Should auto-scale with the global cash economy (e.g., top 1% of recent sells) instead of fixed gold value? Defer to data-tuning post-launch.
- **PII / impersonation.** Broadcasting display names is fine (Roblox already shows them); no DOB/email surface.
- **Frequency cap globally.** If 100 players in 100 servers all hit the threshold simultaneously, MessagingService will throttle. Aggregator server pattern? Defer.

## Log

- 2026-05-08 — Captured from strategy brainstorm. Lowest effort, high value — likely a fast follow-up after BAB-MARKETPLACE-NPC-ROTATION.
