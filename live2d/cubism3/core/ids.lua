-- Core ID types for Cubism 3
-- Ported from Mocari src/core/ids.rs

local ids = {}

function ids.new(value)
    if value == nil or value == "" then
        return nil
    end
    return tostring(value)
end

function ids.as_str(id)
    return id
end

return ids
