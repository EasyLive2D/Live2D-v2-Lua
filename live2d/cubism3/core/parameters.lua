-- Parameter utilities for Cubism 3
-- Ported from Mocari src/core/parameters.rs

local parameters = {}

local REPEAT_Q_THRESHOLD = 8388608

function parameters.clamp_parameter_value(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function parameters.core_repeat_fold(value, minimum, repeat_step)
    if repeat_step == 0 then
        return minimum
    end
    local q = (value - minimum) / repeat_step
    local n = math.floor(q)
    if math.abs(q) < REPEAT_Q_THRESHOLD and n > q then
        n = n - 1
    end
    return (q - n) * repeat_step + minimum
end

function parameters.parameter_dirty(old_cached, new_value)
    return old_cached ~= new_value
end

return parameters
