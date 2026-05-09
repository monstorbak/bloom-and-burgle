--!strict
-- MerchantSellFlow — shared sell-flow helper for marketplace NPC merchants.
--
-- BAB-MARKETPLACE-NPC-ROTATION (2026-05-08).
--
-- Each NPC server script (BrassBart, Hexerine, Verda) builds its OWN visuals
-- and ProximityPrompt, then calls `MerchantSellFlow.attachNPC(npcId, prompt)`
-- to wire it into the shared sell flow. This module:
--
--   1. Registers a single OnServerEvent listener (no duplicate listeners
--      across the 3 NPC scripts).
--   2. Reads each player's stash from the shared DataStore.
--   3. Computes per-line pricing via the pure MerchantPricing module.
--   4. Quotes the player a total via "quote" RemoteEvent payload.
--   5. On client confirm, atomically commits the sell via UpdateAsync.
--   6. Gates currency-mutating handler with RateLimiter (per ADR-2).
--   7. Emits Telemetry.track("sell_payout", ...) per ADR-3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")

local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local MerchantPricing = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MerchantPricing"))
local MerchantPersonalities = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MerchantPersonalities"))
local NPCRotation = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NPCRotation"))

local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter")) :: any
local Telemetry = require(ServerScriptService:WaitForChild("Telemetry")) :: any

local M = {}

-- ── DataStore ────────────────────────────────────────────────────────
local DS_KEY = "BloomAndBurgleData_v1"
local dataStore = DataStoreService:GetDataStore(DS_KEY)

-- ── Per-sell guardrail ───────────────────────────────────────────────
-- Same MAX_PAYOUT as the on-plot Pawn Forge per
-- src/ServerScriptService/Critter/EconomyPad.luau:MAX_SELL_PAYOUT.
-- Anti-exploit: even with capped 3× multiplier, ember-mutated mythics
-- could otherwise produce silly numbers.
local MAX_PAYOUT = 5_000_000

-- ── RemoteEvent (shared with all 3 NPCs + the client UI) ─────────────
local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local MarketplaceSellRE = remotes:FindFirstChild("MarketplaceSell")
if not MarketplaceSellRE then
	MarketplaceSellRE = Instance.new("RemoteEvent")
	MarketplaceSellRE.Name = "MarketplaceSell"
	MarketplaceSellRE.Parent = remotes
end
assert(MarketplaceSellRE)

-- ── State ────────────────────────────────────────────────────────────
-- Round-robin dialogue index per (npcId, userId) so each player sees
-- progressive lines instead of random repeats.
local dialogueIndex: { [string]: number } = {}

-- ── Helpers ──────────────────────────────────────────────────────────

local function dataKey(player: Player): string
	return "player_" .. tostring(player.UserId)
end

-- Read player's stash (shared DataStore key). Returns empty table on read
-- failure so the player still gets a no-op quote (no toast spam).
local function readStash(player: Player): { [string]: number }
	local ok, data = pcall(function() return dataStore:GetAsync(dataKey(player)) end)
	if not ok or typeof(data) ~= "table" then return {} end
	local plot = data.plot
	if typeof(plot) ~= "table" then return {} end
	local stash = plot.stash
	if typeof(stash) ~= "table" then return {} end
	-- Defensive copy.
	local out: { [string]: number } = {}
	for k, v in stash do
		if typeof(k) == "string" and typeof(v) == "number" and v > 0 then
			out[k] = v
		end
	end
	return out
end

-- Player's class id (set by the Hatchery's class-pick flow). Defaults to
-- "knight" (a real class) so the affinity matrix lookup never returns nil
-- shape — but for new accounts we want this to be the player's real class.
-- The Hatchery sets this attribute on PlayerAdded; surviving teleport via
-- Roblox's attribute carry-over.
local function playerClass(player: Player): string
	local c = player:GetAttribute("Class")
	if typeof(c) == "string" and c ~= "" then return c end
	return "knight"
end

-- Round-robin a personality's dialogue lines per (npc, player).
local function nextDialogueLine(npcId: string, player: Player): string
	local p = MerchantPersonalities.get(npcId)
	if not p or #p.dialogue == 0 then return "" end
	local key = npcId .. ":" .. tostring(player.UserId)
	local i = (dialogueIndex[key] or 0) + 1
	if i > #p.dialogue then i = 1 end
	dialogueIndex[key] = i
	return p.dialogue[i]
end

-- Today's special (with display name) for the NPC.
local function todaysSpecialFor(npcId: string): (string?, string?)
	local p = MerchantPersonalities.get(npcId)
	if not p then return nil, nil end
	local sId = NPCRotation.todaysSpecial(npcId, p.specialRotationPool)
	if not sId then return nil, nil end
	local s = CritterData.get(sId)
	return sId, s and s.displayName
end

-- ── Quote flow ───────────────────────────────────────────────────────

local function quoteFor(npcId: string, player: Player)
	local p = MerchantPersonalities.get(npcId)
	if not p then return end

	local stash = readStash(player)
	local class = playerClass(player)
	local cashMult = (player:GetAttribute("CashMultiplier") :: number?) or 1
	local todaysId, todaysName = todaysSpecialFor(npcId)

	local result = MerchantPricing.priceStash({
		npcId = npcId,
		stash = stash,
		playerClass = class,
		todaysSpecialOverride = todaysId,
	})

	local quoted = math.floor(result.totalPayout * cashMult)
	if quoted > MAX_PAYOUT then quoted = MAX_PAYOUT end

	-- Average multiplier across priced lines (for UI display "Bart pays 1.4×").
	-- Excludes skipped (contraband) lines from the denominator.
	local sumBase = 0
	for _, r in result.perEntry do
		if r.skipReason == "" then sumBase += r.basePayout end
	end
	local avgMultiplier = sumBase > 0 and (result.totalPayout / sumBase) or p.basePremium

	MarketplaceSellRE:FireClient(player, "quote", {
		npcId = p.id,
		displayName = p.displayName,
		emoji = p.emoji,
		dialogueLine = nextDialogueLine(npcId, player),
		quotedPayout = quoted,
		count = result.totalCount,
		mutations = result.mutationCount,
		skippedCount = result.skippedCount,
		avgMultiplier = avgMultiplier,
		todaysSpecialId = todaysId,
		todaysSpecialName = todaysName,
	})
