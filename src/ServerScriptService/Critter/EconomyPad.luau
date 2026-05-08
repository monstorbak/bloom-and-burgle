--!strict
-- EconomyPad — shared sell+scrap converter.
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). Replaces the two
-- _doSellInventory + _doScrapInventory blocks (and their four call sites:
-- SellPad.Touched, ScrapPad.Touched, ProximityPulse sell branch, ProximityPulse
-- scrap branch) with a single parameterized `convert(player, kind, source)`
-- function.
--
-- Both kinds share:
--   - rate-limit gate (RateLimiter.tryConsume)
--   - "auto-harvest ripe pods first" pre-scan (HarvestFlow.harvestAllRipeForPlayer)
--   - per-player .5s cooldown shared across .Touched + proximity callers
--   - payout-cap clamp (logged as exploit violation but pays out clamped value)
--   - telemetry event (sell_payout / scrap_payout)
--   - client-facing RemoteEvent fire (SellPlants / ScrapPlants)
--
-- They differ in:
--   - rate-limit key + telemetry event name
--   - the "convert one inventory entry to a payout" rule (cash vs cog parts)
--   - whether `Sacred`-tagged species are skipped (scrap only)
--   - which currency the payout flows into (Cash IntValue vs CogParts attribute)
--
-- The differences are encoded as a `Rule` struct, one per kind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter") :: ModuleScript)
local Telemetry = require(ServerScriptService:WaitForChild("Telemetry") :: ModuleScript)
local CritterRegistry = require(script.Parent:WaitForChild("CritterRegistry") :: ModuleScript)
local HarvestFlow = require(script.Parent:WaitForChild("HarvestFlow") :: ModuleScript)

local SellPlantsRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SellPlants") :: RemoteEvent
local ScrapPlantsRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ScrapPlants") :: RemoteEvent

local EconomyPad = {}

