-- WeaponModels: every weapon is built out of Parts from the definitions below,
-- so the game needs no uploaded meshes. The same definition builds both the
-- first-person viewmodel and the third-person model held by the character.
--
-- Model space: the weapon points down -Z, +Y is up, and the origin is where the
-- right hand holds it. Cylinders in Roblox run along X, so barrels use ry = 90.
--
-- Optional fields: HipOffset, AdsDistance, MagDrop (how far the Mag part moves
-- during a reload), WorldScale.
--
-- Named parts the animation code looks for:
--   Mag    - drops out during reload (guns)
--   Slide  - pistol slide blowback
--   Pump   - shotgun pump
--   Bolt   - sniper bolt
-- Attachments on the Handle:
--   Muzzle, RightGrip, LeftGrip (optional), AimPoint (guns)

local WeaponModels = {}

local METAL = Color3.fromRGB(36, 37, 41)
local GUNMETAL = Color3.fromRGB(68, 70, 76)
local STEEL = Color3.fromRGB(165, 168, 175)
local BLACK = Color3.fromRGB(18, 18, 20)
local WOOD = Color3.fromRGB(112, 70, 38)
local DARKWOOD = Color3.fromRGB(70, 42, 24)
local OLIVE = Color3.fromRGB(78, 92, 54)
local ORANGE = Color3.fromRGB(255, 132, 30)
local RED = Color3.fromRGB(220, 50, 50)
local GLASS = Color3.fromRGB(110, 200, 255)
local WRAP = Color3.fromRGB(28, 28, 60)
local GOLD = Color3.fromRGB(212, 170, 60)

local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local SMOOTH = Enum.Material.SmoothPlastic
local METALMAT = Enum.Material.Metal
local WOODMAT = Enum.Material.Wood
local NEON = Enum.Material.Neon
local GLASSMAT = Enum.Material.Glass

-- Shorthand for one part definition.
-- size (sx, sy, sz), position (x, y, z), rotation in degrees (rx, ry, rz)
local function P(name, sx, sy, sz, x, y, z, color, material, rx, ry, rz, shape)
	return {
		Name = name,
		Size = Vector3.new(sx, sy, sz),
		CFrame = CFrame.new(x, y, z)
			* CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0)),
		Color = color,
		Material = material or SMOOTH,
		Shape = shape,
	}
end

-- Cylinder along Z (length first).
local function TUBE(name, length, diameter, x, y, z, color, material)
	return P(name, length, diameter, diameter, x, y, z, color, material or METALMAT, 0, 90, 0, CYL)
end

---------------------------------------------------------------------------
-- Definitions
---------------------------------------------------------------------------

local Definitions = {}

Definitions.AssaultRifle = {
	Parts = {
		P("Receiver", 0.32, 0.42, 1.5, 0, 0.2, -0.35, METAL, METALMAT),
		P("Rail", 0.2, 0.06, 1.4, 0, 0.44, -0.4, BLACK),
		P("Handguard", 0.3, 0.3, 0.95, 0, 0.22, -1.5, GUNMETAL),
		P("HandguardVent", 0.31, 0.06, 0.8, 0, 0.3, -1.5, BLACK),
		TUBE("Barrel", 0.9, 0.12, 0, 0.24, -2.3, BLACK),
		TUBE("MuzzleBrake", 0.25, 0.17, 0, 0.24, -2.82, METAL),
		P("Stock", 0.24, 0.36, 0.85, 0, 0.12, 0.75, BLACK),
		P("StockPad", 0.26, 0.48, 0.12, 0, 0.05, 1.18, METAL),
		P("Grip", 0.2, 0.5, 0.24, 0, -0.18, 0.05, BLACK, SMOOTH, -15, 0, 0),
		P("TriggerGuard", 0.04, 0.12, 0.26, 0, -0.03, -0.14, METAL),
		P("Mag", 0.2, 0.62, 0.32, 0, -0.22, -0.75, GUNMETAL, METALMAT, 10, 0, 0),
		P("Sight", 0.14, 0.16, 0.3, 0, 0.55, -0.2, BLACK),
		P("SightLens", 0.1, 0.1, 0.03, 0, 0.58, -0.36, RED, NEON),
		P("Stripe", 0.33, 0.08, 0.5, 0, 0.3, -0.6, ORANGE),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0.24, -2.98),
		RightGrip = Vector3.new(0, -0.15, 0.05),
		LeftGrip = Vector3.new(0, 0.05, -1.55),
		AimPoint = Vector3.new(0, 0.6, -0.2),
	},
	HipOffset = CFrame.new(0.75, -0.8, -1.25),
	AdsDistance = 0.95,
	WorldScale = 0.8,
}

