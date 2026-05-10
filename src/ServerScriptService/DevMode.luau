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
			elseif lower:match("^/forcemutation ") and DevMode.isEnabled() then
				-- BAB-PHASE-3 testing: force every harvest's mutation roll to
				-- the given id (e.g. /forcemutation celestial → triggers the
				-- Mythic ceremony on demand). Honored by HarvestFlow only when
				-- DevMode is enabled. Clear via /clearmutation.
				local mutId = lower:match("^/forcemutation (.+)$")
				if mutId and mutId ~= "" then
					Workspace:SetAttribute("ForceMutation", mutId)
					print(("[DevMode] ForceMutation = %s — every harvest now rolls this mutation."):format(mutId))
				end
			elseif (lower == "/clearmutation" or lower == "/forcemutation") and DevMode.isEnabled() then
				Workspace:SetAttribute("ForceMutation", nil)
				print("[DevMode] ForceMutation cleared — harvests roll normally.")
			elseif lower == "/testmythic" and DevMode.isEnabled() then
				-- Direct-fire the Mythic ceremony to the local player. Bypasses
				-- planting + harvesting + mutation rolls — pure visualization
				-- test for clip/screenshot prep. Position is the player's
				-- current HumanoidRootPart, so the camera frames the player.
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local pos = hrp and hrp.Position or Vector3.new(0, 5, 0)
				local re = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
				re = re and re:FindFirstChild("CritterCeremony")
				if re and re:IsA("RemoteEvent") then
					(re :: RemoteEvent):FireClient(player, {
						type = "mythic_hatch",
						position = pos,
						duration = 1.6,
						speciesId = "coal_drake",
						speciesName = "Coal Drake",
						speciesEmoji = "🐉",
						mutationId = "celestial",
						mutationName = "Celestial",
						mutationEmoji = "💫",
					})
					print("[DevMode] /testmythic — Mythic ceremony fired. Close dev console to see toast + bloom + flash.")
				else
					warn("[DevMode] /testmythic — CritterCeremony RemoteEvent not found")
				end
			end
		end)
	end)
end

return DevMode
