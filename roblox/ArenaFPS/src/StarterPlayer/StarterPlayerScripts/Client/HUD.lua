-- HUD: crosshair, hitmarkers, health, ammo, weapon slots, match score,
-- announcements, kill feed, damage indicators, sniper scope, flash overlay
-- and the loadout menu. Everything is built in code.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local HUD = {}

local player = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
local DIM = Color3.fromRGB(160, 165, 175)
local PANEL = Color3.fromRGB(14, 15, 20)
local ACCENT = Color3.fromRGB(255, 190, 60)
local RED = Color3.fromRGB(235, 70, 70)
local BLUE = Color3.fromRGB(70, 140, 255)
local HEAD = Color3.fromRGB(255, 200, 60)
local FONT = Enum.Font.GothamBold
local FONT_LIGHT = Enum.Font.GothamMedium

local gui
local refs = {}
local menuOpen = false
local hitmarkerTime = -10
local hitmarkerColor = WHITE
local crosshairGap = 10
local damageIndicators = {}

---------------------------------------------------------------------------
-- Builders
---------------------------------------------------------------------------

local function new(className, props, children)
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function stroke(thickness, color, transparency)
	return new("UIStroke", {
		Thickness = thickness or 1,
		Color = color or Color3.new(0, 0, 0),
		Transparency = transparency or 0.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or FONT
	props.TextScaled = props.TextScaled or false
	props.TextSize = props.TextSize or 18
	return new("TextLabel", props)
end

local function textStroke(instance)
	instance.TextStrokeTransparency = 0.6
	instance.TextStrokeColor3 = Color3.new(0, 0, 0)
	return instance
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function buildCrosshair(parent)
	local holder = new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	refs.CrosshairLines = {}
	for i, dir in { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) } do
		local vertical = dir.X == 0
		local line = new("Frame", {
			Name = "Line" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = vertical and UDim2.fromOffset(2, 8) or UDim2.fromOffset(8, 2),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Parent = holder,
		}, { stroke(1, Color3.new(0, 0, 0), 0.4) })
		refs.CrosshairLines[i] = { Frame = line, Direction = dir }
	end
	refs.CrosshairDot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = holder,
	}, { corner(2) })
	refs.Crosshair = holder

	-- Hitmarker: four diagonal ticks.
	local marker = new("Frame", {
		Name = "Hitmarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	refs.HitmarkerLines = {}
	for i, angle in { 45, 135, 225, 315 } do
		local r = math.rad(angle)
		local line = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.cos(r) * 12, math.sin(r) * 12),
			Size = UDim2.fromOffset(10, 2),
			Rotation = angle,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			Parent = marker,
		})
		refs.HitmarkerLines[i] = line
	end
end

