--!strict
-- FriendsListHUD — slide-out HUD listing the player's Roblox friends
-- who are currently online in any BAB Hatchery server.
--
-- BAB-PHASE-4-VISIT-FRIEND-AND-TROPHY-HALL (2026-05-10).
--
-- ── How presence is computed ──────────────────────────────────────────
-- 1. On open, fetch the player's Roblox friends via Players:GetFriendsAsync
--    (works client-side; cached for 60s).
-- 2. Invoke server RemoteFunction `GetOnlinePresence` to get the
--    cross-server presence map (all players online in any BAB Hatchery).
-- 3. Intersect: render only friends who appear in the presence map.
--
-- ── Visit flow ────────────────────────────────────────────────────────
-- Click "Visit" on a friend row → fire VisitFriend RemoteEvent with
-- { targetUid }. Server validates friendship + presence, then teleports
-- via TeleportService:TeleportToPlaceInstanceAsync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
-- BAB-DESIGN-CRITIQUE Tier 1 (2026-05-10): native invite UI for the
-- empty-state CTA. SocialService is available on every Roblox client;
-- PromptGameInvite opens the platform-native friend picker.
local SocialService = game:GetService("SocialService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local VisitFriendRE = remotes:WaitForChild("VisitFriend") :: RemoteEvent
local PresenceFn = remotes:WaitForChild("GetOnlinePresence") :: RemoteFunction

-- ── Brand palette mirror ─────────────────────────────────────────────
local C = {
	Brass = Color3.fromRGB(200, 146, 63),
	OilBlack = Color3.fromRGB(26, 20, 16),
	IronworkCharcoal = Color3.fromRGB(46, 42, 42),
	SteamCream = Color3.fromRGB(242, 228, 201),
	AetherCyan = Color3.fromRGB(79, 227, 255),
	GoggleGold = Color3.fromRGB(232, 197, 71),
	SubText = Color3.fromRGB(180, 175, 165),
	DimText = Color3.fromRGB(120, 115, 110),
}

-- ── HUD root + button ────────────────────────────────────────────────
local screen = Instance.new("ScreenGui")
screen.Name = "FriendsListHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

-- Toggle button (top-left, below the cash chip / class badge — row 3).
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.AnchorPoint = Vector2.new(0, 0)
toggleBtn.Position = UDim2.fromOffset(16, 200)
toggleBtn.Size = UDim2.fromOffset(180, 44)
toggleBtn.BackgroundColor3 = C.OilBlack
toggleBtn.Text = "👋 FRIENDS"
toggleBtn.TextColor3 = C.SteamCream
toggleBtn.Font = Enum.Font.FredokaOne
toggleBtn.TextScaled = true
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = screen
local toggleCorner = Instance.new("UICorner"); toggleCorner.CornerRadius = UDim.new(0, 12); toggleCorner.Parent = toggleBtn
local toggleStroke = Instance.new("UIStroke"); toggleStroke.Color = C.Brass; toggleStroke.Thickness = 2; toggleStroke.Parent = toggleBtn
local toggleSize = Instance.new("UITextSizeConstraint"); toggleSize.MaxTextSize = 18; toggleSize.Parent = toggleBtn

-- Slide-out panel (off-screen left when closed, slides in from left).
-- BAB-DESIGN-CRITIQUE Tier 1 (2026-05-10):
--   • Lifted panel Y from 250 → 170 — high enough to clear the bottom
--     "MY WORKSHOP" / "SEED SHOP" nav buttons, low enough to clear the
--     KNIGHT class badge + cash chips at the top-left/top-right.
--   • Height kept at 460 (original) — verified to clear bottom nav with
--     16px margin at a 720p viewport.
--   • BackgroundTransparency 0.05 → 0.2 — less opaque, lets the world
--     breathe behind it.
local PANEL_OPEN_Y = 170
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.fromOffset(-340, PANEL_OPEN_Y)   -- start hidden (off-screen left)
panel.Size = UDim2.fromOffset(320, 460)
panel.BackgroundColor3 = C.OilBlack
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screen
local panelCorner = Instance.new("UICorner"); panelCorner.CornerRadius = UDim.new(0, 12); panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke"); panelStroke.Color = C.Brass; panelStroke.Thickness = 2; panelStroke.Parent = panel

-- Header — now shows a live count "👋 FRIENDS ONLINE (3)".
local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, -52, 0, 36)   -- -52 leaves room for the ✕ button
header.Position = UDim2.fromOffset(8, 8)
header.BackgroundTransparency = 1
header.Text = "👋 FRIENDS ONLINE"
header.TextColor3 = C.GoggleGold
header.Font = Enum.Font.FredokaOne
header.TextScaled = true
header.TextXAlignment = Enum.TextXAlignment.Left
header.Parent = panel
local hSize = Instance.new("UITextSizeConstraint"); hSize.MaxTextSize = 22; hSize.Parent = header

