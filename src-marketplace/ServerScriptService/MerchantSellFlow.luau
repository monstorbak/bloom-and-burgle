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

-- BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL: cross-server Hall of Sales
-- leaderboard. Optional require so existing live servers keep working
-- if the module ever fails to load (DataStore down, etc.).
local TrophyData: any = nil
do
	local mod = ReplicatedStorage:FindFirstChild("Modules")
	local td = mod and mod:FindFirstChild("TrophyData")
	if td and td:IsA("ModuleScript") then
		local ok, m = pcall(require, td)
		if ok then TrophyData = m end
	end
end

-- Threshold for what counts as a "notable" sell worth posting to the
-- Hall of Sales. Picked at 5000g per the Phase 4 ticket — covers a
-- mid-stash sale of mutated mid-tier critters but excludes the constant
-- drip of penny-sells that would dominate the board otherwise.
local HALL_OF_SALES_THRESHOLD = 5000

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

-- ── Quote line builder (Phase 3 rich-UI payload) ─────────────────────
-- Convert a per-entry PriceResult + the raw stash key into a wire-friendly
-- record the client can render directly: emoji, displayNames, multiplier
-- breakdown, asset/liability flag.

local function mutationDisplayFor(mutationId: string): (string?, string?)
	if mutationId == "" then return nil, nil end
	for _, m in CritterData.MUTATIONS do
		if m.id == mutationId then return m.displayName, m.emoji end
	end
	return nil, nil
end

-- Build one wire line for the client. cashMult is folded into the lineSubtotal
-- so the client sees per-line numbers that sum to the player's quoted total.
type QuoteLine = {
	key: string,
	speciesId: string,
	speciesName: string,
	speciesEmoji: string,
	mutationId: string,
	mutationName: string?,
	mutationEmoji: string?,
	count: number,
	basePayout: number,
	lineSubtotal: number,
	multiplier: number,
	rawMultiplier: number,
	wasCapped: boolean,
	affinity: string,
	wasSpecial: boolean,
	inPreference: boolean,
	-- Breakdown components for tooltip (echoed from PriceResult).
	basePremium: number,
	preferenceFit: number,
	arbitrageBonus: number,
	specialBonus: number,
	skipReason: string,
}

local function buildLine(key: string, r, count: number, cashMult: number): QuoteLine?
	-- Parse "speciesId:mutationId" key.
	local sep = string.find(key, ":") or 0
	local sId = if sep > 0 then string.sub(key, 1, sep - 1) else key
	local mId = if sep > 0 then string.sub(key, sep + 1) else ""
	local s = CritterData.get(sId)
	if not s then return nil end
	local mName, mEmoji = mutationDisplayFor(mId)
	return {
		key = key,
		speciesId = sId,
		speciesName = s.displayName,
		speciesEmoji = s.emoji,
		mutationId = mId,
		mutationName = mName,
		mutationEmoji = mEmoji,
		count = count,
		basePayout = r.basePayout,
		lineSubtotal = math.floor(r.totalPayout * cashMult),
		multiplier = r.multiplier,
		rawMultiplier = r.rawMultiplier,
		wasCapped = r.wasCapped,
		affinity = r.affinity,
		wasSpecial = r.wasSpecial,
		inPreference = r.inPreference,
		basePremium = r.basePremium,
		preferenceFit = r.preferenceFit,
		arbitrageBonus = r.arbitrageBonus,
		specialBonus = r.specialBonus,
		skipReason = r.skipReason,
	}
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

	-- Phase 3: per-line records for the rich UI. Priced lines sorted by
	-- subtotal descending (most lucrative first); skipped lines (contraband)
	-- in a separate array so the UI renders them as a "won't buy" section.
	local lines: { QuoteLine } = {}
	local skippedLines: { QuoteLine } = {}
	for key, n in stash do
		local r = result.perEntry[key]
		if not r then continue end
		local line = buildLine(key, r, n, cashMult)
		if not line then continue end
		if r.skipReason == "" then
			table.insert(lines, line)
		else
			table.insert(skippedLines, line)
		end
	end
	table.sort(lines, function(a, b) return a.lineSubtotal > b.lineSubtotal end)
	table.sort(skippedLines, function(a, b)
		-- Lexical sort for stable display since subtotals are 0.
		return a.speciesName < b.speciesName
	end)

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
		lines = lines,
		skippedLines = skippedLines,
	})
end

-- ── Commit flow ──────────────────────────────────────────────────────

