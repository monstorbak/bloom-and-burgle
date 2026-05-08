--!strict
-- SeedShop: spawns a glowing kiosk near spawn. Touching it opens the seed shop UI.
-- Also handles BuySeed RemoteEvent: validates cost + adds seed to player's stash.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlantData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlantData"))
local ServerScriptService = game:GetService("ServerScriptService")
local PlantVisuals = require(ServerScriptService:WaitForChild("PlantVisuals") :: ModuleScript)

local OpenShopRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("OpenShop") :: RemoteEvent
local BuySeedRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("BuySeed") :: RemoteEvent
local PlantInPlotRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlantInPlot") :: RemoteEvent
local PlantSeedRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PlantSeed") :: RemoteEvent

-- seedStash[userId][speciesId] = count
local seedStash: { [number]: { [string]: number } } = {}

local function getStash(player: Player): { [string]: number }
	if not seedStash[player.UserId] then
		seedStash[player.UserId] = {}
	end
	return seedStash[player.UserId]
end

-- Build the Egg Emporium kiosk near spawn (steampunk reskin per spec §2.5).
-- Multi-part build: brass dome on a stout post, glowing aether window inside,
-- floating signage. The "SeedShopKiosk" tag + OpenShopRE wiring stay so the
-- existing SHOP button still works.
local function buildKiosk(): BasePart
	local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))

	local model = Instance.new("Model")
	model.Name = "EggEmporium"
	model.Parent = Workspace

	local center = Vector3.new(0, 0, -15)

	-- Stout charcoal post / counter
	local post = Instance.new("Part")
	post.Name = "Counter"
	post.Size = Vector3.new(8, 4, 5)
	post.Position = center + Vector3.new(0, 2, 0)
	post.Anchored = true
	post.Material = Enum.Material.Metal
	post.Color = BrandColors.IronworkCharcoal
	post.Parent = model

	-- Brass border on top of counter (visual rim)
	local rim = Instance.new("Part")
	rim.Name = "CounterRim"
	rim.Size = Vector3.new(8.4, 0.4, 5.4)
	rim.Position = center + Vector3.new(0, 4.2, 0)
	rim.Anchored = true
	rim.Material = Enum.Material.Metal
	rim.Color = BrandColors.Brass
	rim.CanCollide = false
	rim.Parent = model

	-- Brass dome (sphere on top — the iconic steampunk read)
	local dome = Instance.new("Part")
	dome.Name = "Dome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(6, 6, 6)
	dome.Position = center + Vector3.new(0, 7, 0)
	dome.Anchored = true
	dome.Material = Enum.Material.Metal
	dome.Color = BrandColors.Brass
	dome.CanCollide = false
	dome.Parent = model

	-- Glowing cyan window inside the dome (aether window — looks magical)
	local window = Instance.new("Part")
	window.Name = "AetherWindow"
	window.Shape = Enum.PartType.Ball
	window.Size = Vector3.new(4.6, 4.6, 4.6)
	window.Position = center + Vector3.new(0, 7, 0)
	window.Anchored = true
	window.Material = Enum.Material.Neon
	window.Color = BrandColors.AetherCyan
	window.Transparency = 0.5
	window.CanCollide = false
	window.CanTouch = false
	window.Parent = model

	-- Touch zone — invisible larger box at base so walking up triggers
	local kiosk = Instance.new("Part")
	kiosk.Name = "SeedShopKiosk"
	kiosk.Size = Vector3.new(10, 10, 8)
	kiosk.Position = center + Vector3.new(0, 5, 0)
	kiosk.Anchored = true
	kiosk.CanCollide = false
	kiosk.Transparency = 1
	kiosk.Parent = model
	kiosk:AddTag("SeedShopKiosk")

	-- Floating brass signage above the dome
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Size = Vector3.new(8, 2.2, 0.3)
	sign.Position = center + Vector3.new(0, 11.5, 0)
	sign.Anchored = true
	sign.Material = Enum.Material.Metal
	sign.Color = BrandColors.Brass
	sign.CanCollide = false
	sign.Parent = model

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 50
	signGui.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Text = "EGG EMPORIUM"
	signText.TextColor3 = BrandColors.OilBlack
	signText.TextScaled = true
	signText.Font = Enum.Font.Antique
	signText.Parent = signGui

	-- Floating "Walk in" hint above sign
	local hintGui = Instance.new("BillboardGui")
	hintGui.Size = UDim2.fromOffset(280, 60)
	hintGui.StudsOffset = Vector3.new(0, 3, 0)
	hintGui.AlwaysOnTop = true
	hintGui.Parent = sign
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromScale(1, 1)
	hint.BackgroundTransparency = 1
	hint.Text = "🥚 Walk in to buy eggs"
	hint.TextColor3 = BrandColors.SteamCream
	hint.TextStrokeTransparency = 0
	hint.TextStrokeColor3 = BrandColors.OilBlack
	hint.TextScaled = true
	hint.Font = Enum.Font.FredokaOne
	hint.Parent = hintGui

	-- Touch opens the shop
	local cooldowns: { [number]: number } = {}
	kiosk.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		local now = os.clock()
		if cooldowns[player.UserId] and now - cooldowns[player.UserId] < 1 then return end
		cooldowns[player.UserId] = now
		OpenShopRE:FireClient(player)
	end)

	return kiosk
