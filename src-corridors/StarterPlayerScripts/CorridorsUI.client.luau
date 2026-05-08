--!strict
-- CorridorsUI — client-side UI for the corridors place.
--
-- BAB-STEAL-CORRIDORS scaffolding (2026-05-08). v1 ships only the
-- welcome toast — the map UI shell (current room outlined, doors as
-- gold dots, click-to-snap nav) is a follow-on PR.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- ── Welcome toast ────────────────────────────────────────────────────
local function showWelcome()
	local toast = Instance.new("ScreenGui")
	toast.Name = "CorridorsWelcome"
	toast.ResetOnSpawn = false
	toast.IgnoreGuiInset = true
	toast.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.05)
	panel.Size = UDim2.fromOffset(480, 80)
	panel.BackgroundColor3 = Color3.fromRGB(40, 25, 25)
	panel.BorderSizePixel = 0
	panel.Parent = toast
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = panel
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(193, 60, 42); s.Thickness = 2; s.Parent = panel  -- ValveRed

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, -10)
	lbl.Position = UDim2.fromOffset(8, 5)
	lbl.BackgroundTransparency = 1
	lbl.Text = "🥷 You're in the Corridors. Each door leads to another player's hatchery — pick one and go thieving. Return portal is at the south wall."
	lbl.TextColor3 = Color3.fromRGB(245, 240, 230)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextWrapped = true
	lbl.Parent = panel
	local tx = Instance.new("UITextSizeConstraint"); tx.MaxTextSize = 16; tx.Parent = lbl

	-- Slide in, hold 5s, fade out.
	panel.Position = UDim2.fromScale(0.5, -0.1)
	TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.05),
	}):Play()
	task.delay(5.5, function()
		if not toast or not toast.Parent then return end
		TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, -0.1),
		}):Play()
		task.wait(0.6)
		if toast.Parent then toast:Destroy() end
	end)
end

task.delay(1.2, showWelcome)

print("[BAB-LIFE] CorridorsUI online")
