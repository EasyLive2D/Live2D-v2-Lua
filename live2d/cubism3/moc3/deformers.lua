-- MOC3 deformers parser and composition for Cubism 3
-- Ported from Mocari src/moc3/deformers.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")
local Vector2 = require("live2d.cubism3.core.math").Vector2
local deformers_core = require("live2d.cubism3.core.deformers")

local deformers = {}

local DEFORMER_PARENT_DEFORMER_INDICES_SLOT = 16
local DEFORMER_TYPES_SLOT = 17
local DEFORMER_SPECIFIC_INDICES_SLOT = 18
local WARP_KEYFORM_BINDING_BAND_INDICES_SLOT = 19
local WARP_KEYFORM_BEGIN_INDICES_SLOT = 20
local WARP_KEYFORM_COUNTS_SLOT = 21
local WARP_VERTEX_COUNTS_SLOT = 22
local WARP_ROWS_SLOT = 23
local WARP_COLS_SLOT = 24
local ROTATION_KEYFORM_BINDING_BAND_INDICES_SLOT = 25
local ROTATION_KEYFORM_BEGIN_INDICES_SLOT = 26
local ROTATION_KEYFORM_COUNTS_SLOT = 27
local ROTATION_BASE_ANGLES_SLOT = 28
local WARP_KEYFORM_OPACITIES_SLOT = 59
local WARP_KEYFORM_POSITION_BEGIN_INDICES_SLOT = 60
local ROTATION_KEYFORM_OPACITIES_SLOT = 61
local ROTATION_KEYFORM_ANGLES_SLOT = 62
local ROTATION_KEYFORM_ORIGIN_XS_SLOT = 63
local ROTATION_KEYFORM_ORIGIN_YS_SLOT = 64
local ROTATION_KEYFORM_SCALES_SLOT = 65
local ROTATION_KEYFORM_REFLECT_XS_SLOT = 66
local ROTATION_KEYFORM_REFLECT_YS_SLOT = 67
local KEYFORM_POSITION_XYS_SLOT = 71
local WARP_KEYFORM_COLOR_BEGIN_INDICES_SLOT = 105
local ROTATION_KEYFORM_COLOR_BEGIN_INDICES_SLOT = 106
local KEYFORM_MULTIPLY_COLOR_SLOTS = { 108, 109, 110 }
local KEYFORM_SCREEN_COLOR_SLOTS = { 111, 112, 113 }

-- Deformer kind
local DEFORMER_WARP = 0
local DEFORMER_ROTATION = 1
local ROTATION_PROBE_ITERATIONS = 10
local ROTATION_PROBE_STEP_WARP_PARENT = -0.1
local ROTATION_PROBE_STEP_ROTATION_PARENT = -10.0

local function wrap_angle(angle)
    local two_pi = 2.0 * math.pi
    while angle < -math.pi do
        angle = angle + two_pi
    end
    while angle > math.pi do
        angle = angle - two_pi
    end
    return angle
end

local function read_color_channels(bytes, offs, slots, count, default)
    local r, err = parse.read_f32_section_or_default(bytes, offs, slots[1], count, default)
    if not r then return nil, err end
    local g, err = parse.read_f32_section_or_default(bytes, offs, slots[2], count, default)
    if not g then return nil, err end
    local b, err = parse.read_f32_section_or_default(bytes, offs, slots[3], count, default)
    if not b then return nil, err end
    return { r, g, b }
end

local function interpolate_colors(begin, slots, multiply_colors, screen_colors)
    if begin == nil or begin < 0 then
        return { 1, 1, 1 }, { 0, 0, 0 }
    end

    local multiply = { 0, 0, 0 }
    local screen = { 0, 0, 0 }
    for _, slot in ipairs(slots) do
        local color_index = begin + slot.local_index + 1
        for channel = 1, 3 do
            local multiply_channel = multiply_colors[channel] or {}
            local screen_channel = screen_colors[channel] or {}
            multiply[channel] = multiply[channel] + (multiply_channel[color_index] or 1) * slot.weight
            screen[channel] = screen[channel] + (screen_channel[color_index] or 0) * slot.weight
        end
    end
    return multiply, screen
end

local function compose_colors(local_multiply, local_screen, parent_multiply, parent_screen)
    local multiply = { 0, 0, 0 }
    local screen = { 0, 0, 0 }
    for channel = 1, 3 do
        multiply[channel] = local_multiply[channel] * parent_multiply[channel]
        screen[channel] = local_screen[channel] + parent_screen[channel]
            - local_screen[channel] * parent_screen[channel]
    end
    return multiply, screen
