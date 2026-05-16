--!strict
-- TinkererPass — server-side module for the 🎩 Tinkerer's Pass gamepass.
--
-- BAB-DESIGN-CRITIQUE Tier 2 (2026-05-10).
--
-- The Tinkerer's Pass is BAB's first premium revenue product. Per the
-- design audit, retention + revenue are bottlenecked by gamepass
-- invisibility — there's no upsell touchpoint in any HUD. This pass
-- creates one: the daily-reward chest at the Clocktower's base pays
-- 2× for pass holders, forever. Habit-forming retention + premium
-- monetization in a single artifact.
--
-- ── Setup (manual — must be done on Creator Hub) ─────────────────────
-- This module needs a real GAMEPASS_ID before going live:
--
--   1. Open https://create.roblox.com/dashboard/creations
--   2. Click the Bloom & Burgle universe → Configure → Gamepasses → +Create
--   3. Name: "🎩 Tinkerer's Pass"
--      Description (suggested):
--        "Doubles every daily-reward chest payout, forever. The smart
--        tinkerer's investment in tomorrow's harvest."
--      Price: 299 Robux
--      Image: brass top-hat icon (commission or use the placeholder)
--   4. Once created, copy the gamepass numeric ID from the URL.
--   5. Set the env var BB_TINKERER_PASS_ID in your .env file:
--        BB_TINKERER_PASS_ID=123456789
--   6. The publish script auto-sources .env and bakes it into the place.
--
-- Until step 5 is done, GAMEPASS_ID stays 0 and `hasPass()` always
-- returns false — that's safe; the daily reward simply pays its base
-- amount to everyone.
--
-- ── API ──────────────────────────────────────────────────────────────
--   TinkererPass.GAMEPASS_ID            — the numeric Roblox gamepass ID
--   TinkererPass.hasPass(player) -> bool — cached for the session
--   TinkererPass.payoutMultiplier(player) -> number (1 or 2)
--
-- ── Cache strategy ───────────────────────────────────────────────────
-- UserOwnsGamePassAsync hits Roblox's API and can be slow + rate-limited.
-- We cache per-player for the session (Players.PlayerRemoving clears).
-- Future: invalidate on MarketplaceService.PromptGamePassPurchaseFinished
-- so a player who buys the pass mid-session immediately gets 2×.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local M = {}

-- Read the gamepass ID from an optional generated config file (same
-- pattern as TelemetryConfig). Until the user runs publish with
-- BB_TINKERER_PASS_ID set, this stays 0 → hasPass returns false.
local GAMEPASS_ID: number = 0
do
	local cfg = ServerScriptService:FindFirstChild("GamepassConfig")
	if cfg and cfg:IsA("ModuleScript") then
		local ok, mod = pcall(require, cfg)
		if ok and typeof(mod) == "table" and typeof(mod.TinkererPassId) == "number" then
			GAMEPASS_ID = mod.TinkererPassId
		end
	end
end
M.GAMEPASS_ID = GAMEPASS_ID

-- Cache: userId -> bool. Cleared on PlayerRemoving.
local cache: { [number]: boolean } = {}

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

-- ── Public API ───────────────────────────────────────────────────────

function M.hasPass(player: Player): boolean
	if GAMEPASS_ID == 0 then return false end
	local cached = cache[player.UserId]
	if cached ~= nil then return cached end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_ID)
	end)
	local result = (ok and owns) and true or false
	cache[player.UserId] = result
	return result
end

-- Daily-reward multiplier. Returns 2 for pass holders, 1 for everyone.
function M.payoutMultiplier(player: Player): number
	return M.hasPass(player) and 2 or 1
end

-- Invalidate cache on purchase — fires when the player completes a
-- gamepass purchase during the session. Without this, a freshly-bought
-- pass wouldn't take effect until the player rejoins.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if passId == GAMEPASS_ID and wasPurchased then
		cache[player.UserId] = true
	end
end)

print(string.format("[BAB-LIFE] TinkererPass online (gamepass ID: %s)",
	GAMEPASS_ID == 0 and "UNSET — set BB_TINKERER_PASS_ID in .env" or tostring(GAMEPASS_ID)))

return M
