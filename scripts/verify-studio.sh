#!/bin/bash
# verify-studio.sh — Verify all expected scripts in Studio are the correct Instance type.
# Detects the BAB-011 push-to-studio bug where new files become Folders.
set -e
BRIDGE="${BRIDGE:-http://127.0.0.1:7878}"
cd "$(dirname "$0")/.."

LUA_CHECK=$(python3 <<'PYEOF'
expected = [
    ("game.ServerScriptService.DataStore", "ModuleScript"),
    ("game.ServerScriptService.DevMode", "ModuleScript"),
    ("game.ServerScriptService.PlantVisuals", "ModuleScript"),
    ("game.ServerScriptService.PlantHandler", "Script"),
    ("game.ServerScriptService.PlotManager", "Script"),
    ("game.ServerScriptService.SeedShop", "Script"),
    ("game.ServerScriptService.StealHandler", "Script"),
    ("game.ServerScriptService.GamepassHandler", "Script"),
    ("game.ServerScriptService.DevProductHandler", "Script"),
    ("game.ServerScriptService.LeaderstatsScript", "Script"),
    ("game.StarterPlayer.StarterPlayerScripts.CashHUD", "LocalScript"),
    ("game.StarterPlayer.StarterPlayerScripts.WelcomeUX", "LocalScript"),
    ("game.StarterPlayer.StarterPlayerScripts.SeedShopUI", "LocalScript"),
    ("game.StarterPlayer.StarterPlayerScripts.PlanterUI", "LocalScript"),
    ("game.StarterPlayer.StarterPlayerScripts.StealUI", "LocalScript"),
]
lines = ["local out = {}"]
for sp, cls in expected:
    parts = sp.split('.')[1:]  # drop game
    lines.append("do")
    lines.append('  local node = game:GetService("' + parts[0] + '")')
    for p in parts[1:]:
        lines.append('  if node then node = node:FindFirstChild("' + p + '") end')
    lines.append("  if not node then")
    lines.append('    table.insert(out, "MISSING: ' + sp + '")')
    lines.append('  elseif node.ClassName ~= "' + cls + '" then')
    lines.append('    table.insert(out, "WRONG_TYPE: ' + sp + ' is " .. node.ClassName .. " (expected ' + cls + ')")')
    lines.append("  end")
    lines.append("end")
lines.append('if #out == 0 then return "OK_ALL_GOOD" end')
lines.append('return table.concat(out, "\\n")')
print('\n'.join(lines))
PYEOF
)

PAYLOAD=$(jq -n --arg c "$LUA_CHECK" '{method:"tools/call",params:{name:"execute_luau",arguments:{code:$c}},timeoutMs:10000}')
RESULT=$(curl -sS -X POST "$BRIDGE/rpc" -H "Content-Type: application/json" -d "$PAYLOAD" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('content',[{}])[0].get('text','no result'))")

if [ "$RESULT" = "OK_ALL_GOOD" ]; then
    echo "✅ All scripts correct types in Studio"
    exit 0
fi

echo "❌ Studio state has problems:"
echo "$RESULT"
exit 1
