--!strict
-- LightingBoot: configures the world Lighting + Atmosphere for the steampunk
-- aesthetic per Bloom&Burgle_Design_Spec.md §1.4. Runs once on server boot,
-- then ticks the day/night cycle (Forge Hour ↔ Aether Hour) every minute.
--
-- Why it lives in a Script and not project.json: ColorCorrectionEffect /
-- Atmosphere / Bloom are children of Lighting and easier to wire up
-- imperatively with safe defaults than to maintain in JSON across pushes.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))

-- ── Static base lighting ─────────────────────────────────────────────
Lighting.Brightness = 2.5
Lighting.Ambient = BrandColors.lerpToBlack(BrandColors.Brass, 0.6)
Lighting.OutdoorAmbient = BrandColors.lerpToBlack(BrandColors.Brass, 0.4)
Lighting.GlobalShadows = true
-- Lighting.Technology requires RobloxScript capability and is set via
-- default.project.json instead. Skipping at runtime.
pcall(function() Lighting.EnvironmentDiffuseScale = 0.5 end)
pcall(function() Lighting.EnvironmentSpecularScale = 0.4 end)
Lighting.FogEnd = 1500
Lighting.FogColor = BrandColors.lerpToBlack(BrandColors.Brass, 0.5)
Lighting.ClockTime = 14

-- Brass-tinted volumetric atmosphere
local atmos = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmos.Density = 0.25
atmos.Offset = 0.25
atmos.Color = BrandColors.Brass
atmos.Decay = BrandColors.IronworkCharcoal
atmos.Glare = 0.6
atmos.Haze = 1.4
atmos.Parent = Lighting

-- Bloom for forge glows + Mythic critter highlights
local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
bloom.Intensity = 0.8
bloom.Size = 24
bloom.Threshold = 0.95
bloom.Parent = Lighting

-- Sun rays (cinematic Forge Hour beams)
local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
rays.Intensity = 0.18
rays.Spread = 0.9
rays.Parent = Lighting

-- Color correction — we tween this between Forge (warm) and Aether (cool).
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
cc.Name = "BabColorCorrection"
cc.Brightness = 0.02
cc.Saturation = 0.12
cc.Contrast = 0.10
cc.TintColor = BrandColors.lerpToWhite(BrandColors.EmberOrange, 0.85)  -- subtle warm tilt
cc.Parent = Lighting

-- ── Day cycle: 18-minute real-time loop ──────────────────────────────
-- Forge Hour: 12-18 (warm, screenshot moment).
-- Daytime:    6-12  (neutral cream).
-- Aether Hour: 0-3 (cyan night, magical critter glow).
-- Twilight:   3-6 and 18-24 (transition).

local CYCLE_SECONDS = 18 * 60
local startTick = os.clock()

local function applyMood(hour: number)
	local isNight = hour < 4 or hour > 21
	local isForge = hour >= 12 and hour <= 19

	if isNight then
		-- Aether Hour
		atmos.Color = BrandColors.AetherCyan
		atmos.Decay = BrandColors.OilBlack
		atmos.Density = 0.3
		atmos.Glare = 0.3
		Lighting.Ambient = BrandColors.lerpToBlack(BrandColors.AetherCyan, 0.7)
		Lighting.OutdoorAmbient = BrandColors.lerpToBlack(BrandColors.AetherCyan, 0.6)
		Lighting.FogColor = BrandColors.lerpToBlack(BrandColors.AetherCyan, 0.55)
		cc.TintColor = BrandColors.lerpToWhite(BrandColors.AetherCyan, 0.75)
		cc.Saturation = 0.18
		bloom.Intensity = 1.2
	elseif isForge then
		-- Forge Hour (the screenshot moment)
		atmos.Color = BrandColors.EmberOrange
		atmos.Decay = BrandColors.lerpToBlack(BrandColors.Brass, 0.4)
		atmos.Density = 0.28
		atmos.Glare = 0.9
		Lighting.Ambient = BrandColors.lerpToBlack(BrandColors.EmberOrange, 0.5)
		Lighting.OutdoorAmbient = BrandColors.lerpToBlack(BrandColors.EmberOrange, 0.35)
		Lighting.FogColor = BrandColors.lerpToBlack(BrandColors.EmberOrange, 0.45)
		cc.TintColor = BrandColors.lerpToWhite(BrandColors.EmberOrange, 0.8)
		cc.Saturation = 0.15
		bloom.Intensity = 1.0
	else
		-- Default daytime — brass/cream
		atmos.Color = BrandColors.Brass
		atmos.Decay = BrandColors.IronworkCharcoal
		atmos.Density = 0.25
		atmos.Glare = 0.6
		Lighting.Ambient = BrandColors.lerpToBlack(BrandColors.Brass, 0.6)
		Lighting.OutdoorAmbient = BrandColors.lerpToBlack(BrandColors.Brass, 0.4)
		Lighting.FogColor = BrandColors.lerpToBlack(BrandColors.Brass, 0.5)
		cc.TintColor = BrandColors.lerpToWhite(BrandColors.EmberOrange, 0.85)
		cc.Saturation = 0.12
		bloom.Intensity = 0.8
	end
end

-- Start at Forge Hour so the first session screenshot is the warm one.
Lighting.ClockTime = 16
applyMood(16)

local lastHour = -1
RunService.Heartbeat:Connect(function()
	local elapsed = (os.clock() - startTick) % CYCLE_SECONDS
	local hour = (elapsed / CYCLE_SECONDS) * 24
	Lighting.ClockTime = hour
	local hourFloor = math.floor(hour)
	if hourFloor ~= lastHour then
		lastHour = hourFloor
		applyMood(hour)
	end
end)

print("[BAB-LIFE] LightingBoot online — steampunk atmosphere active, 18-min day cycle")