Definitions.SMG = {
	Parts = {
		P("Receiver", 0.3, 0.4, 1.1, 0, 0.18, -0.3, GUNMETAL, METALMAT),
		P("TopCover", 0.24, 0.08, 1.0, 0, 0.41, -0.3, BLACK),
		TUBE("Barrel", 0.5, 0.12, 0, 0.22, -1.1, BLACK),
		TUBE("Suppressor", 0.65, 0.22, 0, 0.22, -1.6, METAL),
		P("StockBar", 0.08, 0.08, 0.75, 0.08, 0.28, 0.55, STEEL, METALMAT),
		P("StockBarLow", 0.08, 0.08, 0.75, 0.08, 0.02, 0.55, STEEL, METALMAT),
		P("StockPad", 0.16, 0.38, 0.08, 0.08, 0.15, 0.94, BLACK),
		P("Grip", 0.18, 0.48, 0.22, 0, -0.17, 0.05, BLACK, SMOOTH, -12, 0, 0),
		P("Mag", 0.16, 0.72, 0.22, 0, -0.33, -0.55, BLACK, METALMAT),
		P("Foregrip", 0.14, 0.4, 0.14, 0, -0.15, -0.95, BLACK),
		P("Sight", 0.1, 0.12, 0.2, 0, 0.5, -0.25, BLACK),
		P("SightDot", 0.05, 0.05, 0.02, 0, 0.52, -0.36, GLASS, NEON),
		P("Stripe", 0.31, 0.06, 0.4, 0, 0.25, -0.65, GLASS),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0.22, -1.95),
		RightGrip = Vector3.new(0, -0.14, 0.05),
		LeftGrip = Vector3.new(0, -0.22, -0.95),
		AimPoint = Vector3.new(0, 0.54, -0.25),
	},
	HipOffset = CFrame.new(0.7, -0.78, -1.35),
	AdsDistance = 1.0,
	WorldScale = 0.8,
}

Definitions.Shotgun = {
	Parts = {
		P("Receiver", 0.3, 0.42, 1.2, 0, 0.2, -0.3, METAL, METALMAT),
		TUBE("Barrel", 1.85, 0.18, 0, 0.3, -1.75, BLACK),
		TUBE("Tube", 1.4, 0.15, 0, 0.11, -1.55, METAL),
		P("Pump", 0.26, 0.24, 0.62, 0, 0.11, -1.3, WOOD, WOODMAT),
		P("Stock", 0.26, 0.42, 1.05, 0, 0.08, 0.8, WOOD, WOODMAT, 8, 0, 0),
		P("StockPad", 0.27, 0.5, 0.1, 0, 0.0, 1.33, BLACK),
		P("Grip", 0.2, 0.45, 0.24, 0, -0.16, 0.06, WOOD, WOODMAT, -18, 0, 0),
		P("TriggerGuard", 0.04, 0.12, 0.26, 0, -0.03, -0.14, METAL),
		P("Mag", 0.2, 0.08, 0.5, 0, -0.02, -0.5, GOLD, METALMAT),
		P("Bead", 0.05, 0.06, 0.05, 0, 0.42, -2.6, ORANGE, NEON),
		P("RearSight", 0.12, 0.08, 0.06, 0, 0.44, -0.55, BLACK),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0.3, -2.72),
		RightGrip = Vector3.new(0, -0.14, 0.06),
		LeftGrip = Vector3.new(0, 0.02, -1.3),
		AimPoint = Vector3.new(0, 0.48, -0.55),
	},
	HipOffset = CFrame.new(0.75, -0.82, -1.2),
	AdsDistance = 0.9,
	MagDrop = Vector3.new(0, -0.6, 0),
	WorldScale = 0.8,
}

