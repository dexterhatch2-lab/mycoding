-- MapBuilder: builds the lobby and the duel arena out of parts at runtime,
-- so the place file works without any pre-built map.

local Lighting = game:GetService("Lighting")

local MapBuilder = {}

local LOBBY_ORIGIN = Vector3.new(0, 0, 0)
local ARENA_ORIGIN = Vector3.new(600, 0, 0)

local FLOOR = Color3.fromRGB(58, 62, 70)
local FLOOR_LINE = Color3.fromRGB(90, 96, 108)
local WALL = Color3.fromRGB(205, 208, 214)
local COVER = Color3.fromRGB(150, 156, 168)
local CRATE = Color3.fromRGB(170, 120, 70)
local RED = Color3.fromRGB(220, 60, 60)
local BLUE = Color3.fromRGB(60, 120, 230)
local TRIM = Color3.fromRGB(255, 190, 60)

local mapFolder

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Color = props.Color or COVER
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Name = props.Name or "Part"
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.CanCollide == false then
		p.CanCollide = false
	end
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent or mapFolder
	return p
end

-- A box sitting on the floor at (x, z) relative to `origin`.
local function box(parent, origin, x, z, sx, sy, sz, color, material, rotY)
	return part({
		Parent = parent,
		Size = Vector3.new(sx, sy, sz),
		CFrame = CFrame.new(origin + Vector3.new(x, sy / 2, z)) * CFrame.Angles(0, math.rad(rotY or 0), 0),
		Color = color,
		Material = material,
	})
end

-- Ramp from floor level up to `height`, running along +Z from (x, z).
local function ramp(parent, origin, x, z, width, length, height, color, rotY)
	local angle = math.atan2(height, length)
	local slant = math.sqrt(length * length + height * height)
	local base = CFrame.new(origin + Vector3.new(x, 0, z)) * CFrame.Angles(0, math.rad(rotY or 0), 0)
	return part({
		Parent = parent,
		Name = "Ramp",
		Size = Vector3.new(width, 1, slant),
		CFrame = base * CFrame.new(0, height / 2, length / 2) * CFrame.Angles(-angle, 0, 0),
		Color = color,
		Material = Enum.Material.DiamondPlate,
	})
end

local function floorGrid(parent, origin, sizeX, sizeZ, spacing)
	for x = -sizeX / 2 + spacing, sizeX / 2 - spacing, spacing do
		part({
			Parent = parent,
			Name = "GridLine",
			Size = Vector3.new(0.2, 0.05, sizeZ),
			CFrame = CFrame.new(origin + Vector3.new(x, 0.03, 0)),
			Color = FLOOR_LINE,
			CanCollide = false,
		})
	end
	for z = -sizeZ / 2 + spacing, sizeZ / 2 - spacing, spacing do
		part({
			Parent = parent,
			Name = "GridLine",
			Size = Vector3.new(sizeX, 0.05, 0.2),
			CFrame = CFrame.new(origin + Vector3.new(0, 0.03, z)),
			Color = FLOOR_LINE,
			CanCollide = false,
		})
	end
end

local function perimeter(parent, origin, sizeX, sizeZ, height, color)
	local t = 2
	box(parent, origin, 0, -sizeZ / 2 - t / 2, sizeX + t * 2, height, t, color)
	box(parent, origin, 0, sizeZ / 2 + t / 2, sizeX + t * 2, height, t, color)
	box(parent, origin, -sizeX / 2 - t / 2, 0, t, height, sizeZ, color)
	box(parent, origin, sizeX / 2 + t / 2, 0, t, height, sizeZ, color)
end

---------------------------------------------------------------------------
-- Lobby
---------------------------------------------------------------------------

