--!strict
-- CorridorsBoot — procedurally builds a v1 corridor scaffold + return portal.
--
-- BAB-STEAL-CORRIDORS scaffolding (2026-05-08). Per the design ticket at
-- AGENT_COORDINATION/tickets/BAB-STEAL-CORRIDORS.md, the full vision is:
--   - branching tree of corridor segments (depth 4-8, 2-4 branches each)
--   - doors per segment that route to ACTIVE players' hatcheries
--   - per-player door discovery persisted to DataStore as a personal map
--   - click-to-snap navigation
--
-- v1 SCAFFOLD ships only:
--   - 1 corridor room (24×8×24, brass walls, dim cyan aether-lighting)
--   - 3 doors per the 3-doors-per-room recipe — but each routes to a
--     RANDOM Hatchery server via TeleportService:TeleportAsync (no
--     cross-server-presence routing yet — that needs MessagingService)
--   - return portal (cyan glow, mirror of the marketplace return)
--   - SpawnLocation
--   - welcome toast (client side via CorridorsUI)
--
-- Defer for follow-on PRs:
--   - procedural multi-room layouts
--   - MessagingService-based active-target sampling
--   - per-player discoveredDoors persistence
--   - map UI + click-to-snap

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local BabPlaces = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BabPlaces"))

-- ── Scene constants ──────────────────────────────────────────────────
local ROOM_SIZE = Vector3.new(24, 12, 24)
local ROOM_CENTER = Vector3.new(0, 6, 0)
local SPAWN_POSITION = Vector3.new(0, 4, -8)              -- inside the room, near south wall
local RETURN_PORTAL_POSITION = Vector3.new(0, 4, -10)     -- on the south wall
local DOOR_TAG = "CorridorDoor"
local RETURN_PORTAL_TAG = "ReturnToHatchery"

-- ── Build the room shell ─────────────────────────────────────────────
local plaza = Instance.new("Model")
plaza.Name = "CorridorRoom"
plaza.Parent = Workspace

