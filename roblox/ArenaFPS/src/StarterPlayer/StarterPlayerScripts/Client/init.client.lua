-- Client entry point: wires up the HUD, movement, weapons, effects,
-- third-person posing and spectating.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local HUD = require(script.HUD)
local Effects = require(script.Effects)
local Movement = require(script.Movement)
local CameraFX = require(script.CameraFX)
local WeaponController = require(script.WeaponController)
local ThirdPerson = require(script.ThirdPerson)

local player = Players.LocalPlayer

-- Hide the default backpack and health bar; we draw our own.
local function disableCoreGui()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end
task.spawn(disableCoreGui)

-- Runs a startup step; a failure is reported in Output but doesn't stop the
-- rest of the client from starting.
local function safe(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[ArenaFPS] " .. name .. " failed: " .. tostring(err))
	end
	return ok
end

safe("CameraMode", function()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end)
-- Shift is sprint, so turn off shift-lock. Not every client allows this to be
-- set from a LocalScript, hence the pcall (the place file also disables it).
safe("DevEnableMouseLock", function()
	player.DevEnableMouseLock = false
end)

safe("HUD", HUD.init)
safe("Movement", Movement.init)
safe("WeaponController", WeaponController.init)

Effects.onExplosionNearby = function(strength)
	if strength > 0 then
		CameraFX.shake(strength * 10)
	end
end

---------------------------------------------------------------------------
-- Server events
---------------------------------------------------------------------------

Net.get("ShotReplicate").OnClientEvent:Connect(Effects.remoteShot)
Net.get("MeleeReplicate").OnClientEvent:Connect(Effects.remoteMelee)
Net.get("Explosion").OnClientEvent:Connect(Effects.explosion)
Net.get("KillFeed").OnClientEvent:Connect(HUD.killFeed)
Net.get("Flash").OnClientEvent:Connect(HUD.flash)
Net.get("Announce").OnClientEvent:Connect(HUD.announce)

---------------------------------------------------------------------------
-- Match HUD
---------------------------------------------------------------------------

local matchState = Net.matchState()

local function refreshMatch()
	HUD.setMatch(
		matchState:GetAttribute("State") or "Waiting",
		matchState:GetAttribute("Round") or 0,
		matchState:GetAttribute("RedScore") or 0,
		matchState:GetAttribute("BlueScore") or 0,
		matchState:GetAttribute("TimeLeft") or 0
	)

	local state = matchState:GetAttribute("State")
	if player.Team == nil and (state == "Waiting" or state == "Intermission") then
		HUD.setHint("M Loadout  ·  1-4 / Wheel Weapons  ·  G Grenade  ·  R Reload  ·  Shift Sprint  ·  Ctrl Crouch/Slide")
	elseif player.Team == nil then
		HUD.setHint("Match in progress - you'll join the next one. Practise on the dummies.")
	else
		HUD.setHint("")
	end
end

matchState.AttributeChanged:Connect(refreshMatch)
player:GetPropertyChangedSignal("Team"):Connect(refreshMatch)
refreshMatch()

---------------------------------------------------------------------------
-- Spectating teammates after death during a round
---------------------------------------------------------------------------

local spectateTarget

local function stopSpectating()
	if spectateTarget then
		spectateTarget = nil
		HUD.setSpectating(nil)
	end
	if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if humanoid and camera.CameraSubject ~= humanoid then
		camera.CameraSubject = humanoid
	end
end

local function pickSpectateTarget()
	local fallback
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Team ~= nil and Util.isAlive(other.Character) then
			if other.Team == player.Team then
				return other
			end
			fallback = fallback or other
		end
	end
	return fallback
end

local function updateSpectate()
	local state = matchState:GetAttribute("State")
	local inRound = state == "Round" or state == "RoundStart"
	local alive = Util.isAlive(player.Character)

	if alive or not inRound or player.Team == nil then
		if spectateTarget or player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			stopSpectating()
		end
		return
	end

	if not spectateTarget or not Util.isAlive(spectateTarget.Character) then
		spectateTarget = pickSpectateTarget()
		if not spectateTarget then
			HUD.setSpectating(nil)
			return
		end
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 8
		local humanoid = spectateTarget.Character:FindFirstChildOfClass("Humanoid")
		workspace.CurrentCamera.CameraSubject = humanoid
		HUD.setSpectating(spectateTarget.DisplayName)
	end
end

player.CharacterAdded:Connect(function()
	player.CameraMinZoomDistance = 0.5
	stopSpectating()
end)

task.spawn(function()
	while true do
		updateSpectate()
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------------
-- Frame loop: after Roblox's camera has updated
---------------------------------------------------------------------------

RunService:BindToRenderStep("ArenaFPS", Enum.RenderPriority.Camera.Value + 1, function(dt)
	Movement.update(dt)
	WeaponController.update(dt)
	ThirdPerson.update(dt)
end)
