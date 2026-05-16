--!strict
-- AgentPlots — builds the Agent District: a small area south of the
-- Cogworks plaza where AI agents live with their own mini-plots.
--
-- BAB-LIVE-FEATURES Block 1 (2026-05-11).
--
-- ── Why a separate district (vs extending PlotManager) ──────────────
-- The design doc § "Recommended design" called for AI to live on the
-- existing 16-slot PlotManager rotation. In v1 we ship a SEPARATE
-- district because:
--   1. Smaller diff — no PlotManager surgery, no claim-flow conflict
--      handling, no real-player-needs-AI-slot eviction logic.
--   2. Visual clarity — players seeing the AI District immediately
--      understand "those plots are the artificial villagers"; it
--      doubles as another disclosure layer.
--   3. Smaller plots — 4 planters per agent vs 9 per player. AI doesn't
--      need to compete on raw output; they just need to LOOK active.
-- The PlotManager integration is documented as a future revisit in
-- §10 of the live-features doc once we have telemetry on whether
-- "intermingled" AI is preferred.
--
-- ── District location ───────────────────────────────────────────────
-- South of the plaza (opposite from the Trophy Hall at z=100). The
-- district anchor is (0, 0, -120), well clear of the spawn area
-- (spawn at z=12, plaza floor 60x60 centered at 0,1,0).
-- Layout: 6 mini-plots in a 3x2 grid, 30 studs apart.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))

-- CritterVisuals is server-side; AgentBrain needs it to build the plant
-- model when an agent plants a critter. Lazy-required here so callers
-- don't need a separate handle.
local CritterVisuals: any = nil
do
	local cv = ServerScriptService:FindFirstChild("CritterVisuals")
	if cv and cv:IsA("ModuleScript") then
		local ok, mod = pcall(require, cv)
		if ok then CritterVisuals = mod end
	end
end

local M = {}

-- ── Layout ──────────────────────────────────────────────────────────
local DISTRICT_ANCHOR = Vector3.new(0, 0, -120)
local PLOTS_PER_ROW = 3
local PLOT_SPACING = 30   -- 30 studs between mini-plot centers
local MINI_PLOT_SIZE = Vector3.new(20, 1, 20)
local PLOT_FLOOR_Y = 0.5

-- Planters per mini-plot.
local PLANTERS_PER_PLOT = 4
local PLANTER_SIZE = Vector3.new(3, 4, 3)
local PLANTER_GRID_HALF = 5   -- planters arranged in 2x2 at ±5 stud offsets

-- ── State ───────────────────────────────────────────────────────────
local districtBuilt = false
local allocatedSlots: { [number]: boolean } = {}    -- slotIndex → in-use
local plotPartBySlot: { [number]: BasePart } = {}
local planterListBySlot: { [number]: { BasePart } } = {}

-- ── Helpers ─────────────────────────────────────────────────────────

