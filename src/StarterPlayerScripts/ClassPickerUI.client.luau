--!strict
-- ClassPickerUI: full-screen modal that opens on first join when the player
-- has no Class attribute set. Five class cards in a horizontal carousel; each
-- shows crest, name, tagline, combat stats, and signature ability. Tap →
-- confirm → fire PickClass RE → modal closes.
--
-- Per Bloom&Burgle_Design_Spec.md §2.7 + §12 (10–25s onboarding window).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local ClassData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClassData"))
local PickClassRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PickClass") :: RemoteEvent

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- ── UI builders ─────────────────────────────────────────────────────
local function makeStroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function makeCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function buildClassCard(parent: Instance, classSpec: any, onPick: () -> ())
	local card = Instance.new("TextButton")
	card.Name = classSpec.id
	card.Size = UDim2.new(0, 220, 1, -20)
	card.BackgroundColor3 = BrandColors.OilBlack
	card.AutoButtonColor = false
	card.BorderSizePixel = 0
	card.Text = ""
	card.Parent = parent
	makeCorner(card, 14)
	makeStroke(card, BrandColors.classAccent(classSpec.displayName), 3)

	-- Top: crest panel (large brass-rimmed crest emoji)
	local crestPanel = Instance.new("Frame")
	crestPanel.Size = UDim2.new(1, -16, 0, 110)
	crestPanel.Position = UDim2.fromOffset(8, 8)
	crestPanel.BackgroundColor3 = BrandColors.IronworkCharcoal
	crestPanel.BorderSizePixel = 0
	crestPanel.Parent = card
	makeCorner(crestPanel, 10)
	makeStroke(crestPanel, BrandColors.Brass, 1)

	local crest = Instance.new("TextLabel")
	crest.Size = UDim2.fromScale(1, 1)
	crest.BackgroundTransparency = 1
	crest.Text = classSpec.crest
	crest.TextColor3 = BrandColors.classAccent(classSpec.displayName)
	crest.TextScaled = true
	crest.Font = Enum.Font.FredokaOne
	crest.Parent = crestPanel

	-- Class name
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -16, 0, 32)
	name.Position = UDim2.new(0, 8, 0, 124)
	name.BackgroundTransparency = 1
	name.Text = classSpec.displayName
	name.TextColor3 = BrandColors.SteamCream
	name.TextScaled = true
	name.Font = Enum.Font.FredokaOne
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.Parent = card

	-- Tagline
	local tagline = Instance.new("TextLabel")
	tagline.Size = UDim2.new(1, -16, 0, 60)
	tagline.Position = UDim2.new(0, 8, 0, 160)
	tagline.BackgroundTransparency = 1
	tagline.Text = classSpec.tagline
	tagline.TextColor3 = BrandColors.lerpToBlack(BrandColors.SteamCream, 0.15)
	tagline.TextScaled = true
	tagline.TextWrapped = true
	tagline.Font = Enum.Font.GothamMedium
	tagline.TextYAlignment = Enum.TextYAlignment.Top
	tagline.Parent = card

	-- Combat stats row
	local statsRow = Instance.new("Frame")
	statsRow.Size = UDim2.new(1, -16, 0, 28)
	statsRow.Position = UDim2.new(0, 8, 0, 226)
	statsRow.BackgroundTransparency = 1
	statsRow.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = statsRow

	for _, statPair in {
		{ "❤", classSpec.combat.hp },
		{ "⚔", classSpec.combat.damage },
		{ "👟", classSpec.combat.speed },
	} do
		local s = Instance.new("TextLabel")
		s.Size = UDim2.fromScale(0.32, 1)
		s.BackgroundTransparency = 1
		s.Text = string.format("%s %d", statPair[1], statPair[2])
		s.TextColor3 = BrandColors.GoggleGold
		s.TextScaled = true
		s.Font = Enum.Font.FredokaOne
		s.Parent = statsRow
	end

	-- Signature label
	local sig = Instance.new("TextLabel")
	sig.Size = UDim2.new(1, -16, 0, 22)
	sig.Position = UDim2.new(0, 8, 0, 256)
	sig.BackgroundTransparency = 1
	sig.Text = "✦ " .. classSpec.signature.displayName
	sig.TextColor3 = BrandColors.AetherCyan
	sig.TextScaled = true
	sig.Font = Enum.Font.FredokaOne
	sig.Parent = card

	local sigDesc = Instance.new("TextLabel")
	sigDesc.Size = UDim2.new(1, -16, 0, 36)
	sigDesc.Position = UDim2.new(0, 8, 0, 280)
	sigDesc.BackgroundTransparency = 1
	sigDesc.Text = classSpec.signature.description
	sigDesc.TextColor3 = BrandColors.lerpToBlack(BrandColors.SteamCream, 0.2)
	sigDesc.TextScaled = true
	sigDesc.TextWrapped = true
	sigDesc.Font = Enum.Font.GothamBold
	sigDesc.TextYAlignment = Enum.TextYAlignment.Top
	sigDesc.Parent = card

	-- Pick button (bottom)
	local pickBtn = Instance.new("TextButton")
	pickBtn.Size = UDim2.new(1, -16, 0, 40)
	pickBtn.AnchorPoint = Vector2.new(0, 1)
	pickBtn.Position = UDim2.new(0, 8, 1, -8)
	pickBtn.BackgroundColor3 = BrandColors.classAccent(classSpec.displayName)
	pickBtn.Text = "PICK " .. string.upper(classSpec.displayName)
	pickBtn.TextColor3 = BrandColors.OilBlack
	pickBtn.TextScaled = true
	pickBtn.Font = Enum.Font.FredokaOne
	pickBtn.AutoButtonColor = true
	pickBtn.Parent = card
	makeCorner(pickBtn, 8)

	pickBtn.Activated:Connect(onPick)

	-- Hover effect — subtle scale-up via tween
	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15), { Size = UDim2.new(0, 234, 1, -8) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.15), { Size = UDim2.new(0, 220, 1, -20) }):Play()
	end)

	return card