Definitions.Sniper = {
	Parts = {
		P("Receiver", 0.3, 0.4, 1.4, 0, 0.2, -0.2, OLIVE),
		TUBE("Barrel", 2.4, 0.14, 0, 0.25, -2.1, BLACK),
		TUBE("MuzzleBrake", 0.3, 0.2, 0, 0.25, -3.35, METAL),
		P("Stock", 0.26, 0.5, 1.3, 0, 0.05, 0.9, OLIVE),
		P("Cheek", 0.24, 0.12, 0.7, 0, 0.36, 0.85, BLACK),
		P("StockPad", 0.27, 0.6, 0.1, 0, 0.0, 1.58, BLACK),
		P("Grip", 0.2, 0.48, 0.24, 0, -0.18, 0.08, OLIVE, SMOOTH, -20, 0, 0),
		TUBE("ScopeBody", 1.3, 0.26, 0, 0.64, -0.25, BLACK),
		TUBE("ScopeFront", 0.3, 0.36, 0, 0.64, -0.95, BLACK),
		TUBE("ScopeRear", 0.25, 0.32, 0, 0.64, 0.45, BLACK),
		P("ScopeLens", 0.3, 0.3, 0.02, 0, 0.64, -1.11, GLASS, GLASSMAT),
		P("MountFront", 0.12, 0.2, 0.12, 0, 0.45, -0.6, METAL),
		P("MountRear", 0.12, 0.2, 0.12, 0, 0.45, 0.1, METAL),
		P("Bolt", 0.3, 0.08, 0.08, 0.22, 0.3, 0.25, STEEL, METALMAT),
		P("BoltKnob", 0.14, 0.14, 0.14, 0.38, 0.3, 0.25, BLACK, SMOOTH, 0, 0, 0, BALL),
		P("Mag", 0.2, 0.3, 0.42, 0, -0.08, -0.4, BLACK, METALMAT),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0.25, -3.52),
		RightGrip = Vector3.new(0, -0.15, 0.08),
		LeftGrip = Vector3.new(0, 0.05, -1.2),
		AimPoint = Vector3.new(0, 0.64, 0.6),
	},
	HipOffset = CFrame.new(0.75, -0.85, -1.15),
	AdsDistance = 0.6,
	WorldScale = 0.75,
}

Definitions.Handgun = {
	Parts = {
		P("Slide", 0.22, 0.24, 0.9, 0, 0.32, -0.35, METAL, METALMAT),
		P("SlideStripe", 0.23, 0.04, 0.6, 0, 0.36, -0.42, ORANGE),
		P("Frame", 0.2, 0.16, 0.8, 0, 0.14, -0.3, BLACK),
		P("Grip", 0.2, 0.58, 0.28, 0, -0.17, 0.05, BLACK, SMOOTH, -12, 0, 0),
		P("TriggerGuard", 0.04, 0.12, 0.24, 0, 0.0, -0.18, BLACK),
		P("Mag", 0.16, 0.5, 0.22, 0, -0.2, 0.05, GUNMETAL, METALMAT, -12, 0, 0),
		P("FrontSight", 0.04, 0.06, 0.04, 0, 0.47, -0.76, ORANGE, NEON),
		P("RearSight", 0.14, 0.06, 0.05, 0, 0.47, 0.06, BLACK),
		TUBE("BarrelTip", 0.06, 0.1, 0, 0.32, -0.81, BLACK),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0.32, -0.86),
		RightGrip = Vector3.new(0, -0.1, 0.05),
		LeftGrip = Vector3.new(-0.06, -0.24, 0.0),
		AimPoint = Vector3.new(0, 0.5, 0.06),
	},
	HipOffset = CFrame.new(0.55, -0.72, -1.55),
	AdsDistance = 1.25,
	WorldScale = 0.85,
}

