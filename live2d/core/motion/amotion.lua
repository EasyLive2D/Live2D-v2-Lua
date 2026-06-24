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

function AMotion:setFadeIn(fadeInMSec)
    self.fadeInMSec = fadeInMSec
end

function AMotion:setFadeOut(fadeOutMSec)
    self.fadeOutMSec = fadeOutMSec
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

function AMotion:updateParam(model, motionQueueEntry)
    if not motionQueueEntry.available or motionQueueEntry.finished then
        return
    end
    local currentTimeMSec = UtSystem.getUserTimeMSec()
    if motionQueueEntry.startTimeMSec < 0 then
        motionQueueEntry.startTimeMSec = currentTimeMSec
        motionQueueEntry.fadeInStartTimeMSec = currentTimeMSec
        local durationMSec = self:getDurationMSec()
        if motionQueueEntry.endTimeMSec < 0 then
            if durationMSec <= 0 then
                motionQueueEntry.endTimeMSec = -1
            else
                motionQueueEntry.endTimeMSec = motionQueueEntry.startTimeMSec + durationMSec
            end
        end
    end
    local accumulatedWeight = self.weight
    local fadeInWeight
    if self.fadeInMSec == 0 then
        fadeInWeight = 1
    else
        fadeInWeight = UtMotion.getEasingSine((currentTimeMSec - motionQueueEntry.fadeInStartTimeMSec) / self.fadeInMSec)
    end
    local fadeOutWeight
    if self.fadeOutMSec == 0 or motionQueueEntry.endTimeMSec < 0 then
        fadeOutWeight = 1
    else
        fadeOutWeight = UtMotion.getEasingSine((motionQueueEntry.endTimeMSec - currentTimeMSec) / self.fadeOutMSec)
    end
    accumulatedWeight = accumulatedWeight * fadeInWeight * fadeOutWeight
    if not (0 <= accumulatedWeight and accumulatedWeight <= 1) then
        print("### assert!! ###")
    end
    self:updateParamExe(model, currentTimeMSec, accumulatedWeight, motionQueueEntry)
    if motionQueueEntry.endTimeMSec > 0 and motionQueueEntry.endTimeMSec < currentTimeMSec then
        motionQueueEntry.finished = true
    end
end

function AMotion:updateParamExe(model, currentTimeMSec, weight, motionQueueEntry)
    error("abstract method: updateParamExe() not implemented")
end

return AMotion
