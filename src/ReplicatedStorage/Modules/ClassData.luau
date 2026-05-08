--!strict
-- ClassData: the 5-class registry from Bloom&Burgle_Design_Spec.md §7.
-- Class is the player's HUD-permanent identity and drives the asset/liability
-- matrix in CritterData.luau.

local M = {}

export type ClassSpec = {
	id: string,
	displayName: string,
	crest: string,                  -- emoji used on HUD badge + advisory copy
	tagline: string,                -- shown on Class Hall hover
	combat: {
		hp: number,
		damage: number,
		speed: number,              -- WalkSpeed override
		damageType: "Melee" | "Ranged" | "Magic",
	},
	signature: {
		id: string,
		displayName: string,
		description: string,
		cooldown: number,           -- seconds
	},
	hatchBias: {                    -- which species archetype this class is biased toward
		archetype: string,
		bonusPercent: number,       -- +5% (0.05) per spec §7
	},
}

M.CLASSES = {
	knight = {
		id = "knight",
		displayName = "Knight",
		crest = "🛡",
		tagline = "Heavy plate, steel resolve. Mounts and hounds love you. Dragons want you dead.",
		combat = { hp = 140, damage = 25, speed = 14, damageType = "Melee" },
		signature = {
			id = "shieldBash",
			displayName = "Shield Bash",
			description = "Stun one critter for 2s.",
			cooldown = 12,
		},
		hatchBias = { archetype = "mount", bonusPercent = 0.05 },
	} :: ClassSpec,

	alchemist = {
		id = "alchemist",
		displayName = "Alchemist",
		crest = "⚗",
		tagline = "Bottled lightning, brewed plagues. Familiars and imps owe you favors.",
		combat = { hp = 100, damage = 18, speed = 14, damageType = "Ranged" },
		signature = {
			id = "brewCloud",
			displayName = "Brew Cloud",
			description = "Place a 4s damage-over-time poison cloud.",
			cooldown = 16,
		},
		hatchBias = { archetype = "magicalFamiliar", bonusPercent = 0.05 },
	} :: ClassSpec,

	skyPirate = {
		id = "skyPirate",
		displayName = "Sky Pirate",
		crest = "✈",
		tagline = "Pistol, wings, no patience. Fly with wyverns; ground beasts are dead weight.",
		combat = { hp = 90, damage = 22, speed = 18, damageType = "Ranged" },
		signature = {
			id = "grapplingHook",
			displayName = "Grappling Hook",
			description = "Pull yourself or an enemy 30 studs.",
			cooldown = 10,
		},
		hatchBias = { archetype = "skyMount", bonusPercent = 0.05 },
	} :: ClassSpec,

	tinkerer = {
		id = "tinkerer",
		displayName = "Tinkerer",
		crest = "🔧",
		tagline = "Wrench in one hand, blueprint in the other. Cogwork pets and turrets.",
		combat = { hp = 110, damage = 16, speed = 14, damageType = "Ranged" },
		signature = {
			id = "cogTurret",
			displayName = "Cog Turret",
			description = "Deploy a brass auto-firing turret for 8s.",
			cooldown = 18,
		},
		hatchBias = { archetype = "cogworkPet", bonusPercent = 0.05 },
	} :: ClassSpec,

	hexer = {
		id = "hexer",
		displayName = "Hexer",
		crest = "🔮",
		tagline = "Curses, hexes, raw aether. Imps and toads are your siblings.",
		combat = { hp = 85, damage = 28, speed = 16, damageType = "Magic" },
		signature = {
			id = "hexBolt",
			displayName = "Hex Bolt",
			description = "Single-target damage + 3s slow.",
			cooldown = 8,
		},
		hatchBias = { archetype = "magicalCritter", bonusPercent = 0.05 },
	} :: ClassSpec,
}

-- Stable order for HUD pick wheel
M.ORDER = { "knight", "alchemist", "skyPirate", "tinkerer", "hexer" }

function M.get(id: string): ClassSpec?
	return M.CLASSES[id]
end

function M.list(): { ClassSpec }
	local out = {}
	for _, id in M.ORDER do
		table.insert(out, M.CLASSES[id])
	end
	return out
end

return M