local function makeWall(name: string, size: Vector3, position: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.Material = Enum.Material.Slate
	p.Color = color
	p.Size = size
	p.Position = position
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = plaza
end

-- Floor
makeWall("Floor", Vector3.new(ROOM_SIZE.X, 1, ROOM_SIZE.Z), Vector3.new(0, 0.5, 0), BrandColors.IronworkCharcoal)
-- Ceiling
makeWall("Ceiling", Vector3.new(ROOM_SIZE.X, 0.6, ROOM_SIZE.Z), Vector3.new(0, ROOM_SIZE.Y + 0.5, 0), BrandColors.OilBlack)
-- Four walls (with door cutouts placed via the doors below)
makeWall("NorthWall", Vector3.new(ROOM_SIZE.X, ROOM_SIZE.Y, 0.6),  Vector3.new(0, ROOM_SIZE.Y * 0.5 + 1, ROOM_SIZE.Z * 0.5), BrandColors.IronworkCharcoal)
makeWall("SouthWall", Vector3.new(ROOM_SIZE.X, ROOM_SIZE.Y, 0.6),  Vector3.new(0, ROOM_SIZE.Y * 0.5 + 1, -ROOM_SIZE.Z * 0.5), BrandColors.IronworkCharcoal)
makeWall("EastWall",  Vector3.new(0.6, ROOM_SIZE.Y, ROOM_SIZE.Z),  Vector3.new( ROOM_SIZE.X * 0.5, ROOM_SIZE.Y * 0.5 + 1, 0), BrandColors.IronworkCharcoal)
makeWall("WestWall",  Vector3.new(0.6, ROOM_SIZE.Y, ROOM_SIZE.Z),  Vector3.new(-ROOM_SIZE.X * 0.5, ROOM_SIZE.Y * 0.5 + 1, 0), BrandColors.IronworkCharcoal)

-- Brass crown molding for atmosphere
for _, edge in {
	{ pos = Vector3.new(0, 11, -ROOM_SIZE.Z * 0.5 + 0.4),  size = Vector3.new(ROOM_SIZE.X, 0.3, 0.3) },
	{ pos = Vector3.new(0, 11,  ROOM_SIZE.Z * 0.5 - 0.4),  size = Vector3.new(ROOM_SIZE.X, 0.3, 0.3) },
	{ pos = Vector3.new(-ROOM_SIZE.X * 0.5 + 0.4, 11, 0),  size = Vector3.new(0.3, 0.3, ROOM_SIZE.Z) },
	{ pos = Vector3.new( ROOM_SIZE.X * 0.5 - 0.4, 11, 0),  size = Vector3.new(0.3, 0.3, ROOM_SIZE.Z) },
} do
	local trim = Instance.new("Part")
	trim.Name = "BrassCrown"
	trim.Anchored = true
	trim.CanCollide = false
	trim.CanTouch = false
	trim.Material = Enum.Material.Metal
	trim.Color = BrandColors.Brass
	trim.Size = edge.size
	trim.Position = edge.pos
	trim.Parent = plaza
end

-- Aether sconce — cyan glow on each wall for the spec's "dim cyan
-- aether-lighting" requirement.
for _, sconce in {
	Vector3.new(-8, 8, ROOM_SIZE.Z * 0.5 - 0.5),
	Vector3.new( 8, 8, ROOM_SIZE.Z * 0.5 - 0.5),
	Vector3.new(-8, 8, -ROOM_SIZE.Z * 0.5 + 0.5),
	Vector3.new( 8, 8, -ROOM_SIZE.Z * 0.5 + 0.5),
} do
	local s = Instance.new("Part")
	s.Name = "AetherSconce"
	s.Anchored = true
	s.CanCollide = false
	s.CanTouch = false
	s.Material = Enum.Material.Neon
	s.Color = BrandColors.AetherCyan
	s.Size = Vector3.new(0.6, 1.2, 0.4)
	s.Position = sconce
	s.Transparency = 0.2
	s.Parent = plaza
	local light = Instance.new("PointLight")
	light.Color = BrandColors.AetherCyan
	light.Range = 18
	light.Brightness = 1.5
	light.Parent = s
end

-- ── SpawnLocation ────────────────────────────────────────────────────
local spawnPad = Instance.new("SpawnLocation")
spawnPad.Name = "CorridorSpawn"
spawnPad.Anchored = true
spawnPad.CanCollide = true
spawnPad.Material = Enum.Material.Marble
spawnPad.Color = BrandColors.ValveRed
spawnPad.Size = Vector3.new(6, 0.4, 6)
spawnPad.Position = SPAWN_POSITION
spawnPad.Neutral = true
spawnPad.AllowTeamChangeOnTouch = false
spawnPad.Parent = plaza

-- ── 3 doors on the north wall ────────────────────────────────────────
-- Each door routes to a random Hatchery server. v1 has no per-target
-- routing — that's the follow-on with MessagingService presence.
local DOOR_POSITIONS = {
	{ x = -8, label = "?" },
	{ x =  0, label = "?" },
	{ x =  8, label = "?" },
}

for i, def in ipairs(DOOR_POSITIONS) do
	local door = Instance.new("Part")
	door.Name = "Door_" .. tostring(i)
	door.Anchored = true
	door.CanCollide = false
	door.CanTouch = true
	door.Material = Enum.Material.Metal
	door.Color = BrandColors.Brass
	door.Size = Vector3.new(4, 7, 0.6)
	door.Position = Vector3.new(def.x, 4.5, ROOM_SIZE.Z * 0.5 - 0.4)
	door.Parent = plaza
	door:AddTag(DOOR_TAG)
	door:SetAttribute("DoorIndex", i)

	-- Door label (the unknown "?" v1 — full discovery system in follow-on).
	local sgui = Instance.new("SurfaceGui")
	sgui.Face = Enum.NormalId.Back  -- visible from inside the room (player approaches from -Z)
	sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sgui.PixelsPerStud = 50
	sgui.Parent = door
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = def.label
	lbl.TextColor3 = BrandColors.OilBlack
	lbl.Font = Enum.Font.Antique
	lbl.TextScaled = true
	lbl.Parent = sgui

	-- Subtle aether-cyan rim glow per door.
	local rim = Instance.new("Part")
	rim.Name = "DoorRim"
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanTouch = false
	rim.Material = Enum.Material.Neon
	rim.Color = BrandColors.AetherCyan
	rim.Transparency = 0.5
	rim.Size = Vector3.new(4.2, 0.3, 0.7)
	rim.Position = door.Position + Vector3.new(0, -3.6, 0)
	rim.Parent = plaza
end

-- ── Return portal (south wall, behind the spawn) ─────────────────────
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
	end

	frame("LeftColumn",  Vector3.new(0.6, 8, 1.0), Vector3.new(-2.6, 0, 0), BrandColors.Brass)
	frame("RightColumn", Vector3.new(0.6, 8, 1.0), Vector3.new( 2.6, 0, 0), BrandColors.Brass)
	frame("Header",      Vector3.new(6.0, 0.8, 1.0), Vector3.new(0, 3.6, 0), BrandColors.AetherCyan)

	local window = Instance.new("Part")
	window.Name = "Window"
	window.Anchored = true
	window.CanCollide = false
	window.CanTouch = true
	window.CanQuery = true
	window.Material = Enum.Material.Neon
	window.Color = BrandColors.AetherCyan
	window.Transparency = 0.2
	window.Size = Vector3.new(5, 7, 0.4)
	window.CFrame = CFrame.new(RETURN_PORTAL_POSITION)
	window.Parent = model
	window:AddTag(RETURN_PORTAL_TAG)

	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Material = Enum.Material.Metal
	sign.Color = BrandColors.Brass
	sign.Size = Vector3.new(6, 1.4, 0.4)
	sign.CFrame = CFrame.new(RETURN_PORTAL_POSITION + Vector3.new(0, 4.6, 0))
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

-- ── Door + return-portal teleport handlers ───────────────────────────
local lastTeleport: { [number]: number } = {}
local TELEPORT_DEBOUNCE = 2.0

local function attemptDoorTeleport(player: Player, doorIndex: number)
	local now = os.clock()
	if lastTeleport[player.UserId] and now - lastTeleport[player.UserId] < TELEPORT_DEBOUNCE then
		return
	end
	lastTeleport[player.UserId] = now

	local hatcheryId = BabPlaces.hatchery()
	if hatcheryId <= 0 then
		warn("[CorridorsBoot] no Hatchery PlaceId — cannot route door")
		return
	end

	-- v1 lazy routing: TeleportAsync to Hatchery (random server). The
	-- "you arrived in some hatchery, see what you find" experience.
	-- Follow-on: MessagingService presence → TeleportToPlaceInstance to a
	-- specific player's running server, with door discovery persistence.
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		from = "corridors",
		asThief = true,
		doorIndex = doorIndex,
		teleportedAt = os.time(),
	})
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(hatcheryId, { player }, options)
	end)
	if not ok then
		warn(("[CorridorsBoot] door %d teleport failed for %s: %s"):format(doorIndex, player.Name, tostring(err)))
		lastTeleport[player.UserId] = nil
	else
		print(("[BAB-LIFE] %s entered door %d → hatchery"):format(player.Name, doorIndex))
	end