end

function deformers.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end

    local deformer_count = parse.to_usize(cnts.deformers, "deformer count")
    local warp_count = parse.to_usize(cnts.warp_deformers, "warp deformer count")
    local rotation_count = parse.to_usize(cnts.rotation_deformers, "rotation deformer count")
    local warp_kf_count = parse.to_usize(cnts.warp_deformer_keyforms, "warp deformer keyform count")
    local rotation_kf_count = parse.to_usize(cnts.rotation_deformer_keyforms, "rotation deformer keyform count")
    local keyform_multiply_color_count = parse.to_usize(cnts.keyform_multiply_colors or 0, "keyform multiply color count")
    local keyform_screen_color_count = parse.to_usize(cnts.keyform_screen_colors or 0, "keyform screen color count")
    if not deformer_count then return nil, "Invalid deformer count" end

    if warp_kf_count == nil then warp_kf_count = 0 end
    if rotation_kf_count == nil then rotation_kf_count = 0 end
    if keyform_multiply_color_count == nil then keyform_multiply_color_count = 0 end
    if keyform_screen_color_count == nil then keyform_screen_color_count = 0 end

    local deformer_types, err = parse.read_i32_section(bytes, offs, DEFORMER_TYPES_SLOT, deformer_count)
    if not deformer_types then return nil, err end

    -- Parse all sections
    local parent_indices, err = parse.read_i32_section(bytes, offs, DEFORMER_PARENT_DEFORMER_INDICES_SLOT, deformer_count)
    if not parent_indices then return nil, err end
    local specific_indices, err = parse.read_i32_section(bytes, offs, DEFORMER_SPECIFIC_INDICES_SLOT, deformer_count)
    if not specific_indices then return nil, err end

    local warp_kf_band, err = parse.read_i32_section(bytes, offs, WARP_KEYFORM_BINDING_BAND_INDICES_SLOT, warp_count)
    if not warp_kf_band then return nil, err end
    local warp_kf_begin, err = parse.read_i32_section(bytes, offs, WARP_KEYFORM_BEGIN_INDICES_SLOT, warp_count)
    if not warp_kf_begin then return nil, err end
    local warp_kf_counts, err = parse.read_i32_section(bytes, offs, WARP_KEYFORM_COUNTS_SLOT, warp_count)
    if not warp_kf_counts then return nil, err end
    local warp_vertex_counts, err = parse.read_i32_section(bytes, offs, WARP_VERTEX_COUNTS_SLOT, warp_count)
    if not warp_vertex_counts then return nil, err end
    local warp_rows, err = parse.read_i32_section(bytes, offs, WARP_ROWS_SLOT, warp_count)
    if not warp_rows then return nil, err end
    local warp_cols, err = parse.read_i32_section(bytes, offs, WARP_COLS_SLOT, warp_count)
    if not warp_cols then return nil, err end
    local warp_kf_opacities, err = parse.read_f32_section_or_default(bytes, offs, WARP_KEYFORM_OPACITIES_SLOT, warp_kf_count, 1.0)
    if not warp_kf_opacities then return nil, err end

    local rot_kf_band, err = parse.read_i32_section(bytes, offs, ROTATION_KEYFORM_BINDING_BAND_INDICES_SLOT, rotation_count)
    if not rot_kf_band then return nil, err end
    local rot_kf_begin, err = parse.read_i32_section(bytes, offs, ROTATION_KEYFORM_BEGIN_INDICES_SLOT, rotation_count)
    if not rot_kf_begin then return nil, err end
    local rot_kf_counts, err = parse.read_i32_section(bytes, offs, ROTATION_KEYFORM_COUNTS_SLOT, rotation_count)
    if not rot_kf_counts then return nil, err end
    local rot_base_angles, err = parse.read_f32_section(bytes, offs, ROTATION_BASE_ANGLES_SLOT, rotation_count)
    if not rot_base_angles then return nil, err end

    local warp_kf_pos_begin, err = parse.read_i32_section(bytes, offs, WARP_KEYFORM_POSITION_BEGIN_INDICES_SLOT, warp_kf_count)
    if not warp_kf_pos_begin then return nil, err end

    local rot_angles, err = parse.read_f32_section(bytes, offs, ROTATION_KEYFORM_ANGLES_SLOT, rotation_kf_count)
    if not rot_angles then return nil, err end
    local rot_origin_xs, err = parse.read_f32_section(bytes, offs, ROTATION_KEYFORM_ORIGIN_XS_SLOT, rotation_kf_count)
    if not rot_origin_xs then return nil, err end
    local rot_origin_ys, err = parse.read_f32_section(bytes, offs, ROTATION_KEYFORM_ORIGIN_YS_SLOT, rotation_kf_count)
    if not rot_origin_ys then return nil, err end
    local rot_scales, err = parse.read_f32_section(bytes, offs, ROTATION_KEYFORM_SCALES_SLOT, rotation_kf_count)
    if not rot_scales then return nil, err end
    local rot_reflect_xs, err = parse.read_bool_section(bytes, offs, ROTATION_KEYFORM_REFLECT_XS_SLOT, rotation_kf_count)
    if not rot_reflect_xs then return nil, err end
    local rot_reflect_ys, err = parse.read_bool_section(bytes, offs, ROTATION_KEYFORM_REFLECT_YS_SLOT, rotation_kf_count)
    if not rot_reflect_ys then return nil, err end
    local rot_kf_opacities, err = parse.read_f32_section_or_default(bytes, offs, ROTATION_KEYFORM_OPACITIES_SLOT, rotation_kf_count, 1.0)
    if not rot_kf_opacities then return nil, err end

    local kf_pos_count = parse.to_usize(cnts.keyform_positions, "keyform position count")
    local kf_pos_xys, err = parse.read_f32_section(bytes, offs, KEYFORM_POSITION_XYS_SLOT, kf_pos_count)
    if not kf_pos_xys then return nil, err end

    local warp_color_begin, err = parse.read_i32_section_or_default(
        bytes, offs, WARP_KEYFORM_COLOR_BEGIN_INDICES_SLOT, warp_count, -1
    )
    if not warp_color_begin then return nil, err end
    local rotation_color_begin, err = parse.read_i32_section_or_default(
        bytes, offs, ROTATION_KEYFORM_COLOR_BEGIN_INDICES_SLOT, rotation_count, -1
    )
    if not rotation_color_begin then return nil, err end
    local multiply_colors, err = read_color_channels(
        bytes, offs, KEYFORM_MULTIPLY_COLOR_SLOTS, keyform_multiply_color_count, 1
    )
    if not multiply_colors then return nil, err end
    local screen_colors, err = read_color_channels(
        bytes, offs, KEYFORM_SCREEN_COLOR_SLOTS, keyform_screen_color_count, 0
    )
    if not screen_colors then return nil, err end

    return setmetatable({
        parent_deformer_indices = parent_indices,
        deformer_kinds = deformer_types,
        specific_indices = specific_indices,
        warp_keyform_binding_band_indices = warp_kf_band,
        warp_keyform_begin_indices = warp_kf_begin,
        warp_keyform_counts = warp_kf_counts,
        warp_vertex_counts = warp_vertex_counts,
        warp_rows = warp_rows,
        warp_cols = warp_cols,
        warp_keyform_opacities = warp_kf_opacities,
        rotation_keyform_binding_band_indices = rot_kf_band,
        rotation_keyform_begin_indices = rot_kf_begin,
        rotation_keyform_counts = rot_kf_counts,
        rotation_base_angles = rot_base_angles,
        warp_keyform_position_begin_indices = warp_kf_pos_begin,
        rotation_keyform_angles = rot_angles,
        rotation_keyform_origin_xs = rot_origin_xs,
        rotation_keyform_origin_ys = rot_origin_ys,
        rotation_keyform_scales = rot_scales,
        rotation_keyform_reflect_xs = rot_reflect_xs,
        rotation_keyform_reflect_ys = rot_reflect_ys,
        rotation_keyform_opacities = rot_kf_opacities,
        keyform_position_xys = kf_pos_xys,
        warp_keyform_color_begin_indices = warp_color_begin,
        rotation_keyform_color_begin_indices = rotation_color_begin,
        keyform_multiply_colors = multiply_colors,
        keyform_screen_colors = screen_colors,
    }, { __index = deformers })
