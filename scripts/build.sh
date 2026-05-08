#!/bin/bash
# Build Bloom & Burgle into a single .rbxlx via Rojo.
# Pre-build CI gate: enforce material discipline per design spec §1.5.
set -e

export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."

OUT="BloomAndBurgle.rbxlx"

# ── Material discipline (spec §1.5): SmoothPlastic, Plastic, Glass, Foil,
# and ForceField all read as "starter Roblox kit" against the steampunk
# identity. Any new occurrence in src/ fails the build.
echo "🔍 Material discipline check..."
# ERE pattern — must use unescaped parens with -E.
BANNED='Material\.(SmoothPlastic|Plastic|Glass|Foil|ForceField)\b'
HITS=$(grep -rn -E "$BANNED" src --include="*.luau" || true)
if [ -n "$HITS" ]; then
    echo "❌ Banned material(s) found in src/ — see Bloom&Burgle_Design_Spec.md §1.5"
    echo "$HITS"
    echo ""
    echo "   Approved alternatives: Metal, CorrodedMetal, Marble, Brick, Cobblestone,"
    echo "                          Wood, WoodPlanks, Slate, Concrete, Neon."
    exit 2
fi
echo "✅ Material discipline OK (no banned materials)"

echo "🔨 Building Bloom & Burgle..."
rojo build -o "$OUT" default.project.json

if [ -f "$OUT" ]; then
    SIZE=$(du -h "$OUT" | cut -f1)
    echo "✅ Build complete: $SIZE"
else
    echo "❌ Build failed"
    exit 1
fi
