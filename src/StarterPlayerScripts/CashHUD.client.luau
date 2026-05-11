--!strict
-- CashHUD: top-of-screen cash counter, harvest counter, objective banner,
-- + bottom-row action buttons (return to plot, shop).
-- Mobile-first: large fonts, scaled to viewport, AnchorPoint-friendly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local returnRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ReturnToPlot") :: RemoteEvent
local OpenShopRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("OpenShop") :: RemoteEvent
local SellPlantsRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SellPlants") :: RemoteEvent
local HarvestPopupRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("HarvestPopup") :: RemoteEvent

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local function fmt(n: number): string
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	if n < 1_000_000 then
		local s = string.format("%.1fK", n / 1000)
		return s:gsub("%.0K", "K")
	end
	if n < 1_000_000_000 then
		return string.format("%.2fM", n / 1_000_000)
	end
	return string.format("%.2fB", n / 1_000_000_000)
end

local screen = Instance.new("ScreenGui")
screen.Name = "CashHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 10
screen.Parent = pg

-- BAB-DEV: prominent DEV MODE badge whenever Workspace.DevMode is true
local Workspace = game:GetService("Workspace")
local devBadge = Instance.new("Frame")
devBadge.Name = "DevModeBadge"
devBadge.Size = UDim2.fromOffset(180, 32)
devBadge.AnchorPoint = Vector2.new(0, 0)
devBadge.Position = UDim2.new(0, 16, 0, 16)
devBadge.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
devBadge.BorderSizePixel = 0
devBadge.Visible = false
devBadge.Parent = screen
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = devBadge
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 255, 255); s.Thickness = 2; s.Parent = devBadge
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "⚠ DEV MODE"
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Parent = devBadge
end
local function refreshDevBadge()
	devBadge.Visible = Workspace:GetAttribute("DevMode") == true
end
refreshDevBadge()
Workspace:GetAttributeChangedSignal("DevMode"):Connect(refreshDevBadge)

-- ── Top-right cash chip ──────────────────────────────────────────────
-- BAB-UX (2026-05-08): shrunk from 240×70 (max 360×90) to 200×56 (max 280×72).
-- The previous size dominated the top-right quadrant and crowded the seed-bag
-- list below it. The chip now reads as a corner status, not a billboard.
local cashFrame = Instance.new("Frame")
cashFrame.Size = UDim2.new(0, 200, 0, 56)
cashFrame.AnchorPoint = Vector2.new(1, 0)
cashFrame.Position = UDim2.new(1, -16, 0, 16)
cashFrame.BackgroundColor3 = Color3.fromRGB(35, 25, 55)
cashFrame.BackgroundTransparency = 0.1
cashFrame.BorderSizePixel = 0
cashFrame.Parent = screen
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = cashFrame
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 200, 80); s.Thickness = 2; s.Parent = cashFrame
	local sz = Instance.new("UISizeConstraint"); sz.MinSize = Vector2.new(160, 48); sz.MaxSize = Vector2.new(280, 72); sz.Parent = cashFrame
end

local cashLabel = Instance.new("TextLabel")
cashLabel.Size = UDim2.new(1, -16, 1, -10)
cashLabel.Position = UDim2.fromOffset(8, 5)
cashLabel.BackgroundTransparency = 1
cashLabel.Text = "💰 $0"
cashLabel.TextColor3 = Color3.fromRGB(255, 230, 130)
cashLabel.TextStrokeTransparency = 0.3
cashLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
cashLabel.Font = Enum.Font.FredokaOne
cashLabel.TextScaled = true
cashLabel.Parent = cashFrame
-- Cap the cash text at 28pt so "$8.5K" doesn't fill the chip top-to-bottom.
do
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 28; tx.Parent = cashLabel
end

-- ── Seed inventory chip (under cash) ──────────────────────────────────
local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
-- BAB-DESIGN-CRITIQUE Tier 1 (2026-05-10): brand-coherent button styling.
local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))

