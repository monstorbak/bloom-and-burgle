--!strict
-- TrophyHallScript — builds the physical Trophy Hall in the Cogworks
-- plaza + populates 2 leaderboard plaques (Hall of Sales + Mythic Hatchers).
--
-- BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL (2026-05-10).
--
-- Phase 4.A ships 2 plaques. Phase 4.B will add Plot Champions + Class
-- Loyalty (per the ticket) once the format is validated against real data.
--
-- ── Position ─────────────────────────────────────────────────────────
-- Per ticket open question 5: +Z (north of spawn). Cogworks plaza center
-- is at origin; Marketplace portal at (80, 4, 0); Steal portal at
-- (-80, 4, 0). Trophy Hall at (0, 4, 100) is visible from spawn, doesn't
-- crowd the portals, leaves the south side open for future content.
--
-- ── Refresh cadence ──────────────────────────────────────────────────
-- Polls DataStore every 60s. New entries land via TrophyData.submit
-- (called by MerchantSellFlow on notable sells, by HarvestFlow on
-- celestial mutations).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))
local TrophyData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TrophyData"))

-- ── Layout ───────────────────────────────────────────────────────────
local HALL_POSITION = Vector3.new(0, 4, 100)
local PLAQUE_WIDTH = 12
local PLAQUE_HEIGHT = 16
local PLAQUE_DEPTH = 0.6
local PLAQUE_SPACING = 16   -- horizontal gap between plaques

-- ── Build base structure ─────────────────────────────────────────────
local hall = Instance.new("Model")
hall.Name = "TrophyHall"
hall.Parent = Workspace

-- Wide brass-and-charcoal base behind the plaques.
local backWall = Instance.new("Part")
backWall.Name = "BackWall"
backWall.Anchored = true
backWall.CanCollide = true
backWall.Material = Enum.Material.Metal
backWall.Color = BrandColors.IronworkCharcoal
backWall.Size = Vector3.new(48, 22, 1.5)
backWall.Position = HALL_POSITION + Vector3.new(0, 7, 1.5)
backWall.Parent = hall

-- Brass header bar across the top.
local header = Instance.new("Part")
header.Name = "Header"
header.Anchored = true
header.CanCollide = false
header.Material = Enum.Material.Metal
header.Color = BrandColors.Brass
header.Size = Vector3.new(48, 2, 1.5)
header.Position = HALL_POSITION + Vector3.new(0, 18, 1.5)
header.Parent = hall

local headerGui = Instance.new("SurfaceGui")
headerGui.Face = Enum.NormalId.Front
headerGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
headerGui.PixelsPerStud = 50
headerGui.Parent = header
local headerLbl = Instance.new("TextLabel")
headerLbl.Size = UDim2.fromScale(1, 1)
headerLbl.BackgroundTransparency = 1
headerLbl.Text = "🏆 TROPHY HALL"
headerLbl.TextColor3 = BrandColors.OilBlack
headerLbl.Font = Enum.Font.Antique
headerLbl.TextScaled = true
headerLbl.Parent = headerGui