end

-- Deformer depth (for topological sort)
local function deformer_depth(self, index)
    local depth = 0
    local current = index
    while true do
        local parent = self.parent_deformer_indices[current + 1]
        if parent == nil or parent < 0 then
            break
        end
        current = parent
        if current < 0 or current >= #self.parent_deformer_indices then
            break
        end
        depth = depth + 1
        if depth > #self.parent_deformer_indices then
            break
        end
    end
    return depth
end

-- Get warp keyform slots
local function warp_keyform_slots(self, warp_index, bindings, parameter_values)
    local kf_count = self.warp_keyform_counts[warp_index + 1]
    if kf_count == nil then return nil end
    local band_idx = self.warp_keyform_binding_band_indices[warp_index + 1]
    if band_idx == nil then return nil end
    return bindings:keyform_slots(band_idx, kf_count, parameter_values)
end

-- Get rotation keyform slots
local function rotation_keyform_slots(self, rotation_index, bindings, parameter_values)
    local kf_count = self.rotation_keyform_counts[rotation_index + 1]
    if kf_count == nil then return nil end
    local band_idx = self.rotation_keyform_binding_band_indices[rotation_index + 1]
    if band_idx == nil then return nil end
    return bindings:keyform_slots(band_idx, kf_count, parameter_values)
