--!strict
-- MarketplaceUI — client-side UI for the marketplace place.
--
-- Phase 3 rich UI (BAB-MARKETPLACE-NPC-ROTATION extension, 2026-05-08):
--   - Per-species rows in a scrolling list (one entry per stash key) so the
--     player sees WHICH species earned what multiplier.
--   - Asset/liability badges per row (the moat made legible).
--   - Multiplier breakdown line under each row (1.2× × 1.0× × (1+0.2+1.0)).
--   - Today's-special row gets a gold highlight.
--   - Skipped (Contraband) rows shown greyed out at the bottom.
--   - Fusion drives the modal visibility + reactive title/dialogue/totals;
--     row Frames are imperatively rebuilt on each quote (simpler than
--     dynamic Children reactivity).

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

-- ── Brand palette (mirror of BrandColors.luau) ───────────────────────
-- Client-side mirror; the server doesn't ship the BrandColors module to
-- StarterPlayerScripts. These RGBs match BrandColors exactly per
-- Bloom&Burgle_Design_Spec.md §1.2.
local C = {
	Brass            = Color3.fromRGB(200, 146, 63),
	CopperPatina     = Color3.fromRGB(79,  168, 143),
	OilBlack         = Color3.fromRGB(26,  20,  16),
	EmberOrange      = Color3.fromRGB(255, 106, 31),
	SteamCream       = Color3.fromRGB(242, 228, 201),
	IronworkCharcoal = Color3.fromRGB(46,  42,  42),
	AetherCyan       = Color3.fromRGB(79,  227, 255),
	ValveRed         = Color3.fromRGB(193, 60,  42),
	GoggleGold       = Color3.fromRGB(232, 197, 71),
	WitchVellum      = Color3.fromRGB(88,  50,  110),
	SkyCaptainNavy   = Color3.fromRGB(40,  80,  110),
	PanelBg          = Color3.fromRGB(40,  36,  32),
	RowBg            = Color3.fromRGB(54,  48,  42),
	RowBgSpecial     = Color3.fromRGB(78,  62,  32),
	RowBgSkipped     = Color3.fromRGB(38,  32,  30),
	BodyText         = Color3.fromRGB(245, 240, 230),
	SubText          = Color3.fromRGB(180, 175, 165),
	DimText          = Color3.fromRGB(120, 115, 110),
}

-- ── Helpers ──────────────────────────────────────────────────────────

local function fmt(n: number): string
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	if n < 1_000_000 then
		local s = string.format("%.1fK", n / 1000)
		return (s:gsub("%.0K", "K"))
	end
	return string.format("%.2fM", n / 1_000_000)
end

local function fmtMult(m: number): string
	if math.abs(m - math.floor(m)) < 0.05 then
		return string.format("%d×", math.floor(m + 0.5))
	end
	return string.format("%.1f×", m)
end

local function affinityBadge(affinity: string?): (string, Color3)
	if affinity == "asset"     then return "⚒ ASSET",     C.GoggleGold end
	if affinity == "liability" then return "⚠ LIABILITY", C.EmberOrange end
	return "", C.SubText
end

-- Pretty-print the multiplier breakdown for a line. Example:
--   "1.2× × 1.0× × (1 + 0.2 + 1.0) = 2.64×"
local function breakdownText(line: any): string
	local base = string.format("%.1f×", line.basePremium or 1)
	local pref = string.format("%.1f×", line.preferenceFit or 1)
	local arb = string.format("%.1f", line.arbitrageBonus or 0)
	local spec = string.format("%.1f", line.specialBonus or 0)
	local raw = string.format("%.2f×", line.rawMultiplier or 1)
	if line.wasCapped then
		return string.format("%s × %s × (1 + %s + %s) = %s → %s (capped)",
			base, pref, arb, spec, raw, fmtMult(line.multiplier))
	end
	return string.format("%s × %s × (1 + %s + %s) = %s",
		base, pref, arb, spec, fmtMult(line.multiplier))
end

