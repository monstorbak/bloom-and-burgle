#!/usr/bin/env python3
"""
append_history.py — incremental updater for Bloom&Burgle_ChatHistory.md.

Tracks the last-exported message UUID in scripts/history/.last_uuid (written
by export_history.py and updated here). Reads the live session JSONL,
skips everything up to and including that UUID, and appends the rest.

Designed to be invoked by the Claude Code Stop hook after each assistant
turn — runs in <100ms even on the full transcript because we only render
the new tail.

Usage:
    python3 scripts/history/append_history.py [--quiet]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Reuse helpers from export_history — keeps a single source of truth for
# rendering rules (image stripping, tool_use/tool_result formatting).
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from export_history import find_claude_project_dir, latest_session, render_event  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--out",
        default="Bloom&Burgle_ChatHistory.md",
        help="output .md path relative to repo root",
    )
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    repo_root = HERE.parents[1]
    project_dir = find_claude_project_dir(repo_root)
    src = latest_session(project_dir)

    pointer_path = HERE / ".last_uuid"
    last_uuid = None
    last_session_name = None
    if pointer_path.is_file():
        line = pointer_path.read_text().strip()
        if "\t" in line:
            last_session_name, last_uuid = line.split("\t", 1)
        else:
            last_uuid = line

    out_path = repo_root / args.out

    # If the session file changed (new conversation), or .md doesn't exist,
    # do a full re-export instead of incremental — partial appends across
    # different sessions would interleave incorrectly.
    if last_session_name != src.name or not out_path.is_file():
        if not args.quiet:
            print(f"[append_history] session changed or .md missing — full export")
        # Use the programmatic run() entrypoint so we don't accidentally
        # re-parse our own argv (which carries --quiet, an export flag we
        # don't accept).
        from export_history import run as full_export
        full_export(out=args.out)
        return

    new_chunks: list[str] = []
    new_last_uuid: str | None = None
    skipping = last_uuid is not None
    seen = 0
    appended = 0
    with open(src) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            seen += 1
            uid = d.get("uuid")
            if skipping:
                if uid == last_uuid:
                    skipping = False
                continue
            block = render_event(d)
            if block is None:
                if uid:
                    new_last_uuid = uid
                continue
            new_chunks.append(block)
            appended += 1
            if uid:
                new_last_uuid = uid

    if not new_chunks:
        if not args.quiet:
            print(f"[append_history] no new messages (read {seen}, last_uuid={last_uuid[:8] if last_uuid else 'None'}…)")
        return

    with open(out_path, "a") as f:
        f.write("\n\n")
        f.write("\n\n".join(new_chunks))

    if new_last_uuid:
        pointer_path.write_text(f"{src.name}\t{new_last_uuid}\n")

    if not args.quiet:
        size_kb = out_path.stat().st_size / 1024
        print(f"[append_history] +{appended} new messages → {out_path.name} now {size_kb:.0f} KB")


if __name__ == "__main__":
    main()
