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

local function pulseBloom(target: number, hold: number, releaseTime: number)
	local b = ensureBloom()
	local original = b.Intensity
	-- Ramp up
	TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Intensity = target }):Play()
	task.delay(0.25 + hold, function()
		-- Ramp back down
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

local function ceremonyMythic(payload: any)
	if ceremonyActive then return end
	ceremonyActive = true

	local position = payload.position :: Vector3?
	local duration = (payload.duration :: number?) or 1.6
	if not position then ceremonyActive = false; return end

	startOrbit(position, duration)
	pulseBloom(1.4, duration - 0.5, 0.4)

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
