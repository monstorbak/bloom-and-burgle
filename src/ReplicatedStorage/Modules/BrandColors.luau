--!strict
-- BrandColors: the 9-token steampunk palette from Bloom&Burgle_Design_Spec.md §1.2.
-- Every UI surface, Part color, and particle MUST resolve through this module.
-- Code review blocks any hand-rolled Color3 outside this list.

local M = {}

-- Raw RGB (0-255) so the spec table is grep-able from the design doc.
local RGB = {
	Brass            = { 200, 146, 63  },
	CopperPatina     = { 79,  168, 143 },
	OilBlack         = { 26,  20,  16  },
	EmberOrange      = { 255, 106, 31  },
	SteamCream       = { 242, 228, 201 },
	IronworkCharcoal = { 46,  42,  42  },
	AetherCyan       = { 79,  227, 255 },
	ValveRed         = { 193, 60,  42  },
	GoggleGold       = { 232, 197, 71  },
	-- BAB-MARKETPLACE-NPC-ROTATION extension: signature colors for Hexerine
	-- "Stitches" (alchemy witch) and Sky Captain Verda (airship pilot). Both
	-- chosen to coexist with the original 9 — not compete for visual weight.
	WitchVellum      = { 88,  50,  110 },  -- deep aubergine for Hexerine's robes/alembic backing
	SkyCaptainNavy   = { 40,  80,  110 },  -- weathered teal-blue for Verda's flight coat
}

-- Color3 lookups
M.Brass            = Color3.fromRGB(unpack(RGB.Brass))
M.CopperPatina     = Color3.fromRGB(unpack(RGB.CopperPatina))
M.OilBlack         = Color3.fromRGB(unpack(RGB.OilBlack))
M.EmberOrange      = Color3.fromRGB(unpack(RGB.EmberOrange))
M.SteamCream       = Color3.fromRGB(unpack(RGB.SteamCream))
M.IronworkCharcoal = Color3.fromRGB(unpack(RGB.IronworkCharcoal))
M.AetherCyan       = Color3.fromRGB(unpack(RGB.AetherCyan))
M.ValveRed         = Color3.fromRGB(unpack(RGB.ValveRed))
M.GoggleGold       = Color3.fromRGB(unpack(RGB.GoggleGold))
M.WitchVellum      = Color3.fromRGB(unpack(RGB.WitchVellum))
M.SkyCaptainNavy   = Color3.fromRGB(unpack(RGB.SkyCaptainNavy))

-- Lerp helper for the "0-25% toward white/black" rule. Anything outside that
-- band must be flagged in code review.
function M.lerpToWhite(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), math.clamp(t, 0, 0.25))
end
function M.lerpToBlack(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), math.clamp(t, 0, 0.25))
end

-- Rarity rim colors per design spec §1.2 ladder.
M.Rarity = {
	Common    = M.Brass,
	Uncommon  = M.CopperPatina,
	Rare      = M.AetherCyan,
	Epic      = M.EmberOrange,
	Legendary = M.GoggleGold,
	Mythic    = M.AetherCyan,  -- animated cyan→gold flame applied at runtime
}

function M.rarityColor(rarity: string): Color3
	return M.Rarity[rarity] or M.Brass
end

-- Class crest accent colors used in HUD badges and signature ability glows.
M.ClassAccent = {
	Knight     = M.Brass,
	Alchemist  = M.CopperPatina,
	SkyPirate  = M.AetherCyan,
	Tinkerer   = M.GoggleGold,
	Hexer      = M.ValveRed,
}

function M.classAccent(class: string): Color3
	return M.ClassAccent[class] or M.Brass
end

return M
