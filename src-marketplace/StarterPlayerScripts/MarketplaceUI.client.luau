--!strict
-- MarketplaceUI — client-side UI for the marketplace place.
--
-- BAB-MARKETPLACE-HUB scaffolding (2026-05-08). Built using Fusion (the
-- precedent from PR #7 / P1.3). v1 ships:
--   1. Welcome toast on join ("you're at the marketplace; merchants pay
--      better, return portal is south")
--   2. Brass Bart sell modal (triggered by the merchant's quote event)
--
-- Defer for follow-on PRs: full merchant-personality dialogue, P2P
-- trade UI for booth interactions, asset/liability arbitrage hint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Fusion"))

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local OnEvent = Fusion.OnEvent
local Children = Fusion.Children

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local MarketplaceSellRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("MarketplaceSell") :: RemoteEvent

local function fmt(n: number): string
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	if n < 1_000_000 then
		local s = string.format("%.1fK", n / 1000)
		return (s:gsub("%.0K", "K"))
	end
	return string.format("%.2fM", n / 1_000_000)
end

-- ── Welcome toast ────────────────────────────────────────────────────
local function showWelcome()
	local toast = Instance.new("ScreenGui")
	toast.Name = "MarketplaceWelcome"
	toast.ResetOnSpawn = false
	toast.IgnoreGuiInset = true
	toast.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.05)
	panel.Size = UDim2.fromOffset(440, 70)
	panel.BackgroundColor3 = Color3.fromRGB(40, 36, 32)
	panel.BorderSizePixel = 0
	panel.Parent = toast
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(200, 146, 63); s.Thickness = 2; s.Parent = panel

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, -10)
	lbl.Position = UDim2.fromOffset(8, 5)
	lbl.BackgroundTransparency = 1
	lbl.Text = "💰 Welcome to the Marketplace — merchants pay better than your Pawn Forge"
	lbl.TextColor3 = Color3.fromRGB(245, 240, 230)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextWrapped = true
	lbl.Parent = panel
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 18; tx.Parent = lbl

	-- Slide in, hold 4s, fade out.
	panel.Position = UDim2.fromScale(0.5, -0.1)
	TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.05),
	}):Play()
	task.delay(4.5, function()
		if not toast or not toast.Parent then return end
		TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, -0.1),
		}):Play()
		task.wait(0.6)
		if toast.Parent then toast:Destroy() end
	end)
end

task.delay(1.0, showWelcome)  -- give the player a moment to spawn first

-- ── Brass Bart sell modal ────────────────────────────────────────────
-- Reactive cells driven by MarketplaceSellRE quotes.
local quoteVisible = Value(false)
local quoteData: any = Value(nil)

local quoteText = Computed(function()
	local d = quoteData:get()
	if not d then return "" end
	return string.format("Brass Bart offers %s gold for your %d critter%s.",
		"$" .. fmt(d.quotedPayout),
		d.count or 0,
		((d.count or 0) == 1) and "" or "s")
end, { quoteData })

local mutationHint = Computed(function()
	local d = quoteData:get()
	if not d or not d.mutations or d.mutations == 0 then return "" end
	return string.format("✨ %d mutated critter%s included.",
		d.mutations,
		(d.mutations == 1) and "" or "s")
end, { quoteData })

local function closeQuote()
	quoteVisible:set(false)
	quoteData:set(nil)
end

local function confirm()
	MarketplaceSellRE:FireServer("confirm_brass_bart")
	closeQuote()
end

