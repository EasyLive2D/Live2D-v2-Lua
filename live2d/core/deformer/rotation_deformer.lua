local Deformer = require("live2d.core.deformer.deformer")
local RotationContext = require("live2d.core.deformer.rotation_context")
local def = require("live2d.core.def")
local Float32Array = require("live2d.core.type.array").Float32Array
local UtMath = require("live2d.core.util.ut_math")
local floor = math.floor
local sin = math.sin
local cos = math.cos

local AffineEnt = {}  -- forward declaration
AffineEnt.__index = AffineEnt

local RotationDeformer = setmetatable({}, { __index = Deformer })
RotationDeformer.__index = RotationDeformer

RotationDeformer.temp1 = {0.0, 0.0}
RotationDeformer.temp2 = {0.0, 0.0}
RotationDeformer.temp3 = {0.0, 0.0}
RotationDeformer.temp4 = {0.0, 0.0}
RotationDeformer.temp5 = {0.0, 0.0}
RotationDeformer.temp6 = {0.0, 0.0}
RotationDeformer.paramOutside = {false}

function RotationDeformer.new()
    local self = setmetatable(Deformer.new(), RotationDeformer)
    self.pivotManager = nil
    self.affines = nil
    return self
end

function RotationDeformer:getType()
    return Deformer.TYPE_ROTATION
end

function RotationDeformer:read(br)
    Deformer.read(self, br)
    self.pivotManager = br:readObject()
    self.affines = br:readObject()
    Deformer.readOpacity(self, br)
end

function RotationDeformer:init(mc)
    local rctx = RotationContext.new(self)
    rctx.interpolatedAffine = AffineEnt.new()
    if self:needTransform() then
        rctx.transformedAffine = AffineEnt.new()
    end
    return rctx
end

local function setAffineFields(target, source)
    target.originX = source.originX
    target.originY = source.originY
    target.scaleX = source.scaleX
    target.scaleY = source.scaleY
    target.rotationDeg = source.rotationDeg
    target.reflectX = source.reflectX
    target.reflectY = source.reflectY
end

local function interp4(t1, t2, t3, t4, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15, v16)
    local lerpA = v1 + (v2 - v1) * t1
    local lerpB = v3 + (v4 - v3) * t1
    local lerpC = v5 + (v6 - v5) * t1
    local lerpD = v7 + (v8 - v7) * t1
    local lerpE = v9 + (v10 - v9) * t1
    local lerpF = v11 + (v12 - v11) * t1
    local lerpG = v13 + (v14 - v13) * t1
    local lerpH = v15 + (v16 - v15) * t1
    return (1 - t4) * ((1 - t3) * (lerpA + (lerpB - lerpA) * t2) + t3 * (lerpC + (lerpD - lerpC) * t2)) +
           t4 * ((1 - t3) * (lerpE + (lerpF - lerpE) * t2) + t3 * (lerpG + (lerpH - lerpG) * t2))
end

