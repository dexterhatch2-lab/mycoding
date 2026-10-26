-- WeaponController: input, firing, reloading, aiming, melee and grenades on
-- the client. Shots are raycast here for instant feedback and then sent to
-- the server, which re-checks every hit before applying damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local WeaponModels = require(Shared.WeaponModels)

local Viewmodel = require(script.Parent.Viewmodel)
local CameraFX = require(script.Parent.CameraFX)
local Movement = require(script.Parent.Movement)
local Effects = require(script.Parent.Effects)
local HUD = require(script.Parent.HUD)

local WeaponController = {}

local player = Players.LocalPlayer
local rng = Random.new()

local THROW_TIME = 0.6
local THROW_RELEASE = 0.42

local character
local humanoid
local vm
local entries = {}      -- [slot] = { Model, Welds, Definition, Id, Weapon }
local ammo = {}         -- [slot] = { Mag, Reserve }
local charges = 0
local equipped
local lastSlot = "Primary"
local active = false
local connections = {}

local equipStart = 0
local mouseDown = false
local adsHeld = false
local firedThisPress = false
local emptyClicked = false
local adsAlpha = 0
local lastFire = -10
local bloom = 0
local reloading = false
local reloadStart = 0
local meleeStart
local meleeHitDone = false
local lastMelee = -10
local throwStart
local thrown = false
local quickThrowReturn
local lastThrow = -10
local lastPitchSend = 0
local wasGrounded = true
local viewmodelShown = true
local hudKey = ""

local currentSensitivity = 1

-- Scales mouse look while aiming. Wrapped in pcall in case the property is
-- ever locked; only written when the value changes.
local function setSensitivity(value)
	if math.abs(value - currentSensitivity) < 0.005 then
		return
	end
	currentSensitivity = value
	pcall(function()
		UserInputService.MouseDeltaSensitivity = value
	end)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function now()
	return os.clock()
end

local function refreshRayParams()
	local list = { workspace.CurrentCamera }
	if character then
		table.insert(list, character)
	end
	local effects = workspace:FindFirstChild("Effects")
	if effects then
		table.insert(list, effects)
	end
	rayParams.FilterDescendantsInstances = list
end

local function currentEntry()
	return equipped and entries[equipped]
end

local function currentWeapon()
	local entry = currentEntry()
	return entry and entry.Weapon
end

local function isFrozen()
	return character ~= nil and character:GetAttribute("Frozen") == true
end

local function canAct()
	return active and not isFrozen() and not HUD.isMenuOpen()
end

local function equipAlpha()
	local weapon = currentWeapon()
	if not weapon then
		return 1
	end
	return math.clamp((now() - equipStart) / weapon.EquipTime, 0, 1)
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------

local function refreshHud(force)
	local weapon = currentWeapon()
	local slotIds = {}
	for slot, entry in entries do
		slotIds[slot] = entry.Id
	end

	local ammoState = equipped and ammo[equipped]
	local key = table.concat({
		tostring(equipped),
		tostring(ammoState and ammoState.Mag),
		tostring(ammoState and ammoState.Reserve),
		tostring(reloading),
		tostring(charges),
		tostring(slotIds.Primary),
		tostring(slotIds.Secondary),
		tostring(slotIds.Melee),
		tostring(slotIds.Utility),
	}, "|")
	if key == hudKey and not force then
		return
	end
	hudKey = key

	HUD.setSlots(slotIds, equipped, charges)
	if weapon and weapon.Kind == "Gun" and ammoState then
		HUD.setAmmo(weapon.DisplayName, ammoState.Mag, ammoState.Reserve, reloading)
	elseif weapon and weapon.Kind == "Throwable" then
		HUD.setAmmo(weapon.DisplayName, charges, 0, false)
	else
		HUD.setAmmo(weapon and weapon.DisplayName or "", nil, nil, false)
	end
end

---------------------------------------------------------------------------
-- Equip / reload
---------------------------------------------------------------------------

local function cancelReload()
	reloading = false
end

