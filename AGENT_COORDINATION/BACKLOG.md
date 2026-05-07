# BACKLOG

> Quick scoreboard of all open tickets. Source of truth is `tickets/`.

## P0 — money on the floor, fix now

| Ticket | Title | Owner | State |
|---|---|---|---|
| [BAB-001](tickets/BAB-001-sellpad-empty-loop.md) | SellPad payout never fires | G-Tard (Mac) | ✅ done (b53055a) |
| [BAB-002](tickets/BAB-002-plant-state-not-persisted.md) | Plant grow state lost on server restart | G-Tard Lin | 🔨 in-progress |
| [BAB-003](tickets/BAB-003-stash-vs-cash-decoupled.md) | Harvested plants don't go in stash | G-Tard Lin | inbox |
| [BAB-007](tickets/BAB-007-gamepass-and-devproduct-ids.md) | Gamepass + Dev product IDs are zero | G-Tard (Mac) | inbox |

## P1 — retention + virality

| Ticket | Title | Owner |
|---|---|---|
| [BAB-004](tickets/BAB-004-rebirth-system.md) | Rebirth/Prestige system missing | G-Tard Lin |
| [BAB-005](tickets/BAB-005-stealing-direct-cash-no-stash.md) | StealHandler awards direct cash, should drop in stash | G-Tard Lin |
| [BAB-006](tickets/BAB-006-stealing-clientside-prompt-exploit.md) | Steal prompts created client-side (exploit risk) | G-Tard Lin |
| [BAB-008](tickets/BAB-008-trading-economy.md) | Player-to-player trading missing | G-Tard Lin |
| [BAB-009](tickets/BAB-009-pets-system.md) | Pets system entirely missing | G-Tard Lin |
| [BAB-010](tickets/BAB-010-leaderboards.md) | Leaderboards missing | G-Tard Lin |

## Future / un-ticketed (rough notes)

- Live events system (weekly seed events, mutation specials) — spec section 4
- Roleplay hub town square assets, customizable houses — spec section 3
- Anti-exploit + reporting — spec section 6
- Analytics pipeline (DAU, retention, ARPPU dashboards) — spec section 6
- Roblox Premium upsell modal — spec section 5
- Private servers config — spec section 5
- Daily quest + login streak system — spec section 4

## Recommended sequencing

1. **Today (P0 sweep):** BAB-001 → BAB-007 → BAB-002 → BAB-003 (in this order; BAB-002+3 can interleave)
2. **Day 2-3:** BAB-005 + BAB-006 (steal hardening)
3. **Day 4-5:** BAB-004 (rebirth) + BAB-010 (leaderboards) — unlock the long tail
4. **Day 6-10:** BAB-009 (pets) — unlocks egg-based monetization
5. **Day 10+:** BAB-008 (trading) + spec gaps from "future"
