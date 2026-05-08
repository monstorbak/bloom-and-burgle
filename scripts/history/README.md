# scripts/history — Persistent Chat History + RLM Querying

The Bloom & Burgle Claude Code session transcript can outgrow Claude's
context window. This directory provides a workflow that:

1. **Mirrors the live session JSONL** to a human-readable
   `Bloom&Burgle_ChatHistory.md` at the repo root, automatically, after
   every assistant turn (Claude Code `Stop` hook).
2. **Queries the full history** without burning Claude's context, by
   delegating to **[RLM](https://github.com/alexzhang13/rlm)** (Recursive
   Language Models — a wrapper that puts the transcript as a Python REPL
   variable and lets a sub-LM grep/slice it programmatically).

Once you have a few hundred KB of `.md` you can `/clear` Claude's context,
start fresh, and ask questions like *"what was the sell pad bug fix?"* —
the answer comes from `query_history.py` instead of from re-reading the
transcript in-context.

## Why this exists (vs. Claude's `/compact` and `/resume`)

- `/compact` — summarizes in-place, keeps recent turns. Lossy. Good for
  ongoing work; bad for "I want to look up something specific from 800
  messages ago."
- `/resume <session-id>` — continues an old session with its full context.
  Burns the whole thing on every turn.
- **RLM-on-JSONL** — full lossless recall, ~constant tokens per question
  regardless of transcript size. Right tool when you need archival access.

## Files in this directory

| File | What it does |
|---|---|
| `export_history.py` | Full converter. Reads the latest session JSONL from `~/.claude/projects/<encoded-cwd>/`, renders to `Bloom&Burgle_ChatHistory.md` at the repo root. Strips base64 image blobs to placeholders. Idempotent. |
| `append_history.py` | Incremental updater. Tracks `.last_uuid`; appends only new messages. Falls back to a full export if the session changed. Designed for the Stop hook. |
| `query_history.py` | RLM-powered Q&A. Loads the JSONL into a Python REPL variable named `history`, then asks an RLM to slice/grep it. |
| `.last_uuid` | Pointer file (auto-managed). Tracks the last UUID exported so the appender knows where to resume. |
| `.rlm_logs/` | RLM trajectory logs (auto-created on first query). |

## How the auto-append works

`.claude/settings.json` registers a `Stop` hook that runs after every
assistant turn:

```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "python3 scripts/history/append_history.py --quiet ...",
        "timeout": 10
      }
    ]
  }
]
```

The `--quiet` flag silences the "+N new messages" line in normal use; the
hook's stderr is prefixed `[bab-history]` so you'd notice if it errored.
Runtime is well under 1s on the full 8 MB JSONL because the appender skips
already-rendered messages by UUID.

**Why Stop instead of a 50% threshold?** Claude Code doesn't expose context
size to scripts, so threshold-based requires polling. The Stop hook fires
deterministically after each turn — cheaper, real-time, and the .md is
always fresh.

## How to query the history

**One-time setup:**

```bash
# Pick your backend's API key
export ANTHROPIC_API_KEY=sk-ant-...     # for Claude
# OR: export OPENAI_API_KEY=sk-...      # for GPT
# OR: export PORTKEY_API_KEY=...        # for Portkey-routed multi-provider

# Install RLM. Easiest:
pip install rlms python-dotenv anthropic
# Or for editable local dev with the cloned repo at ~/Dev/rlm:
uv pip install -e /Users/nickanthony/Dev/rlm
```

**Ask a question:**

```bash
python3 scripts/history/query_history.py "what was the sell pad bug?"
python3 scripts/history/query_history.py "summarize the steampunk pivot ADRs"
python3 scripts/history/query_history.py "when did Telemetry.luau land and what does it expose?"
```

**Flags:**

```
--backend anthropic|openai|portkey   default: anthropic
--model   <model-name>               default: claude-sonnet-4-6
--max-iters N                        default: 12 (RLM sub-LM step budget)
--jsonl PATH                         override: explicit transcript file
--md PATH                            override: explicit rendered .md
--verbose                            print RLM trajectory live
```

## Manual runs

```bash
# Re-render the .md from scratch (e.g. after pulling a new session)
python3 scripts/history/export_history.py

# Show pointer + force append
cat scripts/history/.last_uuid
python3 scripts/history/append_history.py
```

## Ignoring the .md from git

Add to `.gitignore`:

```
Bloom&Burgle_ChatHistory.md
scripts/history/.last_uuid
scripts/history/.rlm_logs/
```

The .md regenerates from JSONL at any time — there's no value in committing
it. Treat it like a build artifact.

## Recommended workflow

1. Work in Claude Code as normal. The Stop hook keeps `Bloom&Burgle_ChatHistory.md` current.
2. When the conversation gets long (or when Claude is about to compact),
   `/clear` to start fresh.
3. New session — when you need to recall something from before, run
   `python3 scripts/history/query_history.py "..."` from a separate
   terminal. The answer is short and you can paste it back.
4. Iteration cost stays roughly constant in token-spend regardless of how
   much history piles up.

## Cost estimate

- Auto-append: ~0 tokens / turn (it's a Python script, no LLM call).
- Query: a single RLM completion. With Claude Sonnet 4.6 + 12 iterations
  budget on an 8 MB transcript, expect 5–15K input tokens / query (the
  REPL slices keep it small). Compare to ~2M tokens to read the whole
  transcript in-context — ~99% reduction.
