local Id = require("live2d.core.id.id")

local L2DPartsParam = {}
L2DPartsParam.__index = L2DPartsParam

function L2DPartsParam.new(ppid)
    local self = setmetatable({}, L2DPartsParam)
    self.paramIndex = -1
    self.partsIndex = -1
    self.link = nil
    self.id = ppid
    return self
end

function L2DPartsParam:initIndex(model)
    self.paramIndex = model:getParamIndex("VISIBLE:" .. self.id)
    self.partsIndex = model:getPartsDataIndex(Id.getID(self.id))
    model:setParamFloat(self.paramIndex, 1)
end

return L2DPartsParam
