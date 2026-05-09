# BAB Telemetry Worker

Cloudflare Worker that receives event batches from the BAB Roblox places and stores them in Workers KV for later query.

Phase 0 of `BAB-PHASE-0-TELEMETRY-WIRING`.

## What this gets you

- Single endpoint at `https://bab-telemetry.<your-account>.workers.dev`
- Free tier: ~100k requests/day (we'll hit that around 1000+ DAU)
- 90-day KV retention per batch
- Stream logs via `npx wrangler tail`
- Auth via shared secret (`X-Bab-Ingest-Key` header)

## One-time deployment

Prerequisites: Node 18+, a Cloudflare account (free tier is fine).

```bash
cd tools/telemetry-worker

# 1. Auth (opens a browser tab; pick the right account)
npx wrangler login

# 2. Create the KV namespace. Output includes an `id` field — copy it.
npx wrangler kv namespace create BAB_TELEMETRY

# 3. Paste the id into wrangler.toml's `kv_namespaces[0].id`

# 4. Set the ingest secret. Pick a strong random string (e.g.,
#    `openssl rand -hex 32`). You'll re-use this value in the Roblox
#    publish env (BB_TELEMETRY_KEY).
npx wrangler secret put BAB_INGEST_KEY
# (paste the secret when prompted)

# 5. Deploy.
npx wrangler deploy

# Output gives you the live URL, e.g. https://bab-telemetry.your-acct.workers.dev
```

## Smoke test

```bash
# Unauthorized — should return 401
curl -i -X POST https://bab-telemetry.<your-acct>.workers.dev \
  -H 'content-type: application/json' \
  -d '{"events":[]}'

# Authorized empty batch — should return 200 "empty batch"
curl -i -X POST https://bab-telemetry.<your-acct>.workers.dev \
  -H 'content-type: application/json' \
  -H 'x-bab-ingest-key: <your-secret>' \
  -d '{"events":[]}'

# Real-shape batch — should return 200 with {"ok":true, key, count}
curl -i -X POST https://bab-telemetry.<your-acct>.workers.dev \
  -H 'content-type: application/json' \
  -H 'x-bab-ingest-key: <your-secret>' \
  -d '{"placeId":1,"jobId":"test","sessionId":"abc","shipTs":0,"events":[{"name":"smoke_test","ts":0,"props":{}}]}'
```

## Wire up Roblox

After the Worker is live, set these in your `.env`:

```bash
BB_TELEMETRY_ENDPOINT=https://bab-telemetry.<your-acct>.workers.dev
BB_TELEMETRY_KEY=<the-secret-you-set-in-step-4>
```

Then republish all 3 places. The publish scripts inject these as Workspace attributes that `TelemetryBoot.server.luau` reads at server start.

## Querying the data (manual, for now)

KV doesn't have a query language. For now:

```bash
# List recent keys
npx wrangler kv key list --binding BAB_TELEMETRY | head -20

# Read one key
npx wrangler kv key get --binding BAB_TELEMETRY "evt:1746820000000:abc-..."

# Live tail logs (shows every Worker invocation)
npx wrangler tail
```

When DAU justifies it (1000+ players), replace the KV write in `worker.js` with a BigQuery streaming insert and bring in proper query tooling. Until then KV + manual inspection is fine.

## Cost monitoring

Free tier limits:
- 100k requests / day
- 25 GB KV storage

At ~1 batch / 30s / server / 50 servers = ~7k req/day at peak. Plenty of headroom.

If you exceed: `wrangler.toml` cap is set conservatively, and CF will start returning 429s. Worker upgrades are $5/mo for 10M req. Migrate before hitting limits.

## Deletion / decommission

```bash
npx wrangler delete  # tears down the Worker
npx wrangler kv namespace delete --binding BAB_TELEMETRY  # tears down KV
```

Both are reversible (just redeploy from this folder).
