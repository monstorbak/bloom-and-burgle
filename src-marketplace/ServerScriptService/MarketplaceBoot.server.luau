--!strict
-- MarketplaceBoot — procedurally builds the marketplace scene and wires
-- the return portal that sends players back to the Hatchery.
--
-- BAB-MARKETPLACE-HUB scaffolding (2026-05-08). Per design ticket:
--
--   "A market plaza, brass and lamplight, ~120×120 studs:
--     - Center: a fountain of slowly-pouring brass coins.
--     - North: 3 NPC merchant stalls.
--     - East/West: 4 player-trade booths.
--     - South: the return portal (mirror of the Cogworks side)."
--
-- This v1 ships ONLY:
--   - SpawnLocation
--   - 1 NPC merchant booth (Brass Bart) — see BrassBart.server.luau
--   - Return portal
--   - Floor + atmosphere + perimeter walls
--
-- Defer for follow-on PRs: 2 more NPCs, fountain, 4 player-trade booths.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local BabPlaces = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BabPlaces"))

-- ── Scene constants ──────────────────────────────────────────────────
local FLOOR_SIZE = Vector3.new(120, 1, 120)
local FLOOR_POSITION = Vector3.new(0, 0.5, 0)
local SPAWN_POSITION = Vector3.new(0, 4, 50)              -- south end (near return portal)
local RETURN_PORTAL_POSITION = Vector3.new(0, 4, 55)
local RETURN_PORTAL_TAG = "ReturnToHatchery"

-- ── Floor + walls ────────────────────────────────────────────────────
local plaza = Instance.new("Model")
plaza.Name = "MarketplacePlaza"
plaza.Parent = Workspace

local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Anchored = true
floor.CanCollide = true
floor.Material = Enum.Material.Cobblestone
floor.Color = BrandColors.IronworkCharcoal
floor.Size = FLOOR_SIZE
floor.Position = FLOOR_POSITION
floor.TopSurface = Enum.SurfaceType.Smooth
floor.Parent = plaza