local function makePart(name: string, parent: Instance, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Position the center of mini-plot N (1..6) in world space.
local function plotCenter(slotIndex: number): Vector3
	local i = slotIndex - 1
	local col = i % PLOTS_PER_ROW
	local row = math.floor(i / PLOTS_PER_ROW)
	local offsetX = (col - (PLOTS_PER_ROW - 1) / 2) * PLOT_SPACING
	local offsetZ = row * PLOT_SPACING
	return DISTRICT_ANCHOR + Vector3.new(offsetX, PLOT_FLOOR_Y, -offsetZ)
end

-- Build one planter pod (matches the player-side planter visual
-- contract — same size + brass rim + CollectionService "Planter" tag
-- so GrowLoop picks it up automatically).
local function buildPlanter(parent: Instance, pos: Vector3, agentId: string): BasePart
	-- Body — Slate cylinder, matches the player planter look
	local body = Instance.new("Part")
	body.Name = "AgentPlanter"
	body.Shape = Enum.PartType.Cylinder
	body.Size = PLANTER_SIZE
	-- Cylinder shape axis is X by default; rotate to stand up.
	body.Orientation = Vector3.new(0, 0, 90)
	body.Position = pos
	body.Anchored = true
	body.CanCollide = true
	body.Material = Enum.Material.Slate
	body.Color = BrandColors.IronworkCharcoal
	body.TopSurface = Enum.SurfaceType.Smooth
	body.Parent = parent

	-- Brass rim around the top
	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Size = Vector3.new(0.6, PLANTER_SIZE.Y + 0.4, PLANTER_SIZE.Z + 0.4)
	rim.Orientation = Vector3.new(0, 0, 90)
	rim.Position = pos + Vector3.new(0, PLANTER_SIZE.Y / 2 - 0.2, 0)
	rim.Anchored = true
	rim.CanCollide = false
	rim.Material = Enum.Material.Metal
	rim.Color = BrandColors.Brass
	rim.Parent = parent

	-- Aether glow window — same EmptyBorder name the GrowLoop animates
	local glow = Instance.new("Part")
	glow.Name = "EmptyBorder"
	glow.Size = Vector3.new(2.4, 0.2, 2.4)
	glow.Position = pos + Vector3.new(0, PLANTER_SIZE.Y / 2 + 0.05, 0)
	glow.Anchored = true
	glow.CanCollide = false
	glow.Material = Enum.Material.Neon
	glow.Color = BrandColors.AetherCyan
	glow.Transparency = 0.85
	glow.Parent = parent

	-- Required attributes for GrowLoop + HarvestFlow contract.
	-- OwnerAgentId (instead of OwnerUserId) prevents the
	-- HarvestFlow.harvestPlanter player-side path from accepting
	-- harvests when a player walks onto this planter.
	body:SetAttribute("IsEmpty", true)
	body:SetAttribute("Ripe", false)
	body:SetAttribute("OwnerAgentId", agentId)
	body:SetAttribute("IsAgentPlanter", true)

	-- Tag for GrowLoop. The grow tick is owner-agnostic so it'll grow
	-- whatever's planted via SetAttribute path — see AgentBrain.plant().
	CollectionService:AddTag(body, "Planter")

	return body
end

-- ── Public API ──────────────────────────────────────────────────────

-- Build the district. Idempotent — no-op if already built.
-- Returns the count of mini-plots created.
function M.buildDistrict(): number
	if districtBuilt then return PLOTS_PER_ROW * 2 end
	districtBuilt = true

	local districtModel = Instance.new("Model")
	districtModel.Name = "AgentDistrict"
	districtModel.Parent = Workspace

	-- A subtle ground marker so the district reads as "different from
	-- main plots." Charcoal cobblestone, smaller than a player plot.
	for i = 1, PLOTS_PER_ROW * 2 do
		local center = plotCenter(i)
		local floor = makePart(
			"MiniPlot_" .. i,
			districtModel,
			MINI_PLOT_SIZE,
			center,
			BrandColors.IronworkCharcoal,
			Enum.Material.Cobblestone
		)
		-- Brass corner posts so the plot reads as discrete + intentional
		for _, dx in { -1, 1 } do
			for _, dz in { -1, 1 } do
				local post = makePart(
					"Post",
					districtModel,
					Vector3.new(0.6, 3, 0.6),
					center + Vector3.new(dx * (MINI_PLOT_SIZE.X / 2 - 0.5), 1.5, dz * (MINI_PLOT_SIZE.Z / 2 - 0.5)),
					BrandColors.Brass,
					Enum.Material.Metal
				)
				post.CanCollide = false
			end
		end
		plotPartBySlot[i] = floor
		planterListBySlot[i] = {}
	end

	-- A small brass plaque labeling the district — additional disclosure.
	local sign = makePart(
		"DistrictSign",
		districtModel,
		Vector3.new(8, 0.4, 0.4),
		DISTRICT_ANCHOR + Vector3.new(0, 6, 5),
		BrandColors.Brass,
		Enum.Material.Metal
	)
	sign.CanCollide = false
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Top
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 50
	signGui.Parent = sign
	local signLbl = Instance.new("TextLabel")
	signLbl.Size = UDim2.fromScale(1, 1)
	signLbl.BackgroundTransparency = 1
	signLbl.Text = "ARTIFICIAL VILLAGERS' DISTRICT"
	signLbl.TextColor3 = BrandColors.OilBlack
	signLbl.Font = Enum.Font.Antique
	signLbl.TextScaled = true
	signLbl.Parent = signGui

	return PLOTS_PER_ROW * 2
end

-- Claim a free mini-plot slot for the given agent. Returns the floor
-- BasePart + the freshly-built planters. nil if no slot available.
function M.claim(agentId: string): (BasePart?, { BasePart }?)
	for slot = 1, PLOTS_PER_ROW * 2 do
		if allocatedSlots[slot] then continue end
		allocatedSlots[slot] = true
		local floor = plotPartBySlot[slot]
		if not floor then continue end
		local center = floor.Position
		local planters: { BasePart } = {}
		-- 2x2 planter grid centered on the plot, offset ±5 studs.
		for _, dx in { -PLANTER_GRID_HALF, PLANTER_GRID_HALF } do
			for _, dz in { -PLANTER_GRID_HALF, PLANTER_GRID_HALF } do
				local p = buildPlanter(
					floor.Parent :: Instance,
					center + Vector3.new(dx, PLANTER_SIZE.Y / 2 + MINI_PLOT_SIZE.Y / 2, dz),
					agentId
				)
				table.insert(planters, p)
			end
		end
		planterListBySlot[slot] = planters
		return floor, planters
	end
	return nil, nil
end

-- Release a mini-plot when an agent despawns. v1 ships boot-time only
-- spawning, so this is unused in practice — but the implementation is
-- here for the spawner heartbeat to hot-cycle agents in v1.1.
function M.release(plotPart: BasePart)
	for slot, fp in plotPartBySlot do
		if fp == plotPart then
			allocatedSlots[slot] = false
			local planters = planterListBySlot[slot]
			if planters then
				for _, p in planters do p:Destroy() end
			end
			planterListBySlot[slot] = {}
			break
		end
	end
end

-- Build the plant model on a planter — wraps CritterVisuals so AgentBrain
-- can plant without requiring CritterVisuals directly.
function M.buildPlantOn(planter: BasePart, speciesId: string)
	if not CritterVisuals then return end
	local species = CritterData.get(speciesId)
	if not species then return end
	pcall(function() CritterVisuals.create(planter, species) end)
end

return M
