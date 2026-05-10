--!strict
-- CritterCameraHooks — client-side cinematic camera hooks for critter
-- "moments" (rig form transitions, mythic hatches, escape spawns).
--
-- BAB-PHASE-1-CRITTER-RIGS scaffolding (2026-05-09).
--
-- Phase 1 ships this module as the LISTENING side of the camera contract:
--   - listens on `CritterCeremony` RemoteEvent (lazy-created server-side
--     in CritterVisuals.luau)
--   - implements orbit-cam, freeze-frame, bloom boost
--   - is a no-op until Phase 2/3 server-side actually fires events
--
-- Phase 2 (BAB-CRITTER-ESCAPE) fires on liability escape:
--     CritterCeremonyRE:FireAllClients({
--         type = "escape_burst",
--         position = Vector3.new(...),
--         duration = 0.6,
--         speciesId = "coal_drake",
--         affinity = "liability",
--     })
--
-- Phase 3 (BAB-PHASE-3-MYTHIC-CEREMONY) fires on Mythic hatch:
--     CritterCeremonyRE:FireClient(player, {
--         type = "mythic_hatch",
--         position = Vector3.new(...),
--         duration = 1.6,
--         speciesId = "coal_drake",
--         mutationName = "Celestial",
--         mutationEmoji = "💫",
--     })
--
-- ── Ceremony types ───────────────────────────────────────────────────
--   "mythic_hatch"   1.6s freeze, full bloom boost, orbital framing
--   "escape_burst"   0.6s quick cut, slow-mo at impact, no orbit
--   "form_transition" (if ever fired) 0.3s tiny pop, no camera move
--
-- ── Brand discipline ─────────────────────────────────────────────────
-- Bloom boost uses Lighting.Bloom intensity in the 0.5-1.4 range —
-- within the Spec §1.5 "ambient atmosphere" range. No SmoothPlastic,
-- ForceField, or other banned visuals. All Color3 values pulled from
-- the BrandColors palette.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
-- Cache PlayerGui — used as the parent for screenFlash + mythicToast
-- ScreenGuis. Without this, those functions did `sg.Parent = playerGui`
-- where `playerGui` was an undefined global (= nil), Roblox silently
-- accepted nil-Parent, the ScreenGui never rendered. Bug shipped in
-- Phase 1, surfaced in Phase 3 when the ceremony actually fires.
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

-- ── Wait for the RemoteEvent (server lazy-creates it) ────────────────
local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local CritterCeremonyRE = remotes:WaitForChild("CritterCeremony", 30) :: RemoteEvent?
if not CritterCeremonyRE then
	warn("[CritterCameraHooks] CritterCeremony RemoteEvent missing after 30s — camera hooks disabled")
	return
end

-- ── State ────────────────────────────────────────────────────────────
local ceremonyActive = false
local cameraConn: RBXScriptConnection? = nil

-- ── Bloom helper ─────────────────────────────────────────────────────
-- Tween Lighting.Bloom intensity from current → target, restoring on cleanup.
-- If no Bloom instance exists, create one (Phase 3 ceremonies want it).

local function ensureBloom(): BloomEffect
	local b = Lighting:FindFirstChildOfClass("BloomEffect")
	if b then return b end
	local nb = Instance.new("BloomEffect")
	nb.Name = "CeremonyBloom"
	nb.Intensity = 0.5
	nb.Size = 24
	nb.Threshold = 0.95
	nb.Parent = Lighting
	return nb
end

-- Pulse bloom to an ABSOLUTE target intensity, not a relative bump. This
-- guarantees a visible change regardless of the LightingBoot baseline
-- (steampunk atmosphere can set bloom to 1.0+ at boot — a 1.4× relative
-- bump from there is imperceptible).
local function pulseBloom(target: number, hold: number, releaseTime: number)
	local b = ensureBloom()
	local original = b.Intensity
	-- Ramp up
	TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Intensity = target }):Play()
	task.delay(0.25 + hold, function()
		-- Ramp back down to baseline
		TweenService:Create(b, TweenInfo.new(releaseTime, Enum.EasingStyle.Quad), { Intensity = original }):Play()
	end)
end

