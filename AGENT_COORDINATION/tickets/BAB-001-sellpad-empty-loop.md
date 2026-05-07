# BAB-001: SellPad payout never fires (loop runs once at server start before any plots exist)

**Owner:** G-Tard (Mac) — fixed pre-coord in launch-kit hotfix
**State:** done
**Priority:** P0
**Files touched:** `src/ServerScriptService/PlantHandler.server.luau` (or wherever the SellPad loop lives)

## Problem

`LAUNCH.md` flags this explicitly: the `for _, sellPad in CollectionService:GetTagged("SellPad")` loop wires touch handlers **once at server start**, before any player has claimed a plot. Result: every player walks onto a SellPad and nothing happens. **This is revenue-dead.** Players harvest, hit sell, get zero, churn.

## Approach

Replace the one-shot loop with `CollectionService:GetInstanceAddedSignal("SellPad"):Connect(...)`. Wire each pad's `.Touched` (or proximity prompt) **as it spawns**.

```lua
local CollectionService = game:GetService("CollectionService")

local function wireSellPad(pad)
    -- existing logic, hoisted out of the loop body
end

for _, pad in CollectionService:GetTagged("SellPad") do
    wireSellPad(pad)  -- catches anything that exists at script-load time
end

CollectionService:GetInstanceAddedSignal("SellPad"):Connect(wireSellPad)
```

## Acceptance

- [ ] Player claims plot, plants, harvests, walks onto SellPad → cash leaderstat increments
- [ ] Tested with 2+ players, no crosstalk (player A walking on player B's pad doesn't pay player A)
- [ ] No errors in `get_console_output` after a 5-min test session

## Log

- 2026-05-06 — G-Tard filed during initial triage
- 2026-05-06 — Lin spotted that `b53055a` already lands the fix (hoisted `wireSellPad`, `WiredSell` attribute idempotency guard, `GetInstanceAddedSignal` connect at `PlantHandler.server.luau:111-163`). Closed as done-pre-coord. Will verify live in Studio during BAB-002 test pass.
