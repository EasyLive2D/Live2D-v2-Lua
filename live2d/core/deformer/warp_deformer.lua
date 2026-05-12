local Deformer = require("live2d.core.deformer.deformer")
local WarpContext = require("live2d.core.deformer.warp_context")
local Float32Array = require("live2d.core.type.array").Float32Array
local UtInterpolate = require("live2d.core.util.ut_interpolate")

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
    local aI = WarpContext.new(self)
    local aJ = (self.row + 1) * (self.col + 1)
    if aI.interpolatedPoints ~= nil then
        aI.interpolatedPoints = nil
    end
    aI.interpolatedPoints = Float32Array(aJ * 2)
    if aI.transformedPoints ~= nil then
        aI.transformedPoints = nil
    end
    if self:needTransform() then
        aI.transformedPoints = Float32Array(aJ * 2)
    else
        aI.transformedPoints = nil
    end
    return aI
end

function WarpDeformer:setupInterpolate(modelContext, deformerContext)
    local aK = deformerContext
    if not self.pivotMgr:checkParamUpdated(modelContext) then
        return
    end
    local aL = self:getPointCount()
    local aH = WarpDeformer.paramOutSide
    aH[1] = false
    UtInterpolate.interpolatePoints(modelContext, self.pivotMgr, aH, aL, self.pivotPoints, aK.interpolatedPoints, 0, 2)
    deformerContext:setOutsideParam(aH[1])
    self:interpolateOpacity(modelContext, self.pivotMgr, deformerContext, aH)
end

function WarpDeformer:setupTransform(modelContext, deformerContext)
    local aL = deformerContext
    aL:setAvailable(true)
    if not self:needTransform() then
        aL:setTotalOpacity(aL:getInterpolatedOpacity())
    else
        local aH = self:getTargetId()
        if aL.tmpDeformerIndex == Deformer.DEFORMER_INDEX_NOT_INIT then
            aL.tmpDeformerIndex = modelContext:getDeformerIndex(aH)
        end
        if aL.tmpDeformerIndex < 0 then
            print("deformer is not reachable")
            aL:setAvailable(false)
        else
            local aN = modelContext:getDeformer(aL.tmpDeformerIndex)
            local aI = modelContext:getDeformerContext(aL.tmpDeformerIndex)
            if aN ~= nil and aI:isAvailable() then
                local aM = aI:getTotalScale()
                aL:setTotalScale_notForClient(aM)
                local aO = aI:getTotalOpacity()
                aL:setTotalOpacity(aO * aL:getInterpolatedOpacity())
                aN:transformPoints(modelContext, aI, aL.interpolatedPoints, aL.transformedPoints, self:getPointCount(), 0, 2)
                aL:setAvailable(true)
            else
                aL:setAvailable(false)
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

