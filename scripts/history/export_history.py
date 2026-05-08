#!/usr/bin/env python3
"""
export_history.py — full converter: Claude Code session JSONL → human-readable .md

Reads the most-recent session transcript at
    ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
and writes a clean .md to Bloom&Burgle_ChatHistory.md at the repo root.

Idempotent — overwrites the .md from scratch each run. Use append_history.py
for the incremental hot path (Stop hook); use this script for clean re-renders
or first-time export.

Strips base64-encoded image blobs (which would bloat the .md by ~10×) down to
"[image attached: <bytes> b64 chars]" placeholders. The original JSONL still
has the full data, which is what RLM queries reach into.

Usage:
    python3 scripts/history/export_history.py [--session SESSION_ID]

Without --session, picks the most-recently-modified .jsonl in the project's
Claude transcript directory.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# ── Resolve the .claude/projects/<encoded-cwd>/ directory ────────────
def find_claude_project_dir(repo_root: Path) -> Path:
    # Claude Code encodes the CWD by replacing both "/" and "." with "-".
    # That means `/Users/.../.claude/worktrees/X` becomes
    # `-Users-...--claude-worktrees-X` (note the double-dash for `.claude`).
    # We try the encoded form first; fall back to a fuzzy substring
    # search across all Claude project dirs (handles encoding rules
    # changing between Claude Code versions).
    home = Path.home()
    base = home / ".claude" / "projects"
    if not base.is_dir():
        sys.exit(f"no Claude project dir at {base}")

    def encode(p: Path) -> str:
        return str(p.resolve()).replace("/", "-").replace(".", "-")

    candidates: list[Path] = []
    direct = base / encode(repo_root)
    if direct.is_dir():
        candidates.append(direct)

    # Worktrees: each worktree gets its own Claude project dir.
    worktrees = repo_root / ".claude" / "worktrees"
    if worktrees.is_dir():
        for wt in worktrees.iterdir():
            cand = base / encode(wt)
            if cand.is_dir():
                candidates.append(cand)

    # Fuzzy fallback: find any project dir whose name contains the repo's
    # basename. Catches future Claude encoding changes.
    if not candidates:
        repo_basename = repo_root.name
        for d in base.iterdir():
            if d.is_dir() and repo_basename in d.name:
                candidates.append(d)

    if not candidates:
        sys.exit(f"no Claude transcript dir found for {repo_root}")

    # Pick the candidate with the newest .jsonl.
    def newest_mtime(d: Path) -> float:
        ts = [p.stat().st_mtime for p in d.glob("*.jsonl")]
        return max(ts) if ts else 0.0
    return max(candidates, key=newest_mtime)


def latest_session(project_dir: Path) -> Path:
    sessions = sorted(project_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
    if not sessions:
        sys.exit(f"no .jsonl files in {project_dir}")
    return sessions[-1]


# ── Render helpers ──────────────────────────────────────────────────
def render_content_blocks(blocks) -> str:
    """Render Anthropic message content blocks (list[dict]) to markdown."""
    if isinstance(blocks, str):
        return blocks
    if not isinstance(blocks, list):
        return f"_(unexpected content type {type(blocks).__name__})_"
    out: list[str] = []
    for b in blocks:
        if not isinstance(b, dict):
            out.append(str(b))
            continue
        t = b.get("type")
        if t == "text":
            out.append(b.get("text", ""))
        elif t == "thinking":
            txt = b.get("thinking", "").strip()
            if txt:
                out.append(f"<details><summary>💭 thinking</summary>\n\n```\n{txt}\n```\n\n</details>")
        elif t == "image":
            src = b.get("source", {})
            if src.get("type") == "base64":
                size = len(src.get("data", ""))
                out.append(f"_[image attached: {src.get('media_type','?')}, {size} b64 chars]_")
            else:
                out.append(f"_[image: {src!r}]_")
        elif t == "tool_use":
            name = b.get("name", "?")
            tool_input = b.get("input", {})
            # Show the tool input compactly. For long values, truncate.
            try:
                rendered = json.dumps(tool_input, indent=2, default=str)
            except Exception:
                rendered = str(tool_input)
            if len(rendered) > 4000:
                rendered = rendered[:4000] + f"\n... [truncated {len(rendered)-4000} chars]"
            out.append(f"**🔧 tool_use** `{name}`\n\n```json\n{rendered}\n```")
        elif t == "tool_result":
            content = b.get("content")
            if isinstance(content, list):
                # Each item may itself have {type:"text", text:...}
                parts = []
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "text":
                        parts.append(c.get("text", ""))
                    elif isinstance(c, dict) and c.get("type") == "image":
                        src = c.get("source", {})
                        size = len(src.get("data", "")) if isinstance(src, dict) else 0
                        parts.append(f"_[image returned: {size} b64 chars]_")
                    else:
                        parts.append(str(c))
                content_str = "\n".join(parts)
            else:
                content_str = str(content) if content is not None else ""
            is_err = b.get("is_error", False)
            tag = "❌ tool_result (error)" if is_err else "📤 tool_result"
            if len(content_str) > 4000:
                content_str = content_str[:4000] + f"\n... [truncated {len(content_str)-4000} chars]"
            out.append(f"**{tag}**\n\n```\n{content_str}\n```")
        else:
            out.append(f"_[unhandled block type {t!r}: {str(b)[:200]}]_")
    return "\n\n".join(out)


def render_event(d: dict) -> str | None:
    """Convert one JSONL line dict into a markdown chunk, or None to skip."""
    t = d.get("type")
    ts = d.get("timestamp", "")
    if t == "user":
        msg = d.get("message", {})
        body = render_content_blocks(msg.get("content"))
        return f"## 🧑 User — {ts}\n\n{body}\n"
    if t == "assistant":
        msg = d.get("message", {})
        body = render_content_blocks(msg.get("content"))
        return f"## 🤖 Assistant — {ts}\n\n{body}\n"
    if t == "system":
        sub = d.get("subtype", "")
        # Suppress noisy hook-stop telemetry; keep substantive system events.
        if sub in ("stop", "subagent_stop"):
            return None
        return f"### ⚙ System ({sub}) — {ts}\n"
    if t == "attachment":
        att = d.get("attachment", {})
        path = att.get("file_path") or att.get("path") or "?"
        return f"### 📎 Attachment — {ts}\n\n`{path}`\n"
    if t == "pr-link":
        return f"### 🔗 PR — {ts}\n\n{d.get('prUrl','?')}\n"
    if t == "last-prompt":
        return None  # internal book-keeping
    if t == "queue-operation":
        return None
    return None


# ── Main ────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--session", help="session id (without .jsonl)")
    ap.add_argument(
        "--out",
        default="Bloom&Burgle_ChatHistory.md",
        help="output .md path (relative to repo root)",
    )
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    project_dir = find_claude_project_dir(repo_root)
    if args.session:
        src = project_dir / f"{args.session}.jsonl"
        if not src.is_file():
            sys.exit(f"no such session at {src}")
    else:
        src = latest_session(project_dir)

    out_path = repo_root / args.out
    print(f"[export_history] reading: {src}")
    print(f"[export_history] writing: {out_path}")

    chunks: list[str] = [
        f"# Bloom & Burgle — Chat History\n",
        f"_Source: `{src}`_  ",
        f"_Exported: {os.popen('date -u +%FT%TZ').read().strip()}_\n",
        "---",
    ]
    last_uuid: str | None = None
    seen = 0
    rendered = 0
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
            block = render_event(d)
            if block is None:
                continue
            chunks.append(block)
            rendered += 1
            uid = d.get("uuid")
            if uid:
                last_uuid = uid

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n\n".join(chunks))

    # Pointer file used by append_history.py to skip already-exported lines.
    pointer_path = repo_root / "scripts" / "history" / ".last_uuid"
    if last_uuid:
        pointer_path.write_text(f"{src.name}\t{last_uuid}\n")

    size_kb = out_path.stat().st_size / 1024
    print(f"[export_history] {seen} events read, {rendered} rendered ({size_kb:.0f} KB)")
    if last_uuid:
        print(f"[export_history] pointer → {last_uuid[:8]}…")


if __name__ == "__main__":
    main()
