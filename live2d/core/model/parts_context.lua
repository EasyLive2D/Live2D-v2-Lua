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

function PartsDataContext:setPartScreenColor(r, g, b, a)
    self.screenColor[1] = r
    self.screenColor[2] = g
    self.screenColor[3] = b
    self.screenColor[4] = a
end

function PartsDataContext:setPartMultiplyColor(r, g, b, a)
    self.multiplyColor[1] = r
    self.multiplyColor[2] = g
    self.multiplyColor[3] = b
    self.multiplyColor[4] = a
end

return PartsDataContext
