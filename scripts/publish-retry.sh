#!/bin/bash
# publish-retry.sh — publish with exponential backoff. Roblox Open Cloud
# returns Conflict ("Server is busy") under load; retry up to N times.
#
# Usage: ./scripts/publish-retry.sh [Saved|Published] [maxAttempts]
set -e
export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."

VERSION_TYPE="${1:-Published}"
MAX_ATTEMPTS="${2:-12}"
RBXLX="BloomAndBurgle.rbxlx"

if [ -z "$ROBLOX_API_KEY" ] || [ -z "$BB_UNIVERSE_ID" ] || [ -z "$BB_PLACE_ID" ]; then
    echo "❌ Required env not set: ROBLOX_API_KEY, BB_UNIVERSE_ID, BB_PLACE_ID"
    exit 1
fi

./scripts/build.sh

URL="https://apis.roblox.com/universes/v1/$BB_UNIVERSE_ID/places/$BB_PLACE_ID/versions?versionType=$VERSION_TYPE"

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    echo ""
    echo "📤 Attempt $attempt/$MAX_ATTEMPTS — Publishing $VERSION_TYPE..."
    RESP=$(curl -s -X POST \
        -H "x-api-key: $ROBLOX_API_KEY" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$RBXLX" \
        "$URL")

    if echo "$RESP" | grep -q '"versionNumber"'; then
        echo "✅ Published successfully!"
        echo "   Response: $RESP"
        echo ""
        echo "🎮 Live at: https://www.roblox.com/games/$BB_PLACE_ID"
        exit 0
    fi

    if echo "$RESP" | grep -q "Conflict"; then
        # Roblox-side throttle. Backoff: 30s, 45s, 60s, 90s, 120s, then 180s thereafter.
        case "$attempt" in
            1) WAIT=30 ;;
            2) WAIT=45 ;;
            3) WAIT=60 ;;
            4) WAIT=90 ;;
            5) WAIT=120 ;;
            *) WAIT=180 ;;
        esac
        echo "⚠️  Roblox throttle (Conflict). Sleeping ${WAIT}s before retry..."
        sleep "$WAIT"
        continue
    fi

    echo "❌ Publish failed (non-retryable):"
    echo "   $RESP"
    exit 1
done

echo "❌ Gave up after $MAX_ATTEMPTS attempts. Try again later."
exit 2
