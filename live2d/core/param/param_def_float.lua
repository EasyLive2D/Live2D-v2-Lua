local ISerializable = require("live2d.core.io.iserializable")

local ParamDefFloat = setmetatable({}, { __index = ISerializable })
ParamDefFloat.__index = ParamDefFloat

function ParamDefFloat.new()
    local self = setmetatable(ISerializable.new(), ParamDefFloat)
    self.minValue = nil
    self.maxValue = nil
    self.defaultValue = nil
    self.paramId = nil
    return self
end

function ParamDefFloat:read(br)
    self.minValue = br:readFloat32()
    self.maxValue = br:readFloat32()
    self.defaultValue = br:readFloat32()
    self.paramId = br:readObject()
end

function ParamDefFloat:getMinValue()
    return self.minValue
end

function ParamDefFloat:getMaxValue()
    return self.maxValue
end

function ParamDefFloat:getDefaultValue()
    return self.defaultValue
end

function ParamDefFloat:getParamID()
    return self.paramId
end

return ParamDefFloat
