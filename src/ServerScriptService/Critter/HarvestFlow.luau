--!strict
-- HarvestFlow — pure-ish per-pod harvest logic, shared by:
--   - GrowLoop (touch-to-harvest fallback)
--   - EconomyPad (sell + scrap auto-harvest pre-scan)
--   - Persistence (offline ripen → harvestOffline)
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). The point is to
-- have one place where "ripe pod → inventory entry" lives, so the logic
-- (mutation roll, popup, attribute clear) doesn't drift across the four
-- callsites that used to copy-paste it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local CritterVisuals = require(ServerScriptService:WaitForChild("CritterVisuals") :: ModuleScript)
local CritterRegistry = require(script.Parent:WaitForChild("CritterRegistry") :: ModuleScript)
local Telemetry = require(ServerScriptService:WaitForChild("Telemetry") :: ModuleScript) :: any

-- The harvest-popup RemoteEvent is created lazily here so the module is
-- self-sufficient (no PlantHandler.server.luau to make it). Idempotent:
-- subsequent requires hit the existing instance.
local HarvestPopupRE = ReplicatedStorage:WaitForChild("RemoteEvents"):FindFirstChild("HarvestPopup")
if not HarvestPopupRE then
	local re = Instance.new("RemoteEvent")
	re.Name = "HarvestPopup"
	re.Parent = ReplicatedStorage:WaitForChild("RemoteEvents")
	HarvestPopupRE = re
end
assert(HarvestPopupRE, "HarvestPopup RemoteEvent must exist after lazy create")

local HarvestFlow = {}

-- Harvest a single ripe planter for the player. Adds to stash. Returns
-- true if something was actually harvested (planter was ripe + owned).
function HarvestFlow.harvestPlanter(player: Player, planter: BasePart): boolean
	if not planter:GetAttribute("Ripe") then return false end
	if planter:GetAttribute("OwnerUserId") ~= player.UserId then return false end
	local speciesId = planter:GetAttribute("PlantedSpecies") :: string
	local species = CritterData.get(speciesId)
	if not species then return false end

	-- Roll mutation
	local mutationId = ""
	if math.random() <= species.mutationChance then
		local mut = CritterData.rollMutation()
		if mut then mutationId = mut.id end
	end
	local key = speciesId .. ":" .. mutationId
	CritterRegistry.addToInventory(player, key, 1)
	player:SetAttribute("PlantsHarvested", (player:GetAttribute("PlantsHarvested") or 0) + 1)

	-- ADR-3 telemetry. Per the eval's 10 launch events, harvest_decision
	-- captures the moment a player commits a critter to their stash —
	-- the funnel point between pod_ripened and sell_payout/scrap_payout.
	-- Phase 2 (BAB-CRITTER-ESCAPE) will add escape outcomes to this event
	-- with `outcome = "escaped_asset" | "escaped_liability" | ...`; for
	-- now the only outcome is "added_to_stash".
	pcall(function()
		Telemetry.track("harvest_decision", {
			species = speciesId,
			mutationId = mutationId,
			class = player:GetAttribute("Class"),
			outcome = "added_to_stash",
			rarity = species.rarity,
		}, player)
	end)

	-- Fire popup to client. We bind to a local first because Luau's parser
	-- treats a line starting with `(` as a continuation of the previous line
	-- (the classic ambiguous-call gotcha). Letting Roblox's strict-mode
	-- runtime parser see `local re = ... :: RemoteEvent` then `re:FireClient(...)`
	-- avoids the ambiguity without a leading semicolon.
	local re = HarvestPopupRE :: RemoteEvent
	re:FireClient(player, {
		species = speciesId,
		mutation = mutationId,
		emoji = species.emoji,
		name = species.displayName,
		position = planter.Position + Vector3.new(0, 5, 0),
	})

	-- Clear planter
	local plantModel = planter:FindFirstChild("Plant")
	if plantModel and plantModel.Parent then plantModel:Destroy() end
	planter:SetAttribute("IsEmpty", true)
	planter:SetAttribute("Ripe", false)
	planter:SetAttribute("PlantedSpecies", nil)
	planter:SetAttribute("PlantedAt", nil)
	planter:SetAttribute("GrowSeconds", nil)
	local border = planter:FindFirstChild("EmptyBorder") :: BasePart?
	if border then border.Transparency = 0 end
	return true
end

-- BAB-FINDABILITY 2: harvest every ripe pod owned by this player. Returns
-- the count harvested. EconomyPad calls this just before sell + scrap so
-- the player can walk-once-and-be-paid even if they didn't manually
-- harvest first.
function HarvestFlow.harvestAllRipeForPlayer(player: Player): number
	local n = 0
	for _, planter in CollectionService:GetTagged("Planter") do
		if not planter:IsA("BasePart") then continue end
		if planter:GetAttribute("OwnerUserId") ~= player.UserId then continue end
		if not planter:GetAttribute("Ripe") then continue end
		if HarvestFlow.harvestPlanter(player, planter) then n += 1 end
	end
	return n
end

-- Offline ripen → straight to inventory. Used by Persistence.restore when
-- a saved planter's grow timer elapsed while the player was away. Skips
-- the popup + planter-clear (the planter is already-empty by the time we
-- save attributes; the caller is responsible for visual sync).
function HarvestFlow.harvestOffline(player: Player, speciesId: string, species: any)
	local mutationId = ""
	if math.random() <= species.mutationChance then
		local mut = CritterData.rollMutation()
		if mut then mutationId = mut.id end
	end
	local key = speciesId .. ":" .. mutationId
	CritterRegistry.addToInventory(player, key, 1)
	player:SetAttribute("PlantsHarvested", (player:GetAttribute("PlantsHarvested") or 0) + 1)
	if mutationId ~= "" then
		player:SetAttribute("MutationsFound", (player:GetAttribute("MutationsFound") or 0) + 1)
	end

	-- ADR-3 telemetry — same event as online harvest but tagged so we can
	-- distinguish offline ripens from in-world walks.
	pcall(function()
		Telemetry.track("harvest_decision", {
			species = speciesId,
			mutationId = mutationId,
			class = player:GetAttribute("Class"),
			outcome = "added_to_stash",
			rarity = species.rarity,
			source = "offline_ripen",
		}, player)
	end)
end

-- Build a sprout model on a planter at a given progress. Wraps CritterVisuals
-- so Persistence.restore doesn't need to require CritterVisuals directly.
function HarvestFlow.buildSproutFor(planter: BasePart, species: any, progressOverride: number?)
	local model = CritterVisuals.create(planter, species)
	CritterVisuals.update(model, progressOverride or 0)
end

return HarvestFlow
