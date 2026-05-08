#!/usr/bin/env bash
# scripts/debug/lib.sh — shared bridge wrapper for the dbg toolkit.
# Sourced by every dbg subcommand. Defines:
#   bridge_call <method> <json-args>   → raw JSON RPC, prints {ok, result|error}
#   bridge_text <method> <json-args>   → extracts result.content[0].text (most tools)
#   bridge_eval <luau-code>            → execute_luau, returns the function result
#   bridge_ok? <json-rpc-response>     → exit 0 if ok=true
#   die <msg>                          → stderr + exit 1
#
# All bridge calls go to BAB_BRIDGE (default 127.0.0.1:7878). Override per-call
# by exporting BAB_BRIDGE before invoking.

set -uo pipefail

BAB_BRIDGE="${BAB_BRIDGE:-http://127.0.0.1:7878}"
BAB_TIMEOUT_MS="${BAB_TIMEOUT_MS:-15000}"

# ANSI helpers
if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_DIM=""; C_OFF=""
fi

die() { printf '%s%s%s\n' "$C_RED" "$*" "$C_OFF" >&2; exit 1; }
warn() { printf '%s%s%s\n' "$C_YEL" "$*" "$C_OFF" >&2; }

# Raw JSON-RPC. Args:
#   $1 method (e.g. execute_luau, get_console_output, search_game_tree)
#   $2 JSON object literal of arguments (default "{}")
bridge_call() {
    local method="$1"
    local args="${2:-{\}}"
    local payload
    payload=$(jq -n --arg m "$method" --argjson a "$args" --argjson t "$BAB_TIMEOUT_MS" \
        '{method:"tools/call", params:{name:$m, arguments:$a}, timeoutMs:$t}')
    curl -sS -m $((BAB_TIMEOUT_MS / 1000 + 5)) -X POST "$BAB_BRIDGE/rpc" \
        -H "Content-Type: application/json" -d "$payload"
}

# Extract result.content[0].text from a bridge response. Used for tools whose
# output is a single text blob (execute_luau, get_console_output, etc).
bridge_text() {
    local resp
    resp=$(bridge_call "$@") || die "bridge call failed"
    if [ -z "$resp" ]; then die "empty response from $BAB_BRIDGE"; fi
    python3 - "$resp" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception as e:
    print(f"BRIDGE_PARSE_ERROR: {e}", file=sys.stderr); sys.exit(1)
if not d.get("ok"):
    print(f"BRIDGE_ERROR: {json.dumps(d.get('error', d))}", file=sys.stderr); sys.exit(2)
content = d.get("result", {}).get("content", [])
if not content:
    print("BRIDGE_EMPTY: no content", file=sys.stderr); sys.exit(3)
print(content[0].get("text", ""))
PY
}

# Execute a Luau snippet in Studio. Snippet should `return` a value to be useful.
# Returns the Luau return value as a string (multi-line preserved).
bridge_eval() {
    local code="$1"
    local args
    args=$(jq -n --arg c "$code" '{code:$c}')
    bridge_text execute_luau "$args"
}

# Pretty-print JSON if input is JSON, otherwise pass through.
maybe_json() {
    python3 -c '
import sys, json
data = sys.stdin.read()
try:
    obj = json.loads(data)
    print(json.dumps(obj, indent=2))
except Exception:
    sys.stdout.write(data)
'
}

# Quick health check — bridge reachable AND a Studio is active.
bridge_health() {
    local resp
    resp=$(curl -sS -m 3 -X POST "$BAB_BRIDGE/rpc" -H "Content-Type: application/json" \
        -d '{"method":"tools/call","params":{"name":"list_roblox_studios","arguments":{}},"timeoutMs":3000}' 2>/dev/null) || {
        printf '%s✘ bridge unreachable at %s%s\n' "$C_RED" "$BAB_BRIDGE" "$C_OFF" >&2
        return 1
    }
    python3 - "$resp" <<'PY'
import json, sys, os
RED = "\033[31m" if sys.stderr.isatty() else ""
GRN = "\033[32m" if sys.stderr.isatty() else ""
YEL = "\033[33m" if sys.stderr.isatty() else ""
OFF = "\033[0m" if sys.stderr.isatty() else ""
try:
    d = json.loads(sys.argv[1])
    if not d.get("ok"):
        print(f"{RED}✘ bridge error: {d.get('error')}{OFF}", file=sys.stderr); sys.exit(1)
    txt = d["result"]["content"][0]["text"]
    payload = json.loads(txt)
    studios = payload.get("studios", [])
    if not studios:
        print(f"{RED}✘ no Studio instances connected{OFF}", file=sys.stderr); sys.exit(2)
    active = [s for s in studios if s.get("active")]
    if not active:
        names = ", ".join(s["name"] for s in studios)
        print(f"{YEL}⚠ Studio connected but none active ({names}). Run: dbg activate{OFF}", file=sys.stderr)
        sys.exit(3)
    print(f"{GRN}✔ Studio active: {active[0]['name']}{OFF}", file=sys.stderr)
except Exception as e:
    print(f"{RED}✘ health parse: {e}{OFF}", file=sys.stderr); sys.exit(4)
PY
}
