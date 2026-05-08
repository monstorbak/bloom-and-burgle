--!strict
-- GrowLoop — Heartbeat-driven grow progress, ripen attribute, EmptyBorder pulse,
-- and the per-pod `.Touched` harvest fallback.
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). Owns:
--   - the Heartbeat loop that scales sprouts and flips Ripe
--   - pod_ripened telemetry
--   - the cyan EmptyBorder window's transparency animation
--   - per-pod `.Touched` harvest wiring (manual harvest fallback — the
--     SellPad/ScrapPad auto-harvest path lives in EconomyPad)
--
-- Persistence + Services registration is loaded eagerly so both the
-- "CritterHandler" (canonical) and "PlantHandler" (legacy alias)
-- services are online for LeaderstatsScript on cold boot. HarvestFlow
-- is required so the harvest popup RemoteEvent gets created.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local CritterVisuals = require(ServerScriptService:WaitForChild("CritterVisuals") :: ModuleScript)
local Telemetry = require(ServerScriptService:WaitForChild("Telemetry") :: ModuleScript)

-- Eagerly require the Critter modules so their side effects (RemoteEvent
-- creation, Services registration, PlayerRemoving cleanup) take effect.
local Critter = ServerScriptService:WaitForChild("Critter")
local HarvestFlow = require(Critter:WaitForChild("HarvestFlow") :: ModuleScript)
require(Critter:WaitForChild("Persistence") :: ModuleScript)

-- ── Heartbeat: grow tick + ripen + EmptyBorder pulse ──────────────────────
RunService.Heartbeat:Connect(function()
	local now = os.time()
	for _, planter in CollectionService:GetTagged("Planter") do
		if planter:GetAttribute("IsEmpty") then continue end
		if not planter:IsA("BasePart") then continue end
		local plantedAt = planter:GetAttribute("PlantedAt") or 0
		local growSeconds = planter:GetAttribute("GrowSeconds") or 60
		local elapsed = now - plantedAt
		local progress = math.clamp(elapsed / growSeconds, 0, 1)

		local plantModel = planter:FindFirstChild("Plant") :: Model?
		if plantModel and plantModel:IsA("Model") then
			CritterVisuals.update(plantModel, progress)
		end

		if progress >= 1.0 and not planter:GetAttribute("Ripe") then
			-- BAB-011: Plants now STAY ripe (waiting for player to walk over).
			planter:SetAttribute("Ripe", true)
			if plantModel and plantModel:IsA("Model") then
				CritterVisuals.markRipe(plantModel, true)
			end
			-- ADR-3: telemetry — pod_ripened (engagement loop health metric)
			local ownerId = planter:GetAttribute("OwnerUserId")
			local owner = ownerId and Players:GetPlayerByUserId(ownerId)
			Telemetry.track("pod_ripened", {
				species = planter:GetAttribute("PlantedSpecies"),
				growSeconds = planter:GetAttribute("GrowSeconds"),
			}, owner)
		end

		-- BAB-STEAMPUNK: pod aether window glows brighter as growth progresses,
		-- and pulses when ripe. Empty pods are dim. The "EmptyBorder" name is
		-- preserved from the legacy planter; in steampunk reskin it's the cyan
		-- glow window in the pod door.
		local border = planter:FindFirstChild("EmptyBorder") :: BasePart?
		if border then
			if planter:GetAttribute("IsEmpty") then
				border.Transparency = 0.85           -- nearly hidden when dormant
			elseif planter:GetAttribute("Ripe") then
				-- Pulse: 0.05 ↔ 0.35 driven by os.clock so it animates smoothly.
				border.Transparency = 0.2 + 0.15 * math.sin(os.clock() * 4)
			else
				border.Transparency = 0.4 - 0.3 * progress  -- ramps from 0.4 → 0.1 as it grows
			end
		end
	end
end)

-- ── Per-pod `.Touched` harvest fallback ────────────────────────────────────
-- The SellPad/ScrapPad auto-harvest covers the common walk-once flow, but
-- pod-by-pod harvest is still useful when the player wants finer control or
-- a particular pod's effect (popup positioning, mutation surprise) without
-- triggering an immediate sell.
local function wirePlanterHarvest(planter: Instance)
	if not planter:IsA("BasePart") then return end
	if planter:GetAttribute("WiredHarvest") then return end
	planter:SetAttribute("WiredHarvest", true)
	local cooldown: { [number]: number } = {}
	planter.Touched:Connect(function(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		if not char then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		local now = os.clock()
		if cooldown[player.UserId] and now - cooldown[player.UserId] < 0.5 then return end
		cooldown[player.UserId] = now
		HarvestFlow.harvestPlanter(player, planter)
	end)
end
for _, p in CollectionService:GetTagged("Planter") do wirePlanterHarvest(p) end
CollectionService:GetInstanceAddedSignal("Planter"):Connect(wirePlanterHarvest)

print("[BAB-LIFE] Critter/GrowLoop online (Heartbeat tick + per-pod harvest fallback)")
