local UtSystem = require("live2d.core.util.ut_system")
local UtMotion = require("live2d.core.util.ut_motion")

local AMotion = {}
AMotion.__index = AMotion

function AMotion.new()
    local self = setmetatable({}, AMotion)
    self.fadeInMSec = 1000
    self.fadeOutMSec = 1000
    self.weight = 1
    return self
end

function AMotion:setFadeIn(aH)
    self.fadeInMSec = aH
end

function AMotion:setFadeOut(aH)
    self.fadeOutMSec = aH
end

function AMotion:setWeight(aH)
    self.weight = aH
end

function AMotion:getFadeOut()
    return self.fadeOutMSec
end

function AMotion:getWeight()
    return self.weight
end

function AMotion:getDurationMSec()
    return -1
end

function AMotion:getLoopDurationMSec()
    return -1
end

function AMotion:updateParam(aJ, aN)
    if not aN.available or aN.finished then
        return
    end
    local aL = UtSystem.getUserTimeMSec()
    if aN.startTimeMSec < 0 then
        aN.startTimeMSec = aL
        aN.fadeInStartTimeMSec = aL
        local aM = self:getDurationMSec()
        if aN.endTimeMSec < 0 then
            if aM <= 0 then
                aN.endTimeMSec = -1
            else
                aN.endTimeMSec = aN.startTimeMSec + aM
            end
        end
    end
    local aI = self.weight
    local aH
    if self.fadeInMSec == 0 then
        aH = 1
    else
        aH = UtMotion.getEasingSine((aL - aN.fadeInStartTimeMSec) / self.fadeInMSec)
    end
    local aK
    if self.fadeOutMSec == 0 or aN.endTimeMSec < 0 then
        aK = 1
    else
        aK = UtMotion.getEasingSine((aN.endTimeMSec - aL) / self.fadeOutMSec)
    end
    aI = aI * aH * aK
    if not (0 <= aI and aI <= 1) then
        print("### assert!! ###")
    end
    self:updateParamExe(aJ, aL, aI, aN)
    if aN.endTimeMSec > 0 and aN.endTimeMSec < aL then
        aN.finished = true
    end
end

function AMotion:updateParamExe(aH, aI, aJ, aK)
    error("abstract method: updateParamExe() not implemented")
end

function AMotion.getEasing(t, totalTime, accelerateTime)
    local aQ = t / totalTime
    local a1 = accelerateTime / totalTime
    local aU = a1
    local aZ = 1 / 3
    local aR = 2 / 3
    local a0 = 1 - (1 - a1) * (1 - a1)
    local a2 = 1 - (1 - aU) * (1 - aU)
    local aM = 0
    local aL = ((1 - a1) * aZ) * a0 + (aU * aR + (1 - aU) * aZ) * (1 - a0)
    local aK = (aU + (1 - aU) * aR) * a2 + (a1 * aZ + (1 - a1) * aR) * (1 - a2)
    local aJ = 1
    local aY = aJ - 3 * aK + 3 * aL - aM
    local aX = 3 * aK - 6 * aL + 3 * aM
    local aW = 3 * aL - 3 * aM
    local aV = aM
    if aQ <= 0 then return 0 end
    if aQ >= 1 then return 1 end
    local aS = aQ
    local aI = aS * aS
    local aH = aS * aI
    return aY * aH + aX * aI + aW * aS + aV
end

return AMotion
