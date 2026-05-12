local MotionQueueManager = require("live2d.core.motion.motion_queue_manager")

local L2DMotionManager = setmetatable({}, { __index = MotionQueueManager })
L2DMotionManager.__index = L2DMotionManager

function L2DMotionManager.new()
    local self = setmetatable(MotionQueueManager.new(), L2DMotionManager)
    self.currentPriority = 0
    self.reservePriority = 0
    return self
end

function L2DMotionManager:getCurrentPriority() return self.currentPriority end
function L2DMotionManager:getReservePriority() return self.reservePriority end

function L2DMotionManager:reserveMotion(priority)
    if self.reservePriority >= priority then return false end
    if self.currentPriority >= priority then return false end
    self.reservePriority = priority
    return true
end

function L2DMotionManager:setReservePriority(val)
    self.reservePriority = val
end

function L2DMotionManager:updateParam(model)
    local updated = MotionQueueManager.updateParam(self, model)
    if self:isFinished() then
        self.currentPriority = 0
    end
    return updated
end

function L2DMotionManager:startMotionPrio(motion, priority)
    if priority == self.reservePriority then
        self.reservePriority = 0
    end
    self.currentPriority = priority
    return self:startMotion(motion, false)
end

return L2DMotionManager
