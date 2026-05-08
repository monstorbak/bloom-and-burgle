#!/bin/bash
# Build the Corridors place (separate Rojo project under the BAB universe).
# Produces Corridors.rbxlx alongside the Hatchery's BloomAndBurgle.rbxlx.
#
# Usage: bash scripts/build-corridors.sh

set -e

export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."

OUT="Corridors.rbxlx"
PROJECT="default-corridors.project.json"

echo "🔍 Material discipline check (Corridors + shared modules)..."
BANNED='Material\.(SmoothPlastic|Plastic|Glass|Foil|ForceField)\b'
HITS=$(grep -rn -E "$BANNED" src src-corridors --include="*.luau" 2>/dev/null || true)
if [ -n "$HITS" ]; then
    echo "❌ Banned material(s) found in Corridors tree — see Bloom&Burgle_Design_Spec.md §1.5"
    echo "$HITS"
    echo ""
    echo "   Approved alternatives: Metal, CorrodedMetal, Marble, Brick, Cobblestone,"
    echo "                          Wood, WoodPlanks, Slate, Concrete, Neon."
    exit 2
fi
echo "✅ Material discipline OK"

echo "🔨 Building Corridors place..."
rojo build -o "$OUT" "$PROJECT"

if [ -f "$OUT" ]; then
    SIZE=$(du -h "$OUT" | cut -f1)
    echo "✅ Build complete: $OUT ($SIZE)"
else
    echo "❌ Build failed — $OUT not produced"
    exit 1
fi
