local Motion = require("live2d.core.motion.motion")
local AMotion = require("live2d.core.motion.amotion")
local UtString = require("live2d.core.util.ut_string")

local Live2DMotion = setmetatable({}, { __index = AMotion })
Live2DMotion.__index = Live2DMotion

Live2DMotion.MTN_PREFIX_VISIBLE = "VISIBLE:"
Live2DMotion.MTN_PREFIX_LAYOUT = "LAYOUT:"
Live2DMotion.MTN_PREFIX_FADE_IN = "FADEIN:"
Live2DMotion.MTN_PREFIX_FADE_OUT = "FADEOUT:"

function Live2DMotion.new()
    local self = setmetatable(AMotion.new(), Live2DMotion)
    self.motions = {}
    self.srcFps = 30
    self.maxLength = 0
    self.loop = false
    self.loopFadeIn = true
    self.loopDurationMSec = -1
    self.lastWeight = 0
    return self
end

function Live2DMotion:getDurationMSec()
    if self.loop then return -1 end
    return self.loopDurationMSec
end

function Live2DMotion:getLoopDurationMSec()
    return self.loopDurationMSec
end

function Live2DMotion:updateParamExe(aJ, aN, aQ, a3)
    local aO = aN - a3.startTimeMSec
    local a0 = aO * self.srcFps / 1000
    local aK = math.floor(a0)
    local aR = a0 - aK

    for aZ = 1, #self.motions do
        local aV = self.motions[aZ]
        local aL = #aV.values
        local aT = aV.paramIdStr
        if aV.mtnType == Motion.MOTION_TYPE_PARTS_VISIBLE then
            local idx = aK >= aL and aL or (aK + 1)
            local aX = aV.values[idx]
            aJ:setParamFloat(aT, aX)
        else
            if Motion.MOTION_TYPE_LAYOUT_X <= aV.mtnType and aV.mtnType <= Motion.MOTION_TYPE_LAYOUT_SCALE_Y then
                -- pass
            else
                local aH = aJ:getParamIndex(aT)
                local a4 = aJ:getModelContext()
                local aY = a4:getParamMax(aH)
                local aW = a4:getParamMin(aH)
                local aM = 0.4
                local aS = aM * (aY - aW)
                local aU = a4:getParamFloat(aH)
                local idx1 = aK >= aL and aL or (aK + 1)
                local idx2 = aK + 1 >= aL and aL or (aK + 2)
                local a2 = aV.values[idx1]
                local a1 = aV.values[idx2]
                local aI
                if (a2 < a1 and a1 - a2 > aS) or (a2 > a1 and a2 - a1 > aS) then
                    aI = a2
                else
                    aI = a2 + (a1 - a2) * aR
                end
                local aP = aU + (aI - aU) * aQ
                aJ:setParamFloat(aT, aP)
            end
        end
    end

    if aK >= self.maxLength then
        if self.loop then
            a3.startTimeMSec = aN
            if self.loopFadeIn then
                a3.fadeInStartTimeMSec = aN
            end
        else
            a3.finished = true
        end
    end
    self.lastWeight = aQ
end

function Live2DMotion:isLoop()
    return self.loop
end

function Live2DMotion:setLoop(aH)
    self.loop = aH
end

function Live2DMotion:isLoopFadeIn()
    return self.loopFadeIn
end

function Live2DMotion:setLoopFadeIn(value)
    self.loopFadeIn = value
end

