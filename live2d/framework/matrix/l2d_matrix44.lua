local L2DMatrix44 = {}
L2DMatrix44.__index = L2DMatrix44

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
    local tr1 = {1,0,0,0,0,1,0,0,0,0,1,0,shiftX,shiftY,0,1}
    L2DMatrix44.mul(tr1, self.matrixElements, self.matrixElements)
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
    local tr1 = {scaleX,0,0,0,0,scaleY,0,0,0,0,1,0,0,0,0,1}
    L2DMatrix44.mul(tr1, self.matrixElements, self.matrixElements)
end

function L2DMatrix44:scale(scaleX, scaleY)
    self.matrixElements[1] = scaleX
    self.matrixElements[6] = scaleY
end

function L2DMatrix44.mul(a, b, dst)
    local resultMatrix = {}
    for i = 1, 16 do resultMatrix[i] = 0 end
    local matrixOrder = 4
    for i = 1, matrixOrder do
        for j = 1, matrixOrder do
            for k = 1, matrixOrder do
                resultMatrix[i + (j - 1) * 4] = resultMatrix[i + (j - 1) * 4] + a[i + (k - 1) * 4] * b[k + (j - 1) * 4]
            end
        end
    end
    for i = 1, 16 do dst[i] = resultMatrix[i] end
end

return L2DMatrix44
