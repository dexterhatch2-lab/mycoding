-- CombatServer: the server is the authority on ammo, fire rate, damage and kills.
-- Clients raycast locally for responsiveness and send their hits here; every hit
-- is checked (range, line of sight, fire rate, position) before damage is dealt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local WeaponModels = require(Shared.WeaponModels)

local CombatServer = {}

-- Hooks filled in by the match manager.
CombatServer.canDamage = function(_attacker, _victimPlayer, _victimCharacter)
	return true
end
CombatServer.onKill = function(_killer, _victimPlayer, _victimCharacter) end

local states = {} -- [Player] = combat state for the current life

local mapParams = RaycastParams.new()
mapParams.FilterType = Enum.RaycastFilterType.Include

local function refreshMapParams()
	local map = workspace:FindFirstChild("Map")
	mapParams.FilterDescendantsInstances = map and { map } or {}
end

local function now()
	return os.clock()
end

local function isVector3(value)
	return typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z
end

local function getState(player)
	local state = states[player]
	if not state then
		return nil
	end
	if not state.Character or not state.Character.Parent or not Util.isAlive(state.Character) then
		return nil
	end
	return state
end

local function equippedWeapon(state)
	local slot = state.Slots[state.Equipped]
	if not slot then
		return nil, nil
	end
	return Config.getWeapon(slot.Id), slot
end

local function syncAmmo(player, state, slotName)
	local slot = state.Slots[slotName]
	if slot and slot.Mag then
		Net.get("AmmoSync"):FireClient(player, slotName, slot.Mag, slot.Reserve)
	end
end

local function cancelReload(state)
	state.ReloadToken += 1
	state.Reloading = false
end

---------------------------------------------------------------------------
-- Third-person weapon model
---------------------------------------------------------------------------

