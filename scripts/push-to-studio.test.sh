#!/usr/bin/env bash
# push-to-studio.test.sh — verify P1.4 Play-mode safety on push-to-studio.sh.
#
# Mocks the Studio MCP bridge with a tiny Python HTTP server that returns
# either "edit" or "play" from the RunService:IsRunning() probe and
# accepts the rest of the destroy/edit/verify calls. Then drives
# push-to-studio.sh through five scenarios:
#
#   1. Edit + Script           → success
#   2. Play + Script           → refused (exit 2)
#   3. Play + Script + --force → success
#   4. Play + LocalScript      → success (warn-only)
#   5. Bridge unreachable      → refused (exit 3)
#
# Self-contained: starts and tears down its own mock bridge per case so
# each case runs against a known clean state. Designed to run in CI without
# Studio installed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUSH="$HERE/push-to-studio.sh"
PORT=${PORT:-7894}
TMP=$(mktemp -d)
MOCK_PID=""

cleanup() {
    if [ -n "$MOCK_PID" ] && kill -0 "$MOCK_PID" 2>/dev/null; then
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

# Mock bridge body, written once and re-launched per case with a different
# RUN_MODE env var.
cat > "$TMP/mock_bridge.py" <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ["MOCK_PORT"])
MODE = os.environ["RUN_MODE"]   # "play" or "edit"

class H(BaseHTTPRequestHandler):
    def log_message(self, *a, **k): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(n) or b"{}")
        code = body.get("params", {}).get("arguments", {}).get("code", "")
        if "RunService" in code and "IsRunning" in code:
            out = MODE
        elif "tostring(#x.Source)" in code:
            out = "1000"   # fake "synced" size, large enough to pass the >EXPECTED/2 gate
        else:
            out = "reset ok"
        resp = {"ok": True, "result": {"content": [{"text": out}]}}
        b = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY

# Sample input fixture — three sync rows, one per className.
mkdir -p "$TMP/src"
# 1000 chars so EXPECTED/2 = 500 < 1000 (mock returns size "1000")
python3 -c "import sys; sys.stdout.write('-- sample server\n' + 'x' * 1000)" > "$TMP/src/Sample.server.luau"
python3 -c "import sys; sys.stdout.write('-- sample client\n' + 'x' * 1000)" > "$TMP/src/Sample.client.luau"

INPUT_SCRIPT="$TMP/src/Sample.server.luau::game.ServerScriptService.Sample::Script"
INPUT_LOCAL="$TMP/src/Sample.client.luau::game.StarterPlayer.StarterPlayerScripts.Sample::LocalScript"

start_mock() {
    local mode="$1"
    MOCK_PORT="$PORT" RUN_MODE="$mode" python3 "$TMP/mock_bridge.py" >"$TMP/mock.log" 2>&1 &
    MOCK_PID=$!
    for _ in $(seq 1 50); do
        if curl -sS --max-time 0.3 "http://127.0.0.1:$PORT/rpc" \
            -H 'Content-Type: application/json' \
            -d '{"method":"tools/call","params":{"name":"execute_luau","arguments":{"code":"return game:GetService(\"RunService\"):IsRunning() and \"play\" or \"edit\""}}}' \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    echo "❌ mock bridge failed to start on port $PORT (PID=$MOCK_PID)" >&2
    cat "$TMP/mock.log" >&2 || true
    return 1
}

stop_mock() {
    if [ -n "$MOCK_PID" ] && kill -0 "$MOCK_PID" 2>/dev/null; then
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
    MOCK_PID=""
}

assert_eq() {
    local what="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✅ $what: $actual"
    else
        echo "  ❌ $what: expected=$expected actual=$actual"
        return 1
    fi
}

run_case() {
    local name="$1" mode="$2" expected_exit="$3" expect_substr="$4"
    shift 4
    local input="$1"; shift
    local extra_args=("$@")
    echo "── case: $name ──"
    if [ "$mode" != "none" ]; then
        start_mock "$mode" || return 1
    fi
    set +e
    if [ "${#extra_args[@]}" -gt 0 ]; then
        out=$(ROBLOX_MCP_BRIDGE="http://127.0.0.1:$PORT" \
            "$PUSH" "${extra_args[@]}" <<<"$input" 2>&1)
    else
        out=$(ROBLOX_MCP_BRIDGE="http://127.0.0.1:$PORT" \
            "$PUSH" <<<"$input" 2>&1)
    fi
    ec=$?
    set -e
    if [ "$mode" != "none" ]; then
        stop_mock
    fi
    if ! assert_eq "exit code" "$expected_exit" "$ec"; then
        echo "$out" | sed 's/^/    /'
        return 1
    fi
    if [ -n "$expect_substr" ]; then
        if echo "$out" | grep -q -- "$expect_substr"; then
            echo "  ✅ stdout contains: $expect_substr"
        else
            echo "  ❌ stdout missing expected substring: $expect_substr"
            echo "$out" | sed 's/^/    /'
            return 1
        fi
    fi
    echo
}

failures=0

# 1. Edit + Script → success
run_case "edit+Script" "edit" "0" "synced game.ServerScriptService.Sample" \
    "$INPUT_SCRIPT" || failures=$((failures+1))

# 2. Play + Script → refused (exit 2)
run_case "play+Script (refused)" "play" "2" "refusing to sync" \
    "$INPUT_SCRIPT" || failures=$((failures+1))

# 3. Play + Script + --force → success
run_case "play+Script+--force" "play" "0" "synced game.ServerScriptService.Sample" \
    "$INPUT_SCRIPT" --force || failures=$((failures+1))

# 4. Play + LocalScript → success with warn
run_case "play+LocalScript" "play" "0" "may break on respawn" \
    "$INPUT_LOCAL" || failures=$((failures+1))

# 5. Bridge unreachable → refused (exit 3). Point at a free port nobody binds.
PORT=7895
run_case "bridge unreachable" "none" "3" "Refusing to push" \
    "$INPUT_SCRIPT" || failures=$((failures+1))

if [ "$failures" -gt 0 ]; then
    echo "❌ $failures push-to-studio.sh case(s) failed"
    exit 1
fi
echo "🎉 all push-to-studio.sh cases passed"