-- Brass perimeter trim (matches the Hatchery floor's brass trim aesthetic).
for _, edge in {
	{ size = Vector3.new(120.4, 0.6, 0.8), pos = Vector3.new(0, 1.0, -60) },
	{ size = Vector3.new(120.4, 0.6, 0.8), pos = Vector3.new(0, 1.0,  60) },
	{ size = Vector3.new(0.8, 0.6, 120.4), pos = Vector3.new(-60, 1.0, 0) },
	{ size = Vector3.new(0.8, 0.6, 120.4), pos = Vector3.new( 60, 1.0, 0) },
} do
	local trim = Instance.new("Part")
	trim.Name = "BrassTrim"
	trim.Anchored = true
	trim.Material = Enum.Material.Metal
	trim.Color = BrandColors.Brass
	trim.CanCollide = false
	trim.CanTouch = false
	trim.Size = edge.size
	trim.Position = edge.pos
	trim.Parent = plaza
end

-- ── Spawn ────────────────────────────────────────────────────────────
local spawnPad = Instance.new("SpawnLocation")
spawnPad.Name = "MarketplaceSpawn"
spawnPad.Anchored = true
spawnPad.CanCollide = true
spawnPad.Material = Enum.Material.Marble
spawnPad.Color = BrandColors.GoggleGold
spawnPad.Size = Vector3.new(8, 0.4, 8)
spawnPad.Position = SPAWN_POSITION
spawnPad.Neutral = true
spawnPad.AllowTeamChangeOnTouch = false
spawnPad.Parent = plaza

-- ── Return portal ────────────────────────────────────────────────────
-- Mirror of the Hatchery-side Marketplace Portal: gold arch + steam.
-- Walking through teleports the player back to the Hatchery place.
local function buildReturnPortal()
	local model = Instance.new("Model")
	model.Name = "ReturnPortal"
	model.Parent = plaza

	local function frame(name: string, size: Vector3, offset: Vector3, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.Material = Enum.Material.Metal
		p.Color = color
		p.Size = size
		p.CFrame = CFrame.new(RETURN_PORTAL_POSITION + offset)
		p.Parent = model
		return p
	end

	frame("LeftColumn",  Vector3.new(0.8, 12, 1.5), Vector3.new(-3.6, 0, 0), BrandColors.Brass)
	frame("RightColumn", Vector3.new(0.8, 12, 1.5), Vector3.new( 3.6, 0, 0), BrandColors.Brass)
	frame("Header",      Vector3.new(8.0, 1.2, 1.5), Vector3.new(0, 5.4, 0),  BrandColors.GoggleGold)

	local window = Instance.new("Part")
	window.Name = "Window"
	window.Anchored = true
	window.CanCollide = false
	window.CanTouch = true
	window.CanQuery = true
	-- Neon (Spec §1.5 bans ForceField). Cyan-tinted return-portal read.
	window.Material = Enum.Material.Neon
	window.Color = BrandColors.AetherCyan
	window.Transparency = 0.2
	window.Size = Vector3.new(7, 10.4, 0.4)
	window.CFrame = CFrame.new(RETURN_PORTAL_POSITION)
	window.Parent = model
	window:AddTag(RETURN_PORTAL_TAG)

	-- Sign
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Material = Enum.Material.Metal
	sign.Color = BrandColors.Brass
	sign.Size = Vector3.new(8, 2.4, 0.5)
	sign.CFrame = CFrame.new(RETURN_PORTAL_POSITION + Vector3.new(0, 7, 0))
	sign.Parent = model

	local sgui = Instance.new("SurfaceGui")
	sgui.Face = Enum.NormalId.Front
	sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sgui.PixelsPerStud = 50
	sgui.Parent = sign
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "🏠 BACK TO HATCHERY"
	lbl.TextColor3 = BrandColors.OilBlack
	lbl.Font = Enum.Font.Antique
	lbl.TextScaled = true
	lbl.Parent = sgui
end
buildReturnPortal()

-- ── Return portal teleport ───────────────────────────────────────────
local lastReturn: { [number]: number } = {}
local RETURN_DEBOUNCE = 2.0

local function attemptReturn(player: Player)
	local now = os.clock()
	if lastReturn[player.UserId] and now - lastReturn[player.UserId] < RETURN_DEBOUNCE then
		return
	end
	lastReturn[player.UserId] = now

	local hatcheryId = BabPlaces.hatchery()
	if hatcheryId <= 0 then
		warn("[MarketplaceBoot] no Hatchery PlaceId — cannot return")
		return
	end

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		from = "marketplace",
		returningAt = os.time(),
	})
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(hatcheryId, { player }, options)
	end)
	if not ok then
		warn(("[MarketplaceBoot] return failed for %s: %s"):format(player.Name, tostring(err)))
		lastReturn[player.UserId] = nil
	else
		print(("[BAB-LIFE] %s → hatchery (return)"):format(player.Name))
	end
end

local function wireReturnPortal(part: Instance)
	if not part:IsA("BasePart") then return end
	if part:GetAttribute("WiredReturn") then return end
	part:SetAttribute("WiredReturn", true)
	part.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		attemptReturn(player)
	end)
end
for _, p in CollectionService:GetTagged(RETURN_PORTAL_TAG) do wireReturnPortal(p) end
CollectionService:GetInstanceAddedSignal(RETURN_PORTAL_TAG):Connect(wireReturnPortal)

Players.PlayerRemoving:Connect(function(player)
	lastReturn[player.UserId] = nil
end)

-- BrassBart.server.luau is its own Script — Roblox runs it independently.
-- No explicit require needed; it parents itself into the scene on boot.

-- ── Welcome banner via PlayerAdded ───────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	-- (clientside MarketplaceUI handles the welcome toast; this just logs)
	print(("[BAB-LIFE] marketplace welcomes %s"):format(player.Name))
end)

print("[BAB-LIFE] MarketplaceBoot online — plaza built, return portal armed")
