--!strict
-- StealPortal — Cogworks portal that teleports the player to the separate
-- Corridors place (PlaceId per BabPlaces, runtime-override-able via
-- Workspace.CorridorsPlaceId).
--
-- BAB-STEAL-CORRIDORS scaffolding (2026-05-08). Per the design ticket at
-- AGENT_COORDINATION/tickets/BAB-STEAL-CORRIDORS.md:
--
--   "Steal portal in Cogworks → separate Roblox place. Procedurally-
--    generated corridor of doors. Each door routes to an active player's
--    hatchery."
--
-- This module mirrors MarketplacePortal but in red and on the opposite
-- side of the Cogworks. It also charges an entry fee (anti-griefing the
-- corridor — without a cost, repeated re-entries cost nothing and the
-- "I made a wrong door choice" loop is consequence-free).
--
-- v1 entry fee: 100g. The corridor place itself is a 1-room scaffold —
-- map UI, procgen, click-to-snap nav are follow-on PRs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))
local BabPlaces = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BabPlaces"))

-- ── Layout (mirror of MarketplacePortal, opposite side of Cogworks) ──
local PORTAL_POSITION = Vector3.new(-80, 4, 0)   -- mirror of (80, 4, 0)
local PORTAL_TAG = "StealPortal"
local TELEPORT_DEBOUNCE = 2.0
local ENTRY_FEE = 100

local lastTeleport: { [number]: number } = {}

-- ── Build the portal model ───────────────────────────────────────────
local function buildPortal(): Model
	local model = Instance.new("Model")
	model.Name = "StealPortal"
	model.Parent = Workspace

	local function frame(name: string, size: Vector3, offset: Vector3, color: Color3)
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
	end

	frame("LeftColumn",  Vector3.new(0.8, 12, 1.5), Vector3.new(-3.6, 0, 0), BrandColors.IronworkCharcoal)
	frame("RightColumn", Vector3.new(0.8, 12, 1.5), Vector3.new( 3.6, 0, 0), BrandColors.IronworkCharcoal)
	frame("Header",      Vector3.new(8.0, 1.2, 1.5), Vector3.new(0, 5.4, 0),  BrandColors.ValveRed)
	frame("Footer",      Vector3.new(8.0, 0.6, 1.5), Vector3.new(0, -5.7, 0), BrandColors.IronworkCharcoal)

	-- Aether window — Neon, dim ValveRed for the "moral foil" read.
	local window = Instance.new("Part")
	window.Name = "Window"
	window.Anchored = true
	window.CanCollide = false
	window.CanTouch = true
	window.CanQuery = true
	window.Material = Enum.Material.Neon
	window.Color = BrandColors.ValveRed
	window.Transparency = 0.3
	window.Size = Vector3.new(7, 10.4, 0.4)
	window.CFrame = CFrame.new(PORTAL_POSITION)
	window.Parent = model
	window:AddTag(PORTAL_TAG)

	-- Sign
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Material = Enum.Material.Metal
	sign.Color = BrandColors.IronworkCharcoal
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
	lbl.Text = string.format("🥷 STEAL — %dg entry", ENTRY_FEE)
	lbl.TextColor3 = BrandColors.SteamCream
	lbl.Font = Enum.Font.Antique
	lbl.TextScaled = true
	lbl.Parent = sgui

	-- Smoke (heavier than steam — coil + drift, evokes "this is sketchy")
	local smokeAttach = Instance.new("Attachment")
	smokeAttach.Position = Vector3.new(0, -5, 0)
	smokeAttach.Parent = window
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(BrandColors.IronworkCharcoal)
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new(2.0, 4.0)
	smoke.Lifetime = NumberRange.new(3.5, 4.5)
	smoke.Rate = 4
	smoke.Speed = NumberRange.new(1.5, 2.5)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Parent = smokeAttach

	return model
end

-- ── Teleport flow ────────────────────────────────────────────────────
local function attemptTeleport(player: Player)
	local now = os.clock()
	if lastTeleport[player.UserId] and now - lastTeleport[player.UserId] < TELEPORT_DEBOUNCE then
		return
	end
	lastTeleport[player.UserId] = now

	-- Check entry fee.
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash") :: IntValue?
	if not cash or cash.Value < ENTRY_FEE then
		-- Notify via SellPlants RE (handy preexisting "+/- cash" toast path)?
		-- Better: just print + the player will see no teleport. Add a
		-- proper "insufficient funds" toast in a follow-on.
		warn(("[StealPortal] %s tried to enter without %dg"):format(player.Name, ENTRY_FEE))
		lastTeleport[player.UserId] = nil
		return
	end

	local corridorsId = BabPlaces.corridors()
	if corridorsId <= 0 then
		warn("[StealPortal] no Corridors PlaceId — refusing teleport")
		return
	end

	-- Charge fee BEFORE teleport (atomic-ish — if teleport fails below,
	-- we refund). Roblox doesn't have "atomic across two systems" so
	-- this is the best we can do without a transaction ledger.
	cash.Value = cash.Value - ENTRY_FEE

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		from = "hatchery",
		hatcheryPlaceId = BabPlaces.hatchery(),
		entryFeePaid = ENTRY_FEE,
		teleportedAt = os.time(),
	})
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(corridorsId, { player }, options)
	end)
	if not ok then
		warn(("[StealPortal] teleport failed for %s: %s — refunding %dg"):format(player.Name, tostring(err), ENTRY_FEE))
		cash.Value = cash.Value + ENTRY_FEE
		lastTeleport[player.UserId] = nil
	else
		print(("[BAB-LIFE] %s → corridors (placeId=%d, fee=%d)"):format(player.Name, corridorsId, ENTRY_FEE))
	end
end

local function wirePortalWindow(part: Instance)
	if not part:IsA("BasePart") then return end
	if part:GetAttribute("WiredSteal") then return end
	part:SetAttribute("WiredSteal", true)
	part.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		attemptTeleport(player)
	end)
end

buildPortal()
for _, p in CollectionService:GetTagged(PORTAL_TAG) do wirePortalWindow(p) end
CollectionService:GetInstanceAddedSignal(PORTAL_TAG):Connect(wirePortalWindow)

Players.PlayerRemoving:Connect(function(player)
	lastTeleport[player.UserId] = nil
end)

print("[BAB-LIFE] StealPortal online (placeId=" .. BabPlaces.corridors() .. ", fee=" .. ENTRY_FEE .. "g)")
