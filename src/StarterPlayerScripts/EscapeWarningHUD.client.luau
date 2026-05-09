--!strict
-- EscapeWarningHUD — top-right stacked countdown for armed-escape planters.
--
-- BAB-CRITTER-ESCAPE Phase 2.B (2026-05-09).
--
-- Reads the `EscapeAt` and `EscapeArmedAt` attributes that EscapeWindow
-- (server-side) sets on each ripe planter. Pure client — no RemoteEvent
-- needed because attribute writes on Roblox BaseParts replicate to all
-- nearby clients automatically.
--
-- Per pod (owned by local player + escape-armed):
--   1. Adds an entry to the HUD stack: "🐉 Coal Drake — 1:34 to escape!"
--   2. Animates the planter's EmptyBorder color cyan → red as the timer
--      drains (cosmetic; doesn't fight server's transparency tween).
--   3. At <25% remaining, strobes the border hard.
--
-- Stack is sorted ascending by time-remaining so the most-urgent escape
-- is at the top. Mobile-first per Spec §3.1.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local CritterData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CritterData"))

-- ── Brand palette (mirror of BrandColors.luau §1.2) ──────────────────
local C = {
	OilBlack = Color3.fromRGB(26, 20, 16),
	SteamCream = Color3.fromRGB(242, 228, 201),
	AetherCyan = Color3.fromRGB(79, 227, 255),
	ValveRed = Color3.fromRGB(193, 60, 42),
	GoggleGold = Color3.fromRGB(232, 197, 71),
	EmberOrange = Color3.fromRGB(255, 106, 31),
	IronworkCharcoal = Color3.fromRGB(46, 42, 42),
}

-- ── HUD root ─────────────────────────────────────────────────────────
local screen = Instance.new("ScreenGui")
screen.Name = "EscapeWarningHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Stack"
container.AnchorPoint = Vector2.new(1, 0)
container.Position = UDim2.new(1, -16, 0, 100)   -- top-right, below cash chip
container.Size = UDim2.fromOffset(280, 600)
container.BackgroundTransparency = 1
container.Parent = screen

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.Parent = container

-- ── Per-planter entry pool ──────────────────────────────────────────
-- We re-use Frame instances across polls so we don't churn GUI nodes.
type Entry = {
	frame: Frame,
	label: TextLabel,
	stroke: UIStroke,
	planter: BasePart,
	strobePhase: number,
}

local entries: { [BasePart]: Entry } = {}

local function buildEntry(planter: BasePart): Entry
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(280, 44)
	f.BackgroundColor3 = C.OilBlack
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = f

	local stroke = Instance.new("UIStroke")
	stroke.Color = C.AetherCyan
	stroke.Thickness = 2
	stroke.Parent = f

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, -8)
	lbl.Position = UDim2.fromOffset(8, 4)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = C.SteamCream
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = ""
	lbl.Parent = f
	local maxSize = Instance.new("UITextSizeConstraint")
	maxSize.MaxTextSize = 18
	maxSize.Parent = lbl

	return { frame = f, label = lbl, stroke = stroke, planter = planter, strobePhase = 0 }
end

local function destroyEntry(entry: Entry)
	if entry.frame.Parent then entry.frame:Destroy() end
end

-- ── Format helpers ───────────────────────────────────────────────────

local function fmtRemaining(seconds: number): string
	if seconds < 0 then seconds = 0 end
	if seconds < 60 then
		return string.format("0:%02d", math.floor(seconds))
	end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds - m * 60)
	return string.format("%d:%02d", m, s)
end

local function emojiFor(speciesId: string?): string
	if not speciesId then return "🥚" end
	local s = CritterData.get(speciesId)
	return (s and s.emoji) or "🥚"
end

local function speciesNameFor(speciesId: string?): string
	if not speciesId then return "Critter" end
	local s = CritterData.get(speciesId)
	return (s and s.displayName) or speciesId
end

