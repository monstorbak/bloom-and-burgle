--!strict
-- BabPlaces — single source of truth for the universe's PlaceIds.
--
-- The Bloom & Burgle universe has three places (verified live via
-- create.roblox.com/dashboard, 2026-05-08):
--
--   Hatchery     93948369125480   — start place; Cogworks + 16 plots
--   Marketplace  90507376043667   — sell-portal destination
--   Corridors    90190105638268   — steal-portal destination
--
-- All three share the same Roblox universe (id 10130205713) so they share
-- DataStore keys (BloomAndBurgleData_v1, etc).
--
-- ── Override pattern (per AGENTS.md "Don't break") ────────────────────
-- Mirror of BB_GAMEPASS_* / BB_DEVPRODUCT_* runtime overrides. To target
-- a staging place during a hotfix without redeploying:
--
--   Workspace:SetAttribute("MarketplacePlaceId", 12345)
--   Workspace:SetAttribute("CorridorsPlaceId",   67890)
--
-- The compiled-in constants below are the production values; the override
-- attribute wins when set to a positive number.
--
-- Module is in ReplicatedStorage so client + server + all 3 places see
-- the same source.

local Workspace = game:GetService("Workspace")

local BabPlaces = {}

-- Compile-time defaults. NEVER change these without filing a P0 — losing the
-- right Hatchery PlaceId means TeleportService can't deliver returning players.
local DEFAULTS: { [string]: number } = {
	Hatchery    = 93948369125480,
	Marketplace = 90507376043667,
	Corridors   = 90190105638268,
}

-- Read the Workspace.<name>PlaceId attribute, fall through to the constant.
-- Returns 0 if the name is unknown — caller MUST check for non-zero before
-- handing it to TeleportService:TeleportAsync.
function BabPlaces.placeId(name: string): number
	local attr = Workspace:GetAttribute(name .. "PlaceId")
	if typeof(attr) == "number" and attr > 0 then return attr end
	return DEFAULTS[name] or 0
end

-- Convenience helpers (most callers want one specific place).
function BabPlaces.hatchery(): number    return BabPlaces.placeId("Hatchery") end
function BabPlaces.marketplace(): number return BabPlaces.placeId("Marketplace") end
function BabPlaces.corridors(): number   return BabPlaces.placeId("Corridors") end

-- Test/diagnostic seam. Returns the in-source defaults regardless of override
-- so tooling can verify the live state matches what's pinned at compile time.
function BabPlaces._defaults(): { [string]: number }
	local copy = {}
	for k, v in DEFAULTS do copy[k] = v end
	return copy
end

return BabPlaces