local function buildLobby()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = mapFolder

	local o = LOBBY_ORIGIN
	part({
		Parent = folder,
		Name = "Floor",
		Size = Vector3.new(140, 2, 140),
		CFrame = CFrame.new(o + Vector3.new(0, -1, 0)),
		Color = FLOOR,
		Material = Enum.Material.Concrete,
	})
	floorGrid(folder, o, 140, 140, 10)
	perimeter(folder, o, 140, 140, 14, WALL)

	-- Shooting range lanes at the north end, behind the dummies.
	for i = -2, 2 do
		box(folder, o, i * 16, -62, 1, 4, 12, TRIM)
	end
	box(folder, o, 0, -68, 120, 10, 2, COVER, Enum.Material.Concrete)

	-- Some cover to practise strafing around.
	box(folder, o, -30, 10, 8, 5, 8, CRATE, Enum.Material.WoodPlanks)
	box(folder, o, 30, 10, 8, 5, 8, CRATE, Enum.Material.WoodPlanks)
	box(folder, o, 0, 25, 20, 4, 3, COVER)
	box(folder, o, -45, 35, 3, 8, 20, COVER)
	box(folder, o, 45, 35, 3, 8, 20, COVER)
	ramp(folder, o, -20, 40, 10, 16, 6, COVER)
	box(folder, o, -20, 61, 10, 6, 10, COVER)

	-- Spawn pad marker.
	part({
		Parent = folder,
		Name = "SpawnPad",
		Size = Vector3.new(16, 0.2, 16),
		CFrame = CFrame.new(o + Vector3.new(0, 0.1, 50)),
		Color = TRIM,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	return folder
end

---------------------------------------------------------------------------
-- Arena (mirrored across Z so both teams get the same layout)
---------------------------------------------------------------------------

local ARENA_X = 150
local ARENA_Z = 220

-- Cover for one half of the arena (z > 0 side). Mirrored for the other half.
-- { x, z, sizeX, height, sizeZ, kind }
local HALF_COVER = {
	{ 0, 96, 30, 6, 3, "Wall" },           -- spawn shield
	{ -40, 80, 10, 5, 10, "Crate" },
	{ 40, 80, 10, 5, 10, "Crate" },
	{ -52, 55, 3, 10, 30, "Wall" },
	{ 52, 55, 3, 10, 30, "Wall" },
	{ -20, 60, 14, 4, 4, "Low" },
	{ 20, 60, 14, 4, 4, "Low" },
	{ 0, 45, 6, 8, 6, "Pillar" },
	{ -35, 35, 8, 6, 8, "Crate" },
	{ 35, 35, 8, 6, 8, "Crate" },
	{ -55, 20, 12, 4, 4, "Low" },
	{ 55, 20, 12, 4, 4, "Low" },
	{ -15, 22, 4, 9, 14, "Wall" },
	{ 15, 22, 4, 9, 14, "Wall" },
}

local function coverStyle(kind)
	if kind == "Crate" then
		return CRATE, Enum.Material.WoodPlanks
	elseif kind == "Low" then
		return COVER, Enum.Material.Concrete
	elseif kind == "Pillar" then
		return WALL, Enum.Material.Marble
	end
	return COVER, Enum.Material.Concrete
end

local spawnCFrames = { Red = {}, Blue = {} }
local lobbySpawns = {}

local function buildArena()
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = mapFolder

	local o = ARENA_ORIGIN
	part({
		Parent = folder,
		Name = "Floor",
		Size = Vector3.new(ARENA_X, 2, ARENA_Z),
		CFrame = CFrame.new(o + Vector3.new(0, -1, 0)),
		Color = FLOOR,
		Material = Enum.Material.Concrete,
	})
	floorGrid(folder, o, ARENA_X, ARENA_Z, 10)
	perimeter(folder, o, ARENA_X, ARENA_Z, 24, WALL)

	for _, side in { 1, -1 } do
		for _, c in HALF_COVER do
			local color, material = coverStyle(c[6])
			box(folder, o, c[1], c[2] * side, c[3], c[4], c[5], color, material)
		end

		-- Team colour strip along each spawn wall.
		part({
			Parent = folder,
			Name = "TeamStrip",
			Size = Vector3.new(ARENA_X, 0.2, 6),
			CFrame = CFrame.new(o + Vector3.new(0, 0.1, (ARENA_Z / 2 - 4) * side)),
			Color = side == 1 and BLUE or RED,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})

		-- Side catwalks with ramps.
		for _, sx in { -1, 1 } do
			ramp(folder, o, 66 * sx, 60 * side, 10, 20, 8, COVER, side == 1 and 180 or 0)
			box(folder, o, 66 * sx, 30 * side, 10, 8, 22, COVER, Enum.Material.DiamondPlate)
		end
	end

	-- Centre: raised platform with ramps from both sides.
	box(folder, o, 0, 0, 24, 6, 24, WALL, Enum.Material.Marble)
	ramp(folder, o, 0, -30, 10, 18, 6, COVER)
	ramp(folder, o, 0, 30, 10, 18, 6, COVER, 180)
	box(folder, o, -10, 0, 1, 9, 24, TRIM, Enum.Material.Neon)
	box(folder, o, 10, 0, 1, 9, 24, TRIM, Enum.Material.Neon)

	-- Spawn points: Red at -Z facing +Z, Blue at +Z facing -Z.
	for i, x in { -24, -8, 8, 24, -40, 40 } do
		local redPos = o + Vector3.new(x, 3, -ARENA_Z / 2 + 8)
		local bluePos = o + Vector3.new(x, 3, ARENA_Z / 2 - 8)
		spawnCFrames.Red[i] = CFrame.lookAt(redPos, redPos + Vector3.new(0, 0, 1))
		spawnCFrames.Blue[i] = CFrame.lookAt(bluePos, bluePos + Vector3.new(0, 0, -1))
	end

	return folder
end

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(90, 90, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 130, 140)
	Lighting.GlobalShadows = true

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 1
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChild("ArenaBloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "ArenaBloom"
		bloom.Intensity = 0.6
		bloom.Size = 20
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
end

function MapBuilder.build()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end

	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace

	buildLobby()
	buildArena()
	setupLighting()

	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local pos = LOBBY_ORIGIN + Vector3.new(math.cos(angle) * 5, 3, 50 + math.sin(angle) * 5)
		lobbySpawns[i] = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
	end

	-- Folder for runtime effects (grenades, smoke) so raycasts can ignore it.
	local effects = Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = workspace

	return mapFolder
end

function MapBuilder.getTeamSpawn(teamName, index)
	local list = spawnCFrames[teamName]
	return list[((index - 1) % #list) + 1]
end

function MapBuilder.getLobbySpawn()
	return lobbySpawns[math.random(1, #lobbySpawns)]
end

-- Dummy positions in the lobby range: { position, strafes }
function MapBuilder.getDummySpots()
	local o = LOBBY_ORIGIN
	return {
		{ o + Vector3.new(-32, 3, -50), false },
		{ o + Vector3.new(-16, 3, -50), false },
		{ o + Vector3.new(0, 3, -50), true },
		{ o + Vector3.new(16, 3, -50), false },
		{ o + Vector3.new(32, 3, -50), true },
	}
end

return MapBuilder
