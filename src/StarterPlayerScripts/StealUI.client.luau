--!strict
-- StealUI: ProximityPrompts on RIPE planters belonging to OTHER players.
-- Trigger fires StealAttempt to server. Also toasts inbound StealNotifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local StealAttemptRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("StealAttempt") :: RemoteEvent
local StealNotificationRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("StealNotification") :: RemoteEvent

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local function attachStealPrompt(planter: Instance)
	if not planter:IsA("BasePart") then return end
	if planter:FindFirstChild("StealPrompt") then return end
	task.spawn(function()
		local tries = 0
		while planter:GetAttribute("OwnerUserId") == nil and tries < 30 do
			task.wait(0.2); tries += 1
		end
		local ownerId = planter:GetAttribute("OwnerUserId")
		if not ownerId or ownerId == player.UserId then return end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "STEAL 💰"
		prompt.ObjectText = "Neighbor's Plant"
		prompt.HoldDuration = 1.5  -- hold to steal — feels heisty
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Parent = planter

		-- Only enabled when the plant is fully grown
		local function refresh()
			if planter:GetAttribute("IsEmpty") then prompt.Enabled = false; return end
			local plantedAt = planter:GetAttribute("PlantedAt") or 0
			local growSeconds = planter:GetAttribute("GrowSeconds") or 60
			prompt.Enabled = (os.time() - plantedAt) >= growSeconds
		end
		refresh()
		task.spawn(function()
			while planter.Parent do
				task.wait(2)
				refresh()
			end
		end)
		planter:GetAttributeChangedSignal("IsEmpty"):Connect(refresh)

		prompt.Triggered:Connect(function(triggerer)
			if triggerer ~= player then return end
			StealAttemptRE:FireServer(planter)
		end)
	end)
end

for _, p in CollectionService:GetTagged("Planter") do attachStealPrompt(p) end
CollectionService:GetInstanceAddedSignal("Planter"):Connect(attachStealPrompt)

-- Toast notifications (used by both steals and shield blocks)
local function showToast(text: string)
	local screen = Instance.new("ScreenGui")
	screen.Name = "StealToast"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = pg

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.7, 0, 0, 70)
	lbl.AnchorPoint = Vector2.new(0.5, 0)
	lbl.Position = UDim2.fromScale(0.5, 0.18)
	lbl.BackgroundColor3 = Color3.fromRGB(40, 30, 50)
	lbl.BackgroundTransparency = 0.1
	lbl.TextColor3 = Color3.fromRGB(255, 230, 130)
	lbl.TextStrokeTransparency = 0
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = text
	lbl.BorderSizePixel = 0
	lbl.Parent = screen
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = lbl
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(255, 200, 80)
	s.Thickness = 3
	s.Parent = lbl
	local sz = Instance.new("UISizeConstraint")
	sz.MaxSize = Vector2.new(640, 90)
	sz.MinSize = Vector2.new(220, 50)
	sz.Parent = lbl

	TweenService:Create(lbl, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.5, 0.08),
		TextTransparency = 1,
		BackgroundTransparency = 1,
	}):Play()
	task.delay(2.6, function() if screen and screen.Parent then screen:Destroy() end end)
end

StealNotificationRE.OnClientEvent:Connect(showToast)
