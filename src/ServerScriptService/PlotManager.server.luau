--!strict
-- PlotManager: spawns claim pads, hands out plots when players touch them,
-- and builds a procedural starter plot (grass tiles, planter spots, sell pad).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local NUM_PLOT_SLOTS = 16                    -- max concurrent player plots
local PLOT_SPACING = 80                      -- studs between plot centers
local PLOT_RING_RADIUS = 220                 -- distance from town square (where plots get built)
local CLAIM_PAD_RING_RADIUS = 35             -- distance from spawn where claim PADS sit (close so mobile players can find them)
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

-- Compute world position of a claim pad (much closer to spawn so players can find it)
local function claimPadPosition(i: number): Vector3
	local theta = (i - 1) * (2 * math.pi / NUM_PLOT_SLOTS)
	return Vector3.new(math.cos(theta) * CLAIM_PAD_RING_RADIUS, 0, math.sin(theta) * CLAIM_PAD_RING_RADIUS)
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

	-- BAB-011: Planters (3x3 grid) with visual feedback: borders + glow border when empty
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

			-- BAB-011: Glowing border frame when empty (visual hint to interact)
			local border = Instance.new("Part")
			border.Name = "EmptyBorder"
			border.Shape = Enum.PartType.Block
			border.Size = Vector3.new(6.2, 0.2, 6.2)
			border.Position = planter.Position + Vector3.new(0, -0.7, 0)
			border.Anchored = true
			border.Material = Enum.Material.Neon
			border.Color = Color3.fromRGB(100, 200, 100)  -- soft green
			border.CanCollide = false
			border.CanTouch = false
			border.Parent = planter

			-- The border is a child named "EmptyBorder"; PlantHandler finds it via FindFirstChild.
		end
	end

	-- BAB-011: Sell kiosk (clean model with base + post + sign + glow ring)
	local sellModel = Instance.new("Model")
	sellModel.Name = "SellKiosk"
	sellModel.Parent = plot

	-- Base platform (glowing green pad)
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(12, 0.8, 12)
	base.Position = origin + Vector3.new(15, 0.4, 15)
	base.Anchored = true
	base.Material = Enum.Material.Neon
	base.Color = SELL_PAD_COLOR
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.CanCollide = false
	base.CanTouch = false
	base.Parent = sellModel

	-- Glow ring around base (emissive)
	local ring = Instance.new("Part")
	ring.Name = "GlowRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(1.2, 12, 12)
	ring.Position = origin + Vector3.new(15, 0.8, 15)
	ring.Anchored = true
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(100, 255, 100)
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(ring.Position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = sellModel

	-- Central post
	local post = Instance.new("Part")
	post.Name = "Post"
	post.Shape = Enum.PartType.Cylinder
	post.Size = Vector3.new(4.5, 2.4, 0.6)
	post.Position = origin + Vector3.new(15, 1.8, 15)
	post.Anchored = true
	post.Material = Enum.Material.Metal
	post.Color = Color3.fromRGB(200, 200, 200)
	post.CanCollide = false
	post.CanTouch = false
	post.Parent = sellModel

	-- Sign (neon board with text)
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Size = Vector3.new(6, 3, 0.4)
	sign.Position = origin + Vector3.new(15, 3.2, 15)
	sign.Anchored = true
	sign.Material = Enum.Material.Neon
	sign.Color = Color3.fromRGB(0, 200, 0)
	sign.TopSurface = Enum.SurfaceType.Smooth
	sign.CanCollide = false
	sign.CanTouch = false
	sign.Parent = sellModel

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 40
	signGui.Parent = sign

	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 0.3
	signText.BackgroundColor3 = Color3.fromRGB(0, 40, 0)
	signText.Text = "💰\nSELL\n💰"
	signText.TextColor3 = Color3.fromRGB(255, 255, 255)
	signText.TextStrokeTransparency = 0
	signText.TextScaled = true
	signText.Font = Enum.Font.FredokaOne
	signText.Parent = signGui

	-- Floating prompt above sign
	local promptGui = Instance.new("BillboardGui")
	promptGui.Size = UDim2.fromOffset(200, 60)
	promptGui.StudsOffset = Vector3.new(0, 3.5, 0)
	promptGui.AlwaysOnTop = true
	promptGui.Parent = sign
	local promptText = Instance.new("TextLabel")
	promptText.Size = UDim2.fromScale(1, 1)
	promptText.BackgroundTransparency = 1
	promptText.Text = "Walk here to sell"
	promptText.TextColor3 = Color3.fromRGB(200, 255, 200)
	promptText.TextScaled = true
	promptText.Font = Enum.Font.GothamBold
	promptText.Parent = promptGui

	-- Mark the base as sellable collision zone
	base:AddTag("SellPad")
	base:SetAttribute("OwnerUserId", player.UserId)

	plot.Parent = Workspace
	return plot
end

-- Spawn a claim pad at slot `i`. Touching it claims the slot for the player.
local function makeClaimPad(i: number): Part
	local pos = claimPadPosition(i)
	local pad = Instance.new("Part")
	pad.Name = ("ClaimPad_%d"):format(i)
	-- Tall, fat, impossible-to-miss pad. Mobile-friendly: walking near it triggers .Touched easily.
	pad.Size = Vector3.new(12, 4, 12)
	pad.Position = pos + Vector3.new(0, 2, 0)
	pad.Anchored = true
	pad.CanCollide = false  -- Walk-through so mobile thumbstick doesn't bump into it
	pad.Material = Enum.Material.Neon
	pad.Color = CLAIM_PAD_COLOR
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Transparency = 0.2
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

-- BAB-002: Public API for LeaderstatsScript to rebuild a plot when a saved
-- player rejoins. We have to skip the normal claim-pad flow since their
-- `plotClaimed=true` would block re-claim, and the pad may have already been
-- consumed by another joiner anyway (slot tracking is per-server, not per-save).
local API = {}

-- Try to claim the saved slot for `player`. Returns the rebuilt plot model on
-- success, or nil if the slot was unavailable (in which case the caller should
-- treat the player as un-claimed and let them touch a fresh ClaimPad).
function API.rebuildFromSave(player: Player, savedSlot: number): Model?
	if typeof(savedSlot) ~= "number" then return nil end
	-- BAB-002.1: savedSlot of -1 means "legacy player, plotClaimed=true but no
	-- saved index" — fall through to the find-empty-slot fallback below.
	local s = if savedSlot >= 1 and savedSlot <= NUM_PLOT_SLOTS then slots[savedSlot] else nil
	if not s or (s.player and s.player ~= player) then
		-- Slot invalid OR taken by someone else this server — fall back: assign
		-- first empty slot so the player still gets a plot.
		local fallback: number? = nil
		for i = 1, NUM_PLOT_SLOTS do
			if not slots[i].player then fallback = i; break end
		end
		if not fallback then return nil end
		savedSlot = fallback
		s = slots[savedSlot]
	end

	-- Consume claim pad if still standing.
	if s.claimPad then
		s.claimPad:Destroy()
		s.claimPad = nil
	end

	s.player = player
	player:SetAttribute("PlotClaimed", true)
	player:SetAttribute("PlotSlotIndex", savedSlot)

	local plot = buildPlot(player, slotPosition(savedSlot))
	s.plot = plot

	-- Teleport player to plot once the character exists.
	local function teleport(character: Model)
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			hrp.CFrame = CFrame.new(slotPosition(savedSlot) + Vector3.new(0, 5, 0))
		end
	end
	if player.Character then
		teleport(player.Character)
	else
		player.CharacterAdded:Once(teleport)
	end

	return plot
end

_G.PlotManager = API

-- ReturnToPlot RemoteEvent: client-requested teleport back to player's plot.
-- Used by the 🏠 RETURN TO PLOT button after death/respawn.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local returnRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ReturnToPlot") :: RemoteEvent
returnRE.OnServerEvent:Connect(function(player)
	local i = player:GetAttribute("PlotSlotIndex")
	if not i then return end
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	hrp.CFrame = CFrame.new(slotPosition(i) + Vector3.new(0, 5, 0))
end)

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
