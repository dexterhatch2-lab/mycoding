-- Dummies: training targets in the lobby so you can test weapons solo.
-- Some stand still, some strafe left and right. They respawn after dying.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Dummies = {}

local folder

-- Simple block rig used if Roblox can't build an avatar (e.g. API failure).
local function buildFallbackRig()
	local model = Instance.new("Model")

	local function block(name, size, offset, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = CFrame.new(offset)
		p.Parent = model
		return p
	end

	local root = block("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), Color3.new(1, 1, 1))
	root.Transparency = 1
	local torso = block("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), Color3.fromRGB(200, 80, 60))
	local head = block("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), Color3.fromRGB(240, 200, 160))
	local leftArm = block("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), Color3.fromRGB(240, 200, 160))
	local rightArm = block("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), Color3.fromRGB(240, 200, 160))
	local leftLeg = block("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), Color3.fromRGB(50, 60, 90))
	local rightLeg = block("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), Color3.fromRGB(50, 60, 90))

	for _, p in { torso, head, leftArm, rightArm, leftLeg, rightLeg } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function buildRig()
	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		description.HeadColor = Color3.fromRGB(240, 200, 160)
		description.TorsoColor = Color3.fromRGB(200, 80, 60)
		description.LeftArmColor = Color3.fromRGB(240, 200, 160)
		description.RightArmColor = Color3.fromRGB(240, 200, 160)
		description.LeftLegColor = Color3.fromRGB(50, 60, 90)
		description.RightLegColor = Color3.fromRGB(50, 60, 90)
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	warn("[Dummies] Falling back to block rig:", model)
	return buildFallbackRig()
end

local function spawnDummy(index, position, strafes)
	local model = buildRig()
	model.Name = "Training Dummy " .. index
	model:SetAttribute("IsDummy", true)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = Config.DummyHealth
	humanoid.Health = Config.DummyHealth
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.BreakJointsOnDeath = false

	-- Face the lobby spawn (+Z).
	model:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))

	local root = model:FindFirstChild("HumanoidRootPart")
	if root and not strafes then
		root.Anchored = true
	end

	model.Parent = folder
	if root and root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end

	if strafes and root then
		humanoid.WalkSpeed = 12
		task.spawn(function()
			local left = position + Vector3.new(-6, 0, 0)
			local right = position + Vector3.new(6, 0, 0)
			local goRight = true
			while model.Parent and humanoid.Health > 0 do
				humanoid:MoveTo(goRight and right or left)
				humanoid.MoveToFinished:Wait()
				goRight = not goRight
				task.wait(math.random() * 0.4)
			end
		end)
	end

	humanoid.Died:Connect(function()
		task.wait(3)
		model:Destroy()
		spawnDummy(index, position, strafes)
	end)
end

function Dummies.spawnAll(spots)
	folder = workspace:FindFirstChild("Dummies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Dummies"
		folder.Parent = workspace
	end
	for i, spot in spots do
		task.spawn(spawnDummy, i, spot[1], spot[2])
	end
end

return Dummies