-- Floor under the structure (so the hall doesn't appear floating).
local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Anchored = true
floor.CanCollide = true
floor.Material = Enum.Material.Cobblestone
floor.Color = BrandColors.OilBlack
floor.Size = Vector3.new(50, 1, 12)
floor.Position = HALL_POSITION + Vector3.new(0, -2, -3)
floor.Parent = hall

-- ── Build the two plaques ────────────────────────────────────────────
-- Phase-4 design-critique (2026-05-10) fixes:
--   1. Plaque body now BrandColors.OilBlack (was IronworkCharcoal — same
--      shade as the back wall, so plaques disappeared into it). OilBlack
--      gives a deeper black that reads as a separate slab against the
--      charcoal back.
--   2. PointLight spotlight above each plaque (Brass color, range 14) so
--      the plaque face catches light and the trophies feel celebrated.
--   3. Pre-rendered 10 rank slots in the empty state with criteria
--      footer — turns "this is broken" into "this is what's possible."
type Plaque = {
	model: BasePart,
	gui: SurfaceGui,
	listFrame: ScrollingFrame,
	titleLbl: TextLabel,
	footerLbl: TextLabel,         -- criteria copy at the bottom
	emptySlots: { TextLabel },    -- the 10 rank placeholders shown when empty
	accent: Color3,
}

local TOP_N = 10

local function buildPlaque(name: string, displayTitle: string, accent: Color3, xOffset: number, criteriaCopy: string): Plaque
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Metal
	part.Color = BrandColors.OilBlack
	part.Size = Vector3.new(PLAQUE_WIDTH, PLAQUE_HEIGHT, PLAQUE_DEPTH)
	part.Position = HALL_POSITION + Vector3.new(xOffset, 7, 0)
	part.Parent = hall

	-- Brass frame around the plaque (top + bottom strips).
	local topFrame = Instance.new("Part")
	topFrame.Name = "TopFrame"
	topFrame.Anchored = true; topFrame.CanCollide = false
	topFrame.Material = Enum.Material.Metal
	topFrame.Color = accent
	topFrame.Size = Vector3.new(PLAQUE_WIDTH + 0.4, 0.6, PLAQUE_DEPTH + 0.2)
	topFrame.Position = part.Position + Vector3.new(0, PLAQUE_HEIGHT/2, 0)
	topFrame.Parent = hall
	local botFrame = topFrame:Clone()
	botFrame.Name = "BotFrame"
	botFrame.Position = part.Position + Vector3.new(0, -PLAQUE_HEIGHT/2, 0)
	botFrame.Parent = hall

	-- Spotlight overhead so the plaque face glows.
	-- Anchored to TopFrame so it casts down onto the plaque body.
	local spot = Instance.new("PointLight")
	spot.Name = "TrophySpot"
	spot.Color = BrandColors.Brass
	spot.Brightness = 2.4
	spot.Range = 14
	spot.Shadows = false
	spot.Parent = topFrame

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = part

	-- Plaque title at top.
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.Size = UDim2.new(1, -10, 0, 60)
	titleLbl.Position = UDim2.fromOffset(5, 5)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = displayTitle
	titleLbl.TextColor3 = accent
	titleLbl.Font = Enum.Font.FredokaOne
	titleLbl.TextScaled = true
	titleLbl.TextXAlignment = Enum.TextXAlignment.Center
	titleLbl.Parent = gui

	-- ScrollingFrame for the entries. Reduced bottom margin (-100 vs -75)
	-- to leave room for the criteria footer below it.
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "List"
	listFrame.Size = UDim2.new(1, -10, 1, -100)
	listFrame.Position = UDim2.fromOffset(5, 70)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 4
	listFrame.ScrollBarImageColor3 = accent
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame

	-- Pre-render TOP_N rank-slot placeholders. These stay in the listFrame
	-- forever; renderEntries fills them in or restores the "—" placeholder.
	-- LayoutOrder is set so empty slots interleave correctly with real rows.
	local emptySlots: { TextLabel } = {}
	for i = 1, TOP_N do
		local slot = Instance.new("TextLabel")
		slot.Name = "EmptySlot_" .. i
		slot.Size = UDim2.new(1, -8, 0, 28)
		slot.BackgroundTransparency = 1
		slot.Text = string.format("%d.  —", i)
		slot.TextColor3 = Color3.fromRGB(120, 110, 100)   -- dimmer than real entries
		slot.Font = Enum.Font.GothamBold
		slot.TextTransparency = 0.4
		slot.TextScaled = true
		slot.TextXAlignment = Enum.TextXAlignment.Left
		slot.LayoutOrder = i
		slot.Parent = listFrame
		emptySlots[i] = slot
	end

	-- Criteria footer — tells players what they need to do to get on the
	-- board. Anchored to bottom of the GUI, below the list.
	local footerLbl = Instance.new("TextLabel")
	footerLbl.Name = "Footer"
	footerLbl.Size = UDim2.new(1, -10, 0, 28)
	footerLbl.Position = UDim2.new(0, 5, 1, -32)
	footerLbl.AnchorPoint = Vector2.new(0, 0)
	footerLbl.BackgroundTransparency = 1
	footerLbl.Text = criteriaCopy
	footerLbl.TextColor3 = accent
	footerLbl.TextTransparency = 0.15
	footerLbl.Font = Enum.Font.SourceSansItalic
	footerLbl.TextScaled = true
	footerLbl.TextXAlignment = Enum.TextXAlignment.Center
	footerLbl.Parent = gui

	return {
		model = part,
		gui = gui,
		listFrame = listFrame,
		titleLbl = titleLbl,
		footerLbl = footerLbl,
		emptySlots = emptySlots,
		accent = accent,
	}
end

local hallOfSalesPlaque = buildPlaque(
	"HallOfSales", "💰 HALL OF SALES", BrandColors.GoggleGold, -PLAQUE_SPACING,
	"Top single sales — 5,000g+ to qualify"
)
local mythicHatchPlaque = buildPlaque(
	"MythicHatchers", "💫 MYTHIC HATCHERS", BrandColors.AetherCyan, PLAQUE_SPACING,
	"Most lifetime Mythic hatches — keep harvesting"
)

-- ── Format helpers ───────────────────────────────────────────────────

local function fmtCash(n: number): string
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	if n < 1_000_000 then
		local s = string.format("%.1fK", n / 1000)
		return (s:gsub("%.0K", "K"))
	end
	return string.format("%.2fM", n / 1_000_000)
end

local function fmtSalesEntry(rank: number, e: TrophyData.Entry): string
	local s = e.species and CritterData.get(e.species) or nil
	local emoji = (s and s.emoji) or "💰"
	local mut = (e.mutation and e.mutation ~= "") and (" ✨" .. e.mutation:upper()) or ""
	return string.format("%d. %s %s %s — $%s%s",
		rank, emoji, e.displayName, (s and s.displayName) or e.species or "", fmtCash(e.value), mut)
end

local function fmtMythicEntry(rank: number, e: TrophyData.Entry): string
	return string.format("%d. 💫 %s — %d Mythic hatch%s",
		rank, e.displayName, e.value, (e.value == 1) and "" or "es")
end

-- ── Refresh loop ─────────────────────────────────────────────────────

-- Destroy any previously-rendered real rows (everything that isn't a
-- preserved empty slot). EmptySlots are toggled visible/invisible, never
-- destroyed — they're load-bearing scaffolding for the empty-state UX.
local function clearRealRows(plaque: Plaque)
	for _, child in plaque.listFrame:GetChildren() do
		if child:IsA("TextLabel") and not child.Name:match("^EmptySlot_") then
			child:Destroy()
		end
	end
end

local function renderEntries(plaque: Plaque, entries: { TrophyData.Entry }, formatter: (number, TrophyData.Entry) -> string)
	clearRealRows(plaque)
	-- For each rank slot i: if there's a real entry, show it (and hide
	-- the slot placeholder); otherwise show the dim "i. —" slot.
	local n = math.min(#entries, TOP_N)
	for i = 1, TOP_N do
		local slot = plaque.emptySlots[i]
		if i <= n then
			slot.Visible = false
			local row = Instance.new("TextLabel")
			row.Name = "Row_" .. i
			row.Size = UDim2.new(1, -8, 0, 32)
			row.BackgroundTransparency = 1
			row.Text = formatter(i, entries[i])
			row.TextColor3 = (i == 1) and plaque.accent or BrandColors.SteamCream
			row.Font = (i == 1) and Enum.Font.FredokaOne or Enum.Font.GothamBold
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.LayoutOrder = i
			row.Parent = plaque.listFrame
		else
			slot.Visible = true
		end
	end
end

local function refresh()
	local snapshot = TrophyData.read()
	renderEntries(hallOfSalesPlaque, snapshot.hall_of_sales, fmtSalesEntry)
	renderEntries(mythicHatchPlaque, snapshot.mythic_hatch, fmtMythicEntry)
end

-- Initial render (DataStore call is pcall'd inside TrophyData.read so
-- this won't crash if API services are off in Studio).
task.spawn(refresh)

-- Periodic refresh.
task.spawn(function()
	while true do
		task.wait(60)
		refresh()
	end
end)

print("[BAB-LIFE] TrophyHall online (2 plaques: Hall of Sales + Mythic Hatchers)")
