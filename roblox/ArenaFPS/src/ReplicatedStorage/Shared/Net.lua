-- Net: creates (server) or finds (client) every RemoteEvent the game uses.
-- Usage: Net.get("Fire"):FireServer(...)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local RELIABLE = {
	-- client -> server
	"Equip",          -- (slot)
	"Fire",           -- (weaponId, origin, shots)
	"Reload",         -- ()
	"Melee",          -- (targetPart)
	"Throw",          -- (origin, direction)
	"SetLoadout",     -- (loadoutTable)

	-- server -> client
	"ShotReplicate",  -- (shooter, weaponId, origin, hitPoints)
	"HitConfirm",     -- (damage, headshot, killed)
	"Damaged",        -- (amount, sourcePosition)
	"KillFeed",       -- (killerName, victimName, weaponName, headshot)
	"AmmoSync",       -- (slot, mag, reserve)
	"ChargesSync",    -- (charges)
	"Explosion",      -- (position, radius)
	"Flash",          -- (intensity, duration)
	"Announce",       -- (title, subtitle, duration, color)
	"MeleeReplicate", -- (attacker)
}

local UNRELIABLE = {
	"AimPitch",       -- client -> server, sent many times per second
}

local folder
local cache = {}

if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Net"

	for _, name in RELIABLE do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		cache[name] = remote
	end

	for _, name in UNRELIABLE do
		-- UnreliableRemoteEvent is cheaper for high-frequency data.
		local ok, remote = pcall(Instance.new, "UnreliableRemoteEvent")
		if not ok then
			remote = Instance.new("RemoteEvent")
		end
		remote.Name = name
		remote.Parent = folder
		cache[name] = remote
	end

	folder.Parent = ReplicatedStorage

	-- Match state lives as attributes on this folder so clients can read it.
	local match = Instance.new("Folder")
	match.Name = "MatchState"
	match:SetAttribute("State", "Waiting")
	match:SetAttribute("Round", 0)
	match:SetAttribute("RedScore", 0)
	match:SetAttribute("BlueScore", 0)
	match:SetAttribute("TimeLeft", 0)
	match.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Net")
end

function Net.get(name)
	local remote = cache[name]
	if not remote then
		remote = folder:WaitForChild(name)
		cache[name] = remote
	end
	return remote
end

function Net.matchState()
	if RunService:IsServer() then
		return ReplicatedStorage:FindFirstChild("MatchState")
	end
	return ReplicatedStorage:WaitForChild("MatchState")
end

return Net
