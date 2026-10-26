-- Coin Collector: a basic Roblox game in one server Script.
-- Put this Script in ServerScriptService (or Workspace) and press Play.
-- Gold coins spawn around the map; touch one to collect it. Coins respawn.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local COIN_COUNT = 20      -- coins on the map at once
local SPAWN_RADIUS = 60    -- studs from the map centre
local RESPAWN_TIME = 5     -- seconds before a collected coin comes back
local COIN_VALUE = 1       -- coins awarded per pickup
local SPIN_SPEED = 2       -- radians per second

-- Leaderboard ----------------------------------------------------------------

local function setupLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = leaderstats
end

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end

-- Coins ----------------------------------------------------------------------

local coinFolder = Instance.new("Folder")
coinFolder.Name = "Coins"
coinFolder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { coinFolder }

-- Picks a random spot and drops it onto whatever ground is below.
local function randomPosition()
	local x = math.random(-SPAWN_RADIUS, SPAWN_RADIUS)
	local z = math.random(-SPAWN_RADIUS, SPAWN_RADIUS)
	local result = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), rayParams)
	local groundY = result and result.Position.Y or 0
	return Vector3.new(x, groundY + 3, z)
end

local createCoin

local function onCoinTouched(coin, hit)
	if coin:GetAttribute("Collected") then
		return
	end

	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if not player then
		return
	end

	coin:SetAttribute("Collected", true)

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins then
		coins.Value += COIN_VALUE
	end

	coin:Destroy()
	task.delay(RESPAWN_TIME, createCoin)
end

createCoin = function()
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.5, 3, 3)
	coin.Color = Color3.fromRGB(255, 200, 0)
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	coin.CanCollide = false
	coin.CFrame = CFrame.new(randomPosition())
	coin.Touched:Connect(function(hit)
		onCoinTouched(coin, hit)
	end)
	coin.Parent = coinFolder
end

for _ = 1, COIN_COUNT do
	createCoin()
end

-- Spin every coin around the vertical axis.
RunService.Heartbeat:Connect(function(dt)
	local spin = CFrame.Angles(0, SPIN_SPEED * dt, 0)
	for _, coin in coinFolder:GetChildren() do
		local rotation = coin.CFrame - coin.Position
		coin.CFrame = CFrame.new(coin.Position) * spin * rotation
	end
end)