local function buildBottom(parent)
	-- Health (bottom left).
	local health = new("Frame", {
		Name = "Health",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(280, 54),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.35,
		Parent = parent,
	}, { corner(8) })
	refs.HealthText = textStroke(label({
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.fromOffset(80, 30),
		Text = "100",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = health,
	}))
	label({
		Position = UDim2.fromOffset(72, 10),
		Size = UDim2.fromOffset(60, 20),
		Text = "HP",
		TextColor3 = DIM,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = health,
	})
	local barBack = new("Frame", {
		Position = UDim2.new(0, 14, 1, -16),
		Size = UDim2.new(1, -28, 0, 8),
		BackgroundColor3 = Color3.fromRGB(40, 42, 50),
		BorderSizePixel = 0,
		Parent = health,
	}, { corner(4) })
	refs.HealthBar = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(110, 230, 120),
		BorderSizePixel = 0,
		Parent = barBack,
	}, { corner(4) })

	-- Ammo + weapon name (bottom right).
	local ammo = new("Frame", {
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(260, 74),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.35,
		Parent = parent,
	}, { corner(8) })
	refs.WeaponName = textStroke(label({
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -28, 0, 20),
		Text = "",
		TextSize = 16,
		TextColor3 = ACCENT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ammo,
	}))
	refs.AmmoText = textStroke(label({
		Position = UDim2.fromOffset(14, 26),
		Size = UDim2.new(1, -28, 0, 40),
		Text = "",
		TextSize = 34,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ammo,
	}))

	-- Weapon slots above the ammo panel.
	local slots = new("Frame", {
		Name = "Slots",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -106),
		Size = UDim2.fromOffset(260, 140),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		new("UIListLayout", {
			Padding = UDim.new(0, 4),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	refs.Slots = {}
	for i, slotName in Config.SlotOrder do
		local frame = new("Frame", {
			Name = slotName,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.5,
			Parent = slots,
		}, { corner(6) })
		local key = label({
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(20, 30),
			Text = tostring(i),
			TextColor3 = DIM,
			TextSize = 14,
			Parent = frame,
		})
		local name = label({
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.new(1, -40, 1, 0),
			Text = "",
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = FONT_LIGHT,
			Parent = frame,
		})
		refs.Slots[slotName] = { Frame = frame, Key = key, Name = name }
	end

	-- Hint line.
	refs.Hint = textStroke(label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(600, 20),
		Text = "",
		TextSize = 14,
		TextColor3 = DIM,
		Font = FONT_LIGHT,
		Parent = parent,
	}))
end

local function buildTop(parent)
	local bar = new("Frame", {
		Name = "Score",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(300, 56),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.35,
		Parent = parent,
	}, { corner(8) })
	refs.RedScore = textStroke(label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.fromOffset(70, 48),
		Text = "0",
		TextSize = 34,
		TextColor3 = RED,
		Parent = bar,
	}))
	refs.BlueScore = textStroke(label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 4),
		Size = UDim2.fromOffset(70, 48),
		Text = "0",
		TextSize = 34,
		TextColor3 = BLUE,
		Parent = bar,
	}))
	refs.Timer = textStroke(label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(140, 28),
		Text = "",
		TextSize = 24,
		Parent = bar,
	}))
	refs.StateText = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 31),
		Size = UDim2.fromOffset(160, 18),
		Text = "",
		TextSize = 13,
		TextColor3 = DIM,
		Font = FONT_LIGHT,
		Parent = bar,
	})

	-- Big centre announcement.
	refs.Announce = textStroke(label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(900, 80),
		Text = "",
		TextSize = 64,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = parent,
	}))
	refs.AnnounceSub = textStroke(label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 54),
		Size = UDim2.fromOffset(900, 30),
		Text = "",
		TextSize = 22,
		TextColor3 = DIM,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = parent,
	}))

	-- Kill feed (top right).
	refs.KillFeed = new("Frame", {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20),
		Size = UDim2.fromOffset(380, 200),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		new("UIListLayout", {
			Padding = UDim.new(0, 4),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Spectating label.
	refs.Spectate = textStroke(label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(500, 30),
		Text = "",
		TextSize = 22,
		Visible = false,
		Parent = parent,
	}))
end

local function buildOverlays(parent)
	-- Sniper scope: black surround with a round window and a reticle.
	local scope = new("Frame", {
		Name = "Scope",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})
	local window = new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = scope,
	})
	-- Circle edge: a round frame with a very thick black stroke covers the
	-- corners of the square window.
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = window,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIStroke", { Thickness = 400, Color = Color3.new(0, 0, 0) }),
	})
	for _, info in {
		{ Vector2.new(1, 0.5), UDim2.new(0, 0, 0.5, 0) },
		{ Vector2.new(0, 0.5), UDim2.new(1, 0, 0.5, 0) },
	} do
		new("Frame", {
			AnchorPoint = info[1],
			Position = info[2],
			Size = UDim2.new(5, 0, 5, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = window,
		})
	end
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = window,
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = window,
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.fromRGB(255, 60, 60),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = window,
	}, { corner(2) })
	refs.Scope = scope

	-- Flashbang whiteout.
	refs.Flash = new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = parent,
	})

	-- Red vignette when hurt.
	refs.Hurt = new("Frame", {
		Name = "Hurt",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(150, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = parent,
	})

	-- Holder for directional damage arcs.
	refs.DamageHolder = new("Frame", {
		Name = "DamageIndicators",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
end

local function buildLoadoutMenu(parent)
	local menu = new("Frame", {
		Name = "Loadout",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(820, 420),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	}, { corner(12), stroke(2, ACCENT, 0.3) })

	label({
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -48, 0, 36),
		Text = "LOADOUT",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
		Parent = menu,
	})
	refs.MenuNote = label({
		Position = UDim2.fromOffset(24, 48),
		Size = UDim2.new(1, -48, 0, 20),
		Text = "Changes apply instantly in the lobby, or on your next spawn in a match.",
		TextSize = 14,
		TextColor3 = DIM,
		Font = FONT_LIGHT,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
		Parent = menu,
	})

	-- A full-size invisible modal button frees the mouse in first person.
	new("TextButton", {
		Name = "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Modal = true,
		ZIndex = 30,
		Parent = menu,
	})

	refs.MenuButtons = {}
	refs.Selection = table.clone(Config.DefaultLoadout)

	local columnWidth = 190
	for column, slotName in Config.SlotOrder do
		local x = 24 + (column - 1) * (columnWidth + 8)
		label({
			Position = UDim2.fromOffset(x, 82),
			Size = UDim2.fromOffset(columnWidth, 22),
			Text = string.upper(slotName),
			TextSize = 15,
			TextColor3 = ACCENT,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 31,
			Parent = menu,
		})
		refs.MenuButtons[slotName] = {}
		for row, weaponId in Config.LoadoutOptions[slotName] do
			local weapon = Config.getWeapon(weaponId)
			local button = new("TextButton", {
				Name = weaponId,
				Position = UDim2.fromOffset(x, 108 + (row - 1) * 60),
				Size = UDim2.fromOffset(columnWidth, 52),
				BackgroundColor3 = Color3.fromRGB(36, 38, 48),
				AutoButtonColor = true,
				Text = "",
				ZIndex = 31,
				Parent = menu,
			}, { corner(8) })
			label({
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -24, 0, 22),
				Text = weapon.DisplayName,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 32,
				Parent = button,
			})
			local detail
			if weapon.Kind == "Gun" then
				detail = string.format("%d dmg  ·  %d rpm  ·  %d mag", weapon.Damage * weapon.Pellets, weapon.RPM, weapon.MagSize)
			elseif weapon.Kind == "Melee" then
				detail = string.format("%d dmg  ·  %.1fs swing", weapon.Damage, weapon.Cooldown)
			else
				detail = string.format("%d charge%s", weapon.Charges, weapon.Charges == 1 and "" or "s")
			end
			label({
				Position = UDim2.fromOffset(12, 28),
				Size = UDim2.new(1, -24, 0, 18),
				Text = detail,
				TextSize = 12,
				TextColor3 = DIM,
				Font = FONT_LIGHT,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 32,
				Parent = button,
			})
			local outline = stroke(2, ACCENT, 1)
			outline.Parent = button
			refs.MenuButtons[slotName][weaponId] = outline

			button.MouseButton1Click:Connect(function()
				refs.Selection[slotName] = weaponId
				HUD.refreshMenu()
				Net.get("SetLoadout"):FireServer(refs.Selection)
			end)
		end
	end

	local close = new("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -18),
		Size = UDim2.fromOffset(140, 40),
		BackgroundColor3 = ACCENT,
		Text = "DONE  (M)",
		TextColor3 = PANEL,
		Font = FONT,
		TextSize = 16,
		ZIndex = 31,
		Parent = menu,
	}, { corner(8) })
	close.MouseButton1Click:Connect(function()
		HUD.setMenuOpen(false)
	end)

	refs.Menu = menu
	HUD.refreshMenu()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function HUD.init()
	gui = new("ScreenGui", {
		Name = "ArenaHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildCrosshair(gui)
	buildBottom(gui)
	buildTop(gui)
	buildOverlays(gui)
	buildLoadoutMenu(gui)
end

function HUD.refreshMenu()
	for slotName, outlines in refs.MenuButtons do
		for weaponId, outline in outlines do
			outline.Transparency = refs.Selection[slotName] == weaponId and 0 or 1
		end
	end
end

function HUD.isMenuOpen()
	return menuOpen
end

function HUD.setMenuOpen(open)
	menuOpen = open
	refs.Menu.Visible = open
end

function HUD.toggleMenu()
	HUD.setMenuOpen(not menuOpen)
end

-- Called every frame by the weapon controller.
-- info: { Spread (degrees), AdsAlpha, Kind, Scoped, Hidden }
function HUD.updateCrosshair(dt, info)
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local halfFov = math.rad(camera.FieldOfView / 2)
	local targetGap = math.tan(math.rad(info.Spread or 0)) / math.tan(halfFov) * (viewport.Y / 2)
	targetGap = math.clamp(targetGap, 4, 120)
	crosshairGap = Util.approach(crosshairGap, targetGap, 20, dt)

	local hidden = info.Hidden or info.Scoped or (info.Kind == "Gun" and (info.AdsAlpha or 0) > 0.6)
	refs.Crosshair.Visible = not hidden
	for _, line in refs.CrosshairLines do
		local vertical = line.Direction.X == 0
		local offset = line.Direction * (crosshairGap + 4)
		line.Frame.Position = UDim2.fromOffset(offset.X, offset.Y)
		line.Frame.Visible = info.Kind == "Gun"
		line.Frame.Size = vertical and UDim2.fromOffset(2, 8) or UDim2.fromOffset(8, 2)
	end

	refs.Scope.Visible = info.Scoped == true

	-- Hitmarker fade.
	local age = os.clock() - hitmarkerTime
	local alpha = math.clamp(age / 0.3, 0, 1)
	for _, line in refs.HitmarkerLines do
		line.BackgroundTransparency = alpha
		line.BackgroundColor3 = hitmarkerColor
	end

	-- Damage indicators fade.
	for i = #damageIndicators, 1, -1 do
		local indicator = damageIndicators[i]
		local life = os.clock() - indicator.Start
		if life > 1.5 then
			indicator.Frame:Destroy()
			table.remove(damageIndicators, i)
		else
			-- Keep pointing at the source as the camera turns.
			local look = camera.CFrame.LookVector
			local toSource = indicator.Source - camera.CFrame.Position
			local angle = math.atan2(toSource.X, toSource.Z) - math.atan2(look.X, look.Z)
			indicator.Frame.Rotation = -math.deg(angle)
			indicator.Bar.BackgroundTransparency = 0.2 + 0.8 * (life / 1.5)
		end
	end
end

function HUD.hitmarker(headshot, killed)
	hitmarkerTime = os.clock()
	hitmarkerColor = killed and RED or (headshot and HEAD or WHITE)
	local size = killed and 14 or 10
	for _, line in refs.HitmarkerLines do
		line.Size = UDim2.fromOffset(size, killed and 3 or 2)
	end
end

function HUD.damageFrom(sourcePosition)
	if typeof(sourcePosition) ~= "Vector3" then
		return
	end
	local frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = refs.DamageHolder,
	})
	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, -120),
		Size = UDim2.fromOffset(90, 8),
		BackgroundColor3 = Color3.fromRGB(255, 40, 40),
		BorderSizePixel = 0,
		Parent = frame,
	}, { corner(4) })
	table.insert(damageIndicators, { Frame = frame, Bar = bar, Source = sourcePosition, Start = os.clock() })

	refs.Hurt.BackgroundTransparency = 0.7
	TweenService:Create(refs.Hurt, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end

function HUD.setHealth(health, maxHealth)
	local ratio = maxHealth > 0 and math.clamp(health / maxHealth, 0, 1) or 0
	refs.HealthText.Text = tostring(math.ceil(health))
	refs.HealthBar.Size = UDim2.fromScale(ratio, 1)
	refs.HealthBar.BackgroundColor3 = Color3.fromRGB(235, 70, 70):Lerp(Color3.fromRGB(110, 230, 120), ratio)
end

-- slots: { [slotName] = weaponId }, equipped: slotName
function HUD.setSlots(slots, equipped, charges)
	for slotName, ref in refs.Slots do
		local id = slots[slotName]
		local weapon = id and Config.getWeapon(id)
		local name = weapon and weapon.DisplayName or "-"
		if slotName == "Utility" and weapon then
			name = string.format("%s  x%d", name, charges or 0)
		end
		ref.Name.Text = name
		local active = slotName == equipped
		ref.Frame.BackgroundTransparency = active and 0.15 or 0.55
		ref.Name.TextColor3 = active and ACCENT or WHITE
	end
end

function HUD.setAmmo(weaponName, mag, reserve, reloading)
	refs.WeaponName.Text = string.upper(weaponName or "")
	if mag == nil then
		refs.AmmoText.Text = ""
	elseif reloading then
		refs.AmmoText.Text = '<font color="#ffbe3c">RELOADING</font>'
	else
		local color = mag == 0 and "#eb4646" or "#ffffff"
		refs.AmmoText.Text = string.format('<font color="%s">%d</font> <font size="20" color="#a0a5af">/ %d</font>', color, mag, reserve)
	end
end

function HUD.setHint(text)
	refs.Hint.Text = text or ""
end

function HUD.announce(title, subtitle, duration, color)
	refs.Announce.Text = title
	refs.Announce.TextColor3 = color or WHITE
	refs.AnnounceSub.Text = subtitle or ""
	for _, labelRef in { refs.Announce, refs.AnnounceSub } do
		labelRef.TextTransparency = 0
		labelRef.TextStrokeTransparency = 0.6
	end
	refs.Announce.TextSize = 80
	TweenService:Create(refs.Announce, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 64 }):Play()

	local token = {}
	refs.AnnounceToken = token
	task.delay(duration or 2, function()
		if refs.AnnounceToken ~= token then
			return
		end
		for _, labelRef in { refs.Announce, refs.AnnounceSub } do
			TweenService:Create(labelRef, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function HUD.killFeed(killer, victim, weaponName, headshot)
	local text
	if killer == "" then
		text = string.format("%s died", victim)
	else
		text = string.format("%s  [%s%s]  %s", killer, weaponName, headshot and " ✦" or "", victim)
	end
	local involved = killer == player.DisplayName or victim == player.DisplayName

	local entry = new("Frame", {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = involved and Color3.fromRGB(60, 50, 20) or PANEL,
		BackgroundTransparency = 0.3,
		LayoutOrder = -math.floor(os.clock() * 100),
		Parent = refs.KillFeed,
	}, {
		corner(6),
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	label({
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		TextSize = 15,
		TextColor3 = headshot and HEAD or WHITE,
		Parent = entry,
	})

	local children = {}
	for _, child in refs.KillFeed:GetChildren() do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	if #children > 6 then
		table.sort(children, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		children[1]:Destroy()
	end

	task.delay(6, function()
		if entry.Parent then
			entry:Destroy()
		end
	end)
end

function HUD.setMatch(state, round, redScore, blueScore, timeLeft)
	refs.RedScore.Text = tostring(redScore)
	refs.BlueScore.Text = tostring(blueScore)
	if state == "Waiting" then
		refs.Timer.Text = "LOBBY"
		refs.StateText.Text = "Waiting for players"
	elseif state == "Intermission" then
		refs.Timer.Text = tostring(timeLeft)
		refs.StateText.Text = "Match starting"
	elseif state == "RoundStart" then
		refs.Timer.Text = tostring(timeLeft)
		refs.StateText.Text = "Round " .. round
	elseif state == "Round" then
		refs.Timer.Text = Util.formatTime(timeLeft)
		refs.StateText.Text = "Round " .. round
	elseif state == "RoundEnd" then
		refs.Timer.Text = "-"
		refs.StateText.Text = "Round over"
	elseif state == "MatchEnd" then
		refs.Timer.Text = "-"
		refs.StateText.Text = "Match over"
	end
end

function HUD.flash(intensity, duration)
	refs.Flash.BackgroundTransparency = 1 - math.clamp(intensity, 0, 1)
	TweenService:Create(
		refs.Flash,
		TweenInfo.new(duration * intensity, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	):Play()
end

function HUD.setSpectating(name)
	refs.Spectate.Visible = name ~= nil
	refs.Spectate.Text = name and ("SPECTATING  " .. string.upper(name)) or ""
end

function HUD.setCombatVisible(visible)
	for _, key in { "Crosshair" } do
		if not visible then
			refs[key].Visible = false
		end
	end
	gui.Health.Visible = visible
	gui.Ammo.Visible = visible
	gui.Slots.Visible = visible
end

return HUD