local function updateWorldModel(state)
	if state.WorldModel then
		state.WorldModel:Destroy()
		state.WorldModel = nil
	end

	local character = state.Character
	local slot = state.Slots[state.Equipped]
	if not slot or not character then
		return
	end
	if state.Equipped == "Utility" and state.Charges <= 0 then
		return
	end

	local hand = Util.getRightHand(character)
	if not hand then
		return
	end

	local model = WeaponModels.build(slot.Id, false)
	model.Name = "WorldWeapon"
	local handle = model.PrimaryPart
	local grip = handle:FindFirstChild("RightGrip")

	local weld = Instance.new("Weld")
	weld.Name = "GripWeld"
	weld.Part0 = hand
	weld.Part1 = handle
	-- Point the weapon down the hand's -Y axis (the way the arm points).
	weld.C0 = CFrame.new(0, -hand.Size.Y * 0.35, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	weld.C1 = CFrame.new(grip and grip.Position or Vector3.zero)
	weld.Parent = handle

	handle.CFrame = hand.CFrame * weld.C0 * weld.C1:Inverse()
	model.Parent = character
	state.WorldModel = model
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------

local function registerKill(attacker, victimPlayer, victimCharacter, weaponId, headshot)
	victimCharacter:SetAttribute("DeathCounted", true)

	-- Dummy kills show in the feed but don't count toward stats.
	local isDummy = victimCharacter:GetAttribute("IsDummy") == true
	if attacker and attacker ~= victimPlayer and not isDummy then
		local stats = attacker:FindFirstChild("leaderstats")
		local kills = stats and stats:FindFirstChild("Kills")
		if kills then
			kills.Value += 1
		end
	end

	if victimPlayer then
		local stats = victimPlayer:FindFirstChild("leaderstats")
		local deaths = stats and stats:FindFirstChild("Deaths")
		if deaths then
			deaths.Value += 1
		end
	end

	local weapon = Config.getWeapon(weaponId)
	local victimName = victimPlayer and victimPlayer.DisplayName or victimCharacter.Name
	Net.get("KillFeed"):FireAllClients(
		attacker and attacker.DisplayName or "World",
		victimName,
		weapon and weapon.DisplayName or "",
		headshot == true
	)

	CombatServer.onKill(attacker, victimPlayer, victimCharacter)
end

-- Deals damage from `attacker` (a Player) to a character. Returns the damage dealt.
function CombatServer.dealDamage(attacker, character, humanoid, amount, weaponId, headshot, sourcePosition)
	if not humanoid or humanoid.Health <= 0 or amount <= 0 then
		return 0
	end
	if character:FindFirstChildOfClass("ForceField") then
		return 0
	end

	local victimPlayer = Players:GetPlayerFromCharacter(character)
	if not CombatServer.canDamage(attacker, victimPlayer, character) then
		return 0
	end

	amount = math.floor(amount + 0.5)
	humanoid:TakeDamage(amount)
	local killed = humanoid.Health <= 0

	if attacker then
		Net.get("HitConfirm"):FireClient(attacker, amount, headshot == true, killed)
	end
	if victimPlayer then
		Net.get("Damaged"):FireClient(victimPlayer, amount, sourcePosition)
	end

	if killed and not character:GetAttribute("DeathCounted") then
		registerKill(attacker, victimPlayer, character, weaponId, headshot)
	end
	return amount
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------

function CombatServer.onCharacterSpawned(player, character, loadout)
	local state = {
		Character = character,
		Loadout = table.clone(loadout),
		Slots = {},
		Equipped = "Primary",
		EquippedAt = now(),
		LastFire = 0,
		LastMelee = 0,
		LastThrow = 0,
		Reloading = false,
		ReloadToken = 0,
		Charges = 0,
		LastPitchSent = 0,
	}

	for _, slotName in Config.SlotOrder do
		local id = loadout[slotName]
		local weapon = Config.getWeapon(id)
		if weapon then
			local slot = { Id = id }
			if weapon.Kind == "Gun" then
				slot.Mag = weapon.MagSize
				slot.Reserve = weapon.Reserve
			elseif weapon.Kind == "Throwable" then
				state.Charges = weapon.Charges
			end
			state.Slots[slotName] = slot
			character:SetAttribute(slotName, id)
		end
	end

	states[player] = state

	character:SetAttribute("Equipped", state.Slots.Primary and state.Slots.Primary.Id or "")
	character:SetAttribute("AimPitch", 0)
	character:SetAttribute("LoadoutVersion", (character:GetAttribute("LoadoutVersion") or 0) + 1)

	updateWorldModel(state)

	syncAmmo(player, state, "Primary")
	syncAmmo(player, state, "Secondary")
	Net.get("ChargesSync"):FireClient(player, state.Charges)
end

function CombatServer.clear(player)
	local state = states[player]
	if state and state.WorldModel then
		state.WorldModel:Destroy()
	end
	states[player] = nil
end

---------------------------------------------------------------------------
-- Remote handlers
---------------------------------------------------------------------------

local function onEquip(player, slotName)
	local state = getState(player)
	if not state or typeof(slotName) ~= "string" or not state.Slots[slotName] then
		return
	end
	if slotName == "Utility" and state.Charges <= 0 then
		return
	end
	if state.Equipped == slotName then
		return
	end

	cancelReload(state)
	state.Equipped = slotName
	state.EquippedAt = now()
	state.Character:SetAttribute("Equipped", state.Slots[slotName].Id)
	updateWorldModel(state)
end

local function headPosition(character)
	local head = character:FindFirstChild("Head")
	return head and head.Position or character:GetPivot().Position
end

local function onFire(player, weaponId, origin, shots)
	local state = getState(player)
	if not state or typeof(weaponId) ~= "string" or not isVector3(origin) or typeof(shots) ~= "table" then
		return
	end
	local character = state.Character
	if character:GetAttribute("Frozen") then
		return
	end

	local weapon, slot = equippedWeapon(state)
	if not weapon or weapon.Kind ~= "Gun" or slot.Id ~= weaponId then
		return
	end

	local t = now()
	if state.Reloading then
		return
	end
	if t - state.EquippedAt < weapon.EquipTime * 0.6 then
		return
	end
	if slot.Mag <= 0 then
		syncAmmo(player, state, state.Equipped)
		return
	end
	local interval = 60 / weapon.RPM
	if t - state.LastFire < interval * Config.Validation.FireRateTolerance then
		return
	end
	if (headPosition(character) - origin).Magnitude > Config.Validation.MaxOriginOffset then
		return
	end
	if #shots < 1 or #shots > weapon.Pellets then
		return
	end

	state.LastFire = t
	slot.Mag -= 1

	refreshMapParams()

	local damageByHumanoid = {} -- [Humanoid] = { Character, Damage, Headshot }
	local replicatePoints = {}

	for i, shot in shots do
		if i > weapon.Pellets then
			break
		end
		if typeof(shot) ~= "table" or not isVector3(shot.Position) then
			continue
		end

		local position = shot.Position
		local offset = position - origin
		local distance = offset.Magnitude
		if distance > weapon.Range + 10 then
			position = origin + offset.Unit * weapon.Range
			distance = weapon.Range
		end
		table.insert(replicatePoints, position)

		local part = shot.Part
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
			continue
		end

		local targetCharacter, humanoid = Util.getCharacterFromPart(part)
		if not humanoid or targetCharacter == character or humanoid.Health <= 0 then
			continue
		end

		-- The claimed hit point has to be on (or near) the part that was hit.
		local slack = part.Size.Magnitude / 2 + Config.Validation.MaxHitOffset
		if (position - part.Position).Magnitude > slack then
			continue
		end

		-- Nothing solid may sit between the shooter and the hit point.
		if distance > 0.1 then
			local blocked = workspace:Raycast(origin, offset.Unit * distance, mapParams)
			if blocked and (blocked.Position - origin).Magnitude < distance - 1.5 then
				continue
			end
		end

		local headshot = Util.isHead(part)
		local damage = weapon.Damage * Config.falloff(weapon, distance)
		if headshot then
			damage *= weapon.HeadMultiplier
		end

		local entry = damageByHumanoid[humanoid]
		if not entry then
			entry = { Character = targetCharacter, Damage = 0, Headshot = false }
			damageByHumanoid[humanoid] = entry
		end
		entry.Damage += damage
		entry.Headshot = entry.Headshot or headshot
	end

	for humanoid, entry in damageByHumanoid do
		CombatServer.dealDamage(player, entry.Character, humanoid, entry.Damage, weaponId, entry.Headshot, origin)
	end

	-- Show tracers and play the shot sound for everyone else.
	local replicate = Net.get("ShotReplicate")
	for _, other in Players:GetPlayers() do
		if other ~= player then
			replicate:FireClient(other, player, weaponId, origin, replicatePoints)
		end
	end
end

local function onReload(player)
	local state = getState(player)
	if not state or state.Reloading then
		return
	end
	local weapon, slot = equippedWeapon(state)
	if not weapon or weapon.Kind ~= "Gun" then
		return
	end
	if slot.Mag >= weapon.MagSize or slot.Reserve <= 0 then
		return
	end

	state.Reloading = true
	state.ReloadToken += 1
	local token = state.ReloadToken
	local slotName = state.Equipped

	-- Slightly shorter than the client's timer so the first shot after a
	-- reload is never rejected because of latency.
	task.delay(weapon.ReloadTime * 0.9, function()
		if states[player] ~= state or state.ReloadToken ~= token then
			return
		end
		local amount = math.min(weapon.MagSize - slot.Mag, slot.Reserve)
		slot.Mag += amount
		slot.Reserve -= amount
		state.Reloading = false
		syncAmmo(player, state, slotName)
	end)
end

local function onMelee(player, targetPart)
	local state = getState(player)
	if not state then
		return
	end
	local character = state.Character
	if character:GetAttribute("Frozen") then
		return
	end

	local weapon, slot = equippedWeapon(state)
	if not weapon or weapon.Kind ~= "Melee" then
		return
	end

	local t = now()
	if t - state.LastMelee < weapon.Cooldown * Config.Validation.FireRateTolerance then
		return
	end
	if t - state.EquippedAt < weapon.EquipTime * 0.5 then
		return
	end
	state.LastMelee = t

	local replicate = Net.get("MeleeReplicate")
	for _, other in Players:GetPlayers() do
		if other ~= player then
			replicate:FireClient(other, player)
		end
	end

	if typeof(targetPart) ~= "Instance" or not targetPart:IsA("BasePart") or not targetPart:IsDescendantOf(workspace) then
		return
	end

	local targetCharacter, humanoid = Util.getCharacterFromPart(targetPart)
	if not humanoid or targetCharacter == character or humanoid.Health <= 0 then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local toTarget = targetPart.Position - root.Position
	if toTarget.Magnitude > weapon.Range + Config.Validation.MeleeRangeBonus then
		return
	end

	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flat.Magnitude > 2 and flat.Unit:Dot(root.CFrame.LookVector) < 0.1 then
		return
	end

	-- Backstab: hitting someone from behind does double damage.
	local damage = weapon.Damage
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if targetRoot and flat.Magnitude > 0.5 and targetRoot.CFrame.LookVector:Dot(flat.Unit) > 0.6 then
		damage *= 2
	end

	CombatServer.dealDamage(player, targetCharacter, humanoid, damage, slot.Id, false, root.Position)
end

---------------------------------------------------------------------------
-- Throwables
---------------------------------------------------------------------------

local function effectsFolder()
	return workspace:FindFirstChild("Effects") or workspace
end

local function allCharacters()
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character and Util.isAlive(player.Character) then
			table.insert(list, player.Character)
		end
	end
	local dummies = workspace:FindFirstChild("Dummies")
	if dummies then
		for _, dummy in dummies:GetChildren() do
			if Util.isAlive(dummy) then
				table.insert(list, dummy)
			end
		end
	end
	return list
end

local function hasLineOfSight(from, to)
	local offset = to - from
	if offset.Magnitude < 0.1 then
		return true
	end
	local result = workspace:Raycast(from, offset, mapParams)
	return result == nil
end

local function detonateFrag(attacker, weapon, position)
	Net.get("Explosion"):FireAllClients(position, weapon.Radius, "Frag")
	for _, character in allCharacters() do
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and humanoid then
			local distance = (root.Position - position).Magnitude
			if distance <= weapon.Radius and hasLineOfSight(position + Vector3.new(0, 1, 0), root.Position) then
				local falloff = 1 - (distance / weapon.Radius)
				local damage = weapon.Damage * math.clamp(falloff, 0, 1) ^ 0.6
				CombatServer.dealDamage(attacker, character, humanoid, damage, "Frag", false, position)
			end
		end
	end
end

local function detonateFlash(_attacker, weapon, position)
	Net.get("Explosion"):FireAllClients(position, 6, "Flash")
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if head and root and Util.isAlive(character) then
			local offset = position - head.Position
			local distance = offset.Magnitude
			if distance <= weapon.Radius and hasLineOfSight(position + Vector3.new(0, 0.5, 0), head.Position) then
				-- Facing the flash blinds harder than looking away.
				local pitch = character:GetAttribute("AimPitch") or 0
				local look = (root.CFrame * CFrame.Angles(pitch, 0, 0)).LookVector
				local facing = distance > 0.5 and look:Dot(offset.Unit) or 1
				local intensity = math.clamp((facing + 0.4) / 1.4, 0.2, 1) * (1 - 0.6 * distance / weapon.Radius)
				Net.get("Flash"):FireClient(player, intensity, weapon.FlashTime)
			end
		end
	end
end

local function detonateSmoke(_attacker, weapon, position)
	local cloud = Instance.new("Folder")
	cloud.Name = "SmokeCloud"
	cloud.Parent = effectsFolder()

	local rng = Random.new()
	local puffs = {}
	for i = 1, 14 do
		local radius = weapon.Radius
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 0.6), rng:NextNumber(-1, 1)) * radius * 0.6
		local size = rng:NextNumber(0.8, 1.1) * radius
		local puff = Instance.new("Part")
		puff.Name = "Puff" .. i
		puff.Shape = Enum.PartType.Ball
		puff.Size = Vector3.one * 1
		puff.Anchored = true
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		puff.CastShadow = false
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = Color3.fromRGB(200, 205, 200)
		puff.Transparency = 0.15
		puff.CFrame = CFrame.new(position + offset + Vector3.new(0, size * 0.25, 0))
		puff.Parent = cloud
		TweenService:Create(puff, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * size,
		}):Play()

		if i <= 4 then
			local smoke = Instance.new("Smoke")
			smoke.Color = Color3.fromRGB(210, 215, 210)
			smoke.Opacity = 0.6
			smoke.Size = 10
			smoke.RiseVelocity = 1
			smoke.Parent = puff
		end
		table.insert(puffs, puff)
	end

	task.delay(weapon.Duration, function()
		for _, puff in puffs do
			if puff.Parent then
				TweenService:Create(puff, TweenInfo.new(2), { Transparency = 1 }):Play()
				local smoke = puff:FindFirstChildOfClass("Smoke")
				if smoke then
					smoke.Enabled = false
				end
			end
		end
	end)
	Debris:AddItem(cloud, weapon.Duration + 2.5)
