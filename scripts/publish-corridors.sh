#!/bin/bash
# Publish the Corridors place via Roblox Open Cloud.
#
# Usage:
#   ./scripts/publish-corridors.sh                # publishes live (Published)
#   ./scripts/publish-corridors.sh Saved          # saves a draft
#
# Required env: ROBLOX_API_KEY  (scope: universe-places:write)
# Required env: BB_UNIVERSE_ID  (universe id of the BAB experience)
# Required env: BB_CORRIDORS_PLACE_ID
#                  (default: 90190105638268 per
#                   memory/bab_universe_and_place_ids.md)

set -e

export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."

VERSION_TYPE="${1:-Published}"
RBXLX="Corridors.rbxlx"

if [ -z "$ROBLOX_API_KEY" ]; then
    echo "❌ ROBLOX_API_KEY env var not set."
    exit 1
fi

if [ -z "$BB_UNIVERSE_ID" ]; then
    echo "❌ BB_UNIVERSE_ID env var not set."
    exit 1
fi

PLACE_ID="${BB_CORRIDORS_PLACE_ID:-90190105638268}"

./scripts/build-corridors.sh

echo ""
echo "📤 Publishing $RBXLX to Universe $BB_UNIVERSE_ID / Place $PLACE_ID (Corridors, $VERSION_TYPE)..."

RESP=$(curl -s -X POST \
    -H "x-api-key: $ROBLOX_API_KEY" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$RBXLX" \
    "https://apis.roblox.com/universes/v1/$BB_UNIVERSE_ID/places/$PLACE_ID/versions?versionType=$VERSION_TYPE")

if echo "$RESP" | grep -q '"versionNumber"'; then
    echo "✅ Corridors published successfully!"
    echo "   Response: $RESP"
    echo ""
    echo "🎮 Corridors live at: https://www.roblox.com/games/$PLACE_ID"
else
    echo "❌ Publish failed:"
    echo "   $RESP"
    exit 1
fi
