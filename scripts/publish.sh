#!/bin/bash
# Publish Bloom & Burgle directly via Roblox Open Cloud API.
# Bypasses Mantle (whose `import` relies on a removed Roblox API — issue #243).
#
# Usage:
#   ./scripts/publish.sh                 # publishes to live (Published)
#   ./scripts/publish.sh Saved           # saves a draft (no live update)
#
# Required env: ROBLOX_API_KEY  (piddly-api, scope: universe-places:write)
# Required env: BB_UNIVERSE_ID  (universe id of the Bloom & Burgle experience)
# Required env: BB_PLACE_ID     (root place id of the Bloom & Burgle experience)

set -e
export PATH="$HOME/.rokit/bin:$PATH"

cd "$(dirname "$0")/.."

VERSION_TYPE="${1:-Published}"
RBXLX="BloomAndBurgle.rbxlx"

if [ -z "$ROBLOX_API_KEY" ]; then
    echo "❌ ROBLOX_API_KEY env var not set."
    exit 1
fi

if [ -z "$BB_UNIVERSE_ID" ] || [ -z "$BB_PLACE_ID" ]; then
    echo "❌ BB_UNIVERSE_ID / BB_PLACE_ID env vars not set."
    echo "   These are written into ~/.profile after the first 'create-experience.sh' run."
    exit 1
fi

# Build first
./scripts/build.sh

echo ""
echo "📤 Publishing $RBXLX to Universe $BB_UNIVERSE_ID / Place $BB_PLACE_ID ($VERSION_TYPE)..."

RESP=$(curl -s -X POST \
    -H "x-api-key: $ROBLOX_API_KEY" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$RBXLX" \
    "https://apis.roblox.com/universes/v1/$BB_UNIVERSE_ID/places/$BB_PLACE_ID/versions?versionType=$VERSION_TYPE")

if echo "$RESP" | grep -q '"versionNumber"'; then
    echo "✅ Published successfully!"
    echo "   Response: $RESP"
    echo ""
    echo "🎮 Live at: https://www.roblox.com/games/$BB_PLACE_ID"
else
    echo "❌ Publish failed:"
    echo "   $RESP"
    exit 1
fi
