--!strict
-- CritterVisuals (BAB-STEAMPUNK §1.5 + §3.5): builds cute critter models
-- inside incubator pods.
--
-- Renamed from PlantVisuals per ADR-5 (P1.2 / 2026-05-08). The legacy name
-- `PlantVisuals.luau` is kept as a one-release shim. Public API signatures
-- are unchanged.
--
-- ── Two render paths ──────────────────────────────────────────────────
-- 1. Archetype renderer (default) — uses species.archetype to build a
--    quad/winged/bug/multi rig with shared geometry across species.
-- 2. Rig renderer (BAB-PHASE-1-CRITTER-RIGS, 2026-05-09) — for the 4
--    headline species with `rigSupport = true`, build a richer per-
--    species silhouette with hatch-cute / juvenile / adult forms.
--    Form transitions smooth-tween scale + emit a particle pop +
--    fire `rig_form_transition` telemetry. When real authored meshes
--    land, swap from procedural Parts to MeshPart by setting `meshId`
--    on the form profile in CritterRigs.luau.
--
-- A "Plant" Model child instance (legacy name kept — load-bearing in the
-- BasePart child lookup, see CritterRegistry.luau and ADR-5) contains
-- (varies by render path):
--   Egg / EggRibbon — translucent shell visible during incubation
--   Body / Head     — main critter geometry
--   Goggle/GoggleRim — brass-rimmed cyan goggle eye (steampunk read)
--   LegN, WingN, Tail, SegmentN, Indicator
--   (rig path adds:) Ears, Horns, Shell, Antennae, NeckN, TailFan, TailSpike
--
-- Public API (unchanged):
--   CritterVisuals.create(planter, species)         -> Model
--   CritterVisuals.update(plantModel, progress)
--   CritterVisuals.markRipe(plantModel, isRipe)

local CritterVisuals = {}

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CritterRigs = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterRigs"))

-- Optional Telemetry require — graceful in case TelemetryBoot hasn't run
-- (e.g., Studio Play with no ServerScriptService.Telemetry yet).
local Telemetry: any = nil
do
	local tm = ServerScriptService:FindFirstChild("Telemetry")
	if tm and tm:IsA("ModuleScript") then
		local ok, mod = pcall(require, tm)
		if ok then Telemetry = mod end
	end
end

-- Lazy-create the CritterCeremony RemoteEvent. Phase 1 ships the wiring;
-- Phase 2 (BAB-CRITTER-ESCAPE) fires it on liability escape, Phase 3
-- fires it on Mythic hatch. Client listener: CritterCameraHooks.client.luau.
local function ensureCeremonyRE(): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local re = remotes:FindFirstChild("CritterCeremony")
	if not re then
		local ev = Instance.new("RemoteEvent")
		ev.Name = "CritterCeremony"
		ev.Parent = remotes
		re = ev
	end
	return re :: RemoteEvent
end
ensureCeremonyRE()  -- create at module load so Phase 2/3 can fire without race

