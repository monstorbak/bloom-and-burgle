--!strict
-- PlantData: Central registry of plant species.
-- Each plant has a grow time, base value, color, and rarity.
-- ServerScriptService and StarterPlayerScripts both require() this so the
-- shop UI shows the same numbers the server uses for harvest payouts.

local M = {}

export type PlantSpec = {
	id: string,
	displayName: string,
	emoji: string,
	color: { number },        -- Color3 [r,g,b] floats 0-1
	growSeconds: number,      -- time from planting to harvest
	baseValue: number,        -- Bloom Bucks earned on harvest (before mutations / multiplier)
	seedCost: number,
	rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Mythic",
	mutationChance: number,   -- 0-1 chance any harvest is mutated
}

M.SPECIES = {
	sunbloom = {
		id = "sunbloom",
		displayName = "Sunbloom",
		emoji = "🌻",
		color = {1.0, 0.85, 0.2},
		growSeconds = 60,
		baseValue = 10,
		seedCost = 25,
		rarity = "Common",
		mutationChance = 0.02,    -- 2% mutation rate
	} :: PlantSpec,

	-- v0.2 will add: lavender_glow, blue_orb, ember_rose, void_lotus
}

function M.get(id: string): PlantSpec?
	return M.SPECIES[id]
end

function M.list(): { PlantSpec }
	local out = {}
	for _, p in M.SPECIES do
		table.insert(out, p)
	end
	return out
end

return M
