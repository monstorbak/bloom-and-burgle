--!strict
-- HarvestModal — celebratory modal that pops up on rare harvests.
--
-- P1.3 / ADR-6 precedent: this is the FIRST UI built with Fusion (the
-- reactive primitives at src/ReplicatedStorage/Modules/Fusion). New UI
-- in this codebase should follow this pattern; the legacy Instance.new
-- mutations in CashHUD/ClassPickerUI/SellWaypointHUD will age out as we
-- rebuild them.
--
-- ── Trigger ────────────────────────────────────────────────────────────────
-- Listens to `HarvestPopup` RemoteEvent (server fires it from
-- Critter/HarvestFlow.luau on every harvest). Opens the modal ONLY when
-- the drop is rare:
--   - mutation present (any of the CritterData.MUTATIONS)
--   - OR rarity == "Mythic"
-- Common harvests still get the snappy +1 floating label from CashHUD —
-- the modal is reserved for the moments worth pausing for.
--
-- ── Telemetry ──────────────────────────────────────────────────────────────
-- The eval doc identifies "harvest_decision" as the viral hook. This module
-- doesn't fire that yet — it's the *infrastructure* (modal pops up). The
-- decision actions (Stash / Stable / Sell-now / Gift) are stubbed for the
-- next iteration. Modal close fires "harvest_modal_dismissed" via the
-- existing Telemetry surface (server-side; client will fire via a new RE
-- when actions are added).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Fusion"))
local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))

local HarvestPopupRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("HarvestPopup") :: RemoteEvent

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local OnEvent = Fusion.OnEvent
local Children = Fusion.Children

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- ── Reactive state ─────────────────────────────────────────────────────────
-- Open/closed visibility — drives the ScreenGui Enabled.
local visible = Value(false)
-- Current harvest data (the most recent rare drop). Set to nil when closed.
local current: any = Value(nil)

local titleText = Computed(function()
	local d = current:get()
	if not d then return "" end
	return string.format("%s  %s",
		tostring(d.emoji or "✨"),
		tostring(d.name or "Critter"))
end, { current })

local rarityText = Computed(function()
	local d = current:get()
	if not d then return "" end
	local mutation = d.mutation
	if mutation and mutation ~= "" then
		return string.format("%s  •  %s mutation", tostring(d.rarity or "?"), mutation:upper())
	end
	return tostring(d.rarity or "?")
end, { current })

-- CritterData.rarityColor returns `{ r, g, b }` numbers (legacy shape kept
-- for compat with PlantData.rarityColor callers); convert to Color3 here.
local rarityColor = Computed(function()
	local d = current:get()
	if not d or not d.rarity then return Color3.fromRGB(220, 220, 220) end
	local rgb = (CritterData :: any).rarityColor(d.rarity)
	if type(rgb) == "table" and #rgb == 3 then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return Color3.fromRGB(220, 220, 220)
end, { current })

