// BAB Telemetry Worker — receives event batches from Roblox Hatchery /
// Marketplace / Corridors places and stores them in Workers KV for later
// query.
//
// Phase 0 of BAB-PHASE-0-TELEMETRY-WIRING. Free tier covers ~100 req/s
// burst and 100k/day; we won't hit that until 1000+ DAU.
//
// Auth: shared secret in `X-Bab-Ingest-Key` header. Set via
//   npx wrangler secret put BAB_INGEST_KEY
//
// Storage: Workers KV namespace `BAB_TELEMETRY`. Each batch lands as a
// single key `evt:<unix-millis>:<uuid>` containing the JSON payload.
// At ~1KB/batch and 1 batch / 30s / server, a 10-CCU game writes ~80MB/day —
// well under the 25GB free-tier KV limit.
//
// Migration path: when DAU > 1000, replace the KV write with a fetch to a
// BigQuery streaming insert (or PostHog ingest). The Roblox-side payload
// shape stays identical; only this Worker changes.

export default {
  /** @param {Request} request @param {{BAB_TELEMETRY: KVNamespace, BAB_INGEST_KEY: string}} env */
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("only POST accepted", { status: 405 });
    }

    // Auth.
    const provided = request.headers.get("x-bab-ingest-key") || "";
    if (!env.BAB_INGEST_KEY || provided !== env.BAB_INGEST_KEY) {
      // Don't leak whether the key is unset vs wrong.
      return new Response("unauthorized", { status: 401 });
    }

    // Parse + minimal validation.
    let payload;
    try {
      payload = await request.json();
    } catch (e) {
      return new Response("invalid json", { status: 400 });
    }
    if (!payload || typeof payload !== "object") {
      return new Response("not an object", { status: 400 });
    }
    if (!Array.isArray(payload.events)) {
      return new Response("missing events array", { status: 400 });
    }
    if (payload.events.length === 0) {
      // Nothing to store; ack with 200 so Roblox doesn't retry.
      return new Response("empty batch", { status: 200 });
    }

    // Store. Each batch as one key — preserves the server-side bundling
    // and minimizes KV op count vs one-event-per-key.
    const ts = Date.now();
    const id = crypto.randomUUID();
    const key = `evt:${ts}:${id}`;

    const meta = {
      placeId: payload.placeId,
      jobId: payload.jobId,
      sessionId: payload.sessionId,
      eventCount: payload.events.length,
      shipTs: payload.shipTs,
    };

    try {
      await env.BAB_TELEMETRY.put(key, JSON.stringify(payload), {
        // 90-day retention; KV's max is 1 year. Audit-only data; not source-of-truth.
        expirationTtl: 60 * 60 * 24 * 90,
        metadata: meta,
      });
    } catch (e) {
      // KV write failed. Log + 5xx so Roblox COULD retry (it currently won't,
      // per Telemetry.luau which drops on failure to avoid retry storms).
      console.error("KV put failed:", e?.message || e);
      return new Response("storage failure", { status: 502 });
    }

    return new Response(JSON.stringify({ ok: true, key, count: payload.events.length }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  },
};
