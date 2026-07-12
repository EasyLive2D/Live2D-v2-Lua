-- ModelRuntime for Cubism 3
-- Ported from Mocari src/runtime.rs

local moc3 = require("live2d.cubism3.moc3")
local pose3 = require("live2d.cubism3.json.pose3")
local parameter_utils = require("live2d.cubism3.core.parameters")
local draw_order_from_raw = require("live2d.cubism3.core.art_mesh").draw_order_from_raw

local ModelRuntime = {}
ModelRuntime.__index = ModelRuntime

local function normalized_parameter_value(value, minimum, maximum)
    if maximum <= minimum then return 0.0 end
    return math.max(0, math.min(1, (value - minimum) / (maximum - minimum)))
end

local function build_pose_groups(pose_data, part_index)
    local groups = {}
    for _, group in ipairs(pose_data.groups or {}) do
        local members = {}
        local links = {}
        for _, part in ipairs(group) do
            local part_idx = part_index[part.Id]
            if part_idx ~= nil then
                members[#members + 1] = part_idx
                local link_list = {}
                for _, link_id in ipairs(part.Links or {}) do
                    local link_idx = part_index[link_id]
                    if link_idx ~= nil then
                        link_list[#link_list + 1] = link_idx
                    end
                end
                links[#links + 1] = link_list
            end
        end
        if #members >= 2 then
            groups[#groups + 1] = { members = members, links = links }
        end
    end
    return groups
end

local function initial_pose_opacities(groups, part_count)
    local opacities = {}
    for i = 1, part_count do
        opacities[i] = 1.0
    end
    for _, group in ipairs(groups) do
        for position, part in ipairs(group.members) do
            local opacity = position == 1 and 1.0 or 0.0
            opacities[part + 1] = opacity
            for _, link in ipairs(group.links[position]) do
                opacities[link + 1] = opacity
            end
        end
    end
    return opacities
end

function ModelRuntime.new(model, canvas, art_meshes, art_mesh_keyforms, deformers, bindings, ids, offscreen, glues, parts, draw_order_groups, pose)
    if draw_order_groups ~= nil and draw_order_groups.drawable_count_value == nil then
        pose = draw_order_groups
        draw_order_groups = nil
    end
    local parameter_values = {}
    local saved_parameter_values = {}
    local defaults = bindings.parameter_default_values
    for i = 1, #defaults do
        parameter_values[i] = defaults[i]
        saved_parameter_values[i] = defaults[i]
    end

    -- Build parameter index map
    local parameter_index = {}
    for i, id in ipairs(ids.parameters) do
        parameter_index[id] = i - 1
    end

    -- Build part index map
    local part_index = {}
    for i, id in ipairs(ids.parts) do
        part_index[id] = i - 1
    end

    local part_count = parts:part_count()

    local pose_fade_time = 0.0
    if pose and pose.fade_in_time then
        pose_fade_time = pose3.resolved_pose_fade_in_time(pose.fade_in_time)
    end

    local pose_groups = {}
    if pose then
        pose_groups = build_pose_groups(pose, part_index)
    end
    local pose_opacities = initial_pose_opacities(pose_groups, part_count)

    local part_opacity_overrides = {}
    for i = 1, part_count do
        part_opacity_overrides[i] = nil -- None
    end

    local part_opacities = {}
    for i = 1, part_count do
        part_opacities[i] = 1.0
    end

    local self = setmetatable({
        model = model,
        canvas = canvas,
        art_meshes = art_meshes,
        art_mesh_keyforms = art_mesh_keyforms,
        deformers = deformers,
        bindings = bindings,
        ids = ids,
        offscreen = offscreen,
        glues = glues,
        parts = parts,
        draw_order_groups = draw_order_groups,
        parameter_index = parameter_index,
        parameter_values = parameter_values,
        saved_parameter_values = saved_parameter_values,
        parameter_overrides = {},
        parameter_override_sources = {},
        part_index = part_index,
        part_opacity_overrides = part_opacity_overrides,
        part_opacities = part_opacities,
        pose_groups = pose_groups,
        pose_fade_time = pose_fade_time,
        pose_opacities = pose_opacities,
        meshes = {},
        _drawable_part_opacities = {},
        _drawable_draw_orders = {},
        _part_draw_orders = {},
        _part_enable = {},
        _pose_selection = {},
        _pose_faded = {},
        _composed_deformers = {},
        _render_orders = {},
        physics = nil,
        _parameter_write_source = "direct",
        _parameter_trace = nil,
    }, ModelRuntime)

    local ok = self:update_meshes()
    if not ok then
        return nil
    end
    return self
end

function ModelRuntime:parameter_index_of(id)
    return self.parameter_index[id]
end

function ModelRuntime:parameter_value(id)
    local idx = self:parameter_index_of(id)
    if idx == nil then return nil end
    return self.parameter_values[idx + 1]
end

function ModelRuntime:parameter_value_by_index(index)
    return self.parameter_values[index + 1]
end

function ModelRuntime:parameter_ids()
    return self.ids.parameters
end

function ModelRuntime:parameter_minimum_by_index(index)
    return self.bindings.parameter_min_values[index + 1]
end

function ModelRuntime:parameter_maximum_by_index(index)
    return self.bindings.parameter_max_values[index + 1]
end

function ModelRuntime:parameter_default_by_index(index)
    return self.bindings.parameter_default_values[index + 1]
end

function ModelRuntime:parameter_info(id)
    local idx = self:parameter_index_of(id)
    if idx == nil then return nil end
    return self:parameter_info_by_index(idx)
end

function ModelRuntime:parameter_info_by_index(index)
    local id = self.ids.parameters[index + 1]
    local minimum = self:parameter_minimum_by_index(index)
    local maximum = self:parameter_maximum_by_index(index)
    local default = self:parameter_default_by_index(index)
    local value = self:parameter_value_by_index(index)
    if id == nil or minimum == nil or maximum == nil or default == nil or value == nil then
        return nil
    end
    return {
        id = id,
        minimum = minimum,
        maximum = maximum,
        default = default,
        value = value,
        normalized_value = normalized_parameter_value(value, minimum, maximum),
    }
end

function ModelRuntime:parameter_infos()
    local infos = {}
    for index = 0, #self.ids.parameters - 1 do
        local info = self:parameter_info_by_index(index)
        if info ~= nil then infos[#infos + 1] = info end
    end
    return infos
end

function ModelRuntime:parameter_normalized_value(id)
    local idx = self:parameter_index_of(id)
    if idx == nil then return nil end
    return self:parameter_normalized_value_by_index(idx)
end

function ModelRuntime:parameter_normalized_value_by_index(index)
    local value = self:parameter_value_by_index(index)
    local minimum = self:parameter_minimum_by_index(index)
    local maximum = self:parameter_maximum_by_index(index)
    if value == nil or minimum == nil or maximum == nil then return nil end
    return normalized_parameter_value(value, minimum, maximum)
end

function ModelRuntime:raw_parameter_value_from_normalized_index(index, value)
    local minimum = self:parameter_minimum_by_index(index)
    local maximum = self:parameter_maximum_by_index(index)
    if minimum == nil or maximum == nil then return nil end
    local amount = math.max(0, math.min(1, tonumber(value) or 0))
    return minimum + (maximum - minimum) * amount
end

function ModelRuntime:set_parameter(id, value)
    local idx = self:parameter_index_of(id)
    if idx == nil then return false end
    return self:set_parameter_by_index(idx, value)
end

function ModelRuntime:set_parameter_by_index(index, value)
    local slot = index + 1
    local before = self.parameter_values[slot]
    if before == nil then return false end
    local minimum = self.bindings.parameter_min_values[index + 1] or -math.huge
    local maximum = self.bindings.parameter_max_values[index + 1] or math.huge
    local after = parameter_utils.clamp_parameter_value(value, minimum, maximum)
    self.parameter_values[slot] = after
    self:_trace_parameter_write(index, before, after)
    return true
end

-- Public/direct parameter writes are part of the model's persistent base
-- state.  Motion and physics still use set_parameter_by_index directly so
-- their transient results are not fed back into the next frame.
function ModelRuntime:set_base_parameter(id, value)
    local idx = self:parameter_index_of(id)
    if idx == nil then return false end
    return self:set_base_parameter_by_index(idx, value)
end

function ModelRuntime:set_base_parameter_by_index(index, value)
    if not self:set_parameter_by_index(index, value) then return false end
    self.saved_parameter_values[index + 1] = self.parameter_values[index + 1]
    return true
end

function ModelRuntime:set_parameter_normalized(id, value)
    local idx = self:parameter_index_of(id)
    if idx == nil then return false end
    return self:set_parameter_normalized_by_index(idx, value)
end

function ModelRuntime:set_parameter_normalized_by_index(index, value)
    local raw = self:raw_parameter_value_from_normalized_index(index, value)
    if raw == nil then return false end
    return self:set_parameter_by_index(index, raw)
end

function ModelRuntime:set_base_parameter_normalized(id, value)
    local idx = self:parameter_index_of(id)
    if idx == nil then return false end
    return self:set_base_parameter_normalized_by_index(idx, value)
end

function ModelRuntime:set_base_parameter_normalized_by_index(index, value)
    local raw = self:raw_parameter_value_from_normalized_index(index, value)
    if raw == nil then return false end
    return self:set_base_parameter_by_index(index, raw)
end

function ModelRuntime:parameter_override_value(id)
    local idx = self:parameter_index_of(id)
    if idx == nil then return nil end
    return self:parameter_override_value_by_index(idx)
end

function ModelRuntime:parameter_override_value_by_index(index)
    return self.parameter_overrides[index + 1]
end

function ModelRuntime:parameter_override_normalized_value(id)
    local idx = self:parameter_index_of(id)
    if idx == nil then return nil end
    return self:parameter_override_normalized_value_by_index(idx)
end

function ModelRuntime:parameter_override_normalized_value_by_index(index)
    local value = self:parameter_override_value_by_index(index)
    local minimum = self:parameter_minimum_by_index(index)
    local maximum = self:parameter_maximum_by_index(index)
    if value == nil or minimum == nil or maximum == nil then return nil end
    return normalized_parameter_value(value, minimum, maximum)
end

function ModelRuntime:set_parameter_override(id, value, source)
    local idx = self:parameter_index_of(id)
    if idx == nil then return false end
    return self:set_parameter_override_by_index(idx, value, source)
end

function ModelRuntime:set_parameter_override_by_index(index, value, source)
    if self.parameter_values[index + 1] == nil then return false end
    local minimum = self:parameter_minimum_by_index(index)
    local maximum = self:parameter_maximum_by_index(index)
    if minimum == nil or maximum == nil then return false end
    self.parameter_overrides[index + 1] = parameter_utils.clamp_parameter_value(tonumber(value) or 0, minimum, maximum)
    self.parameter_override_sources[index + 1] = tostring(source or "override")
    return true
end

function ModelRuntime:set_parameter_override_normalized(id, value)
    local idx = self:parameter_index_of(id)
    if idx == nil then return false end
    return self:set_parameter_override_normalized_by_index(idx, value)
end

function ModelRuntime:set_parameter_override_normalized_by_index(index, value)
    local raw = self:raw_parameter_value_from_normalized_index(index, value)
    if raw == nil then return false end
    return self:set_parameter_override_by_index(index, raw)
end

function ModelRuntime:clear_parameter_override(id)
    local idx = self:parameter_index_of(id)
    if idx == nil then return false end
    return self:clear_parameter_override_by_index(idx)
end

function ModelRuntime:clear_parameter_override_by_index(index)
    if self.parameter_values[index + 1] == nil then return false end
    self.parameter_overrides[index + 1] = nil
    self.parameter_override_sources[index + 1] = nil
    return true
end

function ModelRuntime:clear_parameter_overrides()
    for i = 1, #self.parameter_values do
        self.parameter_overrides[i] = nil
        self.parameter_override_sources[i] = nil
    end
end

function ModelRuntime:apply_parameter_overrides()
    local phase_source = self._parameter_write_source
    for index = 0, #self.parameter_values - 1 do
        local value = self.parameter_overrides[index + 1]
        if value ~= nil then
            self._parameter_write_source = self.parameter_override_sources[index + 1] or phase_source
            self:set_parameter_by_index(index, value)
        end
    end
    self._parameter_write_source = phase_source
end

-- Cubism's per-frame parameter contract: restore the state saved after the
-- previous motion pass, then save the new motion result before transient
-- expression/tracking/physics writes.  Physics output must never become the
-- next frame's base input.
function ModelRuntime:load_parameters()
    for index = 0, #self.saved_parameter_values - 1 do
        self:set_parameter_by_index(index, self.saved_parameter_values[index + 1])
    end
end

function ModelRuntime:save_parameters()
    for i = 1, #self.parameter_values do
        self.saved_parameter_values[i] = self.parameter_values[i]
    end
end

function ModelRuntime:reset_parameters()
    local defaults = self.bindings.parameter_default_values
    for index = 0, #defaults - 1 do
        self:set_parameter_by_index(index, defaults[index + 1])
        self.saved_parameter_values[index + 1] = self.parameter_values[index + 1]
    end
end

local function trace_tokens(filter)
    local tokens = {}
    for token in tostring(filter or ""):gmatch("[^,%s]+") do
        tokens[#tokens + 1] = token:lower()
    end
    return tokens
end

function ModelRuntime:configure_parameter_trace(filter)
    local text = tostring(filter or "")
    if text == "" or text == "0" or text:lower() == "false" then
        self._parameter_trace = nil
        return
    end
    if text == "1" or text:lower() == "true" then
        text = "leg,knee,foot,bodyangley,param33"
    end
    local current = self._parameter_trace
    if current ~= nil and current.filter == text then return end
    self._parameter_trace = { filter = text, tokens = trace_tokens(text), counts = {} }
end

function ModelRuntime:begin_parameter_frame(frame_number, time_msec, delta_seconds)
    local trace = self._parameter_trace
    if trace == nil then return end
    trace.frame = tonumber(frame_number) or 0
    trace.time_msec = tonumber(time_msec) or 0
    trace.delta = tonumber(delta_seconds) or 0
    trace.counts = {}
end

function ModelRuntime:set_parameter_write_source(source)
    self._parameter_write_source = tostring(source or "unknown")
end

function ModelRuntime:_trace_parameter_write(index, before, after)
    local trace = self._parameter_trace
    if trace == nil then return end
    local id = tostring(self.ids.parameters[index + 1] or index)
    local lower_id = id:lower()
    local matched = #trace.tokens == 0
    for _, token in ipairs(trace.tokens) do
        if lower_id:find(token, 1, true) ~= nil then matched = true break end
    end
    if not matched then return end
    local count = (trace.counts[id] or 0) + 1
    trace.counts[id] = count
    print(string.format(
        "[Live2DParam] frame=%d time_ms=%.3f dt=%.6f id=%s source=%s before=%.6f after=%.6f writes=%d",
        trace.frame or 0, trace.time_msec or 0, trace.delta or 0, id,
        tostring(self._parameter_write_source or "unknown"), tonumber(before) or 0,
        tonumber(after) or 0, count
    ))
end

function ModelRuntime:part_index_of(id)
    return self.part_index[id]
end

function ModelRuntime:set_part_opacity(id, value)
    local idx = self:part_index_of(id)
    if idx == nil then return false end
    return self:set_part_opacity_by_index(idx, value)
end

function ModelRuntime:set_part_opacity_by_index(index, value)
    if index < 0 or index >= self.parts:part_count() then return false end
    self.part_opacity_overrides[index + 1] = math.max(0, math.min(1, value))
    return true
end

function ModelRuntime:reset_part_opacities()
    for i = 1, self.parts:part_count() do
        self.part_opacity_overrides[i] = nil
    end
end

function ModelRuntime:apply_pose(delta_seconds)
    local selection = self._pose_selection
    local faded = self._pose_faded
    for _, group in ipairs(self.pose_groups) do
        local member_count = #group.members
        for i = 1, member_count do
            local part = group.members[i]
            selection[i] = self:part_selection_opacity(part)
        end
        for i = 1, member_count do
            local part = group.members[i]
            faded[i] = self.pose_opacities[part + 1]
        end
        for i = member_count + 1, #selection do
            selection[i] = nil
            faded[i] = nil
        end

        local ok = pose3.update_pose_group_opacities(
            selection, faded, delta_seconds, self.pose_fade_time
        )
        if ok then
            for i = 1, #faded do
                local part = group.members[i]
                self.pose_opacities[part + 1] = faded[i]
            end
            for member_pos, part in ipairs(group.members) do
                pose3.copy_pose_link_opacities(
                    self.pose_opacities,
                    part + 1,
                    group.links[member_pos]
                )
            end
        end
    end
end

function ModelRuntime:part_selection_opacity(part_index)
    local override = self.part_opacity_overrides[part_index + 1]
    if override ~= nil then
        return override
    end
    return self.parts:interpolate_opacity(part_index, self.bindings, self.parameter_values) or 1.0
end

function ModelRuntime:set_physics(physics)
    self.physics = physics
    return self
end

function ModelRuntime:get_physics()
    return self.physics
end

function ModelRuntime:update_physics(delta_seconds)
    if self.physics == nil then return false end
    return self.physics:evaluate(self, delta_seconds)
end

function ModelRuntime:reset_physics()
    if self.physics == nil then return false end
    self.physics:reset()
    return true
end

function ModelRuntime:part_drawable_opacity(part_index)
    local override = self.part_opacity_overrides[part_index + 1]
    if override ~= nil then
        return override
    end
    return 1.0
end

function ModelRuntime:update_part_opacities()
    local part_opacities = self.part_opacities
    local parent_part_indices = self.parts.parent_part_indices
    -- Compute base part opacities
    for index = 0, #part_opacities - 1 do
        local base = self:part_drawable_opacity(index)
        part_opacities[index + 1] = base * self.pose_opacities[index + 1]
    end

    -- Multiply by parent opacities (hierarchical)
    for index = 0, #part_opacities - 1 do
        local opacity = part_opacities[index + 1]
        local parent = parent_part_indices[index + 1]
        while parent ~= nil and parent >= 0 do
            opacity = opacity * (part_opacities[parent + 1] or 1.0)
            parent = parent_part_indices[parent + 1]
        end
        part_opacities[index + 1] = opacity
    end
end

function ModelRuntime:drawable_part_opacities(out)
    local result = out or {}
    local mesh_count = #self.art_meshes.meshes
    local drawable_parent_part_indices = self.offscreen.drawable_parent_part_indices
    for i = 0, mesh_count - 1 do
        local part_idx = drawable_parent_part_indices[i + 1]
        local opacity = 1.0
        if part_idx and part_idx >= 0 then
            opacity = self.part_opacities[part_idx + 1] or 1.0
        end
        result[i + 1] = opacity
    end
    for i = mesh_count + 1, #result do
        result[i] = nil
    end
    return result
end

function ModelRuntime:update_meshes()
    self:update_part_opacities()
    local drawable_part_opacities = self:drawable_part_opacities(self._drawable_part_opacities)
    local meshes = moc3.mesh_build.build_moc3_drawable_meshes_with_parameters_offscreen_and_part_opacities(
        self.art_meshes,
        self.art_mesh_keyforms,
        self.deformers,
        self.bindings,
        self.ids,
        self.offscreen,
        self.parameter_values,
        drawable_part_opacities,
        self.meshes,
        self._composed_deformers
    )
    if not meshes then
        return nil
    end
    if not self.glues:apply(meshes, self.bindings, self.parameter_values) then
        return nil
    end
    self.meshes = meshes
    self:apply_group_render_orders()
    return true
end

function ModelRuntime:apply_group_render_orders()
    local groups = self.draw_order_groups
    if not groups then return end

    local drawable_draw_orders = self._drawable_draw_orders
    local meshes = self.meshes
    for i = 1, #meshes do
        local mesh = meshes[i]
        drawable_draw_orders[i] = draw_order_from_raw(mesh.draw_order)
    end
    for i = #meshes + 1, #drawable_draw_orders do
        drawable_draw_orders[i] = nil
    end

    local part_count = self.parts:part_count()
    local part_draw_orders = self._part_draw_orders
    local part_enable = self._part_enable
    for index = 0, part_count - 1 do
        local raw = self.parts:interpolate_draw_order(index, self.bindings, self.parameter_values)
        if raw ~= nil then
            part_draw_orders[index + 1] = draw_order_from_raw(raw)
            part_enable[index + 1] = true
        else
            part_draw_orders[index + 1] = 0
            part_enable[index + 1] = false
        end
    end
    for i = part_count + 1, #part_draw_orders do
        part_draw_orders[i] = nil
        part_enable[i] = nil
    end

    local render_orders = groups:render_orders(
        drawable_draw_orders,
        part_draw_orders,
        part_enable,
        self.offscreen:part_offscreen_indices_list(),
        self.offscreen:offscreen_count(),
        self._render_orders
    )
    if not render_orders then return end
    for i = 1, #meshes do
        meshes[i].render_order = render_orders[i]
    end
end

return ModelRuntime
