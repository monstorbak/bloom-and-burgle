--!strict
-- SeedShopUI: modal that lists all seed species with buy buttons.
-- Triggered by OpenShop RemoteEvent (kiosk touched server-side).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local PlantData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlantData"))

local OpenShopRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("OpenShop") :: RemoteEvent
local BuySeedRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("BuySeed") :: RemoteEvent
local PlantInPlotRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlantInPlot") :: RemoteEvent

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local function fmt(n: number): string
	if n < 1000 then return tostring(n) end
	if n < 1_000_000 then return string.format("%.1fK", n / 1000):gsub("%.0K", "K") end
	return string.format("%.2fM", n / 1_000_000)
end

local screen: ScreenGui? = nil

local function close()
	if screen and screen.Parent then screen:Destroy() end
	screen = nil
end

local function open()
	close()
	screen = Instance.new("ScreenGui")
	screen.Name = "SeedShop"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 50
	screen.Parent = pg

	-- Backdrop dim
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = screen
	backdrop.Activated:Connect(close)

	-- Modal frame
	local modal = Instance.new("Frame")
	modal.Size = UDim2.new(0.85, 0, 0.85, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.BackgroundColor3 = Color3.fromRGB(35, 30, 50)
	modal.BorderSizePixel = 0
	modal.Parent = screen
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0, 18)
	mc.Parent = modal
	local ms = Instance.new("UIStroke")
	ms.Color = Color3.fromRGB(255, 200, 80)
	ms.Thickness = 4
	ms.Parent = modal
	-- Cap modal width on big screens for sane mobile-style portrait flow
	local sz = Instance.new("UISizeConstraint")
	sz.MaxSize = Vector2.new(720, 920)
	sz.MinSize = Vector2.new(280, 380)
	sz.Parent = modal

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 70)
	header.BackgroundColor3 = Color3.fromRGB(60, 40, 90)
	header.BorderSizePixel = 0
	header.Parent = modal
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 18)
	hc.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.fromOffset(20, 0)
	title.BackgroundTransparency = 1
	title.Text = "🌱 SEED SHOP"
	title.TextColor3 = Color3.fromRGB(255, 230, 130)
	title.TextStrokeTransparency = 0.5
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(50, 50)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.TextScaled = true
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = header
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 12)
	cc.Parent = closeBtn
	closeBtn.Activated:Connect(close)

	-- Scrollable content
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -90)
	scroll.Position = UDim2.fromOffset(10, 80)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 200, 80)
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = modal

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scroll

	local function rerender()
		for _, c in scroll:GetChildren() do
			if c:IsA("Frame") then c:Destroy() end
		end
		local lifetime = player:GetAttribute("LifetimeCash") or 0
		local ls = player:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Cash") and (ls.Cash :: IntValue).Value or 0

		for i, species in ipairs(PlantData.list()) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -10, 0, 90)
			row.BackgroundColor3 = Color3.fromRGB(50, 40, 70)
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.Parent = scroll
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0, 12)
			rc.Parent = row
			local rs = Instance.new("UIStroke")
			local rcol = PlantData.rarityColor(species.rarity)
			rs.Color = Color3.new(rcol[1], rcol[2], rcol[3])
			rs.Thickness = 2
			rs.Parent = row

			-- Emoji icon
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.fromOffset(80, 80)
			icon.Position = UDim2.fromOffset(5, 5)
			icon.BackgroundTransparency = 1
			icon.Text = species.emoji
			icon.Font = Enum.Font.FredokaOne
			icon.TextScaled = true
			icon.Parent = row

			-- Name + stats
			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(0.55, -100, 0, 30)
			name.Position = UDim2.fromOffset(90, 8)
			name.BackgroundTransparency = 1
			name.Text = species.displayName .. " · " .. species.rarity
			name.TextColor3 = Color3.new(rcol[1], rcol[2], rcol[3])
			name.Font = Enum.Font.FredokaOne
			name.TextScaled = true
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Parent = row

			local stats = Instance.new("TextLabel")
			stats.Size = UDim2.new(0.55, -100, 0, 26)
			stats.Position = UDim2.fromOffset(90, 38)
			stats.BackgroundTransparency = 1
			stats.Text = string.format("⏱ %ds  💰 $%s/each  ✨ %d%% mut", species.growSeconds, fmt(species.baseValue), math.floor(species.mutationChance * 100))
			stats.TextColor3 = Color3.fromRGB(220, 220, 220)
			stats.Font = Enum.Font.Gotham
			stats.TextScaled = true
			stats.TextXAlignment = Enum.TextXAlignment.Left
			stats.Parent = row

			local stashCount = player:GetAttribute("Stash_" .. species.id) or 0
			local stashLbl = Instance.new("TextLabel")
			stashLbl.Size = UDim2.new(0.55, -100, 0, 22)
			stashLbl.Position = UDim2.fromOffset(90, 64)
			stashLbl.BackgroundTransparency = 1
			stashLbl.Text = "🎒 You own: " .. tostring(stashCount)
			stashLbl.TextColor3 = Color3.fromRGB(255, 230, 130)
			stashLbl.Font = Enum.Font.GothamBold
			stashLbl.TextScaled = true
			stashLbl.TextXAlignment = Enum.TextXAlignment.Left
			stashLbl.Parent = row

			-- Buy button
			local locked = lifetime < species.unlockCash
			local affordable = (not locked) and cash >= species.seedCost
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.fromOffset(110, 70)
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.new(1, -10, 0.5, 0)
			btn.BackgroundColor3 = locked and Color3.fromRGB(70, 70, 70)
				or affordable and Color3.fromRGB(100, 200, 110)
				or Color3.fromRGB(150, 90, 90)
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.Font = Enum.Font.FredokaOne
			btn.TextScaled = true
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = not locked
			btn.Parent = row
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 10)
			bc.Parent = btn
			if locked then
				btn.Text = "🔒\n$" .. fmt(species.unlockCash) .. "\nlifetime"
			else
				btn.Text = "BUY\n$" .. fmt(species.seedCost)
			end
			if not locked then
				btn.Activated:Connect(function()
					BuySeedRE:FireServer(species.id, 1)
					-- Optimistic re-render after a tick
					task.wait(0.2)
					rerender()
				end)
			end
		end
	end

	rerender()

	-- Re-render when cash changes
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Cash") then
		local cash = ls.Cash :: IntValue
		cash:GetPropertyChangedSignal("Value"):Connect(function()
			if screen and screen.Parent then rerender() end
		end)
	end
end

OpenShopRE.OnClientEvent:Connect(open)

-- Esc closes (keyboard)
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Escape and screen then close() end
end)
