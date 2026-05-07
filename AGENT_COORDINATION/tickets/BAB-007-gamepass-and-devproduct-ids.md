# BAB-007: Gamepass + Dev product IDs are zero defaults — runtime overrides not yet set

**Owner:** G-Tard (Mac — Studio side runtime config)
**State:** inbox
**Priority:** P0 (revenue depends on this)
**Files touched:** Studio Workspace attributes only (no code change), or `src/ServerScriptService/GamepassHandler.server.luau` for hardcoded fallback

## Problem

`GamepassHandler.luau`:
```lua
local DEFAULT_PASS_IDS = {
    ["2X_CASH"] = 0,
    ["4X_CASH"] = 0,
    ...
}
```
All zeros. The Workspace attribute override (`BB_GAMEPASS_<KEY>`) lets us set them at runtime, but **they aren't set yet**.

Same problem for `DevProductHandler.luau` (`BB_DEVPRODUCT_*`).

Per `LAUNCH.md`, gamepasses are queued to be created in the Roblox dashboard but Lin needs the actual asset IDs.

## Approach

Two paths:

**Fast path (G-Tard, today):** Use Studio MCP `execute_luau` to set Workspace attributes for any IDs that already exist in the Roblox dashboard:
```lua
workspace:SetAttribute("BB_GAMEPASS_2X_CASH", 1234567)
workspace:SetAttribute("BB_GAMEPASS_4X_CASH", 1234568)
...
```
These attributes aren't persisted across publishes, so we also need to:

**Durable path:** Hardcode the IDs in the `DEFAULT_PASS_IDS` / `DEFAULT_PRODUCT_IDS` tables in source, commit, push, publish.

## Acceptance

- [ ] All 6 gamepass IDs set (2X_CASH, 4X_CASH, AUTO_HARVEST, ANTI_THEFT, VIP_PLOT, MYTHIC_HUNTER)
- [ ] All 5 devproduct IDs set (GROWTH_ACCELERATOR_INSTANT, PREMIUM_SEED_BUNDLE, JAIL_ESCAPE_TOKEN, LUCK_BOOST_8X, EXTRA_PLOT_SLOT)
- [ ] Test purchase flow with at least one of each (use Studio's TestService or a real Robux test)
- [ ] Receipt idempotency works (re-trigger same PurchaseId, no double-grant)

## Blockers

- Need actual asset IDs from Roblox creator dashboard. Retard / Lin needs to either create the passes or pass us the IDs of any already-created ones.

## Log

- 2026-05-06 — G-Tard filed during initial triage
