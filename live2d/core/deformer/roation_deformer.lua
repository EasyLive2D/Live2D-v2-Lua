local Deformer = require("live2d.core.deformer.deformer")
local RotationContext = require("live2d.core.deformer.rotation_context")
local def = require("live2d.core.def")
local Float32Array = require("live2d.core.type.array").Float32Array
local UtMath = require("live2d.core.util.ut_math")

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

function RotationDeformer:setupInterpolate(mctx, rctx)
    if self ~= rctx:getDeformer() then
        error("context not match")
    end
    if not self.pivotManager:checkParamUpdated(mctx) then
        return
    end

    local success = RotationDeformer.paramOutside
    success[1] = false
    local a2 = self.pivotManager:calcPivotValues(mctx, success)
    rctx:setOutsideParam(success[1])
    self:interpolateOpacity(mctx, self.pivotManager, rctx, success)
    local a3 = mctx:getTempPivotTableIndices()
    local ba = mctx:getTempT()
    self.pivotManager:calcPivotIndices(a3, ba, a2)

    if a2 <= 0 then
        local bn_3 = self.affines[a3[1]]
        setAffineFields(rctx.interpolatedAffine, bn_3)
    elseif a2 == 1 then
        local bn_1 = self.affines[a3[1]]
        local bl = self.affines[a3[2]]
        local a9 = ba[1]
        rctx.interpolatedAffine.originX = bn_1.originX + (bl.originX - bn_1.originX) * a9
        rctx.interpolatedAffine.originY = bn_1.originY + (bl.originY - bn_1.originY) * a9
        rctx.interpolatedAffine.scaleX = bn_1.scaleX + (bl.scaleX - bn_1.scaleX) * a9
        rctx.interpolatedAffine.scaleY = bn_1.scaleY + (bl.scaleY - bn_1.scaleY) * a9
        rctx.interpolatedAffine.rotationDeg = bn_1.rotationDeg + (bl.rotationDeg - bn_1.rotationDeg) * a9
    elseif a2 == 2 then
        local bn_1 = self.affines[a3[1]]
        local bl = self.affines[a3[2]]
        local a1 = self.affines[a3[3]]
        local a0 = self.affines[a3[4]]
        local a9 = ba[1]
        local a8 = ba[2]
        local bC = bn_1.originX + (bl.originX - bn_1.originX) * a9
        local bB = a1.originX + (a0.originX - a1.originX) * a9
        rctx.interpolatedAffine.originX = bC + (bB - bC) * a8
        bC = bn_1.originY + (bl.originY - bn_1.originY) * a9
        bB = a1.originY + (a0.originY - a1.originY) * a9
        rctx.interpolatedAffine.originY = bC + (bB - bC) * a8
        bC = bn_1.scaleX + (bl.scaleX - bn_1.scaleX) * a9
        bB = a1.scaleX + (a0.scaleX - a1.scaleX) * a9
        rctx.interpolatedAffine.scaleX = bC + (bB - bC) * a8
        bC = bn_1.scaleY + (bl.scaleY - bn_1.scaleY) * a9
        bB = a1.scaleY + (a0.scaleY - a1.scaleY) * a9
        rctx.interpolatedAffine.scaleY = bC + (bB - bC) * a8
        bC = bn_1.rotationDeg + (bl.rotationDeg - bn_1.rotationDeg) * a9
        bB = a1.rotationDeg + (a0.rotationDeg - a1.rotationDeg) * a9
        rctx.interpolatedAffine.rotationDeg = bC + (bB - bC) * a8
    elseif a2 == 3 then
        local aP = self.affines[a3[1]]
        local aO = self.affines[a3[2]]
        local bu = self.affines[a3[3]]
        local bs = self.affines[a3[4]]
        local aK = self.affines[a3[5]]
        local aJ = self.affines[a3[6]]
        local bj = self.affines[a3[7]]
        local bi = self.affines[a3[8]]
        local a9 = ba[1]
        local a8 = ba[2]
        local a6 = ba[3]
        local bC = aP.originX + (aO.originX - aP.originX) * a9
        local bB = bu.originX + (bs.originX - bu.originX) * a9
        local bz = aK.originX + (aJ.originX - aK.originX) * a9
        local by = bj.originX + (bi.originX - bj.originX) * a9
        rctx.interpolatedAffine.originX = (1 - a6) * (bC + (bB - bC) * a8) + a6 * (bz + (by - bz) * a8)
        bC = aP.originY + (aO.originY - aP.originY) * a9
        bB = bu.originY + (bs.originY - bu.originY) * a9
        bz = aK.originY + (aJ.originY - aK.originY) * a9
        by = bj.originY + (bi.originY - bj.originY) * a9
        rctx.interpolatedAffine.originY = (1 - a6) * (bC + (bB - bC) * a8) + a6 * (bz + (by - bz) * a8)
        bC = aP.scaleX + (aO.scaleX - aP.scaleX) * a9
        bB = bu.scaleX + (bs.scaleX - bu.scaleX) * a9
        bz = aK.scaleX + (aJ.scaleX - aK.scaleX) * a9
        by = bj.scaleX + (bi.scaleX - bj.scaleX) * a9
        rctx.interpolatedAffine.scaleX = (1 - a6) * (bC + (bB - bC) * a8) + a6 * (bz + (by - bz) * a8)
        bC = aP.scaleY + (aO.scaleY - aP.scaleY) * a9
        bB = bu.scaleY + (bs.scaleY - bu.scaleY) * a9
        bz = aK.scaleY + (aJ.scaleY - aK.scaleY) * a9
        by = bj.scaleY + (bi.scaleY - bj.scaleY) * a9
        rctx.interpolatedAffine.scaleY = (1 - a6) * (bC + (bB - bC) * a8) + a6 * (bz + (by - bz) * a8)
        bC = aP.rotationDeg + (aO.rotationDeg - aP.rotationDeg) * a9
        bB = bu.rotationDeg + (bs.rotationDeg - bu.rotationDeg) * a9
        bz = aK.rotationDeg + (aJ.rotationDeg - aK.rotationDeg) * a9
        by = bj.rotationDeg + (bi.rotationDeg - bj.rotationDeg) * a9
        rctx.interpolatedAffine.rotationDeg = (1 - a6) * (bC + (bB - bC) * a8) + a6 * (bz + (by - bz) * a8)
    elseif a2 == 4 then
        local aT = self.affines[a3[1]]
        local aS = self.affines[a3[2]]
        local bE = self.affines[a3[3]]
        local bD = self.affines[a3[4]]
        local aN = self.affines[a3[5]]
        local aM = self.affines[a3[6]]
        local bp = self.affines[a3[7]]
        local bo = self.affines[a3[8]]
        local bh = self.affines[a3[9]]
        local bg = self.affines[a3[10]]
        local aY = self.affines[a3[11]]
        local aW = self.affines[a3[12]]
        local a7 = self.affines[a3[13]]
        local a5 = self.affines[a3[14]]
        local aR = self.affines[a3[15]]
        local aQ = self.affines[a3[16]]
        local a9 = ba[1]
        local a8 = ba[2]
        local a6 = ba[3]
        local a4 = ba[4]
        local function interp4(v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15, v16)
            local bC = v1 + (v2 - v1) * a9
            local bB = v3 + (v4 - v3) * a9
            local bz = v5 + (v6 - v5) * a9
            local by = v7 + (v8 - v7) * a9
            local bv = v9 + (v10 - v9) * a9
            local bt = v11 + (v12 - v11) * a9
            local br = v13 + (v14 - v13) * a9
            local bq = v15 + (v16 - v15) * a9
            return (1 - a4) * ((1 - a6) * (bC + (bB - bC) * a8) + a6 * (bz + (by - bz) * a8)) +
                   a4 * ((1 - a6) * (bv + (bt - bv) * a8) + a6 * (br + (bq - br) * a8))
        end
        rctx.interpolatedAffine.originX = interp4(aT.originX, aS.originX, bE.originX, bD.originX, aN.originX, aM.originX, bp.originX, bo.originX, bh.originX, bg.originX, aY.originX, aW.originX, a7.originX, a5.originX, aR.originX, aQ.originX)
        rctx.interpolatedAffine.originY = interp4(aT.originY, aS.originY, bE.originY, bD.originY, aN.originY, aM.originY, bp.originY, bo.originY, bh.originY, bg.originY, aY.originY, aW.originY, a7.originY, a5.originY, aR.originY, aQ.originY)
        rctx.interpolatedAffine.scaleX = interp4(aT.scaleX, aS.scaleX, bE.scaleX, bD.scaleX, aN.scaleX, aM.scaleX, bp.scaleX, bo.scaleX, bh.scaleX, bg.scaleX, aY.scaleX, aW.scaleX, a7.scaleX, a5.scaleX, aR.scaleX, aQ.scaleX)
        rctx.interpolatedAffine.scaleY = interp4(aT.scaleY, aS.scaleY, bE.scaleY, bD.scaleY, aN.scaleY, aM.scaleY, bp.scaleY, bo.scaleY, bh.scaleY, bg.scaleY, aY.scaleY, aW.scaleY, a7.scaleY, a5.scaleY, aR.scaleY, aQ.scaleY)
        rctx.interpolatedAffine.rotationDeg = interp4(aT.rotationDeg, aS.rotationDeg, bE.rotationDeg, bD.rotationDeg, aN.rotationDeg, aM.rotationDeg, bp.rotationDeg, bo.rotationDeg, bh.rotationDeg, bg.rotationDeg, aY.rotationDeg, aW.rotationDeg, a7.rotationDeg, a5.rotationDeg, aR.rotationDeg, aQ.rotationDeg)
    else
        local aV = 2 ^ a2
        local aZ = Float32Array(aV)
        for bk = 1, aV do
            local aI = bk - 1
            local aH = 1
            for aL = 1, a2 do
                if aI % 2 == 0 then
                    aH = aH * (1 - ba[aL])
                else
                    aH = aH * ba[aL]
                end
                aI = math.floor(aI / 2)
            end
            aZ[bk] = aH
        end

        local bA = {}
        for aU = 1, aV do
            bA[aU] = self.affines[a3[aU]]
        end

        local be = 0
        local bc = 0
        local bd = 0
        local bb = 0
        local aX = 0
        for aU = 1, aV do
            be = be + aZ[aU] * bA[aU].originX
            bc = bc + aZ[aU] * bA[aU].originY
            bd = bd + aZ[aU] * bA[aU].scaleX
            bb = bb + aZ[aU] * bA[aU].scaleY
            aX = aX + aZ[aU] * bA[aU].rotationDeg
        end
        rctx.interpolatedAffine.originX = be
        rctx.interpolatedAffine.originY = bc
        rctx.interpolatedAffine.scaleX = bd
        rctx.interpolatedAffine.scaleY = bb
        rctx.interpolatedAffine.rotationDeg = aX
    end

    local bn = self.affines[a3[1]]
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
        local aT = self:getTargetId()
        if rctx.tmpDeformerIndex == Deformer.DEFORMER_INDEX_NOT_INIT then
            rctx.tmpDeformerIndex = mctx:getDeformerIndex(aT)
        end
        if rctx.tmpDeformerIndex < 0 then
            print("deformer is not reachable")
            rctx:setAvailable(false)
        else
            local deformer = mctx:getDeformer(rctx.tmpDeformerIndex)
            if deformer ~= nil then
                local dctx = mctx:getDeformerContext(rctx.tmpDeformerIndex)
                local aS = RotationDeformer.temp1
                aS[1] = rctx.interpolatedAffine.originX
                aS[2] = rctx.interpolatedAffine.originY
                local aJ = RotationDeformer.temp2
                aJ[1] = 0
                aJ[2] = -0.1
                local aO = dctx:getDeformer():getType()
                if aO == Deformer.TYPE_ROTATION then
                    aJ[2] = -10
                else
                    aJ[2] = -0.1
                end
                local aQ = RotationDeformer.temp3
                RotationDeformer.getDirectionOnDst(mctx, deformer, dctx, aS, aJ, aQ)
                local aP = UtMath.getAngleNotAbs(aJ, aQ)
                deformer:transformPoints(mctx, dctx, aS, aS, 1, 0, 2)
                rctx.transformedAffine.originX = aS[1]
                rctx.transformedAffine.originY = aS[2]
                rctx.transformedAffine.scaleX = rctx.interpolatedAffine.scaleX
                rctx.transformedAffine.scaleY = rctx.interpolatedAffine.scaleY
                rctx.transformedAffine.rotationDeg = rctx.interpolatedAffine.rotationDeg - aP * UtMath.RAD_TO_DEG
                local aK = dctx:getTotalScale()
                rctx:setTotalScale_notForClient(aK * rctx.transformedAffine.scaleX)
                local aN = dctx:getTotalOpacity()
                rctx:setTotalOpacity(aN * rctx:getInterpolatedOpacity())
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
    local aH = dc
    local aU
    if aH.transformedAffine ~= nil then
        aU = aH.transformedAffine
    else
        aU = aH.interpolatedAffine
    end
    local a0 = math.sin(UtMath.DEG_TO_RAD * aU.rotationDeg)
    local aP = math.cos(UtMath.DEG_TO_RAD * aU.rotationDeg)
    local a3 = aH:getTotalScale()
    local aW = aU.reflectX and -1 or 1
    local aV = aU.reflectY and -1 or 1
    local aS = aP * a3 * aW
    local aQ = -a0 * a3 * aV
    local a1 = a0 * a3 * aW
    local aZ = aP * a3 * aV
    local aY = aU.originX
    local aX = aU.originY  -- same as originX in original
    local aI = numPoint * ptStep
    for aK = ptOffset + 1, aI, ptStep do
        local aN = srcPoints[aK]
        local aM = srcPoints[aK + 1]
        dstPoints[aK] = aS * aN + aQ * aM + aY
        dstPoints[aK + 1] = a1 * aN + aZ * aM + aX
    end
