local L2DMatrix44 = {}
L2DMatrix44.__index = L2DMatrix44

function L2DMatrix44.new()
    local self = setmetatable({}, L2DMatrix44)
    self.tr = {}
    for i = 1, 16 do self.tr[i] = 0 end
    self:identity()
    return self
end

function L2DMatrix44:identity()
    for i = 1, 16 do
        self.tr[i] = (i - 1) % 5 == 0 and 1 or 0
    end
end

function L2DMatrix44:getArray()
    return self.tr
end

function L2DMatrix44:getCopyMatrix()
    local c = {}
    for i = 1, 16 do c[i] = self.tr[i] end
    return c
end

function L2DMatrix44:setMatrix(tr)
    if tr == nil or #tr ~= 16 then return end
    for i = 1, 16 do self.tr[i] = tr[i] end
end

function L2DMatrix44:getScaleX()
    return self.tr[1]
end

function L2DMatrix44:getScaleY()
    return self.tr[6]
end

function L2DMatrix44:transformX(src)
    return self.tr[1] * src + self.tr[13]
end

function L2DMatrix44:transformY(src)
    return self.tr[6] * src + self.tr[14]
end

function L2DMatrix44:invertTransformX(src)
    return (src - self.tr[13]) / self.tr[1]
end

function L2DMatrix44:invertTransformY(src)
    return (src - self.tr[14]) / self.tr[6]
end

function L2DMatrix44:multTranslate(shiftX, shiftY)
    local tr1 = {1,0,0,0,0,1,0,0,0,0,1,0,shiftX,shiftY,0,1}
    L2DMatrix44.mul(tr1, self.tr, self.tr)
end

function L2DMatrix44:translate(x, y)
    self.tr[13] = x
    self.tr[14] = y
end

function L2DMatrix44:translateX(x)
    self.tr[13] = x
end

function L2DMatrix44:translateY(y)
    self.tr[14] = y
end

function L2DMatrix44:multScale(scaleX, scaleY)
    local tr1 = {scaleX,0,0,0,0,scaleY,0,0,0,0,1,0,0,0,0,1}
    L2DMatrix44.mul(tr1, self.tr, self.tr)
end

function L2DMatrix44:scale(scaleX, scaleY)
    self.tr[1] = scaleX
    self.tr[6] = scaleY
end

function L2DMatrix44.mul(a, b, dst)
    local c = {}
    for i = 1, 16 do c[i] = 0 end
    local n = 4
    for i = 1, n do
        for j = 1, n do
            for k = 1, n do
                c[i + (j - 1) * 4] = c[i + (j - 1) * 4] + a[i + (k - 1) * 4] * b[k + (j - 1) * 4]
            end
        end
    end
    for i = 1, 16 do dst[i] = c[i] end
end

return L2DMatrix44
