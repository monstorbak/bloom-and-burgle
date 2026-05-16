--!strict
-- ClocktowerScript — builds the Brass Clocktower at Cogworks plaza
-- center. The hero landmark of Bloom & Burgle.
--
-- BAB-DESIGN-CRITIQUE Tier 2 (2026-05-10).
--
-- Per the 2026-05-10 design audit, the world was bottlenecked by having
-- no iconic landmark — every aerial screenshot would lose to a generic
-- cottagecore farm sim. The Clocktower is the answer: a 60-stud-tall
-- brass-and-charcoal structure with a clock face that actually ticks,
-- visible from every plot on the map.
--
-- ── Geometry ─────────────────────────────────────────────────────────
-- Replaces the deleted Fountain (was at 0, 4.5, 0 — see TownSquare
-- model.json migration in the same commit).
--
-- Anatomy (bottom-up):
--   Base     — octagonal stone-and-brass plinth, 16 studs wide, 4 tall
--   Column   — brass-banded charcoal shaft, 8 studs wide, 36 tall
--   ClockFace — 4 SurfaceGuis (N/S/E/W) on a 10-stud cube near the top
--   Spire    — copper-patina cone topping it off
--   AetherLight — PointLight inside the spire, visible at night
--
-- ── Hands ────────────────────────────────────────────────────────────
-- Hour + minute hands tied to os.time() so the clock shows REAL time.
-- A small `task.spawn(loop)` updates rotation every 5 seconds. Cheap and
-- exact (server clock is authoritative; clients see consistent state).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local UIComponents = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIComponents"))

-- ── Clean up legacy fountain if it still exists in workspace ─────────
-- The TownSquare model.json no longer ships it, but live servers that
-- haven't republished yet may still have it. Belt + suspenders.
do
	local ts = Workspace:FindFirstChild("TownSquare")
	if ts then
		local f = ts:FindFirstChild("Fountain")
		if f then f:Destroy() end
	end
end

-- ── Layout constants ────────────────────────────────────────────────
local BASE_POS = Vector3.new(0, 0, 0)   -- center of plaza
local BASE_SIZE = Vector3.new(16, 4, 16)
local COLUMN_SIZE = Vector3.new(8, 36, 8)
local CLOCK_CUBE_SIZE = Vector3.new(10, 10, 10)
local SPIRE_HEIGHT = 8

-- Vertical centers
local BASE_Y = BASE_POS.Y + BASE_SIZE.Y / 2          -- 2
local COLUMN_Y = BASE_Y + BASE_SIZE.Y / 2 + COLUMN_SIZE.Y / 2  -- 22
local CLOCK_Y = COLUMN_Y + COLUMN_SIZE.Y / 2 + CLOCK_CUBE_SIZE.Y / 2  -- 45
local SPIRE_Y = CLOCK_Y + CLOCK_CUBE_SIZE.Y / 2 + SPIRE_HEIGHT / 2     -- 54

-- ── Build root model ────────────────────────────────────────────────
local tower = Instance.new("Model")
tower.Name = "BrassClocktower"
tower.Parent = Workspace