end

function RotationDeformer.getDirectionOnDst(mdc, targetToDst, targetToDstContext, srcOrigin, srcDir, retDir)
    if targetToDst ~= targetToDstContext:getDeformer() then
        error("context not match")
    end
    local aO = RotationDeformer.temp4
    aO[1] = srcOrigin[1]
    aO[2] = srcOrigin[2]
    targetToDst:transformPoints(mdc, targetToDstContext, aO, aO, 1, 0, 2)
    local aL = RotationDeformer.temp5
    local aS = RotationDeformer.temp6
    local aN = 10
    local aJ = 1
    for aM = 1, aN do
        aS[1] = srcOrigin[1] + aJ * srcDir[1]
        aS[2] = srcOrigin[2] + aJ * srcDir[2]
        targetToDst:transformPoints(mdc, targetToDstContext, aS, aL, 1, 0, 2)
        aL[1] = aL[1] - aO[1]
        aL[2] = aL[2] - aO[2]
        if aL[1] ~= 0 or aL[2] ~= 0 then
            retDir[1] = aL[1]
            retDir[2] = aL[2]
            return
        end
        aS[1] = srcOrigin[1] - aJ * srcDir[1]
        aS[2] = srcOrigin[2] - aJ * srcDir[2]
        targetToDst:transformPoints(mdc, targetToDstContext, aS, aL, 1, 0, 2)
        aL[1] = aL[1] - aO[1]
        aL[2] = aL[2] - aO[2]
        if aL[1] ~= 0 or aL[2] ~= 0 then
            aL[1] = -aL[1]
            aL[2] = -aL[2]
            retDir[1] = aL[1]
            retDir[2] = aL[2]
            return
        end
        aJ = aJ * 0.1
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

function AffineEnt:init(other)
    self.originX = other.originX
    self.originY = other.originY
    self.scaleX = other.scaleX
    self.scaleY = other.scaleY
    self.rotationDeg = other.rotationDeg
    self.reflectX = other.reflectX
    self.reflectY = other.reflectY
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
