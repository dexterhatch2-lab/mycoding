-- Effects: tracers, muzzle flashes, impacts, explosions and sounds.
-- All client-side, so they cost the server nothing.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Effects = {}

local player = Players.LocalPlayer
local folder

local TRACER_COLOR = Color3.fromRGB(255, 220, 140)
local FLASH_COLOR = Color3.fromRGB(255, 190, 90)

local function getFolder()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "ClientFX"
		folder.Parent = workspace.CurrentCamera
	end
	return folder
end

local function basicPart(size, cframe, color, material)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = getFolder()
	return part
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------

-- Plays a sound by key from Config.Sounds.
--   where: nil (2D, heard everywhere) or a Vector3 (3D at that point)
function Effects.sound(key, where, volume, speed)
	local id = Config.Sounds[key]
	if not id or id == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = (speed or 1) * (0.95 + math.random() * 0.1)

	if typeof(where) == "Vector3" then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = where
		attachment.Parent = workspace.Terrain
		sound.RollOffMaxDistance = 400
		sound.RollOffMinDistance = 10
		sound.Parent = attachment
		sound:Play()
		Debris:AddItem(attachment, 4)
	else
		sound.Parent = getFolder()
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

---------------------------------------------------------------------------
-- Guns
---------------------------------------------------------------------------

function Effects.tracer(from, to, color)
	local offset = to - from
	local length = offset.Magnitude
	if length < 1 then
		return
	end
	local part = basicPart(
		Vector3.new(0.06, 0.06, math.min(length, 60)),
		CFrame.lookAt(from + offset.Unit * math.min(length, 60) / 2, to),
		color or TRACER_COLOR
	)
	part.Transparency = 0.2

	-- Slide the streak along the bullet path, then fade.
	local travel = math.min(0.08, length / 1500)
	TweenService:Create(part, TweenInfo.new(travel + 0.05, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(to - offset.Unit * math.min(length, 60) / 2, to + offset.Unit),
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, travel + 0.1)
end

function Effects.muzzleFlash(position, direction, scale)
	scale = scale or 1
	local cf = CFrame.lookAt(position, position + direction)
	local flash = basicPart(Vector3.new(0.35, 0.35, 0.6) * scale, cf * CFrame.new(0, 0, -0.2 * scale), FLASH_COLOR)
	flash.Shape = Enum.PartType.Ball
	flash.Transparency = 0.1

	local light = Instance.new("PointLight")
	light.Color = FLASH_COLOR
	light.Brightness = 4
	light.Range = 10 * scale
	light.Parent = flash

	local spike = basicPart(Vector3.new(0.12, 0.12, 0.9) * scale, cf * CFrame.new(0, 0, -0.45 * scale), Color3.fromRGB(255, 240, 200))
	spike.Transparency = 0.2

	Debris:AddItem(flash, 0.05)
	Debris:AddItem(spike, 0.04)
end

function Effects.impact(position, normal, flesh)
	normal = normal or Vector3.yAxis
	local color = flesh and Color3.fromRGB(190, 30, 30) or Color3.fromRGB(220, 210, 190)
	local cf = CFrame.lookAt(position, position + normal)

	local mark = basicPart(Vector3.new(0.25, 0.25, 0.05), cf, flesh and color or Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic)
	mark.Transparency = flesh and 0.2 or 0.1
	TweenService:Create(mark, TweenInfo.new(flesh and 0.3 or 4, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	Debris:AddItem(mark, flesh and 0.35 or 4.1)

	-- A few sparks / blood bits flying off the surface.
	for _ = 1, flesh and 4 or 3 do
		local spread = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.2
		local dir = (normal + spread).Unit
		local bit = basicPart(Vector3.new(0.08, 0.08, 0.08), CFrame.new(position), color)
		TweenService:Create(bit, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(position + dir * (0.8 + math.random())),
			Transparency = 1,
		}):Play()
		Debris:AddItem(bit, 0.3)
	end
end

-- Another player fired: draw tracers from their gun and play the shot.
function Effects.remoteShot(shooter, weaponId, origin, points)
	local weapon = Config.getWeapon(weaponId)
	local muzzlePosition = origin
	local character = shooter and shooter.Character
	local model = character and character:FindFirstChild("WorldWeapon")
	local handle = model and model.PrimaryPart
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if muzzle then
		muzzlePosition = muzzle.WorldPosition
	end

	for _, point in points do
		Effects.tracer(muzzlePosition, point)
		Effects.impact(point, (muzzlePosition - point).Unit, false)
	end
	local first = points[1]
	if first then
		Effects.muzzleFlash(muzzlePosition, (first - muzzlePosition).Unit, 0.8)
	end
	if weapon and weapon.Sound then
		Effects.sound(weapon.Sound, muzzlePosition, 0.9)
	end
end

function Effects.remoteMelee(attacker)
	local character = attacker and attacker.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.sound("Swing", root.Position, 0.6)
	end
end

---------------------------------------------------------------------------
-- Grenades
---------------------------------------------------------------------------

function Effects.explosion(position, radius, kind)
	if kind == "Flash" then
		local pop = basicPart(Vector3.one * 2, CFrame.new(position), Color3.new(1, 1, 1))
		pop.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Brightness = 10
		light.Range = 40
		light.Parent = pop
		TweenService:Create(pop, TweenInfo.new(0.25), { Size = Vector3.one * 10, Transparency = 1 }):Play()
		Debris:AddItem(pop, 0.3)
		Effects.sound("Hitmarker", position, 1.5, 0.5)
		return
	end

	-- Roblox Explosion for the built-in sound and particles, with no physics.
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius * 0.5
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace

	local fireball = basicPart(Vector3.one * 2, CFrame.new(position), Color3.fromRGB(255, 150, 50))
	fireball.Shape = Enum.PartType.Ball
	TweenService:Create(fireball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 1.2,
		Transparency = 1,
		Color = Color3.fromRGB(80, 60, 50),
	}):Play()
	Debris:AddItem(fireball, 0.4)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local distance = (root.Position - position).Magnitude
		Effects.onExplosionNearby(math.clamp(1 - distance / (radius * 3), 0, 1))
	end
end

-- Replaced by the client entry to shake the camera.
Effects.onExplosionNearby = function(_strength) end

function Effects.clear()
	if folder then
		folder:ClearAllChildren()
	end
end

return Effects