end

local function showPicker()
	if pg:FindFirstChild("ClassPickerScreen") then return end

	local screen = Instance.new("ScreenGui")
	screen.Name = "ClassPickerScreen"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 200
	screen.Parent = pg

	-- Backdrop with warm tilt (forge-feel)
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = BrandColors.OilBlack
	backdrop.BackgroundTransparency = 0.05
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen
	local backGradient = Instance.new("UIGradient")
	backGradient.Color = ColorSequence.new(BrandColors.OilBlack, BrandColors.lerpToBlack(BrandColors.EmberOrange, 0.25))
	backGradient.Rotation = 90
	backGradient.Parent = backdrop

	-- Title strip
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 0, 60)
	title.Position = UDim2.new(0, 20, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "⚙ CHOOSE YOUR CLASS"
	title.TextColor3 = BrandColors.GoggleGold
	title.TextStrokeTransparency = 0
	title.TextStrokeColor3 = BrandColors.OilBlack
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.Parent = screen

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -40, 0, 28)
	sub.Position = UDim2.new(0, 20, 0, 90)
	sub.BackgroundTransparency = 1
	sub.Text = "Your class shapes which critters help you and which try to eat you."
	sub.TextColor3 = BrandColors.SteamCream
	sub.TextScaled = true
	sub.Font = Enum.Font.GothamMedium
	sub.Parent = screen

	-- Card carousel
	local carousel = Instance.new("Frame")
	carousel.AnchorPoint = Vector2.new(0.5, 0.5)
	carousel.Position = UDim2.fromScale(0.5, 0.55)
	carousel.Size = UDim2.new(1, -40, 0, 380)
	carousel.BackgroundTransparency = 1
	carousel.Parent = screen
	local sz = Instance.new("UISizeConstraint")
	sz.MaxSize = Vector2.new(1200, 420)
	sz.Parent = carousel

	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.new(1, 0, 1, 0)
	row.BackgroundTransparency = 1
	row.Parent = carousel
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 12)
	rowLayout.Parent = row

	local function dismiss()
		if screen and screen.Parent then
			TweenService:Create(backdrop, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			if screen and screen.Parent then screen:Destroy() end
		end
	end

	for _, spec in ClassData.list() do
		buildClassCard(row, spec, function()
			-- Optimistic UX: dismiss immediately, server validation will reject
			-- if the player already has a class (no-op).
			PickClassRE:FireServer(spec.id)
			dismiss()
		end)
	end

	-- Footer hint
	local footer = Instance.new("TextLabel")
	footer.Size = UDim2.new(1, -40, 0, 28)
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -24)
	footer.BackgroundTransparency = 1
	footer.Text = "💡 Tip: every class is viable. There are no wrong picks — just different stories."
	footer.TextColor3 = BrandColors.lerpToBlack(BrandColors.SteamCream, 0.2)
	footer.TextScaled = true
	footer.Font = Enum.Font.GothamMedium
	footer.Parent = screen
end

-- Trigger: open the picker if the player has no class set after a short
-- settle delay. Re-check on attribute change in case server load is slow.
local function checkAndShow()
	if not player:GetAttribute("Class") then
		showPicker()
	end
end

task.wait(2.5)  -- let WelcomeUX show first
checkAndShow()
player:GetAttributeChangedSignal("Class"):Connect(function()
	-- If somehow class becomes nil mid-session (admin reset), re-prompt.
	if not player:GetAttribute("Class") then
		showPicker()
	end
end)