-- ADR-2 sanity caps. Single-fire payout above this threshold is logged as
-- a violation but still pays out (legitimate luck on Mythic + Coal Drake +
-- Celestial mutation isn't penalized). The cap exists to bound the blast
-- radius of a save-pollution attack to ~$5M (sell) or 100K cog parts.
EconomyPad.MAX_SELL_PAYOUT = 5000000
EconomyPad.MAX_SCRAP_PAYOUT = 100000

-- ADR-2: per-player .5s cooldown shared across .Touched + proximity. Both
-- pads fire on the same walk-over window so we keep cooldowns global to the
-- module, not per-pad-instance.
local sellCooldown: { [number]: number } = {}
local scrapCooldown: { [number]: number } = {}

local function checkCooldown(table: { [number]: number }, uid: number, window: number): boolean
	local now = os.clock()
	if table[uid] and now - table[uid] < window then return false end
	table[uid] = now
	return true
end

-- Drop cooldown state for a player. Called from Players.PlayerRemoving
-- via PlantingFlow.server.luau so we don't leak per-user state.
function EconomyPad.clearCooldownsFor(player: Player)
	sellCooldown[player.UserId] = nil
	scrapCooldown[player.UserId] = nil
end

-- Returns true if the player is allowed to fire a sell event this tick.
-- Both .Touched + proximity check this before attempting to convert.
function EconomyPad.checkSellCooldown(player: Player): boolean
	return checkCooldown(sellCooldown, player.UserId, 0.5)
end
function EconomyPad.checkScrapCooldown(player: Player): boolean
	return checkCooldown(scrapCooldown, player.UserId, 0.5)
end

type Rule = {
	kind: string,                  -- "sell" | "scrap"
	rateLimitKey: string,          -- "Sell" | "Scrap"
	rateLimitPerSec: number,
	rateLimitBurst: number,
	maxPayout: number,
	telemetryEvent: string,        -- "sell_payout" | "scrap_payout"
	skipSacred: boolean,           -- scrap skips Sacred-tagged species
	-- Per-entry value: takes (species, mutationId, count) → number.
	valueOf: (species: any, mutationId: string, count: number) -> number,
	-- Apply payout to player's wallet. Returns nothing.
	pay: (player: Player, total: number) -> (),
	-- Fire client-side notification. (player, total, skipped). `skipped` is
	-- only used by scrap; sell ignores it.
	notify: (player: Player, total: number, skipped: number) -> (),
}

-- Multiplier-aware sell value (cash). Honors CritterData.MUTATIONS multipliers
-- and the player's CashMultiplier attribute (from gamepasses).
local function sellValueOf(species: any, mutationId: string, count: number): number
	local mult = 1
	if mutationId ~= "" then
		for _, m in CritterData.MUTATIONS do
			if m.id == mutationId then mult = m.multiplier; break end
		end
	end
	return count * species.baseValue * mult
end

-- Scrap value (cog parts). Flat per species, no mutation modifier — scrap
-- is the consolation prize when the cash economy isn't ready for inventory.
local function scrapValueOf(species: any, _mutationId: string, count: number): number
	return count * species.scrapValue
end

local SELL_RULE: Rule = {
	kind = "sell",
	rateLimitKey = "Sell",
	rateLimitPerSec = 0.25,
	rateLimitBurst = 4,
	maxPayout = EconomyPad.MAX_SELL_PAYOUT,
	telemetryEvent = "sell_payout",
	skipSacred = false,
	valueOf = sellValueOf,
	pay = function(player: Player, total: number)
		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local cash = ls:FindFirstChild("Cash") :: IntValue?
			if cash then cash.Value = cash.Value + total end
		end
		local lifetime = (player:GetAttribute("LifetimeCash") or 0) + total
		player:SetAttribute("LifetimeCash", lifetime)
	end,
	notify = function(player: Player, total: number, _skipped: number)
		SellPlantsRE:FireClient(player, total)
	end,
}

local SCRAP_RULE: Rule = {
	kind = "scrap",
	rateLimitKey = "Scrap",
	rateLimitPerSec = 0.25,
	rateLimitBurst = 4,
	maxPayout = EconomyPad.MAX_SCRAP_PAYOUT,
	telemetryEvent = "scrap_payout",
	skipSacred = true,
	valueOf = scrapValueOf,
	pay = function(player: Player, total: number)
		player:SetAttribute("CogParts", (player:GetAttribute("CogParts") or 0) + total)
	end,
	notify = function(player: Player, total: number, skipped: number)
		ScrapPlantsRE:FireClient(player, total, skipped)
	end,
}

-- Apply one of SELL_RULE / SCRAP_RULE to a player's full inventory.
-- `source` is "touched" | "proximity" — used in the rate-limit log + telemetry.
-- Returns (totalPayout, skipped).
local function applyRule(rule: Rule, player: Player, source: string): (number, number)
	-- ADR-2: rate-limit. .25/s sustained (15/min) with burst of 4 — fits
	-- legitimate spam-walks during a Mythic harvest moment but caps a
	-- botted exploit.
	if not RateLimiter.tryConsume(player.UserId, rule.rateLimitKey, rule.rateLimitPerSec, rule.rateLimitBurst) then
		RateLimiter.logViolation(player, rule.rateLimitKey, "source=" .. source)
		return 0, 0
	end

	-- BAB-FINDABILITY 2: auto-harvest any ripe pods first so a single walk
	-- through a sell pad both harvests + sells.
	HarvestFlow.harvestAllRipeForPlayer(player)

	local inv = CritterRegistry.getInv(player)
	local total = 0
	local processedCount = 0
	local mutationCount = 0
	local mythicSold = false
	local skipped = 0

	for key, count in inv do
		if count <= 0 then continue end
		local sep = string.find(key, ":") or 0
		local sId = string.sub(key, 1, sep - 1)
		local mId = string.sub(key, sep + 1)
		local species = CritterData.get(sId)
		if not species then continue end

		if rule.skipSacred and species.tag == "Sacred" then
			skipped += count
			continue
		end

		if mId ~= "" then
			mutationCount += count
		end
		if species.rarity == "Mythic" then mythicSold = true end

		total += rule.valueOf(species, mId, count)
		processedCount += count
		inv[key] = 0
	end

	-- Sell-only: apply CashMultiplier gamepass bonus + floor.
	if rule.kind == "sell" and total > 0 then
		local cashMult = player:GetAttribute("CashMultiplier") or 1
		total = math.floor(total * cashMult)
	end

	-- ADR-2: payout-cap. Log as violation but pay out clamped value so
	-- legitimate big sells survive — only attackers see the clamp.
	if total > rule.maxPayout then
		RateLimiter.logViolation(
			player,
			rule.rateLimitKey .. ".payout_cap",
			string.format("requested=%d clamped=%d", total, rule.maxPayout)
		)
		total = rule.maxPayout
	end

	if rule.kind == "sell" and total <= 0 then
		-- Sell with nothing to sell: stay silent (matches legacy behavior).
		return 0, 0
	end

	if total > 0 then
		rule.pay(player, total)
	end
	if total > 0 or skipped > 0 then
		rule.notify(player, total, skipped)
	end

	-- ADR-3: telemetry. Always emit so we see "Sacred-skipped" funnels and
	-- empty-walk-over events.
	local cashMult = player:GetAttribute("CashMultiplier") or 1
	Telemetry.track(rule.telemetryEvent, {
		amount = total,
		count = processedCount,
		mutations = mutationCount,
		mythic = mythicSold,
		sacredSkipped = skipped,
		cashMult = cashMult,
		source = source,
	}, player)

	return total, skipped
end

-- Public entrypoint. `kind` is "sell" | "scrap"; `source` is "touched" | "proximity".
function EconomyPad.convert(player: Player, kind: string, source: string): (number, number)
	if kind == "sell" then
		return applyRule(SELL_RULE, player, source)
	elseif kind == "scrap" then
		return applyRule(SCRAP_RULE, player, source)
	else
		warn(string.format("[EconomyPad] unknown kind %q (expected 'sell' or 'scrap')", kind))
		return 0, 0
	end
end

-- Test seam: expose the rules so HarvestFlow / unit tests can introspect
-- them without re-deriving values. Not for hot-path use.
EconomyPad._SELL_RULE = SELL_RULE
EconomyPad._SCRAP_RULE = SCRAP_RULE

return EconomyPad