-- ── Welcome toast (unchanged from v2) ────────────────────────────────
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
	panel.BackgroundColor3 = C.PanelBg
	panel.BorderSizePixel = 0
	panel.Parent = toast
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = C.Brass; s.Thickness = 2; s.Parent = panel

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, -10)
	lbl.Position = UDim2.fromOffset(8, 5)
	lbl.BackgroundTransparency = 1
	lbl.Text = "💰 Welcome to the Marketplace — three merchants, three different prices"
	lbl.TextColor3 = C.BodyText
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextWrapped = true
	lbl.Parent = panel
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 18; tx.Parent = lbl

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

task.delay(1.0, showWelcome)

-- ── State ────────────────────────────────────────────────────────────
local quoteVisible = Value(false)
local quoteData: any = Value(nil)

local titleText = Computed(function()
	local d = quoteData:get()
	if not d then return "" end
	return string.format("%s %s", d.emoji or "•", string.upper(d.displayName or "Merchant"))
end, { quoteData })

local dialogueText = Computed(function()
	local d = quoteData:get()
	if not d then return "" end
	return d.dialogueLine or ""
end, { quoteData })

local headerText = Computed(function()
	local d = quoteData:get()
	if not d then return "" end
	local pieces = {}
	table.insert(pieces, string.format("Total: $%s", fmt(d.quotedPayout or 0)))
	table.insert(pieces, string.format("(avg %s)", fmtMult(d.avgMultiplier or 1)))
	if (d.mutations or 0) > 0 then
		table.insert(pieces, string.format("✨ %d mutated", d.mutations))
	end
	return table.concat(pieces, "  ·  ")
end, { quoteData })

local specialBannerText = Computed(function()
	local d = quoteData:get()
	if not d or not d.todaysSpecialName then return "" end
	return string.format("🌟 Today's special: %s — bonus 2× when sold.", d.todaysSpecialName)
end, { quoteData })

local function closeQuote()
	quoteVisible:set(false)
	quoteData:set(nil)
end

local function confirm()
	local d = quoteData:get()
	if not d then return end
	MarketplaceSellRE:FireServer("confirm", d.npcId)
	closeQuote()
end

