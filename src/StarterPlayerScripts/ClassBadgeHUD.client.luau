--!strict
-- ClassBadgeHUD: persistent identity HUD per Bloom&Burgle_Design_Spec.md §3.1.
-- Top-left corner of the screen, never moves. Shows:
--   - Class crest + name (e.g. "🛡 KNIGHT")
--   - Cog Parts secondary currency chip
--   - Stable count chip (e.g. "🐾 4 / 6")
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

-- Outer column container, top-left corner with safe-area padding
local column = Instance.new("Frame")
column.Name = "Column"
column.AnchorPoint = Vector2.new(0, 0)
column.Position = UDim2.fromOffset(12, 80)            -- below Roblox top bar
column.Size = UDim2.fromOffset(180, 130)
column.BackgroundTransparency = 1
column.Parent = screen
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = column

-- ── Class badge ───────────────────────────────────────────────
local classBadge = Instance.new("Frame")
classBadge.Name = "ClassBadge"
classBadge.LayoutOrder = 1
classBadge.Size = UDim2.fromOffset(180, 44)
classBadge.BackgroundColor3 = BrandColors.OilBlack
classBadge.BackgroundTransparency = 0.1
classBadge.BorderSizePixel = 0
classBadge.Parent = column
makeCorner(classBadge, 12)
makeStroke(classBadge, BrandColors.Brass, 2)

local crestLbl = Instance.new("TextLabel")
crestLbl.Name = "Crest"
crestLbl.AnchorPoint = Vector2.new(0, 0.5)
crestLbl.Position = UDim2.new(0, 8, 0.5, 0)
crestLbl.Size = UDim2.fromOffset(34, 34)
crestLbl.BackgroundTransparency = 1
crestLbl.Text = "?"
crestLbl.TextColor3 = BrandColors.GoggleGold
crestLbl.TextScaled = true
crestLbl.Font = Enum.Font.FredokaOne
crestLbl.Parent = classBadge

local nameLbl = Instance.new("TextLabel")
nameLbl.Name = "ClassName"
nameLbl.AnchorPoint = Vector2.new(0, 0.5)
nameLbl.Position = UDim2.new(0, 50, 0.5, 0)
nameLbl.Size = UDim2.new(1, -58, 0, 22)
nameLbl.BackgroundTransparency = 1
nameLbl.Text = "PICK CLASS"
nameLbl.TextColor3 = BrandColors.SteamCream
nameLbl.TextScaled = true
nameLbl.TextXAlignment = Enum.TextXAlignment.Left
nameLbl.Font = Enum.Font.FredokaOne
nameLbl.Parent = classBadge

-- ── Cog Parts chip ────────────────────────────────────────────
local cogChip = Instance.new("Frame")
cogChip.Name = "CogChip"
cogChip.LayoutOrder = 2
cogChip.Size = UDim2.fromOffset(180, 36)
cogChip.BackgroundColor3 = BrandColors.OilBlack
cogChip.BackgroundTransparency = 0.15
cogChip.BorderSizePixel = 0
cogChip.Parent = column
makeCorner(cogChip, 10)
makeStroke(cogChip, BrandColors.IronworkCharcoal, 1)

local cogIcon = Instance.new("TextLabel")
cogIcon.AnchorPoint = Vector2.new(0, 0.5)
cogIcon.Position = UDim2.new(0, 8, 0.5, 0)
cogIcon.Size = UDim2.fromOffset(24, 24)
cogIcon.BackgroundTransparency = 1
cogIcon.Text = "⚙"
cogIcon.TextColor3 = BrandColors.GoggleGold
cogIcon.TextScaled = true
cogIcon.Font = Enum.Font.FredokaOne
cogIcon.Parent = cogChip

local cogLbl = Instance.new("TextLabel")
cogLbl.Name = "CogValue"
cogLbl.AnchorPoint = Vector2.new(0, 0.5)
cogLbl.Position = UDim2.new(0, 36, 0.5, 0)
cogLbl.Size = UDim2.new(1, -42, 0, 20)
cogLbl.BackgroundTransparency = 1
cogLbl.Text = "0 cog parts"
cogLbl.TextColor3 = BrandColors.SteamCream
cogLbl.TextScaled = true
cogLbl.TextXAlignment = Enum.TextXAlignment.Left
cogLbl.Font = Enum.Font.GothamBold
cogLbl.Parent = cogChip

-- ── Stable chip ──────────────────────────────────────────────
local stableChip = Instance.new("Frame")
stableChip.Name = "StableChip"
stableChip.LayoutOrder = 3
stableChip.Size = UDim2.fromOffset(180, 32)
stableChip.BackgroundColor3 = BrandColors.OilBlack
stableChip.BackgroundTransparency = 0.2
stableChip.BorderSizePixel = 0
stableChip.Parent = column
makeCorner(stableChip, 10)
makeStroke(stableChip, BrandColors.IronworkCharcoal, 1)

local stableIcon = Instance.new("TextLabel")
stableIcon.AnchorPoint = Vector2.new(0, 0.5)
stableIcon.Position = UDim2.new(0, 8, 0.5, 0)
stableIcon.Size = UDim2.fromOffset(22, 22)
stableIcon.BackgroundTransparency = 1
stableIcon.Text = "🐾"
stableIcon.TextScaled = true
stableIcon.Font = Enum.Font.FredokaOne
stableIcon.Parent = stableChip

local stableLbl = Instance.new("TextLabel")
stableLbl.Name = "StableValue"
stableLbl.AnchorPoint = Vector2.new(0, 0.5)
stableLbl.Position = UDim2.new(0, 36, 0.5, 0)
stableLbl.Size = UDim2.new(1, -42, 0, 18)
stableLbl.BackgroundTransparency = 1
stableLbl.Text = "Stable 0 / 6"
stableLbl.TextColor3 = BrandColors.SteamCream
stableLbl.TextScaled = true
stableLbl.TextXAlignment = Enum.TextXAlignment.Left
stableLbl.Font = Enum.Font.GothamBold
stableLbl.Parent = stableChip

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
	cogLbl.Text = string.format("%d cog parts", v)
end

local function refreshStable()
	local size = player:GetAttribute("StableSize") or 0
	local cap = player:GetAttribute("StableCapacity") or 6
	stableLbl.Text = string.format("Stable %d / %d", size, cap)
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
