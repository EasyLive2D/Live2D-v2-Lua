-- ClippingManagerOpenGL - manages clip masks via OpenGL FBO
-- Backed by real OpenGL FFI calls

local ClipContext = require("live2d.core.graphics.clip_context")
local ClipMatrix = require("live2d.core.graphics.clip_matrix")
local ClipRectF = require("live2d.core.graphics.clip_rectf")
local TextureInfo = require("live2d.core.graphics.texture_info")
local def = require("live2d.core.def")
local Live2D = require("live2d.core.live2d")
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")

local ClippingManagerOpenGL = {}
ClippingManagerOpenGL.__index = ClippingManagerOpenGL
ClippingManagerOpenGL.CHANNEL_COUNT = 4

function ClippingManagerOpenGL.new(drawParamGL)
    local self = setmetatable({}, ClippingManagerOpenGL)
    self.clipContextList = {}
    self.dpGL = drawParamGL
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

    local channelColor = TextureInfo.new()
    channelColor.r = 0; channelColor.g = 0; channelColor.b = 0; channelColor.a = 1
    self.channelColors[1] = channelColor
    channelColor = TextureInfo.new()
    channelColor.r = 1; channelColor.g = 0; channelColor.b = 0; channelColor.a = 0
    self.channelColors[2] = channelColor
    channelColor = TextureInfo.new()
    channelColor.r = 0; channelColor.g = 1; channelColor.b = 0; channelColor.a = 0
    self.channelColors[3] = channelColor
    channelColor = TextureInfo.new()
    channelColor.r = 0; channelColor.g = 0; channelColor.b = 1; channelColor.a = 0
    self.channelColors[4] = channelColor

    for channelIndex = 0, 3 do
        self.dpGL:setChannelFlagAsColor(channelIndex, self.channelColors[channelIndex + 1])
    end
    self:genMaskRenderTexture()
    return self
end