end

-- Get warp grid for a keyform index
local function warp_grid(self, warp_index, keyform_index)
    local start = self.warp_keyform_position_begin_indices[keyform_index + 1]
    if start == nil or start < 0 then return nil end
    local vertex_count = self.warp_vertex_counts[warp_index + 1]
    if vertex_count == nil or vertex_count < 0 then return nil end
    local len = vertex_count * 2
    if start + len > #self.keyform_position_xys then return nil end
    local result = {}
    for i = 0, vertex_count - 1 do
        result[#result + 1] = Vector2.new(
            self.keyform_position_xys[start + i * 2 + 1],
            self.keyform_position_xys[start + i * 2 + 2]
        )
    end
    return result
end

-- Interpolate warp grid
local function interpolated_warp_grid(self, warp_index, bindings, parameter_values)
    local slots = warp_keyform_slots(self, warp_index, bindings, parameter_values)
    if not slots then return nil end
    local begin = self.warp_keyform_begin_indices[warp_index + 1]
    if begin == nil or begin < 0 then return nil end
    local vertex_count = self.warp_vertex_counts[warp_index + 1]
    if vertex_count == nil or vertex_count < 0 then return nil end

    local grid = {}
    for i = 1, vertex_count do
        grid[i] = Vector2.new(0, 0)
    end

    for _, slot in ipairs(slots) do
        local kf_idx = begin + slot.local_index
        local source = warp_grid(self, warp_index, kf_idx)
        if not source or #source ~= #grid then return nil end
        for i = 1, #grid do
            grid[i] = Vector2.new(
                grid[i]:x() + source[i]:x() * slot.weight,
                grid[i]:y() + source[i]:y() * slot.weight
            )
        end
    end
    return grid
end

-- Interpolate rotation
local function interpolated_rotation(self, rotation_index, bindings, parameter_values)
    local slots = rotation_keyform_slots(self, rotation_index, bindings, parameter_values)
    if not slots then return nil end
    local begin = self.rotation_keyform_begin_indices[rotation_index + 1]
    if begin == nil or begin < 0 then return nil end

    local angle = 0.0
    local translation = Vector2.new(0, 0)
    local scale = 0.0
    local flip_x = 0.0
    local flip_y = 0.0

    for _, slot in ipairs(slots) do
        local kf_idx = begin + slot.local_index
        angle = angle + (self.rotation_keyform_angles[kf_idx + 1] or 0) * slot.weight
        translation = Vector2.new(
            translation:x() + (self.rotation_keyform_origin_xs[kf_idx + 1] or 0) * slot.weight,
            translation:y() + (self.rotation_keyform_origin_ys[kf_idx + 1] or 0) * slot.weight
        )
        scale = scale + (self.rotation_keyform_scales[kf_idx + 1] or 0) * slot.weight
        local reflectXSign = self.rotation_keyform_reflect_xs[kf_idx + 1] and 1 or 0
        local reflectYSign = self.rotation_keyform_reflect_ys[kf_idx + 1] and 1 or 0
        flip_x = flip_x + reflectXSign * slot.weight
        flip_y = flip_y + reflectYSign * slot.weight
    end

    local base_angle = self.rotation_base_angles[rotation_index + 1] or 0
    local flip_x_bool = math.floor(flip_x + 0.001) ~= 0
    local flip_y_bool = math.floor(flip_y + 0.001) ~= 0

    return {
        angle_degrees = base_angle + angle,
        translation = translation,
        scale = scale,
        flip_x = flip_x_bool,
        flip_y = flip_y_bool,
    }
