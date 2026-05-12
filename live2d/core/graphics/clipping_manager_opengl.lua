-- ClippingManagerOpenGL - manages clip masks via OpenGL FBO
-- Backed by real OpenGL FFI calls

local ClipContext = require("live2d.core.graphics.clip_context")
local ClipMatrix = require("live2d.core.graphics.clip_matrix")
local ClipRectF = require("live2d.core.graphics.clip_rectf")
local TextureInfo = require("live2d.core.graphics.texture_info")
local def = require("live2d.core.def")
local Live2D = require("live2d.core.live2d")
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")
local Float32Array = require("live2d.core.type.array").Float32Array

local ClippingManagerOpenGL = {}
ClippingManagerOpenGL.__index = ClippingManagerOpenGL
ClippingManagerOpenGL.CHANNEL_COUNT = 4

function ClippingManagerOpenGL.new(aJ)
    local self = setmetatable({}, ClippingManagerOpenGL)
    self.clipContextList = {}
    self.dpGL = aJ
    self.curFrameNo = 0
    self.firstError_clipInNotUpdate = true
    self.colorBuffer = 0
    self.isInitGLFBFunc = false
    self.tmpBoundsOnModel = ClipRectF.new()
    self.tmpModelToViewMatrix = ClipMatrix.new()
    self.tmpMatrix2 = ClipMatrix.new()
    self.tmpMatrixForMask = ClipMatrix.new()
    self.tmpMatrixForDraw = ClipMatrix.new()
    self.channelColors = {}

    local aI = TextureInfo.new()
    aI.r = 0; aI.g = 0; aI.b = 0; aI.a = 1
    self.channelColors[1] = aI
    aI = TextureInfo.new()
    aI.r = 1; aI.g = 0; aI.b = 0; aI.a = 0
    self.channelColors[2] = aI
    aI = TextureInfo.new()
    aI.r = 0; aI.g = 1; aI.b = 0; aI.a = 0
    self.channelColors[3] = aI
    aI = TextureInfo.new()
    aI.r = 0; aI.g = 0; aI.b = 1; aI.a = 0
    self.channelColors[4] = aI

    for aH = 0, 3 do
        self.dpGL:setChannelFlagAsColor(aH, self.channelColors[aH + 1])
    end
    self:genMaskRenderTexture()
    return self
end

function ClippingManagerOpenGL:releaseShader()
    local aI = #Live2D.frameBuffers
    for aH = 1, aI do
        if Live2D.frameBuffers[aH] then
            Live2DGLWrapper.deleteFramebuffer(Live2D.frameBuffers[aH].framebuffer)
        end
    end
    Live2D.frameBuffers = {}
    Live2D.__glContext = {}
end

