--!strict
-- AgentVisuals — builds the humanoid rig + diegetic 3-layer disclosure
-- for each AI agent.
--
-- BAB-LIVE-FEATURES Block 1 (2026-05-11).
--
-- ── Disclosure rationale ─────────────────────────────────────────────
-- Per the locked 2026-05-11 design decision (see live-features doc §1),
-- AI is disclosed via THREE diegetic layers, not the platform-meta
-- robot-prefix the original draft proposed.
-- This module owns all three:
--   1. Distinct rig — class-themed accessories, not a Roblox player avatar
--   2. Stylized BillboardGui name with · separator (always visible)
--   3. Proximity-revealed sublabel "Artificial Tinkerer" (≤20 studs)
--
-- ── Why R6 + simple parts (not loadable HumanoidDescription) ─────────
-- HumanoidDescription:GetFromUserId requires a real Roblox user id.
-- We're not impersonating any real user — that's part of the disclosure
-- contract. So we build the rig from parts directly. Cheap, controllable,
-- looks distinctly "stylized NPC" rather than "player avatar."

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))

local M = {}

-- ── Class accessory styling ─────────────────────────────────────────
-- Each class gets a signature accessory + color palette. Together with
-- the · name and the proximity label, this makes AI immediately
-- recognizable as NOT-a-player-avatar.

type ClassStyle = {
	bodyColor: Color3,
	accentColor: Color3,
	headAccessory: string,    -- "helmet" | "goggles" | "hood" | "bandana" | "cape"
	chestAccessory: string,   -- "armor" | "apron" | "coat" | "robe" | "cape"
}

local CLASS_STYLES: { [string]: ClassStyle } = {
	Knight = {
		bodyColor = BrandColors.IronworkCharcoal,
		accentColor = BrandColors.Brass,
		headAccessory = "helmet",
		chestAccessory = "armor",
	},
	Tinkerer = {
		bodyColor = BrandColors.IronworkCharcoal,
		accentColor = BrandColors.GoggleGold,
		headAccessory = "goggles",
		chestAccessory = "apron",
	},
	SkyPirate = {
		bodyColor = BrandColors.IronworkCharcoal,
		accentColor = BrandColors.AetherCyan,
		headAccessory = "bandana",
		chestAccessory = "coat",
	},
	Alchemist = {
		bodyColor = BrandColors.IronworkCharcoal,
		accentColor = BrandColors.CopperPatina,
		headAccessory = "hood",
		chestAccessory = "robe",
	},
	Hexer = {
		bodyColor = BrandColors.IronworkCharcoal,
		accentColor = BrandColors.ValveRed,
		headAccessory = "cape",
		chestAccessory = "robe",
	},
}

-- ── Helpers ──────────────────────────────────────────────────────────

local function makePart(name: string, parent: Instance, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = false
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, offset: CFrame): WeldConstraint
	b.CFrame = a.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
	return w
end

-- Build a simple class-themed accessory on the head.
local function attachHeadAccessory(head: BasePart, kind: string, accent: Color3)
	if kind == "helmet" then
		-- Brass dome covering top half of head.
		local helmet = makePart("Helmet", head.Parent :: Instance, Vector3.new(2.1, 1.1, 2.1), accent, Enum.Material.Metal)
		weld(head, helmet, CFrame.new(0, 0.3, 0))
		-- Visor band.
		local visor = makePart("Visor", head.Parent :: Instance, Vector3.new(2.2, 0.3, 0.4), BrandColors.OilBlack, Enum.Material.Metal)
		weld(head, visor, CFrame.new(0, 0.1, -0.9))
	elseif kind == "goggles" then
		-- Two small lenses + a strap.
		local left = makePart("GoggleL", head.Parent :: Instance, Vector3.new(0.6, 0.6, 0.4), accent, Enum.Material.Neon)
		weld(head, left, CFrame.new(-0.5, 0.1, -0.9))
		local right = makePart("GoggleR", head.Parent :: Instance, Vector3.new(0.6, 0.6, 0.4), accent, Enum.Material.Neon)
		weld(head, right, CFrame.new(0.5, 0.1, -0.9))
		local strap = makePart("Strap", head.Parent :: Instance, Vector3.new(2.1, 0.3, 2.1), BrandColors.OilBlack, Enum.Material.Fabric)
		weld(head, strap, CFrame.new(0, 0.1, 0))
	elseif kind == "bandana" then
		local bandana = makePart("Bandana", head.Parent :: Instance, Vector3.new(2.1, 0.6, 2.1), accent, Enum.Material.Fabric)
		weld(head, bandana, CFrame.new(0, 0.4, 0))
	elseif kind == "hood" then
		-- Tall cylinder over the head.
		local hood = makePart("Hood", head.Parent :: Instance, Vector3.new(2.3, 1.6, 2.3), accent, Enum.Material.Fabric)
		weld(head, hood, CFrame.new(0, 0.5, 0))
	elseif kind == "cape" then
		-- A wedge behind torso instead of head — handled on the torso build.
		-- Mark head with a small dark wisp instead.
		local wisp = makePart("HexWisp", head.Parent :: Instance, Vector3.new(0.5, 0.5, 0.5), accent, Enum.Material.Neon)
		weld(head, wisp, CFrame.new(0, 0.9, 0))
	end
