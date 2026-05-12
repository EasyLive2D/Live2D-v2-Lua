local UtSystem = require("live2d.core.util.ut_system")
local Float32Array = require("live2d.core.type.array").Float32Array

local UtInterpolate = {}

function UtInterpolate.interpolateInt(mdc, pivotMgr, ret, pivotValue)
    local a1 = pivotMgr:calcPivotValues(mdc, ret)
    local a3 = mdc:getTempPivotTableIndices()
    local ba = mdc:getTempT()
    pivotMgr:calcPivotIndices(a3, ba, a1)

    if a1 <= 0 then
        return pivotValue[a3[1]]
    elseif a1 == 1 then
        local bj = pivotValue[a3[1]]
        local bi = pivotValue[a3[2]]
        local a9 = ba[1]
        return math.floor(bj + (bi - bj) * a9 + 0.5)
    elseif a1 == 2 then
        local bj = pivotValue[a3[1]]
        local bi = pivotValue[a3[2]]
        local a0 = pivotValue[a3[3]]
        local aZ = pivotValue[a3[4]]
        local a9 = ba[1]
        local a8 = ba[2]
        local br = math.floor(bj + (bi - bj) * a9 + 0.5)
        local bq = math.floor(a0 + (aZ - a0) * a9 + 0.5)
        return math.floor(br + (bq - br) * a8 + 0.5)
    elseif a1 == 3 then
        local aP = pivotValue[a3[1]]
        local aO = pivotValue[a3[2]]
        local bn = pivotValue[a3[3]]
        local bm = pivotValue[a3[4]]
        local aK = pivotValue[a3[5]]
        local aJ = pivotValue[a3[6]]
        local bg = pivotValue[a3[7]]
        local bf = pivotValue[a3[8]]
        local a9 = ba[1]
        local a8 = ba[2]
        local a6 = ba[3]
        local bj = math.floor(aP + (aO - aP) * a9 + 0.5)
        local bi = math.floor(bn + (bm - bn) * a9 + 0.5)
        local a0_v = math.floor(aK + (aJ - aK) * a9 + 0.5)
        local aZ_v = math.floor(bg + (bf - bg) * a9 + 0.5)
        local br = math.floor(bj + (bi - bj) * a8 + 0.5)
        local bq = math.floor(a0_v + (aZ_v - a0_v) * a8 + 0.5)
        return math.floor(br + (bq - br) * a6 + 0.5)
    elseif a1 == 4 then
        local aT = pivotValue[a3[1]]
        local aS = pivotValue[a3[2]]
        local bu = pivotValue[a3[3]]
        local bt = pivotValue[a3[4]]
        local aN = pivotValue[a3[5]]
        local aM = pivotValue[a3[6]]
        local bl = pivotValue[a3[7]]
        local bk = pivotValue[a3[8]]
        local be = pivotValue[a3[9]]
        local bc = pivotValue[a3[10]]
        local aX = pivotValue[a3[11]]
        local aW = pivotValue[a3[12]]
        local a7 = pivotValue[a3[13]]
        local a5 = pivotValue[a3[14]]
        local aR = pivotValue[a3[15]]
        local aQ = pivotValue[a3[16]]
        local a9 = ba[1]
        local a8 = ba[2]
        local a6 = ba[3]
        local a4 = ba[4]
        local aP_v = math.floor(aT + (aS - aT) * a9 + 0.5)
        local aO_v = math.floor(bu + (bt - bu) * a9 + 0.5)
        local bn_v = math.floor(aN + (aM - aN) * a9 + 0.5)
        local bm_v = math.floor(bl + (bk - bl) * a9 + 0.5)
        local aK_v = math.floor(be + (bc - be) * a9 + 0.5)
        local aJ_v = math.floor(aX + (aW - aX) * a9 + 0.5)
        local bg_v = math.floor(a7 + (a5 - a7) * a9 + 0.5)
        local bf_v = math.floor(aR + (aQ - aR) * a9 + 0.5)
        local bj_v = math.floor(aP_v + (aO_v - aP_v) * a8 + 0.5)
        local bi_v = math.floor(bn_v + (bm_v - bn_v) * a8 + 0.5)
        local a0_w = math.floor(aK_v + (aJ_v - aK_v) * a8 + 0.5)
        local aZ_w = math.floor(bg_v + (bf_v - bg_v) * a8 + 0.5)
        local br_w = math.floor(bj_v + (bi_v - bj_v) * a6 + 0.5)
        local bq_w = math.floor(a0_w + (aZ_w - a0_w) * a6 + 0.5)
        return math.floor(br_w + (bq_w - br_w) * a4 + 0.5)
    else
        local aV = bit.lshift(1, a1)
        local aY = Float32Array(aV)
        for bh = 1, aV do
            local aI = bh - 1
            local aH = 1
            for aL = 1, a1 do
                if aI % 2 == 0 then
                    aH = aH * (1 - ba[aL])
                else
                    aH = aH * ba[aL]
                end
                aI = math.floor(aI / 2)
            end
            aY[bh] = aH
        end

        local bs = Float32Array(aV)
        for aU = 1, aV do
            bs[aU] = pivotValue[a3[aU]]
        end

        local bd = 0
        for aU = 1, aV do
            bd = bd + aY[aU] * bs[aU]
        end
        return math.floor(bd + 0.5)
    end
