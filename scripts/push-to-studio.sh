#!/bin/bash
# push-to-studio.sh — push local Luau / .model.json files into Studio via MCP.
# Run on the Mac (host=node). Reads a manifest from stdin: each line is
#   <local_path>::<studio_dot_path>::<className>
# className is optional; if blank, the script must already exist in Studio.
set -euo pipefail
BRIDGE="${BRIDGE:-http://127.0.0.1:7878}"

push_one() {
    local local_path="$1"
    local studio_path="$2"
    local class_name="${3:-}"

    if [ ! -f "$local_path" ]; then
        echo "❌ missing local file: $local_path" >&2
        return 1
    fi

    local NEW_CONTENT
    NEW_CONTENT=$(cat "$local_path")

    # BAB-DEV: Always normalize the target Instance type FIRST.
    # If a previous sync left it as the wrong type (Folder), destroy + recreate.
    if [ -n "$class_name" ]; then
        local NORMALIZE_CODE
        NORMALIZE_CODE=$(python3 -c "
studio_path = '$studio_path'
class_name = '$class_name'
parts = studio_path.split('.')
assert parts[0] == 'game'
lines = ['local node = game:GetService(\\\"' + parts[1] + '\\\")']
for p in parts[2:-1]:
    lines.append('node = node:WaitForChild(\\\"' + p + '\\\")')
leaf = parts[-1]
lines.append('local existing = node:FindFirstChild(\\\"' + leaf + '\\\")')
lines.append('if existing and existing.ClassName ~= \\\"' + class_name + '\\\" then existing:Destroy() existing = nil end')
lines.append('if not existing then')
lines.append('  local m = Instance.new(\\\"' + class_name + '\\\")')
lines.append('  m.Name = \\\"' + leaf + '\\\"')
lines.append('  m.Parent = node')
lines.append('  return \\\"created\\\"')
lines.append('end')
lines.append('return \\\"ok\\\"')
print(chr(10).join(lines))
")
        local NORM_PAYLOAD
        NORM_PAYLOAD=$(jq -n --arg c "$NORMALIZE_CODE" '{method:"tools/call",params:{name:"execute_luau",arguments:{code:$c}},timeoutMs:10000}')
        curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$NORM_PAYLOAD" > /dev/null
    fi

    # Get current content (may fail if script doesn't exist yet)
    local READ_BODY
    READ_BODY=$(jq -n --arg t "$studio_path" '{method:"tools/call",params:{name:"script_read",arguments:{target_file:$t,should_read_entire_file:true}},timeoutMs:10000}')
    local READ_RESP
    READ_RESP=$(curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$READ_BODY")
    local CUR
    CUR=$(echo "$READ_RESP" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
ok = d.get('ok')
if not ok:
    sys.exit(2)
text = d['result']['content'][0]['text']
# Strip the LINE_NUMBER→ prefix from script_read output
out_lines = []
for line in text.split('\n'):
    m = re.match(r'^\s*\d+→', line)
    if m:
        out_lines.append(line[m.end():])
    else:
        out_lines.append(line)
sys.stdout.write('\n'.join(out_lines))
" 2>/dev/null) || CUR=""

    local EDITS_JSON
    if [ -z "$CUR" ]; then
        # New script
        if [ -z "$class_name" ]; then
            echo "❌ $studio_path missing and no className supplied" >&2
            return 1
        fi
        # BAB-011 fix: Studio MCP multi_edit ignores className for new scripts (creates Folder).
        # Pre-create the correct Instance type via execute_luau, THEN write source.
        local CREATE_CODE
        CREATE_CODE=$(python3 -c "
import sys
studio_path = '$studio_path'
class_name = '$class_name'
# studio_path looks like: game.ServerScriptService.PlantVisuals
parts = studio_path.split('.')
assert parts[0] == 'game'
# parent = game:GetService(parts[1]):FindFirstChild(parts[2]) ... etc
lines = ['local node = game:GetService(\\\"' + parts[1] + '\\\")']
for p in parts[2:-1]:
    lines.append('node = node:WaitForChild(\\\"' + p + '\\\")')
leaf = parts[-1]
lines.append('local existing = node:FindFirstChild(\\\"' + leaf + '\\\")')
lines.append('if existing and existing.ClassName ~= \\\"' + class_name + '\\\" then existing:Destroy() existing = nil end')
lines.append('if not existing then')
lines.append('  local m = Instance.new(\\\"' + class_name + '\\\")')
lines.append('  m.Name = \\\"' + leaf + '\\\"')
lines.append('  m.Parent = node')
lines.append('end')
lines.append('return \\\"ensured ' + leaf + ' as ' + class_name + '\\\"')
print(chr(10).join(lines))
")
        local CREATE_PAYLOAD
        CREATE_PAYLOAD=$(jq -n --arg c "$CREATE_CODE" '{method:"tools/call",params:{name:"execute_luau",arguments:{code:$c}},timeoutMs:10000}')
        curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$CREATE_PAYLOAD" > /dev/null
        # Now write source via multi_edit (script now exists with correct ClassName).
        EDITS_JSON=$(jq -n --arg n "$NEW_CONTENT" '{edits:[{old_string:"",new_string:$n}]}')
        local PAYLOAD
        PAYLOAD=$(jq -n --arg p "$studio_path" --arg c "$class_name" --argjson e "$EDITS_JSON" \
            '{method:"tools/call",params:{name:"multi_edit",arguments:{file_path:$p, className:$c, edits:$e.edits}},timeoutMs:15000}')
        curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$PAYLOAD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d.get('ok'): print('  ✅ created', '$studio_path')
else: print('  ❌', d); sys.exit(3)
"
    else
        # Replace whole script: edit old_string=CUR, new_string=NEW_CONTENT
        if [ "$CUR" = "$NEW_CONTENT" ]; then
            echo "  ⏭  unchanged: $studio_path"
            return 0
        fi
        EDITS_JSON=$(jq -n --arg o "$CUR" --arg n "$NEW_CONTENT" '{edits:[{old_string:$o,new_string:$n}]}')
        local PAYLOAD
        PAYLOAD=$(jq -n --arg p "$studio_path" --argjson e "$EDITS_JSON" \
            '{method:"tools/call",params:{name:"multi_edit",arguments:{file_path:$p, edits:$e.edits}},timeoutMs:15000}')
        curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$PAYLOAD" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d.get('ok'): print('  ✅ updated', '$studio_path')
else: print('  ❌', d); sys.exit(3)
"
    fi
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
    push_one "$LOCAL" "$STUDIO" "$CLASS"
done

echo "✨ done"
