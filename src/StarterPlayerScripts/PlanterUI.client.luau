--!strict
-- PlanterUI: client adds ProximityPrompts to each empty planter on the player's plot.
-- Activating the prompt opens a quick-pick of stashed seeds. Mobile-friendly hold-to-plant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PlantData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlantData"))

local PlantInPlotRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlantInPlot") :: RemoteEvent

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local function fmt(n: number): string
	if n < 1000 then return tostring(n) end
	if n < 1_000_000 then return string.format("%.1fK", n / 1000):gsub("%.0K", "K") end
	return string.format("%.2fM", n / 1_000_000)
end

local activePicker: ScreenGui? = nil

local function closePicker()
	if activePicker and activePicker.Parent then activePicker:Destroy() end
	activePicker = nil
end

local function showPicker(planter: BasePart)
	closePicker()
	-- Build the list of seeds the player has in stash, plus a "buy more" hint
	local stashItems: { { id: string, count: number } } = {}
	for _, species in ipairs(PlantData.list()) do
		local count = player:GetAttribute("Stash_" .. species.id) or 0
		if count > 0 then
			table.insert(stashItems, { id = species.id, count = count })
		end
	end

	local picker = Instance.new("ScreenGui")
	picker.Name = "PlanterPicker"
	picker.ResetOnSpawn = false
	picker.IgnoreGuiInset = true
	picker.DisplayOrder = 60
	picker.Parent = pg
	activePicker = picker

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = activePicker
	backdrop.Activated:Connect(closePicker)

	local modal = Instance.new("Frame")
	modal.Size = UDim2.new(0.7, 0, 0.5, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.BackgroundColor3 = Color3.fromRGB(40, 30, 60)
	modal.BorderSizePixel = 0
	modal.Parent = activePicker
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0, 16)
	mc.Parent = modal
	local ms = Instance.new("UIStroke")
	ms.Color = Color3.fromRGB(120, 255, 140)
	ms.Thickness = 4
	ms.Parent = modal
	local sz = Instance.new("UISizeConstraint")
	sz.MaxSize = Vector2.new(640, 540)
	sz.MinSize = Vector2.new(280, 320)
	sz.Parent = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 50)
	title.Position = UDim2.fromOffset(10, 10)
	title.BackgroundTransparency = 1
	title.Text = "🌱 Plant which seed?"
	title.TextColor3 = Color3.fromRGB(255, 230, 130)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = modal

	if #stashItems == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -40, 1, -100)
		empty.Position = UDim2.fromOffset(20, 70)
		empty.BackgroundTransparency = 1
		empty.Text = "🛒 No seeds in your bag.\n\nVisit the green 🌱 SEED SHOP near spawn to buy some!"
		empty.TextColor3 = Color3.fromRGB(220, 220, 220)
		empty.Font = Enum.Font.GothamBold
		empty.TextScaled = true
		empty.TextWrapped = true
		empty.Parent = modal
		return
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -70)
	scroll.Position = UDim2.fromOffset(10, 60)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.Parent = modal
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	for i, entry in ipairs(stashItems) do
		local species = PlantData.get(entry.id)
		if not species then continue end
		local rcol = PlantData.rarityColor(species.rarity)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -10, 0, 70)
		btn.LayoutOrder = i
		btn.BackgroundColor3 = Color3.fromRGB(60, 50, 90)
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = true
		btn.Parent = scroll
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 10)
		bc.Parent = btn
		local bs = Instance.new("UIStroke")
		bs.Color = Color3.new(rcol[1], rcol[2], rcol[3])
		bs.Thickness = 2
		bs.Parent = btn

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -20, 1, 0)
		lbl.Position = UDim2.fromOffset(10, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = string.format("%s  %s · x%d  ⏱%ds  💰$%s", species.emoji, species.displayName, entry.count, species.growSeconds, fmt(species.baseValue))
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = btn

		btn.Activated:Connect(function()
			PlantInPlotRE:FireServer(planter, species.id)
			closePicker()
		end)
	end
end

-- BAB-011: Server creates the ProximityPrompt (more reliable than client-side).
-- This client just hooks Triggered on the prompt and shows the seed picker.
local function hookPlanter(planter: Instance)
	if not planter:IsA("BasePart") then return end
	if planter:GetAttribute("OwnerUserId") ~= player.UserId then
		-- Wait briefly in case owner attr is being set
		task.spawn(function()
			for _ = 1, 30 do
				task.wait(0.2)
				if planter:GetAttribute("OwnerUserId") == player.UserId then
					hookPlanter(planter)
					return
				end
			end
		end)
		return
	end

	local function tryHookPrompt()
		local prompt = planter:FindFirstChild("PlantPrompt") :: ProximityPrompt?
		if not prompt then return false end
		if prompt:GetAttribute("_Hooked") then return true end
		prompt:SetAttribute("_Hooked", true)

		local function refreshVis()
			prompt.Enabled = planter:GetAttribute("IsEmpty") == true
		end
		refreshVis()
		planter:GetAttributeChangedSignal("IsEmpty"):Connect(refreshVis)
		prompt.Triggered:Connect(function(triggerer)
			if triggerer ~= player then return end
			showPicker(planter)
		end)
		return true
	end

	if tryHookPrompt() then return end
	-- Wait for server-side prompt to replicate in
	task.spawn(function()
		for _ = 1, 30 do
			task.wait(0.2)
			if tryHookPrompt() then return end
		end
	end)
end

for _, p in CollectionService:GetTagged("Planter") do hookPlanter(p) end
CollectionService:GetInstanceAddedSignal("Planter"):Connect(hookPlanter)
