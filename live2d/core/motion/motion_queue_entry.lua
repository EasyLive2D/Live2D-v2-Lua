local UtSystem = require("live2d.core.util.ut_system")

local MotionQueueEntry = {}
MotionQueueEntry.__index = MotionQueueEntry
MotionQueueEntry.MQ_NO = 0

function MotionQueueEntry.new()
    local self = setmetatable({}, MotionQueueEntry)
    self.motion = nil
    self.available = true
    self.finished = false
    self.startTimeMSec = -1
    self.fadeInStartTimeMSec = -1
    self.endTimeMSec = -1
    self.mqNo = MotionQueueEntry.MQ_NO
    MotionQueueEntry.MQ_NO = MotionQueueEntry.MQ_NO + 1
    return self
end

function MotionQueueEntry:isFinished()
    return self.finished
end

function MotionQueueEntry:startFadeOut(fadeOutMSec)
    local ct = UtSystem.getUserTimeMSec()
    local new_end_time_m_sec = ct + fadeOutMSec
    if self.endTimeMSec < 0 or new_end_time_m_sec < self.endTimeMSec then
        self.endTimeMSec = new_end_time_m_sec
    end
end

return MotionQueueEntry
