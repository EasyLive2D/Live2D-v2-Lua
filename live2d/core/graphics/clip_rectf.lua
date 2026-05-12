local ClipRectF = {}
ClipRectF.__index = ClipRectF

function ClipRectF.new()
    local self = setmetatable({}, ClipRectF)
    self.x = nil
    self.y = nil
    self.width = nil
    self.height = nil
    return self
end

function ClipRectF:getRight()
    return self.x + self.width
end

function ClipRectF:getBottom()
    return self.y + self.height
end

function ClipRectF:expand(aH, aI)
    self.x = self.x - aH
    self.y = self.y - aI
    self.width = self.width + aH * 2
    self.height = self.height + aI * 2
end

function ClipRectF:setRect(other)
    self.x = other.x
    self.y = other.y
    self.width = other.width
    self.height = other.height
end

return ClipRectF
