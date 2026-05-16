--!strict
-- DailyRewardChest — once-per-24h reward chest at the Brass Clocktower base.
--
-- BAB-DESIGN-CRITIQUE Tier 2 (2026-05-10).
--
-- ── Why this exists ──────────────────────────────────────────────────
-- Habit-forming retention: a daily-claim mechanic gives players a
-- non-grindy reason to log in every day. Pet Sim, Adopt Me, every
-- successful Roblox economy game ships this. We don't have one yet.
--
-- The chest also anchors the Tinkerer's Pass gamepass monetization
-- loop: pass holders get 2× the reward, forever. Pure retention →
-- pure conversion vector.
--
-- ── Mechanics ────────────────────────────────────────────────────────
-- Position: (0, 4, -10) — north side of Clocktower base, between
--   spawn (at z=12) and the Clocktower (at z=0). First thing a new
--   player walks past.
-- Interaction: ProximityPrompt, "Open daily chest"
-- Cooldown: 24h IRL, tracked via DataStore (BAB_DailyReward_v1).
-- Reward (base): 500g
-- Reward (Tinkerer's Pass): 1000g (2× multiplier)
-- Future: streak bonuses (Tier 3) — extra reward on consecutive days.
--
-- ── DataStore key shape ──────────────────────────────────────────────
-- DS key: BAB_DailyReward_v1
-- player_<userId> -> {
--   lastClaimSec = number,    -- os.time() of last successful claim
-- }
-- UpdateAsync used for atomic claim (anti-double-claim across the
-- millisecond gap between read and write).

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local UIComponents = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIComponents"))
local TinkererPass = require(ServerScriptService:WaitForChild("TinkererPass") :: ModuleScript) :: any

-- Optional Telemetry / RateLimiter — graceful when unavailable.
local Telemetry: any = nil
do
	local tm = ServerScriptService:FindFirstChild("Telemetry")
	if tm and tm:IsA("ModuleScript") then
		local ok, mod = pcall(require, tm); if ok then Telemetry = mod end
	end
end
local RateLimiter: any = nil
do
	local rl = ServerScriptService:FindFirstChild("RateLimiter")
	if rl and rl:IsA("ModuleScript") then
		local ok, mod = pcall(require, rl); if ok then RateLimiter = mod end
	end
end

-- ── Config ───────────────────────────────────────────────────────────
local DS_KEY = "BAB_DailyReward_v1"
local CHEST_POS = Vector3.new(0, 4, -10)
local CHEST_SIZE = Vector3.new(5, 4, 4)
local COOLDOWN_SECONDS = 24 * 60 * 60
local BASE_PAYOUT = 500
local PROMPT_DISTANCE = 8

local dataStore = DataStoreService:GetDataStore(DS_KEY)

-- ── Build the chest visuals ─────────────────────────────────────────
local chest = Instance.new("Model")
chest.Name = "DailyRewardChest"
chest.Parent = Workspace

-- Chest body — chunky brass cube with iron banding.
local body = Instance.new("Part")
body.Name = "Body"
body.Anchored = true
body.CanCollide = true
body.Material = Enum.Material.Metal
body.Color = BrandColors.Brass
body.Size = CHEST_SIZE
body.Position = CHEST_POS
body.Parent = chest

-- Iron horizontal bands across the chest body.
for _, yOffset in { -1, 0, 1 } do
	local band = Instance.new("Part")
	band.Name = "Band"
	band.Anchored = true; band.CanCollide = false
	band.Material = Enum.Material.Metal
	band.Color = BrandColors.IronworkCharcoal
	band.Size = Vector3.new(CHEST_SIZE.X + 0.2, 0.4, CHEST_SIZE.Z + 0.2)
	band.Position = CHEST_POS + Vector3.new(0, yOffset * 0.8, 0)
	band.Parent = chest
end

-- Aether-glow lock plate on the front — telegraphs "interactive".
local lock = Instance.new("Part")
lock.Name = "Lock"
lock.Anchored = true; lock.CanCollide = false
lock.Material = Enum.Material.Neon
lock.Color = BrandColors.AetherCyan
lock.Size = Vector3.new(1.2, 1.6, 0.4)
lock.Position = CHEST_POS + Vector3.new(0, 0, CHEST_SIZE.Z / 2 + 0.2)
lock.Parent = chest

-- Faint PointLight from the lock — pulses are added in Tier 3.
local lockLight = Instance.new("PointLight")
lockLight.Color = BrandColors.AetherCyan
lockLight.Brightness = 1.5
lockLight.Range = 8
lockLight.Parent = lock

-- Floating BillboardGui labeling the chest — visible above any nearby
-- player so it doesn't get camouflaged against the busy plaza.
local label = Instance.new("BillboardGui")
label.Name = "ChestLabel"
label.Size = UDim2.fromOffset(220, 50)
label.StudsOffset = Vector3.new(0, 4, 0)
label.AlwaysOnTop = true
label.MaxDistance = 60
label.Parent = body
local labelText = UIComponents.buildHeader({
	name = "LabelText",
	text = "🎁 DAILY CHEST",
	size = UDim2.fromScale(1, 1),
	color = BrandColors.GoggleGold,
	alignment = Enum.TextXAlignment.Center,
	maxTextSize = 28,
})
labelText.Parent = label

-- ProximityPrompt for the actual interaction.
local prompt = Instance.new("ProximityPrompt")
prompt.Name = "OpenChest"
prompt.ActionText = "Open"
prompt.ObjectText = "Daily Chest"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.MaxActivationDistance = PROMPT_DISTANCE
prompt.HoldDuration = 0
prompt.RequiresLineOfSight = false
prompt.Parent = body

CollectionService:AddTag(body, "DailyRewardChest")

-- ── Reward toast (BillboardGui shown after a successful claim) ──────
local function spawnRewardToast(player: Player, payout: number, isPassHolder: boolean)
	-- Server-side BillboardGui parented to the chest, visible only to
	-- the claimer for 3s. Cheap, no client roundtrip required.
	local toast = Instance.new("BillboardGui")
	toast.Size = UDim2.fromOffset(280, 80)
	toast.StudsOffset = Vector3.new(0, 6, 0)
	toast.AlwaysOnTop = true
	toast.Parent = body
	toast.PlayerToHideFrom = nil   -- visible to all; cheap social proof
	local txt = UIComponents.buildHeader({
		text = isPassHolder and string.format("🎩 +%dg (Pass 2×!)", payout)
		                     or string.format("💰 +%dg", payout),
		size = UDim2.fromScale(1, 1),
		color = isPassHolder and BrandColors.GoggleGold or BrandColors.SteamCream,
		alignment = Enum.TextXAlignment.Center,
		maxTextSize = 32,
	})
	txt.Parent = toast
	task.delay(3, function() toast:Destroy() end)
end

-- ── Claim flow ──────────────────────────────────────────────────────

local function dataKey(player: Player): string
	return "player_" .. tostring(player.UserId)
end

-- Attempt to claim. Returns (success, payout, secondsRemaining).
-- On cooldown, payout = 0 and secondsRemaining > 0.
local function tryClaim(player: Player): (boolean, number, number)
	local now = os.time()
	local multiplier = TinkererPass.payoutMultiplier(player)
	local payout = BASE_PAYOUT * multiplier
	local remaining = 0
	local success = false

	local ok = pcall(function()
		dataStore:UpdateAsync(dataKey(player), function(data)
			data = (typeof(data) == "table") and data or {}
			local last = (typeof(data.lastClaimSec) == "number") and data.lastClaimSec or 0
			local elapsed = now - last
			if elapsed < COOLDOWN_SECONDS then
				remaining = COOLDOWN_SECONDS - elapsed
				return data   -- no write
			end
			data.lastClaimSec = now
			success = true
			return data
		end)
	end)
	if not ok then return false, 0, 0 end
	return success, success and payout or 0, remaining
end

prompt.Triggered:Connect(function(player: Player)
	if not player or not player.Parent then return end

	-- ADR-2 rate-limit gate — daily chest is currency-mutating.
	-- Generous: 2/min (player might double-tap E).
	if RateLimiter and not RateLimiter.tryConsume(player.UserId, "DailyChest", 0.5, 2) then
		return
	end

	local success, payout, remaining = tryClaim(player)
	if not success then
		-- On cooldown — show a brief toast with how long is left.
		local hours = math.floor(remaining / 3600)
		local mins = math.floor((remaining % 3600) / 60)
		local cooldownToast = Instance.new("BillboardGui")
		cooldownToast.Size = UDim2.fromOffset(260, 60)
		cooldownToast.StudsOffset = Vector3.new(0, 6, 0)
		cooldownToast.AlwaysOnTop = true
		cooldownToast.Parent = body
		local txt = UIComponents.buildHeader({
			text = string.format("⏳ Back in %dh %dm", hours, mins),
			size = UDim2.fromScale(1, 1),
			color = BrandColors.SteamCream,
			alignment = Enum.TextXAlignment.Center,
			maxTextSize = 24,
		})
		txt.Parent = cooldownToast
		task.delay(2.5, function() cooldownToast:Destroy() end)
		return
	end

	-- Award the cash by mirroring the same pattern other handlers use:
	-- bump leaderstats Cash IntValue + telemetry.
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash") :: IntValue?
		if cash then cash.Value = cash.Value + payout end
	end
	player:SetAttribute("LifetimeCash", (player:GetAttribute("LifetimeCash") or 0) + payout)

	local isPass = TinkererPass.hasPass(player)
	spawnRewardToast(player, payout, isPass)

	if Telemetry then
		pcall(function()
			Telemetry.track("daily_reward_claimed", {
				payout = payout,
				tinkererPass = isPass,
				class = player:GetAttribute("Class"),
			}, player)
		end)
	end
end)

print(string.format(
	"[BAB-LIFE] DailyRewardChest online — base=%dg, %d-hour cooldown, Tinkerer's Pass = 2× payout",
	BASE_PAYOUT, COOLDOWN_SECONDS / 3600
))
