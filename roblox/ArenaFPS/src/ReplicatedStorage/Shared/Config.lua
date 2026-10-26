-- Config: every tunable number in the game lives here.
-- Server and client both read this, so stats stay in sync.

local Config = {}

---------------------------------------------------------------------------
-- Match
---------------------------------------------------------------------------

Config.Match = {
	MinPlayers = 2,           -- players needed before a match starts
	IntermissionTime = 10,    -- lobby countdown before a match
	RoundsToWin = 5,          -- first team to this many rounds wins
	RoundTime = 90,           -- seconds per round before it times out
	FreezeTime = 3,           -- players are frozen this long at round start
	RoundEndTime = 4,         -- pause between rounds
	MatchEndTime = 8,         -- victory screen length
	LobbyRespawnTime = 3,     -- respawn delay in the lobby
}

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------

Config.Movement = {
	WalkSpeed = 16,
	SprintSpeed = 24,
	CrouchSpeed = 9,
	SlideSpeed = 42,          -- burst speed at the start of a slide
	SlideDuration = 0.75,
	SlideCooldown = 0.9,
	CrouchCameraOffset = -1.4,
	SlideCameraOffset = -1.8,
	JumpPower = 50,
}

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------

Config.Camera = {
	DefaultFOV = 75,
	SprintFOV = 82,
	BobWalk = 0.06,
	BobSprint = 0.12,
}

---------------------------------------------------------------------------
-- Keybinds
---------------------------------------------------------------------------

Config.Keys = {
	Primary = Enum.KeyCode.One,
	Secondary = Enum.KeyCode.Two,
	Melee = Enum.KeyCode.Three,
	Utility = Enum.KeyCode.Four,
	QuickThrow = Enum.KeyCode.G,
	Reload = Enum.KeyCode.R,
	Sprint = Enum.KeyCode.LeftShift,
	Crouch = Enum.KeyCode.LeftControl,
	CrouchAlt = Enum.KeyCode.C,
	Loadout = Enum.KeyCode.M,
}

Config.SlotOrder = { "Primary", "Secondary", "Melee", "Utility" }

---------------------------------------------------------------------------
-- Sounds
-- Built-in Roblox sounds are used as placeholders. Swap any of these for
-- sound IDs from the Creator Store ("rbxassetid://123456") for real gun audio.
-- Set an entry to "" to silence it.
---------------------------------------------------------------------------

Config.Sounds = {
	RifleShot = "rbxasset://sounds/paintball.wav",
	PistolShot = "rbxasset://sounds/paintball.wav",
	ShotgunShot = "rbxasset://sounds/paintball.wav",
	SniperShot = "rbxasset://sounds/paintball.wav",
	Reload = "rbxasset://sounds/unsheath.wav",
	Equip = "rbxasset://sounds/unsheath.wav",
	Swing = "rbxasset://sounds/swordslash.wav",
	MeleeHit = "rbxasset://sounds/swordlunge.wav",
	Hitmarker = "rbxasset://sounds/electronicpingshort.wav",
	Throw = "rbxasset://sounds/swordlunge.wav",
	Empty = "rbxasset://sounds/electronicpingshort.wav",
}

---------------------------------------------------------------------------
-- Weapons
--
-- Kind:      "Gun", "Melee" or "Throwable"
-- FireMode:  "Auto", "Semi", "Pump", "Bolt"
-- Damage:    per bullet (per pellet for shotguns)
-- Falloff:   damage scales from 1 at Start studs down to Min at End studs
-- Spread:    degrees of cone; Hip when not aiming, Ads when aiming
-- Recoil:    Pitch/Yaw in degrees per shot, Kick = viewmodel push-back
---------------------------------------------------------------------------

