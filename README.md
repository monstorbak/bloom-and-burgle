# 🌸 Bloom & Burgle

> **Idle farming simulator + PvP stealing + social roleplay hub.**
> Engineered for Roblox virality — modeled on the proven 2025 hits (Grow a Garden, Steal a Brainrot, Adopt Me, Brookhaven).

**Working title:** Bloom & Burgle (subject to change).
**Genre:** Idle Sim + PvP Steal + Social RP.
**Target audience:** 8-16 (broad Roblox demo).

## Tagline

> *"Build the ultimate garden empire. Grow rare mutations. Steal from your neighbors. Show off in the town square."*

## Status

- **MVP (v0.1):** starter plot, 1 plant species (Sunbloom), idle-grow loop, harvest, sell, leaderstats with Cash + Rebirths, claim pad UX.
- **Roadmap:** see `docs/roadmap.md` (TODO).

## Build & Deploy

```bash
# One-time: install Rojo + Mantle pinned by rokit
rokit install

# Build to .rbxlx
./scripts/build.sh

# Publish live to Roblox (Open Cloud API)
export ROBLOX_API_KEY="<piddly-api>"
export BB_UNIVERSE_ID="<universe-id>"
export BB_PLACE_ID="<place-id>"
./scripts/publish.sh                   # publishes live
./scripts/publish.sh Saved             # saves a draft
```

## Architecture

```
src/
├── ServerScriptService/
│   ├── DataStore.luau               # ModuleScript (NOT .server.luau!)
│   ├── LeaderstatsScript.server.luau
│   ├── PlotManager.server.luau      # claim pads + procedural plot spawning
│   └── PlantHandler.server.luau     # grow/harvest/sell loop
├── ReplicatedStorage/
│   ├── Modules/PlantData.luau       # central plant species registry
│   └── RemoteEvents/                # PlotClaimed, PlantSeed, SellPlants
├── ServerStorage/Plants/            # plant model JSONs (v0.2+)
├── StarterPlayerScripts/
│   └── WelcomeUX.client.luau        # welcome modal + sell toast
└── Workspace/
    └── TownSquare.model.json        # spawn area (fountain + sign + spawn pad)
```

## Roblox JSON model gotchas (learned from neon-forge-tycoon)

- Use `Color` as `[r,g,b]` floats (0-1), **NOT `BrickColor` strings**.
- `UDim2` properties need `{UDim2: [[scaleX, offsetX], [scaleY, offsetY]]}` not flat arrays.
- Top-level `name` on a Model is ignored — use the file name or remove.
- `HttpService HttpEnabled: true` lives at the service node.
- **Module scripts MUST end in `.luau`, NOT `.server.luau`** — otherwise Rojo creates a Script (not ModuleScript) and `require()` will throw "invalid argument(s)".

## Spec

Full design + monetization + marketing flywheel: `~/.openclaw/workspace/specs/steal-and-grow.md`.

🤘 Built with the gastown Layer 2 watchdog hierarchy.
