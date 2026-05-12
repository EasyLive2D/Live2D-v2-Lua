local C = require("live2d.core.physics.physics_constants")
local PhysicsPoint = require("live2d.core.physics.physics_point")
local PhysicsSrc = require("live2d.core.physics.physics_src")
local PhysicsTarget = require("live2d.core.physics.physics_target")
local UtMath = require("live2d.core.util.ut_math")

local PhysicsHair = {}
PhysicsHair.__index = PhysicsHair

PhysicsHair.SRC_TO_X = C.SRC_TO_X
PhysicsHair.SRC_TO_Y = C.SRC_TO_Y
PhysicsHair.SRC_TO_G_ANGLE = C.SRC_TO_G_ANGLE
PhysicsHair.TARGET_FROM_ANGLE = C.TARGET_FROM_ANGLE
PhysicsHair.TARGET_FROM_ANGLE_V = C.TARGET_FROM_ANGLE_V

function PhysicsHair.new()
    local self = setmetatable({}, PhysicsHair)
    self.p1 = PhysicsPoint.new()
    self.p2 = PhysicsPoint.new()
    self.Fo_ = 0
    self.Db_ = 0
    self.L2_ = 0
    self.M2_ = 0
    self.ks_ = 0
    self._9b = 0
    self.iP_ = 0
    self.iT_ = 0
    self.lL_ = {}
    self.qP_ = {}
    self:setup(0.3, 0.5, 0.1)
    return self
end

function PhysicsHair:setup(aJ, aI, aH)
    self.ks_ = self:Yb_()
    self.p2:setupLast()
    if aH ~= nil then
        self.Fo_ = aJ
        self.L2_ = aI
        self.p1.mass = aH
        self.p2.mass = aH
        self.p2.y = aJ
        self:setup()
    end
end

function PhysicsHair:getPhysicsPoint1()
    return self.p1
end

function PhysicsHair:getPhysicsPoint2()
    return self.p2
end

function PhysicsHair:qr_()
    return self.Db_
end

function PhysicsHair:pr_(aH)
    self.Db_ = aH
end

function PhysicsHair:_5r()
    return self.M2_
end

function PhysicsHair:Cs_()
    return self._9b
end

function PhysicsHair:Yb_()
    return -180 * math.atan2(self.p1.x - self.p2.x, -(self.p1.y - self.p2.y)) / math.pi
end

function PhysicsHair:addSrcParam(aJ, aH, aL, aI)
    local aK = PhysicsSrc.new(aJ, aH, aL, aI)
    self.lL_[#self.lL_ + 1] = aK
end

function PhysicsHair:addTargetParam(aJ, aH, aK, aI)
    local aL = PhysicsTarget.new(aJ, aH, aK, aI)
    self.qP_[#self.qP_ + 1] = aL
end

function PhysicsHair:update(aI, aL)
    if self.iP_ == 0 then
        self.iP_ = aL
        self.iT_ = aL
        self.Fo_ = math.sqrt((self.p1.x - self.p2.x) * (self.p1.x - self.p2.x) +
                             (self.p1.y - self.p2.y) * (self.p1.y - self.p2.y))
        return
    end

    local aK = (aL - self.iT_) / 1000
    if aK ~= 0 then
        for aJ = #self.lL_, 1, -1 do
            local aM = self.lL_[aJ]
            aM:update(aI, self)
        end

        self:oo_(aI, aK)
        self.M2_ = self:Yb_()
        self._9b = (self.M2_ - self.ks_) / aK
        self.ks_ = self.M2_
    end

    for aJ = #self.qP_, 1, -1 do
        local aH = self.qP_[aJ]
        aH:update(aI, self)
    end

    self.iT_ = aL
end

function PhysicsHair:oo_(aN, aI)
    if aI < 0.033 then aI = 0.033 end

    local aU = 1 / aI
    self.p1.vx = (self.p1.x - self.p1.lastX) * aU
    self.p1.vy = (self.p1.y - self.p1.lastY) * aU
    self.p1.ax = (self.p1.vx - self.p1.lastVX) * aU
    self.p1.ay = (self.p1.vy - self.p1.lastVY) * aU
    self.p1.fx = self.p1.ax * self.p1.mass
    self.p1.fy = self.p1.ay * self.p1.mass
    self.p1:setupLast()

    local aM = -math.atan2(self.p1.y - self.p2.y, self.p1.x - self.p2.x)
    local aR = math.cos(aM)
    local aH = math.sin(aM)
    local aW = 9.8 * self.p2.mass
    local aQ = self.Db_ * UtMath.DEG_TO_RAD
    local aP = aW * math.cos(aM - aQ)
    local aL = aP * aH
    local aV = aP * aR
    local aK = -self.p1.fx * aH * aH
    local aT = -self.p1.fy * aH * aR
    local aJ = -self.p2.vx * self.L2_
    local aS = -self.p2.vy * self.L2_
    self.p2.fx = aL + aK + aJ
    self.p2.fy = aV + aT + aS
    self.p2.ax = self.p2.fx / self.p2.mass
    self.p2.ay = self.p2.fy / self.p2.mass
    self.p2.vx = self.p2.vx + self.p2.ax * aI
    self.p2.vy = self.p2.vy + self.p2.ay * aI
    self.p2.x = self.p2.x + self.p2.vx * aI
    self.p2.y = self.p2.y + self.p2.vy * aI
    local aO = math.sqrt((self.p1.x - self.p2.x) * (self.p1.x - self.p2.x) +
                         (self.p1.y - self.p2.y) * (self.p1.y - self.p2.y))
    self.p2.x = self.p1.x + self.Fo_ * (self.p2.x - self.p1.x) / aO
    self.p2.y = self.p1.y + self.Fo_ * (self.p2.y - self.p1.y) / aO
    self.p2.vx = (self.p2.x - self.p2.lastX) * aU
    self.p2.vy = (self.p2.y - self.p2.lastY) * aU
    self.p2:setupLast()
end

return PhysicsHair