-- ── Aether-window color animation ────────────────────────────────────
-- Find the planter's EmptyBorder child and animate its color from cyan
-- to red as the escape timer drains. Server still owns Transparency
-- (per GrowLoop's pulse). Client-side Color3 changes don't replicate
-- but they're visible to the local player — sufficient for "your pod
-- is about to fail" feedback.

local function updateBorderColor(planter: BasePart, fractionRemaining: number, strobePhase: number)
	local border = planter:FindFirstChild("EmptyBorder")
	if not border or not border:IsA("BasePart") then return end
	-- Lerp cyan → red as timer drains. fractionRemaining = 1 → cyan; 0 → red.
	local t = 1 - math.clamp(fractionRemaining, 0, 1)
	local base = C.AetherCyan:Lerp(C.ValveRed, t)
	-- Strobe in last 25%: pulse rapidly between baseRed and ember orange.
	if fractionRemaining < 0.25 then
		local pulse = 0.5 + 0.5 * math.sin(strobePhase)
		base = base:Lerp(C.EmberOrange, pulse * 0.6)
	end
	border.Color = base
end

-- Restore the border to its default cyan when escape is no longer armed.
local function resetBorderColor(planter: BasePart)
	local border = planter:FindFirstChild("EmptyBorder")
	if not border or not border:IsA("BasePart") then return end
	border.Color = C.AetherCyan
end

-- ── Update loop ──────────────────────────────────────────────────────

local lastUpdate = 0
RunService.Heartbeat:Connect(function(_dt)
	local now = os.clock()
	if now - lastUpdate < 0.2 then return end   -- 5 Hz is plenty for a countdown
	lastUpdate = now

	local timeNow = os.time()

	-- 1. Compute armed planters owned by local player + their state.
	local armed: { { planter: BasePart, escapeAt: number, escapeArmedAt: number, speciesId: string?, totalSeconds: number, remaining: number } } = {}
	for _, planter in CollectionService:GetTagged("Planter") do
		if not planter:IsA("BasePart") then continue end
		if planter:GetAttribute("OwnerUserId") ~= localPlayer.UserId then continue end
		local escapeAt = planter:GetAttribute("EscapeAt") :: number?
		local armedAt = planter:GetAttribute("EscapeArmedAt") :: number?
		if not (escapeAt and armedAt) then continue end
		local remaining = escapeAt - timeNow
		if remaining <= 0 then continue end   -- already escaped or about to
		local total = escapeAt - armedAt
		if total <= 0 then total = 1 end
		table.insert(armed, {
			planter = planter,
			escapeAt = escapeAt,
			escapeArmedAt = armedAt,
			speciesId = planter:GetAttribute("PlantedSpecies") :: string?,
			totalSeconds = total,
			remaining = remaining,
		})
	end

	-- 2. Sort by remaining ascending (most-urgent at top).
	table.sort(armed, function(a, b) return a.remaining < b.remaining end)

	-- 3. Diff vs existing entries — destroy stale, create new, update existing.
	local seen: { [BasePart]: boolean } = {}
	for i, state in ipairs(armed) do
		seen[state.planter] = true
		local entry = entries[state.planter]
		if not entry then
			entry = buildEntry(state.planter)
			entries[state.planter] = entry
		end
		entry.frame.LayoutOrder = i
		entry.strobePhase = entry.strobePhase + 0.5

		local fraction = state.remaining / state.totalSeconds
		entry.label.Text = string.format("%s %s — %s to escape!",
			emojiFor(state.speciesId),
			speciesNameFor(state.speciesId),
			fmtRemaining(state.remaining))

		-- Stroke color tracks the same cyan→red lerp.
		local t = 1 - math.clamp(fraction, 0, 1)
		entry.stroke.Color = C.AetherCyan:Lerp(C.ValveRed, t)
		-- Strobe stroke thickness in last 25%.
		if fraction < 0.25 then
			entry.stroke.Thickness = 2 + math.abs(math.sin(entry.strobePhase)) * 2
		else
			entry.stroke.Thickness = 2
		end

		-- Tint the planter's aether window.
		updateBorderColor(state.planter, fraction, entry.strobePhase)
	end

	-- 4. Cleanup entries whose planters are no longer armed.
	for planter, entry in entries do
		if not seen[planter] then
			destroyEntry(entry)
			entries[planter] = nil
			-- Restore border color so the next plant cycle starts clean.
			resetBorderColor(planter)
		end
	end
end)

-- ── Toast on escape (driven by CritterCeremony "escape_burst") ──────
-- Phase 1's CritterCameraHooks already handles the bloom flash; we add
-- a player-facing toast describing what happened.

local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local CritterCeremonyRE = remotes:WaitForChild("CritterCeremony", 30) :: RemoteEvent?

if CritterCeremonyRE then
	local TweenService = game:GetService("TweenService")

	CritterCeremonyRE.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		if payload.type ~= "escape_burst" then return end

		local speciesName = speciesNameFor(payload.speciesId)
		local affinity = payload.affinity or "neutral"
		local behaviorName = payload.behaviorName

		local text: string
		if affinity == "liability" and behaviorName then
			text = string.format("💥 %s escaped! %s is wrecking your plot.", speciesName, behaviorName)
		elseif affinity == "asset" and behaviorName then
			text = string.format("✨ %s escaped! %s — your plot just got a boost.", speciesName, behaviorName)
		else
			text = string.format("💨 %s escaped silently. The pod is empty.", speciesName)
		end

		local toast = Instance.new("ScreenGui")
		toast.Name = "EscapeToast"
		toast.ResetOnSpawn = false
		toast.IgnoreGuiInset = true
		toast.Parent = playerGui

		local panel = Instance.new("Frame")
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.fromScale(0.5, 0.05)
		panel.Size = UDim2.fromOffset(520, 70)
		panel.BackgroundColor3 = C.OilBlack
		panel.BackgroundTransparency = 0.1
		panel.BorderSizePixel = 0
		panel.Parent = toast
		local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0, 12); cor.Parent = panel
		local stk = Instance.new("UIStroke")
		stk.Color = (affinity == "liability") and C.ValveRed or (affinity == "asset" and C.GoggleGold or C.AetherCyan)
		stk.Thickness = 2
		stk.Parent = panel

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -16, 1, -10)
		lbl.Position = UDim2.fromOffset(8, 5)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = C.SteamCream
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextWrapped = true
		lbl.Parent = panel
		local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = lbl

		-- Slide in, hold 5s, fade out.
		panel.Position = UDim2.fromScale(0.5, -0.1)
		TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.05),
		}):Play()
		task.delay(5.0, function()
			if not toast.Parent then return end
			TweenService:Create(panel, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
				Position = UDim2.fromScale(0.5, -0.1),
			}):Play()
			task.wait(0.5)
			if toast.Parent then toast:Destroy() end
		end)
	end)
end

print("[BAB-LIFE] EscapeWarningHUD online (countdown stack + aether-window strobe + toast)")