-- ── Ripe indicator builder ──────────────────────────────────────────
-- BAB-VISIBILITY-FIX (2026-05-11): consolidated from the two duplicate
-- inline copies (archetype path + rig path). The original had:
--   1. TextColor3 unset → defaulted to BLACK → invisible against the
--      Aether Hour night sky (and the Forge Hour dim corners). Players
--      reported "can't see anything when it's ready to harvest" because
--      both the indicator AND the metal rig were swallowed by ambient.
--   2. No species displayName → on Android, where some emojis (🪲) fail
--      to render, the indicator showed a blank square.
--
-- This helper:
--   - Sets TextColor3 = SteamCream (light) with OilBlack stroke for
--     contrast in any lighting.
--   - Adds the species displayName below the emoji so the indicator
--     stays legible even when the emoji glyph is missing.
--   - Bumps StudsOffset to 4 so the BillboardGui clears the egg shell
--     during the grow cycle (the egg is ~2.8 tall).
local function buildRipeIndicator(body: BasePart, species: any): (PointLight, BillboardGui)
	local color = body.Color   -- match body's tint

	local light = Instance.new("PointLight")
	light.Name = "RipeGlow"
	light.Color = color
	light.Range = 12
	light.Brightness = 0
	light.Parent = body

	local indicator = Instance.new("BillboardGui")
	indicator.Name = "RipeIndicator"
	indicator.Size = UDim2.fromOffset(140, 80)
	indicator.StudsOffset = Vector3.new(0, 4, 0)
	indicator.AlwaysOnTop = true
	indicator.LightInfluence = 0
	indicator.Enabled = false
	indicator.Parent = body

	local emoji = Instance.new("TextLabel")
	emoji.Name = "Emoji"
	emoji.Size = UDim2.new(1, 0, 0.55, 0)
	emoji.Position = UDim2.fromScale(0, 0)
	emoji.BackgroundTransparency = 1
	emoji.Text = (species.emoji or "✨") .. " READY"
	emoji.TextColor3 = Color3.fromRGB(242, 228, 201)  -- SteamCream
	emoji.TextStrokeColor3 = Color3.fromRGB(26, 20, 16)  -- OilBlack
	emoji.TextStrokeTransparency = 0
	emoji.TextScaled = true
	emoji.Font = Enum.Font.FredokaOne
	emoji.RichText = false
	emoji.Parent = indicator

	-- Species name below — fallback for when the emoji glyph is missing
	-- (Android device with limited emoji font, or unicode rendering bug).
	local name = Instance.new("TextLabel")
	name.Name = "SpeciesName"
	name.Size = UDim2.new(1, 0, 0.45, 0)
	name.Position = UDim2.fromScale(0, 0.55)
	name.BackgroundTransparency = 1
	name.Text = species.displayName or species.id or ""
	name.TextColor3 = Color3.fromRGB(232, 197, 71)  -- GoggleGold
	name.TextStrokeColor3 = Color3.fromRGB(26, 20, 16)
	name.TextStrokeTransparency = 0
	name.TextScaled = true
	name.Font = Enum.Font.GothamBold
	name.Parent = indicator

	return light, indicator
end

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

-- ════════════════════════════════════════════════════════════════════
-- Rig renderer (BAB-PHASE-1-CRITTER-RIGS) — for the 4 headline species
-- ════════════════════════════════════════════════════════════════════
--
-- Each rigSupport species gets a richer silhouette built from
-- per-species feature builders. The current form (hatchCute / juvenile
-- / adult) is computed from grow progress and stored on the model as
-- the "CurrentForm" attribute. Crossing a form threshold triggers:
--   1. A scale tween on every rig part to the new form's profile
--   2. A particle pop at the body
--   3. A `rig_form_transition` telemetry event (per ADR-3)
--
-- The egg/ribbon shell is preserved but starts at 0.3 transparency
-- instead of 0, so the cute critter is visible inside the egg from
-- t=0. Egg fades fully 0.4 → 0.6.

local function brandColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local BRASS = brandColor({ 200, 146, 63 })
local CHARCOAL = brandColor({ 46, 42, 42 })
local STEAM_CREAM = brandColor({ 242, 228, 201 })
local AETHER_CYAN = brandColor({ 79, 227, 255 })

-- Adult-form base sizes per species. Forms scale these by `formProfile.scale`
-- and adjust head by `formProfile.headRatio`. Per-species silhouette comes
-- from feature builders below.
local function rigBodyBaseSize(speciesId: string): Vector3
	if speciesId == "mech_hound"   then return Vector3.new(2.0, 1.4, 1.4) end  -- elongated dog body
	if speciesId == "coal_drake"   then return Vector3.new(1.8, 1.4, 1.4) end  -- compact dragon torso
	if speciesId == "brass_beetle" then return Vector3.new(1.4, 0.9, 1.4) end  -- low-slung beetle
	if speciesId == "sky_wyvern"   then return Vector3.new(1.6, 1.4, 1.4) end  -- raptor torso
	return Vector3.new(1.4, 1.0, 1.4)
