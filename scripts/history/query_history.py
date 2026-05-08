#!/usr/bin/env python3
"""
query_history.py — RLM-powered queries over the Bloom & Burgle chat history.

Loads the session JSONL (lossless source) into a Python REPL variable and
asks an RLM to slice/grep it to answer a question. RLM (Recursive Language
Models — https://arxiv.org/abs/2512.24601) keeps the full transcript out of
the model's context window: only the question + a tiny handle to the REPL
variable is sent each turn, and the model writes Python to query the data.

Usage:
    pip install rlms python-dotenv anthropic
    export ANTHROPIC_API_KEY=sk-ant-...   # or OPENAI_API_KEY
    python3 scripts/history/query_history.py "what was the sell pad bug?"

Optional flags:
    --backend anthropic|openai|portkey  (default: anthropic)
    --model claude-...|gpt-...          (default: claude-sonnet-4-6)
    --max-iters N                       (default: 12)
    --jsonl PATH                        (default: latest from this project)
    --md PATH                           (default: Bloom&Burgle_ChatHistory.md)
"""

from __future__ import annotations

import argparse
import os
import sys
import textwrap
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from export_history import find_claude_project_dir, latest_session  # noqa: E402


PROMPT_TEMPLATE = """\
You are a research assistant with REPL access to the full transcript of a
Claude Code session for the Roblox game "Bloom & Burgle". The transcript is
already loaded into a Python variable named `history` — a list of dicts, one
per JSONL line. Useful keys per entry:

  type        — "user" | "assistant" | "system" | "attachment" | ...
  timestamp   — ISO-8601 string
  message     — for user/assistant: {{role, content}}
                  content is a list of blocks: text / thinking / tool_use / tool_result / image
  uuid        — unique id, monotonic-ish

A markdown-rendered, image-stripped version is also available at:
  md_path = {md_path!r}

You can `open(md_path).read()` or use `history` directly. For image data,
use `history` (the .md strips it).

Your tools (available as Python builtins in the REPL):
  - `history`  — the loaded JSONL list (already in scope)
  - `md_path`  — path to the rendered .md (already in scope)
  - All standard library
  - `re`, `json` are already imported

Question:
{question}

Plan: in your first REPL block, slice or grep `history` to find the relevant
turns. Print only the bits you need. Then synthesize a concise answer using
FINAL_VAR(answer). Do not dump entire turns to the output — they are large.
"""


def build_repl_setup(jsonl_path: Path, md_path: Path) -> str:
    """The Python that RLM's REPL will execute on first call to seed `history`."""
    return textwrap.dedent(f"""\
        import json, re
        with open({str(jsonl_path)!r}) as _f:
            history = []
            for _line in _f:
                _line = _line.strip()
                if not _line:
                    continue
                try:
                    history.append(json.loads(_line))
                except json.JSONDecodeError:
                    pass
        md_path = {str(md_path)!r}
        print(f"loaded {{len(history)}} history entries; md at {{md_path}}")
    """)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("question", help="natural-language question about the chat history")
    ap.add_argument("--backend", default="anthropic")
    ap.add_argument("--model", default="claude-sonnet-4-6")
    ap.add_argument("--max-iters", type=int, default=12)
    ap.add_argument("--jsonl", help="explicit path to .jsonl session file")
    ap.add_argument("--md", help="explicit path to rendered .md")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    repo_root = HERE.parents[1]

    if args.jsonl:
        jsonl_path = Path(args.jsonl).resolve()
    else:
        proj_dir = find_claude_project_dir(repo_root)
        jsonl_path = latest_session(proj_dir)

    if args.md:
        md_path = Path(args.md).resolve()
    else:
        md_path = repo_root / "Bloom&Burgle_ChatHistory.md"

    print(f"[query_history] jsonl: {jsonl_path}")
    print(f"[query_history] md:    {md_path}")
    print(f"[query_history] backend: {args.backend} / {args.model}")
    print()

    try:
        from rlm import RLM
        from rlm.logger import RLMLogger
    except ImportError:
        sys.exit(
            "rlms not installed. Run: pip install rlms python-dotenv anthropic\n"
            "Or: uv pip install -e /Users/nickanthony/Dev/rlm"
        )

    # API key resolution by backend
    backend_kwargs: dict = {"model_name": args.model}
    if args.backend == "anthropic":
        key = os.getenv("ANTHROPIC_API_KEY")
        if not key:
            sys.exit("ANTHROPIC_API_KEY not set in environment")
        backend_kwargs["api_key"] = key
    elif args.backend == "openai":
        key = os.getenv("OPENAI_API_KEY")
        if not key:
            sys.exit("OPENAI_API_KEY not set")
        backend_kwargs["api_key"] = key
    elif args.backend == "portkey":
        key = os.getenv("PORTKEY_API_KEY")
        if not key:
            sys.exit("PORTKEY_API_KEY not set")
        backend_kwargs["api_key"] = key

    logger = RLMLogger(log_dir=str(repo_root / "scripts" / "history" / ".rlm_logs"))
    rlm = RLM(
        backend=args.backend,
        backend_kwargs=backend_kwargs,
        environment="local",
        max_iterations=args.max_iters,
        logger=logger,
        verbose=args.verbose,
    )

    # Pre-seed the REPL with `history` and `md_path` so the model doesn't
    # have to re-derive the path on every query.
    try:
        rlm.environment.execute(build_repl_setup(jsonl_path, md_path))
    except AttributeError:
        # If the public env interface changed, fall back to including the
        # setup in the prompt itself (slightly less efficient but works).
        seed = build_repl_setup(jsonl_path, md_path)
        question = f"First, execute this setup in the REPL:\n```python\n{seed}\n```\n\nThen answer:\n{args.question}"
        result = rlm.completion(question)
        print(f"\n=== Answer ===\n{result.response}")
        return

    prompt = PROMPT_TEMPLATE.format(question=args.question, md_path=str(md_path))
    result = rlm.completion(prompt)
    print(f"\n=== Answer ===\n{result.response}")


if __name__ == "__main__":
    main()
