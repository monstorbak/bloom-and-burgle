--!strict
-- BrassBart — first NPC merchant in the Marketplace.
--
-- BAB-MARKETPLACE-HUB scaffolding (2026-05-08). v1 of the merchant system:
-- a single NPC who buys any critter from the player's stash at 1.2× the
-- Pawn Forge formula — better than the on-plot fast-sell, but lower than
-- the full marketplace polish (eventual 1.4× for preferred-species, P2P
-- arbitrage at 2×+).
--
-- Per the design ticket, the eventual lineup is 3 NPCs with rotating
-- preferences. This file is the template for the other two
-- (Hexerine "Stitches", Sky Captain Verda); they ship in a follow-on PR.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")

local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))

-- ── Stall placement ──────────────────────────────────────────────────
local STALL_POSITION = Vector3.new(-30, 4, -30)  -- north-west quadrant
local STALL_SIZE = Vector3.new(10, 1, 10)
local PROMPT_RADIUS = 8

-- BAB-MARKETPLACE-HUB v1 sell rate. The on-plot Pawn Forge pays:
--   count * baseValue * mutationMult * cashMult
-- Brass Bart pays 1.2× that per the ticket's "1.0×–1.4× depending on
-- preference fit" rule. v1 has no preferences yet — flat 1.2×.
local BRASS_BART_MULTIPLIER = 1.2
local MAX_PAYOUT = 5_000_000

-- DataStore (shared across all places in the universe).
local DS_KEY = "BloomAndBurgleData_v1"
local dataStore = DataStoreService:GetDataStore(DS_KEY)

-- ── Build the stall ──────────────────────────────────────────────────
local stallModel = Instance.new("Model")
stallModel.Name = "BrassBartStall"
stallModel.Parent = Workspace

local stallPad = Instance.new("Part")
stallPad.Name = "Pad"
stallPad.Anchored = true
stallPad.CanCollide = true
stallPad.Material = Enum.Material.WoodPlanks
stallPad.Color = BrandColors.OilBlack
stallPad.Size = STALL_SIZE
stallPad.Position = STALL_POSITION
stallPad.Parent = stallModel

-- Counter (tall block with a brass top that the player walks up to)
local counter = Instance.new("Part")
counter.Name = "Counter"
counter.Anchored = true
counter.CanCollide = true
counter.Material = Enum.Material.Metal
counter.Color = BrandColors.Brass
counter.Size = Vector3.new(8, 3, 1.4)
counter.Position = STALL_POSITION + Vector3.new(0, 1.7, -3)
counter.Parent = stallModel

-- A flag-pole sign behind the counter
local sign = Instance.new("Part")
sign.Name = "Sign"
sign.Anchored = true
sign.CanCollide = false
sign.Material = Enum.Material.Metal
sign.Color = BrandColors.Brass
sign.Size = Vector3.new(7, 2, 0.5)
sign.Position = STALL_POSITION + Vector3.new(0, 6, -4)
sign.Parent = stallModel

local sgui = Instance.new("SurfaceGui")
sgui.Face = Enum.NormalId.Front
sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
sgui.PixelsPerStud = 50
sgui.Parent = sign
local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.fromScale(1, 1)
lbl.BackgroundTransparency = 1
lbl.Text = "⚙ BRASS BART — buys critters @ 1.2×"
lbl.TextColor3 = BrandColors.OilBlack
lbl.Font = Enum.Font.Antique
lbl.TextScaled = true
lbl.Parent = sgui

-- The NPC body — a humanoid stand-in. Single-block charcoal column with
-- a brass cap (face); proper character authoring is a P2 polish task.
local npc = Instance.new("Part")
npc.Name = "BrassBart"
npc.Anchored = true
npc.CanCollide = false
npc.Material = Enum.Material.Metal
npc.Color = BrandColors.IronworkCharcoal
npc.Size = Vector3.new(2, 5, 2)
npc.Position = STALL_POSITION + Vector3.new(0, 3, -4.5)
npc.Parent = stallModel

local head = Instance.new("Part")
head.Name = "Head"
head.Shape = Enum.PartType.Ball
head.Anchored = true
head.CanCollide = false
head.Material = Enum.Material.Metal
head.Color = BrandColors.Brass
head.Size = Vector3.new(1.6, 1.6, 1.6)
head.Position = STALL_POSITION + Vector3.new(0, 6.2, -4.5)
head.Parent = stallModel

-- The interaction prompt. Player presses E within 8 studs.
local prompt = Instance.new("ProximityPrompt")
prompt.Name = "BrassBartPrompt"
prompt.ActionText = "Sell to Brass Bart"
prompt.ObjectText = "⚙ Brass Bart"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = PROMPT_RADIUS
prompt.RequiresLineOfSight = false
prompt.Parent = npc

