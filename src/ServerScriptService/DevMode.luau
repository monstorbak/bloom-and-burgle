--!strict
-- DevMode (BAB-DEV): Single-source-of-truth dev/test mode.
--
-- Controlled by ONE place attribute on Workspace:
--   Workspace:GetAttribute("DevMode")  -> boolean (default: false)
--
-- When enabled (any value truthy):
--   • New players spawn with $10,000 cash + 5 of a couple test critter seeds
--   • /devmode chat command (admin-only) toggles it live
--   • Visible "DEV MODE" badge on the HUD so it's NEVER unintentionally shipped
--
-- IMPORTANT: When you publish to live (Mantle/manual upload), Workspace will
-- carry whatever the attribute value was at last save. Always set DevMode=false
-- before pushing a public build. The published build also fails-closed: only
-- ADMIN_USER_IDS may toggle the chat command at runtime, and the badge is
-- impossible to miss in any screenshot.
--
-- Authorized admins (Roblox UserIds). Add yours here.
local ADMIN_USER_IDS = {
	[7965127581] = true,   -- piddlywinx
}

local DevMode = {}

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DEV_BUFFS = {
	cash = 10000,
	seeds = {
		cogwork_rat = 5,
		fire_salamander = 5,
	},
}

local STUDIO_DEFAULTS_TO_ON = true  -- Studio always boots with dev mode on (safe — Studio never reaches public)

function DevMode.isEnabled(): boolean
	return Workspace:GetAttribute("DevMode") == true
end

function DevMode.isAdmin(player: Player): boolean
	return ADMIN_USER_IDS[player.UserId] == true
end

-- Apply dev buffs to a player (cash + seed stash). Idempotent; respects
-- Workspace.DevMode at call time.
function DevMode.applyTo(player: Player)
	if not DevMode.isEnabled() then return end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash") :: IntValue?
		if cash and cash.Value < DEV_BUFFS.cash then
			cash.Value = DEV_BUFFS.cash
		end
	end
	for speciesId, count in DEV_BUFFS.seeds do
		local key = "Stash_" .. speciesId
		local current = player:GetAttribute(key) or 0
		if current < count then
			player:SetAttribute(key, count)
		end
	end
end

-- Init: set Studio default + chat command + per-player apply on join.
function DevMode.init()
	-- Studio always defaults to ON (zero-friction dev). Production publishes
	-- whatever the place file's attribute is; ALWAYS save with DevMode=false
	-- before publishing.
	if RunService:IsStudio() and STUDIO_DEFAULTS_TO_ON then
		if Workspace:GetAttribute("DevMode") == nil then
			Workspace:SetAttribute("DevMode", true)
		end
	end

	-- Chat command: /devmode on|off|toggle (admins only)
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(msg)
			if not DevMode.isAdmin(player) then return end
			local lower = msg:lower()
			if lower == "/devmode on" then
				Workspace:SetAttribute("DevMode", true)
			elseif lower == "/devmode off" then
				Workspace:SetAttribute("DevMode", false)
			elseif lower == "/devmode" or lower == "/devmode toggle" then
				Workspace:SetAttribute("DevMode", not DevMode.isEnabled())
			elseif lower == "/cash" and DevMode.isEnabled() then
				-- quick top-up while dev mode is on
				local ls = player:FindFirstChild("leaderstats")
				local cash = ls and ls:FindFirstChild("Cash") :: IntValue?
				if cash then cash.Value = cash.Value + DEV_BUFFS.cash end
			end
		end)
	end)
end

return DevMode
