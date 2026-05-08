#!/usr/bin/env bash
# push-to-studio.sh — sync local script files into running Roblox Studio via MCP.
#
# Reads stdin lines: <localPath>::<studioPath>::<className>
# Example: src/ServerScriptService/PlantHandler.server.luau::game.ServerScriptService.PlantHandler::Script
#
# Strategy (BAB-DEV-2 — guaranteed clean replacement):
#   1. Destroy any existing instance at studioPath
#   2. Create fresh Instance.new(className) with that name
#   3. Write source via multi_edit with old_string="" (now actually empty)
#
# This avoids the "phantom append" bug where multi_edit sometimes concatenated
# new content onto stale source instead of replacing it, leading to scripts
# that contained TWO copies of themselves with conflicting logic.
#
# ── P1.4 (Architecture Eval §8/§9) ──────────────────────────────────────────
# Play-mode safety: this script destroys + recreates instances. During Play,
# that severs every RemoteEvent / Heartbeat connection the live server-side
# Script had open. The eval doc (Bloom&Burgle_Architecture_Eval.md §8/§9)
# names `rojo serve` as the canonical Edit-time sync; this tool is for
# hot-patching only.
#
#   - In Edit mode: behaves as before.
#   - In Play mode + Script (server) target: refuses with a pointer to
#     `rojo serve` unless --force is passed.
#   - In Play mode + LocalScript target: warns but proceeds (client scripts
#     get re-instanced cleanly on the next character spawn).
#   - In Play mode + ModuleScript target: proceeds silently (consumers cache
#     their require() result, so the change won't take effect until the next
#     Play session anyway — but no connections are severed).
#   - If the bridge is unreachable for the probe: refuses (fail-closed) unless
#     --force is passed.
#
# Override: pass `--force` as the first arg to bypass the safety. Use ONLY
# for the rare case where you genuinely want to live-patch a server script
# during Play and accept the connection-loss consequences.
#
# Test override: --skip-probe assumes Edit mode without contacting the bridge.
# Used only by scripts/push-to-studio.test.sh.

set -uo pipefail

BRIDGE="${ROBLOX_MCP_BRIDGE:-http://127.0.0.1:7878}"

FORCE=0
SKIP_PROBE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --skip-probe) SKIP_PROBE=1; shift ;;
        *) break ;;
    esac
done

# ── Play-mode probe ────────────────────────────────────────────────────────
# One-shot RunService:IsRunning() check. Cached for the rest of the run.
# IS_PLAY values: "0" (Edit) | "1" (Play) | "?" (probe failed).
probe_play_mode() {
    local probe_code='return game:GetService("RunService"):IsRunning() and "play" or "edit"'
    local payload
    payload=$(jq -n --arg c "$probe_code" '{method:"tools/call",params:{name:"execute_luau",arguments:{code:$c}},timeoutMs:5000}')
    local resp
    resp=$(curl -sS --max-time 6 -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$payload" 2>/dev/null)
    if [ -z "$resp" ]; then
        echo "?"
        return
    fi
    local mode
    mode=$(echo "$resp" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('result',{}).get('content',[{}])[0].get('text','?'))
except Exception:
    print('?')" 2>/dev/null)
    case "$mode" in
        play) echo "1" ;;
        edit) echo "0" ;;
        *) echo "?" ;;
    esac
}

if [ "$SKIP_PROBE" = "1" ]; then
    IS_PLAY="0"
else
    IS_PLAY="$(probe_play_mode)"
fi

case "$IS_PLAY" in
    0) ;; # Edit mode — proceed silently.
    1)
        echo "🎮 Studio is in Play mode."
        if [ "$FORCE" = "1" ]; then
            echo "   --force passed; proceeding anyway. Server-script connections WILL be severed."
        fi
        ;;
    \?)
        if [ "$FORCE" = "1" ]; then
            echo "⚠️  Studio Play-mode probe failed; --force passed, proceeding." >&2
        else
            echo "❌ Couldn't reach the Studio MCP bridge at $BRIDGE to verify Play state." >&2
            echo "   Refusing to push (fail-closed). Options:" >&2
            echo "   - Start Roblox Studio with the MCP bridge running." >&2
            echo "   - Use 'rojo serve' for the dev loop instead (recommended)." >&2
            echo "   - Re-run with --force to bypass the probe and push anyway." >&2
            exit 3
        fi
        ;;
esac