function WarpDeformer.transformPoints_sdk2(hvs, dst, pointCount, srcOffset, srcStep, grid, row, col)
    local aW = pointCount * srcStep
    local aT = 0
    local aS = 0
    local bl = 0
    local bk = 0
    local bf = 0
    local be = 0
    local aZ = false
    for ba = srcOffset + 1, aW, srcStep do
        local a4 = hvs[ba]
        local aX = hvs[ba + 1]
        local bd = a4 * row
        local a7 = aX * col
        if bd < 0 or a7 < 0 or row <= bd or col <= a7 then
            local a1 = row + 1
            if not aZ then
                aZ = true
                aT = 0.25 * (grid[((0) + (0) * a1) * 2 + 1] + grid[((row) + (0) * a1) * 2 + 1] +
                             grid[((0) + (col) * a1) * 2 + 1] + grid[((row) + (col) * a1) * 2 + 1])
                aS = 0.25 * (grid[((0) + (0) * a1) * 2 + 2] + grid[((row) + (0) * a1) * 2 + 2] +
                             grid[((0) + (col) * a1) * 2 + 2] + grid[((row) + (col) * a1) * 2 + 2])
                local aM = grid[((row) + (col) * a1) * 2 + 1] - grid[((0) + (0) * a1) * 2 + 1]
                local aL = grid[((row) + (col) * a1) * 2 + 2] - grid[((0) + (0) * a1) * 2 + 2]
                local bh = grid[((row) + (0) * a1) * 2 + 1] - grid[((0) + (col) * a1) * 2 + 1]
                local bg = grid[((row) + (0) * a1) * 2 + 2] - grid[((0) + (col) * a1) * 2 + 2]
                bl = (aM + bh) * 0.5
                bk = (aL + bg) * 0.5
                bf = (aM - bh) * 0.5
                be = (aL - bg) * 0.5
                aT = aT - 0.5 * (bl + bf)
                aS = aS - 0.5 * (bk + be)
            end

            if (-2 < a4 and a4 < 3) and (-2 < aX and aX < 3) then
                if a4 <= 0 then
                    if aX <= 0 then
                        local a3 = grid[((0) + (0) * a1) * 2 + 1]
                        local a2 = grid[((0) + (0) * a1) * 2 + 2]
                        local a8 = aT - 2 * bl
                        local a6 = aS - 2 * bk
                        local aK = aT - 2 * bf
                        local aJ = aS - 2 * be
                        local aO = aT - 2 * bl - 2 * bf
                        local aN = aS - 2 * bk - 2 * be
                        local bj = 0.5 * (a4 - (-2))
                        local bi = 0.5 * (aX - (-2))
                        if bj + bi <= 1 then
                            dst[ba] = aO + (aK - aO) * bj + (a8 - aO) * bi
                            dst[ba + 1] = aN + (aJ - aN) * bj + (a6 - aN) * bi
                        else
                            dst[ba] = a3 + (a8 - a3) * (1 - bj) + (aK - a3) * (1 - bi)
                            dst[ba + 1] = a2 + (a6 - a2) * (1 - bj) + (aJ - a2) * (1 - bi)
                        end
                    elseif aX >= 1 then
                        local aK = grid[((0) + (col) * a1) * 2 + 1]
                        local aJ = grid[((0) + (col) * a1) * 2 + 2]
                        local aO = aT - 2 * bl + 1 * bf
                        local aN = aS - 2 * bk + 1 * be
                        local a3 = aT + 3 * bf
                        local a2 = aS + 3 * be
                        local a8 = aT - 2 * bl + 3 * bf
                        local a6 = aS - 2 * bk + 3 * be
                        local bj = 0.5 * (a4 - (-2))
                        local bi = 0.5 * (aX - (1))
                        if bj + bi <= 1 then
                            dst[ba] = aO + (aK - aO) * bj + (a8 - aO) * bi
                            dst[ba + 1] = aN + (aJ - aN) * bj + (a6 - aN) * bi
                        else
                            dst[ba] = a3 + (a8 - a3) * (1 - bj) + (aK - a3) * (1 - bi)
                            dst[ba + 1] = a2 + (a6 - a2) * (1 - bj) + (aJ - a2) * (1 - bi)
                        end
                    else
                        local aH = math.floor(a7)
                        if aH == col then aH = col - 1 end
                        local bj = 0.5 * (a4 - (-2))
                        local bi = a7 - aH
                        local bb = aH / col
                        local a9 = (aH + 1) / col
                        aK = grid[((0) + (aH) * a1) * 2 + 1]
                        aJ = grid[((0) + (aH) * a1) * 2 + 2]
                        a3 = grid[((0) + (aH + 1) * a1) * 2 + 1]
                        a2 = grid[((0) + (aH + 1) * a1) * 2 + 2]
                        local aO = aT - 2 * bl + bb * bf
                        local aN = aS - 2 * bk + bb * be
                        local a8 = aT - 2 * bl + a9 * bf
                        local a6 = aS - 2 * bk + a9 * be
                        if bj + bi <= 1 then
                            dst[ba] = aO + (aK - aO) * bj + (a8 - aO) * bi
                            dst[ba + 1] = aN + (aJ - aN) * bj + (a6 - aN) * bi
                        else
                            dst[ba] = a3 + (a8 - a3) * (1 - bj) + (aK - a3) * (1 - bi)
                            dst[ba + 1] = a2 + (a6 - a2) * (1 - bj) + (aJ - a2) * (1 - bi)
                        end
                    end
                else
                    if 1 <= a4 then
                        if aX <= 0 then
                            local a8 = grid[((row) + (0) * a1) * 2 + 1]
                            local a6 = grid[((row) + (0) * a1) * 2 + 2]
                            local a3 = aT + 3 * bl
                            local a2 = aS + 3 * bk
                            local aO = aT + 1 * bl - 2 * bf
                            local aN = aS + 1 * bk - 2 * be
                            local aK = aT + 3 * bl - 2 * bf
                            local aJ = aS + 3 * bk - 2 * be
                            local bj = 0.5 * (a4 - (1))
                            local bi = 0.5 * (aX - (-2))
                            if bj + bi <= 1 then
                                dst[ba] = aO + (aK - aO) * bj + (a8 - aO) * bi
                                dst[ba + 1] = aN + (aJ - aN) * bj + (a6 - aN) * bi
                            else
                                dst[ba] = a3 + (a8 - a3) * (1 - bj) + (aK - a3) * (1 - bi)
                                dst[ba + 1] = a2 + (a6 - a2) * (1 - bj) + (aJ - a2) * (1 - bi)
                            end
                        elseif aX >= 1 then
                            local aO = grid[((row) + (col) * a1) * 2 + 1]
                            local aN = grid[((row) + (col) * a1) * 2 + 2]
                            local aK = aT + 3 * bl + 1 * bf
                            local aJ = aS + 3 * bk + 1 * be
                            local a8 = aT + 1 * bl + 3 * bf
                            local a6 = aS + 1 * bk + 3 * be
                            local a3 = aT + 3 * bl + 3 * bf
                            local a2 = aS + 3 * bk + 3 * be
                            local bj = 0.5 * (a4 - (1))
                            local bi = 0.5 * (aX - (1))
                            if bj + bi <= 1 then
                                dst[ba] = aO + (aK - aO) * bj + (a8 - aO) * bi
                                dst[ba + 1] = aN + (aJ - aN) * bj + (a6 - aN) * bi
                            else
                                dst[ba] = a3 + (a8 - a3) * (1 - bj) + (aK - a3) * (1 - bi)
                                dst[ba + 1] = a2 + (a6 - a2) * (1 - bj) + (aJ - a2) * (1 - bi)
                            end
                        else
                            local aH = math.floor(a7)
                            if aH == col then aH = col - 1 end
                            local bj = 0.5 * (a4 - (1))
                            local bi = a7 - aH
                            local bb = aH / col
                            local a9 = (aH + 1) / col
                            aO = grid[((row) + (aH) * a1) * 2 + 1]
                            aN = grid[((row) + (aH) * a1) * 2 + 2]
                            local a8 = grid[((row) + (aH + 1) * a1) * 2 + 1]
                            local a6 = grid[((row) + (aH + 1) * a1) * 2 + 2]
                            aK = aT + 3 * bl + bb * bf
                            aJ = aS + 3 * bk + bb * be
                            a3 = aT + 3 * bl + a9 * bf
                            a2 = aS + 3 * bk + a9 * be
                            if bj + bi <= 1 then
                                dst[ba] = aO + (aK - aO) * bj + (a8 - aO) * bi
                                dst[ba + 1] = aN + (aJ - aN) * bj + (a6 - aN) * bi
                            else
                                dst[ba] = a3 + (a8 - a3) * (1 - bj) + (aK - a3) * (1 - bi)
                                dst[ba + 1] = a2 + (a6 - a2) * (1 - bj) + (aJ - a2) * (1 - bi)
                            end
                        end
                    else
                        if aX <= 0 then
                            local aY = math.floor(bd)
                            if aY == row then aY = row - 1 end
                            local bj = bd - aY
                            local bi = 0.5 * (aX - (-2))
                            local bp = aY / row
                            local bo = (aY + 1) / row
                            local a8 = grid[((aY) + (0) * a1) * 2 + 1]
                            local a6 = grid[((aY) + (0) * a1) * 2 + 2]
                            local a3 = grid[((aY + 1) + (0) * a1) * 2 + 1]
                            local a2 = grid[((aY + 1) + (0) * a1) * 2 + 2]
                            local aO = aT + bp * bl - 2 * bf
                            local aN = aS + bp * bk - 2 * be
                            local aK = aT + bo * bl - 2 * bf
                            local aJ = aS + bo * bk - 2 * be
                            if bj + bi <= 1 then
                                dst[ba] = aO + (aK - aO) * bj + (a8 - aO) * bi
                                dst[ba + 1] = aN + (aJ - aN) * bj + (a6 - aN) * bi
                            else
                                dst[ba] = a3 + (a8 - a3) * (1 - bj) + (aK - a3) * (1 - bi)
                                dst[ba + 1] = a2 + (a6 - a2) * (1 - bj) + (aJ - a2) * (1 - bi)
                            end
                        elseif aX >= 1 then
                            local aY = math.floor(bd)
                            if aY == row then aY = row - 1 end
                            local bj = bd - aY
                            local bi = 0.5 * (aX - (1))
                            local bp = aY / row
                            local bo = (aY + 1) / row
                            local aO = grid[((aY) + (col) * a1) * 2 + 1]
                            local aN = grid[((aY) + (col) * a1) * 2 + 2]
                            local aK = grid[((aY + 1) + (col) * a1) * 2 + 1]
                            local aJ = grid[((aY + 1) + (col) * a1) * 2 + 2]
                            local a8 = aT + bp * bl + 3 * bf
                            local a6 = aS + bp * bk + 3 * be
                            local a3 = aT + bo * bl + 3 * bf
                            local a2 = aS + bo * bk + 3 * be
                            if bj + bi <= 1 then
                                dst[ba] = aO + (aK - aO) * bj + (a8 - aO) * bi
                                dst[ba + 1] = aN + (aJ - aN) * bj + (a6 - aN) * bi
                            else
                                dst[ba] = a3 + (a8 - a3) * (1 - bj) + (aK - a3) * (1 - bi)
                                dst[ba + 1] = a2 + (a6 - a2) * (1 - bj) + (aJ - a2) * (1 - bi)
                            end
                        else
                            error("error @BDBoxGrid")
                        end
                    end
                end
            else
                dst[ba] = aT + a4 * bl + aX * bf
                dst[ba + 1] = aS + a4 * bk + aX * be
            end
        else
            local bn = bd - math.floor(bd)
            local bm = a7 - math.floor(a7)
            local aV = 2 * (math.floor(bd) + math.floor(a7) * (row + 1))
            if bn + bm < 1 then
                dst[ba] = grid[aV + 1] * (1 - bn - bm) + grid[aV + 3] * bn + grid[aV + 2 * (row + 1) + 1] * bm
                dst[ba + 1] = grid[aV + 2] * (1 - bn - bm) + grid[aV + 4] * bn + grid[aV + 2 * (row + 1) + 2] * bm
            else
                dst[ba] = grid[aV + 2 * (row + 1) + 3] * (bn - 1 + bm) + grid[aV + 2 * (row + 1) + 1] * (1 - bn) + grid[aV + 3] * (1 - bm)
                dst[ba + 1] = grid[aV + 2 * (row + 1) + 4] * (bn - 1 + bm) + grid[aV + 2 * (row + 1) + 2] * (1 - bn) + grid[aV + 4] * (1 - bm)
            end
        end
    end
end

return WarpDeformer
