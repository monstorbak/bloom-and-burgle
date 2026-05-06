--!strict
-- WelcomeUX: shows a "tap to claim" popup on join, and "sold for $X!" toast
-- when SellPlants RemoteEvent fires.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local PlotClaimedRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlotClaimed") :: RemoteEvent
local SellPlantsRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SellPlants") :: RemoteEvent

-- ── Welcome modal ────────────────────────────────────────────────────
local function showWelcome()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WelcomeScreen"
	screen.ResetOnSpawn = false
	screen.Parent = pg

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(560, 240)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(40, 25, 60)
	frame.BorderSizePixel = 0
	frame.Parent = screen
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 200, 80)
	stroke.Thickness = 4
	stroke.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Text = "🌸 Welcome to Bloom & Burgle! 🌸"
	title.Size = UDim2.new(1, -20, 0, 60)
	title.Position = UDim2.fromOffset(10, 10)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = frame

	local body = Instance.new("TextLabel")
	body.Text = "Walk to a glowing 💜 CLAIM PAD to start your garden.\nFirst seeds are FREE — harvest, then walk on the green pad to SELL.\n\nGood luck out there, farmer!"
	body.Size = UDim2.new(1, -40, 1, -120)
	body.Position = UDim2.fromOffset(20, 70)
	body.BackgroundTransparency = 1
	body.TextColor3 = Color3.fromRGB(240, 240, 240)
	body.Font = Enum.Font.Gotham
	body.TextScaled = true
	body.TextWrapped = true
	body.Parent = frame

	local close = Instance.new("TextButton")
	close.Text = "LET'S GO 🚀"
	close.Size = UDim2.fromOffset(180, 40)
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -10)
	close.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
	close.TextColor3 = Color3.fromRGB(40, 25, 60)
	close.Font = Enum.Font.FredokaOne
	close.TextScaled = true
	close.BorderSizePixel = 0
	close.Parent = frame
	local ccor = Instance.new("UICorner")
	ccor.CornerRadius = UDim.new(0, 12)
	ccor.Parent = close

	close.Activated:Connect(function() screen:Destroy() end)
	-- Auto-dismiss after 12 sec
	task.delay(12, function() if screen and screen.Parent then screen:Destroy() end end)
end

-- ── Sell toast ───────────────────────────────────────────────────────
local function showSoldToast(amount: number)
	local screen = Instance.new("ScreenGui")
	screen.Name = "SoldToast"
	screen.ResetOnSpawn = false
	screen.Parent = pg

	local label = Instance.new("TextLabel")
	label.Text = ("💰 +$%d"):format(amount)
	label.Size = UDim2.fromOffset(360, 100)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.4)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(120, 255, 140)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = screen

	local goal = UDim2.fromScale(0.5, 0.25)
	TweenService:Create(label, TweenInfo.new(1.6, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		Position = goal,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.8, function() screen:Destroy() end)
end

PlotClaimedRE.OnClientEvent:Connect(function()
	-- Could show a "Plot claimed!" toast here later
end)

SellPlantsRE.OnClientEvent:Connect(showSoldToast)

-- Show welcome 1 sec after spawn
task.wait(1)
showWelcome()
