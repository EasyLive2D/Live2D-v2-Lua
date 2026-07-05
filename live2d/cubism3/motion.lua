-- MotionPlayer for Cubism 3
-- Ported from Mocari src/motion.rs

local motion3 = require("live2d.cubism3.json.motion3")

local MotionPlayer = {}
MotionPlayer.__index = MotionPlayer

function MotionPlayer.new(motion, loop)
    return setmetatable({
        motion = motion,
        time = 0.0,
        weight = 1.0,
        loop = loop,
        finished = false,
    }, MotionPlayer)
end

function MotionPlayer:set_weight(weight)
    self.weight = math.max(0, math.min(1, weight))
end

function MotionPlayer:is_finished()
    return self.finished
end

function MotionPlayer:restart()
    self.time = 0.0
    self.finished = false
end

function MotionPlayer:should_loop()
    if self.loop ~= nil then return self.loop end
    return self.motion.meta.Loop
end

function MotionPlayer:tick(delta_seconds)
    if self.finished then
        return
    end

    self.time = self.time + math.max(0, delta_seconds)
    local duration = (self.motion.meta.Duration or 0)
    if duration <= 0 then
        return
    end

    if self:should_loop() then
        self.time = self.time % duration
    elseif self.time >= duration then
        self.time = duration
        self.finished = true
    end
end

function MotionPlayer:apply(runtime)
    local duration = self.motion.meta.Duration or 0
    local end_time = self:should_loop() and -1.0 or duration
    local fade_in_seconds = tonumber(self.motion.meta.FadeInTime) or 0
    local fade_out_seconds = tonumber(self.motion.meta.FadeOutTime) or 0
    if fade_in_seconds < 0 then fade_in_seconds = 0 end
    if fade_out_seconds < 0 then fade_out_seconds = 0 end
    local fade_in = motion3.motion_fade_in_weight(self.time, 0, fade_in_seconds)
    local fade_out = motion3.motion_fade_out_weight(self.time, end_time, fade_out_seconds)

    for _, curve in ipairs(self.motion.curves) do
        local sampled = curve:sample(self.time)
        if sampled == nil then
            -- skip
        else
            local curve_weight = motion3.parameter_curve_fade_weight(
                self.weight, fade_in, fade_out,
                curve.fade_in_time, curve.fade_out_time,
                self.time, 0, end_time
            )

            if curve.target == "Parameter" then
                local index = runtime:parameter_index_of(curve.id)
                if index ~= nil then
                    local current = runtime:parameter_value_by_index(index) or 0
                    local value = motion3.apply_motion_fade(current, sampled, curve_weight)
                    runtime:set_parameter_by_index(index, value)
                end
            elseif curve.target == "PartOpacity" then
                local index = runtime:part_index_of(curve.id)
                if index ~= nil then
                    local value = motion3.apply_motion_fade(1.0, sampled, curve_weight)
                    runtime:set_part_opacity_by_index(index, value)
                end
            end
        end
    end
end

return MotionPlayer