end

local kiosk = buildKiosk()

-- BAB-011: Server handler for SHOP button (client → server → client open).
-- Without this, clicking the SHOP UI button does nothing.
OpenShopRE.OnServerEvent:Connect(function(player)
	OpenShopRE:FireClient(player)
end)

-- Buy seed: validate, deduct cash, add to stash
BuySeedRE.OnServerEvent:Connect(function(player, speciesId, qty)
	if typeof(speciesId) ~= "string" then return end
	if typeof(qty) ~= "number" then qty = 1 end
	qty = math.clamp(math.floor(qty), 1, 100)
	local species = PlantData.get(speciesId)
	if not species then return end

	-- Unlock check
	local lifetime = player:GetAttribute("LifetimeCash") or 0
	if lifetime < species.unlockCash then return end

	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local cash = ls:FindFirstChild("Cash") :: IntValue?
	if not cash then return end
	local total = species.seedCost * qty
	if cash.Value < total then return end
	cash.Value = cash.Value - total

	local stash = getStash(player)
	stash[speciesId] = (stash[speciesId] or 0) + qty
	-- Sync to client via attribute (simple, no extra RE)
	player:SetAttribute("Stash_" .. speciesId, stash[speciesId])
end)

-- PlantInPlot: client says "use one of my stashed seeds in this empty planter"
PlantInPlotRE.OnServerEvent:Connect(function(player, planterRef, speciesId)
	if typeof(planterRef) ~= "Instance" or not planterRef:IsA("BasePart") then return end
	if not planterRef:HasTag("Planter") then return end
	if planterRef:GetAttribute("OwnerUserId") ~= player.UserId then return end
	if not planterRef:GetAttribute("IsEmpty") then return end
	if typeof(speciesId) ~= "string" then return end

	local stash = getStash(player)
	if (stash[speciesId] or 0) <= 0 then return end
	stash[speciesId] -= 1
	player:SetAttribute("Stash_" .. speciesId, stash[speciesId])

	-- Reuse PlantHandler via the existing PlantSeed RemoteEvent path,
	-- but skip cost (we already deducted at buy time). Simpler: directly mutate planter here.
	local species = PlantData.get(speciesId)
	if not species then return end
	planterRef:SetAttribute("IsEmpty", false)
	planterRef:SetAttribute("PlantedSpecies", species.id)
	planterRef:SetAttribute("PlantedAt", os.time())
	planterRef:SetAttribute("GrowSeconds", species.growSeconds)

	-- BAB-011: build a real plant model (stem + leaves + bud + bloom).
	PlantVisuals.create(planterRef, species)

	-- Hide the empty border (planted now)
	local border = planterRef:FindFirstChild("EmptyBorder") :: BasePart?
	if border then border.Transparency = 1 end
end)

Players.PlayerRemoving:Connect(function(player)
	seedStash[player.UserId] = nil
end)