end

-- Interpolate warp opacity
local function interpolated_warp_opacity(self, warp_index, bindings, parameter_values)
    local slots = warp_keyform_slots(self, warp_index, bindings, parameter_values)
    if not slots then return nil end
    local begin = self.warp_keyform_begin_indices[warp_index + 1]
    if begin == nil or begin < 0 then return nil end
    local opacity = 0.0
    for _, slot in ipairs(slots) do
        local kf_idx = begin + slot.local_index
        opacity = opacity + (self.warp_keyform_opacities[kf_idx + 1] or 1.0) * slot.weight
    end
    return opacity
end

local function interpolated_warp_colors(self, warp_index, bindings, parameter_values)
    local slots = warp_keyform_slots(self, warp_index, bindings, parameter_values)
    if not slots then return nil end
    local begins = self.warp_keyform_color_begin_indices or {}
    return interpolate_colors(
        begins[warp_index + 1] or -1,
        slots,
        self.keyform_multiply_colors or { {}, {}, {} },
        self.keyform_screen_colors or { {}, {}, {} }
    )
end

-- Interpolate rotation opacity
local function interpolated_rotation_opacity(self, rotation_index, bindings, parameter_values)
    local slots = rotation_keyform_slots(self, rotation_index, bindings, parameter_values)
    if not slots then return nil end
    local begin = self.rotation_keyform_begin_indices[rotation_index + 1]
    if begin == nil or begin < 0 then return nil end
    local opacity = 0.0
    for _, slot in ipairs(slots) do
        local kf_idx = begin + slot.local_index
        opacity = opacity + (self.rotation_keyform_opacities[kf_idx + 1] or 1.0) * slot.weight
    end
    return opacity
end

local function interpolated_rotation_colors(self, rotation_index, bindings, parameter_values)
    local slots = rotation_keyform_slots(self, rotation_index, bindings, parameter_values)
    if not slots then return nil end
    local begins = self.rotation_keyform_color_begin_indices or {}
    return interpolate_colors(
        begins[rotation_index + 1] or -1,
        slots,
        self.keyform_multiply_colors or { {}, {}, {} },
        self.keyform_screen_colors or { {}, {}, {} }
    )
end