-- ── Orbital camera ───────────────────────────────────────────────────
-- Snap-and-orbit: capture current camera state, set Camera.CameraType to
-- Scriptable, BindToRenderStep keeps the camera at a fixed offset orbiting
-- the focus point. Restores Custom + character control on release.

local function startOrbit(focus: Vector3, duration: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end

	local previousType = cam.CameraType
	cam.CameraType = Enum.CameraType.Scriptable

	local startTime = os.clock()
	local distance = 12
	local height = 4
	local angularVelocity = math.rad(45)  -- 45°/s slow orbit

	if cameraConn then cameraConn:Disconnect() end
	cameraConn = RunService.RenderStepped:Connect(function(_dt)
		local elapsed = os.clock() - startTime
		if elapsed >= duration then
			if cameraConn then cameraConn:Disconnect(); cameraConn = nil end
			cam.CameraType = previousType
			return
		end
		local angle = angularVelocity * elapsed
		local pos = focus + Vector3.new(
			math.cos(angle) * distance,
			height,
			math.sin(angle) * distance
		)
		cam.CFrame = CFrame.new(pos, focus)
	end)
end

-- ── Freeze-frame ─────────────────────────────────────────────────────
-- Physics-pause-by-proxy: re-anchor character (so it can't walk away during
-- the freeze) and lock controls. ControlScripts read CharacterAdded — we
-- can't disable that cleanly without yanking the PlayerModule. For Phase 1
-- the orbit camera is the freeze; the character may still walk in place
-- below the camera but the visual focus is on the critter.

-- Screen flash overlay — opens nearly opaque, decays over 0.6s. Bright
-- enough to register over heavy fog, red ambient lighting, or partial
-- dev-console overlap. DisplayOrder pushed to 9999 to render above any
-- standard ScreenGui (incl. tutorial banners).
local function screenFlash()
	local sg = Instance.new("ScreenGui")
	sg.Name = "MythicFlash"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 9999
	sg.Parent = playerGui
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	-- Nearly opaque (alpha 0.05 = 95% white) so the flash registers
	-- unambiguously even on busy / dark scenes.
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel = 0
	f.Parent = sg
	TweenService:Create(f, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.7, function() if sg.Parent then sg:Destroy() end end)
end

-- Vertical light pillar at the planter location. Tinted by mutation color
-- when known (Celestial = sky-blue per CritterData.MUTATIONS).
local function lightPillar(focus: Vector3, mutationId: string?, duration: number)
	local color = Color3.fromRGB(153, 230, 255)  -- Celestial default
	if mutationId == "ember" then color = Color3.fromRGB(255, 106, 31)
	elseif mutationId == "aether" then color = Color3.fromRGB(79, 227, 255)
	elseif mutationId == "gilded" then color = Color3.fromRGB(232, 197, 71)
	elseif mutationId == "polished" then color = Color3.fromRGB(255, 245, 200)
	end

	local pillar = Instance.new("Part")
	pillar.Name = "MythicPillar"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Size = Vector3.new(2.4, 60, 2.4)
	pillar.Transparency = 0.2
	pillar.Position = focus + Vector3.new(0, 30, 0)
	pillar.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 30
	light.Brightness = 4
	light.Parent = pillar

	-- Fade out at end of ceremony.
	task.delay(duration - 0.3, function()
		if not pillar.Parent then return end
		TweenService:Create(pillar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		}):Play()
		task.delay(0.5, function() if pillar.Parent then pillar:Destroy() end end)
	end)
end

-- Lock the local character's walk speed during the ceremony so the player
-- can't walk off-screen mid-freeze. Restores after duration.
local function lockWalkSpeed(duration: number)
	local char = localPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local previous = hum.WalkSpeed
	hum.WalkSpeed = 0
	task.delay(duration, function()
		if hum.Parent then hum.WalkSpeed = previous end
	end)
end

