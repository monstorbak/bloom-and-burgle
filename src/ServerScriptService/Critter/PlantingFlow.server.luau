--!strict
-- PlantingFlow — planting flow + per-player lifecycle.
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). Owns:
--   - `plantSeedAt(player, planter, speciesId, freebie?)` — single-pod planting
--   - PlantSeed RemoteEvent listener (client-initiated planting via UI)
--   - Players.PlayerAdded starter pack (BAB-002 free starter critter on first plot)
--   - Players.PlayerRemoving cleanup hook for EconomyPad cooldowns
--
-- Other modules import the planting helper if they need it (SeedShop did
-- this via the PlantSeed RemoteEvent in legacy code; we keep that path
-- working so the migration is mechanical for SeedShop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local CritterVisuals = require(ServerScriptService:WaitForChild("CritterVisuals") :: ModuleScript)
local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter") :: ModuleScript)
local Telemetry = require(ServerScriptService:WaitForChild("Telemetry") :: ModuleScript)

local Critter = ServerScriptService:WaitForChild("Critter")
local CritterRegistry = require(Critter:WaitForChild("CritterRegistry") :: ModuleScript)
local EconomyPad = require(Critter:WaitForChild("EconomyPad") :: ModuleScript)

local PlantSeedRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlantSeed") :: RemoteEvent

-- One-shot starter pack species. Common rarity, lowest baseValue (20g) so the
-- free starter pods don't pre-monetize too much first-session cash. Was
-- "sunbloom" pre-BAB-STEAMPUNK; pivot retired the legacy plants but missed
-- updating this hook (CritterData.get(stale_id) returned nil → empty pods).
-- Fix originated as 737a2f7 on PlantHandler.server.luau pre-split; ported
-- here during P1.1 merge resolution with main (2026-05-08).
local STARTER_SPECIES = "cogwork_rat"

local function plantSeedAt(player: Player, planter: BasePart, speciesId: string, freebie: boolean?): boolean
	if planter:GetAttribute("OwnerUserId") ~= player.UserId then return false end
	if not planter:GetAttribute("IsEmpty") then return false end

	local species = CritterData.get(speciesId)
	if not species then return false end

	-- ADR-2: rate-limit. 9 pods/plot, allow 18 burst then 9/s sustained so
	-- a legitimate "fill all 9 pods at once" tap-flurry succeeds; anything
	-- beyond is a botted exploit.
	if not RateLimiter.tryConsume(player.UserId, "PlantSeed", 9, 18) then
		RateLimiter.logViolation(player, "PlantSeed", "species=" .. speciesId)
		return false
	end

	if not freebie then
		local ls = player:FindFirstChild("leaderstats")
		if not ls then return false end
		local cash = ls:FindFirstChild("Cash") :: IntValue?
		if not cash then return false end
		if cash.Value < species.seedCost then return false end
		cash.Value = cash.Value - species.seedCost
	end

	planter:SetAttribute("IsEmpty", false)
	planter:SetAttribute("PlantedSpecies", species.id)
	planter:SetAttribute("PlantedAt", os.time())
	planter:SetAttribute("GrowSeconds", species.growSeconds)

	CritterVisuals.create(planter, species)

	-- ADR-3: telemetry — pod_loaded
	Telemetry.track("pod_loaded", {
		species = species.id,
		rarity = species.rarity,
		freebie = freebie or false,
		seedCost = freebie and 0 or species.seedCost,
	}, player)

	return true
end

-- Client-initiated planting (touch a planter via UI)
PlantSeedRE.OnServerEvent:Connect(function(player, planterRef, speciesId)
	if typeof(planterRef) ~= "Instance" or not planterRef:IsA("BasePart") then return end
	if not planterRef:HasTag("Planter") then return end
	if typeof(speciesId) ~= "string" then return end
	plantSeedAt(player, planterRef, speciesId, false)
end)

-- Starter pack: free STARTER_SPECIES on first plot. BAB-002: only fire once per
-- account; flagged on the player via attribute `StarterPackGranted` which
-- LeaderstatsScript persists. Without this, every login refills empties with
-- free starters = trivial farming exploit.
Players.PlayerAdded:Connect(function(player)
	CritterRegistry.getInv(player)  -- create the bag eagerly so other modules find it
	task.spawn(function()
		while not player:GetAttribute("PlotClaimed") do
			task.wait(0.5)
			if not player.Parent then return end
		end
		if player:GetAttribute("StarterPackGranted") then return end
		task.wait(2)
		for _, planter in CollectionService:GetTagged("Planter") do
			if planter:IsA("BasePart")
				and planter:GetAttribute("OwnerUserId") == player.UserId
				and planter:GetAttribute("IsEmpty") then
				plantSeedAt(player, planter, STARTER_SPECIES, true)
			end
		end
		player:SetAttribute("StarterPackGranted", true)
	end)
end)

-- EconomyPad cooldown cleanup. Inventory cleanup lives in Persistence.
Players.PlayerRemoving:Connect(function(player)
	EconomyPad.clearCooldownsFor(player)
end)
