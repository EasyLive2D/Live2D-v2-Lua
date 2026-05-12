local Float32Array = require("live2d.core.type.array").Float32Array
local Array = require("live2d.core.type.array").Array

local DrawParam = {}
DrawParam.__index = DrawParam

DrawParam.DEFAULT_FIXED_TEXTURE_COUNT = 32
DrawParam.CLIPPING_PROCESS_NONE = 0
DrawParam.CLIPPING_PROCESS_OVERWRITE_ALPHA = 1
DrawParam.CLIPPING_PROCESS_MULTIPLY_ALPHA = 2
DrawParam.CLIPPING_PROCESS_DRAW = 3
DrawParam.CLIPPING_PROCESS_CLEAR_ALPHA = 4

function DrawParam.new()
    local self = setmetatable({}, DrawParam)
    self.fixedTextureCount = DrawParam.DEFAULT_FIXED_TEXTURE_COUNT
    self.baseAlpha = 1
    self.baseRed = 1
    self.baseGreen = 1
    self.baseBlue = 1
    self.culling = false
    self.matrix4x4 = Float32Array(16)
    self.preMultipliedAlpha = false
    self.anisotropy = 0
    self.clippingProcess = DrawParam.CLIPPING_PROCESS_NONE
    self.clipBufPre_clipContextMask = nil
    self.clipBufPre_clipContextDraw = nil
    self.channel_colors = {}
    return self
end

function DrawParam:setChannelFlagAsColor(aH, aI)
    self.channel_colors[aH] = aI
end

function DrawParam:getChannelFlagAsColor(aY)
    return self.channel_colors[aY]
end

function DrawParam:setupDraw()
    -- no-op: overridden by subclasses
end

function DrawParam:drawTexture(texNo, screenColor, indexArray, vertexArray, uvArray, opacity, comp, multiplyColor)
    -- no-op: overridden by subclasses
end

function DrawParam:setCulling(aH)
    self.culling = aH
end

function DrawParam:setMatrix(aH)
    for aI = 1, 16 do
        self.matrix4x4[aI] = aH[aI]
    end
end

function DrawParam:getMatrix()
    return self.matrix4x4
end

function DrawParam:setPreMultipliedAlpha(aH)
    self.preMultipliedAlpha = aH
end

function DrawParam:isPreMultipliedAlpha()
    return self.preMultipliedAlpha
end

function DrawParam:setAnisotropy(aH)
    self.anisotropy = aH
end

function DrawParam:getAnisotropy()
    return self.anisotropy
end

function DrawParam:getClippingProcess()
    return self.clippingProcess
end

function DrawParam:setClippingProcess(aH)
    self.clippingProcess = aH
end

function DrawParam:setClipBufPre_clipContextForMask(aH)
    self.clipBufPre_clipContextMask = aH
end

function DrawParam:getClipBufPre_clipContextMask()
    return self.clipBufPre_clipContextMask
end

function DrawParam:setClipBufPre_clipContextForDraw(aH)
    self.clipBufPre_clipContextDraw = aH
end

function DrawParam:getClipBufPre_clipContextDraw()
    return self.clipBufPre_clipContextDraw
end

return DrawParam
