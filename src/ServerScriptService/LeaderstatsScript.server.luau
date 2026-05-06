--!strict
-- LeaderstatsScript: builds player.leaderstats (Cash, Rebirths) and wires
-- DataStore load/save with auto-save loop.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- DataStore is a ModuleScript sibling. WaitForChild guards against script
-- load order races on first server boot.
local DataStore = require(ServerScriptService:WaitForChild("DataStore") :: ModuleScript)

local active: { [number]: boolean } = {}

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
	player:SetAttribute("PlantsHarvested", data.plantsHarvested or 0)
end

local function snapshot(player: Player): { [string]: any }?
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return nil end
	local cash = ls:FindFirstChild("Cash")
	local rebirths = ls:FindFirstChild("Rebirths")
	if not (cash and rebirths) then return nil end
	return {
		cash = (cash :: IntValue).Value,
		rebirths = (rebirths :: IntValue).Value,
		multiplier = player:GetAttribute("CashMultiplier") or 1,
		plotClaimed = player:GetAttribute("PlotClaimed") or false,
		plantsHarvested = player:GetAttribute("PlantsHarvested") or 0,
	}
end

Players.PlayerAdded:Connect(function(player)
	local data = DataStore.loadData(player)
	buildLeaderstats(player, data)

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
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		local snap = snapshot(player)
		if snap then
			DataStore.saveData(player, snap)
		end
	end
end)
