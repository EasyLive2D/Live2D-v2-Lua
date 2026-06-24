local MotionQueueEntry = require("live2d.core.motion.motion_queue_entry")

local MotionQueueManager = {}
MotionQueueManager.__index = MotionQueueManager

local function compactMotions(motions, update_model)
    local write = 1
    local updated = false
    for read = 1, #motions do
        local ent = motions[read]
        local keep = false
        if ent ~= nil then
            local mtn = ent.motion
            if mtn ~= nil then
                if update_model ~= nil then
                    mtn:updateParam(update_model, ent)
                    updated = true
                end
                keep = not ent:isFinished()
            end
        end
        if keep then
            motions[write] = ent
            write = write + 1
        end
    end
    for i = write, #motions do
        motions[i] = nil
    end
    return updated
end

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
    return compactMotions(self.motions, aJ)
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
        compactMotions(self.motions)
        for i = 1, #self.motions do
            local ent = self.motions[i]
            if ent ~= nil and not ent:isFinished() then
                return false
            end
        end
        return true
    end
end

function MotionQueueManager:stopAllMotions()
    self.motions = {}
end

return MotionQueueManager