Definitions.Revolver = {
	Parts = {
		P("Frame", 0.22, 0.32, 0.62, 0, 0.22, -0.15, STEEL, METALMAT),
		P("Mag", 0.4, 0.4, 0.36, 0, 0.22, -0.32, GUNMETAL, METALMAT, 0, 90, 0, CYL),
		TUBE("Barrel", 0.9, 0.16, 0, 0.32, -0.9, STEEL),
		P("BarrelRib", 0.08, 0.06, 0.9, 0, 0.42, -0.9, METAL),
		P("Grip", 0.22, 0.6, 0.28, 0, -0.18, 0.12, DARKWOOD, WOODMAT, -20, 0, 0),
		P("Hammer", 0.06, 0.12, 0.1, 0, 0.42, 0.12, METAL),
		P("TriggerGuard", 0.04, 0.12, 0.22, 0, 0.0, -0.12, STEEL),
		P("FrontSight", 0.04, 0.08, 0.05, 0, 0.47, -1.3, GOLD, NEON),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0.32, -1.37),
		RightGrip = Vector3.new(0, -0.1, 0.1),
		LeftGrip = Vector3.new(-0.06, -0.26, 0.05),
		AimPoint = Vector3.new(0, 0.48, 0.1),
	},
	HipOffset = CFrame.new(0.55, -0.72, -1.5),
	AdsDistance = 1.3,
	MagDrop = Vector3.new(-0.45, -0.05, 0),
	WorldScale = 0.85,
}

Definitions.Knife = {
	Parts = {
		P("HandlePart", 0.16, 0.18, 0.55, 0, 0, 0.02, BLACK),
		P("Guard", 0.36, 0.08, 0.06, 0, 0.02, -0.28, STEEL, METALMAT),
		P("Blade", 0.04, 0.24, 0.9, 0, 0.05, -0.76, STEEL, METALMAT),
		P("Edge", 0.045, 0.05, 0.85, 0, -0.08, -0.74, Color3.fromRGB(230, 230, 235), METALMAT),
		P("Pommel", 0.18, 0.2, 0.08, 0, 0, 0.32, ORANGE),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0.05, -1.2),
		RightGrip = Vector3.new(0, 0, 0.02),
	},
	HipOffset = CFrame.new(0.85, -0.95, -1.45) * CFrame.Angles(math.rad(10), math.rad(-8), 0),
	WorldScale = 0.9,
}

Definitions.Katana = {
	Parts = {
		P("HandlePart", 0.15, 0.15, 0.85, 0, 0, 0.15, WRAP),
		P("Tsuba", 0.42, 0.42, 0.05, 0, 0, -0.28, GOLD, METALMAT),
		P("Habaki", 0.08, 0.2, 0.1, 0, 0.02, -0.34, GOLD, METALMAT),
		P("Blade", 0.04, 0.18, 3.1, 0, 0.02, -1.92, STEEL, METALMAT),
		P("Edge", 0.045, 0.04, 3.0, 0, -0.08, -1.9, Color3.fromRGB(235, 235, 240), METALMAT),
		P("Kashira", 0.17, 0.17, 0.06, 0, 0, 0.6, GOLD, METALMAT),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0.02, -3.4),
		RightGrip = Vector3.new(0, 0, 0.1),
	},
	HipOffset = CFrame.new(0.9, -1.0, -1.4) * CFrame.Angles(math.rad(35), math.rad(-12), math.rad(-10)),
	WorldScale = 0.8,
}

