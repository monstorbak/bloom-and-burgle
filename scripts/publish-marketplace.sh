#!/bin/bash
# Publish the Marketplace place via Roblox Open Cloud.
#
# Usage:
#   ./scripts/publish-marketplace.sh                # publishes live (Published)
#   ./scripts/publish-marketplace.sh Saved          # saves a draft
#
# Required env: ROBLOX_API_KEY  (scope: universe-places:write)
# Required env: BB_UNIVERSE_ID  (universe id of the BAB experience)
# Required env: BB_MARKETPLACE_PLACE_ID
#                  (place id of the Marketplace place; default 90507376043667
#                   per memory/bab_universe_and_place_ids.md)

set -e

export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."

VERSION_TYPE="${1:-Published}"
RBXLX="Marketplace.rbxlx"

if [ -z "$ROBLOX_API_KEY" ]; then
    echo "❌ ROBLOX_API_KEY env var not set."
    exit 1
fi

if [ -z "$BB_UNIVERSE_ID" ]; then
    echo "❌ BB_UNIVERSE_ID env var not set."
    exit 1
fi

# Default to the production placeId if the env var isn't set.
PLACE_ID="${BB_MARKETPLACE_PLACE_ID:-90507376043667}"

# Build first
./scripts/build-marketplace.sh

echo ""
echo "📤 Publishing $RBXLX to Universe $BB_UNIVERSE_ID / Place $PLACE_ID (Marketplace, $VERSION_TYPE)..."

RESP=$(curl -s -X POST \
    -H "x-api-key: $ROBLOX_API_KEY" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$RBXLX" \
    "https://apis.roblox.com/universes/v1/$BB_UNIVERSE_ID/places/$PLACE_ID/versions?versionType=$VERSION_TYPE")

if echo "$RESP" | grep -q '"versionNumber"'; then
    echo "✅ Marketplace published successfully!"
    echo "   Response: $RESP"
    echo ""
    echo "🎮 Marketplace live at: https://www.roblox.com/games/$PLACE_ID"
else
    echo "❌ Publish failed:"
    echo "   $RESP"
    exit 1
fi
