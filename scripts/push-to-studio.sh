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
