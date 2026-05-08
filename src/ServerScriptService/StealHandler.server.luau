--!strict
-- StealHandler: lets a player steal a fully-grown plant from a neighbor's planter.
-- Mechanic: ProximityPrompt on grown sprouts (added by client). Server validates
-- distance, ownership (must NOT be owner), and shield gamepass. Stolen plants go
-- into the thief's harvest inventory; victim gets a notification.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter") :: ModuleScript)
local Telemetry = require(ServerScriptService:WaitForChild("Telemetry") :: ModuleScript)

local StealAttemptRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("StealAttempt") :: RemoteEvent
local StealNotificationRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("StealNotification") :: RemoteEvent

-- thief inventory keyed by speciesId .. ":" .. mutationId, mirroring PlantHandler.
-- We can't easily share that inventory table, so we directly inject into the
-- victim's planter outcome by writing attributes. Simpler approach: maintain
-- a separate stolen-loot table that pours out at the next sell.
-- For MVP: directly award cash equivalent to the victim's would-be payout (with
-- a 50% steal tax so it's still a steal but not a perfect arbitrage).

local STEAL_TAX = 0.5
local STEAL_COOLDOWN_SEC = 5
local lastSteal: { [number]: number } = {}

StealAttemptRE.OnServerEvent:Connect(function(thief, planter)
	-- ADR-2: rate limit. Existing 5s steal cooldown is per-target — this
	-- caps the global rate per attacker. 0.2/s sustained (12/min), burst 3.
	if not RateLimiter.tryConsume(thief.UserId, "Steal", 0.2, 3) then
		RateLimiter.logViolation(thief, "Steal")
		return
	end
	if typeof(planter) ~= "Instance" or not planter:IsA("BasePart") then return end
	if not planter:HasTag("Planter") then return end
	local ownerId = planter:GetAttribute("OwnerUserId")
	if not ownerId or ownerId == thief.UserId then return end
	-- Must be fully grown
	if planter:GetAttribute("IsEmpty") then return end
	local plantedAt = planter:GetAttribute("PlantedAt") or 0
	local growSeconds = planter:GetAttribute("GrowSeconds") or 60
	if os.time() - plantedAt < growSeconds then return end
	local speciesId = planter:GetAttribute("PlantedSpecies")
	if typeof(speciesId) ~= "string" then return end
	local species = CritterData.get(speciesId)
	if not species then return end

	-- Owner shield (gamepass-driven attribute set by GamepassHandler)
	local owner = Players:GetPlayerByUserId(ownerId)
	if owner and owner:GetAttribute("AntiTheftShield") then
		StealNotificationRE:FireClient(thief, "🛡️ Their shield blocked you!")
		return
	end

	-- Distance check (anti-exploit)
	local thiefChar = thief.Character
	local hrp = thiefChar and thiefChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	if (hrp.Position - planter.Position).Magnitude > 14 then return end

	-- Cooldown
	local now = os.clock()
	if lastSteal[thief.UserId] and now - lastSteal[thief.UserId] < STEAL_COOLDOWN_SEC then return end
	lastSteal[thief.UserId] = now

	-- Roll mutation (same odds as a normal harvest)
	local mutMult = 1
	local mutEmoji = ""
	if math.random() <= species.mutationChance then
		local mut = CritterData.rollMutation()
		if mut then mutMult = mut.multiplier; mutEmoji = mut.emoji end
	end

	local payout = math.floor(species.baseValue * mutMult * STEAL_TAX)
	if payout < 1 then payout = 1 end

	-- Pay thief
	local tls = thief:FindFirstChild("leaderstats")
	if tls then
		local cash = tls:FindFirstChild("Cash") :: IntValue?
		if cash then cash.Value = cash.Value + payout end
	end
	thief:SetAttribute("LifetimeCash", (thief:GetAttribute("LifetimeCash") or 0) + payout)
	thief:SetAttribute("PlantsStolen", (thief:GetAttribute("PlantsStolen") or 0) + 1)

	-- Reset planter
	planter:SetAttribute("IsEmpty", true)
	planter:SetAttribute("PlantedSpecies", nil)
	planter:SetAttribute("PlantedAt", nil)
	planter:SetAttribute("GrowSeconds", nil)
	local sprout = planter:FindFirstChild("Plant")
	if sprout then sprout:Destroy() end

	-- Notify thief + victim
	StealNotificationRE:FireClient(thief, string.format("💰 +$%d stolen %s%s", payout, mutEmoji, species.emoji))
	if owner then
		StealNotificationRE:FireClient(owner, string.format("🚨 %s stole your %s%s!", thief.DisplayName, mutEmoji, species.emoji))
		owner:SetAttribute("PlantsStolenFrom", (owner:GetAttribute("PlantsStolenFrom") or 0) + 1)
	end

	-- ADR-3: telemetry — steal events drive PvP balance + AntiTheft conversion
	Telemetry.track("steal_succeeded", {
		species = species.id,
		payout = payout,
		mutationMult = mutMult,
		victimUserId = ownerId,
	}, thief)
end)

Players.PlayerRemoving:Connect(function(p) lastSteal[p.UserId] = nil end)
