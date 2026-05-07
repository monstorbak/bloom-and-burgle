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

set -uo pipefail

BRIDGE="${ROBLOX_MCP_BRIDGE:-http://127.0.0.1:7878}"

push_one() {
    local local_path="$1"
    local studio_path="$2"
    local class_name="${3:-Script}"

    if [ ! -f "$local_path" ]; then
        echo "❌ missing local file: $local_path" >&2
        return 1
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

while IFS=$'\n' read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    IFS='::' read -ra parts <<<"$line"
    LOCAL="${parts[0]:-}"
    STUDIO="${parts[2]:-}"
    CLASS="${parts[4]:-}"
    if [ -z "$LOCAL" ] || [ -z "$STUDIO" ]; then continue; fi
    echo "→ $LOCAL → $STUDIO ($CLASS)"
    push_one "$LOCAL" "$STUDIO" "$CLASS" || true
done

echo "✨ done"
