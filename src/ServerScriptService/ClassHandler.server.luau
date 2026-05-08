--!strict
-- ClassHandler: receives PickClass RemoteEvent from the client, validates the
-- chosen class, persists it on the player's "Class" attribute (auto-saved
-- by LeaderstatsScript snapshot), and applies class baselines (HP, WalkSpeed)
-- to the character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClassData"))
local PickClassRE = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("PickClass") :: RemoteEvent

local function applyClassToCharacter(player: Player, classId: string)
	local spec = ClassData.get(classId)
	if not spec then return end
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.MaxHealth = spec.combat.hp
	hum.Health = spec.combat.hp
	hum.WalkSpeed = spec.combat.speed
end

PickClassRE.OnServerEvent:Connect(function(player, classId)
	if typeof(classId) ~= "string" then return end
	local spec = ClassData.get(classId)
	if not spec then return end
	-- Once chosen, class is locked unless paid respec — silently ignore if set.
	if player:GetAttribute("Class") then return end
	player:SetAttribute("Class", classId)
	applyClassToCharacter(player, classId)
	print(string.format("[BAB-LIFE] %s picked class %s", player.Name, classId))
end)

-- On respawn, re-apply class baselines so HP/speed survive death.
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(_)
		local classId = player:GetAttribute("Class")
		if classId then
			task.wait(0.1)  -- let Humanoid initialise
			applyClassToCharacter(player, classId)
		end
	end)
end)

print("[BAB-LIFE] ClassHandler online")
