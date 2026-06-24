package.path = package.path .. ";./?.lua;./?/init.lua"

local MotionQueueManager = require("live2d.core.motion.motion_queue_manager")

local passed = 0
local total = 0

local function check(name, ok, msg)
    total = total + 1
    if ok then
        passed = passed + 1
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name .. ": " .. (msg or "unknown"))
    end
end

local function new_motion(finish_on_update)
    return {
        updates = 0,
        fade_outs = 0,
        getFadeOut = function()
            return 100
        end,
        updateParam = function(self, _model, entry)
            self.updates = self.updates + 1
            if finish_on_update then
                entry.finished = true
            end
        end,
    }
end

local original_remove = table.remove
table.remove = function()
    error("table.remove should not be used in motion queue hot paths", 2)
end

local ok, err = pcall(function()
    local manager = MotionQueueManager.new()
    local active = new_motion(false)
    local finished = new_motion(true)

    manager:startMotion(active)
    manager:startMotion(finished)
    manager.motions[#manager.motions + 1] = nil

    check("updateParam returns true when motions update", manager:updateParam({}) == true)
    check("active motion was updated", active.updates == 1)
    check("finished motion was updated", finished.updates == 1)
    check("finished motion compacted", #manager.motions == 1)
    check("remaining motion is active", manager.motions[1].motion == active)
    check("queue reports unfinished active motion", manager:isFinished() == false)

    manager:stopAllMotions()
    check("stopAllMotions clears queue", #manager.motions == 0)
    check("empty queue is finished", manager:isFinished() == true)
end)

table.remove = original_remove

if not ok then
    check("motion queue avoids table.remove", false, err)
end

print(string.format("\n%d/%d tests passed", passed, total))
if passed ~= total then
    os.exit(1)
end
