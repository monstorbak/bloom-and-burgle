--!strict
-- ClassBadgeHUD: persistent identity HUD per Bloom&Burgle_Design_Spec.md §3.1.
-- Top-left corner of the screen, never moves.
--
-- BAB-UX (2026-05-08): collapsed from 3 stacked frames (124px tall column)
-- to one wider horizontal card (54px tall). Saves ~70px of vertical screen
-- space, letting the world signage and the objective hint banner breathe.
-- Layout: [crest] HEXER  ⚙ 312  🐾 0/6
--
-- Rebuilds on Class attribute change so respeccing reflects immediately.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local ClassData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClassData"))
local ScrapPlantsRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ScrapPlants") :: RemoteEvent

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local function makeCorner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function makeStroke(p: Instance, color: Color3, t: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = t
	s.Parent = p
end

local screen = Instance.new("ScreenGui")
screen.Name = "ClassBadgeScreen"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 50
screen.Parent = pg

-- One horizontal card holds class + cog + stable. Width grows with content
-- but capped so it never spans more than ~25% of the screen on a phone.
local card = Instance.new("Frame")
card.Name = "ClassCard"
card.AnchorPoint = Vector2.new(0, 0)
card.Position = UDim2.fromOffset(12, 80)            -- below Roblox top bar
card.Size = UDim2.fromOffset(280, 54)
card.BackgroundColor3 = BrandColors.OilBlack
card.BackgroundTransparency = 0.1
card.BorderSizePixel = 0
card.Parent = screen
makeCorner(card, 12)
makeStroke(card, BrandColors.Brass, 2)
do
	local sz = Instance.new("UISizeConstraint")
	sz.MinSize = Vector2.new(220, 48)
	sz.MaxSize = Vector2.new(320, 60)
	sz.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = card
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 8)
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Parent = card
end

-- ── Crest + class name ────────────────────────────────────────
local classGroup = Instance.new("Frame")
classGroup.Name = "ClassGroup"
classGroup.LayoutOrder = 1
classGroup.BackgroundTransparency = 1
classGroup.Size = UDim2.new(0, 130, 1, -8)
classGroup.Parent = card

local crestLbl = Instance.new("TextLabel")
crestLbl.Name = "Crest"
crestLbl.AnchorPoint = Vector2.new(0, 0.5)
crestLbl.Position = UDim2.new(0, 0, 0.5, 0)
crestLbl.Size = UDim2.fromOffset(28, 28)
crestLbl.BackgroundTransparency = 1
crestLbl.Text = "?"
crestLbl.TextColor3 = BrandColors.GoggleGold
crestLbl.TextScaled = true
crestLbl.Font = Enum.Font.FredokaOne
crestLbl.Parent = classGroup
do
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 24; tx.Parent = crestLbl
end

local nameLbl = Instance.new("TextLabel")
nameLbl.Name = "ClassName"
nameLbl.AnchorPoint = Vector2.new(0, 0.5)
nameLbl.Position = UDim2.new(0, 32, 0.5, 0)
nameLbl.Size = UDim2.new(1, -34, 0, 20)
nameLbl.BackgroundTransparency = 1
nameLbl.Text = "PICK CLASS"
nameLbl.TextColor3 = BrandColors.SteamCream
nameLbl.TextScaled = true
nameLbl.TextXAlignment = Enum.TextXAlignment.Left
nameLbl.Font = Enum.Font.FredokaOne
nameLbl.Parent = classGroup
do
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 18; tx.Parent = nameLbl
end

-- A thin vertical separator between class and the inline counters.
local sep = Instance.new("Frame")
sep.Name = "Sep"
sep.LayoutOrder = 2
sep.Size = UDim2.new(0, 1, 0.6, 0)
sep.AnchorPoint = Vector2.new(0, 0.5)
sep.Position = UDim2.new(0, 0, 0.5, 0)
sep.BackgroundColor3 = BrandColors.IronworkCharcoal
sep.BackgroundTransparency = 0.4
sep.BorderSizePixel = 0
sep.Parent = card

-- ── Inline cog chip ───────────────────────────────────────────
local cogGroup = Instance.new("Frame")
cogGroup.Name = "CogGroup"
cogGroup.LayoutOrder = 3
cogGroup.BackgroundTransparency = 1
cogGroup.Size = UDim2.new(0, 70, 1, -8)
cogGroup.Parent = card

local cogIcon = Instance.new("TextLabel")
cogIcon.AnchorPoint = Vector2.new(0, 0.5)
cogIcon.Position = UDim2.new(0, 0, 0.5, 0)
cogIcon.Size = UDim2.fromOffset(20, 20)
cogIcon.BackgroundTransparency = 1
cogIcon.Text = "⚙"
cogIcon.TextColor3 = BrandColors.GoggleGold
cogIcon.TextScaled = true
cogIcon.Font = Enum.Font.FredokaOne
cogIcon.Parent = cogGroup

local cogLbl = Instance.new("TextLabel")
cogLbl.Name = "CogValue"
cogLbl.AnchorPoint = Vector2.new(0, 0.5)
cogLbl.Position = UDim2.new(0, 24, 0.5, 0)
cogLbl.Size = UDim2.new(1, -26, 0, 18)
cogLbl.BackgroundTransparency = 1
cogLbl.Text = "0"
cogLbl.TextColor3 = BrandColors.SteamCream
cogLbl.TextScaled = true
cogLbl.TextXAlignment = Enum.TextXAlignment.Left
cogLbl.Font = Enum.Font.GothamBold
cogLbl.Parent = cogGroup
do
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 16; tx.Parent = cogLbl
end