end

local function attachChestAccessory(torso: BasePart, kind: string, accent: Color3)
	if kind == "armor" then
		local plate = makePart("ArmorPlate", torso.Parent :: Instance, Vector3.new(2.1, 1.8, 0.4), accent, Enum.Material.Metal)
		weld(torso, plate, CFrame.new(0, 0, -0.6))
	elseif kind == "apron" then
		local apron = makePart("Apron", torso.Parent :: Instance, Vector3.new(1.9, 1.7, 0.3), accent, Enum.Material.Fabric)
		weld(torso, apron, CFrame.new(0, -0.05, -0.55))
	elseif kind == "coat" then
		-- Long coat — extends below torso.
		local coat = makePart("Coat", torso.Parent :: Instance, Vector3.new(2.2, 2.6, 1.2), accent, Enum.Material.Fabric)
		weld(torso, coat, CFrame.new(0, -0.4, 0))
	elseif kind == "robe" then
		local robe = makePart("Robe", torso.Parent :: Instance, Vector3.new(2.2, 2.4, 1.2), accent, Enum.Material.Fabric)
		weld(torso, robe, CFrame.new(0, -0.3, 0))
	elseif kind == "cape" then
		local cape = makePart("Cape", torso.Parent :: Instance, Vector3.new(2.4, 2.8, 0.3), accent, Enum.Material.Fabric)
		weld(torso, cape, CFrame.new(0, -0.4, 0.65))
	end
end

-- ── Disclosure BillboardGui ─────────────────────────────────────────
-- Two stacked lines above the head:
--   Line 1: stylized name (always visible)
--   Line 2: "Artificial Tinkerer" (only visible within ~20 studs)
-- The proximity reveal is enforced by MaxDistance on the BillboardGui
-- for line 2.

local function buildDisclosureLabel(head: BasePart, displayName: string, worldLabel: string)
	-- Line 1: always-visible name
	local nameBb = Instance.new("BillboardGui")
	nameBb.Name = "NameLabel"
	nameBb.Adornee = head
	nameBb.Size = UDim2.fromOffset(240, 36)
	nameBb.StudsOffset = Vector3.new(0, 3.2, 0)
	nameBb.AlwaysOnTop = true
	nameBb.MaxDistance = 200
	nameBb.Parent = head
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.fromScale(1, 1)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = displayName
	nameLbl.TextColor3 = BrandColors.SteamCream
	nameLbl.TextStrokeColor3 = BrandColors.OilBlack
	nameLbl.TextStrokeTransparency = 0
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.TextScaled = true
	nameLbl.Parent = nameBb
	local nameSz = Instance.new("UITextSizeConstraint"); nameSz.MaxTextSize = 20; nameSz.Parent = nameLbl

	-- Line 2: proximity-revealed sublabel — "Artificial Tinkerer"
	-- Sits just below line 1. MaxDistance = 20 makes it auto-fade past
	-- the threshold (Roblox handles the distance cutoff for us).
	local roleBb = Instance.new("BillboardGui")
	roleBb.Name = "RoleLabel"
	roleBb.Adornee = head
	roleBb.Size = UDim2.fromOffset(200, 24)
	roleBb.StudsOffset = Vector3.new(0, 2.5, 0)
	roleBb.AlwaysOnTop = true
	roleBb.MaxDistance = 20
	roleBb.Parent = head
	local roleLbl = Instance.new("TextLabel")
	roleLbl.Size = UDim2.fromScale(1, 1)
	roleLbl.BackgroundColor3 = BrandColors.Brass
	roleLbl.BackgroundTransparency = 0.2
	roleLbl.Text = worldLabel
	roleLbl.TextColor3 = BrandColors.OilBlack
	roleLbl.Font = Enum.Font.Antique
	roleLbl.TextScaled = true
	roleLbl.BorderSizePixel = 0
	roleLbl.Parent = roleBb
	local roleCorner = Instance.new("UICorner"); roleCorner.CornerRadius = UDim.new(0, 6); roleCorner.Parent = roleLbl
	local roleSz = Instance.new("UITextSizeConstraint"); roleSz.MaxTextSize = 14; roleSz.Parent = roleLbl
