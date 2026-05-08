--!strict
-- MarketplacePortal — Cogworks portal that teleports the player to the
-- separate Marketplace place (PlaceId per BabPlaces, runtime-override-able
-- via Workspace.MarketplacePlaceId).
--
-- BAB-MARKETPLACE-HUB scaffolding (2026-05-08). Per the design ticket at
-- AGENT_COORDINATION/tickets/BAB-MARKETPLACE-HUB.md:
--
--   "Sell portal in Cogworks → separate Roblox place (shared universe,
--    separate placeId, shared DataStore)."
--
-- This module:
--   1. Builds the visible portal model in the Cogworks at boot.
--   2. Wires its .Touched event to TeleportService:TeleportAsync.
--   3. Snapshots the player's data via the existing CritterHandler.snapshot
--      so the marketplace server reads fresh inventory.
--   4. Per-player 2-second debounce so a single walk-over doesn't fire
--      multiple teleport attempts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local BabPlaces = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BabPlaces"))
local Services = require(ServerScriptService:WaitForChild("Services") :: ModuleScript)

-- ── Cogworks anchor ──────────────────────────────────────────────────
-- Per Design Spec §2.1, the Cogworks plaza centers on origin (0,0,0).
-- Marketplace Portal sits opposite the (red) Steal Portal, so we put it
-- at +X, away from the spawn ring. PlotManager's plot ring is at radius
-- 220, so the portal at radius ~80 is comfortably between spawn and the
-- player's hatchery.
local PORTAL_POSITION = Vector3.new(80, 4, 0)
local PORTAL_SIZE = Vector3.new(8, 12, 1.5)
local PORTAL_TAG = "MarketplacePortal"

-- Per-player teleport debounce (s). Higher than typical .5s because the
-- TeleportAsync request itself is async and can take a moment.
local TELEPORT_DEBOUNCE = 2.0

local lastTeleport: { [number]: number } = {}

-- ── Build the portal model ───────────────────────────────────────────
local function buildPortal(): Model
	local model = Instance.new("Model")
	model.Name = "MarketplacePortal"
	model.Parent = Workspace

	-- The arch frame — brass column on each side + brass header.
	local function frame(name: string, size: Vector3, offset: Vector3, color: Color3): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.Material = Enum.Material.Metal
		p.Color = color
		p.Size = size
		p.CFrame = CFrame.new(PORTAL_POSITION + offset)
		p.Parent = model
		return p
	end

	frame("LeftColumn",  Vector3.new(0.8, 12, 1.5), Vector3.new(-3.6, 0, 0), BrandColors.Brass)
	frame("RightColumn", Vector3.new(0.8, 12, 1.5), Vector3.new( 3.6, 0, 0), BrandColors.Brass)
	frame("Header",      Vector3.new(8.0, 1.2, 1.5), Vector3.new(0, 5.4, 0),  BrandColors.GoggleGold)
	frame("Footer",      Vector3.new(8.0, 0.6, 1.5), Vector3.new(0, -5.7, 0), BrandColors.IronworkCharcoal)

	-- Aether window — the glowing teleport surface. CanTouch=true; this
	-- is what the .Touched event hooks into.
	local window = Instance.new("Part")
	window.Name = "Window"
	window.Anchored = true
	window.CanCollide = false
	window.CanTouch = true
	window.CanQuery = true
	-- Neon (not ForceField — banned by Spec §1.5). Brass-tinted to match
	-- the gold archway. Reads as a charged threshold without breaking the
	-- material-discipline rule.
	window.Material = Enum.Material.Neon
	window.Color = BrandColors.GoggleGold
	window.Transparency = 0.2
	window.Size = Vector3.new(7, 10.4, 0.4)
	window.CFrame = CFrame.new(PORTAL_POSITION)
	window.Parent = model
	window:AddTag(PORTAL_TAG)

	-- Slowly-rotating coin-stack icon above the header for "marketplace" read.
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanTouch = false
	sign.Material = Enum.Material.Metal
	sign.Color = BrandColors.Brass
	sign.Size = Vector3.new(8, 2.4, 0.5)
	sign.CFrame = CFrame.new(PORTAL_POSITION + Vector3.new(0, 7, 0))
	sign.Parent = model

	local sgui = Instance.new("SurfaceGui")
	sgui.Face = Enum.NormalId.Front
	sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sgui.PixelsPerStud = 50
	sgui.Parent = sign
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "💰 MARKETPLACE"
	lbl.TextColor3 = BrandColors.OilBlack
	lbl.Font = Enum.Font.Antique
	lbl.TextScaled = true
	lbl.Parent = sgui

	-- Steam puff at the threshold for atmospheric "alive" cue.
	local steamAttach = Instance.new("Attachment")
	steamAttach.Position = Vector3.new(0, -5, 0)
	steamAttach.Parent = window
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(BrandColors.SteamCream)
	steam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	steam.Size = NumberSequence.new(1.5, 3.0)
	steam.Lifetime = NumberRange.new(2.5, 3.5)
	steam.Rate = 6
	steam.Speed = NumberRange.new(2.5, 4)
	steam.SpreadAngle = Vector2.new(8, 8)
	steam.Parent = steamAttach

	return model
