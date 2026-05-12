local Float32Array = require("live2d.core.type.array").Float32Array
local ClipRectF = require("live2d.core.graphics.clip_rectf")
local ClipDrawContext = require("live2d.core.graphics.clip_draw_context")

local ClipContext = {}
ClipContext.__index = ClipContext

function ClipContext.new(aH, aK, aI)
    local self = setmetatable({}, ClipContext)
    self.clipIDList = aI
    self.clippingMaskDrawIndexList = {}
    self.isValid = true
    for aJ = 1, #aI do
        local drawIndex = aK:getDrawDataIndex(aI[aJ])
        if drawIndex < 0 then
            self.isValid = false
        end
        self.clippingMaskDrawIndexList[#self.clippingMaskDrawIndexList + 1] = drawIndex
    end
    self.clippedDrawContextList = {}
    self.isUsing = true
    self.layoutChannelNo = 0
    self.layoutBounds = ClipRectF.new()
    self.allClippedDrawRect = ClipRectF.new()
    self.matrixForMask = Float32Array(16)
    self.matrixForDraw = Float32Array(16)
    self.owner = aH
    return self
end

function ClipContext:addClippedDrawData(aJ, aI)
    local aH = ClipDrawContext.new(aJ, aI)
    self.clippedDrawContextList[#self.clippedDrawContextList + 1] = aH
end

return ClipContext
