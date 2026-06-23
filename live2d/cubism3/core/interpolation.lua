-- Interpolation functions for Cubism 3
-- Ported from Mocari src/core/interpolation.rs

local interpolation = {}

-- InterpolationGroup
function interpolation.new_interpolation_group(index, offset, count, out_index)
    return {
        index = index,
        offset = offset,
        count = count,
        out_index = out_index,
    }
end

-- ArrayInterpolationGroup
function interpolation.new_array_interpolation_group(index, slot_begin, slot_count, out_index, float_count)
    return {
        index = index,
        slot_begin = slot_begin,
        slot_count = slot_count,
        out_index = out_index,
        float_count = float_count,
    }
end

function interpolation.interpolate_float32(values, weights)
    if #values ~= #weights then
        return nil
    end
    local sum = 0
    for i = 1, #values do
        sum = sum + values[i] * weights[i]
    end
    return sum
end

function interpolation.interpolate_int32(values, weights)
    local value = interpolation.interpolate_float32(values, weights)
    if value == nil then
        return nil
    end
    -- truncation after adding small epsilon
    local tr = value + 0.001
    if tr >= 0 then
        return math.floor(tr)
    else
        return math.ceil(tr)
    end
end

function interpolation.interpolate_float32_array(arrays, weights, count)
    if #arrays ~= #weights then
        return nil
    end
    for i = 1, #arrays do
        if #arrays[i] < count then
            return nil
        end
    end
    local out = {}
    for i = 1, count do
        out[i] = 0
    end
    for a = 1, #arrays do
        if weights[a] == 0 then
            -- skip
        else
            for i = 1, count do
                out[i] = out[i] + arrays[a][i] * weights[a]
            end
        end
    end
    return out
end

function interpolation.interpolate_float32_array_grouped(arrays, weights, groups, output_arrays, skip_mask)
    if #arrays ~= #weights then
        return nil
    end
    for _, group in ipairs(groups) do
        if skip_mask and not skip_mask[group.index + 1] then
            -- Lua arrays are 1-indexed; group.index is 0-based
        else
            local slot_end = group.slot_begin + group.slot_count
            if slot_end > #arrays then
                return nil
            end
            local ok = true
            for slot = group.slot_begin + 1, slot_end do
                if #arrays[slot] < group.float_count then
                    ok = false
                    break
                end
            end
            if not ok then
                return nil
            end
            local out = output_arrays[group.out_index + 1]
            if not out then
                return nil
            end
            for i = 1, group.float_count do
                out[i] = 0
            end
            for slot = group.slot_begin + 1, slot_end do
                local w = weights[slot]
                if w ~= 0 then
                    for i = 1, group.float_count do
                        out[i] = out[i] + arrays[slot][i] * w
                    end
                end
            end
        end
    end
    return true
end

function interpolation.interpolate_float32_grouped(values, weights, groups, skip_mask)
    if #values ~= #weights then
        return nil
    end
    local weighted = {}
    for i = 1, #values do
        weighted[i] = values[i] * weights[i]
    end
    local out = {}
    for _, group in ipairs(groups) do
        if skip_mask and not skip_mask[group.index + 1] then
            -- skip
        else
            local ends = group.offset + group.count
            if ends > #weighted then
                return nil
            end
            local sum = 0
            for i = group.offset + 1, ends do
                sum = sum + weighted[i]
            end
            table.insert(out, {
                out_index = group.out_index,
                value = sum,
            })
        end
    end
    return out
end

return interpolation
