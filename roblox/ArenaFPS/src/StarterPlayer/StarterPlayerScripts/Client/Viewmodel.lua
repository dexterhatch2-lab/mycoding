-- Viewmodel: first-person arms + weapon, animated entirely in code.
--
-- Every frame the weapon root is placed relative to the camera, then layered
-- offsets are applied: aim-down-sights, sway, bob, recoil, sprint pose, equip,
-- reload, melee swing, throw and pump/bolt cycling. The arms are stretched from
-- fixed shoulder points to the weapon's grip attachments, so they follow every
-- animation automatically.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spring = require(Shared.Spring)
local Util = require(Shared.Util)

local Viewmodel = {}
Viewmodel.__index = Viewmodel

local player = Players.LocalPlayer

local RIGHT_SHOULDER = Vector3.new(0.95, -1.3, 0.7)
local LEFT_SHOULDER = Vector3.new(-0.95, -1.3, 0.7)
local ARM_WIDTH = 0.42
local SLEEVE_COLOR = Color3.fromRGB(32, 34, 40)
local GLOVE_COLOR = Color3.fromRGB(22, 22, 24)

local rad = math.rad
local ramp = Util.ramp

local function makeArmPart(name, color, size)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

function Viewmodel.new()
	local self = setmetatable({}, Viewmodel)

	self.Folder = Instance.new("Model")
	self.Folder.Name = "Viewmodel"

	self.RightArm = makeArmPart("RightArm", SLEEVE_COLOR, Vector3.new(ARM_WIDTH, ARM_WIDTH, 1))
	self.LeftArm = makeArmPart("LeftArm", SLEEVE_COLOR, Vector3.new(ARM_WIDTH, ARM_WIDTH, 1))
	self.RightHand = makeArmPart("RightHand", GLOVE_COLOR, Vector3.new(0.38, 0.38, 0.45))
	self.LeftHand = makeArmPart("LeftHand", GLOVE_COLOR, Vector3.new(0.38, 0.38, 0.45))
	for _, part in { self.RightArm, self.LeftArm, self.RightHand, self.LeftHand } do
		part.Parent = self.Folder
	end

	self.Sway = Spring.new(Vector3.zero, 90, 11)
	self.Recoil = Spring.new(Vector3.zero, 260, 20)     -- x: pitch, y: yaw, z: push back
	self.Landing = Spring.new(0, 140, 12)
	self.BobTime = 0
	self.BobAmount = 0
	self.Weapon = nil
	self.Visible = true
	self.SwingSide = 1

	self.Folder.Parent = workspace.CurrentCamera
	return self
end

-- Swap to a weapon built by WeaponModels.build(id, true).
function Viewmodel:setWeapon(entry)
	if self.Weapon and self.Weapon.Model then
		self.Weapon.Model.Parent = nil
	end
	self.Weapon = entry
	if entry then
		entry.Model.Parent = self.Folder
		local handle = entry.Model.PrimaryPart
		entry.Muzzle = handle:FindFirstChild("Muzzle")
		entry.RightGrip = handle:FindFirstChild("RightGrip")
		entry.LeftGrip = handle:FindFirstChild("LeftGrip")
		entry.AimPoint = handle:FindFirstChild("AimPoint")
		if not entry.BaseC0 then
			entry.BaseC0 = {}
			for name, weld in entry.Welds do
				entry.BaseC0[name] = weld.C0
			end
		end
		self:setWeaponVisible(true)
	end
end

function Viewmodel:setWeaponVisible(visible)
	if not self.Weapon then
		return
	end
	for _, part in self.Weapon.Model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Handle" then
			part.LocalTransparencyModifier = visible and 0 or 1
		end
	end
	self.WeaponHidden = not visible
end

function Viewmodel:setVisible(visible)
	self.Visible = visible
	for _, part in self.Folder:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Handle" then
			local hiddenWeaponPart = self.WeaponHidden and self.Weapon and part:IsDescendantOf(self.Weapon.Model)
			part.LocalTransparencyModifier = (visible and not hiddenWeaponPart) and 0 or 1
		end
	end
end

-- Shot feedback: push the weapon back and tilt it up.
function Viewmodel:kick(amount)
	local rng = Random.new()
	self.Recoil.Position += Vector3.new(rad(amount * 22), rad(rng:NextNumber(-1, 1) * amount * 8), amount)
