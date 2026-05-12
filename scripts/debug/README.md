# `scripts/debug/dbg` — Live Studio Debug Toolkit

A bash CLI for poking at a running Roblox Studio session from the terminal.
Lets you (or a Claude session) inspect game state, run Luau, take
screenshots, hot-sync code, and probe end-to-end flows without clicking
through Studio's UI.

**Reader:** anyone working on BAB who wants to verify a fix in-game, write
a regression check, or diagnose a live bug.

---

## TL;DR

```bash
./scripts/debug/dbg health           # is Studio reachable?
./scripts/debug/dbg activate         # claim it as the active target
./scripts/debug/dbg state            # snapshot of players + plots + pads
./scripts/debug/dbg eval 'return ...'   # run Luau, get the return value
./scripts/debug/dbg shot screenshot-name
./scripts/debug/dbg sync src/ServerScriptService/Foo.luau
```

Add `scripts/debug/` to your `PATH` for this shell to drop the prefix:

```bash
export PATH="$PWD/scripts/debug:$PATH"
dbg health
```

---

## How it works

There are three actors:

1. **Roblox Studio** — running on this Mac, with the **StudioMCP** plugin
   loaded. The plugin opens a local socket and exposes Studio's APIs as
   MCP tool calls.
2. **`StudioMCP` bridge binary** — `/Applications/RobloxStudio.app/...`. Runs
   on boot, listens on `127.0.0.1:7878`, routes JSON-RPC over to whichever
   Studio instance is "active".
3. **`dbg` CLI** — bash + a thin python helper. Calls the bridge over
   `curl POST /rpc`, parses the JSON-RPC response, pretty-prints.

```
┌─────────────┐    JSON-RPC    ┌──────────────┐   IPC    ┌─────────────┐
│  dbg <cmd>  │ ─────────────► │  StudioMCP   │ ───────► │ Roblox      │
│   (bash)    │ ◄───────────── │  bridge      │ ◄─────── │ Studio      │
└─────────────┘   {ok, ...}    └──────────────┘          │ (plugin)    │
                                  127.0.0.1:7878         └─────────────┘
```

Bridge env vars (overridable per-call):
- `BAB_BRIDGE` — default `http://127.0.0.1:7878`
- `BAB_TIMEOUT_MS` — default 15000

---

## Commands

### `health`

Verifies the bridge is up + a Studio is connected + one is "active".

```
✔ Studio active: Bloom & Burgle              # all good
⚠ Studio connected but none active. Run: dbg activate
✘ no Studio instances connected              # open Studio
✘ bridge unreachable at http://127.0.0.1:7878 # plugin not running
```

Run this **first** in any new shell. If it fails, nothing else will work.

### `activate [name]`

When multiple Studio windows are open (rare), pick one as the target.
`name` is a case-insensitive substring match. Omit to pick the first.

```bash
dbg activate Bloom        # match "Bloom & Burgle"
dbg activate              # first match
```

### `console [N]` / `errors [N]` / `tail [secs]`

Read Studio's Output console.

| Command | Use case |
|---|---|
| `console 60` | Last 60 lines, all severities |
| `errors 30` | Filtered to error/warn/stack-trace tokens |
| `tail 2` | Stream new errors every 2s until Ctrl-C |

The console buffer is bounded by Studio. Stale entries from prior Play
sessions may still appear — check timestamps if you're chasing freshness.

### `eval <luau>` / `evalf <file>`

Execute Luau. The snippet should `return` a value so you see the result.

```bash
dbg eval 'return #game:GetService("Players"):GetPlayers()'
dbg eval 'workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable; return "ok"'
dbg evalf scripts/debug/snippets/dump-stash.lua
```

#### 🚨 Critical gotcha: `eval` runs in **client context, not server**

The MCP plugin executes the snippet inside Roblox Studio's **Assistant**
sandbox, which has client-side privileges. This is the single biggest
foot-gun in this toolkit.

What that means in practice:

✅ **Allowed:**
- Read `Workspace`, `ReplicatedStorage`, `Players` — anything globally
  visible
- Read attributes, properties, CFrames
- Modify Workspace parts (Anchored, Position, Color, Transparency, …)
- Force `RemoteEvent:FireServer(...)` (because the client *can* fire to
  the server)
- Require ModuleScripts in `ReplicatedStorage`

❌ **Will error:**
- `RemoteEvent:FireClient(player, ...)` →
  `FireClient can only be called from the server`
- Reading `Players.LocalPlayer` (no localplayer in this context — you
  may see `nil`)
- Requiring `ServerScriptService` ModuleScripts —
  `XYZ is not a valid member of ServerScriptService`
- Writing to `ServerStorage`

The workaround for "I need to do something server-side" is usually:
1. **Trigger server logic via a RemoteEvent the server listens on.**
   E.g. instead of calling `CritterVisuals.markRipe(...)` (server module),
   `:SetAttribute("PlantedAt", os.time() - 100)` on a Planter — the
   server's Heartbeat loop will pick it up.
