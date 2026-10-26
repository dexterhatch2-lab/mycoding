-- Server entry point. Builds the map, sets up remotes and starts the match loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net) -- creates the RemoteEvents
local Util = require(Shared.Util)

local MapBuilder = require(script.MapBuilder)
local CombatServer = require(script.CombatServer)
local MatchManager = require(script.MatchManager)
local Dummies = require(script.Dummies)

Players.CharacterAutoLoads = false

MapBuilder.build()
Dummies.spawnAll(MapBuilder.getDummySpots())
CombatServer.init()

---------------------------------------------------------------------------
-- Loadouts
---------------------------------------------------------------------------

local loadouts = {} -- [Player] = { Primary = id, ... }

local function getLoadout(player)
	local loadout = loadouts[player]
	if not loadout then
		loadout = table.clone(Config.DefaultLoadout)
		loadouts[player] = loadout
	end
	return loadout
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------

local spawnTokens = {} -- [Player] = number, so stale respawn timers do nothing

local function spawnPlayer(player, cframe)
	if not player.Parent then
		return
	end
	spawnTokens[player] = (spawnTokens[player] or 0) + 1
	CombatServer.clear(player)

	player:LoadCharacter()
	local character = player.Character
	if not character then
		return
	end

	-- Stop health regen; damage should stick in a duel.
	local regen = character:FindFirstChild("Health")
	if regen and regen:IsA("Script") then
		regen:Destroy()
	end

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Movement.JumpPower
	humanoid.BreakJointsOnDeath = false

	character:PivotTo(cframe)
	CombatServer.onCharacterSpawned(player, character, getLoadout(player))

	local token = spawnTokens[player]
	humanoid.Died:Connect(function()
		if not character:GetAttribute("DeathCounted") then
			-- Died without a killer (fell off, reset). Still counts as a death.
			character:SetAttribute("DeathCounted", true)
			local stats = player:FindFirstChild("leaderstats")
			local deaths = stats and stats:FindFirstChild("Deaths")
			if deaths then
				deaths.Value += 1
			end
			Net.get("KillFeed"):FireAllClients("", player.DisplayName, "", false)
		end
		CombatServer.clear(player)

		if MatchManager.shouldRespawnInLobby(player) then
			task.wait(Config.Match.LobbyRespawnTime)
			if spawnTokens[player] == token and player.Parent and MatchManager.shouldRespawnInLobby(player) then
				spawnPlayer(player, MapBuilder.getLobbySpawn())
			end
		end
	end)
end

MatchManager.init(MapBuilder, spawnPlayer)
CombatServer.canDamage = MatchManager.canDamage

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function setupLeaderstats(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Kills", "Deaths" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Value = 0
		value.Parent = stats
	end
	stats.Parent = player
end

local function onPlayerAdded(player)
	setupLeaderstats(player)
	player.Neutral = true
	spawnPlayer(player, MapBuilder.getLobbySpawn())
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	loadouts[player] = nil
	spawnTokens[player] = nil
end)

Net.get("SetLoadout").OnServerEvent:Connect(function(player, choice)
	if typeof(choice) ~= "table" then
		return
	end
	local loadout = getLoadout(player)
	local changed = false
	for _, slot in Config.SlotOrder do
		local id = choice[slot]
		if typeof(id) == "string" and Config.isValidLoadoutChoice(slot, id) and loadout[slot] ~= id then
			loadout[slot] = id
			changed = true
		end
	end

	-- In the lobby the new loadout applies straight away.
	if changed and not MatchManager.isParticipant(player) then
		local character = player.Character
		if character and character.Parent and Util.isAlive(character) then
			CombatServer.clear(player)
			CombatServer.onCharacterSpawned(player, character, loadout)
		end
	end
end)
