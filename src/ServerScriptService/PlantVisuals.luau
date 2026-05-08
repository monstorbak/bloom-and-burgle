--!strict
-- PlantVisuals (BAB-STEAMPUNK §1.5 + §3.5): builds cute critter models inside
-- incubator pods. Module name preserved for compat with PlantHandler callers;
-- the visuals are now critters, not plants.
--
-- A "Plant" model (legacy name kept) contains:
--   Egg / EggRibbon — translucent shell visible during incubation (0–0.5)
--   Body / Head     — main critter geometry (fades in 0.5–0.75, scales)
--   Goggle/GoggleRim — single brass-rimmed cyan goggle eye (the steampunk read)
--   LegN            — limbs per archetype profile
--   WingN           — only for winged archetypes
--   Tail            — only for quad/winged
--   SegmentN        — extra body chunks for multi (serpent/hydra)
--   Indicator       — floating species emoji + ✨ above critter when ripe
--
-- Public API (signatures unchanged so PlantHandler stays as-is):
--   PlantVisuals.create(planter, species)         -> Model
--   PlantVisuals.update(plantModel, progress)
--   PlantVisuals.markRipe(plantModel, isRipe)

local PlantVisuals = {}

local TweenService = game:GetService("TweenService")

local function makePart(name: string, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The pod cylinder is rotated; the critter sits on top of the cylinder casing.
-- Pod height = 4.2 along Y after rotation, centered at planter.Y. Top ≈ +2.6.
local function critterOrigin(planter: BasePart): Vector3
	return planter.Position + Vector3.new(0, 2.6, 0)
end

local function archetypeProfile(archetype: string)
	if archetype == "quad" then
		return { bodyLen = 1.6, bodyHeight = 1.0, legCount = 4, hasTail = true,  hasWings = false }
	elseif archetype == "winged" then
		return { bodyLen = 1.2, bodyHeight = 0.9, legCount = 2, hasTail = true,  hasWings = true  }
	elseif archetype == "multi" then
		return { bodyLen = 0.9, bodyHeight = 0.8, legCount = 0, hasTail = false, hasWings = false, segments = 3 }
	else  -- bug
		return { bodyLen = 1.0, bodyHeight = 0.7, legCount = 6, hasTail = false, hasWings = false }
	end
end

function PlantVisuals.create(planter: BasePart, species: any): Model
	local existing = planter:FindFirstChild("Plant")
	if existing then existing:Destroy() end

	local model = Instance.new("Model")
	model.Name = "Plant"
	model.Parent = planter

	local color = Color3.new(species.color[1], species.color[2], species.color[3])
	local archetype = (species.archetype or "bug")
	local profile = archetypeProfile(archetype)

	local origin = critterOrigin(planter)
	model:SetAttribute("OriginY", origin.Y)
	model:SetAttribute("Archetype", archetype)
	model:SetAttribute("Ripe", false)

	-- ── Egg (visible 0.0–0.5, fades 0.4–0.6) ──
	local egg = makePart("Egg", model)
	egg.Shape = Enum.PartType.Ball
	egg.Material = Enum.Material.Marble
	egg.Color = color:Lerp(Color3.fromRGB(255, 240, 220), 0.6)
	egg.Size = Vector3.new(2.0, 2.4, 2.0)
	egg.Position = origin

	local ribbon = makePart("EggRibbon", model)
	ribbon.Shape = Enum.PartType.Cylinder
	ribbon.Material = Enum.Material.Metal
	ribbon.Color = Color3.fromRGB(200, 146, 63)  -- Brass
	ribbon.Size = Vector3.new(0.2, 2.2, 2.2)
	ribbon.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))

	-- ── Body (hidden until 0.5, scales 0.6→1.0) ──
	-- Material: Metal per spec §1.5 (SmoothPlastic banned — reads as
	-- "starter Roblox kit" against the steampunk identity).
	local body = makePart("Body", model)
	body.Shape = Enum.PartType.Ball
	body.Material = Enum.Material.Metal
	body.Color = color
	body.Size = Vector3.new(profile.bodyLen, profile.bodyHeight, profile.bodyLen)
	body.Position = origin
	body.Transparency = 1

	-- ── Head + goggle eye ──
	local head = makePart("Head", model)
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Metal
	head.Color = color
	head.Size = Vector3.new(0.9, 0.9, 0.9)
	head.Position = origin + Vector3.new(0, 0.4, profile.bodyLen * 0.5)
	head.Transparency = 1

	local goggle = makePart("Goggle", model)
	goggle.Shape = Enum.PartType.Cylinder
	goggle.Material = Enum.Material.Neon
	goggle.Color = Color3.fromRGB(79, 227, 255)  -- AetherCyan
	goggle.Size = Vector3.new(0.1, 0.45, 0.45)
	goggle.CFrame = CFrame.new(head.Position + Vector3.new(0, 0.05, 0.45)) * CFrame.Angles(0, 0, math.rad(90))
	goggle.Transparency = 1

	local goggleRim = makePart("GoggleRim", model)
	goggleRim.Shape = Enum.PartType.Cylinder
	goggleRim.Material = Enum.Material.Metal
	goggleRim.Color = Color3.fromRGB(200, 146, 63)
	goggleRim.Size = Vector3.new(0.05, 0.55, 0.55)
	goggleRim.CFrame = CFrame.new(head.Position + Vector3.new(0, 0.05, 0.48)) * CFrame.Angles(0, 0, math.rad(90))
	goggleRim.Transparency = 1

	-- ── Limbs ──
	local legColor = Color3.fromRGB(46, 42, 42)  -- IronworkCharcoal
	for i = 1, profile.legCount do
		local leg = makePart("Leg" .. tostring(i), model)
		leg.Shape = Enum.PartType.Cylinder
		leg.Material = Enum.Material.Metal
		leg.Color = legColor
		leg.Size = Vector3.new(0.6, 0.18, 0.18)
		local angle = (i - 1) * (math.pi * 2 / profile.legCount)
		local lx = math.cos(angle) * (profile.bodyLen * 0.35)
		local lz = math.sin(angle) * (profile.bodyLen * 0.35)
		leg.CFrame = CFrame.new(origin + Vector3.new(lx, -0.5, lz))
		leg.Transparency = 1
	end

	-- ── Wings (winged only) ──
	-- Material: Marble — gives a translucent veined look that reads as
	-- ornate aether-tech rather than plastic. Spec §1.5 compliant.
	if profile.hasWings then
		for _, side in { -1, 1 } do
			local wing = makePart("Wing" .. tostring(side + 2), model)  -- 1 or 3
			wing.Shape = Enum.PartType.Block
			wing.Material = Enum.Material.Marble
			wing.Color = color:Lerp(Color3.fromRGB(255, 255, 255), 0.3)
			wing.Size = Vector3.new(1.4, 0.08, 0.7)
			wing.CFrame = CFrame.new(origin + Vector3.new(side * 0.8, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(side * -25))
			wing.Transparency = 1
		end
	end

	-- ── Tail (quad/winged only) ──
	-- Material: CorrodedMetal — slight oxidation matches the rugged critter
	-- aesthetic; still reads as steampunk metal.
	if profile.hasTail then
		local tail = makePart("Tail", model)
		tail.Shape = Enum.PartType.Cylinder
		tail.Material = Enum.Material.CorrodedMetal
		tail.Color = color:Lerp(Color3.fromRGB(0, 0, 0), 0.2)
		tail.Size = Vector3.new(0.9, 0.3, 0.3)
		tail.CFrame = CFrame.new(origin + Vector3.new(0, 0.0, -profile.bodyLen * 0.6)) * CFrame.Angles(0, 0, math.rad(90))
		tail.Transparency = 1
	end

	-- ── Multi-segment serpent (multi only) ──
	-- Material: CorrodedMetal — armor-plated serpent segments.
	if archetype == "multi" then
		for i = 1, (profile.segments or 3) - 1 do
			local seg = makePart("Segment" .. tostring(i), model)
			seg.Shape = Enum.PartType.Ball
			seg.Material = Enum.Material.CorrodedMetal
			seg.Color = color
			seg.Size = Vector3.new(0.8, 0.8, 0.8)
			seg.Position = origin + Vector3.new(0, 0, -i * 0.7)
			seg.Transparency = 1
		end
	end

	-- ── Ripe indicator ──
	local light = Instance.new("PointLight")
	light.Name = "RipeGlow"
	light.Color = color
	light.Range = 10
	light.Brightness = 0
	light.Parent = body

	local indicator = Instance.new("BillboardGui")
	indicator.Name = "RipeIndicator"
	indicator.Size = UDim2.fromOffset(80, 80)
	indicator.StudsOffset = Vector3.new(0, 3, 0)
	indicator.AlwaysOnTop = true
	indicator.Enabled = false
	indicator.Parent = body
	local ind = Instance.new("TextLabel")
	ind.Size = UDim2.fromScale(1, 1)
	ind.BackgroundTransparency = 1
	ind.Text = species.emoji or "✨"
	ind.TextScaled = true
	ind.Font = Enum.Font.FredokaOne
	ind.Parent = indicator

	return model
end

function PlantVisuals.update(plantModel: Model, progress: number)
	local egg = plantModel:FindFirstChild("Egg") :: BasePart?
	local body = plantModel:FindFirstChild("Body") :: BasePart?
	if not (egg and body) then return end

	-- Egg fades 0.4 → 0.6
	local eggFade = math.clamp((progress - 0.4) / 0.2, 0, 1)
	egg.Transparency = eggFade
	local ribbon = plantModel:FindFirstChild("EggRibbon") :: BasePart?
	if ribbon then ribbon.Transparency = eggFade end

	-- Body parts fade in 0.5 → 0.75
	local bodyFade = math.clamp((progress - 0.5) / 0.25, 0, 1)
	for _, name in { "Body", "Head", "Goggle", "GoggleRim", "Tail" } do
		local p = plantModel:FindFirstChild(name) :: BasePart?
		if p then p.Transparency = 1 - bodyFade end
	end
	for _, p in plantModel:GetChildren() do
		if p:IsA("BasePart") and (
			p.Name:sub(1, 3) == "Leg" or
			p.Name:sub(1, 4) == "Wing" or
			p.Name:sub(1, 7) == "Segment"
		) then
			p.Transparency = 1 - bodyFade
		end
	end

	if progress >= 1 and not plantModel:GetAttribute("Ripe") then
		PlantVisuals.markRipe(plantModel, true)
	elseif progress < 1 and plantModel:GetAttribute("Ripe") then
		PlantVisuals.markRipe(plantModel, false)
	end
end

function PlantVisuals.markRipe(plantModel: Model, isRipe: boolean)
	plantModel:SetAttribute("Ripe", isRipe)
	local body = plantModel:FindFirstChild("Body") :: BasePart?
	if not body then return end
	local glow = body:FindFirstChild("RipeGlow") :: PointLight?
	local ind = body:FindFirstChild("RipeIndicator") :: BillboardGui?
	if isRipe then
		if glow then glow.Brightness = 2 end
		if ind then ind.Enabled = true end
		task.spawn(function()
			while plantModel.Parent and plantModel:GetAttribute("Ripe") do
				if not body or not body.Parent then return end
				local t = TweenService:Create(body, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					Size = body.Size * 1.06,
				})
				t:Play()
				task.wait(0.1)
				return
			end
		end)
	else
		if glow then glow.Brightness = 0 end
		if ind then ind.Enabled = false end
	end
end

return PlantVisuals
