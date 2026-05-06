--!strict
-- PlotManager: spawns claim pads, hands out plots when players touch them,
-- and builds a procedural starter plot (grass tiles, planter spots, sell pad).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local NUM_PLOT_SLOTS = 16                    -- max concurrent player plots
local PLOT_SPACING = 80                      -- studs between plot centers
local PLOT_RING_RADIUS = 220                 -- distance from town square
local CLAIM_PAD_COLOR = Color3.fromRGB(180, 100, 255)  -- purple-pink claim pad
local PLOT_BASE_COLOR = Color3.fromRGB(50, 30, 60)
local SELL_PAD_COLOR = Color3.fromRGB(60, 230, 120)
local PLANTER_COLOR = Color3.fromRGB(80, 50, 40)

-- ── Plot slot tracking ──────────────────────────────────────────────
local slots: { [number]: { player: Player?, claimPad: Part?, plot: Model? } } = {}
for i = 1, NUM_PLOT_SLOTS do
	slots[i] = { player = nil, claimPad = nil, plot = nil }
end

-- Compute world position of a plot slot in a ring around the town square (origin)
local function slotPosition(i: number): Vector3
	local theta = (i - 1) * (2 * math.pi / NUM_PLOT_SLOTS)
	return Vector3.new(math.cos(theta) * PLOT_RING_RADIUS, 0, math.sin(theta) * PLOT_RING_RADIUS)
end

-- Build a procedural starter plot at `origin` for `player`.
-- Layout: 40x40 base, 3x3 grid of planters (squared off), one sell pad on the edge.
local function buildPlot(player: Player, origin: Vector3): Model
	local plot = Instance.new("Model")
	plot.Name = ("Plot_%s"):format(player.Name)

	-- Base
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(40, 1, 40)
	base.Position = origin + Vector3.new(0, 0.5, 0)
	base.Anchored = true
	base.Material = Enum.Material.Slate
	base.Color = PLOT_BASE_COLOR
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = plot

	-- Owner billboard
	local sign = Instance.new("Part")
	sign.Name = "OwnerSign"
	sign.Size = Vector3.new(8, 6, 1)
	sign.Position = origin + Vector3.new(0, 5, -19)
	sign.Anchored = true
	sign.Material = Enum.Material.Neon
	sign.Color = Color3.fromRGB(255, 200, 80)
	sign.Parent = plot

	local sgui = Instance.new("SurfaceGui")
	sgui.Face = Enum.NormalId.Front
	sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sgui.PixelsPerStud = 50
	sgui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = ("%s's Garden"):format(player.DisplayName)
	label.TextColor3 = Color3.fromRGB(40, 20, 20)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = sgui

	-- Planters (3x3 grid)
	for x = -1, 1 do
		for z = -1, 1 do
			local planter = Instance.new("Part")
			planter.Name = ("Planter_%d_%d"):format(x + 2, z + 2)
			planter.Size = Vector3.new(6, 1.5, 6)
			planter.Position = origin + Vector3.new(x * 8, 1.5, z * 8)
			planter.Anchored = true
			planter.Material = Enum.Material.Wood
			planter.Color = PLANTER_COLOR
			planter.TopSurface = Enum.SurfaceType.Smooth
			planter.BottomSurface = Enum.SurfaceType.Smooth
			planter.Parent = plot
			-- Tag for PlantHandler to enumerate
			planter:AddTag("Planter")
			planter:SetAttribute("OwnerUserId", player.UserId)
			planter:SetAttribute("IsEmpty", true)
		end
	end

	-- Sell pad (lime green, far edge)
	local sellPad = Instance.new("Part")
	sellPad.Name = "SellPad"
	sellPad.Size = Vector3.new(8, 1, 8)
	sellPad.Position = origin + Vector3.new(15, 1.5, 15)
	sellPad.Anchored = true
	sellPad.Material = Enum.Material.Neon
	sellPad.Color = SELL_PAD_COLOR
	sellPad.TopSurface = Enum.SurfaceType.Smooth
	sellPad.Parent = plot
	sellPad:AddTag("SellPad")
	sellPad:SetAttribute("OwnerUserId", player.UserId)

	local sellGui = Instance.new("BillboardGui")
	sellGui.Size = UDim2.fromOffset(180, 50)
	sellGui.StudsOffset = Vector3.new(0, 4, 0)
	sellGui.AlwaysOnTop = true
	sellGui.Parent = sellPad
	local sellText = Instance.new("TextLabel")
	sellText.Size = UDim2.fromScale(1, 1)
	sellText.BackgroundTransparency = 1
	sellText.Text = "💰 SELL 💰"
	sellText.TextColor3 = Color3.fromRGB(255, 255, 255)
	sellText.TextStrokeTransparency = 0
	sellText.TextScaled = true
	sellText.Font = Enum.Font.FredokaOne
	sellText.Parent = sellGui

	plot.Parent = Workspace
	return plot
end

-- Spawn a claim pad at slot `i`. Touching it claims the slot for the player.
local function makeClaimPad(i: number): Part
	local pos = slotPosition(i)
	local pad = Instance.new("Part")
	pad.Name = ("ClaimPad_%d"):format(i)
	pad.Size = Vector3.new(10, 1, 10)
	pad.Position = pos + Vector3.new(0, 1, 0)
	pad.Anchored = true
	pad.Material = Enum.Material.Neon
	pad.Color = CLAIM_PAD_COLOR
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Parent = Workspace
	pad:AddTag("ClaimPad")
	pad:SetAttribute("SlotIndex", i)

	-- Floating "TOUCH TO CLAIM" billboard
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = pad
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Text = "✨ TOUCH TO CLAIM ✨"
	txt.TextColor3 = Color3.fromRGB(255, 255, 255)
	txt.TextStrokeTransparency = 0
	txt.TextScaled = true
	txt.Font = Enum.Font.FredokaOne
	txt.Parent = gui

	-- Soft pulsing glow via attribute (StarterPlayerScripts can read & animate)
	pad:SetAttribute("Pulse", true)

	return pad
end

-- Wire all initial claim pads
for i = 1, NUM_PLOT_SLOTS do
	local pad = makeClaimPad(i)
	slots[i].claimPad = pad

	pad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		-- Already has a plot? Bail.
		if player:GetAttribute("PlotClaimed") then return end

		-- Slot already taken?
		if slots[i].player then return end

		-- Claim it
		slots[i].player = player
		player:SetAttribute("PlotClaimed", true)
		player:SetAttribute("PlotSlotIndex", i)
		pad:Destroy()
		slots[i].claimPad = nil

		local plot = buildPlot(player, slotPosition(i))
		slots[i].plot = plot

		-- Teleport player onto their plot for the wow moment
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			(hrp :: BasePart).CFrame = CFrame.new(slotPosition(i) + Vector3.new(0, 5, 0))
		end

		-- Notify client (used by StarterGui to show "Plot claimed!" toast)
		local re = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents"):FindFirstChild("PlotClaimed")
		if re and re:IsA("RemoteEvent") then
			re:FireClient(player)
		end
	end)
end

-- Free a slot when player leaves so the next joiner can claim
Players.PlayerRemoving:Connect(function(player)
	local i = player:GetAttribute("PlotSlotIndex")
	if not i then return end
	local s = slots[i]
	if not s then return end
	s.player = nil
	if s.plot then
		s.plot:Destroy()
		s.plot = nil
	end
	if not s.claimPad then
		s.claimPad = makeClaimPad(i)
	end
end)