Definitions.Frag = {
	Parts = {
		P("Body", 0.5, 0.55, 0.5, 0, 0, 0, OLIVE, SMOOTH, 0, 0, 0, BALL),
		P("Top", 0.2, 0.14, 0.2, 0, 0.3, 0, METAL, METALMAT),
		P("Lever", 0.06, 0.38, 0.1, 0.14, 0.15, 0, STEEL, METALMAT, 0, 0, -12),
		P("Pin", 0.14, 0.14, 0.03, -0.12, 0.34, 0, GOLD, METALMAT, 0, 0, 0, CYL),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0, 0),
		RightGrip = Vector3.new(0, -0.05, 0.05),
	},
	HipOffset = CFrame.new(0.8, -0.85, -1.5),
	WorldScale = 1,
}

Definitions.Flashbang = {
	Parts = {
		P("Body", 0.6, 0.32, 0.32, 0, 0, 0, STEEL, METALMAT, 0, 0, 90, CYL),
		P("Band", 0.12, 0.34, 0.34, 0, 0.12, 0, BLACK, SMOOTH, 0, 0, 90, CYL),
		P("Top", 0.18, 0.12, 0.18, 0, 0.36, 0, METAL, METALMAT),
		P("Lever", 0.06, 0.42, 0.1, 0.18, 0.1, 0, BLACK, SMOOTH, 0, 0, -8),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0, 0),
		RightGrip = Vector3.new(0, -0.05, 0.05),
	},
	HipOffset = CFrame.new(0.8, -0.85, -1.5),
	WorldScale = 1,
}

Definitions.Smoke = {
	Parts = {
		P("Body", 0.62, 0.34, 0.34, 0, 0, 0, Color3.fromRGB(50, 55, 50), SMOOTH, 0, 0, 90, CYL),
		P("Band", 0.1, 0.36, 0.36, 0, 0.05, 0, Color3.fromRGB(90, 220, 120), NEON, 0, 0, 90, CYL),
		P("Top", 0.18, 0.12, 0.18, 0, 0.37, 0, METAL, METALMAT),
		P("Lever", 0.06, 0.42, 0.1, 0.19, 0.1, 0, STEEL, METALMAT, 0, 0, -8),
	},
	Attachments = {
		Muzzle = Vector3.new(0, 0, 0),
		RightGrip = Vector3.new(0, -0.05, 0.05),
	},
	HipOffset = CFrame.new(0.8, -0.85, -1.5),
	WorldScale = 1,
}

WeaponModels.Definitions = Definitions

---------------------------------------------------------------------------
-- Builder
---------------------------------------------------------------------------

local function makeSafePart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- Builds a weapon model.
--   id:           weapon id from Config.Weapons
--   isViewmodel:  true for the first-person model (anchored handle, no shadows)
-- Returns model, welds (table of part name -> Weld) and the definition.
function WeaponModels.build(id, isViewmodel)
	local def = Definitions[id]
	assert(def, "No weapon model for " .. tostring(id))

	local scale = isViewmodel and 1 or (def.WorldScale or 1)

	local model = Instance.new("Model")
	model.Name = id

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CFrame = CFrame.new()
	makeSafePart(handle)
	handle.Anchored = isViewmodel == true
	handle.Parent = model

	local welds = {}

	for _, partDef in def.Parts do
		local part = Instance.new("Part")
		part.Name = partDef.Name
		part.Size = partDef.Size * scale
		part.Color = partDef.Color
		part.Material = partDef.Material
		if partDef.Shape then
			part.Shape = partDef.Shape
		end
		makeSafePart(part)
		part.CastShadow = not isViewmodel

		local offset = partDef.CFrame - partDef.CFrame.Position + partDef.CFrame.Position * scale
		part.CFrame = offset

		local weld = Instance.new("Weld")
		weld.Name = partDef.Name .. "Weld"
		weld.Part0 = handle
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = part

		part.Parent = model
		welds[partDef.Name] = weld
	end

	for name, position in def.Attachments do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = position * scale
		attachment.Parent = handle
	end

	model.PrimaryPart = handle
	return model, welds, def
end

function WeaponModels.getDefinition(id)
	return Definitions[id]
end

return WeaponModels
