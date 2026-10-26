-- Util: small helpers shared by server and client.

local Players = game:GetService("Players")

local Util = {}

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

function Util.smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 0 -> 1 over [a, b], clamped and smoothed.
function Util.ramp(t, a, b)
	if b <= a then
		return t >= b and 1 or 0
	end
	return Util.smoothstep((t - a) / (b - a))
end

-- Frame-rate independent exponential approach.
function Util.approach(current, target, speed, dt)
	return Util.lerp(current, target, 1 - math.exp(-speed * dt))
end

-- Returns a random unit vector inside a cone around `direction`.
function Util.spreadDirection(direction, degrees, rng)
	if degrees <= 0 then
		return direction.Unit
	end
	rng = rng or Random.new()
	local cf = CFrame.lookAt(Vector3.zero, direction)
	local angle = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local roll = rng:NextNumber() * math.pi * 2
	local rotated = cf * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)
	return rotated.LookVector
end

-- Finds the character model and humanoid that own `part`, if any.
function Util.getCharacterFromPart(part)
	if not part then
		return nil, nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return model, humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

function Util.isAlive(character)
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function Util.getPlayerFromCharacter(character)
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

-- True for the head and for hats/hair attached to the head.
function Util.isHead(part)
	if not part then
		return false
	end
	if part.Name == "Head" then
		return true
	end
	local accessory = part.Parent
	if accessory and accessory:IsA("Accessory") then
		local weld = part:FindFirstChild("AccessoryWeld")
		if weld and ((weld.Part0 and weld.Part0.Name == "Head") or (weld.Part1 and weld.Part1.Name == "Head")) then
			return true
		end
	end
	return false
end

-- Finds the right hand (R15) or right arm (R6).
function Util.getRightHand(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

-- Returns the right and left shoulder Motor6Ds for R15 or R6 rigs.
function Util.getShoulders(character)
	local rightUpper = character:FindFirstChild("RightUpperArm")
	local leftUpper = character:FindFirstChild("LeftUpperArm")
	if rightUpper and leftUpper then
		return rightUpper:FindFirstChild("RightShoulder"), leftUpper:FindFirstChild("LeftShoulder"), "R15"
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		return torso:FindFirstChild("Right Shoulder"), torso:FindFirstChild("Left Shoulder"), "R6"
	end
	return nil, nil, nil
end

-- Yields until `instance` has attribute `name` set (or timeout).
function Util.waitForAttribute(instance, name, timeout)
	local value = instance:GetAttribute(name)
	if value ~= nil then
		return value
	end
	local deadline = os.clock() + (timeout or 10)
	while value == nil and os.clock() < deadline and instance.Parent do
		task.wait()
		value = instance:GetAttribute(name)
	end
	return value
end

function Util.formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Util
