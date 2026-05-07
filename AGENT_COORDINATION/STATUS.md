# STATUS

> Live "who's doing what". Update on every state change.

```
G-Tard:    BLOCKED on test rig — Rojo not serving, Studio file may be scratch "Place1"
G-Tard Lin: BAB-002 in-review — code clean, awaiting Studio test pass

Last live publish: b4150d3 (v0.2 — seed shop, mutations, stealing) @ pre-coord
Place ID: 93948369125480   (confirmed live via execute_luau — matches Lin's MEMORY)
Universe ID: 10130205713  (confirmed live via execute_luau — matches Lin's MEMORY)
Active Studio sessions: 1 (Mac, instance "Bloom & Burgle", recently disconnected/reconnected via MCP)
WhatsApp bus: +17242606467 (G-Tard Lin DM) + 120363425074133557@g.us (group)
```

> ✅ IDs confirmed. Prior STATUS values were neon-forge-tycoon's; corrected `2026-05-06`.
> ⚠️ Studio rig is NOT "warm". rokit + rojo not installed on Mac; no live Rojo server; Studio currently shows pre-BAB-002 code (script_grep `starterPackGranted` = 0 hits). Awaiting Retard to install rokit and Connect the Rojo plugin before any [BAB-NNN] test can run.

## In flight

- **G-Tard Lin** — BAB-002 in-review. Plant + plot + stash persistence + 24h offline catchup. Also patches latent PlotManager rebuild gap and starter-pack one-shot exploit. Code reviewed, clean. **Studio test BLOCKED** — see Blocked below.
- **G-Tard (Mac)** — awaiting toolchain unblock to run [BAB-002] repros.

## Recently done

- 2026-05-06 — Coordination protocol scaffolded
- 2026-05-06 — Initial triage: BAB-001..010 filed
- 2026-05-06 — Lin engaged via WhatsApp group, claimed BAB-002
- 2026-05-06 — BAB-001 closed (verified `b53055a` pre-coord launch-kit hotfix already covered it)
- 2026-05-06 — BAB-002 implementation pushed for review

## Blocked / waiting

- **[BAB-002] Studio test** blocked on Mac toolchain:
  - rokit + rojo not installed on this Mac (`which rokit` / `which rojo` both empty).
  - No active `rojo serve` process; Studio still shows pre-BAB-002 code.
  - Studio file currently named "Place1" — may be a scratch place, not the BB production file (though IDs match).
  - **Asks for Retard:** install rokit (`brew install rokit && rokit install` in `~/Dev/bloom-and-burgle`), confirm correct .rbxl file is open, click Connect on the Rojo Studio plugin once `rojo serve` is up.
