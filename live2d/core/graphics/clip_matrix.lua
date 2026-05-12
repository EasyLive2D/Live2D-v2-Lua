local Float32Array = require("live2d.core.type.array").Float32Array

local ClipMatrix = {}
ClipMatrix.__index = ClipMatrix

function ClipMatrix.new()
    local self = setmetatable({}, ClipMatrix)
    self.m = Float32Array(16)
    self:identity()
    return self
end

function ClipMatrix:identity()
    for aH = 1, 16 do
        if (aH - 1) % 5 == 0 then
            self.m[aH] = 1
        else
            self.m[aH] = 0
        end
    end
end

function ClipMatrix:getArray()
    return self.m
end

function ClipMatrix:getCopyMatrix()
    return Float32Array(#self.m)
end

function ClipMatrix:setMatrix(aI)
    if aI == nil or #aI ~= 16 then
        return
    end
    for aH = 1, 16 do
        self.m[aH] = aI[aH]
    end
end

function ClipMatrix:translate(aH, aJ, aI)
    self.m[13] = self.m[1] * aH + self.m[5] * aJ + self.m[9] * aI + self.m[13]
    self.m[14] = self.m[2] * aH + self.m[6] * aJ + self.m[10] * aI + self.m[14]
    self.m[15] = self.m[3] * aH + self.m[7] * aJ + self.m[11] * aI + self.m[15]
    self.m[16] = self.m[4] * aH + self.m[8] * aJ + self.m[12] * aI + self.m[16]
end

function ClipMatrix:scale(aJ, aI, aH)
    self.m[1] = self.m[1] * aJ
    self.m[5] = self.m[5] * aI
    self.m[9] = self.m[9] * aH
    self.m[2] = self.m[2] * aJ
    self.m[6] = self.m[6] * aI
    self.m[10] = self.m[10] * aH
    self.m[3] = self.m[3] * aJ
    self.m[7] = self.m[7] * aI
    self.m[11] = self.m[11] * aH
    self.m[4] = self.m[4] * aJ
    self.m[8] = self.m[8] * aI
    self.m[12] = self.m[12] * aH
end

return ClipMatrix
