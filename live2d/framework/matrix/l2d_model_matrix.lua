local L2DMatrix44 = require("live2d.framework.matrix.l2d_matrix44")

local L2DModelMatrix = setmetatable({}, { __index = L2DMatrix44 })
L2DModelMatrix.__index = L2DModelMatrix

function L2DModelMatrix.new(w, h)
    local self = setmetatable(L2DMatrix44.new(), L2DModelMatrix)
    self.width = w or 0
    self.height = h or 0
    self.ocx = 0
    self.ocy = 0
    return self
end

function L2DModelMatrix:setPosition(x, y)
    self:translate(x, y)
end

function L2DModelMatrix:setCenterPosition(x, y)
    self.ocx = x
    self.ocy = y
    local w = self.width * self:getScaleX()
    local h = self.height * self:getScaleY()
    self:translate(x - w / 2, y - h / 2)
end

function L2DModelMatrix:top(y)
    self:setY(y)
end

function L2DModelMatrix:bottom(y)
    local h = self.height * self:getScaleY()
    self:translateY(y - h)
end

function L2DModelMatrix:left(x)
    self:setX(x)
end

function L2DModelMatrix:right(x)
    local w = self.width * self:getScaleX()
    self:translateX(x - w)
end

function L2DModelMatrix:centerX(x)
    local w = self.width * self:getScaleX()
    self:translateX(x - w / 2)
end

function L2DModelMatrix:centerY(y)
    local h = self.height * self:getScaleY()
    self:translateY(y - h / 2)
end

function L2DModelMatrix:setX(x)
    self:translateX(x)
end

function L2DModelMatrix:setY(y)
    self:translateY(y)
end

function L2DModelMatrix:setHeight(h)
    local scale_x = h / self.height
    local scale_y = -scale_x
    self:scale(scale_x, scale_y)
end

function L2DModelMatrix:setWidth(w)
    local scale_x = w / self.width
    local scale_y = -scale_x
    self:scale(scale_x, scale_y)
end

return L2DModelMatrix