end

function Viewmodel:land(amount)
	self.Landing:Impulse(amount)
end

function Viewmodel:nextSwing()
	self.SwingSide = -self.SwingSide
end

function Viewmodel:destroy()
	self.Folder:Destroy()
end

-- Rotates/translates a named weapon part relative to its rest pose.
local function poseWeld(entry, name, offset)
	local weld = entry.Welds[name]
	if weld then
		weld.C0 = entry.BaseC0[name] * offset
	end
end

local function placeArm(arm, hand, shoulder, target, visible)
	local delta = target - shoulder
	local length = delta.Magnitude
	if length < 0.05 or not visible then
		arm.LocalTransparencyModifier = 1
		hand.LocalTransparencyModifier = 1
		return
	end
	arm.LocalTransparencyModifier = 0
	hand.LocalTransparencyModifier = 0
	local direction = delta / length
	arm.Size = Vector3.new(ARM_WIDTH, ARM_WIDTH, length)
	arm.CFrame = CFrame.lookAt(shoulder + delta / 2, target)
	hand.CFrame = CFrame.lookAt(target + direction * 0.1, target + direction)
end

--[[
	anim fields (all optional):
	  Kind          "Gun" | "Melee" | "Throwable"
	  AdsAlpha      0..1
	  SprintAlpha   0..1
	  Speed         horizontal speed
	  Grounded      bool
	  EquipAlpha    0..1 (1 = fully raised)
	  ReloadAlpha   0..1 while reloading, nil otherwise
	  ShotTime      seconds since last shot
	  CycleAlpha    0..1 pump/bolt cycle after a shot, nil otherwise
	  MeleeAlpha    0..1 during a swing, nil otherwise
	  ThrowAlpha    0..1 during a throw, nil otherwise
	  Sliding       bool
	  Crouching     bool
]]
function Viewmodel:update(dt, cameraCFrame, anim)
	local entry = self.Weapon
	if not entry or not self.Visible then
		return
	end
	local def = entry.Definition
	local kind = anim.Kind or "Gun"

	-- Mouse sway: weapon lags behind camera rotation.
	local mouseDelta = UserInputService:GetMouseDelta()
	local adsAlpha = anim.AdsAlpha or 0
	local swayScale = 1 - adsAlpha * 0.8
	self.Sway.Target = Vector3.new(
		math.clamp(-mouseDelta.Y * 0.004, -0.15, 0.15),
		math.clamp(-mouseDelta.X * 0.004, -0.15, 0.15),
		math.clamp(-mouseDelta.X * 0.006, -0.2, 0.2)
	) * swayScale
	local sway = self.Sway:Update(dt)

	-- Walk bob.
	local speed = anim.Speed or 0
	local moving = anim.Grounded and speed > 1 and not anim.Sliding
	self.BobAmount = Util.approach(self.BobAmount, moving and math.clamp(speed / 16, 0, 1.6) or 0, 8, dt)
	self.BobTime += dt * math.clamp(speed / 16, 0.6, 1.8) * 9
	local bobScale = self.BobAmount * (1 - adsAlpha * 0.9)
	local bob = CFrame.new(
		math.sin(self.BobTime * 0.5) * 0.06 * bobScale,
		-math.abs(math.cos(self.BobTime * 0.5)) * 0.05 * bobScale,
		0
	) * CFrame.Angles(0, 0, math.sin(self.BobTime * 0.5) * rad(1.5) * bobScale)

	-- Idle breathing.
	local t = os.clock()
	local idle = CFrame.new(0, math.sin(t * 1.6) * 0.012 * (1 - adsAlpha), 0)
		* CFrame.Angles(math.sin(t * 1.1) * rad(0.4) * (1 - adsAlpha), 0, 0)

	local recoil = self.Recoil:Update(dt)
	local landing = self.Landing:Update(dt)

	-- Base offset: hip fire blended toward aiming down sights.
	local offset = def.HipOffset
	if kind == "Gun" and entry.AimPoint then
		local aim = entry.AimPoint.Position
		local adsOffset = CFrame.new(-aim.X, -aim.Y, -aim.Z - (def.AdsDistance or 1))
		offset = def.HipOffset:Lerp(adsOffset, Util.smoothstep(adsAlpha))
	end

	-- Crouch / slide: lower and tilt the weapon a little.
	if anim.Sliding then
		offset = CFrame.new(-0.1, 0.05, 0) * CFrame.Angles(0, 0, rad(12)) * offset
	end

	-- Sprint pose: weapon rotates across the body.
	local sprintAlpha = anim.SprintAlpha or 0
	local sprintPose
	if kind == "Gun" then
		sprintPose = CFrame.new(-0.25 * sprintAlpha, -0.2 * sprintAlpha, 0.15 * sprintAlpha)
			* CFrame.Angles(rad(-18) * sprintAlpha, rad(40) * sprintAlpha, rad(18) * sprintAlpha)
	else
		sprintPose = CFrame.new(0, -0.15 * sprintAlpha, 0.1 * sprintAlpha) * CFrame.Angles(rad(-15) * sprintAlpha, 0, 0)
	end

	-- Equip: rise up from below the screen.
	local equip = 1 - Util.smoothstep(anim.EquipAlpha or 1)
	local equipPose = CFrame.new(0.2 * equip, -1.3 * equip, 0.2 * equip) * CFrame.Angles(rad(-55) * equip, rad(15) * equip, rad(10) * equip)

	-- Recoil.
	local recoilPose = CFrame.new(0, 0, recoil.Z * (1 - adsAlpha * 0.5)) * CFrame.Angles(recoil.X, recoil.Y, 0)

	-- Reload.
	local reloadPose = CFrame.new()
	local magOffset = 0
	local leftToMag = 0
	if anim.ReloadAlpha and kind == "Gun" then
		local r = anim.ReloadAlpha
		local tilt = ramp(r, 0, 0.15) * (1 - ramp(r, 0.85, 1))
		local slap = ramp(r, 0.7, 0.75) * (1 - ramp(r, 0.75, 0.85))
		reloadPose = CFrame.new(0, -0.15 * tilt, 0.1 * tilt) * CFrame.Angles(rad(12) * tilt + rad(5) * slap, rad(-10) * tilt, rad(32) * tilt)
		magOffset = ramp(r, 0.18, 0.35) * (1 - ramp(r, 0.5, 0.72))
		leftToMag = ramp(r, 0.12, 0.25) * (1 - ramp(r, 0.72, 0.85))
	end

	-- Melee swing (alternates direction each swing).
	local meleePose = CFrame.new()
	if anim.MeleeAlpha and kind == "Melee" then
		local m = anim.MeleeAlpha
		local side = self.SwingSide
		local windup = ramp(m, 0, 0.18) * (1 - ramp(m, 0.18, 0.38))
		local slash = ramp(m, 0.18, 0.42) * (1 - ramp(m, 0.55, 1))
		meleePose = CFrame.new((0.35 * windup - 1.0 * slash) * side, 0.3 * windup - 0.15 * slash, 0.25 * windup - 0.6 * slash)
			* CFrame.Angles(rad(20 * windup - 25 * slash), rad((25 * windup + 70 * slash) * side), rad(-45 * slash * side))
	end

	-- Throw: wind up behind the head, then snap forward.
	local throwPose = CFrame.new()
	if anim.ThrowAlpha and kind == "Throwable" then
		local a = anim.ThrowAlpha
		local back = ramp(a, 0, 0.35) * (1 - ramp(a, 0.35, 0.5))
		local forward = ramp(a, 0.35, 0.5) * (1 - ramp(a, 0.6, 1))
		throwPose = CFrame.new(0.15 * back, 0.55 * back + 0.2 * forward, 0.7 * back - 0.9 * forward)
			* CFrame.Angles(rad(45 * back - 50 * forward), 0, rad(-10 * back))
	end

	local landingPose = CFrame.new(0, -landing * 0.15, 0) * CFrame.Angles(-landing * rad(4), 0, 0)
	local swayPose = CFrame.Angles(sway.X, sway.Y, sway.Z)

	local root = cameraCFrame
		* swayPose
		* offset
		* bob
		* idle
		* landingPose
		* sprintPose
		* equipPose
		* reloadPose
		* meleePose
		* throwPose
		* recoilPose

	entry.Model.PrimaryPart.CFrame = root

	-- Moving parts.
	if entry.Welds.Mag then
		local drop = def.MagDrop or Vector3.new(0, -1.5, 0.3)
		poseWeld(entry, "Mag", CFrame.new(drop * magOffset))
		entry.Welds.Mag.Part1.LocalTransparencyModifier = (magOffset > 0.7 or self.WeaponHidden) and 1 or 0
	end

	local shotTime = anim.ShotTime or 99
	if entry.Welds.Slide then
		local back = 1 - ramp(shotTime, 0.02, 0.1)
		if shotTime < 0.02 then
			back = ramp(shotTime, 0, 0.02)
		end
		poseWeld(entry, "Slide", CFrame.new(0, 0, 0.2 * back))
	end

	local pumpBack = 0
	if anim.CycleAlpha then
		local c = anim.CycleAlpha
		if entry.Welds.Pump then
			pumpBack = ramp(c, 0.1, 0.4) * (1 - ramp(c, 0.45, 0.75))
			poseWeld(entry, "Pump", CFrame.new(0, 0, 0.4 * pumpBack))
		end
		if entry.Welds.Bolt then
			local up = ramp(c, 0.15, 0.3) * (1 - ramp(c, 0.7, 0.85))
			local back = ramp(c, 0.3, 0.45) * (1 - ramp(c, 0.55, 0.7))
			poseWeld(entry, "Bolt", CFrame.new(0, 0, 0.35 * back) * CFrame.Angles(0, 0, rad(70) * up))
			if entry.Welds.BoltKnob then
				local knob = entry.BaseC0.BoltKnob
				local pivot = entry.BaseC0.Bolt
				-- Swing the knob around the bolt axis.
				local relative = pivot:Inverse() * knob
				entry.Welds.BoltKnob.C0 = pivot * CFrame.new(0, 0, 0.35 * back) * CFrame.Angles(0, 0, rad(70) * up) * relative
			end
		end
	else
		if entry.Welds.Pump then
			poseWeld(entry, "Pump", CFrame.new())
		end
		if entry.Welds.Bolt then
			poseWeld(entry, "Bolt", CFrame.new())
			if entry.Welds.BoltKnob then
				entry.Welds.BoltKnob.C0 = entry.BaseC0.BoltKnob
			end
		end
	end

	-- Arms.
	local rightShoulder = (cameraCFrame * CFrame.new(RIGHT_SHOULDER)).Position
	local leftShoulder = (cameraCFrame * CFrame.new(LEFT_SHOULDER)).Position

	local rightTarget = entry.RightGrip and entry.RightGrip.WorldPosition or root.Position
	local leftVisible = entry.LeftGrip ~= nil and not self.WeaponHidden
	local leftTarget = leftShoulder
	if entry.LeftGrip then
		leftTarget = entry.LeftGrip.WorldPosition
		if pumpBack > 0 then
			leftTarget += root.LookVector * -0.4 * pumpBack
		end
		if leftToMag > 0 and entry.Welds.Mag then
			local magPosition = entry.Welds.Mag.Part1.Position
			leftTarget = leftTarget:Lerp(magPosition, leftToMag)
		end
	end

	-- Hide the right arm too while a throwable has left the hand.
	local rightVisible = not (kind == "Throwable" and self.WeaponHidden)

	placeArm(self.RightArm, self.RightHand, rightShoulder, rightTarget, rightVisible)
	placeArm(self.LeftArm, self.LeftHand, leftShoulder, leftTarget, leftVisible)
end

function Viewmodel:getMuzzlePosition()
	local entry = self.Weapon
	if entry and entry.Muzzle then
		return entry.Muzzle.WorldPosition
	end
	local camera = workspace.CurrentCamera
	return camera.CFrame.Position + camera.CFrame.LookVector * 2
end

-- Applies the player's skin/shirt colours to the viewmodel arms.
function Viewmodel:applyCharacterColors(character)
	local arm = character:FindFirstChild("RightLowerArm") or character:FindFirstChild("Right Arm")
	local hand = character:FindFirstChild("RightHand") or arm
	if arm then
		self.RightArm.Color = arm.Color
		self.LeftArm.Color = arm.Color
	end
	if hand then
		self.RightHand.Color = hand.Color
		self.LeftHand.Color = hand.Color
	end
end

return Viewmodel