-- BAB-UX (2026-05-08): seed bag tracks the smaller cash chip — y-offset
-- 95 → 80 (cash chip is now 56px tall + 16px top gutter + 8px gap = 80).
-- Width 240 → 200 to match the cash chip footprint.
local seedFrame = Instance.new("Frame")
seedFrame.Name = "SeedInventory"
seedFrame.Size = UDim2.new(0, 200, 0, 0)  -- height auto via UIListLayout
seedFrame.AutomaticSize = Enum.AutomaticSize.Y
seedFrame.AnchorPoint = Vector2.new(1, 0)
seedFrame.Position = UDim2.new(1, -16, 0, 80)
seedFrame.BackgroundColor3 = Color3.fromRGB(35, 25, 55)
seedFrame.BackgroundTransparency = 0.1
seedFrame.BorderSizePixel = 0
seedFrame.Visible = false  -- hidden when empty
seedFrame.Parent = screen
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = seedFrame
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(120, 220, 120); s.Thickness = 2; s.Parent = seedFrame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8); padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10); padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = seedFrame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = seedFrame
end

local seedTitle = Instance.new("TextLabel")
seedTitle.Name = "Title"
seedTitle.Size = UDim2.new(1, 0, 0, 20)
seedTitle.LayoutOrder = 0
seedTitle.BackgroundTransparency = 1
seedTitle.Text = "🌱 SEED BAG"
seedTitle.TextColor3 = Color3.fromRGB(180, 255, 180)
seedTitle.Font = Enum.Font.FredokaOne
seedTitle.TextScaled = true
seedTitle.TextXAlignment = Enum.TextXAlignment.Left
seedTitle.Parent = seedFrame

local function refreshSeeds()
	for _, c in seedFrame:GetChildren() do
		if c:IsA("TextLabel") and c.Name ~= "Title" then c:Destroy() end
	end
	local totalSeeds = 0
	local i = 0
	for _, species in CritterData.list() do
		local count = player:GetAttribute("Stash_" .. species.id) or 0
		if count > 0 then
			i += 1
			totalSeeds += count
			local lbl = Instance.new("TextLabel")
			lbl.Name = "Seed_" .. species.id
			lbl.Size = UDim2.new(1, 0, 0, 22)
			lbl.LayoutOrder = i
			lbl.BackgroundTransparency = 1
			lbl.Text = string.format("%s %s × %d", species.emoji, species.displayName, count)
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.Font = Enum.Font.GothamBold
			lbl.TextScaled = true
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Parent = seedFrame
		end
	end
	seedFrame.Visible = totalSeeds > 0
end

refreshSeeds()
player.AttributeChanged:Connect(function(name)
	if name:sub(1, 6) == "Stash_" then refreshSeeds() end
end)

-- BAB-011: Harvest popup — a floating "+1 🌻 Sunbloom" world‐label that floats up.
HarvestPopupRE.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	local pos = data.position
	if typeof(pos) ~= "Vector3" then return end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = pos
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(180, 50)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.Parent = anchor

	local mutation = data.mutation and data.mutation ~= "" and data.mutation or nil
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.format("+1 %s %s%s",
		tostring(data.emoji or "✨"),
		tostring(data.name or "crop"),
		mutation and (" ✨ " .. mutation:upper()) or "")
	label.TextColor3 = mutation and Color3.fromRGB(255, 220, 80) or Color3.fromRGB(180, 255, 180)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = bb

	task.spawn(function()
		local start = anchor.Position
		for i = 0, 1, 0.04 do
			if not anchor.Parent then return end
			anchor.Position = start + Vector3.new(0, i * 4, 0)
			label.TextTransparency = i
			label.TextStrokeTransparency = i
			task.wait(0.04)
		end
		anchor:Destroy()
	end)
end)