function RotationDeformer:setupInterpolate(mctx, rctx)
    if self ~= rctx:getDeformer() then
        error("context not match")
    end
    if not self.pivotManager:checkParamUpdated(mctx) then
        return
    end

    local success = RotationDeformer.paramOutside
    success[1] = false
    local pivotDimensionCount = self.pivotManager:calcPivotValues(mctx, success)
    rctx:setOutsideParam(success[1])
    self:interpolateOpacity(mctx, self.pivotManager, rctx, success)
    local pivotIndices = mctx:getTempPivotTableIndices()
    local pivotTValues = mctx:getTempT()
    self.pivotManager:calcPivotIndices(pivotIndices, pivotTValues, pivotDimensionCount)

    if pivotDimensionCount <= 0 then
        local affineEntry = self.affines[pivotIndices[1]]
        setAffineFields(rctx.interpolatedAffine, affineEntry)
    elseif pivotDimensionCount == 1 then
        local affine0 = self.affines[pivotIndices[1]]
        local affine1 = self.affines[pivotIndices[2]]
        local t1 = pivotTValues[1]
        rctx.interpolatedAffine.originX = affine0.originX + (affine1.originX - affine0.originX) * t1
        rctx.interpolatedAffine.originY = affine0.originY + (affine1.originY - affine0.originY) * t1
        rctx.interpolatedAffine.scaleX = affine0.scaleX + (affine1.scaleX - affine0.scaleX) * t1
        rctx.interpolatedAffine.scaleY = affine0.scaleY + (affine1.scaleY - affine0.scaleY) * t1
        rctx.interpolatedAffine.rotationDeg = affine0.rotationDeg + (affine1.rotationDeg - affine0.rotationDeg) * t1
    elseif pivotDimensionCount == 2 then
        local affine0 = self.affines[pivotIndices[1]]
        local affine1 = self.affines[pivotIndices[2]]
        local affine2 = self.affines[pivotIndices[3]]
        local affine3 = self.affines[pivotIndices[4]]
        local t1 = pivotTValues[1]
        local t2 = pivotTValues[2]
        local lerpA = affine0.originX + (affine1.originX - affine0.originX) * t1
        local lerpB = affine2.originX + (affine3.originX - affine2.originX) * t1
        rctx.interpolatedAffine.originX = lerpA + (lerpB - lerpA) * t2
        lerpA = affine0.originY + (affine1.originY - affine0.originY) * t1
        lerpB = affine2.originY + (affine3.originY - affine2.originY) * t1
        rctx.interpolatedAffine.originY = lerpA + (lerpB - lerpA) * t2
        lerpA = affine0.scaleX + (affine1.scaleX - affine0.scaleX) * t1
        lerpB = affine2.scaleX + (affine3.scaleX - affine2.scaleX) * t1
        rctx.interpolatedAffine.scaleX = lerpA + (lerpB - lerpA) * t2
        lerpA = affine0.scaleY + (affine1.scaleY - affine0.scaleY) * t1
        lerpB = affine2.scaleY + (affine3.scaleY - affine2.scaleY) * t1
        rctx.interpolatedAffine.scaleY = lerpA + (lerpB - lerpA) * t2
        lerpA = affine0.rotationDeg + (affine1.rotationDeg - affine0.rotationDeg) * t1
        lerpB = affine2.rotationDeg + (affine3.rotationDeg - affine2.rotationDeg) * t1
        rctx.interpolatedAffine.rotationDeg = lerpA + (lerpB - lerpA) * t2
    elseif pivotDimensionCount == 3 then
        local affine000 = self.affines[pivotIndices[1]]
        local affine001 = self.affines[pivotIndices[2]]
        local affine010 = self.affines[pivotIndices[3]]
        local affine011 = self.affines[pivotIndices[4]]
        local affine100 = self.affines[pivotIndices[5]]
        local affine101 = self.affines[pivotIndices[6]]
        local affine110 = self.affines[pivotIndices[7]]
        local affine111 = self.affines[pivotIndices[8]]
        local t1 = pivotTValues[1]
        local t2 = pivotTValues[2]
        local t3 = pivotTValues[3]
        local lerpA = affine000.originX + (affine001.originX - affine000.originX) * t1
        local lerpB = affine010.originX + (affine011.originX - affine010.originX) * t1
        local lerpC = affine100.originX + (affine101.originX - affine100.originX) * t1
        local lerpD = affine110.originX + (affine111.originX - affine110.originX) * t1
        rctx.interpolatedAffine.originX = (1 - t3) * (lerpA + (lerpB - lerpA) * t2) + t3 * (lerpC + (lerpD - lerpC) * t2)
        lerpA = affine000.originY + (affine001.originY - affine000.originY) * t1
        lerpB = affine010.originY + (affine011.originY - affine010.originY) * t1
        lerpC = affine100.originY + (affine101.originY - affine100.originY) * t1
        lerpD = affine110.originY + (affine111.originY - affine110.originY) * t1
        rctx.interpolatedAffine.originY = (1 - t3) * (lerpA + (lerpB - lerpA) * t2) + t3 * (lerpC + (lerpD - lerpC) * t2)
        lerpA = affine000.scaleX + (affine001.scaleX - affine000.scaleX) * t1
        lerpB = affine010.scaleX + (affine011.scaleX - affine010.scaleX) * t1
        lerpC = affine100.scaleX + (affine101.scaleX - affine100.scaleX) * t1
        lerpD = affine110.scaleX + (affine111.scaleX - affine110.scaleX) * t1
        rctx.interpolatedAffine.scaleX = (1 - t3) * (lerpA + (lerpB - lerpA) * t2) + t3 * (lerpC + (lerpD - lerpC) * t2)
        lerpA = affine000.scaleY + (affine001.scaleY - affine000.scaleY) * t1
        lerpB = affine010.scaleY + (affine011.scaleY - affine010.scaleY) * t1
        lerpC = affine100.scaleY + (affine101.scaleY - affine100.scaleY) * t1
        lerpD = affine110.scaleY + (affine111.scaleY - affine110.scaleY) * t1
        rctx.interpolatedAffine.scaleY = (1 - t3) * (lerpA + (lerpB - lerpA) * t2) + t3 * (lerpC + (lerpD - lerpC) * t2)
        lerpA = affine000.rotationDeg + (affine001.rotationDeg - affine000.rotationDeg) * t1
        lerpB = affine010.rotationDeg + (affine011.rotationDeg - affine010.rotationDeg) * t1
        lerpC = affine100.rotationDeg + (affine101.rotationDeg - affine100.rotationDeg) * t1
        lerpD = affine110.rotationDeg + (affine111.rotationDeg - affine110.rotationDeg) * t1
        rctx.interpolatedAffine.rotationDeg = (1 - t3) * (lerpA + (lerpB - lerpA) * t2) + t3 * (lerpC + (lerpD - lerpC) * t2)
    elseif pivotDimensionCount == 4 then
        local affine0000 = self.affines[pivotIndices[1]]
        local affine0001 = self.affines[pivotIndices[2]]
        local affine0010 = self.affines[pivotIndices[3]]
        local affine0011 = self.affines[pivotIndices[4]]
        local affine0100 = self.affines[pivotIndices[5]]
        local affine0101 = self.affines[pivotIndices[6]]
        local affine0110 = self.affines[pivotIndices[7]]
        local affine0111 = self.affines[pivotIndices[8]]
        local affine1000 = self.affines[pivotIndices[9]]
        local affine1001 = self.affines[pivotIndices[10]]
        local affine1010 = self.affines[pivotIndices[11]]
        local affine1011 = self.affines[pivotIndices[12]]
        local affine1100 = self.affines[pivotIndices[13]]
        local affine1101 = self.affines[pivotIndices[14]]
        local affine1110 = self.affines[pivotIndices[15]]
        local affine1111 = self.affines[pivotIndices[16]]
        local t1 = pivotTValues[1]
        local t2 = pivotTValues[2]
        local t3 = pivotTValues[3]
        local t4 = pivotTValues[4]
        rctx.interpolatedAffine.originX = interp4(t1, t2, t3, t4, affine0000.originX, affine0001.originX, affine0010.originX, affine0011.originX, affine0100.originX, affine0101.originX, affine0110.originX, affine0111.originX, affine1000.originX, affine1001.originX, affine1010.originX, affine1011.originX, affine1100.originX, affine1101.originX, affine1110.originX, affine1111.originX)
        rctx.interpolatedAffine.originY = interp4(t1, t2, t3, t4, affine0000.originY, affine0001.originY, affine0010.originY, affine0011.originY, affine0100.originY, affine0101.originY, affine0110.originY, affine0111.originY, affine1000.originY, affine1001.originY, affine1010.originY, affine1011.originY, affine1100.originY, affine1101.originY, affine1110.originY, affine1111.originY)
        rctx.interpolatedAffine.scaleX = interp4(t1, t2, t3, t4, affine0000.scaleX, affine0001.scaleX, affine0010.scaleX, affine0011.scaleX, affine0100.scaleX, affine0101.scaleX, affine0110.scaleX, affine0111.scaleX, affine1000.scaleX, affine1001.scaleX, affine1010.scaleX, affine1011.scaleX, affine1100.scaleX, affine1101.scaleX, affine1110.scaleX, affine1111.scaleX)
        rctx.interpolatedAffine.scaleY = interp4(t1, t2, t3, t4, affine0000.scaleY, affine0001.scaleY, affine0010.scaleY, affine0011.scaleY, affine0100.scaleY, affine0101.scaleY, affine0110.scaleY, affine0111.scaleY, affine1000.scaleY, affine1001.scaleY, affine1010.scaleY, affine1011.scaleY, affine1100.scaleY, affine1101.scaleY, affine1110.scaleY, affine1111.scaleY)
        rctx.interpolatedAffine.rotationDeg = interp4(t1, t2, t3, t4, affine0000.rotationDeg, affine0001.rotationDeg, affine0010.rotationDeg, affine0011.rotationDeg, affine0100.rotationDeg, affine0101.rotationDeg, affine0110.rotationDeg, affine0111.rotationDeg, affine1000.rotationDeg, affine1001.rotationDeg, affine1010.rotationDeg, affine1011.rotationDeg, affine1100.rotationDeg, affine1101.rotationDeg, affine1110.rotationDeg, affine1111.rotationDeg)
    else
        local tableSize = 2 ^ pivotDimensionCount
        local weightTable = Float32Array(tableSize)
        for bk = 1, tableSize do
            local bitPattern = bk - 1
            local weightProduct = 1
            for dim = 1, pivotDimensionCount do
                if bitPattern % 2 == 0 then
                    weightProduct = weightProduct * (1 - pivotTValues[dim])
                else
                    weightProduct = weightProduct * pivotTValues[dim]
                end
                bitPattern = floor(bitPattern / 2)
            end
            weightTable[bk] = weightProduct
        end

        local selectedAffines = {}
        for aU = 1, tableSize do
            selectedAffines[aU] = self.affines[pivotIndices[aU]]
        end

        local sumOriginX = 0
        local sumOriginY = 0
        local sumScaleX = 0
        local sumScaleY = 0
        local sumRotation = 0
        for aU = 1, tableSize do
            sumOriginX = sumOriginX + weightTable[aU] * selectedAffines[aU].originX
            sumOriginY = sumOriginY + weightTable[aU] * selectedAffines[aU].originY
            sumScaleX = sumScaleX + weightTable[aU] * selectedAffines[aU].scaleX
            sumScaleY = sumScaleY + weightTable[aU] * selectedAffines[aU].scaleY
            sumRotation = sumRotation + weightTable[aU] * selectedAffines[aU].rotationDeg
        end
        rctx.interpolatedAffine.originX = sumOriginX
        rctx.interpolatedAffine.originY = sumOriginY
        rctx.interpolatedAffine.scaleX = sumScaleX
        rctx.interpolatedAffine.scaleY = sumScaleY
        rctx.interpolatedAffine.rotationDeg = sumRotation
    end

    local bn = self.affines[pivotIndices[1]]
    rctx.interpolatedAffine.reflectX = bn.reflectX
    rctx.interpolatedAffine.reflectY = bn.reflectY
