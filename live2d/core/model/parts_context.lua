local PartsDataContext = {}
PartsDataContext.__index = PartsDataContext

function PartsDataContext.new(parts)
    local self = setmetatable({}, PartsDataContext)
    self.partsOpacity = nil
    self.partsData = parts
    self.screenColor = {0.0, 0.0, 0.0, 0.0}
    self.multiplyColor = {1.0, 1.0, 1.0, 0.0}
    return self
end

function PartsDataContext:getPartsOpacity()
    return self.partsOpacity
end

function PartsDataContext:setPartsOpacity(value)
    self.partsOpacity = value
end

return PartsDataContext
