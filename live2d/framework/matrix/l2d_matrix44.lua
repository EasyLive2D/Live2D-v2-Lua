local L2DMatrix44 = {}
L2DMatrix44.__index = L2DMatrix44

local mulResult = {}
for i = 1, 16 do mulResult[i] = 0 end

function L2DMatrix44.new()
    local self = setmetatable({}, L2DMatrix44)
    self.matrixElements = {}
    for i = 1, 16 do self.matrixElements[i] = 0 end
    self:identity()
    return self
end

function L2DMatrix44:identity()
    for i = 1, 16 do
        self.matrixElements[i] = (i - 1) % 5 == 0 and 1 or 0
    end
end

function L2DMatrix44:getArray()
    return self.matrixElements
end

function L2DMatrix44:getScaleX()
    return self.matrixElements[1]
end

function L2DMatrix44:getScaleY()
    return self.matrixElements[6]
end

function L2DMatrix44:transformX(src)
    return self.matrixElements[1] * src + self.matrixElements[13]
end

function L2DMatrix44:transformY(src)
    return self.matrixElements[6] * src + self.matrixElements[14]
end

function L2DMatrix44:invertTransformX(src)
    return (src - self.matrixElements[13]) / self.matrixElements[1]
end

function L2DMatrix44:invertTransformY(src)
    return (src - self.matrixElements[14]) / self.matrixElements[6]
end

function L2DMatrix44:multTranslate(shiftX, shiftY)
    local m = self.matrixElements
    for column = 0, 3 do
        local offset = column * 4
        local w = m[offset + 4]
        m[offset + 1] = m[offset + 1] + shiftX * w
        m[offset + 2] = m[offset + 2] + shiftY * w
    end
end

function L2DMatrix44:translate(x, y)
    self.matrixElements[13] = x
    self.matrixElements[14] = y
end

function L2DMatrix44:translateX(x)
    self.matrixElements[13] = x
end

function L2DMatrix44:translateY(y)
    self.matrixElements[14] = y
end

function L2DMatrix44:multScale(scaleX, scaleY)
    local m = self.matrixElements
    for column = 0, 3 do
        local offset = column * 4
        m[offset + 1] = m[offset + 1] * scaleX
        m[offset + 2] = m[offset + 2] * scaleY
    end
end

function L2DMatrix44:scale(scaleX, scaleY)
    self.matrixElements[1] = scaleX
    self.matrixElements[6] = scaleY
end

function L2DMatrix44.mul(a, b, dst)
    local matrixOrder = 4
    for i = 1, matrixOrder do
        for j = 1, matrixOrder do
            local resultIndex = i + (j - 1) * 4
            local value = 0
            for k = 1, matrixOrder do
                value = value + a[i + (k - 1) * 4] * b[k + (j - 1) * 4]
            end
            mulResult[resultIndex] = value
        end
    end
    for i = 1, 16 do dst[i] = mulResult[i] end
end

return L2DMatrix44
