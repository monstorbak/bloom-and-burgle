--!strict
-- SellPad — wires `.Touched` on every SellPad-tagged BasePart.
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). Responsibility
-- is intentionally narrow: tag-watch + cooldown + EconomyPad.convert.
-- All economic logic (rate-limit, payout-cap, telemetry) is in EconomyPad.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local Critter = ServerScriptService:WaitForChild("Critter")
local EconomyPad = require(Critter:WaitForChild("EconomyPad") :: ModuleScript)

local function wireSellPad(sellPad: Instance)
	if not sellPad:IsA("BasePart") then return end
	if sellPad:GetAttribute("WiredSell") then return end
	sellPad:SetAttribute("WiredSell", true)
	print(string.format("[BAB-LIFE] wireSellPad connected: %s", sellPad:GetFullName()))
	sellPad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		if sellPad:GetAttribute("OwnerUserId") ~= player.UserId then return end
		if not EconomyPad.checkSellCooldown(player) then return end
		EconomyPad.convert(player, "sell", "touched")
	end)
end

for _, sellPad in CollectionService:GetTagged("SellPad") do wireSellPad(sellPad) end
CollectionService:GetInstanceAddedSignal("SellPad"):Connect(wireSellPad)
