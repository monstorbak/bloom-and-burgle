# AGENT_COORDINATION/PROTOCOL.md

> **Bloom & Burgle dev protocol — G-Tard (Mac) ⨯ G-Tard Lin (Ubuntu).**
> The repo is the source of truth. WhatsApp is the realtime bus.
> No GDrive — Mac doesn't auto-mirror it and Lin's Ubuntu can't reach it.

---

## 🤖 Agents

| Agent | Host | Role | What they own |
|---|---|---|---|
| **G-Tard** | Mac (this machine) | Studio operator + publisher | Roblox Studio MCP bridge (`http://127.0.0.1:7878/rpc`), live console watching, build + publish via Open Cloud, hotfix authority, screen capture for repros |
| **G-Tard Lin** | Ubuntu Linux | Code engineer + marketer | Primary Luau author, architecture, marketing copy, TikTok scripts, backlog grooming, PR-style commits |

Both push **direct to `main`**. No PR review gate. We trust the loop.

---

## 🔁 The Dev Loop

```
Lin writes feature on branch  →  pushes to main
                                       │
                                       ▼
   Lin pings G-Tard on WhatsApp:  "[BAB-NNN] ready to test"
                                       │
                                       ▼
G-Tard pulls → builds → opens in Studio → execute_luau / start_stop_play
                                       │
                       ┌───────────────┴────────────────┐
                       ▼                                ▼
                    PASS                              FAIL
                       │                                │
                       ▼                                ▼
            scripts/publish.sh           screen_capture + console excerpt
            (live to Roblox)             pasted to WhatsApp + commit to
                                         AGENT_COORDINATION/triage/
                       │                                │
                       ▼                                ▼
       WhatsApp: "BAB-NNN merged + live"       WhatsApp: "BAB-NNN repro attached"
```

---

## 📋 Tickets

Tickets live in `AGENT_COORDINATION/tickets/BAB-NNN.md`. Filename format: `BAB-NNN-short-slug.md`.

### Ticket lifecycle
1. **inbox** — filed but no owner
2. **planning** — owner reasoning about approach
3. **in-progress** — actively being coded
4. **in-review** — implementer asking for testing
5. **testing** — G-Tard running it in Studio
6. **done** — merged + live (or wontfix with reason)

State changes go in the ticket file. Each transition adds a dated bullet.

### Ticket file shape

```markdown
# BAB-NNN: <title>

**Owner:** G-Tard | G-Tard Lin
**State:** inbox | planning | in-progress | in-review | testing | done
**Priority:** P0 | P1 | P2
**Files touched:** src/ServerScriptService/Foo.luau

## Problem

(what's broken or missing)

## Approach

(how we fix it)

## Acceptance

- [ ] criterion 1
- [ ] criterion 2

## Log

- 2026-05-06 — G-Tard filed
- 2026-05-06 — Lin claimed, planning
```

---

## 🧷 STATUS.md

`AGENT_COORDINATION/STATUS.md` is the live "who's doing what right now" board. Both agents update it on every state change. Format kept tiny on purpose:

```
G-Tard:    BAB-003 testing  (Studio open, running plot-claim repro)
G-Tard Lin: BAB-007 in-progress  (DataStore plant persistence)

Last live publish: BAB-002 @ 2026-05-07 14:22
Place ID: 82054981653891  (live + beta, single env for now)
```

Stale state (>2h no update while in `in-progress`) → other agent pings on WhatsApp.

---

## 📨 WhatsApp message format

Keep it **machine-parseable** so we can scan history fast.

```
[BAB-NNN] <verb>: <one-line summary>
```

Verbs we use:
- `claim` — taking the ticket
- `plan` — sharing approach (link to ticket)
- `ready` — asking the other agent to test/review/publish
- `pass` — testing succeeded
- `fail` — testing failed (attach console + screenshot)
- `live` — published to Roblox
- `block` — stuck, need help
- `q` — question

**Examples:**
- `[BAB-003] ready: SellPad fix on main, please test`
- `[BAB-003] fail: console says GetInstanceAddedSignal nil — repro in triage/BAB-003-fail-1.txt`
- `[BAB-003] live: published v0.2.1 at 14:22`

Anything that doesn't fit a ticket → freeform, but try to ticket-ify within an hour.

---

## 🔧 Build + publish cheatsheet (Mac side)

```bash
cd /Users/nickanthony/Dev/bloom-and-burgle
git pull
./scripts/build.sh                                       # → BloomAndBurgle.rbxlx
./scripts/push-to-studio.sh < /path/to/manifest.txt      # push specific files into open Studio session
./scripts/publish.sh                                     # publish .rbxlx to live
```

For Studio MCP RPC (Mac local):
```bash
curl -sS http://127.0.0.1:7878/rpc -H 'Content-Type: application/json' \
  -d '{"method":"tools/call","params":{"name":"get_console_output","arguments":{}}}'
```

---

## 🚨 Escalation rules

- **Game-breaking on live** → G-Tard publishes a hotfix immediately, opens BAB-NNN-hotfix-* ticket retroactively, pings Lin "live broken, fixed at <commit>".
- **Spec ambiguity** → ticket goes to `inbox` with `state: blocked`, WhatsApp the human (Retard).
- **Money flow / monetization decisions** → always loop in human before changing pricing or adding paid features.
- **Disagreement between agents** → human is tiebreaker. Don't loop forever.

---

## 🌳 Branching

- `main` is the live code. Both agents commit directly.
- Big risky refactors → feature branch (`feat/<slug>`), merge in one squash commit when ticket is `done`.
- Tag releases as `v0.X.Y` when we publish a notable milestone.

---

## 🔄 Sync ritual (every session start)

Both agents, before doing anything:
1. `git fetch && git log --oneline origin/main..HEAD origin/main` — what's new
2. `cat AGENT_COORDINATION/STATUS.md` — what's in flight
3. `ls AGENT_COORDINATION/tickets/` — backlog state
4. WhatsApp scrollback (last 30 messages) — realtime context

Then work.

---

🤘 Ship daily. No perfection. Money first, polish second.
