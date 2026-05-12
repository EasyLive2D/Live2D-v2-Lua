local L2DMatrix44 = require("live2d.framework.matrix.l2d_matrix44")

local L2DViewMatrix = setmetatable({}, { __index = L2DMatrix44 })
L2DViewMatrix.__index = L2DViewMatrix

function L2DViewMatrix.new()
    local self = setmetatable(L2DMatrix44.new(), L2DViewMatrix)
    self.screenLeft = nil
    self.screenRight = nil
    self.screenTop = nil
    self.screenBottom = nil
    self.maxLeft = nil
    self.maxRight = nil
    self.maxTop = nil
    self.maxBottom = nil
    self.max = math.huge
    self.min = 0
    return self
end

function L2DViewMatrix:getMaxScale() return self.max end
function L2DViewMatrix:getMinScale() return self.min end
function L2DViewMatrix:setMaxScale(v) self.max = v end
function L2DViewMatrix:setMinScale(v) self.min = v end
function L2DViewMatrix:isMaxScale() return self:getScaleX() == self.max end
function L2DViewMatrix:isMinScale() return self:getScaleX() == self.min end

function L2DViewMatrix:adjustTranslate(shift_x, shift_y)
    if self.tr[1] * self.maxLeft + (self.tr[13] + shift_x) > self.screenLeft then
        shift_x = self.screenLeft - self.tr[1] * self.maxLeft - self.tr[13]
    end
    if self.tr[1] * self.maxRight + (self.tr[13] + shift_x) < self.screenRight then
        shift_x = self.screenRight - self.tr[1] * self.maxRight - self.tr[13]
    end
    if self.tr[6] * self.maxTop + (self.tr[14] + shift_y) < self.screenTop then
        shift_y = self.screenTop - self.tr[6] * self.maxTop - self.tr[14]
    end
    if self.tr[6] * self.maxBottom + (self.tr[14] + shift_y) > self.screenBottom then
        shift_y = self.screenBottom - self.tr[6] * self.maxBottom - self.tr[14]
    end
    local tr1 = {1,0,0,0,0,1,0,0,0,0,1,0,shift_x,shift_y,0,1}
    L2DMatrix44.mul(tr1, self.tr, self.tr)
end

function L2DViewMatrix:adjustScale(cx, cy, scale)
    local target_scale = scale * self.tr[1]
    if target_scale < self.min then
        if self.tr[1] > 0 then scale = self.min / self.tr[1] end
    elseif target_scale > self.max then
        if self.tr[1] > 0 then scale = self.max / self.tr[1] end
    end
    local tr1 = {1,0,0,0,0,1,0,0,0,0,1,0,cx,cy,0,1}
    local tr2 = {scale,0,0,0,0,scale,0,0,0,0,1,0,0,0,0,1}
    local tr3 = {1,0,0,0,0,1,0,0,0,0,1,0,-cx,-cy,0,1}
    L2DMatrix44.mul(tr3, self.tr, self.tr)
    L2DMatrix44.mul(tr2, self.tr, self.tr)
    L2DMatrix44.mul(tr1, self.tr, self.tr)
end

function L2DViewMatrix:setScreenRect(left, right, bottom, top)
    self.screenLeft = left; self.screenRight = right
    self.screenTop = top; self.screenBottom = bottom
end

function L2DViewMatrix:setMaxScreenRect(left, right, bottom, top)
    self.maxLeft = left; self.maxRight = right
    self.maxTop = top; self.maxBottom = bottom
end

function L2DViewMatrix:getScreenLeft() return self.screenLeft end
function L2DViewMatrix:getScreenRight() return self.screenRight end
function L2DViewMatrix:getScreenBottom() return self.screenBottom end
function L2DViewMatrix:getScreenTop() return self.screenTop end
function L2DViewMatrix:getMaxLeft() return self.maxLeft end
function L2DViewMatrix:getMaxRight() return self.maxRight end
function L2DViewMatrix:getMaxBottom() return self.maxBottom end
function L2DViewMatrix:getMaxTop() return self.maxTop end

return L2DViewMatrix