-- ✕ Close button (top-right of panel). Standard pattern; its absence
-- reads as polish-debt. Set up here, .Activated wired below alongside
-- the toggleBtn (calls the same setVisible).
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -8, 0, 8)
closeBtn.Size = UDim2.fromOffset(36, 36)
closeBtn.BackgroundColor3 = C.IronworkCharcoal
closeBtn.Text = "✕"
closeBtn.TextColor3 = C.SteamCream
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextScaled = true
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = true
closeBtn.Parent = panel
local closeCorner = Instance.new("UICorner"); closeCorner.CornerRadius = UDim.new(0, 8); closeCorner.Parent = closeBtn
local closeStroke = Instance.new("UIStroke"); closeStroke.Color = C.Brass; closeStroke.Thickness = 1; closeStroke.Parent = closeBtn
local closeTxSz = Instance.new("UITextSizeConstraint"); closeTxSz.MaxTextSize = 22; closeTxSz.Parent = closeBtn

-- Status line (loading / no-one-online / etc). Font fix: GothamItalic
-- doesn't exist as a valid Enum.Font value — was a latent crash waiting
-- for the .Text setter (status.Text was empty on init so it never fired).
local status = Instance.new("TextLabel")
status.Name = "Status"
status.Size = UDim2.new(1, -16, 0, 20)
status.Position = UDim2.fromOffset(8, 46)
status.BackgroundTransparency = 1
status.Text = ""
status.TextColor3 = C.SubText
status.Font = Enum.Font.SourceSansItalic
status.TextScaled = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = panel
local stSize = Instance.new("UITextSizeConstraint"); stSize.MaxTextSize = 14; stSize.Parent = status

-- ScrollingFrame for the friend rows. Bottom reserved for the empty-
-- state CTA card below. -240 leaves room for the 180px card + 60px
-- header band (header + status + ✕ button).
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Size = UDim2.new(1, -16, 1, -240)
list.Position = UDim2.fromOffset(8, 70)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = C.Brass
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

-- ── Empty-state CTA card (the virality engine) ───────────────────────
-- BAB-DESIGN-CRITIQUE Tier 1: when a player opens the Friends panel and
-- nobody is online, this card converts the dead-air into an invite vector.
-- Every empty-state view is potentially a k-factor lift.
local emptyCard = Instance.new("Frame")
emptyCard.Name = "EmptyCard"
emptyCard.AnchorPoint = Vector2.new(0, 1)
emptyCard.Position = UDim2.new(0, 8, 1, -8)
emptyCard.Size = UDim2.new(1, -16, 0, 180)
emptyCard.BackgroundColor3 = C.IronworkCharcoal
emptyCard.BackgroundTransparency = 0.1
emptyCard.BorderSizePixel = 0
emptyCard.Visible = false
emptyCard.Parent = panel
local ecCorner = Instance.new("UICorner"); ecCorner.CornerRadius = UDim.new(0, 10); ecCorner.Parent = emptyCard
local ecStroke = Instance.new("UIStroke"); ecStroke.Color = C.Brass; ecStroke.Thickness = 1; ecStroke.Parent = emptyCard

local ecLine1 = Instance.new("TextLabel")
ecLine1.Size = UDim2.new(1, -16, 0, 32)
ecLine1.Position = UDim2.fromOffset(8, 10)
ecLine1.BackgroundTransparency = 1
ecLine1.Text = "💤 No friends online"
ecLine1.TextColor3 = C.SteamCream
ecLine1.Font = Enum.Font.FredokaOne
ecLine1.TextScaled = true
ecLine1.TextXAlignment = Enum.TextXAlignment.Center
ecLine1.Parent = emptyCard
local ecLine1Sz = Instance.new("UITextSizeConstraint"); ecLine1Sz.MaxTextSize = 20; ecLine1Sz.Parent = ecLine1

