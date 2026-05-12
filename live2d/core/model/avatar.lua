local ISerializable = require("live2d.core.io.iserializable")

local Avatar = setmetatable({}, { __index = ISerializable })
Avatar.__index = Avatar

function Avatar.new()
    local self = setmetatable(ISerializable.new(), Avatar)
    self.id = nil
    self.deformerList = nil
    self.drawDataList = nil
    return self
end

function Avatar:getDeformer()
    return self.deformerList
end

function Avatar:getDrawDataList()
    return self.drawDataList
end

function Avatar:read(br)
    self.id = br:readObject()
    self.drawDataList = br:readObject()
    self.deformerList = br:readObject()
end

function Avatar:replacePartsData(parts)
    parts:setDeformer(self.deformerList)
    parts:setDrawDataList(self.drawDataList)
    self.deformerList = nil
    self.drawDataList = nil
end

return Avatar
