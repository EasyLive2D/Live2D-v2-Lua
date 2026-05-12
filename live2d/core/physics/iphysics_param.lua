local IPhysicsParam = {}
IPhysicsParam.__index = IPhysicsParam

function IPhysicsParam.new(paramId, scale, weight)
    local self = setmetatable({}, IPhysicsParam)
    self.paramId = paramId
    self.scale = scale
    self.weight = weight
    return self
end

function IPhysicsParam:update(aI, aH)
    error("abstract method: update() not implemented")
end

return IPhysicsParam
