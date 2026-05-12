local PhysicsPoint = {}
PhysicsPoint.__index = PhysicsPoint

function PhysicsPoint.new()
    local self = setmetatable({}, PhysicsPoint)
    self.mass = 1
    self.x = 0
    self.y = 0
    self.vx = 0
    self.vy = 0
    self.ax = 0
    self.ay = 0
    self.fx = 0
    self.fy = 0
    self.lastX = 0
    self.lastY = 0
    self.lastVX = 0
    self.lastVY = 0
    return self
end

function PhysicsPoint:setupLast()
    self.lastX = self.x
    self.lastY = self.y
    self.lastVX = self.vx
    self.lastVY = self.vy
end

return PhysicsPoint
