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

- **G-Tard Lin** — BAB-002 in-review. Plant + plot + stash persistence + 24h offline catchup. Also patches latent PlotManager rebuild gap and starter-pack one-shot exploit. Code reviewed, clean.
- **G-Tard (Mac)** — ✅ BAB-002 Studio code verified + synced. All 4 scripts (DataStore, PlantHandler, PlotManager, LeaderstatsScript) in Studio, syntax clean, `_G.PlantHandler` export wired. **Awaiting DataStore permission enable** (see Blocked).

## Recently done

- 2026-05-06 — Coordination protocol scaffolded
- 2026-05-06 — Initial triage: BAB-001..010 filed
- 2026-05-06 — Lin engaged via WhatsApp group, claimed BAB-002
- 2026-05-06 — BAB-001 closed (verified `b53055a` pre-coord launch-kit hotfix already covered it)
- 2026-05-06 — BAB-002 implementation pushed for review

## Blocked / waiting

- **[BAB-002] DataStore API access** blocked on Studio setting:
  - Console shows `DataStoreService: StudioAccessToApisNotAllowed` when DataStore tries to load.
  - **Asks for Retard:** In Roblox Studio, open Game Settings (top menu or gear icon) → go to Security tab → toggle "Studio Access to API Services" = ON. Then restart Play in Studio and BAB-002 can run a real smoke test.
