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
| `sync` | **CWD-independent dispatcher.** Resolves its own location via `$BASH_SOURCE` so it works from any directory (repo root, subdir, hook context, or after `cd src/...`). Default: `append-quiet` (the Stop hook target). Subcommands: `append`, `export`, `query "..."`. |
| `export_history.py` | Full converter. Reads the latest session JSONL from `~/.claude/projects/<encoded-cwd>/`, renders to `Bloom&Burgle_ChatHistory.md` at the repo root. Strips base64 image blobs to placeholders. Idempotent. |
| `append_history.py` | Incremental updater. Tracks `.last_uuid`; appends only new messages. Falls back to a full export if the session changed. Designed for the Stop hook. |
| `query_history.py` | RLM-powered Q&A. Loads the JSONL into a Python REPL variable named `history`, then asks an RLM to slice/grep it. |
| `.last_uuid` | Pointer file (auto-managed). Tracks the last UUID exported so the appender knows where to resume. |
| `.rlm_logs/` | RLM trajectory logs (auto-created on first query). |

**All scripts work from any CWD** — they locate themselves via `__file__` (Python) or `$BASH_SOURCE` (shell). The Stop hook uses `git rev-parse --show-toplevel` to find the repo root, so it's safe to invoke from `cd src/...` or any subdirectory.

## How the auto-append works

`.claude/settings.json` registers a `Stop` hook that runs after every
assistant turn:

```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "r=$(git rev-parse --show-toplevel 2>/dev/null); if [ -x \"$r/scripts/history/sync\" ]; then \"$r/scripts/history/sync\" 2>&1 | sed 's/^/[bab-history] /' || true; fi",
        "timeout": 10
      }
    ]
  }
]
```

The hook is fully CWD-independent — `git rev-parse --show-toplevel` finds
the repo root regardless of where you launched Claude (`cd src/... &&
claude` works, as does running from a worktree). If you happen to run
Claude outside any git tree, the hook silently skips. Output is prefixed
`[bab-history]` so you'd notice if it errored.

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
./scripts/history/sync query "what was the sell pad bug?"
./scripts/history/sync query "summarize the steampunk pivot ADRs"
./scripts/history/sync query "when did Telemetry.luau land and what does it expose?"
```

(Or call `python3 scripts/history/query_history.py "..."` directly.)

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

The `sync` wrapper is the recommended entry point — it's the same script
the Stop hook calls, and it works from any CWD.

```bash
# Re-render the .md from scratch (e.g. after pulling a new session)
./scripts/history/sync export

# Force a verbose append (no `--quiet`)
./scripts/history/sync append

# Default — silent incremental append (same as the Stop hook)
./scripts/history/sync

# Ask a question via RLM
./scripts/history/sync query "what was the sell pad bug?"

# Show the current resume pointer
cat scripts/history/.last_uuid
```

Or call the Python scripts directly — they all use `__file__` to find
themselves so CWD doesn't matter:

```bash
python3 /any/path/to/scripts/history/export_history.py
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
