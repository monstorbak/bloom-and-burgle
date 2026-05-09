--!strict
-- MerchantPricing — pure pricing formula for marketplace NPC merchants.
--
-- BAB-MARKETPLACE-NPC-ROTATION (2026-05-08).
--
-- Composes:
--   1. Pawn Forge floor:    count × baseValue × mutationMult
--   2. NPC base premium:    × personality.basePremium
--   3. Preference fit:      × 1.0 if matches, × personality.nonPreferenceMultiplier otherwise
--   4. Arbitrage bonus:     + personality.arbitrageBonus when profile matches affinity
--   5. Today's-special:     + 1.0 when species == NPCRotation.todaysSpecial(npcId)
--   6. Multiplier cap:      min(rawMultiplier, MULTIPLIER_CAP)
--
-- CashMultiplier (per-player attribute) and the per-sell MAX_PAYOUT cap are
-- applied OUTSIDE this module by the calling NPC script (BrassBart, Hexerine,
-- Verda) so this stays a pure function.
--
-- ── Compatibility with the on-plot Pawn Forge ────────────────────────
-- The Pawn Forge in the Hatchery uses a different formula
-- (count × baseValue × mutationMult, no NPC layers) and IS NOT affected by
-- this module. Pawn Forge stays the floor; NPCs are the destination commerce.

local CritterData = require(script.Parent:WaitForChild("CritterData"))
local MerchantPersonalities = require(script.Parent:WaitForChild("MerchantPersonalities"))
local NPCRotation = require(script.Parent:WaitForChild("NPCRotation"))

local M = {}

-- Prevents "perfect storm" combos from breaking the cash economy.
-- 3.0× = base 1.3 × prefFit 1.0 × (1 + arb 0.4 + special 1.0) = 3.12 capped.
M.MULTIPLIER_CAP = 3.0

-- Result of pricing one stash entry. All intermediate breakdown components
-- are surfaced for telemetry + future UI tooltips (Phase 3).
export type PriceResult = {
	-- Pre-multiplier base (count × baseValue × mutationMult)
	basePayout: number,
	-- Final multiplier applied to basePayout (capped)
	multiplier: number,
	-- Pre-cap multiplier (so callers can detect cap-hit for telemetry)
	rawMultiplier: number,
	-- Final per-line payout BEFORE cashMult / MAX_PAYOUT clamping
	totalPayout: number,
	-- Per-component breakdown
	basePremium: number,
	preferenceFit: number,
	arbitrageBonus: number,
	specialBonus: number,
	wasCapped: boolean,
	-- Affinity / special diagnostics
	affinity: string,                  -- "asset" | "liability" | "neutral"
	wasSpecial: boolean,
	todaysSpecial: string?,
	inPreference: boolean,
	-- Skip reason if payout = 0 ("contraband" / "unknown_species" / "unknown_npc"). Empty if priced normally.
	skipReason: string,
}

-- ── Helpers ──────────────────────────────────────────────────────────

local function mutationMultiplier(mutationId: string): number
	if mutationId == "" then return 1 end
	for _, m in CritterData.MUTATIONS do
		if m.id == mutationId then return m.multiplier end
	end
	return 1
end

local function inSet(needle: string, haystack: { string }): boolean
	for _, v in haystack do
		if v == needle then return true end
	end
	return false
end

-- Whether species matches any of the NPC's preference axes.
local function speciesInPreference(personality, species): boolean
	if inSet(species.hatchArchetype, personality.preferredHatchArchetypes) then return true end
	if inSet(species.archetype, personality.preferredVisualArchetypes) then return true end
	if species.tag and inSet(species.tag, personality.preferredTags) then return true end
	return false
end

-- ── Public API ───────────────────────────────────────────────────────

-- Empty/skip result helper.
local function skip(reason: string): PriceResult
	return {
		basePayout = 0,
		multiplier = 0,
		rawMultiplier = 0,
		totalPayout = 0,
		basePremium = 0,
		preferenceFit = 0,
		arbitrageBonus = 0,
		specialBonus = 0,
		wasCapped = false,
		affinity = "neutral",
		wasSpecial = false,
		todaysSpecial = nil,
		inPreference = false,
		skipReason = reason,
	}
end