end

function RotationDeformer:setupTransform(mctx, rctx)
    if self ~= rctx:getDeformer() then
        error("Invalid Deformer")
    end

    rctx:setAvailable(true)
    if not self:needTransform() then
        rctx:setTotalScale_notForClient(rctx.interpolatedAffine.scaleX)
        rctx:setTotalOpacity(rctx:getInterpolatedOpacity())
    else
        local targetId = self:getTargetId()
        if rctx.tmpDeformerIndex == Deformer.DEFORMER_INDEX_NOT_INIT then
            rctx.tmpDeformerIndex = mctx:getDeformerIndex(targetId)
        end
        if rctx.tmpDeformerIndex < 0 then
            print("deformer is not reachable")
            rctx:setAvailable(false)
        else
            local deformer = mctx:getDeformer(rctx.tmpDeformerIndex)
            if deformer ~= nil then
                local dctx = mctx:getDeformerContext(rctx.tmpDeformerIndex)
                local transformOrigin = RotationDeformer.temp1
                transformOrigin[1] = rctx.interpolatedAffine.originX
                transformOrigin[2] = rctx.interpolatedAffine.originY
                local transformDir = RotationDeformer.temp2
                transformDir[1] = 0
                transformDir[2] = -0.1
                local parentType = dctx:getDeformer():getType()
                if parentType == Deformer.TYPE_ROTATION then
                    transformDir[2] = -10
                else
                    transformDir[2] = -0.1
                end
                local transformedDir = RotationDeformer.temp3
                RotationDeformer.getDirectionOnDst(mctx, deformer, dctx, transformOrigin, transformDir, transformedDir)
                local rotationAngle = UtMath.getAngleNotAbs(transformDir, transformedDir)
                deformer:transformPoints(mctx, dctx, transformOrigin, transformOrigin, 1, 0, 2)
                rctx.transformedAffine.originX = transformOrigin[1]
                rctx.transformedAffine.originY = transformOrigin[2]
                rctx.transformedAffine.scaleX = rctx.interpolatedAffine.scaleX
                rctx.transformedAffine.scaleY = rctx.interpolatedAffine.scaleY
                rctx.transformedAffine.rotationDeg = rctx.interpolatedAffine.rotationDeg - rotationAngle * UtMath.RAD_TO_DEG
                local parentTotalScale = dctx:getTotalScale()
                rctx:setTotalScale_notForClient(parentTotalScale * rctx.transformedAffine.scaleX)
                local parentTotalOpacity = dctx:getTotalOpacity()
                rctx:setTotalOpacity(parentTotalOpacity * rctx:getInterpolatedOpacity())
                rctx.transformedAffine.reflectX = rctx.interpolatedAffine.reflectX
                rctx.transformedAffine.reflectY = rctx.interpolatedAffine.reflectY
                rctx:setAvailable(dctx:isAvailable())
            else
                rctx:setAvailable(false)
            end
        end
    end
