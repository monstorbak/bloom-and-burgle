#!/bin/bash
# Build Bloom & Burgle into a single .rbxlx via Rojo.
set -e

export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."

OUT="BloomAndBurgle.rbxlx"

echo "🔨 Building Bloom & Burgle..."
rojo build -o "$OUT" default.project.json

if [ -f "$OUT" ]; then
    SIZE=$(du -h "$OUT" | cut -f1)
    echo "✅ Build complete: $SIZE"
else
    echo "❌ Build failed"
    exit 1
fi
