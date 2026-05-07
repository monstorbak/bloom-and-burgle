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

-- Build a kiosk part near spawn
local function buildKiosk(): BasePart
	local kiosk = Instance.new("Part")
	kiosk.Name = "SeedShopKiosk"
	kiosk.Size = Vector3.new(8, 10, 8)
	kiosk.Position = Vector3.new(0, 5, -15)  -- near spawn, in front of fountain
	kiosk.Anchored = true
	kiosk.CanCollide = false
	kiosk.Material = Enum.Material.Neon
	kiosk.Color = Color3.fromRGB(120, 220, 100)
	kiosk.Transparency = 0.15
	kiosk.Parent = Workspace
	kiosk:AddTag("SeedShopKiosk")

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(280, 120)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.Parent = kiosk

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(20, 60, 30)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 14)
	fc.Parent = frame
	local fs = Instance.new("UIStroke")
	fs.Color = Color3.fromRGB(180, 255, 140)
	fs.Thickness = 3
	fs.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -10, 0.55, 0)
	title.Position = UDim2.fromOffset(5, 5)
	title.BackgroundTransparency = 1
	title.Text = "🌱 SEED SHOP 🌱"
	title.TextColor3 = Color3.fromRGB(220, 255, 200)
	title.TextStrokeTransparency = 0
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = frame

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -10, 0.45, -10)
	sub.Position = UDim2.new(0, 5, 0.55, 0)
	sub.BackgroundTransparency = 1
	sub.Text = "Walk into me to shop!"
	sub.TextColor3 = Color3.fromRGB(200, 230, 200)
	sub.TextStrokeTransparency = 0.4
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Parent = frame

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
