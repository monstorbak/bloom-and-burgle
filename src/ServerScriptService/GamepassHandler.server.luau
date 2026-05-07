--!strict
-- GamepassHandler: grants the perks of each owned game pass on player join.
-- Pass IDs need to be filled in once they're created in the Roblox dashboard.
-- We read them from a Workspace attribute set "BB_GAMEPASS_<NAME>" so we can
-- ship a working build before all pass IDs exist; missing IDs simply skip.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")

-- Default pass IDs (replace with real ones from the Roblox dashboard).
-- Set Workspace:SetAttribute("BB_GAMEPASS_<KEY>", id) at runtime to override.
-- BAB-007: Gamepass IDs from Roblox Creator Dashboard (live as of 2026-05-07).
local DEFAULT_PASS_IDS = {
	["2X_CASH"] = 1825685723,         -- 2x money forever (199R)
	["4X_CASH"] = 1828272546,         -- 4x money forever (499R)
	["AUTO_HARVEST"] = 1826815749,    -- auto-harvest every 8 hours (349R)
	["ANTI_THEFT"] = 1825685871,      -- shield blocks steals (299R)
	["VIP_PLOT"] = 1824169699,        -- larger plot + 2x growth (399R)
	["MYTHIC_HUNTER"] = 1825847920,   -- 4x mutation chance (799R)
}

local function passId(key: string): number
	local override = Workspace:GetAttribute("BB_GAMEPASS_" .. key)
	if typeof(override) == "number" and override > 0 then return override end
	return DEFAULT_PASS_IDS[key] or 0
end

local function ownsPass(player: Player, key: string): boolean
	local id = passId(key)
	if id <= 0 then return false end
	local ok, owns = pcall(function()
		return -- TODO: gamepass check will fail until IDs are real. For now, always return false
		-- to prevent errors with placeholder IDs.
		if id == 0 then return false end
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	return ok and owns or false
end

local function applyPerks(player: Player)
	local mult = 1
	if ownsPass(player, "2X_CASH") then mult = math.max(mult, 2) end
	if ownsPass(player, "4X_CASH") then mult = math.max(mult, 4) end
	player:SetAttribute("CashMultiplier", mult)
	player:SetAttribute("AntiTheftShield", ownsPass(player, "ANTI_THEFT"))
	player:SetAttribute("VipPlot", ownsPass(player, "VIP_PLOT"))
	player:SetAttribute("MythicHunter", ownsPass(player, "MYTHIC_HUNTER"))
end

Players.PlayerAdded:Connect(applyPerks)
for _, p in Players:GetPlayers() do task.spawn(applyPerks, p) end

-- React to mid-session purchases
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end
	applyPerks(player)
end)
