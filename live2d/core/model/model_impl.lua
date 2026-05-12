local ISerializable = require("live2d.core.io.iserializable")

local ModelImpl = setmetatable({}, { __index = ISerializable })
ModelImpl.__index = ModelImpl

function ModelImpl.new()
    local self = setmetatable(ISerializable.new(), ModelImpl)
    self.paramDefSet = nil
    self.partsDataList = nil
    self.canvasWidth = 400
    self.canvasHeight = 400
    return self
end

function ModelImpl:initDirect()
    if self.paramDefSet == nil then
        self.paramDefSet = require("live2d.core.param.param_def_set").new()
    end
    if self.partsDataList == nil then
        self.partsDataList = {}
    end
end

function ModelImpl:getCanvasWidth()
    return self.canvasWidth
end

function ModelImpl:getCanvasHeight()
    return self.canvasHeight
end

function ModelImpl:read(br)
    self.paramDefSet = br:readObject()
    self.partsDataList = br:readObject()
    self.canvasWidth = br:readInt32()
    self.canvasHeight = br:readInt32()
end

function ModelImpl:getPartsDataList()
    return self.partsDataList
end

function ModelImpl:getParamDefSet()
    return self.paramDefSet
end

return ModelImpl
