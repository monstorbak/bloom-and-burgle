--!strict
-- ScrapPad — wires `.Touched` on every ScrapPad-tagged BasePart.
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). Mirror of SellPad
-- — same shape, different EconomyPad.convert kind.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local Critter = ServerScriptService:WaitForChild("Critter")
local EconomyPad = require(Critter:WaitForChild("EconomyPad") :: ModuleScript)

local function wireScrapPad(scrapPad: Instance)
	if not scrapPad:IsA("BasePart") then return end
	if scrapPad:GetAttribute("WiredScrap") then return end
	scrapPad:SetAttribute("WiredScrap", true)
	scrapPad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		if scrapPad:GetAttribute("OwnerUserId") ~= player.UserId then return end
		if not EconomyPad.checkScrapCooldown(player) then return end
		EconomyPad.convert(player, "scrap", "touched")
	end)
end

for _, scrapPad in CollectionService:GetTagged("ScrapPad") do wireScrapPad(scrapPad) end
CollectionService:GetInstanceAddedSignal("ScrapPad"):Connect(wireScrapPad)
