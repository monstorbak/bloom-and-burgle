# BAB-004: Rebirth/Prestige system missing (spec-required)

**Owner:** G-Tard Lin
**State:** inbox
**Priority:** P1
**Files touched:** `src/ServerScriptService/LeaderstatsScript.server.luau`, new `src/ServerScriptService/RebirthHandler.server.luau`, new `src/ReplicatedStorage/RemoteEvents/RebirthRequest.model.json`, new `src/StarterPlayerScripts/RebirthUI.client.luau`

## Problem

Spec calls out:
> "Rebirth/Prestige System: Reset for permanent global multipliers (classic simulator staple)."

Currently `DataStore.DEFAULT_DATA.rebirths = 0` and `multiplier = 1` exist as fields, but no script consumes them. **No way to actually rebirth.** This kills the long-tail progression hook that whales and grinders chase.

## Approach

1. New `RebirthHandler.server.luau`:
   - On `RebirthRequest` RE from client, validate player has hit `cash >= REBIRTH_THRESHOLD(rebirths)`.
   - Threshold curve: `1_000 * 5^rebirths` (1k → 5k → 25k → 125k → ...).
   - Reset cash to 0, reset stash, increment `rebirths`, multiplier = `1 + 0.5 * rebirths`.
2. `PlantHandler` sell payout multiplied by `player:GetAttribute("CashMultiplier")` (or whatever LeaderstatsScript already exposes).
3. UI: a 🌟 button that shows "REBIRTH (cost: $X)" when affordable.
4. Display rebirth count next to player name in plot signage and leaderboards.

## Acceptance

- [ ] Hit threshold → button lights up
- [ ] Click → confirm modal → reset + multiplier increment
- [ ] Multiplier persists in DataStore
- [ ] Sell payout reflects multiplier

## Log

- 2026-05-06 — G-Tard filed during initial triage
