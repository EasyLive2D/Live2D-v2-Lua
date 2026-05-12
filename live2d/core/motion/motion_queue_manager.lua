local MotionQueueEntry = require("live2d.core.motion.motion_queue_entry")

local MotionQueueManager = {}
MotionQueueManager.__index = MotionQueueManager

function MotionQueueManager.new()
    local self = setmetatable({}, MotionQueueManager)
    self.motions = {}
    return self
end

function MotionQueueManager:startMotion(aJ, aI)
    local count = #self.motions
    for i = 1, count do
        local ent = self.motions[i]
        if ent ~= nil and ent.motion ~= nil then
            ent:startFadeOut(ent.motion:getFadeOut())
        end
    end
    if aJ == nil then
        return -1
    end
    local ent = MotionQueueEntry.new()
    ent.motion = aJ
    self.motions[#self.motions + 1] = ent
    return ent.mqNo
end

function MotionQueueManager:updateParam(aJ)
    local updated = false
    local i = 1
    while i <= #self.motions do
        local ent = self.motions[i]
        if ent == nil then
            table.remove(self.motions, i)
        else
            local mtn = ent.motion
            if mtn == nil then
                table.remove(self.motions, i)
            else
                mtn:updateParam(aJ, ent)
                updated = true
                if ent:isFinished() then
                    table.remove(self.motions, i)
                else
                    i = i + 1
                end
            end
        end
    end
    return updated
end

function MotionQueueManager:isFinished(nr)
    if nr ~= nil then
        for i = 1, #self.motions do
            local ent = self.motions[i]
            if ent ~= nil and ent.mqNo == nr and not ent:isFinished() then
                return false
            end
        end
        return true
    else
        local i = 1
        while i <= #self.motions do
            local ent = self.motions[i]
            if ent == nil then
                table.remove(self.motions, i)
            else
                local aH = ent.motion
                if aH == nil then
                    table.remove(self.motions, i)
                elseif not ent:isFinished() then
                    return false
                else
                    i = i + 1
                end
            end
        end
        return true
    end
end

function MotionQueueManager:stopAllMotions()
    local i = 1
    while i <= #self.motions do
        table.remove(self.motions, i)
    end
end

return MotionQueueManager
