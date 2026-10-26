-- MatchManager: lobby -> intermission -> team rounds -> victory -> lobby.
-- Players are split into Red and Blue. Each round, the last team standing wins.
-- First team to Config.Match.RoundsToWin rounds wins the match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local MatchManager = {}

local MapBuilder
local spawnPlayer -- function(player, cframe) set by init

local matchState
local participants = {} -- [Player] = "Red" | "Blue"
local teams = {}

local RED_COLOR = Color3.fromRGB(235, 70, 70)
local BLUE_COLOR = Color3.fromRGB(70, 140, 255)

local function setState(name)
	matchState:SetAttribute("State", name)
end

function MatchManager.getState()
	return matchState:GetAttribute("State")
end

local function announce(title, subtitle, duration, color, targets)
	local remote = Net.get("Announce")
	if targets then
		for _, player in targets do
			remote:FireClient(player, title, subtitle or "", duration or 2, color)
		end
	else
		remote:FireAllClients(title, subtitle or "", duration or 2, color)
	end
end

local function createTeams()
	for _, info in { { "Red", BrickColor.new("Bright red") }, { "Blue", BrickColor.new("Bright blue") } } do
		local team = Teams:FindFirstChild(info[1])
		if not team then
			team = Instance.new("Team")
			team.Name = info[1]
			team.TeamColor = info[2]
			team.AutoAssignable = false
			team.Parent = Teams
		end
		teams[info[1]] = team
	end
end

function MatchManager.isParticipant(player)
	return participants[player] ~= nil
end

function MatchManager.getTeam(player)
	return participants[player]
end

-- Who may damage whom. Dummies can always be hit; players only during a
-- live round, and only if they are on different teams.
function MatchManager.canDamage(attacker, victimPlayer, victimCharacter)
	if victimCharacter and victimCharacter:GetAttribute("IsDummy") then
		return true
	end
	if not attacker or not victimPlayer or attacker == victimPlayer then
		return false
	end
	if MatchManager.getState() ~= "Round" then
		return false
	end
	local attackerTeam = participants[attacker]
	local victimTeam = participants[victimPlayer]
	return attackerTeam ~= nil and victimTeam ~= nil and attackerTeam ~= victimTeam
end

local function teamMembers(teamName)
	local list = {}
	for player, team in participants do
		if team == teamName and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

local function aliveCount(teamName)
	local count = 0
	for _, player in teamMembers(teamName) do
		if Util.isAlive(player.Character) then
			count += 1
		end
	end
	return count
end

local function totalHealth(teamName)
	local total = 0
	for _, player in teamMembers(teamName) do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			total += humanoid.Health
		end
	end
	return total
end

local function participantList()
	local list = {}
	for player in participants do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

local function setFrozen(player, frozen)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("Frozen", frozen)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = frozen
	end
end

local function assignTeams()
	table.clear(participants)
	local list = Players:GetPlayers()
	-- Shuffle so teams change between matches.
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	for i, player in list do
		local teamName = (i % 2 == 1) and "Red" or "Blue"
		participants[player] = teamName
		player.Team = teams[teamName]
		player.Neutral = false
	end
end

local function returnToLobby(player)
	player.Team = nil
	player.Neutral = true
	spawnPlayer(player, MapBuilder.getLobbySpawn())
end

local function bothTeamsPresent()
	return #teamMembers("Red") > 0 and #teamMembers("Blue") > 0
end