-- ── RemoteEvent for the client UI ────────────────────────────────────
-- The marketplace shares ReplicatedStorage.RemoteEvents with the Hatchery
-- (via $path in default-marketplace.project.json), so we look for an
-- existing MarketplaceSell RE first.
local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local MarketplaceSellRE = remotes:FindFirstChild("MarketplaceSell")
if not MarketplaceSellRE then
	MarketplaceSellRE = Instance.new("RemoteEvent")
	MarketplaceSellRE.Name = "MarketplaceSell"
	MarketplaceSellRE.Parent = remotes
end
assert(MarketplaceSellRE)

-- ── Sell logic ───────────────────────────────────────────────────────
-- Read the player's stash from the DataStore (the source of truth across
-- places). The Hatchery's MarketplacePortal flushes a snapshot just
-- before teleport so this read is fresh.
local function readStash(player: Player): { [string]: number }
	local key = "player_" .. tostring(player.UserId)
	local ok, data = pcall(function() return dataStore:GetAsync(key) end)
	if not ok or typeof(data) ~= "table" then return {} end
	local plot = data.plot
	if typeof(plot) ~= "table" then return {} end
	local stash = plot.stash
	if typeof(stash) ~= "table" then return {} end
	-- Defensive copy — never hand out the raw saved table.
	local out: { [string]: number } = {}
	for k, v in stash do
		if typeof(k) == "string" and typeof(v) == "number" and v > 0 then
			out[k] = v
		end
	end
	return out
end

-- Compute the sell value for the entire stash at Brass Bart's rate.
-- Returns (totalPayout, processedCount, mutationCount).
local function valueOf(stash: { [string]: number }): (number, number, number)
	local total = 0
	local count = 0
	local mutationCount = 0
	for key, n in stash do
		local sep = string.find(key, ":") or 0
		local sId = string.sub(key, 1, sep - 1)
		local mId = string.sub(key, sep + 1)
		local species = CritterData.get(sId)
		if not species then continue end
		local mult = 1
		if mId ~= "" then
			for _, m in CritterData.MUTATIONS do
				if m.id == mId then mult = m.multiplier; mutationCount += n; break end
			end
		end
		total += n * species.baseValue * mult
		count += n
	end
	return total, count, mutationCount
end

-- Persist the sell: clear stash, credit cash, write back via UpdateAsync
-- for atomicity.
local function commitSell(player: Player): (number, number)
	local key = "player_" .. tostring(player.UserId)
	local payout = 0
	local processed = 0
	local ok = pcall(function()
		dataStore:UpdateAsync(key, function(data)
			if typeof(data) ~= "table" then return data end
			data.plot = data.plot or {}
			data.plot.stash = data.plot.stash or {}
			-- Compute payout from the AT-COMMIT-TIME stash (the read above
			-- was just for UI estimation; the source of truth is here).
			local total, c = valueOf(data.plot.stash)
			-- Apply Brass Bart's multiplier + the player's own CashMultiplier.
			local cashMult = player:GetAttribute("CashMultiplier") or 1
			total = math.floor(total * BRASS_BART_MULTIPLIER * cashMult)
			if total > MAX_PAYOUT then total = MAX_PAYOUT end
			data.cash = (data.cash or 0) + total
			data.lifetimeCash = (data.lifetimeCash or 0) + total
			data.plot.stash = {}
			payout = total
			processed = c
			return data
		end)
	end)
	if not ok then return 0, 0 end
	-- Mirror the cash bump onto the live leaderstats so the HUD updates
	-- without a fresh DataStore round-trip.
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash") :: IntValue?
		if cash then cash.Value = cash.Value + payout end
	end
	player:SetAttribute("LifetimeCash", (player:GetAttribute("LifetimeCash") or 0) + payout)
	return payout, processed
end

-- ── Wire prompt + RemoteEvent ────────────────────────────────────────
prompt.Triggered:Connect(function(player)
	-- Send the player a quote (read-only, doesn't commit).
	local stash = readStash(player)
	local total, count, mutations = valueOf(stash)
	local cashMult = player:GetAttribute("CashMultiplier") or 1
	local quotedPayout = math.floor(total * BRASS_BART_MULTIPLIER * cashMult)
	if quotedPayout > MAX_PAYOUT then quotedPayout = MAX_PAYOUT end
	MarketplaceSellRE:FireClient(player, "quote", {
		merchant = "BrassBart",
		quotedPayout = quotedPayout,
		count = count,
		mutations = mutations,
		multiplier = BRASS_BART_MULTIPLIER,
	})
end)

MarketplaceSellRE.OnServerEvent:Connect(function(player, action)
	if action ~= "confirm_brass_bart" then return end
	local payout, processed = commitSell(player)
	MarketplaceSellRE:FireClient(player, "result", {
		merchant = "BrassBart",
		payout = payout,
		count = processed,
	})
end)

print("[BAB-LIFE] BrassBart online (multiplier=" .. BRASS_BART_MULTIPLIER .. "x)")
