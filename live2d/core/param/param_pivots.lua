local ISerializable = require("live2d.core.io.iserializable")

local ParamPivots = setmetatable({}, { __index = ISerializable })
ParamPivots.__index = ParamPivots

ParamPivots.PARAM_INDEX_NOT_INIT = -2

function ParamPivots.new()
    local self = setmetatable(ISerializable.new(), ParamPivots)
    self.pivotCount = 0
    self.paramId = nil
    self.pivotValues = nil
    self.paramIndex = ParamPivots.PARAM_INDEX_NOT_INIT
    self.initVersion = -1
    self.tmpPivotIndex = 0
    self.tmpT = 0
    return self
end

function ParamPivots:read(br)
    self.paramId = br:readObject()
    self.pivotCount = br:readInt32()
    self.pivotValues = br:readObject()
end

function ParamPivots:getParamIndex(initVersion)
    if self.initVersion ~= initVersion then
        self.paramIndex = ParamPivots.PARAM_INDEX_NOT_INIT
    end
    return self.paramIndex
end

function ParamPivots:setParamIndex(index, initVersion)
    self.paramIndex = index
    self.initVersion = initVersion
end

function ParamPivots:getParamID()
    return self.paramId
end

function ParamPivots:getPivotCount()
    return self.pivotCount
end

function ParamPivots:getPivotValues()
    return self.pivotValues
end

function ParamPivots:getTmpPivotIndex()
    return self.tmpPivotIndex
end

function ParamPivots:setTmpPivotIndex(index)
    self.tmpPivotIndex = index
end

function ParamPivots:getTmpT()
    return self.tmpT
end

function ParamPivots:setTmpT(value)
    self.tmpT = value
end

return ParamPivots