-- Compose deformers (the main composition function)
function deformers.compose(self, bindings, parameter_values)
    local count = #self.deformer_kinds
    -- Topological sort by depth
    local order = {}
    for i = 0, count - 1 do
        order[#order + 1] = i
    end
    table.sort(order, function(a, b)
        return deformer_depth(self, a) < deformer_depth(self, b)
    end)

    local composed = {}
    for i = 1, count do
        composed[i] = nil
    end

    for _, idx in ipairs(order) do
        local parent = self.parent_deformer_indices[idx + 1] or -1
        local specific = self.specific_indices[idx + 1]
        if specific == nil or specific < 0 then
            return nil
        end
        local kind = self.deformer_kinds[idx + 1]

        -- Helper: apply composed parent to point
        local function apply_parent(p, point)
            if p < 0 then return point end
            local childIndex = p + 1
            if not composed[childIndex] then return point end
            return apply_one(composed[childIndex], point)
        end

        -- Helper: parent scale accum
        local function parent_scale(p)
            if p < 0 then return 1.0 end
            local childIndex = p + 1
            local c = composed[childIndex]
            if not c then return 1.0 end
            if c.kind == "warp" then return c.scale_accum end
            if c.kind == "rotation" then return c.scale_accum end
            return 1.0
        end

        -- Helper: parent opacity accum
        local function parent_opacity(p)
            if p < 0 then return 1.0 end
            local childIndex = p + 1
            local c = composed[childIndex]
            if not c then return 1.0 end
            if c.kind == "warp" then return c.opacity_accum end
            if c.kind == "rotation" then return c.opacity_accum end
            return 1.0
        end

        local function parent_colors(p)
            if p < 0 then return { 1, 1, 1 }, { 0, 0, 0 } end
            local childIndex = p + 1
            local c = composed[childIndex]
            if not c then return { 1, 1, 1 }, { 0, 0, 0 } end
            return c.multiply_color or { 1, 1, 1 }, c.screen_color or { 0, 0, 0 }
        end

        if kind == DEFORMER_WARP then
            local grid = interpolated_warp_grid(self, specific, bindings, parameter_values)
            if not grid then return nil end
            local cols = self.warp_cols[specific + 1] or 0
            local rows = self.warp_rows[specific + 1] or 0
            -- Apply parent transforms to grid
            for i, point in ipairs(grid) do
                local p = apply_parent(parent, point)
                if not p then return nil end
                grid[i] = p
            end
            local scale_accum = parent_scale(parent)
            local opacity = interpolated_warp_opacity(self, specific, bindings, parameter_values)
            if not opacity then return nil end
            local opacity_accum = opacity * parent_opacity(parent)
            local local_multiply, local_screen = interpolated_warp_colors(self, specific, bindings, parameter_values)
            if not local_multiply then return nil end
            local parent_multiply, parent_screen = parent_colors(parent)
            local multiply_color, screen_color = compose_colors(
                local_multiply,
                local_screen,
                parent_multiply,
                parent_screen
            )
            composed[idx + 1] = {
                kind = "warp",
                grid = grid,
                cols = cols,
                rows = rows,
                scale_accum = scale_accum,
                opacity_accum = opacity_accum,
                multiply_color = multiply_color,
                screen_color = screen_color,
            }
        elseif kind == DEFORMER_ROTATION then
            local rotation = interpolated_rotation(self, specific, bindings, parameter_values)
            if not rotation then return nil end
            local origin = apply_parent(parent, rotation.translation)
            if not origin then return nil end
            local step = ROTATION_PROBE_STEP_WARP_PARENT
            local parent_deformer = parent >= 0 and composed[parent + 1] or nil
            if parent_deformer and parent_deformer.kind == "rotation" then
                step = ROTATION_PROBE_STEP_ROTATION_PARENT
            end

            local direction = Vector2.new(0, 0)
            local scale = 1.0
            for _ = 1, ROTATION_PROBE_ITERATIONS do
                local offset = step * scale
                local forward = apply_parent(parent, Vector2.new(
                    rotation.translation:x(),
                    rotation.translation:y() + offset
                ))
                if not forward then return nil end

                local dx = forward:x() - origin:x()
                local dy = forward:y() - origin:y()
                if dx ~= 0 or dy ~= 0 then
                    direction = Vector2.new(dx, dy)
                    break
                end

                local backward = apply_parent(parent, Vector2.new(
                    rotation.translation:x(),
                    rotation.translation:y() - offset
                ))
                if not backward then return nil end

                dx = backward:x() - origin:x()
                dy = backward:y() - origin:y()
                if dx ~= 0 or dy ~= 0 then
                    direction = Vector2.new(-dx, -dy)
                    break
                end

                scale = scale * 0.1
            end

            local parent_angle_rad = wrap_angle(
                math.atan2(direction:y(), direction:x()) - math.atan2(step, 0.0)
            )
            local parent_angle_deg = parent_angle_rad * 180 / math.pi
            local scale_accum = parent_scale(parent)
            local opacity = interpolated_rotation_opacity(self, specific, bindings, parameter_values)
            if not opacity then return nil end
            local opacity_accum = opacity * parent_opacity(parent)
            local local_multiply, local_screen = interpolated_rotation_colors(self, specific, bindings, parameter_values)
            if not local_multiply then return nil end
            local parent_multiply, parent_screen = parent_colors(parent)
            local multiply_color, screen_color = compose_colors(
                local_multiply,
                local_screen,
                parent_multiply,
                parent_screen
            )
            composed[idx + 1] = {
                kind = "rotation",
                origin = origin,
                angle_degrees = rotation.angle_degrees + parent_angle_deg,
                scale = rotation.scale * scale_accum,
                flip_x = rotation.flip_x,
                flip_y = rotation.flip_y,
                scale_accum = rotation.scale * scale_accum,
                opacity_accum = opacity_accum,
                multiply_color = multiply_color,
                screen_color = screen_color,
            }
        end
    end

    return composed
end

-- Apply one composed deformer to a point
function apply_one(deformer, point)
    if not deformer then return point end
    if deformer.kind == "warp" then
        return deformers_core.warp_deformer_transform_target(
            point, deformer.grid, deformer.cols, deformer.rows,
            deformers_core.WARP_QUAD
        )
    elseif deformer.kind == "rotation" then
        return deformers_core.rotation_deformer_transform_point(
            point, deformer.angle_degrees, deformer.scale,
            deformer.origin, deformer.flip_x, deformer.flip_y
        )
    end
    return point
end

deformers.apply_one = apply_one

return deformers