push_one() {
    local local_path="$1"
    local studio_path="$2"
    local class_name="${3:-Script}"

    if [ ! -f "$local_path" ]; then
        echo "❌ missing local file: $local_path" >&2
        return 1
    fi

    # Play-mode guard: refuse server scripts unless --force.
    if [ "$IS_PLAY" = "1" ] && [ "$FORCE" != "1" ]; then
        case "$class_name" in
            Script)
                echo "  ❌ refusing to sync $studio_path during Play." >&2
                echo "     Server Scripts can't be hot-reloaded — destroy+recreate severs every" >&2
                echo "     RemoteEvent and Heartbeat connection the live server has open." >&2
                echo "     Stop Play first, or use 'rojo serve' for the live-sync dev loop," >&2
                echo "     or pass --force to bypass (you accept the consequences)." >&2
                return 2
                ;;
            LocalScript)
                echo "  ⚠️  syncing LocalScript $studio_path during Play; client connections may break on respawn."
                ;;
        esac
    fi

    local NEW_CONTENT
    NEW_CONTENT=$(cat "$local_path")

    # Step 1: Destroy + recreate the target Instance fresh. This guarantees a
    # clean slate. We always do this — never try to "edit in place" because the
    # MCP multi_edit tool has subtle bugs with empty/stale source.
    local RESET_CODE
    RESET_CODE=$(python3 -c "
studio_path = '$studio_path'
class_name = '$class_name'
parts = studio_path.split('.')
assert parts[0] == 'game'
lines = ['local node = game:GetService(\\\"' + parts[1] + '\\\")']
for p in parts[2:-1]:
    lines.append('node = node:WaitForChild(\\\"' + p + '\\\")')
leaf = parts[-1]
lines.append('local existing = node:FindFirstChild(\\\"' + leaf + '\\\")')
lines.append('if existing then existing:Destroy() end')
lines.append('local m = Instance.new(\\\"' + class_name + '\\\")')
lines.append('m.Name = \\\"' + leaf + '\\\"')
lines.append('m.Parent = node')
lines.append('return \\\"reset \\\" .. \\\"' + leaf + '\\\"')
print(chr(10).join(lines))
")
    local RESET_PAYLOAD
    RESET_PAYLOAD=$(jq -n --arg c "$RESET_CODE" '{method:"tools/call",params:{name:"execute_luau",arguments:{code:$c}},timeoutMs:10000}')
    local RESET_RESP
    RESET_RESP=$(curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$RESET_PAYLOAD")
    if ! echo "$RESET_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
        echo "  ❌ reset failed for $studio_path: $RESET_RESP" >&2
        return 1
    fi

    # Step 2: Write source via multi_edit. The script is now empty, so
    # old_string="" is a valid "insert at beginning" operation.
    local EDITS_JSON
    EDITS_JSON=$(jq -n --arg n "$NEW_CONTENT" '{edits:[{old_string:"",new_string:$n}]}')
    local PAYLOAD
    PAYLOAD=$(jq -n --arg p "$studio_path" --arg c "$class_name" --argjson e "$EDITS_JSON" \
        '{method:"tools/call",params:{name:"multi_edit",arguments:{file_path:$p, className:$c, edits:$e.edits}},timeoutMs:30000}')
    local RESP
    RESP=$(curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$PAYLOAD")

    # Step 3: Verify by reading back size from Studio
    local EXPECTED
    EXPECTED=${#NEW_CONTENT}
    local VERIFY_CODE
    VERIFY_CODE=$(python3 -c "
studio_path = '$studio_path'
parts = studio_path.split('.')
lines = ['local node = game:GetService(\\\"' + parts[1] + '\\\")']
for p in parts[2:-1]:
    lines.append('node = node:WaitForChild(\\\"' + p + '\\\")')
leaf = parts[-1]
lines.append('local x = node:FindFirstChild(\\\"' + leaf + '\\\")')
lines.append('if not x then return \\\"missing\\\" end')
lines.append('if not x:IsA(\\\"LuaSourceContainer\\\") then return \\\"wrongtype:\\\" .. x.ClassName end')
lines.append('return tostring(#x.Source)')
print(chr(10).join(lines))
")
    local VERIFY_PAYLOAD
    VERIFY_PAYLOAD=$(jq -n --arg c "$VERIFY_CODE" '{method:"tools/call",params:{name:"execute_luau",arguments:{code:$c}},timeoutMs:10000}')
    local VERIFY_RESP
    VERIFY_RESP=$(curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$VERIFY_PAYLOAD")
    local STUDIO_SIZE
    STUDIO_SIZE=$(echo "$VERIFY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('content',[{}])[0].get('text','?'))" 2>/dev/null)

    # Tolerate small drift (line ending normalization in Roblox Studio).
    # Hard fail only if Studio is empty or vastly smaller than expected.
    if [ "$STUDIO_SIZE" = "missing" ] || [ "$STUDIO_SIZE" = "?" ] || [[ "$STUDIO_SIZE" == wrongtype:* ]]; then
        echo "  ❌ sync failed: studio=$STUDIO_SIZE for $studio_path" >&2
        return 1
    fi
    if [ "$STUDIO_SIZE" -lt $((EXPECTED / 2)) ] 2>/dev/null; then
        echo "  ❌ content too small: expected ~$EXPECTED studio=$STUDIO_SIZE for $studio_path" >&2
        return 1
    fi
    echo "  ✅ synced $studio_path (local=$EXPECTED studio=$STUDIO_SIZE)"
}

REFUSED=0
while IFS=$'\n' read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    IFS='::' read -ra parts <<<"$line"
    LOCAL="${parts[0]:-}"
    STUDIO="${parts[2]:-}"
    CLASS="${parts[4]:-}"
    if [ -z "$LOCAL" ] || [ -z "$STUDIO" ]; then continue; fi
    echo "→ $LOCAL → $STUDIO ($CLASS)"
    push_one "$LOCAL" "$STUDIO" "$CLASS"
    rc=$?
    if [ "$rc" = "2" ]; then
        REFUSED=$((REFUSED + 1))
    fi
done

if [ "$REFUSED" -gt 0 ]; then
    echo "✋ done — $REFUSED file(s) refused (Play-mode + Script). Stop Play and re-run, or pass --force." >&2
    exit 2
fi

echo "✨ done"
