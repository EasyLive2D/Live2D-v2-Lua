local IPhysicsParam = require("live2d.core.physics.iphysics_param")
local C = require("live2d.core.physics.physics_constants")

local PhysicsTarget = setmetatable({}, { __index = IPhysicsParam })
PhysicsTarget.__index = PhysicsTarget

function PhysicsTarget.new(scale, aK, paramId, weight)
    local self = setmetatable(IPhysicsParam.new(aK, paramId, weight), PhysicsTarget)
    self.YP_ = scale
    return self
end

function PhysicsTarget:update(aI, aH)
    if self.YP_ == C.TARGET_FROM_ANGLE then
        aI:setParamFloat(self.paramId, self.scale * aH:_5r(), self.weight)
    elseif self.YP_ == C.TARGET_FROM_ANGLE_V then
        aI:setParamFloat(self.paramId, self.scale * aH:Cs_(), self.weight)
    end
end

return PhysicsTarget
