-- ThirdPerson: poses other players' arms so they hold their weapon and aim
-- up/down with their camera. Uses the replicated AimPitch attribute.
-- Also hides your own third-person weapon model while in first person.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local ThirdPerson = {}

local localPlayer = Players.LocalPlayer
local defaults = setmetatable({}, { __mode = "k" }) -- [Motor6D] = original C0
local smoothedPitch = setmetatable({}, { __mode = "k" }) -- [Model] = number

local function rememberDefault(motor)
	if motor and not defaults[motor] then
		defaults[motor] = motor.C0
	end
	return motor and defaults[motor]
end

local function restore(character)
	local right, left = Util.getShoulders(character)
	for _, motor in { right, left } do
		if motor and defaults[motor] then
			motor.C0 = defaults[motor]
		end
	end
	local upperTorso = character:FindFirstChild("UpperTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist")
	if waist and defaults[waist] then
		waist.C0 = defaults[waist]
	end
end

local function pose(character, dt)
	local weaponId = character:GetAttribute("Equipped")
	local weapon = weaponId and Config.getWeapon(weaponId)
	if not weapon or not Util.isAlive(character) then
		restore(character)
		return
	end

	local target = character:GetAttribute("AimPitch") or 0
	local pitch = Util.approach(smoothedPitch[character] or target, target, 15, dt)
	smoothedPitch[character] = pitch

	local right, left, rig = Util.getShoulders(character)
	local rightDefault = rememberDefault(right)
	local leftDefault = rememberDefault(left)
	local twoHanded = weapon.Kind == "Gun"

	if rig == "R15" then
		local raise = weapon.Kind == "Melee" and math.rad(60) or math.pi / 2
		if right then
			right.C0 = rightDefault * CFrame.Angles(0, math.rad(12), 0) * CFrame.Angles(raise + pitch, 0, 0)
		end
		if left then
			if twoHanded then
				left.C0 = leftDefault * CFrame.Angles(0, math.rad(-45), 0) * CFrame.Angles(raise + pitch, 0, 0)
			else
				left.C0 = leftDefault
			end
		end
		local upperTorso = character:FindFirstChild("UpperTorso")
		local waist = upperTorso and upperTorso:FindFirstChild("Waist")
		if waist then
			local waistDefault = rememberDefault(waist)
			waist.C0 = waistDefault * CFrame.Angles(pitch * 0.4, 0, 0)
		end
	elseif rig == "R6" then
		local raise = weapon.Kind == "Melee" and math.rad(60) or math.pi / 2
		if right then
			right.C0 = rightDefault * CFrame.Angles(0, 0, raise + pitch)
		end
		if left then
			if twoHanded then
				left.C0 = leftDefault * CFrame.Angles(math.rad(-30), 0, -(raise + pitch))
			else
				left.C0 = leftDefault
			end
		end
	end
end

local function hideOwnWeapon()
	local character = localPlayer.Character
	local model = character and character:FindFirstChild("WorldWeapon")
	if not model then
		return
	end
	-- Only hide while the camera is actually in first person.
	local camera = workspace.CurrentCamera
	local head = character:FindFirstChild("Head")
	local firstPerson = head and camera and (camera.CFrame.Position - head.Position).Magnitude < 3
	local modifier = firstPerson and 1 or 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = modifier
		end
	end
end

function ThirdPerson.update(dt)
	for _, other in Players:GetPlayers() do
		if other ~= localPlayer and other.Character then
			pose(other.Character, dt)
		end
	end
	hideOwnWeapon()
end

return ThirdPerson