local function playRound(roundNumber)
	matchState:SetAttribute("Round", roundNumber)
	setState("RoundStart")

	-- Spawn everyone at their team's side, frozen.
	local index = { Red = 0, Blue = 0 }
	for _, player in participantList() do
		local teamName = participants[player]
		index[teamName] += 1
		spawnPlayer(player, MapBuilder.getTeamSpawn(teamName, index[teamName]))
		setFrozen(player, true)
	end

	announce("ROUND " .. roundNumber, "Get ready", Config.Match.FreezeTime - 0.2)
	for t = Config.Match.FreezeTime, 1, -1 do
		matchState:SetAttribute("TimeLeft", t)
		task.wait(1)
	end

	for _, player in participantList() do
		setFrozen(player, false)
	end
	setState("Round")
	announce("FIGHT!", "", 1)

	local deadline = os.clock() + Config.Match.RoundTime
	local winner
	while true do
		local timeLeft = deadline - os.clock()
		matchState:SetAttribute("TimeLeft", math.ceil(math.max(0, timeLeft)))

		if not bothTeamsPresent() then
			winner = #teamMembers("Red") > 0 and "Red" or "Blue"
			break
		end

		local redAlive = aliveCount("Red")
		local blueAlive = aliveCount("Blue")
		if redAlive == 0 and blueAlive == 0 then
			winner = "Draw"
			break
		elseif redAlive == 0 then
			winner = "Blue"
			break
		elseif blueAlive == 0 then
			winner = "Red"
			break
		end

		if timeLeft <= 0 then
			-- Time out: the team with more remaining health takes it.
			local redHealth, blueHealth = totalHealth("Red"), totalHealth("Blue")
			if redHealth > blueHealth then
				winner = "Red"
			elseif blueHealth > redHealth then
				winner = "Blue"
			else
				winner = "Draw"
			end
			break
		end
		task.wait(0.2)
	end

	setState("RoundEnd")
	if winner == "Red" or winner == "Blue" then
		local key = winner .. "Score"
		matchState:SetAttribute(key, matchState:GetAttribute(key) + 1)
		announce(
			string.upper(winner) .. " WINS THE ROUND",
			string.format("Red %d - %d Blue", matchState:GetAttribute("RedScore"), matchState:GetAttribute("BlueScore")),
			Config.Match.RoundEndTime - 0.5,
			winner == "Red" and RED_COLOR or BLUE_COLOR
		)
	else
		announce("DRAW", "Nobody scores", Config.Match.RoundEndTime - 0.5)
	end
	task.wait(Config.Match.RoundEndTime)
end

local function runMatch()
	assignTeams()
	matchState:SetAttribute("RedScore", 0)
	matchState:SetAttribute("BlueScore", 0)

	local round = 0
	local toWin = Config.Match.RoundsToWin
	while bothTeamsPresent()
		and matchState:GetAttribute("RedScore") < toWin
		and matchState:GetAttribute("BlueScore") < toWin
	do
		round += 1
		playRound(round)
	end

	setState("MatchEnd")
	local red, blue = matchState:GetAttribute("RedScore"), matchState:GetAttribute("BlueScore")
	local winner
	if not bothTeamsPresent() then
		winner = #teamMembers("Red") > 0 and "Red" or "Blue"
	else
		winner = red > blue and "Red" or "Blue"
	end
	local score = string.format("Red %d - %d Blue", red, blue)

	for _, player in participantList() do
		if participants[player] == winner then
			announce("VICTORY", score, Config.Match.MatchEndTime - 1, Color3.fromRGB(255, 210, 70), { player })
		else
			announce("DEFEAT", score, Config.Match.MatchEndTime - 1, Color3.fromRGB(200, 200, 200), { player })
		end
		setFrozen(player, true)
	end
	-- Spectators in the lobby get the result too.
	for _, player in Players:GetPlayers() do
		if not participants[player] then
			announce(string.upper(winner) .. " WINS", score, Config.Match.MatchEndTime - 1)
		end
	end

	task.wait(Config.Match.MatchEndTime)

	local list = participantList()
	table.clear(participants)
	for _, player in list do
		returnToLobby(player)
	end
	matchState:SetAttribute("Round", 0)
	matchState:SetAttribute("RedScore", 0)
	matchState:SetAttribute("BlueScore", 0)
end

local function loop()
	while true do
		setState("Waiting")
		while #Players:GetPlayers() < Config.Match.MinPlayers do
			matchState:SetAttribute("TimeLeft", 0)
			task.wait(1)
		end

		setState("Intermission")
		local cancelled = false
		for t = Config.Match.IntermissionTime, 1, -1 do
			matchState:SetAttribute("TimeLeft", t)
			task.wait(1)
			if #Players:GetPlayers() < Config.Match.MinPlayers then
				cancelled = true
				break
			end
		end

		if not cancelled then
			runMatch()
		end
	end
end

function MatchManager.onPlayerRemoving(player)
	participants[player] = nil
end

-- Called when a character dies. Returns true if the player should respawn
-- in the lobby (i.e. they are not in a running match).
function MatchManager.shouldRespawnInLobby(player)
	if not participants[player] then
		return true
	end
	return false
end

function MatchManager.init(mapBuilder, spawnFunction)
	MapBuilder = mapBuilder
	spawnPlayer = spawnFunction
	matchState = Net.matchState()
	createTeams()
	Players.PlayerRemoving:Connect(MatchManager.onPlayerRemoving)
	task.spawn(loop)
end

return MatchManager