-- Class affinity advisory — BAB-PHASE-3-MYTHIC-CEREMONY-AND-ADVISORY upgraded
-- this from `affinityFor` (returns kind only) to `advisoryFor` (returns the
-- full class-aware copy "✓ Hexers thrive with Patina Toads. Strong asset
-- if nurtured."). The richer template makes the asset/liability moat
-- visible at the harvest decision point — the spec's brand differentiator.
local affinityText = Computed(function()
	local d = current:get()
	if not d then return "" end
	local class = localPlayer:GetAttribute("Class")
	if not class then return "" end
	if typeof(CritterData) ~= "table" or typeof((CritterData :: any).advisoryFor) ~= "function" then
		return ""
	end
	return (CritterData :: any).advisoryFor(d.species, class)
end, { current })

-- Class-accent color for the advisory line. Asset = gold, liability =
-- ember-orange, neutral = subtle gray. Pulled from the same affinity
-- check so the visual + copy stay aligned.
local affinityColor = Computed(function()
	local d = current:get()
	if not d then return Color3.fromRGB(180, 180, 180) end
	local class = localPlayer:GetAttribute("Class")
	if not class then return Color3.fromRGB(180, 180, 180) end
	local kind = (CritterData :: any).affinityFor(d.species, class)
	if kind == "asset" then return Color3.fromRGB(232, 197, 71)         -- GoggleGold
	elseif kind == "liability" then return Color3.fromRGB(255, 106, 31) -- EmberOrange
	end
	return Color3.fromRGB(180, 180, 180)
end, { current })

-- ── Modal markup ───────────────────────────────────────────────────────────
local function close()
	visible:set(false)
	current:set(nil)
end

-- The whole UI is built once and stays mounted; only its props mutate via
-- the reactive cells. This is the Fusion pattern's payoff — no rebuilds.
local screenGui = New "ScreenGui" {
	Name = "HarvestModal",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = visible,
	[Children] = {
		-- Dimming backdrop
		New "Frame" {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			[Children] = {
				-- Click-to-dismiss hit target
				New "TextButton" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "",
					[OnEvent("Activated")] = close,
				},
			},
		},
		-- Modal panel
		New "Frame" {
			Name = "Panel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 280),
			BackgroundColor3 = Color3.fromRGB(40, 36, 32),  -- IronworkCharcoal-ish
			BorderSizePixel = 0,
			[Children] = {
				New "UICorner" { CornerRadius = UDim.new(0, 12) },
				New "UIStroke" {
					Color = Color3.fromRGB(200, 146, 63),  -- Brass
					Thickness = 2,
				},
				-- Title row
				New "TextLabel" {
					Name = "Title",
					Size = UDim2.new(1, -32, 0, 60),
					Position = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Text = titleText,
					TextColor3 = Color3.fromRGB(245, 240, 230),
					Font = Enum.Font.FredokaOne,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				-- Rarity badge
				New "TextLabel" {
					Name = "Rarity",
					Size = UDim2.new(1, -32, 0, 32),
					Position = UDim2.fromOffset(16, 84),
					BackgroundTransparency = 1,
					Text = rarityText,
					TextColor3 = rarityColor,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				-- Class-affinity advisory — Phase 3 upgraded to the richer
				-- advisoryFor() template ("✓ Hexers thrive with Patina Toads.
				-- Strong asset if nurtured."). Color is class-accent: gold for
				-- asset, ember for liability, gray for neutral.
				New "TextLabel" {
					Name = "Affinity",
					Size = UDim2.new(1, -32, 0, 56),
					Position = UDim2.fromOffset(16, 124),
					BackgroundTransparency = 1,
					Text = affinityText,
					TextColor3 = affinityColor,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
				},
				-- Dismiss button
				New "TextButton" {
					Name = "Awesome",
					Size = UDim2.fromOffset(180, 56),
					Position = UDim2.new(0.5, -90, 1, -76),
					BackgroundColor3 = Color3.fromRGB(200, 146, 63),  -- Brass
					Text = "Awesome",
					TextColor3 = Color3.new(0, 0, 0),
					Font = Enum.Font.FredokaOne,
					TextScaled = true,
					BorderSizePixel = 0,
					[Children] = { New "UICorner" { CornerRadius = UDim.new(0, 8) } },
					[OnEvent("Activated")] = close,
				},
			},
		},
	},
}
screenGui.Parent = playerGui

-- ── Trigger ────────────────────────────────────────────────────────────────
-- Decide if this harvest deserves the modal. Common drops fall through to
-- the existing CashHUD floating-label.
local function isRare(species: any, mutation: string?): boolean
	if mutation and mutation ~= "" then return true end
	if not species then return false end
	if species.rarity == "Mythic" then return true end
	return false
end

HarvestPopupRE.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	local speciesId = data.species
	if typeof(speciesId) ~= "string" then return end
	local species = CritterData.get(speciesId)
	if not isRare(species, data.mutation) then return end

	-- Stamp the current harvest. Reactive cells update the rendered modal.
	current:set({
		species = speciesId,
		emoji = data.emoji,
		name = data.name,
		mutation = data.mutation,
		rarity = species and species.rarity,
	})
	visible:set(true)

	-- Auto-dismiss after 4s if the player doesn't click. The check ensures
	-- we don't close a follow-up modal that opened in the meantime.
	local opened = current:get()
	task.delay(4, function()
		if current:get() == opened then close() end
	end)
end)

print("[BAB-LIFE] HarvestModal online (Fusion-driven, rare-drop trigger)")
