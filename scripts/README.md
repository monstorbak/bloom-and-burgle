# scripts/

Helper scripts. The Roblox-side tooling has three sync paths — using the
wrong one leads to silent breakage. Read this before reaching for any of
them.

## Sync paths — quick reference

| Path | When to use | Caveats |
|---|---|---|
| **`rojo serve default.project.json`** | **Canonical Edit-mode dev loop.** | Live file-watch. Handles `.model.json`. Click "Connect" in the Rojo Studio plugin. |
| **`scripts/push-to-studio.sh`** | One-off hot-patch in Edit mode. | Destroy+recreate. Refuses server `Script`s during Play. No `.model.json` support. |
| **`scripts/build.sh` + open `.rbxlx`** | First-time setup, full rebuild, anything touching `.model.json`. | Heavy. Close Studio first. |

If you're not sure: **use `rojo serve`**. It's the standard Roblox-tooling
path and the one new contributors should learn first.

## scripts/push-to-studio.sh

Reads `<localPath>::<studioPath>::<className>` lines from stdin. For each,
destroys the target Instance and recreates it with the local file's
contents.

**Play-mode safety (P1.4 / Architecture Eval §8/§9):** the script probes
`RunService:IsRunning()` once at startup via the MCP bridge, then:

- **Edit mode** → behaves as before.
- **Play mode + `Script` (server)** → **refused** with exit 2 and a pointer
  to `rojo serve`. Destroy+recreate severs every RemoteEvent and Heartbeat
  connection the live server has open. Pass `--force` to bypass.
- **Play mode + `LocalScript`** → warns and proceeds (client connections
  may break on respawn).
- **Play mode + `ModuleScript`** → proceeds silently. Consumers cache
  their `require()` result; the change won't take effect until the next
  Play session, but no connections sever.
- **Bridge unreachable** → refused (fail-closed) with exit 3 unless
  `--force` is passed.

Flags (must come before stdin):

```bash
--force        # Bypass Play-mode and bridge-down safety. Use only if you
               # genuinely want to live-patch a server script during Play
               # and accept the consequences.
--skip-probe   # Assume Edit mode without contacting the bridge. Used by
               # the test harness (push-to-studio.test.sh).
```

Example usage (canonical — single Lua script, Edit mode):

```bash
echo "src/ServerScriptService/Critter/GrowLoop.server.luau::game.ServerScriptService.Critter.GrowLoop::Script" \
    | scripts/push-to-studio.sh
```

Example with `--force` (rare — live server-script patch during Play):

```bash
scripts/push-to-studio.sh --force <<<"src/ServerScriptService/Critter/GrowLoop.server.luau::game.ServerScriptService.Critter.GrowLoop::Script"
```

## scripts/push-to-studio.test.sh

Runs five scenarios against a mocked MCP bridge:

1. Edit + `Script` → success
2. Play + `Script` → refused (exit 2)
3. Play + `Script` + `--force` → success
4. Play + `LocalScript` → success with warning
5. Bridge unreachable → refused (exit 3)

Self-contained. Run it directly:

```bash
bash scripts/push-to-studio.test.sh
```

No Studio install required. Used as the regression check whenever
push-to-studio.sh changes.

## scripts/build.sh

`rojo build -o BloomAndBurgle.rbxlx` plus a pre-build material-discipline
check (CI gate against banned materials per design spec §1.5).

## scripts/publish.sh / scripts/publish-retry.sh

Open Cloud publish to live (Roblox API). Mantle is in `rokit.toml` for
legacy compatibility but its `import` is broken upstream — use
`publish.sh` for actual deploys.

## scripts/history/

Persistent chat-history mirror + RLM-powered query. See
`scripts/history/README.md`.

## scripts/debug/

`dbg` — Roblox runtime introspection CLI (errors, services, sample state).
Uses `_G.BabDebug` from `DebugHooks.server.luau`. Anything you create via
`dbg eval` must be committed to disk before merge or it disappears on the
next Studio restart.