-- Price one stash entry (one species + mutation combo).
--
-- Caller passes:
--   npcId            ("bart" | "hexerine" | "verda")
--   speciesId        (CritterData species id, e.g. "coal_drake")
--   mutationId       ("" if unmutated, otherwise mutation id e.g. "ember")
--   count            number of critters being priced
--   playerClass      ("knight" | "alchemist" | "skyPirate" | "tinkerer" | "hexer")
--   todaysSpecialOverride  (optional; if nil, computed from NPCRotation.
--                          tests/UI may pass a fixed value)
--
-- Returns a PriceResult. If the species is Contraband (can't be sold) or
-- the npc/species id is unknown, returns a skip result with payout = 0.
function M.priceLine(opts: {
	npcId: string,
	speciesId: string,
	mutationId: string,
	count: number,
	playerClass: string,
	todaysSpecialOverride: string?,
}): PriceResult
	local p = MerchantPersonalities.get(opts.npcId)
	if not p then return skip("unknown_npc") end

	local s = CritterData.get(opts.speciesId)
	if not s then return skip("unknown_species") end

	-- Contraband can't be sold to merchants (per Spec §1.5); only scrap.
	if s.tag == "Contraband" then return skip("contraband") end

	local mut = mutationMultiplier(opts.mutationId)
	local basePayout = opts.count * s.baseValue * mut

	local inPref = speciesInPreference(p, s)
	local prefFit = inPref and 1.0 or p.nonPreferenceMultiplier

	local affinity = CritterData.affinityFor(opts.speciesId, opts.playerClass)
	local arbitrageBonus = 0
	if (p.arbitrageProfile == "asset" and affinity == "asset")
		or (p.arbitrageProfile == "liability" and affinity == "liability")
	then
		arbitrageBonus = p.arbitrageBonus
	end

	local todaysSpecial = opts.todaysSpecialOverride
		or NPCRotation.todaysSpecial(opts.npcId, p.specialRotationPool)
	local wasSpecial = (todaysSpecial == opts.speciesId)
	local specialBonus = wasSpecial and 1.0 or 0

	local rawMultiplier = p.basePremium * prefFit * (1 + arbitrageBonus + specialBonus)
	local capped = rawMultiplier > M.MULTIPLIER_CAP
	local multiplier = capped and M.MULTIPLIER_CAP or rawMultiplier

	local totalPayout = basePayout * multiplier

	return {
		basePayout = basePayout,
		multiplier = multiplier,
		rawMultiplier = rawMultiplier,
		totalPayout = totalPayout,
		basePremium = p.basePremium,
		preferenceFit = prefFit,
		arbitrageBonus = arbitrageBonus,
		specialBonus = specialBonus,
		wasCapped = capped,
		affinity = affinity,
		wasSpecial = wasSpecial,
		todaysSpecial = todaysSpecial,
		inPreference = inPref,
		skipReason = "",
	}
end

-- Price an entire stash. Stash format: { ["speciesId:mutationId"] = count }
-- (mutationId may be "" for unmutated; "speciesId:" suffix is always present
-- per the Hatchery → DataStore convention).
--
-- Returns aggregate totals + per-entry detail (for UI / telemetry).
export type StashPriceResult = {
	totalPayout: number,
	totalCount: number,        -- sum of priced critters (excludes skipped)
	mutationCount: number,
	skippedCount: number,      -- e.g. contraband; informational
	perEntry: { [string]: PriceResult },
}

function M.priceStash(opts: {
	npcId: string,
	stash: { [string]: number },
	playerClass: string,
	todaysSpecialOverride: string?,
}): StashPriceResult
	local result: StashPriceResult = {
		totalPayout = 0,
		totalCount = 0,
		mutationCount = 0,
		skippedCount = 0,
		perEntry = {},
	}

	for key, n in opts.stash do
		if typeof(key) ~= "string" or typeof(n) ~= "number" or n <= 0 then
			continue
		end
		local sep = string.find(key, ":") or 0
		local sId = if sep > 0 then string.sub(key, 1, sep - 1) else key
		local mId = if sep > 0 then string.sub(key, sep + 1) else ""

		local r = M.priceLine({
			npcId = opts.npcId,
			speciesId = sId,
			mutationId = mId,
			count = n,
			playerClass = opts.playerClass,
			todaysSpecialOverride = opts.todaysSpecialOverride,
		})

		result.perEntry[key] = r
		if r.skipReason == "" then
			result.totalPayout += r.totalPayout
			result.totalCount += n
			if mId ~= "" then result.mutationCount += n end
		else
			result.skippedCount += n
		end
	end

	return result
end

return M
