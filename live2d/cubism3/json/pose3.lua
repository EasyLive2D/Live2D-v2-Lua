-- Pose3 JSON parser and pose logic for Cubism 3
-- Ported from Mocari src/json/pose3.rs

local json = require("live2d.dkjson")

local pose3 = {}

local DEFAULT_POSE_FADE_IN_TIME = 0.5

function pose3.resolved_pose_fade_in_time(fade_in_time)
    if fade_in_time ~= nil and fade_in_time >= 0 then
        return fade_in_time
    end
    return DEFAULT_POSE_FADE_IN_TIME
end

function pose3.parse(source)
    local ok, raw = pcall(json.decode, source)
    if not ok then
        return nil, "Invalid pose3.json: " .. tostring(raw)
    end

    return {
        kind = raw.Type,
        fade_in_time = raw.FadeInTime,
        groups = raw.Groups or {},
    }
end

function pose3.update_pose_group_opacities(parameter_values, part_opacities, delta_time_seconds, fade_time_seconds)
    if #parameter_values == 0 or #parameter_values ~= #part_opacities then
        return nil
    end

    delta_time_seconds = math.max(0, delta_time_seconds)
    local visible_part_index = nil
    local new_opacity = 1

    for i = 1, #parameter_values do
        if parameter_values[i] <= 0.001 then
            -- skip
        else
            if visible_part_index ~= nil then
                break
            end
            visible_part_index = i
            if fade_time_seconds == 0 then
                new_opacity = 1
            else
                new_opacity = math.min(1, part_opacities[i] + (delta_time_seconds / fade_time_seconds))
            end
        end
    end

    visible_part_index = visible_part_index or 1

    for i = 1, #part_opacities do
        if i == visible_part_index then
            part_opacities[i] = new_opacity
        else
            local target_opacity
            if new_opacity < 0.5 then
                target_opacity = new_opacity * (0.5 - 1) / 0.5 + 1
            else
                target_opacity = (1 - new_opacity) * 0.5 / (1 - 0.5)
            end
            local back_opacity = (1 - target_opacity) * (1 - new_opacity)
            if back_opacity > 0.15 then
                target_opacity = 1 - 0.15 / (1 - new_opacity)
            end
            if part_opacities[i] > target_opacity then
                part_opacities[i] = target_opacity
            end
        end
    end

    return true
end

function pose3.copy_pose_link_opacities(part_opacities, source_index, link_indices)
    if source_index < 1 or source_index > #part_opacities then
        return nil
    end
    for _, link_index in ipairs(link_indices) do
        if link_index < 1 or link_index > #part_opacities then
            return nil
        end
    end
    local opacity = part_opacities[source_index]
    for _, link_index in ipairs(link_indices) do
        part_opacities[link_index] = opacity
    end
    return true
end

return pose3
