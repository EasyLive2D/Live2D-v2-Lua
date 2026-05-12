local IPhysicsParam = require("live2d.core.physics.iphysics_param")
local C = require("live2d.core.physics.physics_constants")

local PhysicsSrc = setmetatable({}, { __index = IPhysicsParam })
PhysicsSrc.__index = PhysicsSrc

function PhysicsSrc.new(paramId, aK, scale, weight)
    local self = setmetatable(IPhysicsParam.new(aK, scale, weight), PhysicsSrc)
    self.tL_ = paramId
    return self
end

function PhysicsSrc:update(aJ, aH)
    local aK = self.scale * aJ:getParamFloat(self.paramId)
    local aL = aH:getPhysicsPoint1()
    if self.tL_ == C.SRC_TO_X then
        aL.x = aL.x + (aK - aL.x) * self.weight
    elseif self.tL_ == C.SRC_TO_Y then
        aL.y = aL.y + (aK - aL.y) * self.weight
    elseif self.tL_ == C.SRC_TO_G_ANGLE then
        local aI = aH:qr_()
        aI = aI + (aK - aI) * self.weight
        aH:pr_(aI)
    end
end

return PhysicsSrc