end

-- ── Teleport flow ────────────────────────────────────────────────────
local function attemptTeleport(player: Player)
	local now = os.clock()
	if lastTeleport[player.UserId] and now - lastTeleport[player.UserId] < TELEPORT_DEBOUNCE then
		return
	end
	lastTeleport[player.UserId] = now

	local marketplaceId = BabPlaces.marketplace()
	if marketplaceId <= 0 then
		warn("[MarketplacePortal] no Marketplace PlaceId — refusing teleport")
		return
	end

	-- Snapshot player state to DataStore via the existing PlantHandler/
	-- CritterHandler API so the marketplace place reads fresh inventory.
	-- LeaderstatsScript also flushes on PlayerRemoving but the marketplace
	-- needs the data NOW, not after a 30s autosave.
	local critterHandler = Services.get("CritterHandler") or Services.get("PlantHandler")
	if critterHandler and critterHandler.snapshot then
		pcall(critterHandler.snapshot, player)
	end

	-- TeleportData carries the originating place + class so the marketplace
	-- server can shortcut identity lookup.
	local teleportData = {
		from = "hatchery",
		hatcheryPlaceId = BabPlaces.hatchery(),
		carriedClass = player:GetAttribute("Class"),
		teleportedAt = os.time(),
	}
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(teleportData)

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(marketplaceId, { player }, options)
	end)
	if not ok then
		warn(("[MarketplacePortal] teleport failed for %s: %s"):format(player.Name, tostring(err)))
		-- Reset debounce so the player can try again soon.
		lastTeleport[player.UserId] = nil
	else
		print(("[BAB-LIFE] %s → marketplace (placeId=%d)"):format(player.Name, marketplaceId))
	end
end

-- Wire .Touched on every tagged window (handles future portal repaints).
local function wirePortalWindow(part: Instance)
	if not part:IsA("BasePart") then return end
	if part:GetAttribute("WiredMarketplace") then return end
	part:SetAttribute("WiredMarketplace", true)
	part.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		attemptTeleport(player)
	end)
end

-- ── Boot ─────────────────────────────────────────────────────────────
local CollectionService = game:GetService("CollectionService")
buildPortal()
for _, p in CollectionService:GetTagged(PORTAL_TAG) do wirePortalWindow(p) end
CollectionService:GetInstanceAddedSignal(PORTAL_TAG):Connect(wirePortalWindow)

Players.PlayerRemoving:Connect(function(player)
	lastTeleport[player.UserId] = nil
end)

print("[BAB-LIFE] MarketplacePortal online (placeId=" .. BabPlaces.marketplace() .. ")")