function ClippingManagerOpenGL:init(aO, aN, aL)
    for aM = 1, #aN do
        local aH = aN[aM]:getClipIDList()
        if aH ~= nil then
            local aJ = self:findSameClip(aH)
            if aJ == nil then
                aJ = ClipContext.new(self, aO, aH)
                if aJ.isValid then
                    self.clipContextList[#self.clipContextList + 1] = aJ
                end
            end
            if aJ.isValid then
                local aI = aN[aM]:getId()
                local aK = aO:getDrawDataIndex(aI)
                aJ:addClippedDrawData(aI, aK)
                local aP = aL[aM]
                aP.clipBufPre_clipContext = aJ
            end
        end
    end
end

function ClippingManagerOpenGL:genMaskRenderTexture()
    if self.dpGL.createFramebuffer then
        self.dpGL:createFramebuffer()
    end
end

function ClippingManagerOpenGL:setupClip(a1, aQ)
    local aK = 0
    for aO = 1, #self.clipContextList do
        local aP = self.clipContextList[aO]
        self:calcClippedDrawTotalBounds(a1, aP)
        if aP.isUsing then aK = aK + 1 end
    end

    if aK > 0 then
        local oldFbo = Live2DGLWrapper.getParameter(Live2DGLWrapper.FRAMEBUFFER_BINDING)
        local rect = {0, 0, aQ.gl.width, aQ.gl.height}
        Live2DGLWrapper.viewport(0, 0, Live2D.clippingMaskBufferSize, Live2D.clippingMaskBufferSize)
        self:setupLayoutBounds(aK)
        if aQ.framebufferObject then
            Live2DGLWrapper.bindFramebuffer(Live2DGLWrapper.FRAMEBUFFER, aQ.framebufferObject.framebuffer)
        end
        Live2DGLWrapper.clearColor(0, 0, 0, 0)
        Live2DGLWrapper.clear(Live2DGLWrapper.COLOR_BUFFER_BIT)

        for aO = 1, #self.clipContextList do
            local aP = self.clipContextList[aO]
            local aT = aP.allClippedDrawRect
            local aV = aP.layoutBounds
            local aJ = 0.05
            self.tmpBoundsOnModel:setRect(aT)
            self.tmpBoundsOnModel:expand(aT.width * aJ, aT.height * aJ)
            local aZ = aV.width / self.tmpBoundsOnModel.width
            local aY = aV.height / self.tmpBoundsOnModel.height

            self.tmpMatrix2:identity()
            self.tmpMatrix2:translate(-1, -1, 0)
            self.tmpMatrix2:scale(2, 2, 1)
            self.tmpMatrix2:translate(aV.x, aV.y, 0)
            self.tmpMatrix2:scale(aZ, aY, 1)
            self.tmpMatrix2:translate(-self.tmpBoundsOnModel.x, -self.tmpBoundsOnModel.y, 0)
            self.tmpMatrixForMask:setMatrix(self.tmpMatrix2.m)

            self.tmpMatrix2:identity()
            self.tmpMatrix2:translate(aV.x, aV.y, 0)
            self.tmpMatrix2:scale(aZ, aY, 1)
            self.tmpMatrix2:translate(-self.tmpBoundsOnModel.x, -self.tmpBoundsOnModel.y, 0)
            self.tmpMatrixForDraw:setMatrix(self.tmpMatrix2.m)

            local aH = self.tmpMatrixForMask:getArray()
            for aX = 1, 16 do aP.matrixForMask[aX] = aH[aX] end
            local a0 = self.tmpMatrixForDraw:getArray()
            for aX = 1, 16 do aP.matrixForDraw[aX] = a0[aX] end

            local aS = #aP.clippingMaskDrawIndexList
            for aU = 1, aS do
                local aR = aP.clippingMaskDrawIndexList[aU]
                local aI = a1:getDrawData(aR)
                if aI ~= nil then
                    local aL = a1:getDrawContext(aR)
                    aQ:setClipBufPre_clipContextForMask(aP)
                    aI:draw(aQ, a1, aL)
                end
            end
        end

        Live2DGLWrapper.bindFramebuffer(Live2DGLWrapper.FRAMEBUFFER, oldFbo)
        aQ:setClipBufPre_clipContextForMask(nil)
        Live2DGLWrapper.viewport(rect[1], rect[2], rect[3], rect[4])
    end
end

function ClippingManagerOpenGL:getColorBuffer()
    return self.colorBuffer
end

function ClippingManagerOpenGL:findSameClip(aK)
    for aN = 1, #self.clipContextList do
        local aO = self.clipContextList[aN]
        local aH = #aO.clipIDList
        if aH == #aK then
            local aI = 0
            for aM = 1, aH do
                local aL = aO.clipIDList[aM]
                for aJ = 1, aH do
                    if tostring(aK[aJ]) == tostring(aL) then
                        aI = aI + 1
                        break
                    end
                end
            end
            if aI == aH then return aO end
        end
    end
    return nil
end

function ClippingManagerOpenGL:calcClippedDrawTotalBounds(a6, aV)
    local aU = a6.model:getModelImpl():getCanvasWidth()
    local a5 = a6.model:getModelImpl():getCanvasHeight()
    local aJ = aU > a5 and aU or a5
    local aT = aJ
    local aR = aJ
    local aS = 0
    local aP = 0
    local aL = #aV.clippedDrawContextList

    for aM = 1, aL do
        local aW = aV.clippedDrawContextList[aM]
        local aN = aW.drawDataIndex
        local aK = a6:getDrawContext(aN)
        if aK:isAvailable() then
            local aX = aK:getTransformedPoints()
            local a4 = #aX
            local aI = Float32Array(a4)
            local aH = Float32Array(a4)
            local aO = 1
            for a3 = def.VERTEX_OFFSET + 1, a4, def.VERTEX_STEP do
                aI[aO] = aX[a3]
                aH[aO] = aX[a3 + 1]
                aO = aO + 1
            end
            if aO > 1 then
                local a2 = math.min(unpack(aI, 1, aO - 1))
                local a1 = math.min(unpack(aH, 1, aO - 1))
                local a0 = math.max(unpack(aI, 1, aO - 1))
                local aZ = math.max(unpack(aH, 1, aO - 1))
                if a2 < aT then aT = a2 end
                if a1 < aR then aR = a1 end
                if a0 > aS then aS = a0 end
                if aZ > aP then aP = aZ end
            end
        end
    end

    if aT == aJ then
        aV.allClippedDrawRect.x = 0; aV.allClippedDrawRect.y = 0
        aV.allClippedDrawRect.width = 0; aV.allClippedDrawRect.height = 0
        aV.isUsing = false
    else
        aV.allClippedDrawRect.x = aT; aV.allClippedDrawRect.y = aR
        aV.allClippedDrawRect.width = aS - aT; aV.allClippedDrawRect.height = aP - aR
        aV.isUsing = true
    end
end

function ClippingManagerOpenGL:setupLayoutBounds(aQ)
    local aI = math.floor(aQ / ClippingManagerOpenGL.CHANNEL_COUNT)
    local aP = aQ % ClippingManagerOpenGL.CHANNEL_COUNT
    local aH = 1
    for aJ = 1, ClippingManagerOpenGL.CHANNEL_COUNT do
        local aM = aI + (aJ <= aP and 1 or 0)
        if aM == 1 then
            local aL = self.clipContextList[aH]; aH = aH + 1
            aL.layoutChannelNo = aJ - 1
            aL.layoutBounds.x = 0; aL.layoutBounds.y = 0
            aL.layoutBounds.width = 1; aL.layoutBounds.height = 1
        elseif aM == 2 then
            for aO = 1, aM do
                local aN = (aO - 1) % 2
                local aL = self.clipContextList[aH]; aH = aH + 1
                aL.layoutChannelNo = aJ - 1
                aL.layoutBounds.x = aN * 0.5; aL.layoutBounds.y = 0
                aL.layoutBounds.width = 0.5; aL.layoutBounds.height = 1
            end
        elseif aM <= 4 then
            for aO = 1, aM do
                local aN = (aO - 1) % 2
                local aK = math.floor((aO - 1) / 2)
                local aL = self.clipContextList[aH]; aH = aH + 1
                aL.layoutChannelNo = aJ - 1
                aL.layoutBounds.x = aN * 0.5; aL.layoutBounds.y = aK * 0.5
                aL.layoutBounds.width = 0.5; aL.layoutBounds.height = 0.5
            end
        elseif aM <= 9 then
            for aO = 1, aM do
                local aN = (aO - 1) % 3
                local aK = math.floor((aO - 1) / 3)
                local aL = self.clipContextList[aH]; aH = aH + 1
                aL.layoutChannelNo = aJ - 1
                aL.layoutBounds.x = aN / 3; aL.layoutBounds.y = aK / 3
                aL.layoutBounds.width = 1 / 3; aL.layoutBounds.height = 1 / 3
            end
        end
    end
end

return ClippingManagerOpenGL
