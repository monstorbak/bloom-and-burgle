#!/bin/bash
# studio-rpc.sh — call the Mac-side Studio MCP bridge from Linux.
# Usage: ./studio-rpc.sh <method> '<json-args>'
# Examples:
#   ./studio-rpc.sh execute_luau '{"code":"return 1+1"}'
#   ./studio-rpc.sh get_console_output '{}'
#   ./studio-rpc.sh search_game_tree '{"path":"Workspace"}'
set -euo pipefail
METHOD="${1:-execute_luau}"
ARGS="${2:-{}}"
PAYLOAD=$(jq -n --arg m "$METHOD" --argjson a "$ARGS" '{method:"tools/call", params:{name:$m, arguments:$a}, timeoutMs:20000}')
curl -sS -X POST http://127.0.0.1:7878/rpc -H "Content-Type: application/json" -d "$PAYLOAD"
