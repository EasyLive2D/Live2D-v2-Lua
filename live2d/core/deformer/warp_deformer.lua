local Deformer = require("live2d.core.deformer.deformer")
local WarpContext = require("live2d.core.deformer.warp_context")
local Float32Array = require("live2d.core.type.array").Float32Array
local UtInterpolate = require("live2d.core.util.ut_interpolate")
local floor = math.floor

local WarpDeformer = setmetatable({}, { __index = Deformer })
WarpDeformer.__index = WarpDeformer

WarpDeformer.paramOutSide = {false}

function WarpDeformer.new()
    local self = setmetatable(Deformer.new(), WarpDeformer)
    self.row = 0
    self.col = 0
    self.pivotMgr = nil
    self.pivotPoints = nil
    return self
end

function WarpDeformer:read(br)
    Deformer.read(self, br)
    self.col = br:readInt32()
    self.row = br:readInt32()
    self.pivotMgr = br:readObject()
    self.pivotPoints = br:readObject()
    Deformer.readOpacity(self, br)
end

function WarpDeformer:init(mc)
    local warpContext = WarpContext.new(self)
    local gridPointCount = (self.row + 1) * (self.col + 1)
    if warpContext.interpolatedPoints ~= nil then
        warpContext.interpolatedPoints = nil
    end
    warpContext.interpolatedPoints = Float32Array(gridPointCount * 2)
    if warpContext.transformedPoints ~= nil then
        warpContext.transformedPoints = nil
    end
    if self:needTransform() then
        warpContext.transformedPoints = Float32Array(gridPointCount * 2)
    else
        warpContext.transformedPoints = nil
    end
    return warpContext
end

function WarpDeformer:setupInterpolate(modelContext, deformerContext)
    local deformerCtx = deformerContext
    if not self.pivotMgr:checkParamUpdated(modelContext) then
        return
    end
    local pointCount = self:getPointCount()
    local outsideFlag = WarpDeformer.paramOutSide
    outsideFlag[1] = false
    UtInterpolate.interpolatePoints(modelContext, self.pivotMgr, outsideFlag, pointCount, self.pivotPoints, deformerCtx.interpolatedPoints, 0, 2)
    deformerContext:setOutsideParam(outsideFlag[1])
    self:interpolateOpacity(modelContext, self.pivotMgr, deformerContext, outsideFlag)
end

function WarpDeformer:setupTransform(modelContext, deformerContext)
    local deformerCtx = deformerContext
    deformerCtx:setAvailable(true)
    if not self:needTransform() then
        deformerCtx:setTotalOpacity(deformerCtx:getInterpolatedOpacity())
    else
        local targetId = self:getTargetId()
        if deformerCtx.tmpDeformerIndex == Deformer.DEFORMER_INDEX_NOT_INIT then
            deformerCtx.tmpDeformerIndex = modelContext:getDeformerIndex(targetId)
        end
        if deformerCtx.tmpDeformerIndex < 0 then
            print("deformer is not reachable")
            deformerCtx:setAvailable(false)
        else
            local parentDeformer = modelContext:getDeformer(deformerCtx.tmpDeformerIndex)
            local parentCtx = modelContext:getDeformerContext(deformerCtx.tmpDeformerIndex)
            if parentDeformer ~= nil and parentCtx:isAvailable() then
                local totalScale = parentCtx:getTotalScale()
                deformerCtx:setTotalScale_notForClient(totalScale)
                local totalOpacity = parentCtx:getTotalOpacity()
                deformerCtx:setTotalOpacity(totalOpacity * deformerCtx:getInterpolatedOpacity())
                parentDeformer:transformPoints(modelContext, parentCtx, deformerCtx.interpolatedPoints, deformerCtx.transformedPoints, self:getPointCount(), 0, 2)
                deformerCtx:setAvailable(true)
            else
                deformerCtx:setAvailable(false)
            end
        end
    end
end

