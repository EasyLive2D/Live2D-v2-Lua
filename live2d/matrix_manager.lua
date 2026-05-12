local L2DMatrix44 = require("live2d.framework.matrix.l2d_matrix44")

local MatrixManager = {}
MatrixManager.__index = MatrixManager

function MatrixManager.new()
    local self = setmetatable({}, MatrixManager)
    self._projection = L2DMatrix44.new()
    self._screenToScene = L2DMatrix44.new()
    self._ww = 600
    self._wh = 600
    self._offsetX = 0
    self._offsetY = 0
    self._scale = 1
    return self
end

function MatrixManager:getWidth() return self._ww end
function MatrixManager:getHeight() return self._wh end

function MatrixManager:onResize(width, height)
    self._ww = width
    self._wh = height
    local ratio = width / height
    local left = -ratio
    local right = ratio
    local bottom = -1.0
    local top = 1.0
    self._screenToScene:identity()
    self._screenToScene:multTranslate(-width / 2, -height / 2)
    if width > height then
        local sw = math.abs(right - left)
        self._screenToScene:multScale(sw / width, -sw / width)
    else
        local sh = math.abs(top - bottom)
        self._screenToScene:multScale(sh / height, -sh / height)
    end
end

function MatrixManager:screenToScene(scr_x, scr_y)
    return self._screenToScene:transformX(scr_x), self._screenToScene:transformY(scr_y)
end

function MatrixManager:invertTransform(src_x, src_y)
    return self._projection:invertTransformX(src_x), self._projection:invertTransformY(src_y)
end

function MatrixManager:setScale(scale)
    self._scale = scale
end

function MatrixManager:setOffset(dx, dy)
    self._offsetX = dx
    self._offsetY = dy
end

function MatrixManager:getMvp(model_matrix)
    self._projection:identity()
    if self._wh > self._ww then
        model_matrix:setWidth(2.0)
        self._projection:multScale(1.0, self._ww / self._wh)
    else
        self._projection:multScale(self._wh / self._ww, 1.0)
    end
    self._projection:multScale(self._scale, self._scale)
    self._projection:translate(self._offsetX, self._offsetY)
    local pa = self._projection:getArray()
    local ma = model_matrix:getArray()
    L2DMatrix44.mul(pa, ma, pa)
    return self._projection:getArray()
end

return MatrixManager
