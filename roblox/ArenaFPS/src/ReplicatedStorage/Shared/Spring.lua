-- Spring: critically-dampable spring used for recoil, sway and camera kick.
-- Works on numbers or Vector3s.

local Spring = {}
Spring.__index = Spring

function Spring.new(initial, stiffness, damping)
	local self = setmetatable({}, Spring)
	self.Position = initial
	self.Velocity = initial * 0
	self.Target = initial
	self.Stiffness = stiffness or 120
	self.Damping = damping or 14
	return self
end

-- Adds instant velocity (a "kick").
function Spring:Impulse(velocity)
	self.Velocity += velocity
end

function Spring:Update(dt)
	-- Sub-step so large frame times stay stable.
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local step = dt / steps
	for _ = 1, steps do
		local force = (self.Target - self.Position) * self.Stiffness
		local damp = self.Velocity * self.Damping
		self.Velocity += (force - damp) * step
		self.Position += self.Velocity * step
	end
	return self.Position
end

function Spring:Reset(value)
	self.Position = value
	self.Velocity = value * 0
	self.Target = value
end

return Spring