-- Mythic-tinted toast. Fires at t+2.0s ("💫 CELESTIAL Coal Drake hatched!").
-- Held for 4s then fades. DisplayOrder=9999 to render above standard
-- ScreenGuis. Anchored DEAD CENTER (0.5, 0.5) so no top-of-screen
-- tutorial banner can hide it (the persistent "Buy seeds at the EGG
-- EMPORIUM" prompt sits at the top — kills any toast at 0.08-0.18).
-- The player's character is walk-locked during the ceremony, so a
-- center-screen toast doesn't block gameplay.
local function mythicToast(payload: any)
	local sg = Instance.new("ScreenGui")
	sg.Name = "MythicToast"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 9999
	sg.Parent = playerGui
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(680, 130)
	panel.BackgroundColor3 = Color3.fromRGB(40, 36, 32)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = sg
	local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0, 12); cor.Parent = panel
	local stk = Instance.new("UIStroke")
	stk.Color = Color3.fromRGB(232, 197, 71)  -- GoggleGold
	stk.Thickness = 3
	stk.Parent = panel

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, -10)
	lbl.Position = UDim2.fromOffset(8, 5)
	lbl.BackgroundTransparency = 1
	local mutPart = ""
	if payload.mutationName then
		mutPart = string.format("%s ", string.upper(payload.mutationName))
	end
	lbl.Text = string.format("%s %s%s hatched!",
		payload.mutationEmoji or "💫",
		mutPart,
		payload.speciesName or "Critter")
	lbl.TextColor3 = Color3.fromRGB(232, 197, 71)
	lbl.TextStrokeTransparency = 0
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Parent = panel
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 28; sz.Parent = lbl

	-- Pop-in from slightly larger scale + fade in from transparent. Center-
	-- screen positioning means a slide-from-top animation is wrong; use a
	-- pop-in instead. Held 4s then fades out.
	panel.BackgroundTransparency = 1
	lbl.TextTransparency = 1
	stk.Transparency = 1
	-- Start slightly oversized + tween down to natural size for the "land" feel.
	local naturalSize = panel.Size
	panel.Size = UDim2.fromOffset(naturalSize.X.Offset * 1.2, naturalSize.Y.Offset * 1.2)
	TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = naturalSize,
		BackgroundTransparency = 0.05,
	}):Play()
	TweenService:Create(lbl, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(stk, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0,
	}):Play()
	task.delay(4.0, function()
		if not sg.Parent then return end
		TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(lbl, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}):Play()
		TweenService:Create(stk, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
		task.wait(0.6)
		if sg.Parent then sg:Destroy() end
	end)
end

local function ceremonyMythic(payload: any)
	if ceremonyActive then return end
	ceremonyActive = true

	local position = payload.position :: Vector3?
	local duration = (payload.duration :: number?) or 1.6
	if not position then ceremonyActive = false; return end

	-- t+0.0s : screen flash + camera orbit + bloom ramp + walk lock.
	-- Bloom target = 4.0 absolute (was 1.4, but baselines from LightingBoot
	-- can already exceed that — absolute value guarantees a visible jump).
	screenFlash()
	startOrbit(position, duration)
	pulseBloom(4.0, duration - 0.5, 0.4)
	lockWalkSpeed(duration + 0.3)

	-- t+0.1s : light pillar at the pod (mutation-tinted)
	task.delay(0.1, function()
		lightPillar(position, payload.mutationId, duration)
	end)

	-- t+2.0s : mythic-tinted toast (after the freeze ends, gives the
	-- player time to catch the rig in screenshot).
	task.delay(2.0, function()
		mythicToast(payload)
	end)

	task.delay(duration, function() ceremonyActive = false end)
end

local function ceremonyEscapeBurst(payload: any)
	if ceremonyActive then return end
	ceremonyActive = true

	local duration = (payload.duration :: number?) or 0.6
	-- Lighter ceremony — bloom flash only, no orbit (escape is a quick cut).
	pulseBloom(1.2, 0.2, 0.3)

	task.delay(duration, function() ceremonyActive = false end)
end

-- ── Wire RemoteEvent → ceremony dispatch ─────────────────────────────
CritterCeremonyRE.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then return end
	local kind = payload.type
	if kind == "mythic_hatch" then
		ceremonyMythic(payload)
	elseif kind == "escape_burst" then
		ceremonyEscapeBurst(payload)
	-- Other ceremony types can dispatch here without changing call sites.
	end
end)

print("[BAB-LIFE] CritterCameraHooks online (listening for ceremony events)")
