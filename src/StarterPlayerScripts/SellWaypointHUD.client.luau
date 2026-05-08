--!strict
-- SellWaypointHUD: when the player has ripe critters in their pods, show
-- (a) a pulsing 3D arrow above the Pawn Forge sign, and
-- (b) a HUD compass arrow pointing at the pad if the pad is off-screen.
--
-- Why both: the 3D arrow handles the "I'm on the plot but lost" case; the
-- HUD compass handles the "I'm at the Cogworks and need to find my plot"
-- case. Together they make the sell pad impossible to miss.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- ── Find this player's sell pad (Base part — visible one) ──
local function findSellPad(): BasePart?
	for _, sp in CollectionService:GetTagged("SellPad") do
		if sp:IsA("BasePart")
			and sp:GetAttribute("OwnerUserId") == player.UserId
			and sp.Name == "Base" then
			return sp
		end
	end
	return nil
end

local function findSellSign(): BasePart?
	-- Find the Sign part in this player's SellKiosk model
	local pad = findSellPad()
	if not pad then return nil end
	local sellModel = pad.Parent
	if not sellModel then return nil end
	local sign = sellModel:FindFirstChild("Sign")
	if sign and sign:IsA("BasePart") then return sign end
	return nil
end

-- ── Build the 3D arrow attached to the sign ──
-- Uses a BillboardGui with a downward-pointing arrow icon. Pulses when
-- ripe critters are present.
local function ensureArrow(sign: BasePart): BillboardGui?
	local existing = sign:FindFirstChild("RipeArrow")
	if existing and existing:IsA("BillboardGui") then return existing end

	local g = Instance.new("BillboardGui")
	g.Name = "RipeArrow"
	g.Size = UDim2.fromOffset(180, 180)
	g.StudsOffset = Vector3.new(0, 8, 0)
	g.AlwaysOnTop = true
	g.MaxDistance = 250
	g.Enabled = false                            -- starts hidden
	g.Parent = sign

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.BackgroundTransparency = 1
	arrow.Text = "⬇"
	arrow.TextColor3 = BrandColors.GoggleGold
	arrow.TextStrokeTransparency = 0
	arrow.TextStrokeColor3 = BrandColors.OilBlack
	arrow.TextScaled = true
	arrow.Font = Enum.Font.FredokaOne
	arrow.Parent = g

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Size = UDim2.new(1, 0, 0.25, 0)
	count.AnchorPoint = Vector2.new(0.5, 1)
	count.Position = UDim2.new(0.5, 0, 1, 0)
	count.BackgroundTransparency = 1
	count.Text = ""
	count.TextColor3 = BrandColors.SteamCream
	count.TextStrokeTransparency = 0
	count.TextStrokeColor3 = BrandColors.OilBlack
	count.TextScaled = true
	count.Font = Enum.Font.FredokaOne
	count.Parent = g

	return g
end

-- ── HUD compass arrow (off-screen indicator) ──
local screen = Instance.new("ScreenGui")
screen.Name = "SellWaypointScreen"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 60
screen.Parent = pg

local compass = Instance.new("Frame")
compass.Name = "Compass"
compass.AnchorPoint = Vector2.new(0.5, 0.5)
compass.Position = UDim2.fromScale(0.5, 0.5)
compass.Size = UDim2.fromOffset(140, 140)
compass.BackgroundTransparency = 1
compass.Visible = false
compass.Parent = screen

local compassArrow = Instance.new("TextLabel")
compassArrow.Size = UDim2.fromScale(1, 1)
compassArrow.BackgroundTransparency = 1
compassArrow.Text = "➤"
compassArrow.TextColor3 = BrandColors.EmberOrange
compassArrow.TextStrokeTransparency = 0
compassArrow.TextStrokeColor3 = BrandColors.OilBlack
compassArrow.TextScaled = true
compassArrow.Font = Enum.Font.FredokaOne
compassArrow.Rotation = 0
compassArrow.Parent = compass

local compassLabel = Instance.new("TextLabel")
compassLabel.AnchorPoint = Vector2.new(0.5, 0)
compassLabel.Position = UDim2.new(0.5, 0, 1, 4)
compassLabel.Size = UDim2.fromOffset(220, 28)
compassLabel.BackgroundColor3 = BrandColors.OilBlack
compassLabel.BackgroundTransparency = 0.15
compassLabel.Text = "💰 PAWN FORGE"
compassLabel.TextColor3 = BrandColors.GoggleGold
compassLabel.TextStrokeTransparency = 0
compassLabel.TextStrokeColor3 = BrandColors.OilBlack
compassLabel.TextScaled = true
compassLabel.Font = Enum.Font.FredokaOne
compassLabel.Parent = compass
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = compassLabel
local cs = Instance.new("UIStroke"); cs.Color = BrandColors.EmberOrange; cs.Thickness = 2; cs.Parent = compassLabel

-- ── Per-frame compass logic ──
-- When player has ripe critters AND the pad is off-screen, show the compass
-- pointing toward the pad. When the pad enters the screen, hide compass —
-- the 3D arrow on the sign takes over.

local function countRipe(): number
	local n = 0
	for _, planter in CollectionService:GetTagged("Planter") do
		if planter:GetAttribute("OwnerUserId") == player.UserId
			and not planter:GetAttribute("IsEmpty")
			and planter:GetAttribute("Ripe") then
			n += 1
		end
	end
	return n
end

local lastRipe = -1
local pulseT = 0

RunService.RenderStepped:Connect(function(dt)
	pulseT += dt
	local pad = findSellPad()
	if not pad then
		compass.Visible = false
		return
	end
	local sign = findSellSign()
	local arrow = sign and ensureArrow(sign)

	local ripe = countRipe()
	local hasRipe = ripe > 0

	-- 3D arrow above sign — show always when ripe, pulse opacity
	if arrow then
		arrow.Enabled = hasRipe
		if hasRipe then
			local lbl = arrow:FindFirstChild("Arrow") :: TextLabel?
			local cnt = arrow:FindFirstChild("Count") :: TextLabel?
			if lbl then
				lbl.TextTransparency = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(pulseT * 4))
			end
			if cnt then
				cnt.Text = string.format("%d ripe!", ripe)
			end
		end
	end

	-- Compass logic — only when off-screen
	local camera = Workspace.CurrentCamera
	if not camera then compass.Visible = false; return end
	local screenPoint, onScreen = camera:WorldToScreenPoint(pad.Position)
	local viewport = camera.ViewportSize

	-- Off-screen: show compass at edge, rotated to point at the pad.
	if hasRipe and (not onScreen or screenPoint.Z < 0) then
		compass.Visible = true
		-- Compute direction from screen center to projected (clamped) pad
		local cx, cy = viewport.X * 0.5, viewport.Y * 0.5
		local dx = screenPoint.X - cx
		local dy = screenPoint.Y - cy
		-- If pad is BEHIND camera (Z<0), flip direction so arrow points back
		if screenPoint.Z < 0 then dx = -dx; dy = -dy end
		local angle = math.atan2(dy, dx)
		-- Clamp position to a circle near screen center but slightly in
		local radius = math.min(viewport.X, viewport.Y) * 0.32
		local px = cx + math.cos(angle) * radius
		local py = cy + math.sin(angle) * radius
		compass.Position = UDim2.fromOffset(px, py)
		-- Rotate the arrow glyph to match. The ➤ glyph points right at 0deg.
		compassArrow.Rotation = math.deg(angle)
		compassLabel.Text = string.format("💰 %d ripe — %s", ripe, "PAWN FORGE")
	else
		compass.Visible = false
	end
end)