end

local function rigHeadBaseSize(speciesId: string): Vector3
	if speciesId == "mech_hound"   then return Vector3.new(1.0, 1.0, 1.0) end
	if speciesId == "coal_drake"   then return Vector3.new(1.1, 1.0, 1.2) end  -- slight snout
	if speciesId == "brass_beetle" then return Vector3.new(0.8, 0.7, 0.9) end  -- small head
	if speciesId == "sky_wyvern"   then return Vector3.new(0.95, 0.9, 1.1) end
	return Vector3.new(0.9, 0.9, 0.9)
end

-- Apply form profile to part sizes. Body uses scale; head uses scale × headRatio.
local function scaleForForm(baseSize: Vector3, profileScale: number, isHead: boolean, headRatio: number?): Vector3
	if isHead and headRatio then
		return baseSize * profileScale * headRatio
	end
	return baseSize * profileScale
end

-- ── Feature builders ─────────────────────────────────────────────────
-- Each builder appends parts to the model and returns. They use the
-- adult-base origin/sizes; updateRig() rescales them on form transition.

local function buildEars(model: Model, origin: Vector3, color: Color3, headBaseSize: Vector3)
	for _, side in { -1, 1 } do
		local ear = makePart("Ear" .. tostring(side + 2), model)
		ear.Shape = Enum.PartType.Ball
		ear.Material = Enum.Material.Metal
		ear.Color = color:Lerp(BRASS, 0.4)
		ear.Size = Vector3.new(0.4, 0.6, 0.4)
		-- Top of head, slightly offset side-to-side.
		ear.CFrame = CFrame.new(origin + Vector3.new(side * 0.35, 0.55, headBaseSize.Z * 0.35))
			* CFrame.Angles(math.rad(side * -15), 0, 0)
	end
end

local function buildHorns(model: Model, origin: Vector3, headBaseSize: Vector3)
	for _, side in { -1, 1 } do
		local horn = makePart("Horn" .. tostring(side + 2), model)
		horn.Shape = Enum.PartType.Cylinder
		horn.Material = Enum.Material.CorrodedMetal
		horn.Color = CHARCOAL
		horn.Size = Vector3.new(0.5, 0.16, 0.16)
		horn.CFrame = CFrame.new(origin + Vector3.new(side * 0.25, 0.45, headBaseSize.Z * 0.25))
			* CFrame.Angles(0, 0, math.rad(side * 60))
	end
end

local function buildWings(model: Model, origin: Vector3, color: Color3, bodyBaseLen: number, isLarge: boolean)
	local wingSize = isLarge and Vector3.new(2.4, 0.1, 1.1) or Vector3.new(1.4, 0.08, 0.7)
	local wingMaterial = isLarge and Enum.Material.Marble or Enum.Material.Marble
	for _, side in { -1, 1 } do
		local wing = makePart("Wing" .. tostring(side + 2), model)
		wing.Shape = Enum.PartType.Block
		wing.Material = wingMaterial
		wing.Color = color:Lerp(STEAM_CREAM, 0.35)
		wing.Size = wingSize
		wing.CFrame = CFrame.new(origin + Vector3.new(side * (bodyBaseLen * 0.5), 0.4, 0))
			* CFrame.Angles(0, 0, math.rad(side * -20))
	end
end

local function buildShell(model: Model, origin: Vector3, color: Color3)
	local shell = makePart("Shell", model)
	shell.Shape = Enum.PartType.Ball
	shell.Material = Enum.Material.Metal
	shell.Color = color:Lerp(BRASS, 0.5)  -- brassy patina shell
	shell.Size = Vector3.new(1.6, 0.8, 1.4)  -- domed
	shell.Position = origin + Vector3.new(0, 0.5, 0)