function Live2DMotion.loadMotion(aT)
    local mtn = Live2DMotion.new()
    local aI = {0}
    local aQ = #aT
    mtn.maxLength = 0
    local aJ = 0
    while aJ < aQ do
        local aL = aT:byte(aJ + 1)
        local aS = string.char(aL)
        if aS == "\n" or aS == "\r" then
            aJ = aJ + 1
        elseif aS == "#" then
            while aJ < aQ do
                local c = aT:sub(aJ + 1, aJ + 1)
                if c == "\n" or c == "\r" then break end
                aJ = aJ + 1
            end
            aJ = aJ + 1
        elseif aS == "" then
            local aV = aJ
            while aJ < aQ do
                local c = aT:sub(aJ + 1, aJ + 1)
                if c == "\r" or c == "\n" then break end
                if c == "=" then break end
                aJ = aJ + 1
            end
            while aJ < aQ do
                local c = aT:sub(aJ + 1, aJ + 1)
                if c == "\n" or c == "\r" then break end
                aJ = aJ + 1
            end
            aJ = aJ + 1
        else
            local isAlpha = (97 <= aL and aL <= 122) or (65 <= aL and aL <= 90) or aS == "_"
            if isAlpha then
                local aV = aJ
                local aK = -1
                while aJ < aQ do
                    local c = aT:sub(aJ + 1, aJ + 1)
                    if c == "\r" or c == "\n" then break end
                    if c == "=" then
                        aK = aJ
                        break
                    end
                    aJ = aJ + 1
                end

                if aK >= 0 then
                    local aO = Motion.new()
                    if UtString.startsWith(aT, aV, Live2DMotion.MTN_PREFIX_VISIBLE) then
                        aO.mtnType = Motion.MOTION_TYPE_PARTS_VISIBLE
                        aO.paramIdStr = UtString.createString(aT, aV, aK - aV)
                    elseif UtString.startsWith(aT, aV, Live2DMotion.MTN_PREFIX_LAYOUT) then
                        aO.paramIdStr = UtString.createString(aT, aV + 7, aK - aV - 7)
                        if UtString.startsWith(aT, aV + 7, "ANCHOR_X") then
                            aO.mtnType = Motion.MOTION_TYPE_LAYOUT_ANCHOR_X
                        elseif UtString.startsWith(aT, aV + 7, "ANCHOR_Y") then
                            aO.mtnType = Motion.MOTION_TYPE_LAYOUT_ANCHOR_Y
                        elseif UtString.startsWith(aT, aV + 7, "SCALE_X") then
                            aO.mtnType = Motion.MOTION_TYPE_LAYOUT_SCALE_X
                        elseif UtString.startsWith(aT, aV + 7, "SCALE_Y") then
                            aO.mtnType = Motion.MOTION_TYPE_LAYOUT_SCALE_Y
                        elseif UtString.startsWith(aT, aV + 7, "Y") then
                            aO.mtnType = Motion.MOTION_TYPE_LAYOUT_Y
                        else
                            aO.mtnType = Motion.MOTION_TYPE_LAYOUT_X
                        end
                    else
                        aO.mtnType = Motion.MOTION_TYPE_PARAM
                        aO.paramIdStr = UtString.createString(aT, aV, aK - aV)
                    end

                    mtn.motions[#mtn.motions + 1] = aO
                    local aU = 0
                    local aR = {}
                    aJ = aK + 1
                    while aJ < aQ do
                        local c = aT:sub(aJ + 1, aJ + 1)
                        if c == "\r" or c == "\n" then break end
                        if c == "," or c == " " or c == "\t" then
                            aJ = aJ + 1
                        else
                            local aM = UtString.strToFloat(aT, aQ, aJ, aI)
                            if aI[1] > 0 then
                                aR[#aR + 1] = aM
                                aU = aU + 1
                                local aH = aI[1]
                                if aH < aJ then
                                    print("invalid state during loadMotion")
                                    break
                                end
                                aJ = aH - 1
                            end
                            aJ = aJ + 1
                        end
                    end
                    aO.values = aR
                    if aU > mtn.maxLength then
                        mtn.maxLength = aU
                    end
                end
            end
            aJ = aJ + 1
        end
    end

    mtn.loopDurationMSec = math.floor((1000 * mtn.maxLength) / mtn.srcFps)
    return mtn
end

return Live2DMotion
