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

function AMotion:getFadeOut()
    return self.fadeOutMSec
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

return AMotion
