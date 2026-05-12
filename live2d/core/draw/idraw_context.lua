local IDrawContext = {}
IDrawContext.__index = IDrawContext

function IDrawContext.new(dd)
    local self = setmetatable({}, IDrawContext)
    self.interpolatedDrawOrder = nil
    self.paramOutside = {false}
    self.partsOpacity = 0
    self.available = true
    self.baseOpacity = 1.0
    self.clipBufPre_clipContext = nil
    self.drawData = dd
    self.partsIndex = -1
    return self
end

function IDrawContext:isParamOutside()
    return self.paramOutside[1]
end

function IDrawContext:isAvailable()
    return self.available and not self.paramOutside[1]
end

function IDrawContext:getDrawData()
    return self.drawData
end

return IDrawContext