end

-- ── Build a complete agent humanoid model ───────────────────────────
-- Returns the Model with a Humanoid + class accessories + disclosure
-- label. Parented to Workspace at the given spawn position.
--
-- Caller is responsible for setting `model.PrimaryPart` if needed and
-- for triggering Humanoid:MoveTo() to drive walking.
function M.buildAgent(opts: {
	classId: string,
	displayName: string,
	worldLabel: string,
	spawnPosition: Vector3,
	walkSpeed: number,
}): Model
	local style = CLASS_STYLES[opts.classId] or CLASS_STYLES.Tinkerer

	local model = Instance.new("Model")
	model.Name = "AiAgent_" .. opts.displayName:gsub("[^%w]", "_")

	-- ── Torso ────────────────────────────────────────────────────
	-- Use a single-block "humanoid" style (R6-like) since R15 with rigged
	-- limbs would need a downloaded mesh. Custom NPCs with simple Parts
	-- are the Roblox-standard cheap NPC pattern.
	local torso = makePart("Torso", model, Vector3.new(2, 2, 1), style.bodyColor, Enum.Material.Fabric)
	torso.CFrame = CFrame.new(opts.spawnPosition)
	torso.Anchored = false
	torso.CanCollide = true
	model.PrimaryPart = torso

	-- ── Head ────────────────────────────────────────────────────
	local head = makePart("Head", model, Vector3.new(1.4, 1.4, 1.4), style.bodyColor, Enum.Material.Fabric)
	weld(torso, head, CFrame.new(0, 1.7, 0))
	head.CanCollide = false

	-- Face: two black dots for eyes (visual: clearly stylized NPC, not a face)
	local eyeL = makePart("EyeL", model, Vector3.new(0.18, 0.18, 0.05), BrandColors.OilBlack, Enum.Material.Neon)
	weld(head, eyeL, CFrame.new(-0.3, 0.1, -0.7))
	local eyeR = makePart("EyeR", model, Vector3.new(0.18, 0.18, 0.05), BrandColors.OilBlack, Enum.Material.Neon)
	weld(head, eyeR, CFrame.new(0.3, 0.1, -0.7))

	-- ── Limbs ───────────────────────────────────────────────────
	-- Two leg blocks (no animated joints — agents walk via the Humanoid
	-- root part movement; the legs stay rigidly welded to the torso).
	local legL = makePart("LegL", model, Vector3.new(0.7, 2, 1), style.bodyColor, Enum.Material.Fabric)
	weld(torso, legL, CFrame.new(-0.55, -2, 0))
	legL.CanCollide = false
	local legR = makePart("LegR", model, Vector3.new(0.7, 2, 1), style.bodyColor, Enum.Material.Fabric)
	weld(torso, legR, CFrame.new(0.55, -2, 0))
	legR.CanCollide = false

	-- Two arm blocks
	local armL = makePart("ArmL", model, Vector3.new(0.7, 2, 1), style.bodyColor, Enum.Material.Fabric)
	weld(torso, armL, CFrame.new(-1.35, 0, 0))
	armL.CanCollide = false
	local armR = makePart("ArmR", model, Vector3.new(0.7, 2, 1), style.bodyColor, Enum.Material.Fabric)
	weld(torso, armR, CFrame.new(1.35, 0, 0))
	armR.CanCollide = false

	-- ── Class accessories (the visual class identity) ────────────
	attachChestAccessory(torso, style.chestAccessory, style.accentColor)
	attachHeadAccessory(head, style.headAccessory, style.accentColor)

	-- ── Humanoid (drives walking) ───────────────────────────────
	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = opts.walkSpeed
	humanoid.JumpHeight = 0
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None  -- we use our own BillboardGui
	humanoid.NameOcclusion = Enum.NameOcclusion.NoOcclusion
	humanoid.Parent = model

	-- HumanoidRootPart is required by Roblox's NPC walk logic. R6 NPC
	-- convention: the torso doubles as HumanoidRootPart, but for the
	-- Humanoid:MoveTo() pathing to work cleanly we add a hidden one.
	local rootPart = makePart("HumanoidRootPart", model, Vector3.new(2, 2, 1), style.bodyColor, Enum.Material.Metal)
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Massless = true
	weld(torso, rootPart, CFrame.new(0, 0, 0))

	-- ── Disclosure label (layers 2 + 3 of the 3-layer tell) ──────
	buildDisclosureLabel(head, opts.displayName, opts.worldLabel)

	return model
end

return M