function WarpDeformer:transformPoints(mc, dc, srcPoints, dstPoints, numPoint, ptOffset, ptStep)
    local pivot_points
    if dc.transformedPoints ~= nil then
        pivot_points = dc.transformedPoints
    else
        pivot_points = dc.interpolatedPoints
    end
    WarpDeformer.transformPoints_sdk2(srcPoints, dstPoints, numPoint, ptOffset, ptStep, pivot_points, self.row, self.col)
end

function WarpDeformer:getPointCount()
    return (self.row + 1) * (self.col + 1)
end

function WarpDeformer:getType()
    return Deformer.TYPE_WARP
end

function WarpDeformer.transformPoints_sdk2(sourceVertices, dst, pointCount, srcOffset, srcStep, grid, row, col)
    local totalStride = pointCount * srcStep
    local centerX = 0
    local centerY = 0
    local extrapolateScaleX = 0
    local extrapolateScaleY = 0
    local extrapolateSkewX = 0
    local extrapolateSkewY = 0
    local extrapolationComputed = false
    for vertexOffset = srcOffset + 1, totalStride, srcStep do
        local normalizedX = sourceVertices[vertexOffset]
        local normalizedY = sourceVertices[vertexOffset + 1]
        local gridRow = normalizedX * row
        local gridCol = normalizedY * col
        if gridRow < 0 or gridCol < 0 or row <= gridRow or col <= gridCol then
            local rowStride = row + 1
            if not extrapolationComputed then
                extrapolationComputed = true
                centerX = 0.25 * (grid[((0) + (0) * rowStride) * 2 + 1] + grid[((row) + (0) * rowStride) * 2 + 1] +
                             grid[((0) + (col) * rowStride) * 2 + 1] + grid[((row) + (col) * rowStride) * 2 + 1])
                centerY = 0.25 * (grid[((0) + (0) * rowStride) * 2 + 2] + grid[((row) + (0) * rowStride) * 2 + 2] +
                             grid[((0) + (col) * rowStride) * 2 + 2] + grid[((row) + (col) * rowStride) * 2 + 2])
                local diagonalDX = grid[((row) + (col) * rowStride) * 2 + 1] - grid[((0) + (0) * rowStride) * 2 + 1]
                local diagonalDY = grid[((row) + (col) * rowStride) * 2 + 2] - grid[((0) + (0) * rowStride) * 2 + 2]
                local antiDiagDX = grid[((row) + (0) * rowStride) * 2 + 1] - grid[((0) + (col) * rowStride) * 2 + 1]
                local antiDiagDY = grid[((row) + (0) * rowStride) * 2 + 2] - grid[((0) + (col) * rowStride) * 2 + 2]
                extrapolateScaleX = (diagonalDX + antiDiagDX) * 0.5
                extrapolateScaleY = (diagonalDY + antiDiagDY) * 0.5
                extrapolateSkewX = (diagonalDX - antiDiagDX) * 0.5
                extrapolateSkewY = (diagonalDY - antiDiagDY) * 0.5
                centerX = centerX - 0.5 * (extrapolateScaleX + extrapolateSkewX)
                centerY = centerY - 0.5 * (extrapolateScaleY + extrapolateSkewY)
            end

            if (-2 < normalizedX and normalizedX < 3) and (-2 < normalizedY and normalizedY < 3) then
                if normalizedX <= 0 then
                    if normalizedY <= 0 then
                        local gridCornerX = grid[((0) + (0) * rowStride) * 2 + 1]
                        local gridCornerY = grid[((0) + (0) * rowStride) * 2 + 2]
                        local extrapPointX1 = centerX - 2 * extrapolateScaleX
                        local extrapPointY1 = centerY - 2 * extrapolateScaleY
                        local extrapPointX2 = centerX - 2 * extrapolateSkewX
                        local extrapPointY2 = centerY - 2 * extrapolateSkewY
                        local extrapPointX3 = centerX - 2 * extrapolateScaleX - 2 * extrapolateSkewX
                        local extrapPointY3 = centerY - 2 * extrapolateScaleY - 2 * extrapolateSkewY
                        local baryU = 0.5 * (normalizedX - (-2))
                        local baryV = 0.5 * (normalizedY - (-2))
                        if baryU + baryV <= 1 then
                            dst[vertexOffset] = extrapPointX3 + (extrapPointX2 - extrapPointX3) * baryU + (extrapPointX1 - extrapPointX3) * baryV
                            dst[vertexOffset + 1] = extrapPointY3 + (extrapPointY2 - extrapPointY3) * baryU + (extrapPointY1 - extrapPointY3) * baryV
                        else
                            dst[vertexOffset] = gridCornerX + (extrapPointX1 - gridCornerX) * (1 - baryU) + (extrapPointX2 - gridCornerX) * (1 - baryV)
                            dst[vertexOffset + 1] = gridCornerY + (extrapPointY1 - gridCornerY) * (1 - baryU) + (extrapPointY2 - gridCornerY) * (1 - baryV)
                        end
                    elseif normalizedY >= 1 then
                        local extrapPointX2 = grid[((0) + (col) * rowStride) * 2 + 1]
                        local extrapPointY2 = grid[((0) + (col) * rowStride) * 2 + 2]
                        local extrapPointX3 = centerX - 2 * extrapolateScaleX + 1 * extrapolateSkewX
                        local extrapPointY3 = centerY - 2 * extrapolateScaleY + 1 * extrapolateSkewY
                        local gridCornerX = centerX + 3 * extrapolateSkewX
                        local gridCornerY = centerY + 3 * extrapolateSkewY
                        local extrapPointX1 = centerX - 2 * extrapolateScaleX + 3 * extrapolateSkewX
                        local extrapPointY1 = centerY - 2 * extrapolateScaleY + 3 * extrapolateSkewY
                        local baryU = 0.5 * (normalizedX - (-2))
                        local baryV = 0.5 * (normalizedY - (1))
                        if baryU + baryV <= 1 then
                            dst[vertexOffset] = extrapPointX3 + (extrapPointX2 - extrapPointX3) * baryU + (extrapPointX1 - extrapPointX3) * baryV
                            dst[vertexOffset + 1] = extrapPointY3 + (extrapPointY2 - extrapPointY3) * baryU + (extrapPointY1 - extrapPointY3) * baryV
                        else
                            dst[vertexOffset] = gridCornerX + (extrapPointX1 - gridCornerX) * (1 - baryU) + (extrapPointX2 - gridCornerX) * (1 - baryV)
                            dst[vertexOffset + 1] = gridCornerY + (extrapPointY1 - gridCornerY) * (1 - baryU) + (extrapPointY2 - gridCornerY) * (1 - baryV)
                        end
                    else
                        local aH = floor(gridCol)
                        if aH == col then aH = col - 1 end
                        local baryU = 0.5 * (normalizedX - (-2))
                        local baryV = gridCol - aH
                        local colFraction1 = aH / col
                        local colFraction2 = (aH + 1) / col
                        extrapPointX2 = grid[((0) + (aH) * rowStride) * 2 + 1]
                        extrapPointY2 = grid[((0) + (aH) * rowStride) * 2 + 2]
                        gridCornerX = grid[((0) + (aH + 1) * rowStride) * 2 + 1]
                        gridCornerY = grid[((0) + (aH + 1) * rowStride) * 2 + 2]
                        local extrapPointX3 = centerX - 2 * extrapolateScaleX + colFraction1 * extrapolateSkewX
                        local extrapPointY3 = centerY - 2 * extrapolateScaleY + colFraction1 * extrapolateSkewY
                        local extrapPointX1 = centerX - 2 * extrapolateScaleX + colFraction2 * extrapolateSkewX
                        local extrapPointY1 = centerY - 2 * extrapolateScaleY + colFraction2 * extrapolateSkewY
                        if baryU + baryV <= 1 then
                            dst[vertexOffset] = extrapPointX3 + (extrapPointX2 - extrapPointX3) * baryU + (extrapPointX1 - extrapPointX3) * baryV
                            dst[vertexOffset + 1] = extrapPointY3 + (extrapPointY2 - extrapPointY3) * baryU + (extrapPointY1 - extrapPointY3) * baryV
                        else
                            dst[vertexOffset] = gridCornerX + (extrapPointX1 - gridCornerX) * (1 - baryU) + (extrapPointX2 - gridCornerX) * (1 - baryV)
                            dst[vertexOffset + 1] = gridCornerY + (extrapPointY1 - gridCornerY) * (1 - baryU) + (extrapPointY2 - gridCornerY) * (1 - baryV)
                        end
                    end
                else
                    if 1 <= normalizedX then
                        if normalizedY <= 0 then
                            local extrapPointX1 = grid[((row) + (0) * rowStride) * 2 + 1]
                            local extrapPointY1 = grid[((row) + (0) * rowStride) * 2 + 2]
                            local gridCornerX = centerX + 3 * extrapolateScaleX
                            local gridCornerY = centerY + 3 * extrapolateScaleY
                            local extrapPointX3 = centerX + 1 * extrapolateScaleX - 2 * extrapolateSkewX
                            local extrapPointY3 = centerY + 1 * extrapolateScaleY - 2 * extrapolateSkewY
                            local extrapPointX2 = centerX + 3 * extrapolateScaleX - 2 * extrapolateSkewX
                            local extrapPointY2 = centerY + 3 * extrapolateScaleY - 2 * extrapolateSkewY
                            local baryU = 0.5 * (normalizedX - (1))
                            local baryV = 0.5 * (normalizedY - (-2))
                            if baryU + baryV <= 1 then
                                dst[vertexOffset] = extrapPointX3 + (extrapPointX2 - extrapPointX3) * baryU + (extrapPointX1 - extrapPointX3) * baryV
                                dst[vertexOffset + 1] = extrapPointY3 + (extrapPointY2 - extrapPointY3) * baryU + (extrapPointY1 - extrapPointY3) * baryV
                            else
                                dst[vertexOffset] = gridCornerX + (extrapPointX1 - gridCornerX) * (1 - baryU) + (extrapPointX2 - gridCornerX) * (1 - baryV)
                                dst[vertexOffset + 1] = gridCornerY + (extrapPointY1 - gridCornerY) * (1 - baryU) + (extrapPointY2 - gridCornerY) * (1 - baryV)
                            end
                        elseif normalizedY >= 1 then
                            local extrapPointX3 = grid[((row) + (col) * rowStride) * 2 + 1]
                            local extrapPointY3 = grid[((row) + (col) * rowStride) * 2 + 2]
                            local extrapPointX2 = centerX + 3 * extrapolateScaleX + 1 * extrapolateSkewX
                            local extrapPointY2 = centerY + 3 * extrapolateScaleY + 1 * extrapolateSkewY
                            local extrapPointX1 = centerX + 1 * extrapolateScaleX + 3 * extrapolateSkewX
                            local extrapPointY1 = centerY + 1 * extrapolateScaleY + 3 * extrapolateSkewY
                            local gridCornerX = centerX + 3 * extrapolateScaleX + 3 * extrapolateSkewX
                            local gridCornerY = centerY + 3 * extrapolateScaleY + 3 * extrapolateSkewY
                            local baryU = 0.5 * (normalizedX - (1))
                            local baryV = 0.5 * (normalizedY - (1))
                            if baryU + baryV <= 1 then
                                dst[vertexOffset] = extrapPointX3 + (extrapPointX2 - extrapPointX3) * baryU + (extrapPointX1 - extrapPointX3) * baryV
                                dst[vertexOffset + 1] = extrapPointY3 + (extrapPointY2 - extrapPointY3) * baryU + (extrapPointY1 - extrapPointY3) * baryV
                            else
                                dst[vertexOffset] = gridCornerX + (extrapPointX1 - gridCornerX) * (1 - baryU) + (extrapPointX2 - gridCornerX) * (1 - baryV)
                                dst[vertexOffset + 1] = gridCornerY + (extrapPointY1 - gridCornerY) * (1 - baryU) + (extrapPointY2 - gridCornerY) * (1 - baryV)
                            end
                        else
                            local aH = floor(gridCol)
                            if aH == col then aH = col - 1 end
                            local baryU = 0.5 * (normalizedX - (1))
                            local baryV = gridCol - aH
                            local colFraction1 = aH / col
                            local colFraction2 = (aH + 1) / col
                            extrapPointX3 = grid[((row) + (aH) * rowStride) * 2 + 1]
                            extrapPointY3 = grid[((row) + (aH) * rowStride) * 2 + 2]
                            local extrapPointX1 = grid[((row) + (aH + 1) * rowStride) * 2 + 1]
                            local extrapPointY1 = grid[((row) + (aH + 1) * rowStride) * 2 + 2]
                            extrapPointX2 = centerX + 3 * extrapolateScaleX + colFraction1 * extrapolateSkewX
                            extrapPointY2 = centerY + 3 * extrapolateScaleY + colFraction1 * extrapolateSkewY
                            gridCornerX = centerX + 3 * extrapolateScaleX + colFraction2 * extrapolateSkewX
                            gridCornerY = centerY + 3 * extrapolateScaleY + colFraction2 * extrapolateSkewY
                            if baryU + baryV <= 1 then
                                dst[vertexOffset] = extrapPointX3 + (extrapPointX2 - extrapPointX3) * baryU + (extrapPointX1 - extrapPointX3) * baryV
                                dst[vertexOffset + 1] = extrapPointY3 + (extrapPointY2 - extrapPointY3) * baryU + (extrapPointY1 - extrapPointY3) * baryV
                            else
                                dst[vertexOffset] = gridCornerX + (extrapPointX1 - gridCornerX) * (1 - baryU) + (extrapPointX2 - gridCornerX) * (1 - baryV)
                                dst[vertexOffset + 1] = gridCornerY + (extrapPointY1 - gridCornerY) * (1 - baryU) + (extrapPointY2 - gridCornerY) * (1 - baryV)
                            end
                        end
                    else
                        if normalizedY <= 0 then
                            local gridRowInt = floor(gridRow)
                            if gridRowInt == row then gridRowInt = row - 1 end
                            local baryU = gridRow - gridRowInt
                            local baryV = 0.5 * (normalizedY - (-2))
                            local rowFraction1 = gridRowInt / row
                            local rowFraction2 = (gridRowInt + 1) / row
                            local extrapPointX1 = grid[((gridRowInt) + (0) * rowStride) * 2 + 1]
                            local extrapPointY1 = grid[((gridRowInt) + (0) * rowStride) * 2 + 2]
                            local gridCornerX = grid[((gridRowInt + 1) + (0) * rowStride) * 2 + 1]
                            local gridCornerY = grid[((gridRowInt + 1) + (0) * rowStride) * 2 + 2]
                            local extrapPointX3 = centerX + rowFraction1 * extrapolateScaleX - 2 * extrapolateSkewX
                            local extrapPointY3 = centerY + rowFraction1 * extrapolateScaleY - 2 * extrapolateSkewY
                            local extrapPointX2 = centerX + rowFraction2 * extrapolateScaleX - 2 * extrapolateSkewX
                            local extrapPointY2 = centerY + rowFraction2 * extrapolateScaleY - 2 * extrapolateSkewY
                            if baryU + baryV <= 1 then
                                dst[vertexOffset] = extrapPointX3 + (extrapPointX2 - extrapPointX3) * baryU + (extrapPointX1 - extrapPointX3) * baryV
                                dst[vertexOffset + 1] = extrapPointY3 + (extrapPointY2 - extrapPointY3) * baryU + (extrapPointY1 - extrapPointY3) * baryV
                            else
                                dst[vertexOffset] = gridCornerX + (extrapPointX1 - gridCornerX) * (1 - baryU) + (extrapPointX2 - gridCornerX) * (1 - baryV)
                                dst[vertexOffset + 1] = gridCornerY + (extrapPointY1 - gridCornerY) * (1 - baryU) + (extrapPointY2 - gridCornerY) * (1 - baryV)
                            end
                        elseif normalizedY >= 1 then
                            local gridRowInt = floor(gridRow)
                            if gridRowInt == row then gridRowInt = row - 1 end
                            local baryU = gridRow - gridRowInt
                            local baryV = 0.5 * (normalizedY - (1))
                            local rowFraction1 = gridRowInt / row
                            local rowFraction2 = (gridRowInt + 1) / row
                            local extrapPointX3 = grid[((gridRowInt) + (col) * rowStride) * 2 + 1]
                            local extrapPointY3 = grid[((gridRowInt) + (col) * rowStride) * 2 + 2]
                            local extrapPointX2 = grid[((gridRowInt + 1) + (col) * rowStride) * 2 + 1]
                            local extrapPointY2 = grid[((gridRowInt + 1) + (col) * rowStride) * 2 + 2]
                            local extrapPointX1 = centerX + rowFraction1 * extrapolateScaleX + 3 * extrapolateSkewX
                            local extrapPointY1 = centerY + rowFraction1 * extrapolateScaleY + 3 * extrapolateSkewY
                            local gridCornerX = centerX + rowFraction2 * extrapolateScaleX + 3 * extrapolateSkewX
                            local gridCornerY = centerY + rowFraction2 * extrapolateScaleY + 3 * extrapolateSkewY
                            if baryU + baryV <= 1 then
                                dst[vertexOffset] = extrapPointX3 + (extrapPointX2 - extrapPointX3) * baryU + (extrapPointX1 - extrapPointX3) * baryV
                                dst[vertexOffset + 1] = extrapPointY3 + (extrapPointY2 - extrapPointY3) * baryU + (extrapPointY1 - extrapPointY3) * baryV
                            else
                                dst[vertexOffset] = gridCornerX + (extrapPointX1 - gridCornerX) * (1 - baryU) + (extrapPointX2 - gridCornerX) * (1 - baryV)
                                dst[vertexOffset + 1] = gridCornerY + (extrapPointY1 - gridCornerY) * (1 - baryU) + (extrapPointY2 - gridCornerY) * (1 - baryV)
                            end
                        else
                            error("error @BDBoxGrid")
                        end
                    end
                end
            else
                dst[vertexOffset] = centerX + normalizedX * extrapolateScaleX + normalizedY * extrapolateSkewX
                dst[vertexOffset + 1] = centerY + normalizedX * extrapolateScaleY + normalizedY * extrapolateSkewY
            end
        else
            local bd_floor = floor(gridRow)
            local a7_floor = floor(gridCol)
            local rowFraction = gridRow - bd_floor
            local colFraction = gridCol - a7_floor
            local gridBaseIndex = 2 * (bd_floor + a7_floor * (row + 1))
            if rowFraction + colFraction < 1 then
                dst[vertexOffset] = grid[gridBaseIndex + 1] * (1 - rowFraction - colFraction) + grid[gridBaseIndex + 3] * rowFraction + grid[gridBaseIndex + 2 * (row + 1) + 1] * colFraction
                dst[vertexOffset + 1] = grid[gridBaseIndex + 2] * (1 - rowFraction - colFraction) + grid[gridBaseIndex + 4] * rowFraction + grid[gridBaseIndex + 2 * (row + 1) + 2] * colFraction
            else
                dst[vertexOffset] = grid[gridBaseIndex + 2 * (row + 1) + 3] * (rowFraction - 1 + colFraction) + grid[gridBaseIndex + 2 * (row + 1) + 1] * (1 - rowFraction) + grid[gridBaseIndex + 3] * (1 - colFraction)
                dst[vertexOffset + 1] = grid[gridBaseIndex + 2 * (row + 1) + 4] * (rowFraction - 1 + colFraction) + grid[gridBaseIndex + 2 * (row + 1) + 2] * (1 - rowFraction) + grid[gridBaseIndex + 4] * (1 - colFraction)
            end
        end
    end
end

return WarpDeformer