Config.Weapons = {
	-- Primaries -----------------------------------------------------------
	AssaultRifle = {
		DisplayName = "Assault Rifle",
		Slot = "Primary",
		Kind = "Gun",
		FireMode = "Auto",
		RPM = 620,
		Damage = 24,
		HeadMultiplier = 1.5,
		Pellets = 1,
		MagSize = 30,
		Reserve = 180,
		ReloadTime = 2.0,
		EquipTime = 0.45,
		Range = 700,
		Falloff = { Start = 70, End = 220, Min = 0.65 },
		Spread = { Hip = 2.4, Ads = 0.35, Move = 1.6, Air = 4 },
		Recoil = { Pitch = 1.05, Yaw = 0.45, Kick = 0.14 },
		AdsFOV = 55,
		AdsSpeed = 12,
		SpeedMultiplier = 0.95,
		Sound = "RifleShot",
	},
	SMG = {
		DisplayName = "SMG",
		Slot = "Primary",
		Kind = "Gun",
		FireMode = "Auto",
		RPM = 900,
		Damage = 16,
		HeadMultiplier = 1.4,
		Pellets = 1,
		MagSize = 35,
		Reserve = 210,
		ReloadTime = 1.7,
		EquipTime = 0.35,
		Range = 450,
		Falloff = { Start = 35, End = 120, Min = 0.55 },
		Spread = { Hip = 2.8, Ads = 1.0, Move = 0.8, Air = 3 },
		Recoil = { Pitch = 0.6, Yaw = 0.55, Kick = 0.09 },
		AdsFOV = 62,
		AdsSpeed = 15,
		SpeedMultiplier = 1.0,
		Sound = "PistolShot",
	},
	Shotgun = {
		DisplayName = "Shotgun",
		Slot = "Primary",
		Kind = "Gun",
		FireMode = "Pump",
		RPM = 72,
		Damage = 11,
		HeadMultiplier = 1.25,
		Pellets = 9,
		MagSize = 6,
		Reserve = 36,
		ReloadTime = 2.6,
		EquipTime = 0.5,
		Range = 160,
		Falloff = { Start = 15, End = 60, Min = 0.3 },
		Spread = { Hip = 6.5, Ads = 4.8, Move = 0.5, Air = 1.5 },
		Recoil = { Pitch = 5.5, Yaw = 1.2, Kick = 0.45 },
		AdsFOV = 62,
		AdsSpeed = 10,
		SpeedMultiplier = 0.95,
		Sound = "ShotgunShot",
	},
	Sniper = {
		DisplayName = "Sniper",
		Slot = "Primary",
		Kind = "Gun",
		FireMode = "Bolt",
		RPM = 45,
		Damage = 90,
		HeadMultiplier = 2.0,
		Pellets = 1,
		MagSize = 5,
		Reserve = 30,
		ReloadTime = 3.0,
		EquipTime = 0.6,
		Range = 1500,
		Falloff = { Start = 1500, End = 1500, Min = 1 },
		Spread = { Hip = 9, Ads = 0, Move = 4, Air = 10 },
		Recoil = { Pitch = 6, Yaw = 0.8, Kick = 0.5 },
		AdsFOV = 22,
		AdsSpeed = 8,
		SpeedMultiplier = 0.85,
		Scope = true,
		Sound = "SniperShot",
	},

	-- Secondaries ---------------------------------------------------------
	Handgun = {
		DisplayName = "Handgun",
		Slot = "Secondary",
		Kind = "Gun",
		FireMode = "Semi",
		RPM = 420,
		Damage = 22,
		HeadMultiplier = 1.6,
		Pellets = 1,
		MagSize = 12,
		Reserve = 72,
		ReloadTime = 1.4,
		EquipTime = 0.3,
		Range = 500,
		Falloff = { Start = 40, End = 140, Min = 0.6 },
		Spread = { Hip = 1.8, Ads = 0.5, Move = 0.9, Air = 3 },
		Recoil = { Pitch = 1.8, Yaw = 0.5, Kick = 0.18 },
		AdsFOV = 62,
		AdsSpeed = 16,
		SpeedMultiplier = 1.05,
		Sound = "PistolShot",
	},
	Revolver = {
		DisplayName = "Revolver",
		Slot = "Secondary",
		Kind = "Gun",
		FireMode = "Semi",
		RPM = 130,
		Damage = 48,
		HeadMultiplier = 1.8,
		Pellets = 1,
		MagSize = 6,
		Reserve = 36,
		ReloadTime = 2.4,
		EquipTime = 0.4,
		Range = 600,
		Falloff = { Start = 50, End = 180, Min = 0.7 },
		Spread = { Hip = 1.6, Ads = 0.25, Move = 1.2, Air = 4 },
		Recoil = { Pitch = 4.2, Yaw = 0.9, Kick = 0.3 },
		AdsFOV = 58,
		AdsSpeed = 13,
		SpeedMultiplier = 1.0,
		Sound = "SniperShot",
	},

	-- Melee ----------------------------------------------------------------
	Knife = {
		DisplayName = "Knife",
		Slot = "Melee",
		Kind = "Melee",
		Damage = 45,
		Cooldown = 0.5,
		Range = 7,
		HitDelay = 0.12,   -- seconds into the swing when the hit lands
		EquipTime = 0.25,
		SpeedMultiplier = 1.12,
	},
	Katana = {
		DisplayName = "Katana",
		Slot = "Melee",
		Kind = "Melee",
		Damage = 70,
		Cooldown = 0.85,
		Range = 9.5,
		HitDelay = 0.18,
		EquipTime = 0.4,
		SpeedMultiplier = 1.06,
	},

	-- Utilities -------------------------------------------------------------
	Frag = {
		DisplayName = "Frag Grenade",
		Slot = "Utility",
		Kind = "Throwable",
		Effect = "Frag",
		Charges = 2,
		Cooldown = 1.0,
		ThrowSpeed = 85,
		Fuse = 2.4,
		Damage = 110,
		Radius = 18,
		EquipTime = 0.3,
		SpeedMultiplier = 1.0,
	},
	Flashbang = {
		DisplayName = "Flashbang",
		Slot = "Utility",
		Kind = "Throwable",
		Effect = "Flash",
		Charges = 2,
		Cooldown = 1.0,
		ThrowSpeed = 90,
		Fuse = 1.5,
		Radius = 75,
		FlashTime = 3.5,
		EquipTime = 0.3,
		SpeedMultiplier = 1.0,
	},
	Smoke = {
		DisplayName = "Smoke Grenade",
		Slot = "Utility",
		Kind = "Throwable",
		Effect = "Smoke",
		Charges = 1,
		Cooldown = 1.0,
		ThrowSpeed = 75,
		Fuse = 1.2,
		Radius = 15,
		Duration = 14,
		EquipTime = 0.3,
		SpeedMultiplier = 1.0,
	},
}