end

-- ── Commit flow ──────────────────────────────────────────────────────

-- Returns (totalPayout, processedCount, mutationCount).
local function commitSell(npcId: string, player: Player): (number, number, number)
	local p = MerchantPersonalities.get(npcId)
	if not p then return 0, 0, 0 end

	local class = playerClass(player)
	local cashMult = (player:GetAttribute("CashMultiplier") :: number?) or 1
	local todaysId = NPCRotation.todaysSpecial(npcId, p.specialRotationPool)

	local payout = 0
	local processed = 0
	local mutationCount = 0
	local capHit = false

	local ok = pcall(function()
		dataStore:UpdateAsync(dataKey(player), function(data)
			if typeof(data) ~= "table" then return data end
			data.plot = data.plot or {}
			data.plot.stash = data.plot.stash or {}

			-- Re-price at commit time from the source-of-truth stash.
			local result = MerchantPricing.priceStash({
				npcId = npcId,
				stash = data.plot.stash,
				playerClass = class,
				todaysSpecialOverride = todaysId,
			})

			local raw = math.floor(result.totalPayout * cashMult)
			if raw > MAX_PAYOUT then
				raw = MAX_PAYOUT
				capHit = true
			end

			data.cash = (data.cash or 0) + raw
			data.lifetimeCash = (data.lifetimeCash or 0) + raw

			-- Clear ONLY the stash lines we actually paid for. Contraband / skipped
			-- entries stay in the stash for the player to scrap later.
			local remaining: { [string]: number } = {}
			for key, n in data.plot.stash do
				local r = result.perEntry[key]
				if not r or r.skipReason ~= "" then
					remaining[key] = n
				end
			end
			data.plot.stash = remaining

			payout = raw
			processed = result.totalCount
			mutationCount = result.mutationCount
			return data
		end)
	end)

	if not ok then return 0, 0, 0 end

	-- Mirror cash bump onto live leaderstats (no extra DataStore round-trip).
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash") :: IntValue?
		if cash then cash.Value = cash.Value + payout end
	end
	player:SetAttribute("LifetimeCash", (player:GetAttribute("LifetimeCash") or 0) + payout)

	if capHit then
		warn(("[%s] payout cap hit for %s — clamped to %d"):format(npcId, player.Name, MAX_PAYOUT))
	end

	return payout, processed, mutationCount
end

-- ── Public API ───────────────────────────────────────────────────────

-- Wire an NPC's ProximityPrompt to fire a quote when a player triggers it.
-- Called from each NPC's server script after building visuals.
function M.attachNPC(npcId: string, prompt: ProximityPrompt)
	if not MerchantPersonalities.get(npcId) then
		warn("[MerchantSellFlow] attachNPC: unknown npcId " .. tostring(npcId))
		return
	end
	prompt.Triggered:Connect(function(player)
		quoteFor(npcId, player)
	end)
	-- Print today's special on boot for live-server-log discoverability.
	local _, todaysName = todaysSpecialFor(npcId)
	print(("[BAB-LIFE] %s online (today's special: %s)"):format(npcId, todaysName or "—"))
end

-- ── Single dispatch listener for confirm ─────────────────────────────
-- Client fires: MarketplaceSellRE:FireServer("confirm", npcId).
MarketplaceSellRE.OnServerEvent:Connect(function(player, action, npcId)
	if action ~= "confirm" then return end
	if typeof(npcId) ~= "string" then return end

	local p = MerchantPersonalities.get(npcId)
	if not p then return end

	-- ADR-2 anti-exploit gate. 1 confirm per second sustained, burst 3 (so
	-- a bumpy network can deliver 3 quick clicks without over-rejecting,
	-- but a script can't dump 100 confirms/sec).
	if not RateLimiter.tryConsume(player.UserId, "MarketplaceSell:" .. npcId, 1, 3) then
		RateLimiter.logViolation(player, "MarketplaceSell:" .. npcId, "marketplace_npc")
		return
	end

	local payout, processed, mutations = commitSell(npcId, player)

	-- ADR-3 telemetry. Emitting on the server side (single source of truth)
	-- so client-spoofed events can't pollute the funnel.
	pcall(function()
		Telemetry.track("sell_payout", {
			merchant = "marketplace_npc",
			npcId = npcId,
			payout = payout,
			processed = processed,
			mutations = mutations,
			class = playerClass(player),
			cashMult = player:GetAttribute("CashMultiplier") or 1,
		}, player)
	end)

	MarketplaceSellRE:FireClient(player, "result", {
		npcId = npcId,
		displayName = p.displayName,
		emoji = p.emoji,
		payout = payout,
		count = processed,
	})
end)

-- Cleanup dialogue index on PlayerRemoving so we don't grow unbounded.
Players.PlayerRemoving:Connect(function(player)
	for k in dialogueIndex do
		if string.sub(k, -#tostring(player.UserId)) == tostring(player.UserId) then
			dialogueIndex[k] = nil
		end
	end
end)

return M