-- ── Per-row rendering (imperative — Fusion doesn't fit a dynamic list well) ──
-- Build one row for a priced QuoteLine.
local function buildRow(line: any, isSpecial: boolean): Frame
	local row = Instance.new("Frame")
	row.Name = "Row_" .. line.key
	row.Size = UDim2.new(1, -16, 0, 64)
	row.BackgroundColor3 = isSpecial and C.RowBgSpecial or C.RowBg
	row.BorderSizePixel = 0
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row
	if isSpecial then
		local s = Instance.new("UIStroke"); s.Color = C.GoggleGold; s.Thickness = 1.5; s.Parent = row
	end

	-- LEFT: emoji + species name + count + mutation badge
	local left = Instance.new("TextLabel")
	left.Name = "Left"
	left.Size = UDim2.new(0.55, 0, 0.55, 0)
	left.Position = UDim2.fromOffset(10, 6)
	left.BackgroundTransparency = 1
	left.TextXAlignment = Enum.TextXAlignment.Left
	local mutPart = ""
	if line.mutationName then
		mutPart = string.format(" %s %s", line.mutationEmoji or "✨", line.mutationName)
	end
	left.Text = string.format("%s %s%s × %d",
		line.speciesEmoji or "•", line.speciesName, mutPart, line.count)
	left.TextColor3 = C.BodyText
	left.Font = Enum.Font.GothamBold
	left.TextScaled = true
	left.Parent = row

	-- MIDDLE: badges
	local badges = Instance.new("TextLabel")
	badges.Name = "Badges"
	badges.Size = UDim2.new(0.25, 0, 0.55, 0)
	badges.Position = UDim2.new(0.55, 8, 0, 6)
	badges.BackgroundTransparency = 1
	badges.TextXAlignment = Enum.TextXAlignment.Left
	local badgeText, badgeColor = affinityBadge(line.affinity)
	badges.Text = badgeText
	badges.TextColor3 = badgeColor
	badges.Font = Enum.Font.GothamBold
	badges.TextScaled = true
	badges.Parent = row

	-- RIGHT: subtotal
	local right = Instance.new("TextLabel")
	right.Name = "Right"
	right.Size = UDim2.new(0.20, -10, 0.55, 0)
	right.Position = UDim2.new(0.80, 0, 0, 6)
	right.BackgroundTransparency = 1
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.Text = "$" .. fmt(line.lineSubtotal)
	right.TextColor3 = isSpecial and C.GoggleGold or C.BodyText
	right.Font = Enum.Font.FredokaOne
	right.TextScaled = true
	right.Parent = row

	-- BOTTOM: breakdown text in lighter color
	local breakdown = Instance.new("TextLabel")
	breakdown.Name = "Breakdown"
	breakdown.Size = UDim2.new(1, -20, 0.40, -2)
	breakdown.Position = UDim2.new(0, 10, 0.55, 4)
	breakdown.BackgroundTransparency = 1
	breakdown.TextXAlignment = Enum.TextXAlignment.Left
	breakdown.Text = breakdownText(line)
	breakdown.TextColor3 = C.SubText
	breakdown.Font = Enum.Font.Code
	breakdown.TextScaled = true
	breakdown.Parent = row

	return row
end

-- Build one row for a skipped QuoteLine (Contraband).
local function buildSkippedRow(line: any): Frame
	local row = Instance.new("Frame")
	row.Name = "Skipped_" .. line.key
	row.Size = UDim2.new(1, -16, 0, 40)
	row.BackgroundColor3 = C.RowBgSkipped
	row.BorderSizePixel = 0
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, -8)
	lbl.Position = UDim2.fromOffset(8, 4)
	lbl.BackgroundTransparency = 1
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = string.format("%s %s × %d   ⚠ contraband (scrap instead)",
		line.speciesEmoji or "•", line.speciesName, line.count)
	lbl.TextColor3 = C.DimText
	lbl.Font = Enum.Font.GothamItalic
	lbl.TextScaled = true
	lbl.Parent = row

	return row
end

-- ── Build modal shell ────────────────────────────────────────────────
local rowsContainer  -- forward ref to the ScrollingFrame so onClientEvent can repopulate

