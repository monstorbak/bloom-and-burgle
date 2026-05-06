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
	unlockCash: number,       -- min lifetime cash earned to unlock in shop (0 = always)
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
		mutationChance = 0.02,
		unlockCash = 0,
	} :: PlantSpec,

	lavender_glow = {
		id = "lavender_glow",
		displayName = "Lavender Glow",
		emoji = "💜",
		color = {0.7, 0.45, 1.0},
		growSeconds = 120,
		baseValue = 30,
		seedCost = 60,
		rarity = "Uncommon",
		mutationChance = 0.04,
		unlockCash = 200,
	} :: PlantSpec,

	blue_orb = {
		id = "blue_orb",
		displayName = "Blue Orb",
		emoji = "🔵",
		color = {0.25, 0.55, 1.0},
		growSeconds = 300,
		baseValue = 110,
		seedCost = 200,
		rarity = "Rare",
		mutationChance = 0.06,
		unlockCash = 800,
	} :: PlantSpec,

	ember_rose = {
		id = "ember_rose",
		displayName = "Ember Rose",
		emoji = "🌹",
		color = {1.0, 0.3, 0.15},
		growSeconds = 600,
		baseValue = 350,
		seedCost = 600,
		rarity = "Epic",
		mutationChance = 0.08,
		unlockCash = 3000,
	} :: PlantSpec,

	void_lotus = {
		id = "void_lotus",
		displayName = "Void Lotus",
		emoji = "🪷",
		color = {0.4, 0.0, 0.6},
		growSeconds = 1500,
		baseValue = 1500,
		seedCost = 2500,
		rarity = "Mythic",
		mutationChance = 0.12,
		unlockCash = 12000,
	} :: PlantSpec,
}

-- Mutation registry: applied to harvested plants for big value boosts + visual flex
export type MutationSpec = {
	id: string,
	displayName: string,
	emoji: string,
	multiplier: number,
	chance: number,    -- relative weight; sampled inside species mutationChance roll
	color: { number }, -- override sprout color
}

M.MUTATIONS = {
	{ id = "shiny",   displayName = "Shiny",   emoji = "✨", multiplier = 2.0,  chance = 0.50, color = {1.0, 1.0, 0.7} } :: MutationSpec,
	{ id = "golden",  displayName = "Golden",  emoji = "🥇", multiplier = 5.0,  chance = 0.25, color = {1.0, 0.84, 0.0} } :: MutationSpec,
	{ id = "rainbow", displayName = "Rainbow", emoji = "🌈", multiplier = 12.0, chance = 0.15, color = {1.0, 0.4, 1.0} } :: MutationSpec,
	{ id = "void",    displayName = "Void",    emoji = "🌌", multiplier = 30.0, chance = 0.08, color = {0.2, 0.0, 0.4} } :: MutationSpec,
	{ id = "celestial", displayName = "Celestial", emoji = "💫", multiplier = 100.0, chance = 0.02, color = {0.6, 0.9, 1.0} } :: MutationSpec,
}

function M.get(id: string): PlantSpec?
	return M.SPECIES[id]
end

function M.list(): { PlantSpec }
	local out = {}
	for _, p in M.SPECIES do
		table.insert(out, p)
	end
	-- Sort by seedCost ascending so shop UI is stable
	table.sort(out, function(a, b) return a.seedCost < b.seedCost end)
	return out
end

-- Roll a mutation. Returns nil if no mutation, or a MutationSpec.
-- Caller should pre-multiply species.mutationChance to determine if ANY mutation occurs.
function M.rollMutation(): MutationSpec?
	local roll = math.random()
	local cumulative = 0
	for _, mut in M.MUTATIONS do
		cumulative += mut.chance
		if roll <= cumulative then
			return mut
		end
	end
	return M.MUTATIONS[1] -- fallback to shiny
end

function M.rarityColor(rarity: string): { number }
	if rarity == "Common" then return {0.7, 0.7, 0.7}
	elseif rarity == "Uncommon" then return {0.4, 0.9, 0.4}
	elseif rarity == "Rare" then return {0.3, 0.6, 1.0}
	elseif rarity == "Epic" then return {0.8, 0.4, 1.0}
	elseif rarity == "Mythic" then return {1.0, 0.5, 0.0}
	end
	return {1, 1, 1}
end

return M