end

function UtInterpolate.interpolateFloat(mdc, pivotMgr, ret, pivotValue)
    local a1 = pivotMgr:calcPivotValues(mdc, ret)
    local a2 = mdc:getTempPivotTableIndices()
    local a9 = mdc:getTempT()
    pivotMgr:calcPivotIndices(a2, a9, a1)

    if a1 <= 0 then
        return pivotValue[a2[1]]
    elseif a1 == 1 then
        local bj = pivotValue[a2[1]]
        local bi = pivotValue[a2[2]]
        local a8 = a9[1]
        return bj + (bi - bj) * a8
    elseif a1 == 2 then
        local bj = pivotValue[a2[1]]
        local bi = pivotValue[a2[2]]
        local a0_v = pivotValue[a2[3]]
        local aZ_v = pivotValue[a2[4]]
        local a8 = a9[1]
        local a7 = a9[2]
        return (1 - a7) * (bj + (bi - bj) * a8) + a7 * (a0_v + (aZ_v - a0_v) * a8)
    elseif a1 == 3 then
        local aP = pivotValue[a2[1]]
        local aO = pivotValue[a2[2]]
        local bn = pivotValue[a2[3]]
        local bm = pivotValue[a2[4]]
        local aK = pivotValue[a2[5]]
        local aJ = pivotValue[a2[6]]
        local bf = pivotValue[a2[7]]
        local be = pivotValue[a2[8]]
        local a8 = a9[1]
        local a7 = a9[2]
        local a5 = a9[3]
        return (1 - a5) * ((1 - a7) * (aP + (aO - aP) * a8) + a7 * (bn + (bm - bn) * a8)) +
               a5 * ((1 - a7) * (aK + (aJ - aK) * a8) + a7 * (bf + (be - bf) * a8))
    elseif a1 == 4 then
        local aT = pivotValue[a2[1]]
        local aS = pivotValue[a2[2]]
        local bs = pivotValue[a2[3]]
        local br = pivotValue[a2[4]]
        local aN = pivotValue[a2[5]]
        local aM = pivotValue[a2[6]]
        local bl = pivotValue[a2[7]]
        local bk = pivotValue[a2[8]]
        local bd = pivotValue[a2[9]]
        local bb = pivotValue[a2[10]]
        local aX = pivotValue[a2[11]]
        local aW = pivotValue[a2[12]]
        local a6 = pivotValue[a2[13]]
        local a4 = pivotValue[a2[14]]
        local aR = pivotValue[a2[15]]
        local aQ = pivotValue[a2[16]]
        local a8 = a9[1]
        local a7 = a9[2]
        local a5 = a9[3]
        local a3 = a9[4]
        return (1 - a3) * ((1 - a5) * ((1 - a7) * (aT + (aS - aT) * a8) + a7 * (bs + (br - bs) * a8)) +
               a5 * ((1 - a7) * (aN + (aM - aN) * a8) + a7 * (bl + (bk - bl) * a8))) +
               a3 * ((1 - a5) * ((1 - a7) * (bd + (bb - bd) * a8) + a7 * (aX + (aW - aX) * a8)) +
               a5 * ((1 - a7) * (a6 + (a4 - a6) * a8) + a7 * (aR + (aQ - aR) * a8)))
    else
        local aV = bit.lshift(1, a1)
        local aY = Float32Array(aV)
        for bh = 1, aV do
            local aI = bh - 1
            local aH = 1
            for aL = 1, a1 do
                if aI % 2 == 0 then
                    aH = aH * (1 - a9[aL])
                else
                    aH = aH * a9[aL]
                end
                aI = math.floor(aI / 2)
            end
            aY[bh] = aH
        end

        local bq = Float32Array(aV)
        for aU = 1, aV do
            bq[aU] = pivotValue[a2[aU]]
        end

        local bc = 0
        for aU = 1, aV do
            bc = bc + aY[aU] * bq[aU]
        end
        return bc
    end
