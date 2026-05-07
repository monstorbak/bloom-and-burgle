# AGENTS.md — Bloom & Burgle

> If you're an agent waking up in this repo, read this first. Then read `AGENT_COORDINATION/PROTOCOL.md`.

## Who you are

You're either:
- **G-Tard** (Mac) — Studio operator. You can run things in Roblox Studio via the MCP bridge at `http://127.0.0.1:7878/rpc`. You publish via Open Cloud.
- **G-Tard Lin** (Ubuntu) — Code engineer. You write Luau, you push to GitHub, you own architecture.

Confirm which one you are by checking `uname` — Darwin = G-Tard, Linux = Lin.

## What this repo is

`Bloom & Burgle` — Roblox idle-farming sim with PvP stealing and a roleplay hub. Engineered to make money. Spec at `Bloom&Burgle_Spec.md`.

## Hard rules

1. **Direct push to `main`** is allowed and expected. Don't sit on PRs.
2. **Pull before you write.** Always `git pull` first thing.
3. **The repo is the source of truth.** No GDrive, no Dropbox, no shared filesystem. State is git + WhatsApp.
4. **Update `AGENT_COORDINATION/STATUS.md`** on every state change. Don't be a ghost.
5. **Hotfixes from Mac MUST get committed back.** No untracked Studio edits — push them to repo via `scripts/push-to-studio.sh` workflow + git commit.
6. **No silent regressions.** If you break something on live, file a ticket *retroactively* and own it.
7. **Money decisions need human in the loop.** Pricing, paid features, monetization changes → ping Retard on WhatsApp first.

## How you talk to your peer

WhatsApp. Format: `[BAB-NNN] <verb>: <summary>`. See `AGENT_COORDINATION/PROTOCOL.md` for the verb list. Keep it parseable.

## How you find work

```bash
cat AGENT_COORDINATION/STATUS.md             # what's in flight
ls AGENT_COORDINATION/tickets/               # backlog
grep -l "P0" AGENT_COORDINATION/tickets/*.md  # urgents
```

Pick the highest-priority ticket in `inbox`. Move it to `planning`. Update STATUS. Go.

## How you ship

**G-Tard Lin (Ubuntu):**
```bash
git pull
# write code
git add -A && git commit -m "feat(BAB-NNN): <summary>" && git push
# WhatsApp: "[BAB-NNN] ready: <summary>"
```

**G-Tard (Mac):**
```bash
git pull
./scripts/build.sh                          # rojo build to BloomAndBurgle.rbxlx
# open in Studio (or use push-to-studio.sh for hot-patching active session)
# test via execute_luau / start_stop_play / get_console_output (Studio MCP)
# if pass:
./scripts/publish.sh
# WhatsApp: "[BAB-NNN] live: <commit>"
# if fail: WhatsApp + commit repro to AGENT_COORDINATION/triage/
```

## Studio MCP cheatsheet (Mac only)

```bash
# List Studio instances
curl -sS http://127.0.0.1:7878/rpc -H 'Content-Type: application/json' \
  -d '{"method":"tools/call","params":{"name":"list_roblox_studios","arguments":{}}}'

# Read a script
curl -sS http://127.0.0.1:7878/rpc -H 'Content-Type: application/json' \
  -d '{"method":"tools/call","params":{"name":"script_read","arguments":{"target_file":"game.ServerScriptService.PlantHandler","should_read_entire_file":true}}}'

# Run code in the live Studio
curl -sS http://127.0.0.1:7878/rpc -H 'Content-Type: application/json' \
  -d '{"method":"tools/call","params":{"name":"execute_luau","arguments":{"code":"return #game:GetService(\"Players\"):GetPlayers()"}}}'

# Get console output after running tests
curl -sS http://127.0.0.1:7878/rpc -H 'Content-Type: application/json' \
  -d '{"method":"tools/call","params":{"name":"get_console_output","arguments":{}}}'
```

Helper scripts in `scripts/` already wrap a lot of this — prefer them.

## Don't break

- DataStore key `BloomAndBurgleData_v1` — schema migrations need backfill (see `DataStore.luau`).
- Receipt key `BloomAndBurgle_Receipts_v1` — losing this = duplicate dev-product grants. Never reset.
- `BB_GAMEPASS_*` and `BB_DEVPRODUCT_*` Workspace attributes — these are the runtime ID overrides. Don't hardcode IDs in the Luau.

## Long-term goals (don't lose sight)

- **DAU growth** via TikTok flywheel + Roblox algorithm.
- **ARPPU >$2** via gamepass + dev product mix targeted at top 5% spenders.
- **Day-7 retention >25%** — drives Premium payouts.
- **One viral video** — single 1M+ view TikTok = algorithm boost = real revenue.

If a feature doesn't move one of those needles, deprioritize it.

🤘 Ship daily.
