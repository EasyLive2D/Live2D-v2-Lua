-- Keyform runtime computation for Cubism 3
-- Ported from Mocari src/core/keyforms.rs

local bit = require("bit")

local keyforms = {}

-- KeyformAxisInterval
function keyforms.new_keyform_axis_interval(left_index, t)
    return { left_index = left_index, t = t }
end

-- KeyformAxis
function keyforms.new_keyform_axis(left_index, t, stride)
    return { left_index = left_index, t = t, stride = stride }
end

-- KeyformRuntimeSlot
function keyforms.new_keyform_runtime_slot(flat_index, weight)
    return { flat_index = flat_index, weight = weight }
end

function keyforms.compute_keyform_axis_interval(keys, value)
    if #keys == 0 then
        return nil
    end
    local first = keys[1]
    if value <= first then
        return keyforms.new_keyform_axis_interval(0, 0)
    end
    local last_index = #keys - 1
    if value >= keys[#keys] then
        return keyforms.new_keyform_axis_interval(last_index, 0)
    end
    for i = 0, last_index - 1 do
        local left = keys[i + 1]
        local right = keys[i + 2]
        if left <= value and value <= right then
            return keyforms.new_keyform_axis_interval(i, (value - left) / (right - left))
        end
    end
    return keyforms.new_keyform_axis_interval(last_index, 0)
end

function keyforms.expand_keyform_runtime_slots(axes)
    local active_count = 0
    for _, axis in ipairs(axes) do
        if axis.t ~= 0 then
            active_count = active_count + 1
        end
    end
    local slot_count = 1
    for _ = 1, active_count do
        slot_count = slot_count * 2
    end
    local slots = {}
    for mask = 0, slot_count - 1 do
        local flat_index = 0
        local weight = 1
        local bit_pos = 0
        for _, axis in ipairs(axes) do
            if axis.t == 0 then
                flat_index = flat_index + axis.left_index * axis.stride
            else
                local use_right = (bit.rshift(mask, bit_pos) % 2) ~= 0
                bit_pos = bit_pos + 1
                if use_right then
                    flat_index = flat_index + (axis.left_index + 1) * axis.stride
                    weight = weight * axis.t
                else
                    flat_index = flat_index + axis.left_index * axis.stride
                    weight = weight * (1 - axis.t)
                end
            end
        end
        table.insert(slots, keyforms.new_keyform_runtime_slot(flat_index, weight))
    end
    return slots
end

return keyforms