local function part(name: string, color: Color3, material: Enum.Material, size: Vector3, pos: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.Material = material
	p.Color = color
	p.Size = size
	p.Position = pos
	p.Parent = tower
	return p
end

-- Base plinth — chunky stone-and-brass octagon (Roblox doesn't have a
-- cheap octagon primitive, so this is a wide chamfered block).
local base = part(
	"Base",
	BrandColors.IronworkCharcoal,
	Enum.Material.Slate,
	BASE_SIZE,
	BASE_POS + Vector3.new(0, BASE_Y, 0)
)

-- Brass rim around the base (top edge — like a metal cap on the plinth).
local rim = part(
	"BaseRim",
	BrandColors.Brass,
	Enum.Material.Metal,
	Vector3.new(BASE_SIZE.X + 0.6, 0.8, BASE_SIZE.Z + 0.6),
	BASE_POS + Vector3.new(0, BASE_Y + BASE_SIZE.Y / 2, 0)
)

-- Column — the main vertical shaft.
local column = part(
	"Column",
	BrandColors.IronworkCharcoal,
	Enum.Material.Metal,
	COLUMN_SIZE,
	BASE_POS + Vector3.new(0, COLUMN_Y, 0)
)

-- Brass bands at 1/3 and 2/3 up the column — gives it the "machined
-- engineering" silhouette instead of looking like a featureless pillar.
local function brassBand(yOffset: number)
	part(
		"BrassBand",
		BrandColors.Brass,
		Enum.Material.Metal,
		Vector3.new(COLUMN_SIZE.X + 0.4, 0.8, COLUMN_SIZE.Z + 0.4),
		BASE_POS + Vector3.new(0, COLUMN_Y - COLUMN_SIZE.Y / 2 + yOffset, 0)
	)
end
brassBand(COLUMN_SIZE.Y / 3)
brassBand(2 * COLUMN_SIZE.Y / 3)

-- Clock face cube — sits atop the column.
local clockCube = part(
	"ClockHead",
	BrandColors.Brass,
	Enum.Material.Metal,
	CLOCK_CUBE_SIZE,
	BASE_POS + Vector3.new(0, CLOCK_Y, 0)
)

-- Spire — copper-patina cone (wedges form a rough pyramid). One central
-- pyramid is enough at this scale; the SpecialMesh keeps part-count low.
local spire = Instance.new("Part")
spire.Name = "Spire"
spire.Anchored = true
spire.CanCollide = false
spire.Material = Enum.Material.Metal
spire.Color = BrandColors.CopperPatina
spire.Size = Vector3.new(8, SPIRE_HEIGHT, 8)
spire.Position = BASE_POS + Vector3.new(0, SPIRE_Y, 0)
spire.Parent = tower
local spireMesh = Instance.new("SpecialMesh")
spireMesh.MeshType = Enum.MeshType.Wedge
spireMesh.Scale = Vector3.new(1, 1, 1)
spireMesh.Parent = spire

-- Aether light at the spire — visible glow at night. PointLight,
-- AetherCyan, large range so it casts onto the column below.
local aetherLight = Instance.new("PointLight")
aetherLight.Color = BrandColors.AetherCyan
aetherLight.Brightness = 3
aetherLight.Range = 30
aetherLight.Shadows = false
aetherLight.Parent = spire

-- ── Clock faces (N / S / E / W) ──────────────────────────────────────
-- One SurfaceGui per cardinal face of the ClockHead cube. Each contains
-- a brass-on-charcoal dial with 12 hour ticks + animated hour + minute
-- hands (Frames anchored at clock center, rotated each tick).

type FaceHands = {
	gui: SurfaceGui,
	hour: Frame,
	minute: Frame,
}

local faces: { FaceHands } = {}

local function buildFace(normalId: Enum.NormalId): FaceHands
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face_" .. tostring(normalId.Name)
	gui.Face = normalId
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.4
	gui.Parent = clockCube

	-- Charcoal background panel for the dial.
	local dial = Instance.new("Frame")
	dial.Size = UDim2.fromScale(1, 1)
	dial.BackgroundColor3 = BrandColors.OilBlack
	dial.BorderSizePixel = 0
	dial.Parent = gui

	-- 12 hour ticks around the dial — small brass rectangles rotated.
	for h = 1, 12 do
		local angle = (h - 3) * (math.pi / 6)   -- -3 so 12 is at top
		local tick = Instance.new("Frame")
		tick.Size = UDim2.new(0, 12, 0, 30)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Place at 40% from center.
		tick.Position = UDim2.new(0.5 + math.cos(angle) * 0.4, 0, 0.5 + math.sin(angle) * 0.4, 0)
		tick.BackgroundColor3 = BrandColors.Brass
		tick.BorderSizePixel = 0
		tick.Rotation = math.deg(angle) + 90
		tick.Parent = dial
	end

	-- Hour hand — chunky brass spike.
	local hour = Instance.new("Frame")
	hour.Name = "HourHand"
	hour.Size = UDim2.new(0, 14, 0, 100)
	hour.AnchorPoint = Vector2.new(0.5, 0.85)   -- pivot near the base
	hour.Position = UDim2.fromScale(0.5, 0.5)
	hour.BackgroundColor3 = BrandColors.Brass
	hour.BorderSizePixel = 0
	hour.ZIndex = 2
	hour.Parent = dial

	-- Minute hand — longer + thinner, copper-patina to differentiate.
	local minute = Instance.new("Frame")
	minute.Name = "MinuteHand"
	minute.Size = UDim2.new(0, 8, 0, 150)
	minute.AnchorPoint = Vector2.new(0.5, 0.9)
	minute.Position = UDim2.fromScale(0.5, 0.5)
	minute.BackgroundColor3 = BrandColors.CopperPatina
	minute.BorderSizePixel = 0
	minute.ZIndex = 3
	minute.Parent = dial

	-- Center pin — small brass dot covering the hand pivots.
	local pin = Instance.new("Frame")
	pin.Size = UDim2.new(0, 20, 0, 20)
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.fromScale(0.5, 0.5)
	pin.BackgroundColor3 = BrandColors.Brass
	pin.BorderSizePixel = 0
	pin.ZIndex = 4
	pin.Parent = dial
	local pinCorner = Instance.new("UICorner")
	pinCorner.CornerRadius = UDim.new(1, 0)
	pinCorner.Parent = pin

	return { gui = gui, hour = hour, minute = minute }
end

for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
	table.insert(faces, buildFace(face))
end

-- ── Foundation plaque (engraved brass slab on the base) ─────────────
-- Replaces the "🌸 Bloom & Burgle 💰" floating banner that was deleted
-- from the WelcomeArch. Branding belongs in the world, on metal.
local plaque = Instance.new("Part")
plaque.Name = "FoundationPlaque"
plaque.Anchored = true
plaque.CanCollide = false
plaque.Material = Enum.Material.Metal
plaque.Color = BrandColors.Brass
plaque.Size = Vector3.new(12, 2, 0.3)
plaque.CFrame = CFrame.new(BASE_POS + Vector3.new(0, BASE_Y + 0.5, BASE_SIZE.Z / 2 + 0.1))
plaque.Parent = tower
local plaqueGui = Instance.new("SurfaceGui")
plaqueGui.Face = Enum.NormalId.Front
plaqueGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
plaqueGui.PixelsPerStud = 60
plaqueGui.Parent = plaque
local plaqueText = UIComponents.buildWorldSign({
	name = "PlaqueText",
	text = "🌸 BLOOM & BURGLE • EST. 1882",
	maxTextSize = 56,
})
plaqueText.Parent = plaqueGui

-- ── Hand animation loop ──────────────────────────────────────────────
-- Update every 5 seconds — minute-resolution is plenty for a clock
-- spire seen from across the map. Tied to os.time() so all servers
-- show consistent time.

local function updateHands()
	local secs = os.time()
	local hours = (secs / 3600) % 12
	local mins = (secs / 60) % 60
	local hourAngle = (hours / 12) * 360
	local minuteAngle = (mins / 60) * 360
	for _, f in faces do
		f.hour.Rotation = hourAngle
		f.minute.Rotation = minuteAngle
	end
end

updateHands()
task.spawn(function()
	while true do
		task.wait(5)
		updateHands()
	end
end)

print(string.format(
	"[BAB-LIFE] BrassClocktower online — %d studs tall, plaza-center hero landmark, 4 ticking faces",
	math.floor(SPIRE_Y + SPIRE_HEIGHT / 2)
))