end

function RotationDeformer:transformPoints(mc, dc, srcPoints, dstPoints, numPoint, ptOffset, ptStep)
    if self ~= dc:getDeformer() then
        error("context not match")
    end
    local deformerCtx = dc
    local activeAffine
    if deformerCtx.transformedAffine ~= nil then
        activeAffine = deformerCtx.transformedAffine
    else
        activeAffine = deformerCtx.interpolatedAffine
    end
    local sinRotation = sin(UtMath.DEG_TO_RAD * activeAffine.rotationDeg)
    local cosRotation = cos(UtMath.DEG_TO_RAD * activeAffine.rotationDeg)
    local totalScale = deformerCtx:getTotalScale()
    local reflectXSign = activeAffine.reflectX and -1 or 1
    local reflectYSign = activeAffine.reflectY and -1 or 1
    local matrix00 = cosRotation * totalScale * reflectXSign
    local matrix01 = -sinRotation * totalScale * reflectYSign
    local matrix10 = sinRotation * totalScale * reflectXSign
    local matrix11 = cosRotation * totalScale * reflectYSign
    local originX = activeAffine.originX
    local originY = activeAffine.originY  -- same as originX in original
    local totalStride = numPoint * ptStep
    for offset = ptOffset + 1, totalStride, ptStep do
        local srcX = srcPoints[offset]
        local srcY = srcPoints[offset + 1]
        dstPoints[offset] = matrix00 * srcX + matrix01 * srcY + originX
        dstPoints[offset + 1] = matrix10 * srcX + matrix11 * srcY + originY
    end