end

local DETONATE = {
	Frag = detonateFrag,
	Flash = detonateFlash,
	Smoke = detonateSmoke,
}

local function rng()
	return math.random() * 2 - 1
end

local function spawnProjectile(player, weaponId, weapon, origin, direction)
	local ball = Instance.new("Part")
	ball.Name = weaponId .. "Projectile"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 0.6
	ball.Transparency = 1
	ball.CanCollide = true
	ball.CanQuery = false
	ball.CustomPhysicalProperties = PhysicalProperties.new(2, 0.6, 0.35, 1, 1)
	ball.CFrame = CFrame.new(origin)

	local model = WeaponModels.build(weaponId, false)
	local handle = model.PrimaryPart
	handle.CFrame = ball.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ball
	weld.Part1 = handle
	weld.Parent = ball
	model.Parent = ball

	ball.Parent = effectsFolder()
	ball:SetNetworkOwner(nil)
	ball.AssemblyLinearVelocity = direction * weapon.ThrowSpeed + Vector3.new(0, 12, 0)
	ball.AssemblyAngularVelocity = Vector3.new(rng(), rng(), rng()) * 8

	task.delay(weapon.Fuse, function()
		local position = ball.Position
		ball:Destroy()
		refreshMapParams()
		local detonate = DETONATE[weapon.Effect]
		if detonate then
			detonate(player, weapon, position)
		end
	end)
