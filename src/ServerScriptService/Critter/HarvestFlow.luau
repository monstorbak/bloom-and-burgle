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

local Workspace = game:GetService("Workspace")

local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local CritterVisuals = require(ServerScriptService:WaitForChild("CritterVisuals") :: ModuleScript)
local CritterRegistry = require(script.Parent:WaitForChild("CritterRegistry") :: ModuleScript)
local Telemetry = require(ServerScriptService:WaitForChild("Telemetry") :: ModuleScript) :: any
-- BAB-CRITTER-ESCAPE Phase 2.A: cancel the escape timer when harvested.
local EscapeWindow = require(script.Parent:WaitForChild("EscapeWindow") :: ModuleScript) :: any
-- BAB-PHASE-3 testing: DevMode-only mutation override (set via
-- /forcemutation <id> chat command; honored only when DevMode is on).
local DevMode = require(ServerScriptService:WaitForChild("DevMode") :: ModuleScript) :: any

-- BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL: cross-server Mythic Hatchers
-- leaderboard. Optional require — server keeps running if module fails to
-- load (e.g. DataStore unavailable in Studio without API access).
local TrophyData: any = nil
do
	local mod = ReplicatedStorage:FindFirstChild("Modules")
	local td = mod and mod:FindFirstChild("TrophyData")
	if td and td:IsA("ModuleScript") then
		local ok, m = pcall(require, td)
		if ok then TrophyData = m end
	end
end

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

	-- BAB-CRITTER-ESCAPE Phase 2.A: cancel any pending escape timer. The
	-- player beat the escape window — happy path. No-op if not armed.
	pcall(function() EscapeWindow.cancel(planter) end)

	-- Roll mutation. DevMode override path (Workspace.ForceMutation) lets
	-- admins force any mutation id for screenshot/clip prep — only honored
	-- when DevMode is enabled, and the override applies to ALL harvests
	-- until cleared. Set/clear via the /forcemutation chat command in
	-- DevMode.luau.
	local mutationId = ""
	local forceMut: any = DevMode.isEnabled() and Workspace:GetAttribute("ForceMutation")
	if typeof(forceMut) == "string" and forceMut ~= "" then
		-- Validate against the known mutation registry — silently no-op
		-- if the id is unknown so admins can't accidentally inject garbage.
		for _, m in CritterData.MUTATIONS do
			if m.id == forceMut then mutationId = forceMut; break end
		end
	elseif math.random() <= species.mutationChance then
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

	-- BAB-PHASE-3-MYTHIC-CEREMONY-AND-ADVISORY: fire the cinematic on
	-- Mythic-rarity hatches. "Mythic" = celestial mutation roll (1×100
	-- value) OR a species with rarity == "Mythic". Phase 1 set up the
	-- CritterCameraHooks client-side handler; this is the server-side
	-- trigger.
	local isMythic = (mutationId == "celestial") or (species.rarity == "Mythic")
	if isMythic then
		local mutDisplayName: string? = nil
		local mutEmoji: string? = nil
		if mutationId ~= "" then
			for _, m in CritterData.MUTATIONS do
				if m.id == mutationId then
					mutDisplayName = m.displayName
					mutEmoji = m.emoji
					break
				end
			end
		end
		local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
		local ceremonyRE = remotes and remotes:FindFirstChild("CritterCeremony") :: RemoteEvent?
		if ceremonyRE then
			pcall(function()
				ceremonyRE:FireClient(player, {
					type = "mythic_hatch",
					position = planter.Position + Vector3.new(0, 5, 0),
					duration = 1.6,
					speciesId = speciesId,
					speciesName = species.displayName,
					speciesEmoji = species.emoji,
					mutationId = mutationId,
					mutationName = mutDisplayName,
					mutationEmoji = mutEmoji,
				})
			end)
		end
		-- Telemetry: separate event from harvest_decision to make Mythic
		-- moments easy to filter in the funnel.
		pcall(function()
			Telemetry.track("mythic_hatch", {
				species = speciesId,
				mutationId = mutationId,
				class = player:GetAttribute("Class"),
			}, player)
		end)

		-- BAB-PHASE-4: increment lifetime Mythic Hatchers counter and post
		-- to the cross-server Trophy Hall. Counter is mirrored on the
		-- player attribute so subsequent mythic rolls in the same session
		-- bump the leaderboard value monotonically without a DataStore
		-- read. The TrophyData.submit dedupes by (uid, value) so resubmits
		-- from concurrent jobs don't double-count.
		local lifetimeMythics = (player:GetAttribute("MythicHatches") or 0) + 1
		player:SetAttribute("MythicHatches", lifetimeMythics)
		if TrophyData then
			task.spawn(function()
				pcall(function()
					TrophyData.submit("mythic_hatch", {
						userId = player.UserId,
						displayName = player.DisplayName,
						value = lifetimeMythics,
						species = speciesId,
						mutation = mutationId,
						timestamp = os.time(),
					})
				end)
			end)
		end
	end

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