2. **Set Workspace attributes** that server scripts watch. E.g.
   `Workspace:SetAttribute("DevMode", true)`.
3. **Use chat commands** the server registered (see `DevMode.luau` —
   `/forcemutation`, `/testmythic`, etc).

#### Other gotchas

- Long expressions: pass via `evalf` rather than `eval` to avoid shell
  quoting hell.
- The `string.format` `%s` / `%d` mismatch is a classic — keep snippets
  small or test them locally first.
- A snippet that doesn't `return` anything echoes empty output.

### `state`

JSON snapshot of game state. Pretty-printed. Includes:

- `players[]` — name, userId, cash, plotClaimed, plotSlot, harvest count,
  multiplier
- `plots[]` — by name + descendant count
- `sellPads[]` — owner, position, sensor wired flag
- `planters` — counts: planted / ripe / empty
- `recentErrors` — if `DebugHooks.server.luau` registered `_G.BabDebug`

Cheap and side-effect-free. Run this whenever you need to know "what's
going on in the world right now."

### `tree [path] [depth]` / `inspect <path>`

Walk the DataModel.

```bash
dbg tree Workspace 3
dbg tree game.ReplicatedStorage.Modules 2
dbg inspect workspace.TrophyHall.HallOfSales
```

`tree` is a wrapper for `search_game_tree`. `inspect` shows properties +
children of a single instance. Both pipe through `maybe_json` so structured
output stays readable.

### `play start|stop|status`

Toggle Play mode.

```bash
dbg play start    # boots the server + spawns a player
dbg play stop     # tears down; back to Edit mode
dbg play status   # returns "true" or "false"
```

`dbg play stop` is critical before syncing server scripts — see the
`sync` gotcha below.

### `shot [name]`

Take a screenshot. Saves to `scripts/debug/captures/<name>.png`. If `name`
is omitted, uses `shot-<timestamp>`.

```bash
dbg shot trophy-hall
dbg shot                       # auto-named
```

Captures the active viewport — the Edit-mode camera if not playing, the
player's camera (or the scripted camera you set via eval) if playing.

To frame a specific shot, override the camera first:

```bash
dbg eval '
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.new(Vector3.new(0, 14, 70), Vector3.new(0, 10, 100))
return "camera positioned"
'
dbg shot wide-trophy-hall
dbg eval 'workspace.CurrentCamera.CameraType = Enum.CameraType.Custom; return "restored"'
```

### `nav <x> <y> <z>` / `nav-to <path>`

Move the LocalPlayer's character.

```bash
dbg nav 0 5 100
dbg nav-to workspace.TrophyHall.HallOfSales
```

⚠ Returns `RPC timeout` for long paths but the move usually still
completes — check the screenshot or `state` to confirm.

⚠ If you anchor the HumanoidRootPart from eval, you have to manually
un-anchor it for input to resume working.

### `key <KeyCode>`

Send a single key press to the running game (e.g. to trigger a custom
keybind).

```bash
dbg key F5
dbg key E
```

⚠ This is real input — if Studio's window isn't focused, the input may
go elsewhere. Don't `dbg key F5` while Studio is in Edit mode; you'll
accidentally start Play mode.

### `sync <relative-path>`

Hot-push a single Luau file from `src/` into the running Studio session,
without rebuilding the whole project.

```bash
dbg sync src/ServerScriptService/CritterVisuals.luau
dbg sync src/StarterPlayerScripts/FriendsListHUD.client.luau
dbg sync src/ReplicatedStorage/Modules/CritterData.luau
```

Path-to-instance mapping:

| Filesystem | Studio path | Class |
|---|---|---|
| `src/ServerScriptService/Foo.server.luau` | `game.ServerScriptService.Foo` | `Script` |
| `src/ServerScriptService/Foo.luau` | `game.ServerScriptService.Foo` | `ModuleScript` |
| `src/StarterPlayerScripts/Bar.client.luau` | `game.StarterPlayer.StarterPlayerScripts.Bar` | `LocalScript` |
| `src/ReplicatedStorage/Modules/Baz.luau` | `game.ReplicatedStorage.Modules.Baz` | `ModuleScript` |

#### 🚨 Critical gotchas for `sync`

1. **Only `src/` paths work.** `src-marketplace/` and `src-corridors/`
   error out — those are separate Place files, not loaded into the
   active Studio session.
2. **Server scripts in Play mode refuse to sync.** You'll see:
   > Server Scripts can't be hot-reloaded — destroy+recreate severs
   > every RemoteEvent and Heartbeat connection the live server has open.
   > Stop Play first, or use 'rojo serve' for the live-sync dev loop,
   > or pass --force to bypass (you accept the consequences).

   Workflow: `dbg play stop` → `dbg sync ...` → `dbg play start`.
