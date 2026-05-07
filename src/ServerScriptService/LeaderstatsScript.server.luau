--!strict
-- LeaderstatsScript: builds player.leaderstats (Cash, Rebirths) and wires
-- DataStore load/save with auto-save loop.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- DataStore is a ModuleScript sibling. WaitForChild guards against script
-- load order races on first server boot.
local DataStore = require(ServerScriptService:WaitForChild("DataStore") :: ModuleScript)

local active: { [number]: boolean } = {}

-- BAB-002: stash the loaded payload per-player so we can rebuild the plot
-- and replay plant state once PlotManager / PlantHandler are reachable. The
-- order required is exactly: DataStore.loadData → PlotManager.rebuildFromSave
-- → PlantHandler.restore. Replaying plants before the plot exists would no-op
-- because findPlanterForSlot returns nil.
local loadedData: { [number]: { [string]: any } } = {}

local function buildLeaderstats(player: Player, data: { [string]: any })
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = data.cash
	cash.Parent = ls

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.rebirths
	rebirths.Parent = ls

	player:SetAttribute("CashMultiplier", data.multiplier)
	player:SetAttribute("PlotClaimed", data.plotClaimed)
	player:SetAttribute("PlotSlotIndex", data.plotSlotIndex)
	player:SetAttribute("PlantsHarvested", data.plantsHarvested or 0)
	player:SetAttribute("MutationsFound", data.mutationsFound or 0)
	player:SetAttribute("LifetimeCash", data.lifetimeCash or 0)
	player:SetAttribute("StarterPackGranted", data.starterPackGranted or false)
end

local function snapshot(player: Player): { [string]: any }?
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return nil end
	local cash = ls:FindFirstChild("Cash")
	local rebirths = ls:FindFirstChild("Rebirths")
	if not (cash and rebirths) then return nil end

	-- Pull current plot state from PlantHandler (BAB-002). _G.PlantHandler is
	-- assigned synchronously when PlantHandler.server.luau runs; on the very
	-- first save during boot this could in theory race, so we tolerate nil.
	local plot = nil
	if _G.PlantHandler and _G.PlantHandler.snapshot then
		local ok, result = pcall(_G.PlantHandler.snapshot, player)
		if ok then plot = result end
	end

	return {
		cash = (cash :: IntValue).Value,
		rebirths = (rebirths :: IntValue).Value,
		multiplier = player:GetAttribute("CashMultiplier") or 1,
		plotClaimed = player:GetAttribute("PlotClaimed") or false,
		plotSlotIndex = player:GetAttribute("PlotSlotIndex"),
		plantsHarvested = player:GetAttribute("PlantsHarvested") or 0,
		mutationsFound = player:GetAttribute("MutationsFound") or 0,
		lifetimeCash = player:GetAttribute("LifetimeCash") or 0,
		starterPackGranted = player:GetAttribute("StarterPackGranted") or false,
		plot = plot,
	}
end

local function waitForGlobal(name: string, timeoutSeconds: number): any?
	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline do
		if _G[name] then return _G[name] end
		task.wait()
	end
	return _G[name]
end

Players.PlayerAdded:Connect(function(player)
	local data = DataStore.loadData(player)
	loadedData[player.UserId] = data
	buildLeaderstats(player, data)

	-- BAB-002 load order: rebuild plot → replay plants. Both APIs are exposed
	-- via _G by their respective server scripts; wait briefly for them in case
	-- of script load ordering on first server boot.
	-- BAB-002.1: If plotClaimed=true but plotSlotIndex is nil (legacy save from
	-- before plotSlotIndex was tracked), still rebuild — PlotManager will pick
	-- the first available slot.
	if data.plotClaimed then
		local plotManager = waitForGlobal("PlotManager", 5)
		if plotManager and plotManager.rebuildFromSave then
			local slotToTry = data.plotSlotIndex or -1  -- -1 signals "any"
			local ok, err = pcall(plotManager.rebuildFromSave, player, slotToTry)
			if not ok then
				warn(("[Leaderstats] PlotManager.rebuildFromSave failed for %s: %s"):format(player.Name, tostring(err)))
			end
		else
			warn(("[Leaderstats] PlotManager API not available; %s plot will not be rebuilt"):format(player.Name))
		end
	end

	local plantHandler = waitForGlobal("PlantHandler", 5)
	if plantHandler and plantHandler.restore then
		local ok, err = pcall(plantHandler.restore, player, data.plot, data.lastSeen)
		if not ok then
			warn(("[Leaderstats] PlantHandler.restore failed for %s: %s"):format(player.Name, tostring(err)))
		end
	end

	active[player.UserId] = true
	-- Auto-save loop
	task.spawn(function()
		while active[player.UserId] do
			task.wait(60)
			if not active[player.UserId] then break end
			local snap = snapshot(player)
			if snap then
				DataStore.saveData(player, snap)
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	active[player.UserId] = nil
	local snap = snapshot(player)
	if snap then
		DataStore.saveData(player, snap)
	end
	loadedData[player.UserId] = nil
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		local snap = snapshot(player)
		if snap then
			DataStore.saveData(player, snap)
		end
	end
end)
