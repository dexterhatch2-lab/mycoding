-- CameraFX: recoil kick, view bob, slide tilt and FOV changes.
-- Runs right after Roblox's camera update each frame.
--
-- Pitch/yaw recoil is applied as a per-frame *delta*: Roblox's camera reads
-- its own CFrame back each frame, so the kick climbs while you spray and
-- settles back down as the spring returns to zero.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Spring = require(Shared.Spring)
local Util = require(Shared.Util)

local CameraFX = {}

local player = Players.LocalPlayer

local recoil = Spring.new(Vector3.zero, 160, 18)
local applied = Vector3.zero
local shakeApplied = Vector3.zero
local shake = Spring.new(Vector3.zero, 220, 14)
local bobTime = 0
local bobAmount = 0
local roll = 0
local fov = Config.Camera.DefaultFOV

-- Kick the view by `pitch` / `yaw` degrees.
function CameraFX.kick(pitch, yaw)
	recoil.Position += Vector3.new(math.rad(pitch), math.rad(yaw), 0)
end

-- Short random shake (explosions, getting hit).
function CameraFX.shake(strength)
	local rng = Random.new()
	shake:Impulse(Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * strength)
end

-- ctx: { TargetFOV, Speed, Grounded, Sprinting, Sliding, AdsAlpha }
function CameraFX.update(dt, ctx)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- Recoil (delta so it doesn't fight mouse input).
	local offset = recoil:Update(dt)
	local delta = offset - applied
	applied = offset

	local character = player.Character
	local alive = Util.isAlive(character)

	-- View bob scales with ground speed and fades while aiming.
	local speed = ctx.Speed or 0
	local moving = alive and ctx.Grounded and speed > 1 and not ctx.Sliding
	local targetBob = 0
	if moving then
		targetBob = (ctx.Sprinting and Config.Camera.BobSprint or Config.Camera.BobWalk) * (1 - 0.85 * (ctx.AdsAlpha or 0))
	end
	bobAmount = Util.approach(bobAmount, targetBob, 10, dt)
	bobTime += dt * math.clamp(speed / 16, 0.5, 1.8) * 9

	local bobX = math.sin(bobTime * 0.5) * bobAmount
	local bobY = math.abs(math.cos(bobTime * 0.5)) * bobAmount * 0.8

	-- Lean into slides.
	roll = Util.approach(roll, ctx.Sliding and math.rad(-6) or 0, 8, dt)

	-- Shake pitch/yaw is also applied as a delta; roll is rebuilt each frame
	-- by Roblox's camera so it can be applied in full.
	local shakeOffset = shake:Update(dt) * 0.02
	local shakeDelta = shakeOffset - shakeApplied
	shakeApplied = shakeOffset

	if alive then
		camera.CFrame = camera.CFrame
			* CFrame.Angles(delta.X + shakeDelta.X, delta.Y + shakeDelta.Y, 0)
			* CFrame.new(bobX, bobY, 0)
			* CFrame.Angles(0, 0, roll + shakeOffset.Z)
	end

	fov = Util.approach(fov, ctx.TargetFOV or Config.Camera.DefaultFOV, 14, dt)
	camera.FieldOfView = fov
end

function CameraFX.reset()
	recoil:Reset(Vector3.zero)
	shake:Reset(Vector3.zero)
	applied = Vector3.zero
	shakeApplied = Vector3.zero
	roll = 0
end

return CameraFX
