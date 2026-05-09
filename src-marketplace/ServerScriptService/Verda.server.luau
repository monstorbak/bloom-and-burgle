--!strict
-- Sky Captain Verda — cocky airship-pilot NPC, east stall.
--
-- BAB-MARKETPLACE-NPC-ROTATION (2026-05-08).
-- Visual identity: SkyCaptainNavy flight coat, Brass goggles+rank, ValveRed
-- airship-cape detail. Pays liability premium for winged species; scoffs at
-- ground-bound stock at 0.8× base.

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local MerchantPersonalities = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MerchantPersonalities"))
local MerchantSellFlow = require(ServerScriptService:WaitForChild("MerchantSellFlow"))

local NPC_ID = "verda"
local STALL_POSITION = Vector3.new(30, 4, -30)   -- east of Bart
local PROMPT_RADIUS = 8

local personality = MerchantPersonalities.get(NPC_ID)
assert(personality, "Verda: personality missing in MerchantPersonalities")

-- ── Build stall ──────────────────────────────────────────────────────
local stall = Instance.new("Model")
stall.Name = "VerdaStall"
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

-- Counter — sky navy with brass trim feel
local counter = Instance.new("Part")
counter.Name = "Counter"
counter.Anchored = true
counter.CanCollide = true
counter.Material = Enum.Material.Metal
counter.Color = BrandColors.SkyCaptainNavy
counter.Size = Vector3.new(8, 3, 1.4)
counter.Position = STALL_POSITION + Vector3.new(0, 1.7, -3)
counter.Parent = stall

-- Sign — gold lettering on navy field
local sign = Instance.new("Part")
sign.Name = "Sign"
sign.Anchored = true
sign.CanCollide = false
sign.Material = Enum.Material.Metal
sign.Color = BrandColors.SkyCaptainNavy
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
lbl.TextColor3 = BrandColors.GoggleGold
lbl.Font = Enum.Font.Antique
lbl.TextScaled = true
lbl.Parent = sgui

-- NPC body — navy flight coat
local npc = Instance.new("Part")
npc.Name = "Verda"
npc.Anchored = true
npc.CanCollide = false
npc.Material = Enum.Material.Fabric
npc.Color = BrandColors.SkyCaptainNavy
npc.Size = Vector3.new(2, 5, 2)
npc.Position = STALL_POSITION + Vector3.new(0, 3, -4.5)
npc.Parent = stall

-- Cape — valve-red, drapes off the back
local cape = Instance.new("Part")
cape.Name = "Cape"
cape.Anchored = true
cape.CanCollide = false
cape.Material = Enum.Material.Fabric
cape.Color = BrandColors.ValveRed
cape.Size = Vector3.new(2.6, 4.5, 0.2)
cape.Position = STALL_POSITION + Vector3.new(0, 3.5, -5.4)
cape.Parent = stall

-- Head — brass-helmet read
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

-- Goggles — gold rim halfway down the helmet
local goggles = Instance.new("Part")
goggles.Name = "Goggles"
goggles.Anchored = true
goggles.CanCollide = false
goggles.Material = Enum.Material.Metal
goggles.Color = BrandColors.GoggleGold
goggles.Size = Vector3.new(1.7, 0.4, 0.4)
goggles.Position = STALL_POSITION + Vector3.new(0, 6.2, -3.85)
goggles.Parent = stall

-- Mini airship — small docked dirigible above the stall as her signature
-- silhouette. Two parts: hull (navy) + balloon (cream).
local hull = Instance.new("Part")
hull.Name = "AirshipHull"
hull.Shape = Enum.PartType.Cylinder
hull.Anchored = true
hull.CanCollide = false
hull.Material = Enum.Material.WoodPlanks
hull.Color = BrandColors.SkyCaptainNavy
hull.Size = Vector3.new(4, 1.2, 1.2)
hull.Orientation = Vector3.new(0, 0, 90)
hull.Position = STALL_POSITION + Vector3.new(3, 9, -3)
hull.Parent = stall

local balloon = Instance.new("Part")
balloon.Name = "AirshipBalloon"
balloon.Shape = Enum.PartType.Ball
balloon.Anchored = true
balloon.CanCollide = false
balloon.Material = Enum.Material.Fabric
balloon.Color = BrandColors.SteamCream
balloon.Size = Vector3.new(4, 2.2, 2)
balloon.Position = STALL_POSITION + Vector3.new(3, 10.6, -3)
balloon.Parent = stall

-- ── Today's special plaque (Phase 3 plaza-visible banner) ────────────
local todaysSId, todaysSName, todaysSEmoji = MerchantSellFlow.todaysSpecialFor(NPC_ID)
if todaysSName then
	local plaque = Instance.new("Part")
	plaque.Name = "TodaysSpecialPlaque"
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.Material = Enum.Material.Metal
	plaque.Color = BrandColors.ValveRed
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
	plbl.Text = string.format("✈ TODAY'S CARGO: %s %s", todaysSEmoji or "", todaysSName)
	plbl.TextColor3 = BrandColors.GoggleGold
	plbl.Font = Enum.Font.GothamBold
	plbl.TextScaled = true
	plbl.Parent = pgui
end

-- ── Prompt + wire to MerchantSellFlow ────────────────────────────────
local prompt = Instance.new("ProximityPrompt")
prompt.Name = "VerdaPrompt"
prompt.ActionText = personality.actionText
prompt.ObjectText = personality.objectText
prompt.HoldDuration = 0
prompt.MaxActivationDistance = PROMPT_RADIUS
prompt.RequiresLineOfSight = false
prompt.Parent = npc

MerchantSellFlow.attachNPC(NPC_ID, prompt)
