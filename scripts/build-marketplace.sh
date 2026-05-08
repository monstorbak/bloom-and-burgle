#!/bin/bash
# Build the Marketplace place (separate Rojo project under the BAB universe).
# Produces Marketplace.rbxlx alongside the Hatchery's BloomAndBurgle.rbxlx.
#
# Usage: bash scripts/build-marketplace.sh
#
# Material discipline check is intentionally identical to scripts/build.sh —
# the Marketplace place ships with the same brand/material rules per
# Bloom&Burgle_Design_Spec.md §1.5. If the marketplace introduces a banned
# material, the build fails the same way.

set -e

export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."

OUT="Marketplace.rbxlx"
PROJECT="default-marketplace.project.json"

# Material discipline (spec §1.5) — same banned set as the Hatchery.
echo "🔍 Material discipline check (Marketplace + shared modules)..."
BANNED='Material\.(SmoothPlastic|Plastic|Glass|Foil|ForceField)\b'
HITS=$(grep -rn -E "$BANNED" src src-marketplace --include="*.luau" 2>/dev/null || true)
if [ -n "$HITS" ]; then
    echo "❌ Banned material(s) found in Marketplace tree — see Bloom&Burgle_Design_Spec.md §1.5"
    echo "$HITS"
    echo ""
    echo "   Approved alternatives: Metal, CorrodedMetal, Marble, Brick, Cobblestone,"
    echo "                          Wood, WoodPlanks, Slate, Concrete, Neon."
    exit 2
fi
echo "✅ Material discipline OK"

echo "🔨 Building Marketplace place..."
rojo build -o "$OUT" "$PROJECT"

if [ -f "$OUT" ]; then
    SIZE=$(du -h "$OUT" | cut -f1)
    echo "✅ Build complete: $OUT ($SIZE)"
else
    echo "❌ Build failed — $OUT not produced"
    exit 1
fi
