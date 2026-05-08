# CLAUDE.md — instructions for any Claude session in this repo

> Claude Code auto-reads this file on every session start. It tells you
> what's persistent, where to look first, and when to query the chat
> history instead of asking the user.

## TL;DR — read these in order

1. **This file** (you're already here).
2. `AGENTS.md` — agent rules + coordination protocol (Mac vs Linux roles).
3. `Bloom&Burgle_Spec.md` — product mechanics + monetization.
4. `Bloom&Burgle_Design_Spec.md` — visual identity + design criteria.
5. `Bloom&Burgle_Architecture_Eval.md` — current architecture, P0/P1/P2 ADRs.

## Persistent chat history (the most important section)

This project has a **lossless mirror of every Claude session** at:

- **`Bloom&Burgle_ChatHistory.md`** at the repo root — human-readable, image-stripped, ~800 KB at last write. Auto-updated by the Stop hook after every assistant turn.
- **`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`** — the lossless source of truth (8 MB+). The .md is regenerated from this.

**You should query this history instead of asking the user "what did we decide?" / "remind me about X" / "what was the bug?".** The user has already answered those. The toolkit is built specifically so you don't burn the user's time or your own context window.

### How to query

```bash
./scripts/history/sync query "what was the sell pad bug fix?"
./scripts/history/sync query "summarize the steampunk pivot ADRs"
./scripts/history/sync query "when did Telemetry.luau land and what does it expose?"
```

The wrapper at `scripts/history/sync` works from any CWD — it self-locates via `$BASH_SOURCE`. The `query` subcommand uses [RLM (Recursive Language Models)](https://github.com/alexzhang13/rlm) to load the JSONL into a Python REPL variable named `history` and lets a sub-LM grep/slice it programmatically. Token cost: ~5–15K input vs ~2M to read the transcript in-context.

**Setup needed for the first query** (if not already installed):

```bash
pip install rlms python-dotenv anthropic
export ANTHROPIC_API_KEY=sk-ant-...   # or OPENAI_API_KEY / PORTKEY_API_KEY
```

### When to reach for it

| Scenario | What to do |
|---|---|
| User asks "remind me what we did about X" | `./scripts/history/sync query "what we did about X"` first; quote the answer back |
| You feel context is thin and you might miss prior decisions | Query for the topic before suggesting changes |
| User mentions a past commit or PR by description not hash | Query for the description; get the SHA |
| You're about to ask the user "did we already do Y?" | Don't ask — query the history |
| Architecture decisions, design rationale, ADRs | Already in the spec docs (read those first), but transcript has the conversation that produced them |

### Maintenance

- Stop hook auto-runs `scripts/history/sync` after every assistant turn → silent incremental append.
- If the hook ever errors, output is prefixed `[bab-history]` so you'd see it in your transcript.
- Manual full re-render (after pulling new sessions): `./scripts/history/sync export`.
- Manual append: `./scripts/history/sync append`.

## Other persistent infrastructure to know about

### Live Roblox Studio debug toolkit

`scripts/debug/dbg` wraps the Studio MCP bridge at `127.0.0.1:7878`. Common subcommands:

- `dbg health` — bridge + active Studio status
- `dbg state` — JSON snapshot: players, plots, sell-pads, planters, recent errors
- `dbg eval '<luau>'` — run Luau in the live game
- `dbg sync <relpath>` — push a single src/*.luau into Studio's place file
- `dbg shot [name]` — screenshot to `scripts/debug/captures/`
- `dbg sell-test` — end-to-end sell pad regression test

Full subcommand list: `./scripts/debug/dbg help`.

### Architecture conventions

- **Server services**: register/await pattern via `src/ServerScriptService/Services.luau` (replaces server `_G` registry — see ADR-1).
- **Currency-mutating handlers**: must call `RateLimiter.tryConsume(...)` first (anti-exploit per ADR-2).
- **Player-facing events**: emit `Telemetry.track(...)` for funnel analysis (ADR-3).
- **Material discipline**: `BrandColors.luau` palette only; banned: `SmoothPlastic`, `Plastic`, `Glass`, `Foil` (CI gate enforces).

## Hard rules (mirrored from AGENTS.md, but worth repeating)

1. **Always `git pull` first.** Multiple machines push to this repo.
2. **Direct push to `main` is allowed.** Don't sit on PRs unless the change is large.
3. **No silent regressions.** If you break something on live, file a ticket retroactively and own it.
4. **Money decisions need human in the loop.** Pricing, gamepass changes, monetization tuning → ask the user before merging.

## When you /clear or start a new session

The whole point of this setup: you don't lose anything. Run a query for whatever you need from the prior conversation. Trust the history; don't reconstruct from memory.