-- Build modal (reactive, mounted once)
local quoteModal = New "ScreenGui" {
	Name = "BrassBartQuote",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = quoteVisible,
	[Children] = {
		New "Frame" {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			[Children] = {
				New "TextButton" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "",
					[OnEvent("Activated")] = closeQuote,
				},
			},
		},
		New "Frame" {
			Name = "Panel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(440, 280),
			BackgroundColor3 = Color3.fromRGB(40, 36, 32),
			BorderSizePixel = 0,
			[Children] = {
				New "UICorner" { CornerRadius = UDim.new(0, 12) },
				New "UIStroke" { Color = Color3.fromRGB(200, 146, 63), Thickness = 2 },

				New "TextLabel" {
					Name = "Title",
					Size = UDim2.new(1, -32, 0, 50),
					Position = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Text = "⚙ BRASS BART",
					TextColor3 = Color3.fromRGB(232, 197, 71),
					Font = Enum.Font.FredokaOne,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				New "TextLabel" {
					Name = "Body",
					Size = UDim2.new(1, -32, 0, 70),
					Position = UDim2.fromOffset(16, 80),
					BackgroundTransparency = 1,
					Text = quoteText,
					TextColor3 = Color3.fromRGB(245, 240, 230),
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
				},
				New "TextLabel" {
					Name = "Mutation",
					Size = UDim2.new(1, -32, 0, 24),
					Position = UDim2.fromOffset(16, 156),
					BackgroundTransparency = 1,
					Text = mutationHint,
					TextColor3 = Color3.fromRGB(120, 220, 255),
					Font = Enum.Font.Gotham,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},

				-- Confirm button
				New "TextButton" {
					Name = "Confirm",
					Size = UDim2.fromOffset(180, 56),
					Position = UDim2.new(0.5, -190, 1, -76),
					BackgroundColor3 = Color3.fromRGB(200, 146, 63),
					Text = "💰 SELL",
					TextColor3 = Color3.new(0, 0, 0),
					Font = Enum.Font.FredokaOne,
					TextScaled = true,
					BorderSizePixel = 0,
					[Children] = { New "UICorner" { CornerRadius = UDim.new(0, 8) } },
					[OnEvent("Activated")] = confirm,
				},
				-- Decline
				New "TextButton" {
					Name = "Decline",
					Size = UDim2.fromOffset(180, 56),
					Position = UDim2.new(0.5, 10, 1, -76),
					BackgroundColor3 = Color3.fromRGB(60, 50, 50),
					Text = "Maybe later",
					TextColor3 = Color3.fromRGB(220, 220, 220),
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					BorderSizePixel = 0,
					[Children] = { New "UICorner" { CornerRadius = UDim.new(0, 8) } },
					[OnEvent("Activated")] = closeQuote,
				},
			},
		},
	},
}
quoteModal.Parent = playerGui

-- ── Wire RemoteEvent → modal state ───────────────────────────────────
MarketplaceSellRE.OnClientEvent:Connect(function(action, data)
	if action == "quote" then
		if typeof(data) ~= "table" then return end
		if (data.quotedPayout or 0) <= 0 then
			-- Player has nothing to sell; brief toast instead of the full modal.
			showWelcome()  -- repurpose the welcome toast UI, but with different text
			return
		end
		quoteData:set(data)
		quoteVisible:set(true)
	elseif action == "result" then
		-- Quick confirmation flash
		local toast = Instance.new("ScreenGui")
		toast.ResetOnSpawn = false
		toast.IgnoreGuiInset = true
		toast.Parent = playerGui
		local lbl = Instance.new("TextLabel")
		lbl.AnchorPoint = Vector2.new(0.5, 0.5)
		lbl.Position = UDim2.fromScale(0.5, 0.5)
		lbl.Size = UDim2.fromOffset(420, 90)
		lbl.BackgroundTransparency = 1
		lbl.Text = string.format("💰 +$%s from Brass Bart!", fmt(data.payout or 0))
		lbl.TextColor3 = Color3.fromRGB(232, 197, 71)
		lbl.TextStrokeTransparency = 0
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.Parent = toast
		TweenService:Create(lbl, TweenInfo.new(2.0, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.25),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.delay(2.2, function() if toast.Parent then toast:Destroy() end end)
	end
end)

print("[BAB-LIFE] MarketplaceUI online")
