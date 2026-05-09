--!strict
-- BrassBart — gruff dwarf-coded mech-trader NPC, central stall.
--
-- BAB-MARKETPLACE-NPC-ROTATION (2026-05-08). Refactored from the v1
-- single-multiplier scaffold to consume the shared MerchantSellFlow helper.
-- Pricing, telemetry, and rate-limiting all flow through MerchantSellFlow.
-- This script only owns Bart's VISUALS and his stall geometry.

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local MerchantPersonalities = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MerchantPersonalities"))
local MerchantSellFlow = require(ServerScriptService:WaitForChild("MerchantSellFlow"))

local NPC_ID = "bart"
local STALL_POSITION = Vector3.new(0, 4, -30)   -- north-center (was -30, -30 in v1)
local PROMPT_RADIUS = 8

local personality = MerchantPersonalities.get(NPC_ID)
assert(personality, "BrassBart: personality missing in MerchantPersonalities")

-- ── Build stall ──────────────────────────────────────────────────────
local stall = Instance.new("Model")
stall.Name = "BrassBartStall"
stall.Parent = Workspace

-- Pad
local pad = Instance.new("Part")
pad.Name = "Pad"
pad.Anchored = true
pad.CanCollide = true
pad.Material = Enum.Material.WoodPlanks
pad.Color = BrandColors.OilBlack
pad.Size = Vector3.new(10, 1, 10)
pad.Position = STALL_POSITION
pad.Parent = stall

-- Brass-topped counter
local counter = Instance.new("Part")
counter.Name = "Counter"
counter.Anchored = true
counter.CanCollide = true
counter.Material = Enum.Material.Metal
counter.Color = BrandColors.Brass
counter.Size = Vector3.new(8, 3, 1.4)
counter.Position = STALL_POSITION + Vector3.new(0, 1.7, -3)
counter.Parent = stall

-- Sign over the counter
local sign = Instance.new("Part")
sign.Name = "Sign"
sign.Anchored = true
sign.CanCollide = false
sign.Material = Enum.Material.Metal
sign.Color = BrandColors.Brass
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
lbl.TextColor3 = BrandColors.OilBlack
lbl.Font = Enum.Font.Antique
lbl.TextScaled = true
lbl.Parent = sgui

-- NPC body — charcoal column, brass head (same v1 stand-in; proper
-- character authoring is the BAB-NPC-CHARACTERS P2 task).
local npc = Instance.new("Part")
npc.Name = "BrassBart"
npc.Anchored = true
npc.CanCollide = false
npc.Material = Enum.Material.Metal
npc.Color = BrandColors.IronworkCharcoal
npc.Size = Vector3.new(2, 5, 2)
npc.Position = STALL_POSITION + Vector3.new(0, 3, -4.5)
npc.Parent = stall

local head = Instance.new("Part")
head.Name = "Head"
head.Shape = Enum.PartType.Ball
head.Anchored = true
head.CanCollide = false
head.Material = Enum.Material.Metal
head.Color = BrandColors.Brass
head.Size = Vector3.new(1.6, 1.6, 1.6)
head.Position = STALL_POSITION + Vector3.new(0, 6.2, -4.5)
head.Parent = stall

-- ── Today's special plaque (Phase 3 plaza-visible banner) ────────────
-- Smaller sign immediately below the main sign, gold-accented to draw
-- the eye. Visible from across the plaza so players can shop the rotation
-- before committing to a stall.
local todaysSId, todaysSName, todaysSEmoji = MerchantSellFlow.todaysSpecialFor(NPC_ID)
if todaysSName then
	local plaque = Instance.new("Part")
	plaque.Name = "TodaysSpecialPlaque"
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.Material = Enum.Material.Metal
	plaque.Color = BrandColors.GoggleGold
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
	plbl.Text = string.format("🌟 TODAY: %s %s", todaysSEmoji or "", todaysSName)
	plbl.TextColor3 = BrandColors.OilBlack
	plbl.Font = Enum.Font.GothamBold
	plbl.TextScaled = true
	plbl.Parent = pgui
end

-- ── Prompt + wire to MerchantSellFlow ────────────────────────────────
local prompt = Instance.new("ProximityPrompt")
prompt.Name = "BrassBartPrompt"
prompt.ActionText = personality.actionText
prompt.ObjectText = personality.objectText
prompt.HoldDuration = 0
prompt.MaxActivationDistance = PROMPT_RADIUS
prompt.RequiresLineOfSight = false
prompt.Parent = npc

MerchantSellFlow.attachNPC(NPC_ID, prompt)