-- ── Top-center objective banner ──────────────────────────────────────
-- BAB-UX (2026-05-08): toned down + shrunk.
--   - Width 0.55 → 0.40 of screen so it stops crowding the world signage
--     behind it (PAWN FORGE, etc.).
--   - Bright-green stroke → Brass; thinner. Per Spec §3.4 the modal is the
--     visual peak, not the tutorial banner.
--   - Text capped at 18pt so long copy ("Buy eggs at the EGG EMPORIUM…")
--     wraps to 2 lines instead of ballooning to fill the banner.
--   - Auto-hides when the player is within 14 studs of any tagged kiosk
--     (the kiosk's own ProximityPrompt takes over).
local hintFrame = Instance.new("Frame")
hintFrame.Name = "ObjectiveHint"
hintFrame.Size = UDim2.new(0.40, 0, 0, 52)
hintFrame.AnchorPoint = Vector2.new(0.5, 0)
hintFrame.Position = UDim2.new(0.5, 0, 0, 12)
hintFrame.BackgroundColor3 = Color3.fromRGB(25, 20, 45)
hintFrame.BackgroundTransparency = 0.25
hintFrame.BorderSizePixel = 0
hintFrame.Parent = screen
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = hintFrame
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(200, 146, 63); s.Thickness = 1; s.Parent = hintFrame
	local sz = Instance.new("UISizeConstraint"); sz.MinSize = Vector2.new(260, 44); sz.MaxSize = Vector2.new(480, 60); sz.Parent = hintFrame
end

local hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.new(1, -20, 1, -8)
hintLabel.Position = UDim2.fromOffset(10, 4)
hintLabel.BackgroundTransparency = 1
hintLabel.Text = "🌸 Walk into a glowing GOLD pad to claim your plot"
hintLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
hintLabel.TextStrokeTransparency = 0.5
hintLabel.Font = Enum.Font.GothamBold
hintLabel.TextScaled = true
hintLabel.TextWrapped = true
hintLabel.Parent = hintFrame
do
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 18; tx.Parent = hintLabel
end

-- ── Bottom-row nav buttons ───────────────────────────────────────────
-- BAB-DESIGN-CRITIQUE Tier 1 (2026-05-10): rebranded from generic
-- pink/green Roblox-template buttons to brass-bordered OilBlack panels
-- aligned to the steampunk identity. Same functional wiring; only the
-- visual treatment changed.

-- Shared button builder. Returns the TextButton — caller wires .Activated.
-- Using a local builder instead of dragging in a new UIComponents module
-- because this is the only place these 2 buttons exist and we want the
-- diff small. Promote to a module in Tier 2 (UIComponents.luau).
local function buildNavButton(opts: {
	name: string,
	text: string,
	anchor: Vector2,
	position: UDim2,
}): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = opts.name
	btn.Size = UDim2.new(0, 220, 0, 70)
	btn.AnchorPoint = opts.anchor
	btn.Position = opts.position
	btn.BackgroundColor3 = BrandColors.OilBlack
	btn.BackgroundTransparency = 0.05
	btn.TextColor3 = BrandColors.SteamCream
	btn.Text = opts.text
	btn.Font = Enum.Font.FredokaOne
	btn.TextScaled = true
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Parent = screen
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = btn
	-- Brass stroke = the brand-coherent visual signal "this is interactive".
	local s = Instance.new("UIStroke"); s.Color = BrandColors.Brass; s.Thickness = 2; s.Parent = btn
	local sz = Instance.new("UISizeConstraint"); sz.MinSize = Vector2.new(160, 56); sz.MaxSize = Vector2.new(260, 78); sz.Parent = btn
	-- Hold the text smaller than the box so we get true button-y padding.
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 22; tx.Parent = btn
	-- 6px interior padding (matches Friends panel toggle button).
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = btn
	return btn
end

-- "MY WORKSHOP" reads better than "PLOT" in the steampunk-Ghibli register —
-- a workshop is what tinkerers tend to. Same destination (your plot).
local returnBtn = buildNavButton({
	name = "ReturnToPlotBtn",
	text = "🔧 MY WORKSHOP",
	anchor = Vector2.new(0, 1),
	position = UDim2.new(0, 16, 1, -16),
})
returnBtn.Visible = false   -- shown only when player has wandered off-plot
returnBtn.Activated:Connect(function() returnRE:FireServer() end)

-- "🌱 SEED SHOP" is what the panel itself is titled (SeedShopUI.client.luau),
-- so keeping that name avoids a mismatch with the opened panel.
local shopBtn = buildNavButton({
	name = "ShopBtn",
	text = "🌱 SEED SHOP",
	anchor = Vector2.new(1, 1),
	position = UDim2.new(1, -16, 1, -16),
})
shopBtn.Activated:Connect(function() OpenShopRE:FireServer() end)

-- ── Wire to leaderstats Cash ──────────────────────────────────────────
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	if not ls then return end
	local cash = ls:WaitForChild("Cash", 10) :: IntValue?
	if not cash then return end
	local function update()
		cashLabel.Text = "💰 $" .. fmt(cash.Value)
	end
	update()
	cash:GetPropertyChangedSignal("Value"):Connect(update)
end)

