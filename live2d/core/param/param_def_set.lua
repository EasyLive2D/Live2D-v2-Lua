local ISerializable = require("live2d.core.io.iserializable")

local ParamDefSet = setmetatable({}, { __index = ISerializable })
ParamDefSet.__index = ParamDefSet

function ParamDefSet.new()
    local self = setmetatable(ISerializable.new(), ParamDefSet)
    self.paramDefList = nil
    return self
end

function ParamDefSet:getParamDefFloatList()
    return self.paramDefList
end

function ParamDefSet:read(br)
    self.paramDefList = br:readObject()
end

return ParamDefSet