-- ── Inline stable chip ────────────────────────────────────────
local stableGroup = Instance.new("Frame")
stableGroup.Name = "StableGroup"
stableGroup.LayoutOrder = 4
stableGroup.BackgroundTransparency = 1
stableGroup.Size = UDim2.new(0, 60, 1, -8)
stableGroup.Parent = card

local stableIcon = Instance.new("TextLabel")
stableIcon.AnchorPoint = Vector2.new(0, 0.5)
stableIcon.Position = UDim2.new(0, 0, 0.5, 0)
stableIcon.Size = UDim2.fromOffset(20, 20)
stableIcon.BackgroundTransparency = 1
stableIcon.Text = "🐾"
stableIcon.TextScaled = true
stableIcon.Font = Enum.Font.FredokaOne
stableIcon.Parent = stableGroup

local stableLbl = Instance.new("TextLabel")
stableLbl.Name = "StableValue"
stableLbl.AnchorPoint = Vector2.new(0, 0.5)
stableLbl.Position = UDim2.new(0, 24, 0.5, 0)
stableLbl.Size = UDim2.new(1, -26, 0, 18)
stableLbl.BackgroundTransparency = 1
stableLbl.Text = "0/6"
stableLbl.TextColor3 = BrandColors.SteamCream
stableLbl.TextScaled = true
stableLbl.TextXAlignment = Enum.TextXAlignment.Left
stableLbl.Font = Enum.Font.GothamBold
stableLbl.Parent = stableGroup
do
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 16; tx.Parent = stableLbl
end

-- Aliases for the live-update bindings below — they referenced the old
-- variable names (classBadge, cogChip, stableChip) for the .UIStroke pulse
-- on scrap. The pulse target is now the whole card, since cog is inline.
local classBadge = card
local cogChip = card

-- ── Live update bindings ──────────────────────────────────────
local function refreshClass()
	local classId = player:GetAttribute("Class")
	if classId then
		local spec = ClassData.get(classId)
		if spec then
			crestLbl.Text = spec.crest
			crestLbl.TextColor3 = BrandColors.classAccent(spec.displayName)
			nameLbl.Text = string.upper(spec.displayName)
			classBadge.UIStroke.Color = BrandColors.classAccent(spec.displayName)
		end
	else
		crestLbl.Text = "?"
		crestLbl.TextColor3 = BrandColors.SteamCream
		nameLbl.Text = "PICK CLASS"
		classBadge.UIStroke.Color = BrandColors.Brass
	end
end

local function refreshCog()
	local v = player:GetAttribute("CogParts") or 0
	-- Inline format: just the number. The ⚙ icon next to it does the labelling.
	if v >= 1000 then
		cogLbl.Text = string.format("%.1fK", v / 1000):gsub("%.0K", "K")
	else
		cogLbl.Text = tostring(v)
	end
end

local function refreshStable()
	local size = player:GetAttribute("StableSize") or 0
	local cap = player:GetAttribute("StableCapacity") or 6
	-- Inline format: 0/6. The 🐾 icon does the labelling.
	stableLbl.Text = string.format("%d/%d", size, cap)
end

refreshClass()
refreshCog()
refreshStable()

player:GetAttributeChangedSignal("Class"):Connect(refreshClass)
player:GetAttributeChangedSignal("CogParts"):Connect(refreshCog)
player:GetAttributeChangedSignal("StableSize"):Connect(refreshStable)
player:GetAttributeChangedSignal("StableCapacity"):Connect(refreshStable)

-- Scrap toast — wired here since CogChip is the visible target
ScrapPlantsRE.OnClientEvent:Connect(function(amount: number, skipped: number?)
	if amount and amount > 0 then
		-- Pulse the cog chip green-ish for a moment
		local origStroke = cogChip.UIStroke.Color
		cogChip.UIStroke.Color = BrandColors.CopperPatina
		cogChip.UIStroke.Thickness = 3
		task.wait(0.6)
		cogChip.UIStroke.Color = origStroke
		cogChip.UIStroke.Thickness = 1
	end
	if skipped and skipped > 0 then
		-- Toast: sacred critters skipped
		local toast = Instance.new("TextLabel")
		toast.AnchorPoint = Vector2.new(0.5, 0)
		toast.Position = UDim2.new(0.5, 0, 0, 80)
		toast.Size = UDim2.fromOffset(360, 36)
		toast.BackgroundColor3 = BrandColors.OilBlack
		toast.BackgroundTransparency = 0.15
		toast.Text = ("🜏 %d Sacred critters skipped — they cannot be scrapped"):format(skipped)
		toast.TextColor3 = BrandColors.AetherCyan
		toast.TextScaled = true
		toast.Font = Enum.Font.FredokaOne
		toast.Parent = screen
		makeCorner(toast, 10)
		makeStroke(toast, BrandColors.AetherCyan, 2)
		task.delay(2.5, function() if toast.Parent then toast:Destroy() end end)
	end
end)