local function equip(slot)
	if not active or not entries[slot] or slot == equipped then
		return
	end
	if slot == "Utility" and charges <= 0 then
		return
	end
	if throwStart then
		return
	end

	cancelReload()
	meleeStart = nil
	if equipped and equipped ~= "Utility" then
		lastSlot = equipped
	end
	equipped = slot
	equipStart = now()
	firedThisPress = mouseDown
	vm:setWeapon(entries[slot])
	viewmodelShown = true
	vm:setVisible(true)
	Net.get("Equip"):FireServer(slot)
	Effects.sound("Equip", nil, 0.35, 1.2)
	refreshHud()
end

local function startReload()
	local weapon = currentWeapon()
	local ammoState = equipped and ammo[equipped]
	if not active or not weapon or weapon.Kind ~= "Gun" or not ammoState then
		return
	end
	if reloading or ammoState.Mag >= weapon.MagSize or ammoState.Reserve <= 0 then
		return
	end
	reloading = true
	reloadStart = now()
	Net.get("Reload"):FireServer()
	Effects.sound("Reload", nil, 0.5)
	refreshHud()
end

local function finishReload()
	local weapon = currentWeapon()
	local ammoState = equipped and ammo[equipped]
	reloading = false
	if weapon and ammoState then
		local amount = math.min(weapon.MagSize - ammoState.Mag, ammoState.Reserve)
		ammoState.Mag += amount
		ammoState.Reserve -= amount
	end
	refreshHud()
end

---------------------------------------------------------------------------
-- Guns
---------------------------------------------------------------------------

local function currentSpread(weapon, ctx)
	if not weapon or weapon.Kind ~= "Gun" then
		return 0
	end
	local spread = Util.lerp(weapon.Spread.Hip, weapon.Spread.Ads, adsAlpha)
	local moveFactor = math.clamp((ctx.Speed or 0) / Config.Movement.WalkSpeed, 0, 1.5)
	spread += weapon.Spread.Move * moveFactor * (1 - adsAlpha * 0.5)
	if not ctx.Grounded then
		spread += weapon.Spread.Air
	end
	if ctx.Crouching then
		spread *= 0.8
	end
	return spread + bloom
end

local function fireGun(weapon, ctx)
	local entry = currentEntry()
	local ammoState = ammo[equipped]
	local camera = workspace.CurrentCamera
	local cameraCFrame = camera.CFrame
	local origin = cameraCFrame.Position
	local spread = currentSpread(weapon, ctx)

	refreshRayParams()
	local muzzle = vm:getMuzzlePosition()
	local shots = {}

	for i = 1, weapon.Pellets do
		local direction = Util.spreadDirection(cameraCFrame.LookVector, spread, rng)
		local result = workspace:Raycast(origin, direction * weapon.Range, rayParams)
		local position = result and result.Position or (origin + direction * weapon.Range)
		local part = result and result.Instance
		shots[i] = { Position = position, Part = part }

		local _, hitHumanoid = Util.getCharacterFromPart(part)
		Effects.tracer(muzzle, position)
		if result then
			Effects.impact(position, result.Normal, hitHumanoid ~= nil)
		end
	end

	Net.get("Fire"):FireServer(entry.Id, origin, shots)

	ammoState.Mag -= 1
	lastFire = now()
	firedThisPress = true
	bloom = math.min(bloom + weapon.Recoil.Pitch * 0.35, 4)

	local adsRecoil = 1 - adsAlpha * 0.35
	CameraFX.kick(weapon.Recoil.Pitch * adsRecoil, rng:NextNumber(-1, 1) * weapon.Recoil.Yaw * adsRecoil)
	vm:kick(weapon.Recoil.Kick)
	Effects.muzzleFlash(muzzle, cameraCFrame.LookVector, weapon.Pellets > 1 and 1.4 or 1)
	Effects.sound(weapon.Sound, nil, 0.7)
	refreshHud()
end

local function updateGun(weapon, ctx)
	local ammoState = ammo[equipped]
	if not ammoState then
		return
	end
	local t = now()
	local interval = 60 / weapon.RPM

	if reloading then
		if t - reloadStart >= weapon.ReloadTime then
			finishReload()
		end
		return
	end

	if mouseDown and canAct() and equipAlpha() >= 1 then
		if ctx.Sprinting then
			Movement.cancelSprint()
		end
		local readyForShot = weapon.FireMode == "Auto" or not firedThisPress
		if readyForShot and t - lastFire >= interval then
			if ammoState.Mag > 0 then
				fireGun(weapon, ctx)
			elseif not emptyClicked then
				emptyClicked = true
				Effects.sound("Empty", nil, 0.4, 0.6)
				startReload()
			end
		end
	end

	-- Auto-reload once the last shot has finished cycling.
	if ammoState.Mag <= 0 and t - lastFire >= interval and not reloading then
		startReload()
	end
