--!strict
-- DevProductHandler: routes Roblox dev-product purchases to in-game effects.
-- Like gamepasses, IDs are read from Workspace attributes (BB_DEVPRODUCT_<KEY>).
-- Each handler is idempotent against the receipt's PurchaseId via DataStore.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local receiptStore = DataStoreService:GetDataStore("BloomAndBurgle_Receipts_v1")

local DEFAULT_PRODUCT_IDS = {
	GROWTH_ACCELERATOR_INSTANT = 0,    -- instant-finish all your plants
	PREMIUM_SEED_BUNDLE = 0,           -- 5x random rare seeds
	JAIL_ESCAPE_TOKEN = 0,             -- (future) escape steal jail
	LUCK_BOOST_8X = 0,                 -- 8x mutation chance for 30 min
	EXTRA_PLOT_SLOT = 0,
}

local function productId(key: string): number
	local override = Workspace:GetAttribute("BB_DEVPRODUCT_" .. key)
	if typeof(override) == "number" and override > 0 then return override end
	return DEFAULT_PRODUCT_IDS[key] or 0
end

local function findProductKey(id: number): string?
	for k, _ in DEFAULT_PRODUCT_IDS do
		if productId(k) == id then return k end
	end
	return nil
end

local function grantInstant(player: Player)
	local CS = game:GetService("CollectionService")
	for _, planter in CS:GetTagged("Planter") do
		if planter:GetAttribute("OwnerUserId") == player.UserId
			and not planter:GetAttribute("IsEmpty") then
			planter:SetAttribute("PlantedAt", 0)  -- effectively instant ripen
		end
	end
end

local function grantSeedBundle(player: Player)
	-- 5 random non-mythic seeds added to stash
	local PlantData = require(game:GetService("ReplicatedStorage").Modules.PlantData)
	local pool: { string } = {}
	for _, s in PlantData.list() do
		if s.rarity ~= "Mythic" then table.insert(pool, s.id) end
	end
	for _ = 1, 5 do
		local id = pool[math.random(1, #pool)]
		local cur = player:GetAttribute("Stash_" .. id) or 0
		player:SetAttribute("Stash_" .. id, cur + 1)
	end
end

local function grantLuckBoost(player: Player)
	-- 30 min 8x mutation chance via temporary attribute
	player:SetAttribute("LuckExpiresAt", os.time() + 1800)
	player:SetAttribute("LuckMultiplier", 8)
end

local function grantExtraPlot(player: Player)
	-- We don't currently support multi-plot; mark for future use.
	player:SetAttribute("ExtraPlots", (player:GetAttribute("ExtraPlots") or 0) + 1)
end

local HANDLERS: { [string]: (Player) -> () } = {
	GROWTH_ACCELERATOR_INSTANT = grantInstant,
	PREMIUM_SEED_BUNDLE = grantSeedBundle,
	LUCK_BOOST_8X = grantLuckBoost,
	EXTRA_PLOT_SLOT = grantExtraPlot,
}

MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local receiptKey = "rcpt_" .. info.PurchaseId
	local already = false
	local ok, _ = pcall(function()
		already = receiptStore:GetAsync(receiptKey) == true
	end)
	if ok and already then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local key = findProductKey(info.ProductId)
	if not key then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local handler = HANDLERS[key]
	if handler then
		local ok2, err = pcall(handler, player)
		if not ok2 then
			warn(("[DevProduct] handler %s failed: %s"):format(key, tostring(err)))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	-- Mark consumed
	pcall(function() receiptStore:SetAsync(receiptKey, true) end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
