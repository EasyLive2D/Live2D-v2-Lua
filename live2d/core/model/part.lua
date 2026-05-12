local PartsDataContext = require("live2d.core.model.parts_context")
local ISerializable = require("live2d.core.io.iserializable")

local PartsData = setmetatable({}, { __index = ISerializable })
PartsData.__index = PartsData

function PartsData.new()
    local self = setmetatable(ISerializable.new(), PartsData)
    self.visible = true
    self.locked = false
    self.id = nil
    self.deformerList = nil
    self.drawDataList = nil
    return self
end

function PartsData:initDirect()
    self.deformerList = {}
    self.drawDataList = {}
end

function PartsData:read(aH)
    self.locked = aH:readBit()
    self.visible = aH:readBit()
    self.id = aH:readObject()
    self.deformerList = aH:readObject()
    self.drawDataList = aH:readObject()
end

function PartsData:init()
    local aH = PartsDataContext.new(self)
    if self:isVisible() then
        aH:setPartsOpacity(1)
    else
        aH:setPartsOpacity(0)
    end
    return aH
end

function PartsData:setDeformerList(aH)
    self.deformerList = aH
end

function PartsData:setDrawDataList(aH)
    self.drawDataList = aH
end

function PartsData:isVisible()
    return self.visible
end

function PartsData:isLocked()
    return self.locked
end

function PartsData:setVisible(aH)
    self.visible = aH
end

function PartsData:setLocked(aH)
    self.locked = aH
end

function PartsData:getDeformer()
    return self.deformerList
end

function PartsData:getDrawData()
    return self.drawDataList
end

function PartsData:getId()
    return self.id
end

function PartsData:setId(aH)
    self.id = aH
end

return PartsData
