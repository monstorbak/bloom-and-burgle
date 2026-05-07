--!strict
-- PlantVisuals (BAB-011): Build proper-looking plant models instead of yellow boxes.
--
-- A plant model is a Model with parts:
--   StemBase        -- thin cylinder from soil
--   Stem            -- main stalk (scales with progress)
--   LeafL, LeafR    -- two angled leaves halfway up (appear at progress >= 0.4)
--   Bud             -- flower bud at top (visible at progress >= 0.6)
--   Bloom           -- full bloom mesh + glow (visible at progress >= 0.85, ripe)
--   RipeIndicator   -- floating BillboardGui ✨ above plant when ripe (progress = 1)
--
-- All parts are anchored, CanCollide false, and parented to the planter so
-- destruction on harvest cleans up automatically.
--
-- Public:
--   PlantVisuals.create(planter, species)         -> Model
--   PlantVisuals.update(plantModel, progress)     -- called per-frame from grow loop
--   PlantVisuals.markRipe(plantModel, isRipe)     -- toggles ripe glow + indicator

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

-- Build the plant Model. `planter` is the BasePart this plant grows out of.
-- `species` is a PlantData PlantSpec (color, rarity).
function PlantVisuals.create(planter: BasePart, species: any): Model
	local existing = planter:FindFirstChild("Plant")
	if existing then existing:Destroy() end

	local model = Instance.new("Model")
	model.Name = "Plant"
	model.Parent = planter

	local color = Color3.new(species.color[1], species.color[2], species.color[3])
	local stemColor = Color3.fromRGB(60, 130, 50)
	local leafColor = Color3.fromRGB(80, 170, 60)
	local origin = planter.Position + Vector3.new(0, planter.Size.Y / 2, 0)

	-- StemBase: small mound at soil level, always visible after planting
	local base = makePart("StemBase", model)
	base.Shape = Enum.PartType.Ball
	base.Size = Vector3.new(1.4, 1.4, 1.4)
	base.Material = Enum.Material.Grass
	base.Color = Color3.fromRGB(80, 60, 40)
	base.Position = origin + Vector3.new(0, 0.2, 0)

	-- Stem: cylinder that grows in height
	local stem = makePart("Stem", model)
	stem.Shape = Enum.PartType.Cylinder
	stem.Material = Enum.Material.Grass
	stem.Color = stemColor
	stem.Size = Vector3.new(0.6, 0.4, 0.4)  -- length on X axis (will be rotated up)
	stem.CFrame = CFrame.new(origin + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))

	-- Two leaves
	local leafL = makePart("LeafL", model)
	leafL.Shape = Enum.PartType.Block
	leafL.Material = Enum.Material.Grass
	leafL.Color = leafColor
	leafL.Size = Vector3.new(1.4, 0.3, 0.6)
	leafL.CFrame = CFrame.new(origin + Vector3.new(-0.6, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(20))
	leafL.Transparency = 1

	local leafR = makePart("LeafR", model)
	leafR.Shape = Enum.PartType.Block
	leafR.Material = Enum.Material.Grass
	leafR.Color = leafColor
	leafR.Size = Vector3.new(1.4, 0.3, 0.6)
	leafR.CFrame = CFrame.new(origin + Vector3.new(0.6, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(-20))
	leafR.Transparency = 1

	-- Bud: small ball at top, color of species
	local bud = makePart("Bud", model)
	bud.Shape = Enum.PartType.Ball
	bud.Material = Enum.Material.SmoothPlastic
	bud.Color = color:Lerp(Color3.fromRGB(40, 80, 40), 0.4) -- darker, unripe
	bud.Size = Vector3.new(1.0, 1.0, 1.0)
	bud.Position = origin + Vector3.new(0, 1.5, 0)
	bud.Transparency = 1

	-- Bloom: full neon flower at top when ripe
	local bloom = makePart("Bloom", model)
	bloom.Shape = Enum.PartType.Ball
	bloom.Material = Enum.Material.Neon
	bloom.Color = color
	bloom.Size = Vector3.new(2.4, 2.4, 2.4)
	bloom.Position = origin + Vector3.new(0, 1.5, 0)
	bloom.Transparency = 1

	-- Glow attachment for ripe indicator
	local glowAttach = Instance.new("Attachment")
	glowAttach.Name = "GlowAttach"
	glowAttach.Position = Vector3.new(0, 0, 0)
	glowAttach.Parent = bloom

	local pl = Instance.new("PointLight")
	pl.Name = "RipeGlow"
	pl.Color = color
	pl.Range = 12
	pl.Brightness = 0
	pl.Parent = bloom

	-- Floating ✨ indicator (hidden until ripe)
	local indicator = Instance.new("BillboardGui")
	indicator.Name = "RipeIndicator"
	indicator.Size = UDim2.fromOffset(80, 80)
	indicator.StudsOffset = Vector3.new(0, 4, 0)
	indicator.AlwaysOnTop = true
	indicator.Enabled = false
	indicator.Parent = bloom
	local ind = Instance.new("TextLabel")
	ind.Size = UDim2.fromScale(1, 1)
	ind.BackgroundTransparency = 1
	ind.Text = species.emoji or "✨"
	ind.TextScaled = true
	ind.Font = Enum.Font.FredokaOne
	ind.Parent = indicator

	-- Subtle bobbing motion for ripe plants
	model:SetAttribute("OriginY", origin.Y)
	model:SetAttribute("Ripe", false)

	return model
end

-- Update growth visuals. progress in [0,1].
function PlantVisuals.update(plantModel: Model, progress: number)
	local stem = plantModel:FindFirstChild("Stem") :: BasePart?
	if not stem then return end
	local leafL = plantModel:FindFirstChild("LeafL") :: BasePart?
	local leafR = plantModel:FindFirstChild("LeafR") :: BasePart?
	local bud = plantModel:FindFirstChild("Bud") :: BasePart?
	local bloom = plantModel:FindFirstChild("Bloom") :: BasePart?
	if not (leafL and leafR and bud and bloom) then return end

	local originY = plantModel:GetAttribute("OriginY") or 0
	local pivot = stem.Position
	-- Stem: grows from height 0.4 to 4.5
	local stemHeight = 0.4 + progress * 4.1
	stem.Size = Vector3.new(stemHeight, 0.5, 0.5)
	-- Re-anchor stem so its base stays at originY+0.4
	stem.CFrame = CFrame.new(Vector3.new(pivot.X, originY + 0.4 + stemHeight / 2, pivot.Z)) * CFrame.Angles(0, 0, math.rad(90))

	-- Leaves: appear at progress >= 0.4, fade in 0.4 -> 0.55, sit halfway up stem
	local leafFade = math.clamp((progress - 0.4) / 0.15, 0, 1)
	leafL.Transparency = 1 - leafFade
	leafR.Transparency = 1 - leafFade
	local leafY = originY + 0.4 + stemHeight * 0.5
	leafL.CFrame = CFrame.new(Vector3.new(pivot.X - 0.7, leafY, pivot.Z)) * CFrame.Angles(0, 0, math.rad(20))
	leafR.CFrame = CFrame.new(Vector3.new(pivot.X + 0.7, leafY, pivot.Z)) * CFrame.Angles(0, 0, math.rad(-20))

	-- Bud: appears at progress >= 0.6, fade in 0.6 -> 0.8, swells over time
	local budFade = math.clamp((progress - 0.6) / 0.2, 0, 1)
	bud.Transparency = 1 - budFade
	local budSize = 0.6 + budFade * 0.8
	bud.Size = Vector3.new(budSize, budSize, budSize)
	local topY = originY + 0.4 + stemHeight + 0.3
	bud.Position = Vector3.new(pivot.X, topY, pivot.Z)

	-- Bloom: appears at progress >= 0.85, fade in 0.85 -> 1.0
	local bloomFade = math.clamp((progress - 0.85) / 0.15, 0, 1)
	bloom.Transparency = 1 - bloomFade
	local bloomSize = 0.5 + bloomFade * 1.9
	bloom.Size = Vector3.new(bloomSize, bloomSize, bloomSize)
	bloom.Position = Vector3.new(pivot.X, topY + 0.2, pivot.Z)

	-- Bud color lerps toward bloom color as it ripens (greenish -> species color)
	if budFade > 0 and bud:IsA("BasePart") then
		local fullColor = bloom.Color
		bud.Color = fullColor:Lerp(Color3.fromRGB(40, 80, 40), 1 - budFade)
	end

	-- Once fully ripe, switch on glow + indicator (idempotent)
	if progress >= 1 and not plantModel:GetAttribute("Ripe") then
		PlantVisuals.markRipe(plantModel, true)
	elseif progress < 1 and plantModel:GetAttribute("Ripe") then
		PlantVisuals.markRipe(plantModel, false)
	end
end

function PlantVisuals.markRipe(plantModel: Model, isRipe: boolean)
	plantModel:SetAttribute("Ripe", isRipe)
	local bloom = plantModel:FindFirstChild("Bloom") :: BasePart?
	if not bloom then return end
	local glow = bloom:FindFirstChild("RipeGlow") :: PointLight?
	local ind = bloom:FindFirstChild("RipeIndicator") :: BillboardGui?
	if isRipe then
		if glow then glow.Brightness = 2 end
		if ind then ind.Enabled = true end
		-- Pulse the bloom slightly
		task.spawn(function()
			while plantModel.Parent and plantModel:GetAttribute("Ripe") do
				if not bloom or not bloom.Parent then return end
				local t = TweenService:Create(bloom, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					Size = bloom.Size * 1.08,
				})
				t:Play()
				task.wait(0.1)
				return -- the reverse:true in TweenInfo handles the loop
			end
		end)
	else
		if glow then glow.Brightness = 0 end
		if ind then ind.Enabled = false end
	end
end

return PlantVisuals