local ecLine2 = Instance.new("TextLabel")
ecLine2.Size = UDim2.new(1, -16, 0, 38)
ecLine2.Position = UDim2.fromOffset(8, 44)
ecLine2.BackgroundTransparency = 1
ecLine2.Text = "Bring a friend — both of you\nget +25% growth for an hour."
ecLine2.TextColor3 = C.SubText
ecLine2.Font = Enum.Font.Gotham
ecLine2.TextScaled = true
ecLine2.TextWrapped = true
ecLine2.TextXAlignment = Enum.TextXAlignment.Center
ecLine2.Parent = emptyCard
local ecLine2Sz = Instance.new("UITextSizeConstraint"); ecLine2Sz.MaxTextSize = 13; ecLine2Sz.Parent = ecLine2

-- Invite button (the CTA itself). Wired below to SocialService:PromptGameInvite.
local inviteBtn = Instance.new("TextButton")
inviteBtn.Name = "InviteBtn"
inviteBtn.AnchorPoint = Vector2.new(0.5, 1)
inviteBtn.Position = UDim2.new(0.5, 0, 1, -12)
inviteBtn.Size = UDim2.new(1, -32, 0, 60)
inviteBtn.BackgroundColor3 = C.GoggleGold
inviteBtn.Text = "👋 INVITE A FRIEND"
inviteBtn.TextColor3 = C.OilBlack
inviteBtn.Font = Enum.Font.FredokaOne
inviteBtn.TextScaled = true
inviteBtn.BorderSizePixel = 0
inviteBtn.AutoButtonColor = true
inviteBtn.Parent = emptyCard
local ibCorner = Instance.new("UICorner"); ibCorner.CornerRadius = UDim.new(0, 10); ibCorner.Parent = inviteBtn
local ibStroke = Instance.new("UIStroke"); ibStroke.Color = C.Brass; ibStroke.Thickness = 2; ibStroke.Parent = inviteBtn
local ibSz = Instance.new("UITextSizeConstraint"); ibSz.MaxTextSize = 22; ibSz.Parent = inviteBtn

-- ── Friend row builder ───────────────────────────────────────────────
local function buildFriendRow(displayName: string, userId: number, class: string?, plotIndex: number?): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 60)
	row.BackgroundColor3 = C.IronworkCharcoal
	row.BorderSizePixel = 0
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.65, -8, 0, 28)
	nameLbl.Position = UDim2.fromOffset(8, 4)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = "✦ " .. displayName
	nameLbl.TextColor3 = C.SteamCream
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextScaled = true
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row
	local nSize = Instance.new("UITextSizeConstraint"); nSize.MaxTextSize = 16; nSize.Parent = nameLbl

	local subLbl = Instance.new("TextLabel")
	subLbl.Size = UDim2.new(0.65, -8, 0, 22)
	subLbl.Position = UDim2.fromOffset(8, 32)
	subLbl.BackgroundTransparency = 1
	local classBit = class and (string.upper(class:sub(1,1)) .. class:sub(2)) or "—"
	local plotBit = plotIndex and (" · Plot " .. tostring(plotIndex)) or ""
	subLbl.Text = classBit .. plotBit
	subLbl.TextColor3 = C.SubText
	subLbl.Font = Enum.Font.Gotham
	subLbl.TextScaled = true
	subLbl.TextXAlignment = Enum.TextXAlignment.Left
	subLbl.Parent = row
	local sSize = Instance.new("UITextSizeConstraint"); sSize.MaxTextSize = 13; sSize.Parent = subLbl

	-- Visit button
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.32, -8, 1, -16)
	btn.Position = UDim2.new(0.68, 0, 0, 8)
	btn.BackgroundColor3 = C.Brass
	btn.Text = "VISIT"
	btn.TextColor3 = C.OilBlack
	btn.Font = Enum.Font.FredokaOne
	btn.TextScaled = true
	btn.BorderSizePixel = 0
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = btn
	local bSize = Instance.new("UITextSizeConstraint"); bSize.MaxTextSize = 18; bSize.Parent = btn
	btn.Parent = row

	btn.Activated:Connect(function()
		btn.Text = "..."
		VisitFriendRE:FireServer({ targetUid = userId })
		-- The teleport happens server-side; if it succeeds, the player
		-- leaves this server entirely. If not, the button stays in "..."
		-- until the panel is closed/reopened. Acceptable for v1.
		task.delay(3, function()
			if btn.Parent then btn.Text = "VISIT" end
		end)
	end)

	return row
end