-- Returns (totalPayout, processedCount, mutationCount, topSpeciesId, topMutationId).
-- topSpeciesId/topMutationId capture the single line with the highest
-- subtotal — used for the Hall of Sales leaderboard's "what was sold"
-- column. Empty strings if nothing was sold (e.g. all contraband).
local function commitSell(npcId: string, player: Player): (number, number, number, string, string)
	local p = MerchantPersonalities.get(npcId)
	if not p then return 0, 0, 0, "", "" end

	local class = playerClass(player)
	local cashMult = (player:GetAttribute("CashMultiplier") :: number?) or 1
	local todaysId = NPCRotation.todaysSpecial(npcId, p.specialRotationPool)

	local payout = 0
	local processed = 0
	local mutationCount = 0
	local capHit = false
	local topSpeciesId = ""
	local topMutationId = ""

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

			-- Find the dominant line (highest perEntry subtotal among priced
			-- entries). Drives the Hall of Sales leaderboard's species column.
			local topSubtotal = 0
			for key, r in result.perEntry do
				if r.skipReason ~= "" then continue end
				local sub = r.totalPayout
				if sub > topSubtotal then
					topSubtotal = sub
					local sep = string.find(key, ":") or 0
					topSpeciesId = if sep > 0 then string.sub(key, 1, sep - 1) else key
					topMutationId = if sep > 0 then string.sub(key, sep + 1) else ""
				end
			end

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

	if not ok then return 0, 0, 0, "", "" end

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

	return payout, processed, mutationCount, topSpeciesId, topMutationId
end

-- ── Public API ───────────────────────────────────────────────────────

-- Wire an NPC's ProximityPrompt to fire a quote when a player triggers it.
-- Called from each NPC's server script after building visuals.
--
-- BAB-ANDROID-TAP-FIX (2026-05-11): also wires ClickDetectors to any
-- BaseParts under the NPC's parent Model so mobile players who tap the
-- 3D NPC directly (instead of the on-screen prompt button) still trigger
-- the sell quote. ProximityPrompt's mobile UI is unreliable when other
-- HUD elements occlude its tap target; ClickDetector is the always-works
-- backstop. Same UX as a Workspace ClickDetector: just walk close + tap.
function M.attachNPC(npcId: string, prompt: ProximityPrompt)
	if not MerchantPersonalities.get(npcId) then
		warn("[MerchantSellFlow] attachNPC: unknown npcId " .. tostring(npcId))
		return
	end
	prompt.Triggered:Connect(function(player)
		quoteFor(npcId, player)
	end)

	-- Attach a ClickDetector to every BasePart in the NPC's containing
	-- model (counter, head, body, sign — any of them tappable). MaxActivation-
	-- Distance matches the ProximityPrompt so we don't accidentally let
	-- players sell from across the plaza.
	local container = prompt.Parent
	if container and container:IsA("Instance") then
		-- Walk up to find the stall Model that wraps the NPC visuals.
		local stall: Instance? = container
		while stall and stall.Parent ~= nil and not (stall:IsA("Model") and stall:FindFirstChildOfClass("Part")) do
			stall = stall.Parent
		end
		local hostModel = stall and stall:IsA("Model") and stall or container
		local parts: { BasePart } = {}
		-- Pull the NPC's own part (prompt's parent) first.
		if container:IsA("BasePart") then table.insert(parts, container :: BasePart) end
		-- Then sweep the surrounding stall model for clickable surfaces.
		if hostModel then
			for _, c in hostModel:GetDescendants() do
				if c:IsA("BasePart") and c ~= container and c.CanQuery ~= false then
					table.insert(parts, c)
				end
			end
		end
		for _, part in parts do
			local existing = part:FindFirstChildOfClass("ClickDetector")
			if existing then continue end
			local cd = Instance.new("ClickDetector")
			cd.Name = "MerchantClick"
			cd.MaxActivationDistance = prompt.MaxActivationDistance
			cd.CursorIcon = ""   -- default cursor; let Roblox theme it
			cd.Parent = part
			cd.MouseClick:Connect(function(player) quoteFor(npcId, player) end)
		end
	end

	-- Print today's special on boot for live-server-log discoverability.
	local _, todaysName = todaysSpecialFor(npcId)
	print(("[BAB-LIFE] %s online (today's special: %s)"):format(npcId, todaysName or "—"))
end

-- Look up today's special for an NPC. NPC server scripts use this to render
-- the plaza-visible "Today's Special" plaque on their stall sign.
-- Returns (speciesId, speciesDisplayName, speciesEmoji) or nil-tuple.
function M.todaysSpecialFor(npcId: string): (string?, string?, string?)
	local sId, sName = todaysSpecialFor(npcId)
	if not sId then return nil, nil, nil end
	local s = CritterData.get(sId)
	return sId, sName, s and s.emoji or nil
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

	local payout, processed, mutations, topSpeciesId, topMutationId = commitSell(npcId, player)

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

	-- BAB-PHASE-4: post notable sells to the cross-server Hall of Sales
	-- leaderboard. Threshold (5000g) excludes the noise-floor of small
	-- starter sales so the board reflects meaningful trophies.
	if TrophyData and payout >= HALL_OF_SALES_THRESHOLD then
		task.spawn(function()
			pcall(function()
				TrophyData.submit("hall_of_sales", {
					userId = player.UserId,
					displayName = player.DisplayName,
					value = payout,
					species = topSpeciesId,
					mutation = topMutationId,
					timestamp = os.time(),
				})
			end)
		end)
	end

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