end

function UtInterpolate.interpolatePoints(mdc, pivotMgr, retParamOut, numPts, pivotPoints, dstPoints, ptOffset, ptStep)
    local aN = pivotMgr:calcPivotValues(mdc, retParamOut)
    local bw = mdc:getTempPivotTableIndices()
    local a2 = mdc:getTempT()
    pivotMgr:calcPivotIndices(bw, a2, aN)

    local aJ = numPts * 2
    local aQ = ptOffset

    if aN <= 0 then
        local bI = bw[1]
        local bq = pivotPoints[bI]
        if ptStep == 2 and ptOffset == 0 then
            UtSystem.arraycopy(bq, 0, dstPoints, 0, aJ)
        else
            local bt = 1
            while bt <= aJ do
                dstPoints[aQ + 1] = bq[bt]
                bt = bt + 1
                dstPoints[aQ + 2] = bq[bt]
                bt = bt + 1
                aQ = aQ + ptStep
            end
        end
    elseif aN == 1 then
        local bq = pivotPoints[bw[1]]
        local bp = pivotPoints[bw[2]]
        local b3 = a2[1]
        local bT = 1 - b3
        local bt = 1
        aQ = ptOffset
        while bt <= aJ do
            dstPoints[aQ + 1] = bq[bt] * bT + bp[bt] * b3
            bt = bt + 1
            dstPoints[aQ + 2] = bq[bt] * bT + bp[bt] * b3
            bt = bt + 1
            aQ = aQ + ptStep
        end
    elseif aN == 2 then
        local bq = pivotPoints[bw[1]]
        local bp = pivotPoints[bw[2]]
        local aZ = pivotPoints[bw[3]]
        local aY = pivotPoints[bw[4]]
        local b3 = a2[1]
        local b1 = a2[2]
        local bT = 1 - b3
        local bP = 1 - b1
        local b2 = bP * bT
        local b0 = bP * b3
        local bM = b1 * bT
        local bL = b1 * b3
        local bt = 1
        aQ = ptOffset
        while bt <= aJ do
            dstPoints[aQ + 1] = b2 * bq[bt] + b0 * bp[bt] + bM * aZ[bt] + bL * aY[bt]
            bt = bt + 1
            dstPoints[aQ + 2] = b2 * bq[bt] + b0 * bp[bt] + bM * aZ[bt] + bL * aY[bt]
            bt = bt + 1
            aQ = aQ + ptStep
        end
    elseif aN == 3 then
        local ba = pivotPoints[bw[1]]
        local a9 = pivotPoints[bw[2]]
        local aP = pivotPoints[bw[3]]
        local aO = pivotPoints[bw[4]]
        local a6 = pivotPoints[bw[5]]
        local a4 = pivotPoints[bw[6]]
        local aL = pivotPoints[bw[7]]
        local aK = pivotPoints[bw[8]]
        local b3 = a2[1]
        local b1 = a2[2]
        local bZ = a2[3]
        local bT = 1 - b3
        local bP = 1 - b1
        local bN = 1 - bZ
        local b8 = bN * bP * bT
        local b7 = bN * bP * b3
        local bU = bN * b1 * bT
        local bS = bN * b1 * b3
        local b6 = bZ * bP * bT
        local b5 = bZ * bP * b3
        local bQ = bZ * b1 * bT
        local bO = bZ * b1 * b3
        local bt = 1
        aQ = ptOffset
        while bt <= aJ do
            dstPoints[aQ + 1] = b8 * ba[bt] + b7 * a9[bt] + bU * aP[bt] + bS * aO[bt] +
                               b6 * a6[bt] + b5 * a4[bt] + bQ * aL[bt] + bO * aK[bt]
            bt = bt + 1
            dstPoints[aQ + 2] = b8 * ba[bt] + b7 * a9[bt] + bU * aP[bt] + bS * aO[bt] +
                               b6 * a6[bt] + b5 * a4[bt] + bQ * aL[bt] + bO * aK[bt]
            bt = bt + 1
            aQ = aQ + ptStep
        end
    elseif aN == 4 then
        local bD = pivotPoints[bw[1]]
        local bB = pivotPoints[bw[2]]
        local bo = pivotPoints[bw[3]]
        local bm = pivotPoints[bw[4]]
        local by_ = pivotPoints[bw[5]]
        local bx = pivotPoints[bw[6]]
        local be = pivotPoints[bw[7]]
        local bd = pivotPoints[bw[8]]
        local bG = pivotPoints[bw[9]]
        local bE = pivotPoints[bw[10]]
        local bv = pivotPoints[bw[11]]
        local bu = pivotPoints[bw[12]]
        local bA = pivotPoints[bw[13]]
        local bz = pivotPoints[bw[14]]
        local bn = pivotPoints[bw[15]]
        local bl = pivotPoints[bw[16]]
        local b3 = a2[1]
        local b1 = a2[2]
        local bZ = a2[3]
        local bY = a2[4]
        local bT = 1 - b3
        local bP = 1 - b1
        local bN = 1 - bZ
        local bK = 1 - bY
        local bk = bK * bN * bP * bT
        local bi = bK * bN * bP * b3
        local aW = bK * bN * b1 * bT
        local aV = bK * bN * b1 * b3
        local bc = bK * bZ * bP * bT
        local bb = bK * bZ * bP * b3
        local aS = bK * bZ * b1 * bT
        local aR = bK * bZ * b1 * b3
        local bs = bY * bN * bP * bT
        local br = bY * bN * bP * b3
        local a1 = bY * bN * b1 * bT
        local a0 = bY * bN * b1 * b3
        local bh = bY * bZ * bP * bT
        local bf = bY * bZ * bP * b3
        local aU = bY * bZ * b1 * bT
        local aT = bY * bZ * b1 * b3
        local bt = 1
        aQ = ptOffset
        while bt <= aJ do
            dstPoints[aQ + 1] = bk * bD[bt] + bi * bB[bt] + aW * bo[bt] + aV * bm[bt] +
                               bc * by_[bt] + bb * bx[bt] + aS * be[bt] + aR * bd[bt] +
                               bs * bG[bt] + br * bE[bt] + a1 * bv[bt] + a0 * bu[bt] +
                               bh * bA[bt] + bf * bz[bt] + aU * bn[bt] + aT * bl[bt]
            bt = bt + 1
            dstPoints[aQ + 2] = bk * bD[bt] + bi * bB[bt] + aW * bo[bt] + aV * bm[bt] +
                               bc * by_[bt] + bb * bx[bt] + aS * be[bt] + aR * bd[bt] +
                               bs * bG[bt] + br * bE[bt] + a1 * bv[bt] + a0 * bu[bt] +
                               bh * bA[bt] + bf * bz[bt] + aU * bn[bt] + aT * bl[bt]
            bt = bt + 1
            aQ = aQ + ptStep
        end
    else
        local b4 = bit.lshift(1, aN)
        local bJ = Float32Array(b4)
        for bj = 1, b4 do
            local aH = bj - 1
            local aM = 1
            for bF = 1, aN do
                if aH % 2 == 0 then
                    aM = aM * (1 - a2[bF])
                else
                    aM = aM * a2[bF]
                end
                aH = math.floor(aH / 2)
            end
            bJ[bj] = aM
        end

        local bg = {}
        for aX = 1, b4 do
            bg[aX] = pivotPoints[bw[aX]]
        end

        local bt = 1
        aQ = ptOffset
        while bt <= aJ do
            local a8 = 0
            local a7 = 0
            local bR = bt + 1
            for aX = 1, b4 do
                a8 = a8 + bJ[aX] * bg[aX][bt]
                a7 = a7 + bJ[aX] * bg[aX][bR]
            end
            bt = bt + 2
            dstPoints[aQ + 1] = a8
            dstPoints[aQ + 2] = a7
            aQ = aQ + ptStep
        end
    end
end

return UtInterpolate