end

local function onThrow(player, origin, direction)
	local state = getState(player)
	if not state or not isVector3(origin) or not isVector3(direction) then
		return
	end
	local character = state.Character
	if character:GetAttribute("Frozen") then
		return
	end

	local slot = state.Slots.Utility
	local weapon = slot and Config.getWeapon(slot.Id)
	if not weapon or weapon.Kind ~= "Throwable" then
		return
	end
	if state.Charges <= 0 then
		return
	end
	local t = now()
	if t - state.LastThrow < weapon.Cooldown * Config.Validation.FireRateTolerance then
		return
	end
	if (headPosition(character) - origin).Magnitude > Config.Validation.MaxOriginOffset then
		return
	end
	if direction.Magnitude < 0.5 then
		return
	end

	state.LastThrow = t
	state.Charges -= 1
	Net.get("ChargesSync"):FireClient(player, state.Charges)

	direction = direction.Unit
	spawnProjectile(player, slot.Id, weapon, origin + direction * 2.5, direction)

	if state.Equipped == "Utility" and state.Charges <= 0 then
		updateWorldModel(state)
	end
end

local function onAimPitch(player, pitch)
	local state = states[player]
	if not state or typeof(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	local t = now()
	if t - state.LastPitchSent < 0.05 then
		return
	end
	state.LastPitchSent = t
	pitch = math.clamp(math.floor(pitch * 100 + 0.5) / 100, -1.4, 1.4)
	if state.Character and state.Character.Parent then
		state.Character:SetAttribute("AimPitch", pitch)
	end
end

function CombatServer.init()
	Net.get("Equip").OnServerEvent:Connect(onEquip)
	Net.get("Fire").OnServerEvent:Connect(onFire)
	Net.get("Reload").OnServerEvent:Connect(onReload)
	Net.get("Melee").OnServerEvent:Connect(onMelee)
	Net.get("Throw").OnServerEvent:Connect(onThrow)
	Net.get("AimPitch").OnServerEvent:Connect(onAimPitch)

	Players.PlayerRemoving:Connect(CombatServer.clear)
	refreshMapParams()
end

return CombatServer
