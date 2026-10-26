-- Movement: sprint, crouch and slide on top of the default Roblox controls.
--   Shift        sprint (forward only, cancels aiming)
--   Ctrl / C     crouch; press while sprinting to slide

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Movement = {}

local player = Players.LocalPlayer
local M = Config.Movement

local sprintHeld = false
local crouchHeld = false
local sprinting = false
local crouching = false
local sliding = false
local slideStart = 0
local lastSlide = -10
local slideDirection = Vector3.zero
local slideVelocity
local slideAttachment
local cameraOffsetY = 0
local sprintAlpha = 0

-- Set by WeaponController each frame.
Movement.weaponSpeedMultiplier = 1
Movement.aiming = false
Movement.blockSprint = false

local function getParts()
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

local function isGrounded(humanoid)
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

local function stopSlide()
	sliding = false
	if slideVelocity then
		slideVelocity:Destroy()
		slideVelocity = nil
	end
	if slideAttachment then
		slideAttachment:Destroy()
		slideAttachment = nil
	end
end

local function startSlide(humanoid, root)
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		return
	end
	sliding = true
	slideStart = os.clock()
	lastSlide = slideStart
	slideDirection = Vector3.new(direction.X, 0, direction.Z).Unit

	slideAttachment = Instance.new("Attachment")
	slideAttachment.Name = "SlideAttachment"
	slideAttachment.Parent = root

	slideVelocity = Instance.new("LinearVelocity")
	slideVelocity.Name = "SlideVelocity"
	slideVelocity.Attachment0 = slideAttachment
	slideVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	slideVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	slideVelocity.PrimaryTangentAxis = Vector3.xAxis
	slideVelocity.SecondaryTangentAxis = Vector3.zAxis
	slideVelocity.MaxForce = 60000
	slideVelocity.PlaneVelocity = Vector2.new(slideDirection.X, slideDirection.Z) * M.SlideSpeed
	slideVelocity.Parent = root
end

function Movement.isSprinting()
	return sprinting
end

function Movement.isSliding()
	return sliding
end

function Movement.isCrouching()
	return crouching
end

function Movement.getSprintAlpha()
	return sprintAlpha
end

function Movement.cancelSprint()
	sprinting = false
end

function Movement.update(dt)
	local humanoid, root = getParts()
	if not humanoid or not root or humanoid.Health <= 0 then
		stopSlide()
		sprinting = false
		crouching = false
		return
	end

	local character = player.Character
	local frozen = character:GetAttribute("Frozen") == true
	local grounded = isGrounded(humanoid)
	local moveDirection = humanoid.MoveDirection
	local moving = moveDirection.Magnitude > 0.1

	-- Sprint only when moving roughly forward relative to the camera.
	local camera = workspace.CurrentCamera
	local forward = camera and Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z) or Vector3.zero
	local movingForward = moving and forward.Magnitude > 0 and moveDirection:Dot(forward.Unit) > 0.35

	sprinting = sprintHeld
		and movingForward
		and not crouchHeld
		and not Movement.aiming
		and not Movement.blockSprint
		and not sliding
		and not frozen

	-- Slides end on time, on jump, or when they lose ground for too long.
	if sliding then
		local elapsed = os.clock() - slideStart
		local alpha = elapsed / M.SlideDuration
		if alpha >= 1 or humanoid.Jump or not crouchHeld then
			stopSlide()
		elseif slideVelocity then
			local speed = Util.lerp(M.SlideSpeed, M.CrouchSpeed, Util.smoothstep(alpha))
			slideVelocity.PlaneVelocity = Vector2.new(slideDirection.X, slideDirection.Z) * speed
		end
	end

	crouching = crouchHeld and not sliding and grounded

	local speed = M.WalkSpeed
	if sprinting then
		speed = M.SprintSpeed
	elseif crouching or sliding then
		speed = M.CrouchSpeed
	end
	if Movement.aiming then
		speed *= 0.7
	end
	speed *= Movement.weaponSpeedMultiplier
	if frozen then
		speed = 0
	end
	humanoid.WalkSpeed = speed

	sprintAlpha = Util.approach(sprintAlpha, sprinting and 1 or 0, 10, dt)

	local targetOffset = 0
	if sliding then
		targetOffset = M.SlideCameraOffset
	elseif crouching then
		targetOffset = M.CrouchCameraOffset
	end
	cameraOffsetY = Util.approach(cameraOffsetY, targetOffset, 12, dt)
	humanoid.CameraOffset = Vector3.new(0, cameraOffsetY, 0)
end

-- Info for the camera and viewmodel.
function Movement.getContext()
	local humanoid, root = getParts()
	if not humanoid or not root then
		return { Speed = 0, Grounded = true, Sprinting = false, Sliding = false }
	end
	local velocity = root.AssemblyLinearVelocity
	return {
		Speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude,
		Grounded = isGrounded(humanoid),
		Sprinting = sprinting,
		Sliding = sliding,
		Crouching = crouching,
	}
end

function Movement.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Config.Keys.Sprint then
			sprintHeld = true
		elseif input.KeyCode == Config.Keys.Crouch or input.KeyCode == Config.Keys.CrouchAlt then
			crouchHeld = true
			local humanoid, root = getParts()
			if humanoid and root and sprinting and isGrounded(humanoid) and os.clock() - lastSlide > M.SlideCooldown then
				startSlide(humanoid, root)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Config.Keys.Sprint then
			sprintHeld = false
		elseif input.KeyCode == Config.Keys.Crouch or input.KeyCode == Config.Keys.CrouchAlt then
			crouchHeld = false
		end
	end)

	player.CharacterAdded:Connect(function()
		stopSlide()
		cameraOffsetY = 0
	end)
end

return Movement
