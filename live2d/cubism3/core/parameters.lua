-- Parameter utilities for Cubism 3
-- Ported from Mocari src/core/parameters.rs

local parameters = {}

function parameters.clamp_parameter_value(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

return parameters
