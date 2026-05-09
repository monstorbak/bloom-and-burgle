--!strict
-- Hexerine "Stitches" — eccentric witch-alchemist NPC, west stall.
--
-- BAB-MARKETPLACE-NPC-ROTATION (2026-05-08).
-- Visual identity: WitchVellum-purple robes, CopperPatina alembic with
-- AetherCyan glow particles. Pays asset-premium for class-aligned harvests.

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local MerchantPersonalities = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MerchantPersonalities"))
local MerchantSellFlow = require(ServerScriptService:WaitForChild("MerchantSellFlow"))

local NPC_ID = "hexerine"
local STALL_POSITION = Vector3.new(-30, 4, -30)   -- west of Bart
local PROMPT_RADIUS = 8

local personality = MerchantPersonalities.get(NPC_ID)
assert(personality, "Hexerine: personality missing in MerchantPersonalities")

-- ── Build stall ──────────────────────────────────────────────────────
local stall = Instance.new("Model")
stall.Name = "HexerineStall"
stall.Parent = Workspace

-- Pad — slightly larger than Bart's, hex-paneled feel via wood + dark trim
local pad = Instance.new("Part")
pad.Name = "Pad"
pad.Anchored = true
pad.CanCollide = true
pad.Material = Enum.Material.WoodPlanks
pad.Color = BrandColors.OilBlack
pad.Size = Vector3.new(10, 1, 10)
pad.Position = STALL_POSITION
pad.Parent = stall

-- Counter — vellum purple instead of brass
local counter = Instance.new("Part")
counter.Name = "Counter"
counter.Anchored = true
counter.CanCollide = true
counter.Material = Enum.Material.Fabric    -- ragged-cloth read for "stitches"
counter.Color = BrandColors.WitchVellum
counter.Size = Vector3.new(8, 3, 1.4)
counter.Position = STALL_POSITION + Vector3.new(0, 1.7, -3)
counter.Parent = stall

-- Sign — copper trim
local sign = Instance.new("Part")
sign.Name = "Sign"
sign.Anchored = true
sign.CanCollide = false
sign.Material = Enum.Material.Metal
sign.Color = BrandColors.CopperPatina
sign.Size = Vector3.new(7, 2, 0.5)
sign.Position = STALL_POSITION + Vector3.new(0, 6, -4)
sign.Parent = stall

local sgui = Instance.new("SurfaceGui")
sgui.Face = Enum.NormalId.Front
sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
sgui.PixelsPerStud = 50
sgui.Parent = sign
local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.fromScale(1, 1)
lbl.BackgroundTransparency = 1
lbl.Text = personality.emoji .. " " .. personality.displayName:upper()
lbl.TextColor3 = BrandColors.SteamCream
lbl.Font = Enum.Font.Antique
lbl.TextScaled = true
lbl.Parent = sgui

-- NPC body — purple robe column
local npc = Instance.new("Part")
npc.Name = "Hexerine"
npc.Anchored = true
npc.CanCollide = false
npc.Material = Enum.Material.Fabric
npc.Color = BrandColors.WitchVellum
npc.Size = Vector3.new(2, 5, 2)
npc.Position = STALL_POSITION + Vector3.new(0, 3, -4.5)
npc.Parent = stall

-- Head — pale stitched leather (steam cream)
local head = Instance.new("Part")
head.Name = "Head"
head.Shape = Enum.PartType.Ball
head.Anchored = true
head.CanCollide = false
head.Material = Enum.Material.Fabric
head.Color = BrandColors.SteamCream
head.Size = Vector3.new(1.6, 1.6, 1.6)
head.Position = STALL_POSITION + Vector3.new(0, 6.2, -4.5)
head.Parent = stall

-- Alembic — copper-patina vessel with aether-cyan glow on the counter
local alembic = Instance.new("Part")
alembic.Name = "Alembic"
alembic.Shape = Enum.PartType.Cylinder
alembic.Anchored = true
alembic.CanCollide = false
alembic.Material = Enum.Material.Metal
alembic.Color = BrandColors.CopperPatina
alembic.Size = Vector3.new(2.2, 1.6, 1.6)   -- cylinder oriented along Z
alembic.Orientation = Vector3.new(0, 0, 90)
alembic.Position = STALL_POSITION + Vector3.new(2.5, 3.4, -3)
alembic.Parent = stall

local alembicGlow = Instance.new("Part")
alembicGlow.Name = "AlembicGlow"
alembicGlow.Shape = Enum.PartType.Ball
alembicGlow.Anchored = true
alembicGlow.CanCollide = false
alembicGlow.Material = Enum.Material.Neon
alembicGlow.Color = BrandColors.AetherCyan
alembicGlow.Transparency = 0.3
alembicGlow.Size = Vector3.new(0.8, 0.8, 0.8)
alembicGlow.Position = STALL_POSITION + Vector3.new(2.5, 4.2, -3)
alembicGlow.Parent = stall

-- Steam puff from the alembic
local steamAttach = Instance.new("Attachment")
steamAttach.Position = Vector3.new(0, 0.6, 0)
steamAttach.Parent = alembicGlow

local steam = Instance.new("ParticleEmitter")
steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
steam.Color = ColorSequence.new(BrandColors.AetherCyan)
steam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(0.6, 0.7),
	NumberSequenceKeypoint.new(1, 1),
})
steam.Size = NumberSequence.new(0.6, 1.4)
steam.Lifetime = NumberRange.new(2.0, 3.0)
steam.Rate = 4
steam.Speed = NumberRange.new(1.0, 1.8)
steam.SpreadAngle = Vector2.new(8, 8)
steam.Parent = steamAttach

-- ── Today's special plaque (Phase 3 plaza-visible banner) ────────────
local todaysSId, todaysSName, todaysSEmoji = MerchantSellFlow.todaysSpecialFor(NPC_ID)
if todaysSName then
	local plaque = Instance.new("Part")
	plaque.Name = "TodaysSpecialPlaque"
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.Material = Enum.Material.Metal
	plaque.Color = BrandColors.WitchVellum
	plaque.Size = Vector3.new(7, 1.2, 0.5)
	plaque.Position = STALL_POSITION + Vector3.new(0, 4.4, -4)
	plaque.Parent = stall

	local pgui = Instance.new("SurfaceGui")
	pgui.Face = Enum.NormalId.Front
	pgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	pgui.PixelsPerStud = 50
	pgui.Parent = plaque

	local plbl = Instance.new("TextLabel")
	plbl.Size = UDim2.fromScale(1, 1)
	plbl.BackgroundTransparency = 1
	plbl.Text = string.format("🜍 ESSENCE: %s %s", todaysSEmoji or "", todaysSName)
	plbl.TextColor3 = BrandColors.SteamCream
	plbl.Font = Enum.Font.GothamBold
	plbl.TextScaled = true
	plbl.Parent = pgui
end

-- ── Prompt + wire to MerchantSellFlow ────────────────────────────────
local prompt = Instance.new("ProximityPrompt")
prompt.Name = "HexerinePrompt"
prompt.ActionText = personality.actionText
prompt.ObjectText = personality.objectText
prompt.HoldDuration = 0
prompt.MaxActivationDistance = PROMPT_RADIUS
prompt.RequiresLineOfSight = false
prompt.Parent = npc

MerchantSellFlow.attachNPC(NPC_ID, prompt)
