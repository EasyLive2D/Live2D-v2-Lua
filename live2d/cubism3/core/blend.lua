-- Blend utilities for Cubism 3
-- Ported from Mocari src/core/blend.rs

local blend = {}

-- Rgb
function blend.Rgb(r, g, b)
    return { r = r or 0, g = g or 0, b = b or 0 }
end

-- BlendSlot enum
blend.BLEND_SKIP = "skip"
blend.BLEND_SINGLE = "single"
blend.BLEND_PAIR = "pair"

function blend.new_blend_slot_skip()
    return { kind = blend.BLEND_SKIP }
end

function blend.new_blend_slot_single(base, index, weight, final_weight)
    return {
        kind = blend.BLEND_SINGLE,
        base = base,
        index = index,
        weight = weight,
        final_weight = final_weight,
    }
end

function blend.new_blend_slot_pair(base, index0, weight0, index1, weight1, final_weight)
    return {
        kind = blend.BLEND_PAIR,
        base = base,
        index0 = index0,
        weight0 = weight0,
        index1 = index1,
        weight1 = weight1,
        final_weight = final_weight,
    }
end

function blend.blend_scalar_slots(slots, source_values, initial)
    local out = initial
    for _, slot in ipairs(slots) do
        if slot.kind == blend.BLEND_SKIP then
            -- nothing
        elseif slot.kind == blend.BLEND_SINGLE then
            local idx = slot.base + slot.index + 1
            local value = source_values[idx]
            if value then
                out = out + value * slot.weight * slot.final_weight
            end
        elseif slot.kind == blend.BLEND_PAIR then
            local idx0 = slot.base + slot.index0 + 1
            local idx1 = slot.base + slot.index1 + 1
            local value0 = source_values[idx0]
            local value1 = source_values[idx1]
            if value0 and value1 then
                out = out + (value0 * slot.weight0 + value1 * slot.weight1) * slot.final_weight
            end
        end
    end
    return out
end

function blend.blend_scalar_slots_clamped(slots, source_values, initial, minimum, maximum)
    local result = blend.blend_scalar_slots(slots, source_values, initial)
    if result == nil then
        return nil
    end
    return math.max(minimum, math.min(maximum, result))
end

function blend.multiply_rgb(local_c, parent_c)
    return blend.Rgb(local_c.r * parent_c.r, local_c.g * parent_c.g, local_c.b * parent_c.b)
end

local function clamp01(value)
    return math.max(0, math.min(1, value))
end

function blend.screen_rgb(local_c, parent_c)
    return blend.Rgb(
        clamp01(local_c.r + parent_c.r - local_c.r * parent_c.r),
        clamp01(local_c.g + parent_c.g - local_c.g * parent_c.g),
        clamp01(local_c.b + parent_c.b - local_c.b * parent_c.b)
    )
end

return blend