local quoteModal = New "ScreenGui" {
	Name = "MerchantQuote",
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
			Size = UDim2.fromOffset(560, 600),
			BackgroundColor3 = C.PanelBg,
			BorderSizePixel = 0,
			[Children] = {
				New "UICorner" { CornerRadius = UDim.new(0, 12) },
				New "UIStroke" { Color = C.Brass, Thickness = 2 },

				New "TextLabel" {
					Name = "Title",
					Size = UDim2.new(1, -32, 0, 44),
					Position = UDim2.fromOffset(16, 14),
					BackgroundTransparency = 1,
					Text = titleText,
					TextColor3 = C.GoggleGold,
					Font = Enum.Font.FredokaOne,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				New "TextLabel" {
					Name = "Dialogue",
					Size = UDim2.new(1, -32, 0, 32),
					Position = UDim2.fromOffset(16, 60),
					BackgroundTransparency = 1,
					Text = dialogueText,
					TextColor3 = C.SubText,
					Font = Enum.Font.GothamItalic,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
				},
				New "TextLabel" {
					Name = "SpecialBanner",
					Size = UDim2.new(1, -32, 0, 24),
					Position = UDim2.fromOffset(16, 96),
					BackgroundTransparency = 1,
					Text = specialBannerText,
					TextColor3 = C.GoggleGold,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				New "TextLabel" {
					Name = "Header",
					Size = UDim2.new(1, -32, 0, 28),
					Position = UDim2.fromOffset(16, 124),
					BackgroundTransparency = 1,
					Text = headerText,
					TextColor3 = C.BodyText,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				New "ScrollingFrame" {
					Name = "Rows",
					Size = UDim2.new(1, -32, 0, 360),
					Position = UDim2.fromOffset(16, 158),
					BackgroundColor3 = C.IronworkCharcoal,
					BorderSizePixel = 0,
					ScrollBarThickness = 6,
					ScrollBarImageColor3 = C.Brass,
					CanvasSize = UDim2.new(0, 0, 0, 0),  -- updated by UIListLayout
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					[Children] = {
						New "UICorner" { CornerRadius = UDim.new(0, 6) },
						New "UIListLayout" {
							Padding = UDim.new(0, 6),
							SortOrder = Enum.SortOrder.LayoutOrder,
						},
						New "UIPadding" {
							PaddingTop = UDim.new(0, 8),
							PaddingBottom = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						},
					},
				},

				-- Confirm button
				New "TextButton" {
					Name = "Confirm",
					Size = UDim2.fromOffset(240, 56),
					Position = UDim2.new(0.5, -250, 1, -76),
					BackgroundColor3 = C.Brass,
					Text = "💰 SELL ALL",
					TextColor3 = C.OilBlack,
					Font = Enum.Font.FredokaOne,
					TextScaled = true,
					BorderSizePixel = 0,
					[Children] = { New "UICorner" { CornerRadius = UDim.new(0, 8) } },
					[OnEvent("Activated")] = confirm,
				},
				-- Decline
				New "TextButton" {
					Name = "Decline",
					Size = UDim2.fromOffset(240, 56),
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
rowsContainer = quoteModal:FindFirstChild("Panel"):FindFirstChild("Rows") :: ScrollingFrame

-- Repopulate the row container when a new quote arrives.
local function populateRows(data: any)
	-- Clear existing rows (preserve UIListLayout + UIPadding).
	for _, child in rowsContainer:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end

	local layoutOrder = 0
	-- Priced lines (sorted server-side by subtotal desc).
	for _, line in ipairs(data.lines or {}) do
		layoutOrder += 1
		local row = buildRow(line, line.wasSpecial == true)
		row.LayoutOrder = layoutOrder
		row.Parent = rowsContainer
	end

	-- Skipped lines after a divider header.
	if data.skippedLines and #data.skippedLines > 0 then
		layoutOrder += 1
		local divider = Instance.new("TextLabel")
		divider.Name = "_Divider"
		divider.Size = UDim2.new(1, -16, 0, 24)
		divider.BackgroundTransparency = 1
		divider.Text = "── Won't buy ──"
		divider.TextColor3 = C.DimText
		divider.Font = Enum.Font.GothamItalic
		divider.TextScaled = true
		divider.LayoutOrder = layoutOrder
		divider.Parent = rowsContainer

		for _, line in ipairs(data.skippedLines) do
			layoutOrder += 1
			local row = buildSkippedRow(line)
			row.LayoutOrder = layoutOrder
			row.Parent = rowsContainer
		end
	end
end

-- ── Wire RemoteEvent → modal state ───────────────────────────────────
MarketplaceSellRE.OnClientEvent:Connect(function(action, data)
	if action == "quote" then
		if typeof(data) ~= "table" then return end
		local hasContent = (data.quotedPayout or 0) > 0
			or (data.skippedCount or 0) > 0
			or (#(data.lines or {}) > 0)
			or (#(data.skippedLines or {}) > 0)
		if not hasContent then
			showWelcome()
			return
		end
		quoteData:set(data)
		populateRows(data)
		quoteVisible:set(true)
	elseif action == "result" then
		local toast = Instance.new("ScreenGui")
		toast.ResetOnSpawn = false
		toast.IgnoreGuiInset = true
		toast.Parent = playerGui
		local lbl = Instance.new("TextLabel")
		lbl.AnchorPoint = Vector2.new(0.5, 0.5)
		lbl.Position = UDim2.fromScale(0.5, 0.5)
		lbl.Size = UDim2.fromOffset(460, 90)
		lbl.BackgroundTransparency = 1
		lbl.Text = string.format("💰 +$%s from %s!", fmt(data.payout or 0), data.displayName or "the merchant")
		lbl.TextColor3 = C.GoggleGold
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

print("[BAB-LIFE] MarketplaceUI online (Phase 3 rich-UI client)")
