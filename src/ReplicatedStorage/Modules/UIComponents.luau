--!strict
-- UIComponents — shared brand-coherent UI primitives.
--
-- BAB-DESIGN-CRITIQUE Tier 2 (2026-05-10).
--
-- The 2026-05-10 design audit (Bloom&Burgle_Design_Critique_2026-05-10.md)
-- flagged "three competing button shapes" and "font soup" as cross-cutting
-- consistency bugs. This module is the single source of truth: every new
-- HUD element should go through one of these builders so the design
-- system stays coherent without policing it in code review.
--
-- ── Pattern ──────────────────────────────────────────────────────────
-- All builders are PURE constructors. They take an `opts` table and
-- return the constructed Instance(s). They do not parent anything; the
-- caller decides where the result lives. They do not connect events;
-- the caller wires interaction. This keeps the module testable +
-- composable.
--
-- ── Tokens ───────────────────────────────────────────────────────────
-- The font + spacing constants below are the canonical values. If the
-- design spec evolves, change them here and every dependent HUD updates.
-- DO NOT inline these values in callsites — that's how drift starts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BrandColors = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrandColors"))

local M = {}

-- ── Design tokens ────────────────────────────────────────────────────
-- Per the critique: pick TWO fonts. Fredoka(One) for HUD/UI ("we are a
-- modern game"), Antique for in-world signage ("we are a steampunk
-- world"). Anything else needs an explicit reason in code review.
M.Font = {
	-- HUD button + header text. FredokaOne is the chunky/playful variant
	-- of Fredoka — high readability at small sizes, friendly silhouette
	-- against complex backgrounds.
	HudHeading = Enum.Font.FredokaOne,
	-- Body copy + status lines + sublabels.
	HudBody = Enum.Font.Gotham,
	-- Italic body (status messages, "Loading…", empty-state hints).
	HudItalic = Enum.Font.SourceSansItalic,
	-- In-world signage (Pawn Forge plaque, Clocktower face, Trophy Hall
	-- header). Antique reads as engraved metal.
	WorldSign = Enum.Font.Antique,
}

-- Corner radius for all interactive surfaces (buttons, panels, chips).
-- 12px hits the sweet spot between sharp/industrial and soft/friendly
-- for the steampunk-Ghibli register.
M.CornerRadius = UDim.new(0, 12)

-- Stroke thickness for the canonical "this is interactive" brass border.
M.BrassStroke = 2

-- Standard interior padding so text never kisses the button edge.
M.ButtonPadding = {
	left = UDim.new(0, 10),
	right = UDim.new(0, 10),
	top = UDim.new(0, 6),
	bottom = UDim.new(0, 6),
}

-- Standard button size constraints. Min keeps fat-fingers happy on
-- mobile (Apple's 44pt floor); max keeps the design composed on 4K.
M.ButtonMinSize = Vector2.new(160, 48)
M.ButtonMaxSize = Vector2.new(280, 80)

-- ── Builders ─────────────────────────────────────────────────────────

export type ButtonOpts = {
	name: string?,
	text: string,
	-- Where the button sits in its parent. Caller-driven.
	size: UDim2?,
	anchor: Vector2?,
	position: UDim2?,
	-- Visual variant. "primary" = OilBlack body + Brass stroke (default).
	-- "accent" = filled with the accent color, used for CTAs like
	-- "INVITE A FRIEND" or "BUY PASS".
	variant: "primary" | "accent"?,
	accent: Color3?,            -- only relevant for variant="accent"
	-- Optional. If provided, applies a UITextSizeConstraint with this max.
	maxTextSize: number?,
}

-- buildButton returns a TextButton. Caller wires .Activated themselves.
function M.buildButton(opts: ButtonOpts): TextButton
	local variant = opts.variant or "primary"
	local btn = Instance.new("TextButton")
	btn.Name = opts.name or "BabButton"
	btn.Size = opts.size or UDim2.new(0, 220, 0, 70)
	btn.AnchorPoint = opts.anchor or Vector2.new(0, 0)
	if opts.position then btn.Position = opts.position end
	btn.Text = opts.text
	btn.Font = M.Font.HudHeading
	btn.TextScaled = true
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true

	if variant == "accent" then
		local fill = opts.accent or BrandColors.GoggleGold
		btn.BackgroundColor3 = fill
		btn.TextColor3 = BrandColors.OilBlack
	else
		btn.BackgroundColor3 = BrandColors.OilBlack
		btn.BackgroundTransparency = 0.05
		btn.TextColor3 = BrandColors.SteamCream
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = M.CornerRadius
	corner.Parent = btn

	-- Brass stroke = THE visual signal "this is interactive". Every
	-- button gets one, even accent-fill variants — preserves the
	-- "BAB button" silhouette across the whole game.
	local stroke = Instance.new("UIStroke")
	stroke.Color = BrandColors.Brass
	stroke.Thickness = M.BrassStroke
	stroke.Parent = btn

	local sz = Instance.new("UISizeConstraint")
	sz.MinSize = M.ButtonMinSize
	sz.MaxSize = M.ButtonMaxSize
	sz.Parent = btn

	if opts.maxTextSize then
		local tx = Instance.new("UITextSizeConstraint")
		tx.MaxTextSize = opts.maxTextSize
		tx.Parent = btn
	end

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = M.ButtonPadding.left
	pad.PaddingRight = M.ButtonPadding.right
	pad.PaddingTop = M.ButtonPadding.top
	pad.PaddingBottom = M.ButtonPadding.bottom
	pad.Parent = btn

	return btn
end

-- ── Panel ────────────────────────────────────────────────────────────
-- The standard chip/card/modal surface. Same brass+OilBlack identity as
-- buttons but with the body of a container.
export type PanelOpts = {
	name: string?,
	size: UDim2?,
	anchor: Vector2?,
	position: UDim2?,
	transparency: number?,     -- 0..1; default 0.1
	stroke: number?,            -- override M.BrassStroke if needed
}

function M.buildPanel(opts: PanelOpts): Frame
	local panel = Instance.new("Frame")
	panel.Name = opts.name or "BabPanel"
	panel.Size = opts.size or UDim2.fromOffset(320, 200)
	panel.AnchorPoint = opts.anchor or Vector2.new(0, 0)
	if opts.position then panel.Position = opts.position end
	panel.BackgroundColor3 = BrandColors.OilBlack
	panel.BackgroundTransparency = opts.transparency or 0.1
	panel.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = M.CornerRadius
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = BrandColors.Brass
	stroke.Thickness = opts.stroke or M.BrassStroke
	stroke.Parent = panel

	return panel
end

-- ── Header TextLabel ─────────────────────────────────────────────────
-- For panel titles, plaque headers, etc.
export type HeaderOpts = {
	name: string?,
	text: string,
	size: UDim2?,
	position: UDim2?,
	color: Color3?,
	maxTextSize: number?,
	alignment: Enum.TextXAlignment?,
}

function M.buildHeader(opts: HeaderOpts): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = opts.name or "BabHeader"
	lbl.Size = opts.size or UDim2.new(1, -16, 0, 36)
	if opts.position then lbl.Position = opts.position end
	lbl.BackgroundTransparency = 1
	lbl.Text = opts.text
	lbl.TextColor3 = opts.color or BrandColors.GoggleGold
	lbl.Font = M.Font.HudHeading
	lbl.TextScaled = true
	lbl.TextXAlignment = opts.alignment or Enum.TextXAlignment.Left

	if opts.maxTextSize then
		local tx = Instance.new("UITextSizeConstraint")
		tx.MaxTextSize = opts.maxTextSize
		tx.Parent = lbl
	end

	return lbl
end

-- ── Body TextLabel (for hints, status lines, sublabels) ─────────────
export type BodyOpts = {
	name: string?,
	text: string,
	size: UDim2?,
	position: UDim2?,
	color: Color3?,
	italic: boolean?,           -- if true, use HudItalic font
	maxTextSize: number?,
	alignment: Enum.TextXAlignment?,
	wrapped: boolean?,
}

function M.buildBody(opts: BodyOpts): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = opts.name or "BabBody"
	lbl.Size = opts.size or UDim2.new(1, -16, 0, 24)
	if opts.position then lbl.Position = opts.position end
	lbl.BackgroundTransparency = 1
	lbl.Text = opts.text
	lbl.TextColor3 = opts.color or BrandColors.SteamCream
	lbl.Font = opts.italic and M.Font.HudItalic or M.Font.HudBody
	lbl.TextScaled = true
	lbl.TextXAlignment = opts.alignment or Enum.TextXAlignment.Left
	if opts.wrapped then lbl.TextWrapped = true end

	if opts.maxTextSize then
		local tx = Instance.new("UITextSizeConstraint")
		tx.MaxTextSize = opts.maxTextSize
		tx.Parent = lbl
	end

	return lbl
end

-- ── World sign (SurfaceGui-friendly TextLabel) ──────────────────────
-- For Pawn Forge plates, Clocktower face, anywhere brass-engraved type
-- appears IN the world (not in HUD). Uses Antique font and dark text on
-- the assumption you're rendering against Brass-colored metal.
export type SignOpts = {
	name: string?,
	text: string,
	size: UDim2?,
	color: Color3?,
	maxTextSize: number?,
}

function M.buildWorldSign(opts: SignOpts): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = opts.name or "BabSign"
	lbl.Size = opts.size or UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = opts.text
	lbl.TextColor3 = opts.color or BrandColors.OilBlack
	lbl.Font = M.Font.WorldSign
	lbl.TextScaled = true
	lbl.TextXAlignment = Enum.TextXAlignment.Center

	if opts.maxTextSize then
		local tx = Instance.new("UITextSizeConstraint")
		tx.MaxTextSize = opts.maxTextSize
		tx.Parent = lbl
	end

	return lbl
end

return M
