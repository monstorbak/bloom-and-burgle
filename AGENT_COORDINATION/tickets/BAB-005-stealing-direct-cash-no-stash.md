# BAB-005: StealHandler awards direct cash with 50% tax — should drop in stash

**Owner:** G-Tard Lin
**State:** inbox
**Priority:** P1
**Files touched:** `src/ServerScriptService/StealHandler.server.luau`

## Problem

Per `StealHandler.luau`:
```lua
local STEAL_TAX = 0.5
local payout = math.floor(species.baseValue * mutMult * STEAL_TAX)
-- Pay thief
local cash = tls:FindFirstChild("Cash") :: IntValue?
if cash then cash.Value = cash.Value + payout end
```

This dumps cash directly. Issues:
1. Inconsistent with BAB-003 (harvest goes to stash, theft goes to cash) — players will be confused.
2. Removes the "I stole a Mythic Glowing Sunbloom!" flex moment — they get nothing visual to show, just a cash bump.
3. No mutation diversity in the thief's stash → less trading economy depth.

## Approach

1. Remove the 50% tax cash payout.
2. Insert stolen plant into thief's stash with `mutationId` preserved.
3. Display steal notification with the *plant* details ("💰 stole a Glowing Sunbloom!"), not just $X.
4. **Anti-arbitrage:** when stolen plants are sold, multiply by 0.5 at sell time → spec's STEAL_TAX is honored without breaking the stash model.

## Acceptance

- [ ] Steal a plant → thief's stash gains 1× plant with correct mutation
- [ ] Sell stolen plant → 50% of normal sell value
- [ ] Notification shows plant name + emoji, not just $X
- [ ] Victim's notification still fires

## Log

- 2026-05-06 — G-Tard filed during initial triage