end

function RotationDeformer.getDirectionOnDst(mdc, targetToDst, targetToDstContext, srcOrigin, srcDir, retDir)
    if targetToDst ~= targetToDstContext:getDeformer() then
        error("context not match")
    end
    local transformedOrigin = RotationDeformer.temp4
    transformedOrigin[1] = srcOrigin[1]
    transformedOrigin[2] = srcOrigin[2]
    targetToDst:transformPoints(mdc, targetToDstContext, transformedOrigin, transformedOrigin, 1, 0, 2)
    local transformedPoint = RotationDeformer.temp5
    local testPoint = RotationDeformer.temp6
    local maxAttempts = 10
    local stepSize = 1
    for attempt = 1, maxAttempts do
        testPoint[1] = srcOrigin[1] + stepSize * srcDir[1]
        testPoint[2] = srcOrigin[2] + stepSize * srcDir[2]
        targetToDst:transformPoints(mdc, targetToDstContext, testPoint, transformedPoint, 1, 0, 2)
        transformedPoint[1] = transformedPoint[1] - transformedOrigin[1]
        transformedPoint[2] = transformedPoint[2] - transformedOrigin[2]
        if transformedPoint[1] ~= 0 or transformedPoint[2] ~= 0 then
            retDir[1] = transformedPoint[1]
            retDir[2] = transformedPoint[2]
            return
        end
        testPoint[1] = srcOrigin[1] - stepSize * srcDir[1]
        testPoint[2] = srcOrigin[2] - stepSize * srcDir[2]
        targetToDst:transformPoints(mdc, targetToDstContext, testPoint, transformedPoint, 1, 0, 2)
        transformedPoint[1] = transformedPoint[1] - transformedOrigin[1]
        transformedPoint[2] = transformedPoint[2] - transformedOrigin[2]
        if transformedPoint[1] ~= 0 or transformedPoint[2] ~= 0 then
            transformedPoint[1] = -transformedPoint[1]
            transformedPoint[2] = -transformedPoint[2]
            retDir[1] = transformedPoint[1]
            retDir[2] = transformedPoint[2]
            return
        end
        stepSize = stepSize * 0.1
    end
    print("Invalid state")
end

function AffineEnt.new()
    local self = setmetatable({}, AffineEnt)
    self.originX = 0
    self.originY = 0
    self.scaleX = 1
    self.scaleY = 1
    self.rotationDeg = 0
    self.reflectX = false
    self.reflectY = false
    return self
end

function AffineEnt:read(br)
    self.originX = br:readFloat32()
    self.originY = br:readFloat32()
    self.scaleX = br:readFloat32()
    self.scaleY = br:readFloat32()
    self.rotationDeg = br:readFloat32()
    if br:getFormatVersion() >= def.LIVE2D_FORMAT_VERSION_V2_10_SDK2 then
        self.reflectX = br:readBoolean()
        self.reflectY = br:readBoolean()
    end
end

RotationDeformer.AffineEnt = AffineEnt

return RotationDeformer
