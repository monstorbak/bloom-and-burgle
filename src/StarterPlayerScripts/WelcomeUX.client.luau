--!strict
-- WelcomeUX: short, punchy welcome modal on join. Auto-dismiss + tap-to-skip.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local function showWelcome()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WelcomeScreen"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 100
	screen.Parent = pg

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = screen

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0.7, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(26, 20, 16)         -- OilBlack
	frame.BorderSizePixel = 0
	frame.Parent = screen
	local sz = Instance.new("UISizeConstraint"); sz.MinSize = Vector2.new(320, 320); sz.MaxSize = Vector2.new(760, 540); sz.Parent = frame
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(232, 197, 71); stroke.Thickness = 4; stroke.Parent = frame  -- GoggleGold
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 14); corner.Parent = frame
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(46, 42, 42), Color3.fromRGB(26, 20, 16))
	grad.Rotation = 90
	grad.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 60)
	title.Position = UDim2.fromOffset(10, 14)
	title.BackgroundTransparency = 1
	title.Text = "⚙ BLOOM & BURGLE ⚙"
	title.TextColor3 = Color3.fromRGB(232, 197, 71)
	title.TextStrokeTransparency = 0
	title.TextStrokeColor3 = Color3.fromRGB(26, 20, 16)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = frame

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -20, 0, 22)
	sub.Position = UDim2.fromOffset(10, 78)
	sub.BackgroundTransparency = 1
	sub.Text = "Hatch cute critters. Decide their fate. Build your menagerie."
	sub.TextColor3 = Color3.fromRGB(242, 228, 201)
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.Parent = frame

	local steps = Instance.new("TextLabel")
	steps.Size = UDim2.new(1, -40, 1, -210)
	steps.Position = UDim2.fromOffset(20, 112)
	steps.BackgroundTransparency = 1
	steps.Text = table.concat({
		"1️⃣  Pick your CLASS — knight, alchemist, sky pirate, tinkerer, or hexer",
		"2️⃣  Walk into a GOLD pad → claim your Hatchery",
		"3️⃣  Eggs incubate in your pods 🥚 — first one's free",
		"4️⃣  When ready: SELL for gold 💰, SCRAP for Cog Parts ⚙, or NURTURE 🐾",
		"5️⃣  Asset critters protect you. Liabilities may attack. Choose wisely.",
	}, "\n")
	steps.TextColor3 = Color3.fromRGB(242, 228, 201)
	steps.Font = Enum.Font.GothamBold
	steps.TextScaled = true
	steps.TextWrapped = true
	steps.TextXAlignment = Enum.TextXAlignment.Left
	steps.TextYAlignment = Enum.TextYAlignment.Top
	steps.Parent = frame

	local close = Instance.new("TextButton")
	close.Size = UDim2.new(0.7, 0, 0, 60)
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -16)
	close.BackgroundColor3 = Color3.fromRGB(232, 197, 71)
	close.TextColor3 = Color3.fromRGB(26, 20, 16)
	close.Text = "ENTER THE COGWORKS"
	close.Font = Enum.Font.FredokaOne
	close.TextScaled = true
	close.BorderSizePixel = 0
	close.Parent = frame
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 12); cc.Parent = close

	local function dismiss()
		if screen and screen.Parent then screen:Destroy() end
	end
	close.Activated:Connect(dismiss)
	backdrop.Activated:Connect(dismiss)
	task.delay(8, dismiss)
end

task.wait(0.8)
showWelcome()
