local def = require("live2d.core.def")
local ISerializable = require("live2d.core.io.iserializable")
local ParamPivots = require("live2d.core.param.param_pivots")

local PivotManager = setmetatable({}, { __index = ISerializable })
PivotManager.__index = PivotManager

function PivotManager.new()
    local self = setmetatable(ISerializable.new(), PivotManager)
    self.paramPivotTable = nil
    return self
end

function PivotManager:read(aH)
    self.paramPivotTable = aH:readObject()
end

function PivotManager:checkParamUpdated(aK)
    if aK:requireSetup() then
        return true
    end

    local aH = aK:getInitVersion()
    local tableLen = #self.paramPivotTable
    for aJ = tableLen, 1, -1 do
        local aI = self.paramPivotTable[aJ]:getParamIndex(aH)
        if aI == ParamPivots.PARAM_INDEX_NOT_INIT then
            aI = aK:getParamIndex(self.paramPivotTable[aJ]:getParamID())
        end
        if aK:isParamUpdated(aI) then
            return true
        end
    end
    return false
end

function PivotManager:calcPivotValues(mdc, ret)
    local aX = #self.paramPivotTable
    local aJ = mdc:getInitVersion()
    local aN = 0
    for aK = 1, aX do
        local aH = self.paramPivotTable[aK]
        local aI = aH:getParamIndex(aJ)
        if aI == ParamPivots.PARAM_INDEX_NOT_INIT then
            aI = mdc:getParamIndex(aH:getParamID())
            aH:setParamIndex(aI, aJ)
        end
        if aI < 0 then
            error("err 23242 : " .. tostring(aH:getParamID()))
        end
        local aU = mdc:getParamFloat(aI)
        if aI < 0 then aU = 0 end
        local aQ = aH:getPivotCount()
        local aM = aH:getPivotValues()
        local aP = -1
        local aT = 0
        if aQ >= 1 then
            if aQ == 1 then
                local aS = aM[1]
                if aS - def.GOSA < aU and aU < aS + def.GOSA then
                    aP = 0
                    aT = 0
                else
                    aP = 0
                    ret[1] = true
                end
            else
                local aS = aM[1]
                if aU < aS - def.GOSA then
                    aP = 0
                    ret[1] = true
                else
                    if aU < aS + def.GOSA then
                        aP = 0
                    else
                        local aW = false
                        for aO = 2, aQ do
                            local aR = aM[aO]
                            if aU < aR + def.GOSA then
                                if aR - def.GOSA < aU then
                                    aP = aO - 1
                                else
                                    aP = aO - 2
                                    aT = (aU - aS) / (aR - aS)
                                    aN = aN + 1
                                end
                                aW = true
                                break
                            end
                            aS = aR
                        end
                        if not aW then
                            aP = aQ - 1
                            aT = 0
                            ret[1] = true
                        end
                    end
                end
            end
        end
        aH:setTmpPivotIndex(aP)
        aH:setTmpT(aT)
    end
    return aN
end

function PivotManager:calcPivotIndices(aN, aT, aP)
    local aR = bit.lshift(1, aP)
    if aR + 1 > def.PIVOT_TABLE_SIZE then
        print("err 23245")
    end

    local aS = #self.paramPivotTable
    local aK = 1
    local aH = 1
    local aJ = 1
    for aQ = 1, aR do
        aN[aQ] = 0
    end

    for aL = 1, aS do
        local aI = self.paramPivotTable[aL]
        if aI:getTmpT() == 0 then
            local aO = aI:getTmpPivotIndex() * aK
            if aO < 0 then
                error("err 23246")
            end
            for aQ = 1, aR do
                aN[aQ] = aN[aQ] + aO
            end
        else
            local aO = aK * aI:getTmpPivotIndex()
            local aM = aK * (aI:getTmpPivotIndex() + 1)
            for aQ = 1, aR do
                if math.floor((aQ - 1) / aH) % 2 == 0 then
                    aN[aQ] = aN[aQ] + aO
                else
                    aN[aQ] = aN[aQ] + aM
                end
            end
            aT[aJ] = aI:getTmpT()
            aJ = aJ + 1
            aH = aH * 2
        end
        aK = aK * aI:getPivotCount()
    end

    aN[aR + 1] = 65536
    aT[aJ] = -1

    -- Convert indices from 0-based (C/Python) to 1-based (Lua)
    for aQ = 1, aR do
        aN[aQ] = aN[aQ] + 1
    end
end

function PivotManager:getParamCount()
    return #self.paramPivotTable
end

return PivotManager