end

---------------------------------------------------------------------------
-- Melee
---------------------------------------------------------------------------

local function doMeleeHit(weapon)
	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * weapon.Range
	refreshRayParams()

	local result = workspace:Spherecast(origin, 1.2, direction, rayParams) or workspace:Raycast(origin, direction, rayParams)
	local part = result and result.Instance
	local hitCharacter = part and Util.getCharacterFromPart(part)

	Net.get("Melee"):FireServer(hitCharacter and part or nil)

	if hitCharacter then
		Effects.sound("MeleeHit", nil, 0.7)
		Effects.impact(result.Position, result.Normal, true)
		CameraFX.kick(1.5, 0)
	elseif result then
		Effects.impact(result.Position, result.Normal, false)
	end
end

local function updateMelee(weapon)
	local t = now()
	if meleeStart then
		if not meleeHitDone and t - meleeStart >= weapon.HitDelay then
			meleeHitDone = true
			doMeleeHit(weapon)
		end
		if t - meleeStart >= weapon.Cooldown * 0.95 then
			meleeStart = nil
		end
	end

	if mouseDown and canAct() and not meleeStart and equipAlpha() >= 0.6 and t - lastMelee >= weapon.Cooldown then
		lastMelee = t
		meleeStart = t
		meleeHitDone = false
		vm:nextSwing()
		Effects.sound("Swing", nil, 0.6)
		Movement.cancelSprint()
	end
end

---------------------------------------------------------------------------
-- Throwables
---------------------------------------------------------------------------

local function startThrow(quick)
	if not canAct() or throwStart or charges <= 0 then
		return
	end
	local entry = entries.Utility
	if not entry or now() - lastThrow < entry.Weapon.Cooldown then
		return
	end
	if equipped ~= "Utility" then
		if not quick then
			return
		end
		quickThrowReturn = equipped
		equip("Utility")
		if equipped ~= "Utility" then
			quickThrowReturn = nil
			return
		end
	end
	throwStart = now()
	thrown = false
end

local function updateThrow()
	if not throwStart then
		if mouseDown and equipped == "Utility" and equipAlpha() >= 0.8 then
			startThrow(false)
		end
		return
	end

	local alpha = (now() - throwStart) / THROW_TIME
	if alpha >= THROW_RELEASE and not thrown then
		thrown = true
		lastThrow = now()
		local camera = workspace.CurrentCamera
		Net.get("Throw"):FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
		charges = math.max(0, charges - 1)
		vm:setWeaponVisible(false)
		Effects.sound("Throw", nil, 0.6)
		refreshHud()
	end

	if alpha >= 1 then
		throwStart = nil
		if quickThrowReturn or charges <= 0 then
			local target = quickThrowReturn or lastSlot
			quickThrowReturn = nil
			equip(target)
		else
			vm:setWeaponVisible(true)
			equipStart = now()
		end
	end
end

---------------------------------------------------------------------------
-- Loadout / lifecycle
---------------------------------------------------------------------------

local function clearEntries()
	if vm then
		vm:setWeapon(nil)
	end
	for _, entry in entries do
		entry.Model:Destroy()
	end
	table.clear(entries)
	table.clear(ammo)
end

local function buildLoadout()
	if not character or not vm then
		return
	end
	clearEntries()
	charges = 0

	for _, slot in Config.SlotOrder do
		local id = character:GetAttribute(slot)
		local weapon = id and Config.getWeapon(id)
		if weapon then
			local model, welds, definition = WeaponModels.build(id, true)
			entries[slot] = {
				Id = id,
				Weapon = weapon,
				Model = model,
				Welds = welds,
				Definition = definition,
			}
			if weapon.Kind == "Gun" then
				ammo[slot] = { Mag = weapon.MagSize, Reserve = weapon.Reserve }
			elseif weapon.Kind == "Throwable" then
				charges = weapon.Charges
			end
		end
	end

	equipped = nil
	cancelReload()
	meleeStart = nil
	throwStart = nil
	quickThrowReturn = nil
	equip("Primary")
	refreshHud(true)
