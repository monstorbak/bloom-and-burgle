--!strict
-- RateLimiter: per-player per-key token-bucket gate for currency-mutating
-- handlers per ADR-2 (Bloom&Burgle_Architecture_Eval.md).
--
-- Token bucket semantics:
--   - Each (userId, key) tuple gets a bucket with `capacity` tokens.
--   - Tokens regenerate at `refillPerSec` per second up to capacity.
--   - tryConsume() spends one token; returns true on success, false on empty.
--
-- Why not a fixed-window counter? Token buckets allow short bursts (good UX
-- for legitimate quick-clicks) while still enforcing a sustained-rate cap.
--
-- Usage in a RemoteEvent handler:
--   local RateLimiter = require(...:WaitForChild("RateLimiter"))
--   if not RateLimiter.tryConsume(player.UserId, "BuySeed", 4, 8) then
--       RateLimiter.logViolation(player, "BuySeed")
--       return
--   end
--   -- ... actual handler logic
--
-- The (perSecond=4, burst=8) means: long-run cap of 4 buys/s, burst of 8.

local Players = game:GetService("Players")

local RateLimiter = {}

type Bucket = {
	tokens: number,
	lastRefill: number,
	capacity: number,
	refillPerSec: number,
}

-- buckets[userId][key] = Bucket
local buckets: { [number]: { [string]: Bucket } } = {}

-- Per-player violation counters for telemetry / soft-ban heuristics.
local violations: { [number]: { [string]: number } } = {}

local function ensureBucket(userId: number, key: string, capacity: number, refillPerSec: number): Bucket
	if not buckets[userId] then buckets[userId] = {} end
	local b = buckets[userId][key]
	if not b then
		b = {
			tokens = capacity,
			lastRefill = os.clock(),
			capacity = capacity,
			refillPerSec = refillPerSec,
		}
		buckets[userId][key] = b
	else
		-- Allow capacity / rate to evolve at runtime (e.g. premium gamepass
		-- raises the buy-seed cap). Re-bind on every consume so we don't
		-- need a separate "configure" call.
		b.capacity = capacity
		b.refillPerSec = refillPerSec
	end
	return b
end

-- Spend a token. Returns true if allowed, false if rate-limited.
function RateLimiter.tryConsume(
	userId: number,
	key: string,
	perSecond: number,
	burst: number
): boolean
	local now = os.clock()
	local b = ensureBucket(userId, key, burst, perSecond)
	local elapsed = now - b.lastRefill
	b.tokens = math.min(b.capacity, b.tokens + elapsed * b.refillPerSec)
	b.lastRefill = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

-- Returns how many tokens this player has remaining for a key — useful for
-- exposing UI feedback ("3 sells left this minute").
function RateLimiter.peek(userId: number, key: string): number
	local b = buckets[userId] and buckets[userId][key]
	if not b then return 0 end
	local now = os.clock()
	local elapsed = now - b.lastRefill
	return math.min(b.capacity, b.tokens + elapsed * b.refillPerSec)
end

-- Record a violation. Surfaced via [BAB-EXPLOIT] in the console stream
-- so dbg errors can grep for them. Telemetry can later read this and
-- ship to the collector.
function RateLimiter.logViolation(player: Player, key: string, extra: string?)
	local uid = player.UserId
	if not violations[uid] then violations[uid] = {} end
	violations[uid][key] = (violations[uid][key] or 0) + 1
	local count = violations[uid][key]
	-- Print only on milestones to avoid log spam under sustained attack.
	if count == 1 or count == 10 or count == 100 or count % 1000 == 0 then
		print(string.format(
			"[BAB-EXPLOIT] %s (uid=%d) hit rate limit for %q (count=%d)%s",
			player.Name, uid, key, count, extra and (" — " .. extra) or ""
		))
	end
end

function RateLimiter.violationCount(userId: number, key: string?): number
	local v = violations[userId]
	if not v then return 0 end
	if key then return v[key] or 0 end
	local total = 0
	for _, c in pairs(v) do total += c end
	return total
end

-- Cleanup on player leave so we don't leak buckets / violations.
Players.PlayerRemoving:Connect(function(player)
	buckets[player.UserId] = nil
	violations[player.UserId] = nil
end)

return RateLimiter