function ClippingManagerOpenGL:init(modelContext, drawDataList, drawContextList)
    for drawDataIndex = 1, #drawDataList do
        local clipIDList = drawDataList[drawDataIndex]:getClipIDList()
        if clipIDList ~= nil then
            local existingClip = self:findSameClip(clipIDList)
            if existingClip == nil then
                existingClip = ClipContext.new(self, modelContext, clipIDList)
                if existingClip.isValid then
                    self.clipContextList[#self.clipContextList + 1] = existingClip
                end
            end
            if existingClip.isValid then
                local drawDataId = drawDataList[drawDataIndex]:getId()
                local clipDrawDataIndex = modelContext:getDrawDataIndex(drawDataId)
                existingClip:addClippedDrawData(drawDataId, clipDrawDataIndex)
                local drawCtx = drawContextList[drawDataIndex]
                drawCtx.clipBufPre_clipContext = existingClip
            end
        end
    end
end

function ClippingManagerOpenGL:genMaskRenderTexture()
    if self.dpGL.createFramebuffer then
        self.dpGL:createFramebuffer()
    end
end

function ClippingManagerOpenGL:setupClip(modelContext, drawParam)
    local activeClipCount = 0
    for clipIndex = 1, #self.clipContextList do
        local clipCtx = self.clipContextList[clipIndex]
        self:calcClippedDrawTotalBounds(modelContext, clipCtx)
        if clipCtx.isUsing then activeClipCount = activeClipCount + 1 end
    end

    if activeClipCount > 0 then
        local oldFbo = Live2DGLWrapper.getParameter(Live2DGLWrapper.FRAMEBUFFER_BINDING)
        local rect = {0, 0, drawParam.gl.width, drawParam.gl.height}
        Live2DGLWrapper.viewport(0, 0, Live2D.clippingMaskBufferSize, Live2D.clippingMaskBufferSize)
        self:setupLayoutBounds(activeClipCount)
        if drawParam.framebufferObject then
            Live2DGLWrapper.bindFramebuffer(Live2DGLWrapper.FRAMEBUFFER, drawParam.framebufferObject.framebuffer)
        end
        Live2DGLWrapper.clearColor(0, 0, 0, 0)
        Live2DGLWrapper.clear(Live2DGLWrapper.COLOR_BUFFER_BIT)

        for clipIndex = 1, #self.clipContextList do
            local clipCtx = self.clipContextList[clipIndex]
            local clippedBounds = clipCtx.allClippedDrawRect
            local layoutBounds = clipCtx.layoutBounds
            local boundsExpandRatio = 0.05
            self.tmpBoundsOnModel:setRect(clippedBounds)
            self.tmpBoundsOnModel:expand(clippedBounds.width * boundsExpandRatio, clippedBounds.height * boundsExpandRatio)
            local scaleX = layoutBounds.width / self.tmpBoundsOnModel.width
            local scaleY = layoutBounds.height / self.tmpBoundsOnModel.height

            self.tmpMatrix2:identity()
            self.tmpMatrix2:translate(-1, -1, 0)
            self.tmpMatrix2:scale(2, 2, 1)
            self.tmpMatrix2:translate(layoutBounds.x, layoutBounds.y, 0)
            self.tmpMatrix2:scale(scaleX, scaleY, 1)
            self.tmpMatrix2:translate(-self.tmpBoundsOnModel.x, -self.tmpBoundsOnModel.y, 0)
            self.tmpMatrixForMask:setMatrix(self.tmpMatrix2.m)

            self.tmpMatrix2:identity()
            self.tmpMatrix2:translate(layoutBounds.x, layoutBounds.y, 0)
            self.tmpMatrix2:scale(scaleX, scaleY, 1)
            self.tmpMatrix2:translate(-self.tmpBoundsOnModel.x, -self.tmpBoundsOnModel.y, 0)
            self.tmpMatrixForDraw:setMatrix(self.tmpMatrix2.m)

            local maskMatrixArray = self.tmpMatrixForMask:getArray()
            for aX = 1, 16 do clipCtx.matrixForMask[aX] = maskMatrixArray[aX] end
            local drawMatrixArray = self.tmpMatrixForDraw:getArray()
            for aX = 1, 16 do clipCtx.matrixForDraw[aX] = drawMatrixArray[aX] end

            local maskDrawCount = #clipCtx.clippingMaskDrawIndexList
            for maskIndex = 1, maskDrawCount do
                local drawIndex = clipCtx.clippingMaskDrawIndexList[maskIndex]
                local drawData = modelContext:getDrawData(drawIndex)
                if drawData ~= nil then
                    local drawCtx = modelContext:getDrawContext(drawIndex)
                    drawParam:setClipBufPre_clipContextForMask(clipCtx)
                    drawData:draw(drawParam, modelContext, drawCtx)
                end
            end
        end

        Live2DGLWrapper.bindFramebuffer(Live2DGLWrapper.FRAMEBUFFER, oldFbo)
        drawParam:setClipBufPre_clipContextForMask(nil)
        Live2DGLWrapper.viewport(rect[1], rect[2], rect[3], rect[4])
    end
end

function ClippingManagerOpenGL:findSameClip(clipIDs)
    for clipIndex = 1, #self.clipContextList do
        local existingClip = self.clipContextList[clipIndex]
        local idCount = #existingClip.clipIDList
        if idCount == #clipIDs then
            local matchCount = 0
            for outerIndex = 1, idCount do
                local existingID = existingClip.clipIDList[outerIndex]
                for innerIndex = 1, idCount do
                    if tostring(clipIDs[innerIndex]) == tostring(existingID) then
                        matchCount = matchCount + 1
                        break
                    end
                end
            end
            if matchCount == idCount then return existingClip end
        end
    end
    return nil
end

function ClippingManagerOpenGL:calcClippedDrawTotalBounds(modelContext, clipCtx)
    local canvasWidth = modelContext.model:getModelImpl():getCanvasWidth()
    local canvasHeight = modelContext.model:getModelImpl():getCanvasHeight()
    local maxCanvasDimension = canvasWidth > canvasHeight and canvasWidth or canvasHeight
    local minX = maxCanvasDimension
    local minY = maxCanvasDimension
    local maxX = 0
    local maxY = 0
    local clippedCount = #clipCtx.clippedDrawContextList

    for drawIndex = 1, clippedCount do
        local clippedEntry = clipCtx.clippedDrawContextList[drawIndex]
        local drawDataIdx = clippedEntry.drawDataIndex
        local drawCtx = modelContext:getDrawContext(drawDataIdx)
        if drawCtx:isAvailable() then
            local transformedPoints = drawCtx:getTransformedPoints()
            local pointCount = #transformedPoints
            local boundsMinX = nil
            local boundsMinY = nil
            local boundsMaxX = nil
            local boundsMaxY = nil
            for a3 = def.VERTEX_OFFSET + 1, pointCount, def.VERTEX_STEP do
                local x = transformedPoints[a3]
                local y = transformedPoints[a3 + 1]
                if boundsMinX == nil then
                    boundsMinX = x; boundsMaxX = x; boundsMinY = y; boundsMaxY = y
                else
                    if x < boundsMinX then boundsMinX = x end
                    if x > boundsMaxX then boundsMaxX = x end
                    if y < boundsMinY then boundsMinY = y end
                    if y > boundsMaxY then boundsMaxY = y end
                end
            end
            if boundsMinX ~= nil then
                if boundsMinX < minX then minX = boundsMinX end
                if boundsMinY < minY then minY = boundsMinY end
                if boundsMaxX > maxX then maxX = boundsMaxX end
                if boundsMaxY > maxY then maxY = boundsMaxY end
            end
        end
    end

    if minX == maxCanvasDimension then
        clipCtx.allClippedDrawRect.x = 0; clipCtx.allClippedDrawRect.y = 0
        clipCtx.allClippedDrawRect.width = 0; clipCtx.allClippedDrawRect.height = 0
        clipCtx.isUsing = false
    else
        clipCtx.allClippedDrawRect.x = minX; clipCtx.allClippedDrawRect.y = minY
        clipCtx.allClippedDrawRect.width = maxX - minX; clipCtx.allClippedDrawRect.height = maxY - minY
        clipCtx.isUsing = true
    end
end

function ClippingManagerOpenGL:setupLayoutBounds(activeClipCount)
    local clipsPerChannel = math.floor(activeClipCount / ClippingManagerOpenGL.CHANNEL_COUNT)
    local extraClips = activeClipCount % ClippingManagerOpenGL.CHANNEL_COUNT
    local clipIndex = 1
    for channelIndex = 1, ClippingManagerOpenGL.CHANNEL_COUNT do
        local clipsInThisChannel = clipsPerChannel + (channelIndex <= extraClips and 1 or 0)
        if clipsInThisChannel == 1 then
            local clipCtx = self.clipContextList[clipIndex]; clipIndex = clipIndex + 1
            clipCtx.layoutChannelNo = channelIndex - 1
            clipCtx.layoutBounds.x = 0; clipCtx.layoutBounds.y = 0
            clipCtx.layoutBounds.width = 1; clipCtx.layoutBounds.height = 1
        elseif clipsInThisChannel == 2 then
            for rowIndex = 1, clipsInThisChannel do
                local columnIndex = (rowIndex - 1) % 2
                local clipCtx = self.clipContextList[clipIndex]; clipIndex = clipIndex + 1
                clipCtx.layoutChannelNo = channelIndex - 1
                clipCtx.layoutBounds.x = columnIndex * 0.5; clipCtx.layoutBounds.y = 0
                clipCtx.layoutBounds.width = 0.5; clipCtx.layoutBounds.height = 1
            end
        elseif clipsInThisChannel <= 4 then
            for rowIndex = 1, clipsInThisChannel do
                local columnIndex = (rowIndex - 1) % 2
                local rowIndex = math.floor((rowIndex - 1) / 2)
                local clipCtx = self.clipContextList[clipIndex]; clipIndex = clipIndex + 1
                clipCtx.layoutChannelNo = channelIndex - 1
                clipCtx.layoutBounds.x = columnIndex * 0.5; clipCtx.layoutBounds.y = rowIndex * 0.5
                clipCtx.layoutBounds.width = 0.5; clipCtx.layoutBounds.height = 0.5
            end
        elseif clipsInThisChannel <= 9 then
            for rowIndex = 1, clipsInThisChannel do
                local columnIndex = (rowIndex - 1) % 3
                local rowIndex = math.floor((rowIndex - 1) / 3)
                local clipCtx = self.clipContextList[clipIndex]; clipIndex = clipIndex + 1
                clipCtx.layoutChannelNo = channelIndex - 1
                clipCtx.layoutBounds.x = columnIndex / 3; clipCtx.layoutBounds.y = rowIndex / 3
                clipCtx.layoutBounds.width = 1 / 3; clipCtx.layoutBounds.height = 1 / 3
            end
        end
    end
end

return ClippingManagerOpenGL