end

local function deactivate()
	active = false
	mouseDown = false
	adsHeld = false
	adsAlpha = 0
	reloading = false
	throwStart = nil
	meleeStart = nil
	setSensitivity(1)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearEntries()
	equipped = nil
	if vm then
		vm:destroy()
		vm = nil
	end
	HUD.setCombatVisible(false)
end

local function onCharacterAdded(newCharacter)
	deactivate()
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	CameraFX.reset()

	Util.waitForAttribute(newCharacter, "LoadoutVersion", 15)
	if character ~= newCharacter or not newCharacter.Parent then
		return
	end

	vm = Viewmodel.new()
	active = true
	HUD.setCombatVisible(true)
	buildLoadout()

	task.delay(1, function()
		if vm and character == newCharacter then
			vm:applyCharacterColors(newCharacter)
		end
	end)

	table.insert(connections, newCharacter:GetAttributeChangedSignal("LoadoutVersion"):Connect(buildLoadout))
	table.insert(connections, humanoid.HealthChanged:Connect(function(health)
		HUD.setHealth(health, humanoid.MaxHealth)
	end))
	table.insert(connections, humanoid.Died:Connect(deactivate))
	HUD.setHealth(humanoid.Health, humanoid.MaxHealth)
end

---------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------

function WeaponController.update(dt)
	local camera = workspace.CurrentCamera
	local ctx = Movement.getContext()
	local weapon = active and currentWeapon()

	if not weapon or not vm then
		CameraFX.update(dt, {
			TargetFOV = Config.Camera.DefaultFOV,
			Speed = ctx.Speed,
			Grounded = ctx.Grounded,
		})
		HUD.updateCrosshair(dt, { Spread = 0, Kind = "None", Hidden = true })
		return
	end

	local t = now()
	local menuOpen = HUD.isMenuOpen()

	-- Aim down sights.
	local canAds = weapon.Kind == "Gun" and not reloading and not ctx.Sprinting and not menuOpen and equipAlpha() > 0.5
	adsAlpha = Util.approach(adsAlpha, (adsHeld and canAds) and 1 or 0, weapon.AdsSpeed or 12, dt)
	if adsAlpha < 0.001 then
		adsAlpha = 0
	end

	Movement.weaponSpeedMultiplier = weapon.SpeedMultiplier or 1
	Movement.aiming = adsHeld and canAds
	Movement.blockSprint = mouseDown and weapon.Kind ~= "Throwable" and not menuOpen

	bloom = math.max(0, bloom - dt * 5)

	if weapon.Kind == "Gun" then
		updateGun(weapon, ctx)
	elseif weapon.Kind == "Melee" then
		updateMelee(weapon)
	elseif weapon.Kind == "Throwable" then
		updateThrow()
	end

	-- Re-read: the update above may have switched weapons (after a throw).
	weapon = currentWeapon()
	if not weapon or not vm then
		return
	end

	-- Camera.
	local baseFov = ctx.Sprinting and Config.Camera.SprintFOV or Config.Camera.DefaultFOV
	local targetFov = baseFov
	local sensitivity = 1
	if weapon.Kind == "Gun" then
		targetFov = Util.lerp(baseFov, weapon.AdsFOV, adsAlpha)
		sensitivity = Util.lerp(1, weapon.AdsFOV / Config.Camera.DefaultFOV, adsAlpha)
	end
	setSensitivity(sensitivity)
	CameraFX.update(dt, {
		TargetFOV = targetFov,
		Speed = ctx.Speed,
		Grounded = ctx.Grounded,
		Sprinting = ctx.Sprinting,
		Sliding = ctx.Sliding,
		AdsAlpha = adsAlpha,
	})

	-- Landing bump.
	if ctx.Grounded and not wasGrounded then
		vm:land(4)
	end
	wasGrounded = ctx.Grounded

	-- Sniper scope hides the viewmodel.
	local scoped = weapon.Scope == true and adsAlpha > 0.85
	if viewmodelShown == scoped then
		viewmodelShown = not scoped
		vm:setVisible(viewmodelShown)
	end

	local interval = weapon.RPM and (60 / weapon.RPM) or 0
	local sinceShot = t - lastFire
	local cycleAlpha
	if (weapon.FireMode == "Pump" or weapon.FireMode == "Bolt") and sinceShot < interval then
		cycleAlpha = sinceShot / interval
	end

	vm:update(dt, camera.CFrame, {
		Kind = weapon.Kind,
		AdsAlpha = adsAlpha,
		SprintAlpha = Movement.getSprintAlpha(),
		Speed = ctx.Speed,
		Grounded = ctx.Grounded,
		Sliding = ctx.Sliding,
		Crouching = ctx.Crouching,
		EquipAlpha = equipAlpha(),
		ReloadAlpha = reloading and math.clamp((t - reloadStart) / weapon.ReloadTime, 0, 1) or nil,
		ShotTime = sinceShot,
		CycleAlpha = cycleAlpha,
		MeleeAlpha = meleeStart and math.clamp((t - meleeStart) / (weapon.Cooldown * 0.95), 0, 1) or nil,
		ThrowAlpha = throwStart and math.clamp((t - throwStart) / THROW_TIME, 0, 1) or nil,
	})

	HUD.updateCrosshair(dt, {
		Spread = currentSpread(weapon, ctx),
		AdsAlpha = adsAlpha,
		Kind = weapon.Kind,
		Scoped = scoped,
		Hidden = menuOpen,
	})
	refreshHud()

	-- Tell the server where we're looking so others see our arms aim.
	if t - lastPitchSend > 0.1 then
		lastPitchSend = t
		Net.get("AimPitch"):FireServer(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
	end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

local SLOT_KEYS = {
	[Config.Keys.Primary] = "Primary",
	[Config.Keys.Secondary] = "Secondary",
	[Config.Keys.Melee] = "Melee",
	[Config.Keys.Utility] = "Utility",
}

local function cycleSlot(step)
	if not equipped then
		return
	end
	local order = Config.SlotOrder
	local index = table.find(order, equipped) or 1
	for _ = 1, #order do
		index = ((index - 1 + step) % #order) + 1
		local slot = order[index]
		if entries[slot] and (slot ~= "Utility" or charges > 0) then
			equip(slot)
			return
		end
	end
end

local function onInputBegan(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if processed then
			return
		end
		mouseDown = true
		firedThisPress = false
		emptyClicked = false
		return
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if processed then
			return
		end
		adsHeld = true
		return
	end

	if processed then
		return
	end

	if input.KeyCode == Config.Keys.Loadout then
		HUD.toggleMenu()
		return
	end

	if not canAct() then
		return
	end

	local slot = SLOT_KEYS[input.KeyCode]
	if slot then
		equip(slot)
	elseif input.KeyCode == Config.Keys.Reload then
		startReload()
	elseif input.KeyCode == Config.Keys.QuickThrow then
		startThrow(true)
	end
end

local function onInputEnded(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseDown = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		adsHeld = false
	end
end

local function onInputChanged(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	if canAct() then
		cycleSlot(input.Position.Z > 0 and -1 or 1)
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function WeaponController.isActive()
	return active
end

function WeaponController.init()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.InputChanged:Connect(onInputChanged)

	Net.get("AmmoSync").OnClientEvent:Connect(function(slot, mag, reserve)
		local ammoState = ammo[slot]
		if not ammoState then
			return
		end
		if reloading and slot == equipped then
			return
		end
		ammoState.Mag = mag
		ammoState.Reserve = reserve
		refreshHud()
	end)

	Net.get("ChargesSync").OnClientEvent:Connect(function(serverCharges)
		charges = serverCharges
		refreshHud()
	end)

	Net.get("HitConfirm").OnClientEvent:Connect(function(_damage, headshot, killed)
		HUD.hitmarker(headshot, killed)
		Effects.sound("Hitmarker", nil, killed and 0.9 or 0.5, headshot and 1.4 or 1)
	end)

	Net.get("Damaged").OnClientEvent:Connect(function(amount, sourcePosition)
		HUD.damageFrom(sourcePosition)
		CameraFX.shake(math.clamp(amount * 0.12, 1, 8))
	end)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

return WeaponController
