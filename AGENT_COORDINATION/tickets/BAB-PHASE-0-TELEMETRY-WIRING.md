# BAB-PHASE-0-TELEMETRY-WIRING: wire the 10 launch events + Cloudflare Worker endpoint (ADR-3)

**Owner:** unassigned
**State:** inbox (design — implementation-ready; this is the next PR)
**Priority:** **P0** — Architecture eval `Bloom&Burgle_Architecture_Eval.md:250` flagged this 4 months ago and it's still unchecked. Blocks all virality tuning (Phases 2-5) because we'd be flying blind.
**Files touched (planned):**

- audit + extend `src/ServerScriptService/Telemetry.luau` (likely a small `setEndpoint` runtime-override hook + retry/queue tweaks; module already exposes `track / flush / queueDepth / setEndpoint`)
- new `tools/telemetry-worker/worker.js` (Cloudflare Worker — single file, ~30 LOC)
- new `tools/telemetry-worker/wrangler.toml`
- audit + add `Telemetry.track(...)` calls at the 9 missing event sites:
  - `session_start`        → already auto-fires per `Telemetry.luau:156` (verify)
  - `class_picked`         → likely in `src/ServerScriptService/Critter/PlantingFlow.server.luau` or wherever Class attribute is set
  - `pod_loaded`           → `src/ServerScriptService/Critter/PlantingFlow.server.luau` (PlantSeed listener)
  - `pod_ripened`          → `src/ServerScriptService/Critter/GrowLoop.server.luau` (when Ripe attribute flips true)
  - `harvest_decision`     → `src/ServerScriptService/Critter/HarvestFlow.luau`
  - `sell_payout`          → already wired in marketplace `MerchantSellFlow.luau`; need to add to on-plot `EconomyPad.luau` too
  - `scrap_payout`         → `src/ServerScriptService/Critter/EconomyPad.luau`
  - `gamepass_purchased`   → wherever MarketplaceService receipts are wired (grep `ProcessReceipt`)
  - `dev_product_purchased` → same as gamepass
  - `error_caught`         → wire global `LogService.MessageOut` listener with severity filter

## Problem

Per `Bloom&Burgle_Architecture_Eval.md` ADR-3 (P0, line 250+): we have a
Telemetry module but no events are emitted at the canonical 10 funnel
points. Without the funnel:

- Can't tune which Mythic ceremony scaling drives the most "share moment" toasts
- Can't measure conversion from `class_picked` → first `harvest_decision`
- Can't tell which species/class combos drive the asset/liability arbitrage activations
- Can't isolate where the 24h retention drop happens

ADR-3 is the precondition for evidence-based tuning of every other phase
(escape mechanic, mythic ceremony, visit-a-friend, weekly events). Phases
1-5 all assume we know what's working. We don't, today.

## Approach

### What's already there

`src/ServerScriptService/Telemetry.luau` already exposes:
- `Telemetry.track(eventName, props, player)` — main API
- `Telemetry.flush()` — manual flush for testing
- `Telemetry.queueDepth()` — diagnostic
- `Telemetry.setEndpoint(url)` — runtime override

So this PR is wiring + endpoint, not building from scratch.

### Cloudflare Worker as the backend

Single-file Worker (`tools/telemetry-worker/worker.js`):

```js
export default {
  async fetch(request, env) {
    if (request.method !== "POST") return new Response("only POST", { status: 405 });
    const body = await request.json();
    // Append to a Workers KV namespace OR forward to PostHog/BigQuery
    await env.BAB_TELEMETRY.put(`evt:${Date.now()}:${crypto.randomUUID()}`, JSON.stringify(body));
    return new Response("ok", { status: 200 });
  },
};
```

Hosted at `https://bab-telemetry.<account>.workers.dev`. Authentication
via a shared secret in the request header (Worker reads from
`env.BAB_INGEST_KEY`; Roblox sends in `X-Bab-Ingest-Key`). Rejected
requests return 401 to keep raw KV clean.

Cost: free tier covers ~100k requests/day; we won't hit that until 1000+
DAU. Migration path to BigQuery is a 10-line change in the Worker.

### Endpoint hookup from Roblox