end

local function attemptReturn(player: Player)
	local now = os.clock()
	if lastTeleport[player.UserId] and now - lastTeleport[player.UserId] < TELEPORT_DEBOUNCE then
		return
	end
	lastTeleport[player.UserId] = now

	local hatcheryId = BabPlaces.hatchery()
	if hatcheryId <= 0 then return end

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ from = "corridors", returningAt = os.time() })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(hatcheryId, { player }, options)
	end)
	if not ok then
		warn(("[CorridorsBoot] return failed for %s: %s"):format(player.Name, tostring(err)))
		lastTeleport[player.UserId] = nil
	else
		print(("[BAB-LIFE] %s → hatchery (return from corridors)"):format(player.Name))
	end
end

local function wireDoor(part: Instance)
	if not part:IsA("BasePart") then return end
	if part:GetAttribute("WiredDoor") then return end
	part:SetAttribute("WiredDoor", true)
	local doorIndex = part:GetAttribute("DoorIndex") or 0
	part.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		attemptDoorTeleport(player, doorIndex)
	end)
end
for _, p in CollectionService:GetTagged(DOOR_TAG) do wireDoor(p) end
CollectionService:GetInstanceAddedSignal(DOOR_TAG):Connect(wireDoor)

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
	lastTeleport[player.UserId] = nil
end)

print("[BAB-LIFE] CorridorsBoot online — 1-room scaffold, 3 doors, return portal armed")
