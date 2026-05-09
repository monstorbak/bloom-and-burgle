--!strict
-- NPCRotation — deterministic UTC-aligned daily rotation for marketplace NPC
-- "today's special" preferences.
--
-- BAB-MARKETPLACE-NPC-ROTATION (2026-05-08).
--
-- ── Why deterministic? ────────────────────────────────────────────────
-- Every server globally must agree on which species is each NPC's "today's
-- special" so cross-server discoverability works ("friend on Discord said
-- Hexerine is buying salamanders 5× today!"). MessagingService is NOT used
-- for the rotation pick itself — the rotation is a pure function of (npcId,
-- UTC year-day, pool), so every server computes the same answer locally
-- with no coordination overhead.
--
-- ── Rotation seed function ────────────────────────────────────────────
-- seed(npcId, yday) = (yday * 2654435761 + first-byte(npcId) * 7919) mod #pool
--
-- 2654435761 is Knuth's golden-ratio multiplicative-hash constant; 7919 is
-- a small prime that ensures different NPCs land on different species on
-- the same day (avoiding "everyone wants coal_drake on Tuesday" collisions
-- for short pools).
--
-- The rotation is INTENDED to be deterministic and predictable — players
-- discovering "every Friday Bart wants iron_hydra" is content, not a bug.
-- Lifetime variance comes from the year-day mod arithmetic across the pool.

local M = {}

-- Pure: convert a unix timestamp (or os.time() if nil) into a UTC year-day
-- 1..366. The "!" prefix on os.date forces UTC.
function M._utcYday(timeOverride: number?): number
	local t = timeOverride or os.time()
	local d = os.date("!*t", t) :: any
	return d.yday
end

-- Pure: deterministic seeded pick from a pool. Returns nil if pool is empty.
-- Exposed for testing — production callers should use `todaysSpecial`.
function M._pick(npcId: string, pool: { string }, utcYday: number): string?
	if #pool == 0 then return nil end
	local first = string.byte(npcId, 1) or 0
	-- 32-bit safe: stick within Lua's number range. yday max 366, multiplier
	-- 2654435761, first-byte ≤ 255 × 7919 = 2.0M. Sum stays well within 2^53.
	local seed = (utcYday * 2654435761 + first * 7919) % #pool + 1
	return pool[seed]
end

-- Returns today's special species id for the given NPC. Caller passes the
-- NPC's specialRotationPool (from MerchantPersonalities). This signature
-- keeps NPCRotation independent of MerchantPersonalities to avoid require
-- cycles.
function M.todaysSpecial(npcId: string, pool: { string }, timeOverride: number?): string?
	return M._pick(npcId, pool, M._utcYday(timeOverride))
end

return M