`Telemetry.setEndpoint("https://bab-telemetry.<account>.workers.dev")`
called once at server boot (in a new `src/ServerScriptService/TelemetryBoot.server.luau` or as part of `LeaderstatsScript`'s init).

Runtime override per `Workspace.TelemetryEndpoint` attribute (mirrors
the BabPlaces pattern) so a hotfix can re-point the endpoint without
republishing.

### Anti-PII discipline

Roblox Telemetry events should NOT include:
- Display names (use `userId` only — display names are PII when joined to other data)
- Plot positions
- Chat message contents

Already-shipped events (`session_start` per Telemetry.luau) are clean.
New event sites must follow this rule. Add a comment block at the top
of each event declaration noting the props schema.

### The 10 events — schemas

| Event | Props | Where fired |
|---|---|---|
| `session_start` | `{class, lifetimeCash}` | Telemetry.luau:156 (auto) |
| `class_picked` | `{class, isFirstPick}` | wherever `player:SetAttribute("Class", ...)` runs |
| `pod_loaded` | `{species, slot, seedCost}` | PlantingFlow PlantSeed handler |
| `pod_ripened` | `{species, slot, mutationsRolled}` | GrowLoop ripe transition |
| `harvest_decision` | `{species, slot, choice: "harvest"\|"escape"\|"timed_out"}` | HarvestFlow.harvestPlanter |
| `sell_payout` | `{merchant, npcId?, species, mutationId, count, multiplier, payout, isAsset, wasSpecial}` | MerchantSellFlow ✓ + EconomyPad sell branch |
| `scrap_payout` | `{species, mutationId, count, payout}` | EconomyPad scrap branch |
| `gamepass_purchased` | `{passId, price}` | MarketplaceService.ProcessReceipt callback |
| `dev_product_purchased` | `{productId, price}` | same |
| `error_caught` | `{message, severity, source}` | LogService.MessageOut filter `>= MessageWarning` |

## Acceptance

- [ ] Cloudflare Worker deployed; reachable via curl POST returns 200.
- [ ] `setEndpoint` called at server boot using either env-baked URL or `Workspace.TelemetryEndpoint` runtime override.
- [ ] All 10 event sites emit at least once during a single playthrough (verifiable via Worker KV inspection).
- [ ] No PII (display names, positions, chat content) in any payload.
- [ ] Telemetry queue flushes on `PlayerRemoving` (already in `Telemetry.luau`; verify still works).
- [ ] Failed POSTs retry 3× with exponential backoff before being dropped (silently — never block gameplay).
- [ ] No regression on the existing harvest loop (run the standard live verification post-publish).
- [ ] Worker auth via shared secret in `X-Bab-Ingest-Key` header; missing/wrong → 401 + dropped, not stored.

## Open questions

1. **Where does the ingest secret live?** Cloudflare env-var on Worker side; Roblox-side via `Workspace.TelemetryIngestKey` attribute set at publish time. Don't commit it. Document the publish-time setup step in AGENTS.md.
2. **Sampling.** At launch, send 100% of events. If we hit free-tier limits, sample non-critical events (`pod_loaded`, `pod_ripened`) at 10% but always send `session_start`, `class_picked`, payout events, `error_caught`.
3. **Retention / queryability.** KV is fine for the first 1000 DAU. Next move is a Worker that pipes to BigQuery; defer until it matters.

## Defer

- Real-time dashboards (Looker / Grafana). KV inspection + manual queries are enough until DAU > 100.
- A/B testing infra. We don't have enough volume yet to run experiments.
- PostHog integration. Skip — Cloudflare Worker → BigQuery is cheaper and we don't need PostHog's UI for the first 6 months.

## Log

- 2026-05-08 — Direction shift session; user re-prioritized to telemetry-first. Drafted ticket.
- 2026-05-09 — Discovery surprise: 9 of 10 canonical events were already wired (`session_start`, `class_picked`, `pod_loaded`, `pod_ripened`, `sell_payout`, `scrap_payout`, `gamepass_purchased`, `dev_product_purchased`, `error_caught`). Only `harvest_decision` was missing. Plus 2 bonus events (`egg_purchased`, `steal_succeeded`).
- 2026-05-09 — Phase 0 code merged (PR #14 / commit `9494555`): Cloudflare Worker scaffolding (`tools/telemetry-worker/`), `harvest_decision` event in `HarvestFlow.luau`, `Telemetry.setIngestKey` + `X-Bab-Ingest-Key` header on flush, `TelemetryBoot.server.luau` reads generated `TelemetryConfig.luau` from `.env`-injected build (gitignored), Workspace-attribute fallback for runtime override.
- 2026-05-09 — Phase 0 deployed (PR #15 / commit `b245a8a`):
  - Cloudflare Worker live at `https://bab-telemetry.nick-b7a.workers.dev`
  - KV namespace `BAB_TELEMETRY` (id `b0d556638b91491f8c17604ba2443249`) bound, smoke-tests pass end-to-end (401 unauth / 401 wrong key / 200 empty / 200 real-shape with KV write verified)
  - `wrangler.toml` populated with KV id; `[limits].cpu_ms` removed (paid-plan only)
  - All 3 places republished with telemetry config baked in: Hatchery v65, Marketplace v4, Corridors v6
  - Hatchery publish from Mac succeeded first try after Linux session hit ~31× HTTP 409 retries (place-specific lock pattern; Mac credentials unblocked it)
- **STATUS: Phase 0 LIVE** — every player session now POSTs the 11 events (`session_start`, `session_end`, `class_picked`, `pod_loaded`, `pod_ripened`, `harvest_decision`, `sell_payout`, `scrap_payout`, `gamepass_purchased`, `dev_product_purchased`, `error_caught`, plus bonus `egg_purchased` and `steal_succeeded`) to Workers KV. Inspect with `npx wrangler kv key list --binding BAB_TELEMETRY --remote`.
