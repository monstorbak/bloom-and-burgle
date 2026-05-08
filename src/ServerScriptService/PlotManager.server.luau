--!strict
-- PlotManager: spawns claim pads, hands out Hatcheries when players touch them,
-- and builds a procedural starter Hatchery (plank floor, incubator pods,
-- Pawn Forge sell pad, Black Market scrap pad).
-- Steampunk reskin per Bloom&Burgle_Design_Spec.md §2.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))

local NUM_PLOT_SLOTS = 16                    -- max concurrent player Hatcheries
local PLOT_RING_RADIUS = 220                 -- distance from Cogworks (where Hatcheries get built)
local CLAIM_PAD_RING_RADIUS = 35             -- distance from spawn where claim pads sit (close so mobile players can find them)

-- Steampunk palette (sourced from BrandColors per spec §1.2)
local CLAIM_PAD_COLOR  = BrandColors.GoggleGold       -- gold claim pad — premium-looking but not raid-able
local PLOT_BASE_COLOR  = BrandColors.OilBlack         -- plank floor read as oily wood
local POD_COLOR        = BrandColors.IronworkCharcoal -- incubator pod casing
local POD_RIM_COLOR    = BrandColors.Brass            -- pod rim/brass trim
local POD_GLOW_COLOR   = BrandColors.AetherCyan       -- aether window glow when active
local SELL_PAD_COLOR   = BrandColors.EmberOrange      -- Pawn Forge — fire-tinted
local SCRAP_PAD_COLOR  = BrandColors.ValveRed         -- Black Market — danger-tinted
local FENCE_COLOR      = BrandColors.IronworkCharcoal -- wrought iron starter fence

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

