--!strict
-- ProximityPulse — single 4Hz loop that simulates a `.Touched` event when
-- a player's HumanoidRootPart is inside an owned sell or scrap pad.
--
-- Extracted from PlantHandler.server.luau (P1.1 / ADR-4). Why it exists
-- (BAB-FINDABILITY 3): `.Touched` is famously unreliable when a player
-- teleports / respawns into a pad, or when the character was already
-- intersecting at script-load time. The 4Hz pulse closes that gap.
--
-- The same per-player .5s cooldown tables (in EconomyPad) prevent
-- double-fires with the .Touched path.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local Critter = ServerScriptService:WaitForChild("Critter")
local EconomyPad = require(Critter:WaitForChild("EconomyPad") :: ModuleScript)

-- Cheap AABB containment in the part's local frame.
local function isInsidePart(point: Vector3, part: BasePart): boolean
	local local_p = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(local_p.X) <= half.X
		and math.abs(local_p.Y) <= half.Y
		and math.abs(local_p.Z) <= half.Z
end

local function pulseProximity()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local pos = hrp.Position

		for _, pad in CollectionService:GetTagged("SellPad") do
			if not pad:IsA("BasePart") then continue end
			if pad:GetAttribute("OwnerUserId") ~= player.UserId then continue end
			if isInsidePart(pos, pad) and EconomyPad.checkSellCooldown(player) then
				EconomyPad.convert(player, "sell", "proximity")
				break
			end
		end

		for _, pad in CollectionService:GetTagged("ScrapPad") do
			if not pad:IsA("BasePart") then continue end
			if pad:GetAttribute("OwnerUserId") ~= player.UserId then continue end
			if isInsidePart(pos, pad) and EconomyPad.checkScrapCooldown(player) then
				EconomyPad.convert(player, "scrap", "proximity")
				break
			end
		end
	end
end

task.spawn(function()
	while true do
		pulseProximity()
		task.wait(0.25)
	end
end)
print("[BAB-LIFE] Critter/ProximityPulse online (4Hz fallback for .Touched)")
