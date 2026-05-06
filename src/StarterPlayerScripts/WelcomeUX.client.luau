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
	frame.Size = UDim2.new(0.7, 0, 0.45, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(40, 25, 60)
	frame.BorderSizePixel = 0
	frame.Parent = screen
	local sz = Instance.new("UISizeConstraint"); sz.MinSize = Vector2.new(300, 280); sz.MaxSize = Vector2.new(720, 460); sz.Parent = frame
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(255, 200, 80); stroke.Thickness = 4; stroke.Parent = frame
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 18); corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 60)
	title.Position = UDim2.fromOffset(10, 14)
	title.BackgroundTransparency = 1
	title.Text = "🌸 Bloom & Burgle 💰"
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.TextStrokeTransparency = 0
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = frame

	local steps = Instance.new("TextLabel")
	steps.Size = UDim2.new(1, -40, 1, -150)
	steps.Position = UDim2.fromOffset(20, 80)
	steps.BackgroundTransparency = 1
	steps.Text = "1️⃣  Walk into a PINK pad → get a free plot\n2️⃣  Wait for your free seeds to grow 🌱\n3️⃣  Walk on the GREEN pad to SELL 💰\n4️⃣  Buy more seeds at the 🛒 SHOP"
	steps.TextColor3 = Color3.fromRGB(245, 245, 245)
	steps.Font = Enum.Font.GothamBold
	steps.TextScaled = true
	steps.TextWrapped = true
	steps.TextXAlignment = Enum.TextXAlignment.Left
	steps.Parent = frame

	local close = Instance.new("TextButton")
	close.Size = UDim2.new(0.7, 0, 0, 60)
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -16)
	close.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
	close.TextColor3 = Color3.fromRGB(40, 25, 60)
	close.Text = "LET'S GO 🚀"
	close.Font = Enum.Font.FredokaOne
	close.TextScaled = true
	close.BorderSizePixel = 0
	close.Parent = frame
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 14); cc.Parent = close

	local function dismiss()
		if screen and screen.Parent then screen:Destroy() end
	end
	close.Activated:Connect(dismiss)
	backdrop.Activated:Connect(dismiss)
	task.delay(8, dismiss)
end

task.wait(0.8)
showWelcome()