end

local function buildAntennae(model: Model, origin: Vector3, headBaseSize: Vector3)
	for _, side in { -1, 1 } do
		local ant = makePart("Antenna" .. tostring(side + 2), model)
		ant.Shape = Enum.PartType.Cylinder
		ant.Material = Enum.Material.Metal
		ant.Color = CHARCOAL
		ant.Size = Vector3.new(0.7, 0.08, 0.08)
		ant.CFrame = CFrame.new(origin + Vector3.new(side * 0.2, 0.7, headBaseSize.Z * 0.4))
			* CFrame.Angles(0, 0, math.rad(side * -45))
	end
end

local function buildLegs(model: Model, origin: Vector3, count: number, bodyBaseLen: number)
	for i = 1, count do
		local leg = makePart("Leg" .. tostring(i), model)
		leg.Shape = Enum.PartType.Cylinder
		leg.Material = Enum.Material.Metal
		leg.Color = CHARCOAL
		leg.Size = Vector3.new(0.6, 0.18, 0.18)
		local angle = (i - 1) * (math.pi * 2 / count)
		local lx = math.cos(angle) * (bodyBaseLen * 0.35)
		local lz = math.sin(angle) * (bodyBaseLen * 0.35)
		leg.CFrame = CFrame.new(origin + Vector3.new(lx, -0.5, lz))
	end
end

local function buildTail(model: Model, origin: Vector3, color: Color3, bodyBaseLen: number)
	local tail = makePart("Tail", model)
	tail.Shape = Enum.PartType.Cylinder
	tail.Material = Enum.Material.CorrodedMetal
	tail.Color = color:Lerp(CHARCOAL, 0.4)
	tail.Size = Vector3.new(0.9, 0.3, 0.3)
	tail.CFrame = CFrame.new(origin + Vector3.new(0, 0.0, -bodyBaseLen * 0.6))
		* CFrame.Angles(0, 0, math.rad(90))
end

local function buildTailSpike(model: Model, origin: Vector3, bodyBaseLen: number)
	local spike = makePart("TailSpike", model)
	spike.Shape = Enum.PartType.Cylinder
	spike.Material = Enum.Material.CorrodedMetal
	spike.Color = CHARCOAL
	spike.Size = Vector3.new(0.4, 0.16, 0.16)
	spike.CFrame = CFrame.new(origin + Vector3.new(0, 0.05, -bodyBaseLen * 1.0))
		* CFrame.Angles(0, 0, math.rad(60))
end

local function buildTailFan(model: Model, origin: Vector3, color: Color3, bodyBaseLen: number)
	local fan = makePart("TailFan", model)
	fan.Shape = Enum.PartType.Block
	fan.Material = Enum.Material.Marble
	fan.Color = color:Lerp(STEAM_CREAM, 0.3)
	fan.Size = Vector3.new(0.06, 0.6, 0.7)
	fan.CFrame = CFrame.new(origin + Vector3.new(0, 0.1, -bodyBaseLen * 1.0))
end

local function buildLongNeck(model: Model, origin: Vector3, color: Color3, headBaseSize: Vector3)
	-- Two extra spheres between body and head to elongate the neck.
	for i = 1, 2 do
		local neck = makePart("Neck" .. tostring(i), model)
		neck.Shape = Enum.PartType.Ball
		neck.Material = Enum.Material.Metal
		neck.Color = color
		neck.Size = Vector3.new(headBaseSize.X * 0.7, headBaseSize.Y * 0.7, headBaseSize.Z * 0.7)
		neck.Position = origin + Vector3.new(0, 0.15 * i, headBaseSize.Z * (0.2 + i * 0.3))
	end
end