3. **`local=N studio=N` confirms success.** Mismatch (`local=N studio=0`)
   means the sync failed — usually because Studio destroyed the script
   on Stop Play but reattached the old version on Start Play. Stop again,
   sync, then start.
4. **`sync` does NOT publish to Roblox.** It only updates the local Studio
   session. To make changes visible to players, you also need to
   `publish.sh` (CLI build → Open Cloud upload) or **File → Publish to
   Roblox** from inside Studio.

#### When `sync` vs `publish.sh` vs Studio's File→Publish

| Goal | Tool |
|---|---|
| Test a code change in my own Studio Play session | `dbg sync` |
| Make a code change visible to live players | `bash scripts/publish.sh` |
| Push Studio's current session (including in-Studio edits) to live | Studio → File → Publish to Roblox |

**Important:** Studio's File→Publish uploads from Studio's session state,
**not** from the git repo on disk. If git is ahead, `git pull` doesn't
update Studio — you have to `dbg sync` each changed file, or close Studio
and reopen the `.rbxlx` you built. We've been bitten by this enough times
to call it out.

### `sell-test`

End-to-end regression probe for the sell-pad flow:

1. Picks the first empty owned planter.
2. Forges its attributes to "ripe sunbloom now."
3. Teleports the player onto the planter (Touched → harvest).
4. Teleports the player onto the sell pad (Touched → cash payout).
5. Reports the cash delta.

```bash
dbg sell-test
```

Outputs JSON with `steps[]` and `success: true/false`. Run this after any
change to PlantHandler / HarvestFlow / SellPad / leaderstats to verify
nothing regressed.

### `bug-report`

Auto-collect everything (state + console + errors + workspace tree +
screenshot) into a timestamped dated directory:

```bash
dbg bug-report
# ✔ scripts/debug/captures/report-20260511-141522/
```

Use when you need to share a snapshot of a live issue — paste the
directory into the bug ticket.

### `help`

Print the command list (the top of the `dbg` script itself).

---

## Common workflows

### "I changed a file and want to see the effect in Studio"

```bash
dbg play stop                                           # if needed
dbg sync src/ServerScriptService/MyModule.luau
dbg play start
# observe in Studio
```

### "I want to take a clean screenshot of an in-world feature"

```bash
dbg play start
sleep 5                                                  # let scripts boot
dbg eval '
  local cam = workspace.CurrentCamera
  cam.CameraType = Enum.CameraType.Scriptable
  cam.CFrame = CFrame.new(Vector3.new(0, 14, 70), Vector3.new(0, 10, 100))
  return "camera set"
'
dbg shot my-feature-name
```

### "Something broke and I need to know what"

```bash
dbg bug-report           # snapshot everything
dbg errors 50            # see what's red recently
dbg tail 1               # watch for new errors as you reproduce
```

### "I want to verify a server module loaded correctly"

```bash
# Module ScriptService modules aren't requireable from eval (client
# context). Instead, check for the module's side effect.
dbg eval '
local svc = workspace:FindFirstChild("TrophyHall")
if not svc then return "module did not run" end
return "TrophyHall present, children=" .. #svc:GetChildren()
'

# Or grep the console for the modules boot log:
dbg console 200 | grep "BAB-LIFE.*TrophyHall"
```

### "I want to test the visit-friend or marketplace flow"

These require a second Studio + Play session, OR teleporting between
published places. The bridge is single-session — `dbg` can only see one
Studio at a time. For cross-place flows, publish a debug build and test
in the real Roblox client.

---

## Architecture notes

### Why `bridge_text` / `bridge_eval` / `bridge_call` in `lib.sh`?

Three layers because different bridge tools return different shapes:

- `bridge_call` — raw JSON-RPC. Used for `screen_capture` which returns
  a binary image content block.
- `bridge_text` — extracts `result.content[0].text` (the common case).
- `bridge_eval` — wraps `execute_luau` so callers don't have to JSON-
  encode the snippet manually.

### Why `sync` shells out to `push-to-studio.sh`?

Historical. The Lua-path-to-Studio-path mapping is done inline in `dbg`
(in python). The actual instance creation + property writing is done by
the older `push-to-studio.sh`, which predates this toolkit. Consolidating
them is a TODO.

### Why isn't there a `republish-from-studio` command?

Studio's File→Publish to Roblox is keyboard-only (not exposed via the
MCP plugin's tool surface). The Open Cloud API path (`scripts/publish.sh`)
hits a different endpoint and frequently conflicts with Studio's session
lock — see CLAUDE.md for the known pattern.

If the Open Cloud publish keeps Conflicting:
1. Save Studio (Ctrl+S).
2. Run `dbg sync` for each changed file so Studio matches disk.
3. **Manually** publish from Studio (Alt+P / Cmd+Alt+P).

---

## Maintenance

This doc reflects the toolkit as of 2026-05-11. When commands are added,
update the `Commands` section. When new gotchas are discovered, add them
to the per-command section — don't let the gotcha get rediscovered by
the next Claude session.