-- Build a procedural Hatchery at `origin` for `player`.
-- Layout: 40×40 plank floor, wrought-iron perimeter fence, 3×3 incubator pods,
--         Pawn Forge (sell) + Black Market (scrap) on the back-right corner.
local function buildPlot(player: Player, origin: Vector3): Model
	local plot = Instance.new("Model")
	plot.Name = ("Plot_%s"):format(player.Name)

	-- ── Plank floor (oil-black wood) ──
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(40, 1, 40)
	base.Position = origin + Vector3.new(0, 0.5, 0)
	base.Anchored = true
	base.Material = Enum.Material.WoodPlanks
	base.Color = PLOT_BASE_COLOR
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = plot

	-- Brass border trim along the floor edge — reads as steampunk at distance
	for _, edge in {
		{ size = Vector3.new(40.4, 0.4, 0.6), pos = Vector3.new(0, 1.0, -20) },
		{ size = Vector3.new(40.4, 0.4, 0.6), pos = Vector3.new(0, 1.0,  20) },
		{ size = Vector3.new(0.6, 0.4, 40.4), pos = Vector3.new(-20, 1.0, 0) },
		{ size = Vector3.new(0.6, 0.4, 40.4), pos = Vector3.new( 20, 1.0, 0) },
	} do
		local trim = Instance.new("Part")
		trim.Name = "BrassTrim"
		trim.Size = edge.size
		trim.Position = origin + edge.pos
		trim.Anchored = true
		trim.Material = Enum.Material.Metal
		trim.Color = BrandColors.Brass
		trim.CanCollide = false
		trim.CanTouch = false
		trim.Parent = plot
	end

	-- ── Wrought-iron fence (starter tier) on three sides — back, left, right ──
	for _, fence in {
		{ size = Vector3.new(40, 4, 0.6), pos = Vector3.new(0, 3, -20) },   -- back
		{ size = Vector3.new(0.6, 4, 40), pos = Vector3.new(-20, 3, 0) },   -- left
		{ size = Vector3.new(0.6, 4, 40), pos = Vector3.new( 20, 3, 0) },   -- right
	} do
		local f = Instance.new("Part")
		f.Name = "Fence"
		f.Size = fence.size
		f.Position = origin + fence.pos
		f.Anchored = true
		f.Material = Enum.Material.Metal
		f.Color = FENCE_COLOR
		f.Transparency = 0.3
		f.CanCollide = true
		f.Parent = plot
	end

	-- ── Owner sign — engraved brass plaque ──
	local sign = Instance.new("Part")
	sign.Name = "OwnerSign"
	sign.Size = Vector3.new(10, 4, 0.6)
	sign.Position = origin + Vector3.new(0, 7, -19.5)
	sign.Anchored = true
	sign.Material = Enum.Material.Metal
	sign.Color = BrandColors.Brass
	sign.Parent = plot

	local sgui = Instance.new("SurfaceGui")
	sgui.Face = Enum.NormalId.Front
	sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sgui.PixelsPerStud = 50
	sgui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = ("%s's Hatchery"):format(player.DisplayName)
	label.TextColor3 = BrandColors.OilBlack
	label.Font = Enum.Font.Antique
	label.TextScaled = true
	label.Parent = sgui

	-- Two brass posts framing the sign
	for _, side in { -1, 1 } do
		local post = Instance.new("Part")
		post.Name = "SignPost"
		post.Size = Vector3.new(0.6, 9, 0.6)
		post.Position = origin + Vector3.new(side * 5, 5.5, -19.5)
		post.Anchored = true
		post.Material = Enum.Material.Metal
		post.Color = BrandColors.IronworkCharcoal
		post.Parent = plot
	end

	-- ── Incubator pods (3×3 grid) — replaces planters ──
	-- Tag stays "Planter" + name stays "Planter_X_Z" so PlantHandler / DataStore
	-- migration is non-destructive. The visual is now a charcoal cylinder pod
	-- with a brass rim and a glowing aether window.
	for x = -1, 1 do
		for z = -1, 1 do
			local pod = Instance.new("Part")
			pod.Name = ("Planter_%d_%d"):format(x + 2, z + 2)
			pod.Shape = Enum.PartType.Cylinder
			pod.Size = Vector3.new(4.2, 6, 6)         -- length on X (will rotate vertical)
			pod.Anchored = true
			pod.Material = Enum.Material.Metal
			pod.Color = POD_COLOR
			pod.TopSurface = Enum.SurfaceType.Smooth
			pod.BottomSurface = Enum.SurfaceType.Smooth
			pod.CFrame = CFrame.new(origin + Vector3.new(x * 8, 3.1, z * 8)) * CFrame.Angles(0, 0, math.rad(90))
			pod.Parent = plot
			pod:AddTag("Planter")
			pod:SetAttribute("OwnerUserId", player.UserId)
			pod:SetAttribute("IsEmpty", true)

			-- Brass collar around the top of the pod
			local collar = Instance.new("Part")
			collar.Name = "PodCollar"
			collar.Shape = Enum.PartType.Cylinder
			collar.Size = Vector3.new(0.5, 6.4, 6.4)
			collar.Anchored = true
			collar.Material = Enum.Material.Metal
			collar.Color = POD_RIM_COLOR
			collar.CanCollide = false
			collar.CanTouch = false
			collar.CFrame = CFrame.new(origin + Vector3.new(x * 8, 5.9, z * 8)) * CFrame.Angles(0, 0, math.rad(90))
			collar.Parent = pod

			-- Aether window — glows cyan when pod is active, dim when empty
			local window = Instance.new("Part")
			window.Name = "PodWindow"
			window.Shape = Enum.PartType.Cylinder
			window.Size = Vector3.new(0.2, 4.2, 4.2)
			window.Anchored = true
			window.Material = Enum.Material.Neon
			window.Color = POD_GLOW_COLOR
			window.Transparency = 0.4
			window.CanCollide = false
			window.CanTouch = false
			window.CFrame = CFrame.new(origin + Vector3.new(x * 8, 3.1, z * 8)) * CFrame.Angles(0, 0, math.rad(90))
			window.Parent = pod
			-- The "EmptyBorder" naming is preserved so PlantHandler's grow-tick
			-- transparency toggle (border.Transparency = 0/1) keeps working.
			window.Name = "EmptyBorder"

			-- Steam vent on top — small particle generator for mood
			local vent = Instance.new("Part")
			vent.Name = "PodVent"
			vent.Shape = Enum.PartType.Cylinder
			vent.Size = Vector3.new(1.2, 1.0, 1.0)
			vent.Anchored = true
			vent.Material = Enum.Material.Metal
			vent.Color = BrandColors.IronworkCharcoal
			vent.CanCollide = false
			vent.CanTouch = false
			vent.CFrame = CFrame.new(origin + Vector3.new(x * 8, 6.6, z * 8)) * CFrame.Angles(0, 0, math.rad(90))
			vent.Parent = pod

			local steamAttach = Instance.new("Attachment")
			steamAttach.Position = Vector3.new(0, 0.5, 0)
			steamAttach.Parent = vent

			local steam = Instance.new("ParticleEmitter")
			steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
			steam.Color = ColorSequence.new(BrandColors.SteamCream)
			steam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(0.6, 0.7),
				NumberSequenceKeypoint.new(1, 1),
			})
			steam.Size = NumberSequence.new(0.6, 1.6)
			steam.Lifetime = NumberRange.new(2.5, 3.5)
			steam.Rate = 4
			steam.Speed = NumberRange.new(2, 3.5)
			steam.SpreadAngle = Vector2.new(8, 8)
			steam.Parent = steamAttach

			-- Server-side ProximityPrompt (text updated to "Load Egg" — pod, not planter)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PlantPrompt"
			prompt.ActionText = "Load Egg"
			prompt.ObjectText = "Empty Pod"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.Enabled = true
			prompt.Parent = pod
		end
	end

	-- BAB-011: Sell kiosk (clean model with base + post + sign + glow ring)
	-- BAB-FIX: pad now sits ON TOP of the plot floor (y=1.0) instead of inside it,
	-- and the touch zone has CanTouch=true so .Touched actually fires.
	local sellModel = Instance.new("Model")
	sellModel.Name = "SellKiosk"
	sellModel.Parent = plot

	local sellCenter = origin + Vector3.new(15, 0, 15)

	-- Base platform (glowing green pad — visible AND the touch sensor)
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(12, 0.4, 12)
	base.Position = sellCenter + Vector3.new(0, 1.2, 0)  -- bottom at plot floor (y=1.0)
	base.Anchored = true
	base.Material = Enum.Material.Neon
	base.Color = SELL_PAD_COLOR
	base.Transparency = 0.15
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.CanCollide = false  -- walk-through so character isn't blocked
	base.CanTouch = true     -- BAB-FIX: required for Touched event in PlantHandler
	base.Parent = sellModel

	-- Tall invisible sensor on top of the pad — guarantees Touched fires even if
	-- the player runs across at speed or hovers on a step, and works on mobile
	-- where touch hitboxes can graze the pad without intersecting a thin plate.
	local sensor = Instance.new("Part")
	sensor.Name = "SellSensor"
	sensor.Size = Vector3.new(12, 8, 12)
	sensor.Position = sellCenter + Vector3.new(0, 5, 0)
	sensor.Anchored = true
	sensor.Transparency = 1
	sensor.CanCollide = false
	sensor.CanTouch = true
	sensor.CanQuery = false
	sensor.Parent = sellModel

	-- Brass glow ring around base (emissive halo, raised to match new base height)
	local ring = Instance.new("Part")
	ring.Name = "GlowRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.6, 13.5, 13.5)
	ring.Anchored = true
	ring.Material = Enum.Material.Neon
	ring.Color = BrandColors.lerpToWhite(BrandColors.EmberOrange, 0.15)
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(sellCenter + Vector3.new(0, 1.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = sellModel

	-- Central post (brass)
	local post = Instance.new("Part")
	post.Name = "Post"
	post.Shape = Enum.PartType.Cylinder
	post.Size = Vector3.new(4.5, 0.8, 0.8)
	post.Anchored = true
	post.Material = Enum.Material.Metal
	post.Color = BrandColors.Brass
	post.CanCollide = false
	post.CanTouch = false
	post.CFrame = CFrame.new(sellCenter + Vector3.new(0, 3.65, 0)) * CFrame.Angles(0, 0, math.rad(90))
	post.Parent = sellModel

	-- Sign (neon brass board)
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Size = Vector3.new(7, 3.4, 0.4)
	sign.Position = sellCenter + Vector3.new(0, 6.4, 0)
	sign.Anchored = true
	sign.Material = Enum.Material.Neon
	sign.Color = BrandColors.EmberOrange
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
	signText.BackgroundTransparency = 0.25
	signText.BackgroundColor3 = BrandColors.OilBlack
	signText.Text = "PAWN\nFORGE"
	signText.TextColor3 = BrandColors.SteamCream
	signText.TextStrokeTransparency = 0
	signText.TextStrokeColor3 = BrandColors.OilBlack
	signText.TextScaled = true
	signText.Font = Enum.Font.FredokaOne
	signText.Parent = signGui

	-- Floating prompt above sign
	local promptGui = Instance.new("BillboardGui")
	promptGui.Size = UDim2.fromOffset(240, 70)
	promptGui.StudsOffset = Vector3.new(0, 3.5, 0)
	promptGui.AlwaysOnTop = true
	promptGui.Parent = sign
	local promptText = Instance.new("TextLabel")
	promptText.Size = UDim2.fromScale(1, 1)
	promptText.BackgroundTransparency = 1
	promptText.Text = "💰 Walk on pad to SELL"
	promptText.TextColor3 = BrandColors.SteamCream
	promptText.TextStrokeTransparency = 0
	promptText.TextStrokeColor3 = BrandColors.OilBlack
	promptText.TextScaled = true
	promptText.Font = Enum.Font.FredokaOne
	promptText.Parent = promptGui

	-- Tag BOTH the visible pad and the invisible sensor so PlantHandler
	-- wires .Touched on either entry.
	base:AddTag("SellPad")
	base:SetAttribute("OwnerUserId", player.UserId)
	sensor:AddTag("SellPad")
	sensor:SetAttribute("OwnerUserId", player.UserId)

	-- ── Black Market scrap pad — sits opposite corner of the Pawn Forge ──
	-- Touches → fire ScrapPlants RemoteEvent for this player. Wired by
	-- PlantHandler.wireScrapPad (added in same sweep).
	local scrapModel = Instance.new("Model")
	scrapModel.Name = "ScrapKiosk"
	scrapModel.Parent = plot
	local scrapCenter = origin + Vector3.new(15, 0, -15)

	local scrapBase = Instance.new("Part")
	scrapBase.Name = "Base"
	scrapBase.Size = Vector3.new(8, 0.4, 8)
	scrapBase.Position = scrapCenter + Vector3.new(0, 1.2, 0)
	scrapBase.Anchored = true
	scrapBase.Material = Enum.Material.Neon
	scrapBase.Color = SCRAP_PAD_COLOR
	scrapBase.Transparency = 0.2
	scrapBase.CanCollide = false
	scrapBase.CanTouch = true
	scrapBase.Parent = scrapModel

	local scrapSensor = Instance.new("Part")
	scrapSensor.Name = "ScrapSensor"
	scrapSensor.Size = Vector3.new(8, 8, 8)
	scrapSensor.Position = scrapCenter + Vector3.new(0, 5, 0)
	scrapSensor.Anchored = true
	scrapSensor.Transparency = 1
	scrapSensor.CanCollide = false
	scrapSensor.CanTouch = true
	scrapSensor.CanQuery = false
	scrapSensor.Parent = scrapModel

	local scrapPost = Instance.new("Part")
	scrapPost.Name = "Post"
	scrapPost.Shape = Enum.PartType.Cylinder
	scrapPost.Size = Vector3.new(3.5, 0.6, 0.6)
	scrapPost.Anchored = true
	scrapPost.Material = Enum.Material.Metal
	scrapPost.Color = BrandColors.IronworkCharcoal
	scrapPost.CanCollide = false
	scrapPost.CanTouch = false
	scrapPost.CFrame = CFrame.new(scrapCenter + Vector3.new(0, 3.0, 0)) * CFrame.Angles(0, 0, math.rad(90))
	scrapPost.Parent = scrapModel

	local scrapSign = Instance.new("Part")
	scrapSign.Name = "Sign"
	scrapSign.Size = Vector3.new(5.5, 2.6, 0.4)
	scrapSign.Position = scrapCenter + Vector3.new(0, 5.2, 0)
	scrapSign.Anchored = true
	scrapSign.Material = Enum.Material.Neon
	scrapSign.Color = SCRAP_PAD_COLOR
	scrapSign.CanCollide = false
	scrapSign.CanTouch = false
	scrapSign.Parent = scrapModel

	local scrapSignGui = Instance.new("SurfaceGui")
	scrapSignGui.Face = Enum.NormalId.Front
	scrapSignGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	scrapSignGui.PixelsPerStud = 40
	scrapSignGui.Parent = scrapSign

	local scrapSignText = Instance.new("TextLabel")
	scrapSignText.Size = UDim2.fromScale(1, 1)
	scrapSignText.BackgroundTransparency = 0.25
	scrapSignText.BackgroundColor3 = BrandColors.OilBlack
	scrapSignText.Text = "SCRAP"
	scrapSignText.TextColor3 = BrandColors.SteamCream
	scrapSignText.TextStrokeTransparency = 0
	scrapSignText.TextStrokeColor3 = BrandColors.OilBlack
	scrapSignText.TextScaled = true
	scrapSignText.Font = Enum.Font.FredokaOne
	scrapSignText.Parent = scrapSignGui

	local scrapPromptGui = Instance.new("BillboardGui")
	scrapPromptGui.Size = UDim2.fromOffset(220, 60)
	scrapPromptGui.StudsOffset = Vector3.new(0, 3.0, 0)
	scrapPromptGui.AlwaysOnTop = true
	scrapPromptGui.Parent = scrapSign
	local scrapPromptText = Instance.new("TextLabel")
	scrapPromptText.Size = UDim2.fromScale(1, 1)
	scrapPromptText.BackgroundTransparency = 1
	scrapPromptText.Text = "⚙ Cog Parts"
	scrapPromptText.TextColor3 = BrandColors.SteamCream
	scrapPromptText.TextStrokeTransparency = 0
	scrapPromptText.TextStrokeColor3 = BrandColors.OilBlack
	scrapPromptText.TextScaled = true
	scrapPromptText.Font = Enum.Font.FredokaOne
	scrapPromptText.Parent = scrapPromptGui

	scrapBase:AddTag("ScrapPad")
	scrapBase:SetAttribute("OwnerUserId", player.UserId)
	scrapSensor:AddTag("ScrapPad")
	scrapSensor:SetAttribute("OwnerUserId", player.UserId)

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
	gui.Size = UDim2.fromOffset(240, 70)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = pad
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Text = "⚙ CLAIM HATCHERY ⚙"
	txt.TextColor3 = BrandColors.SteamCream
	txt.TextStrokeTransparency = 0
	txt.TextStrokeColor3 = BrandColors.OilBlack
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