local function buildChestPlate(model: Model, origin: Vector3, bodyBaseSize: Vector3)
	local plate = makePart("ChestPlate", model)
	plate.Shape = Enum.PartType.Block
	plate.Material = Enum.Material.Metal
	plate.Color = BRASS
	plate.Size = Vector3.new(bodyBaseSize.X * 0.45, 0.6, 0.16)
	plate.CFrame = CFrame.new(origin + Vector3.new(0, 0.0, bodyBaseSize.Z * 0.55))
end

-- ── Rig create ────────────────────────────────────────────────────────
-- Builds the full per-species rig. Egg/ribbon shell, body+head, plus all
-- features in CritterRigs[species].features. Sets CurrentForm attribute
-- so updateRig() can detect transitions.

local function createRig(model: Model, planter: BasePart, species: any)
	local color = Color3.new(species.color[1], species.color[2], species.color[3])
	local origin = critterOrigin(planter)
	local speciesId = species.id

	model:SetAttribute("RigSupport", true)
	model:SetAttribute("SpeciesId", speciesId)
	model:SetAttribute("OriginY", origin.Y)
	model:SetAttribute("CurrentForm", "hatchCute")
	model:SetAttribute("Ripe", false)

	-- Egg + ribbon (translucent so the rig is visible inside).
	local egg = makePart("Egg", model)
	egg.Shape = Enum.PartType.Ball
	egg.Material = Enum.Material.Marble
	egg.Color = color:Lerp(STEAM_CREAM, 0.6)
	egg.Size = Vector3.new(2.4, 2.8, 2.4)
	egg.Position = origin
	egg.Transparency = 0.35  -- semi-transparent; rig peeks through

	local ribbon = makePart("EggRibbon", model)
	ribbon.Shape = Enum.PartType.Cylinder
	ribbon.Material = Enum.Material.Metal
	ribbon.Color = BRASS
	ribbon.Size = Vector3.new(0.2, 2.6, 2.6)
	ribbon.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	ribbon.Transparency = 0.3

	-- Body + head at hatch-cute scale (the smallest, cutest form).
	local form = CritterRigs.profile(speciesId, "hatchCute") :: any
	local scale = form and form.scale or 0.6
	local headRatio = form and form.headRatio or 1.5

	local bodyBase = rigBodyBaseSize(speciesId)
	local headBase = rigHeadBaseSize(speciesId)
	local bodySize = scaleForForm(bodyBase, scale, false, nil)
	local headSize = scaleForForm(headBase, scale, true, headRatio)

	local body = makePart("Body", model)
	body.Shape = Enum.PartType.Ball
	body.Material = Enum.Material.Metal
	body.Color = color
	body.Size = bodySize
	body.Position = origin

	local head = makePart("Head", model)
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Metal
	head.Color = color
	head.Size = headSize
	head.Position = origin + Vector3.new(0, 0.3 * scale, bodyBase.Z * 0.5 * scale)

	-- Goggle eye (signature steampunk read).
	local goggle = makePart("Goggle", model)
	goggle.Shape = Enum.PartType.Cylinder
	goggle.Material = Enum.Material.Neon
	goggle.Color = AETHER_CYAN
	goggle.Size = Vector3.new(0.1, 0.45, 0.45)
	goggle.CFrame = CFrame.new(head.Position + Vector3.new(0, 0.05, headSize.Z * 0.45))
		* CFrame.Angles(0, 0, math.rad(90))

	local goggleRim = makePart("GoggleRim", model)
	goggleRim.Shape = Enum.PartType.Cylinder
	goggleRim.Material = Enum.Material.Metal
	goggleRim.Color = BRASS
	goggleRim.Size = Vector3.new(0.05, 0.55, 0.55)
	goggleRim.CFrame = CFrame.new(head.Position + Vector3.new(0, 0.05, headSize.Z * 0.48))
		* CFrame.Angles(0, 0, math.rad(90))

	-- ── Per-species features ──
	if CritterRigs.hasFeature(speciesId, "ears") then
		buildEars(model, head.Position, color, headBase)
	end
	if CritterRigs.hasFeature(speciesId, "horns") then
		buildHorns(model, head.Position, headBase)
	end
	if CritterRigs.hasFeature(speciesId, "wings") then
		local isLarge = (speciesId == "sky_wyvern" or speciesId == "coal_drake")
		buildWings(model, origin, color, bodyBase.X, isLarge)
	end
	if CritterRigs.hasFeature(speciesId, "shell") then
		buildShell(model, origin, color)
	end
	if CritterRigs.hasFeature(speciesId, "antennae") then
		buildAntennae(model, head.Position, headBase)
	end
	if CritterRigs.hasFeature(speciesId, "longNeck") then
		buildLongNeck(model, origin, color, headBase)
	end
	if CritterRigs.hasFeature(speciesId, "chestPlate") then
		buildChestPlate(model, origin, bodyBase)
	end
	if CritterRigs.hasFeature(speciesId, "fourLegs") then
		buildLegs(model, origin, 4, bodyBase.X)
	end
	if CritterRigs.hasFeature(speciesId, "twoLegs") then
		buildLegs(model, origin, 2, bodyBase.X)
	end
	if CritterRigs.hasFeature(speciesId, "sixLegs") then
		buildLegs(model, origin, 6, bodyBase.X)
	end
	if CritterRigs.hasFeature(speciesId, "tail") then
		buildTail(model, origin, color, bodyBase.X)
	end
	if CritterRigs.hasFeature(speciesId, "tailSpike") then
		buildTailSpike(model, origin, bodyBase.X)
	end
	if CritterRigs.hasFeature(speciesId, "tailFan") then
		buildTailFan(model, origin, color, bodyBase.X)
	end

	-- ── Pop particle (used on form transitions) ──
	local popAttach = Instance.new("Attachment")
	popAttach.Name = "FormPopAttach"
	popAttach.Position = Vector3.new(0, 0, 0)
	popAttach.Parent = body

	local pop = Instance.new("ParticleEmitter")
	pop.Name = "FormPop"
	pop.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pop.Color = ColorSequence.new(AETHER_CYAN)
	pop.Size = NumberSequence.new(0.4, 1.2)
	pop.Lifetime = NumberRange.new(0.6, 0.9)
	pop.Rate = 0
	pop.Speed = NumberRange.new(2, 5)
	pop.SpreadAngle = Vector2.new(180, 180)
	pop.Enabled = false
	pop.Parent = popAttach

	-- ── Ripe indicator (consolidated builder; see top of file) ──
	buildRipeIndicator(body, species)

	-- Idle: subtle scale-pulse on the body. Runs forever (low cost).
	task.spawn(function()
		while body.Parent do
			local target = body.Size * 1.03
			local t = TweenService:Create(body, TweenInfo.new(2.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				Size = target,
			})
			t:Play()
			return  -- one-shot setup; the looping is on the tween itself
		end
	end)