-- Weapons shown in the loadout menu, per slot, in display order.
Config.LoadoutOptions = {
	Primary = { "AssaultRifle", "SMG", "Shotgun", "Sniper" },
	Secondary = { "Handgun", "Revolver" },
	Melee = { "Knife", "Katana" },
	Utility = { "Frag", "Flashbang", "Smoke" },
}

Config.DefaultLoadout = {
	Primary = "AssaultRifle",
	Secondary = "Handgun",
	Melee = "Knife",
	Utility = "Frag",
}

---------------------------------------------------------------------------
-- Server validation tolerances (anti-cheat leniency for lag)
---------------------------------------------------------------------------

Config.Validation = {
	MaxOriginOffset = 10,      -- studs between claimed shot origin and server head
	MaxHitOffset = 7,          -- studs between claimed hit point and the hit part
	FireRateTolerance = 0.8,   -- accept shots at 80% of the true interval (jitter)
	MeleeRangeBonus = 4,
}

---------------------------------------------------------------------------
-- Damage / health
---------------------------------------------------------------------------

Config.MaxHealth = 100
Config.DummyHealth = 150

-- Helpers ----------------------------------------------------------------

function Config.getWeapon(id)
	return Config.Weapons[id]
end

function Config.isValidLoadoutChoice(slot, id)
	local options = Config.LoadoutOptions[slot]
	if not options then
		return false
	end
	for _, option in options do
		if option == id then
			return true
		end
	end
	return false
end

-- Damage multiplier for a shot travelling `distance` studs.
function Config.falloff(weapon, distance)
	local f = weapon.Falloff
	if not f or distance <= f.Start then
		return 1
	end
	if distance >= f.End then
		return f.Min
	end
	local alpha = (distance - f.Start) / (f.End - f.Start)
	return 1 + (f.Min - 1) * alpha
end

return Config