-- ── Update objective hint based on player state ───────────────────────
-- BAB-UX (2026-05-08): smarter content + auto-hide near kiosks.
--   1. If stash already has seeds, "press E on a pod" — don't tell the
--      player to buy seeds they already own.
--   2. When player is within 14 studs of a tagged kiosk (Planter, SellPad,
--      ScrapPad, ClaimPad), the kiosk's own ProximityPrompt is doing the
--      job. Hide the banner so the world signage isn't competing.
local KIOSK_TAGS = { "Planter", "SellPad", "ScrapPad", "ClaimPad" }
local KIOSK_HIDE_RADIUS = 14

local function hasSeeds(): boolean
	for _, attr in player:GetAttributes() do end  -- noop, attribute changed signal handles refresh
	for k, v in player:GetAttributes() do
		if typeof(k) == "string" and k:sub(1, 6) == "Stash_" and typeof(v) == "number" and v > 0 then
			return true
		end
	end
	return false
end

local function nearKiosk(): boolean
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return false end
	local pos = hrp.Position
	for _, tag in KIOSK_TAGS do
		for _, kiosk in CollectionService:GetTagged(tag) do
			if kiosk:IsA("BasePart") then
				if (kiosk.Position - pos).Magnitude <= KIOSK_HIDE_RADIUS then
					return true
				end
			end
		end
	end
	return false
end

task.spawn(function()
	while true do
		-- Hide near kiosks; the kiosk's own UI takes over.
		if nearKiosk() then
			hintFrame.Visible = false
			task.wait(0.5)
			continue
		end

		local claimed = player:GetAttribute("PlotClaimed")
		-- Count current ripe + growing plants on player's plot
		local growing, ripe = 0, 0
		for _, planter in CollectionService:GetTagged("Planter") do
			if planter:GetAttribute("OwnerUserId") == player.UserId
				and not planter:GetAttribute("IsEmpty") then
				growing += 1
				local at = planter:GetAttribute("PlantedAt") or 0
				local g = planter:GetAttribute("GrowSeconds") or 60
				if os.time() - at >= g then ripe += 1 end
			end
		end

		if not claimed then
			hintLabel.Text = "⚙ Touch a glowing GOLD pad to claim your Hatchery"
		elseif ripe > 0 then
			hintLabel.Text = string.format("💰 %d ripe — walk on the PAWN FORGE to sell!", ripe)
		elseif growing == 0 then
			-- Smarter: if stash has seeds, the player just needs to plant them.
			if hasSeeds() then
				hintLabel.Text = "🥚 You have seeds — press E on a pod to plant"
			else
				hintLabel.Text = "🥚 Buy seeds at the EGG EMPORIUM"
			end
		else
			hintLabel.Text = string.format("🥚 %d incubating… come back soon", growing)
		end
		hintFrame.Visible = true
		task.wait(1.5)
	end
end)

-- ── Show/hide bottom buttons based on plot status ─────────────────────
task.spawn(function()
	while true do
		returnBtn.Visible = player:GetAttribute("PlotClaimed") == true
		task.wait(0.5)
	end
end)

-- ── Hide leftover claim pads after we've claimed ──────────────────────
task.spawn(function()
	while not player:GetAttribute("PlotClaimed") do
		task.wait(0.5)
		if not player.Parent then return end
	end
	local function hide(pad: Instance)
		if pad:IsA("BasePart") then
			pad.LocalTransparencyModifier = 1
			for _, child in pad:GetDescendants() do
				if child:IsA("BillboardGui") then child.Enabled = false end
			end
		end
	end
	for _, pad in CollectionService:GetTagged("ClaimPad") do hide(pad) end
	CollectionService:GetInstanceAddedSignal("ClaimPad"):Connect(hide)
end)

-- ── Sell toast ────────────────────────────────────────────────────────
SellPlantsRE.OnClientEvent:Connect(function(amount)
	local toast = Instance.new("ScreenGui")
	toast.ResetOnSpawn = false
	toast.IgnoreGuiInset = true
	toast.Parent = pg
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.5, 0, 0, 90)
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.Position = UDim2.fromScale(0.5, 0.5)
	lbl.BackgroundTransparency = 1
	lbl.Text = string.format("💰 +$%s", fmt(amount))
	lbl.TextColor3 = Color3.fromRGB(120, 255, 140)
	lbl.TextStrokeTransparency = 0
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Parent = toast
	local sz = Instance.new("UISizeConstraint"); sz.MaxSize = Vector2.new(700, 140); sz.Parent = lbl
	TweenService:Create(lbl, TweenInfo.new(2.0, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.25),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(2.2, function() if toast and toast.Parent then toast:Destroy() end end)
end)