end

-- ── Rig form transition ──
-- Called from updateRig() when grow progress crosses a threshold.
-- Tween every per-form-scaled part to the new form's proportions.
local function transitionRigToForm(model: Model, species: any, newForm: string)
	local speciesId = species.id
	local newProfile = CritterRigs.profile(speciesId, newForm :: any)
	if not newProfile then return end

	local body = model:FindFirstChild("Body") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?
	if not (body and head) then return end

	local bodyBase = rigBodyBaseSize(speciesId)
	local headBase = rigHeadBaseSize(speciesId)
	local newBodySize = scaleForForm(bodyBase, newProfile.scale, false, nil)
	local newHeadSize = scaleForForm(headBase, newProfile.scale, true, newProfile.headRatio)

	local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(body, tweenInfo, { Size = newBodySize }):Play()
	TweenService:Create(head, tweenInfo, { Size = newHeadSize }):Play()

	-- Particle pop for the "moment".
	local body2 = body :: any
	local popAttach = body2:FindFirstChild("FormPopAttach") :: Attachment?
	if popAttach then
		local pop = popAttach:FindFirstChild("FormPop") :: ParticleEmitter?
		if pop then pop:Emit(15) end
	end

	-- Telemetry per ADR-3.
	if Telemetry then
		pcall(function()
			Telemetry.track("rig_form_transition", {
				species = speciesId,
				newForm = newForm,
				rarity = species.rarity,
			})
		end)
	end

	model:SetAttribute("CurrentForm", newForm)