-- ── Roblox friends fetch (cached 60s) ────────────────────────────────
local friendsCache: { ids: { [number]: boolean }, expiresAt: number }? = nil

local function fetchRobloxFriends(): { [number]: boolean }
	local now = os.time()
	if friendsCache and friendsCache.expiresAt > now then
		return friendsCache.ids
	end
	local ids: { [number]: boolean } = {}
	local ok, pages = pcall(function() return Players:GetFriendsAsync(localPlayer.UserId) end)
	if ok and pages then
		while true do
			for _, info in pages:GetCurrentPage() do
				if typeof(info.Id) == "number" then ids[info.Id] = true end
			end
			if pages.IsFinished then break end
			pcall(function() pages:AdvanceToNextPageAsync() end)
		end
	end
	friendsCache = { ids = ids, expiresAt = now + 60 }
	return ids
end

-- ── Refresh logic ────────────────────────────────────────────────────
local function clearList()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function refresh()
	status.Text = "Loading…"
	header.Text = "👋 FRIENDS ONLINE"
	emptyCard.Visible = false
	clearList()
	-- Fetch the player's Roblox friends + the cross-server presence map.
	local friendIds = fetchRobloxFriends()
	local presence: { any } = {}
	local ok = pcall(function() presence = PresenceFn:InvokeServer() end)
	if not ok then presence = {} end
	-- Filter presence to only players the local player is friends with.
	local online: { any } = {}
	for _, entry in presence do
		if friendIds[entry.userId] then table.insert(online, entry) end
	end
	-- Sort by displayName for deterministic order.
	table.sort(online, function(a, b) return a.displayName < b.displayName end)
	-- BAB-DESIGN-CRITIQUE Tier 1: header reflects the live count, and
	-- the empty-state CTA card shows whenever no friends are online.
	header.Text = string.format("👋 FRIENDS ONLINE (%d)", #online)
	if #online == 0 then
		status.Text = ""
		emptyCard.Visible = true
		return
	end
	status.Text = string.format("%d friend%s online", #online, (#online == 1) and "" or "s")
	for i, entry in online do
		local row = buildFriendRow(entry.displayName, entry.userId, entry.class, entry.plotIndex)
		row.LayoutOrder = i
		row.Parent = list
	end
end

-- ── Slide-in / out animation ─────────────────────────────────────────
-- BAB-DESIGN-CRITIQUE Tier 1: PANEL_OPEN_Y lifted from 250 → 60 so the
-- panel no longer overlaps the bottom nav. Slide animation now uses
-- that constant on both open + close.
local visible = false
local function setVisible(v: boolean)
	if v == visible then return end
	visible = v
	if v then
		panel.Visible = true
		panel.Position = UDim2.fromOffset(-340, PANEL_OPEN_Y)
		TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(16, PANEL_OPEN_Y),
		}):Play()
		refresh()
	else
		TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(-340, PANEL_OPEN_Y),
		}):Play()
		task.delay(0.4, function() if not visible then panel.Visible = false end end)
	end
end

toggleBtn.Activated:Connect(function() setVisible(not visible) end)
closeBtn.Activated:Connect(function() setVisible(false) end)

-- BAB-DESIGN-CRITIQUE Tier 1 — virality CTA. Opens the platform-native
-- friend picker. SocialService:CanSendGameInviteAsync gates by platform
-- (some console builds return false); we render the button unconditionally
-- but show a non-crashing fallback toast in that case.
inviteBtn.Activated:Connect(function()
	-- Disable while the prompt is open to avoid double-fire.
	inviteBtn.AutoButtonColor = false
	inviteBtn.Active = false
	local canInvite = false
	pcall(function()
		canInvite = SocialService:CanSendGameInviteAsync(localPlayer)
	end)
	if canInvite then
		pcall(function() SocialService:PromptGameInvite(localPlayer) end)
	else
		-- Fallback: tell the player how to share manually. Goes to the
		-- status line so it doesn't add yet another UI surface.
		status.Text = "Invites unavailable here — share the game link manually."
	end
	task.delay(1.0, function()
		inviteBtn.AutoButtonColor = true
		inviteBtn.Active = true
	end)
end)

-- Keyboard shortcut: F5 toggles the panel (mobile-first projects often
-- skip this, but desktop dev/testing benefits).
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.F5 then
		setVisible(not visible)
	end
end)

print("[BAB-LIFE] FriendsListHUD online (toggle: 👋 FRIENDS button or F5 key, ✕ close, empty-state invite CTA)")