end

-- ── Rig update — drives form transitions + egg fade ──
local function updateRig(model: Model, species: any, progress: number)
	local egg = model:FindFirstChild("Egg") :: BasePart?
	local ribbon = model:FindFirstChild("EggRibbon") :: BasePart?

	-- Egg fades 0.4 → 0.6 (from 0.35 starting transparency to fully invisible).
	if egg or ribbon then
		local t = math.clamp((progress - 0.4) / 0.2, 0, 1)
		local trans = 0.35 + (1 - 0.35) * t  -- 0.35 → 1.0
		if egg then egg.Transparency = trans end
		if ribbon then ribbon.Transparency = trans end
	end

	-- Form transitions.
	local expectedForm = CritterRigs.formForProgress(progress)
	local currentForm = model:GetAttribute("CurrentForm")
	if expectedForm ~= currentForm then
		transitionRigToForm(model, species, expectedForm)
	end

	-- Ripe handoff (same rule as archetype path).
	if progress >= 1 and not model:GetAttribute("Ripe") then
		CritterVisuals.markRipe(model, true)
	elseif progress < 1 and model:GetAttribute("Ripe") then
		CritterVisuals.markRipe(model, false)
	end
end

-- ════════════════════════════════════════════════════════════════════
-- Public API
-- ════════════════════════════════════════════════════════════════════

function CritterVisuals.create(planter: BasePart, species: any): Model
	local existing = planter:FindFirstChild("Plant")
	if existing then existing:Destroy() end

	local model = Instance.new("Model")
	model.Name = "Plant"
	model.Parent = planter

	-- BAB-PHASE-1-CRITTER-RIGS: dispatch to rig builder for opted-in species.
	if species.rigSupport and CritterRigs.has(species.id) then
		createRig(model, planter, species)
		return model
	end

	-- ── Archetype path (default — 8 species) ──
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

	-- ── Ripe indicator (consolidated builder; see top of file) ──
	buildRipeIndicator(body, species)

	return model
end

function CritterVisuals.update(plantModel: Model, progress: number)
	-- BAB-PHASE-1-CRITTER-RIGS: dispatch to rig updater for rigSupport species.
	if plantModel:GetAttribute("RigSupport") then
		local speciesId = plantModel:GetAttribute("SpeciesId") :: string?
		if speciesId then
			-- Late-require CritterData to avoid a require cycle at module load.
			local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData")) :: any
			local species = CritterData.get(speciesId)
			if species then
				updateRig(plantModel, species, progress)
				return
			end
		end
	end

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
		CritterVisuals.markRipe(plantModel, true)
	elseif progress < 1 and plantModel:GetAttribute("Ripe") then
		CritterVisuals.markRipe(plantModel, false)
	end
end

function CritterVisuals.markRipe(plantModel: Model, isRipe: boolean)
	plantModel:SetAttribute("Ripe", isRipe)
	local body = plantModel:FindFirstChild("Body") :: BasePart?
	if not body then return end
	local glow = body:FindFirstChild("RipeGlow") :: PointLight?
	local ind = body:FindFirstChild("RipeIndicator") :: BillboardGui?
	if isRipe then
		-- BAB-VISIBILITY-FIX (2026-05-11): brightness bumped 2 → 5 so the
		-- body's brass actually lights up against Aether Hour ambient (the
		-- night phase dims ambient to ~0.3× brass, swallowing critters).
		if glow then glow.Brightness = 5 end
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

return CritterVisuals
