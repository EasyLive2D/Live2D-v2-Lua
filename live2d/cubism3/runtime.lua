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
    local defaults = bindings.parameter_default_values
    for i = 1, #defaults do
        parameter_values[i] = defaults[i]
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
        parameter_overrides = {},
        part_index = part_index,
        part_opacity_overrides = part_opacity_overrides,
        part_opacities = part_opacities,
        pose_groups = pose_groups,
        pose_fade_time = pose_fade_time,
        pose_opacities = pose_opacities,
        meshes = {},
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
    local slot = self.parameter_values[index + 1]
    if slot == nil then return false end
    local minimum = self.bindings.parameter_min_values[index + 1] or -math.huge
    local maximum = self.bindings.parameter_max_values[index + 1] or math.huge
    self.parameter_values[index + 1] = parameter_utils.clamp_parameter_value(value, minimum, maximum)
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

function ModelRuntime:set_parameter_override(id, value)
    local idx = self:parameter_index_of(id)
    if idx == nil then return false end
    return self:set_parameter_override_by_index(idx, value)
end

function ModelRuntime:set_parameter_override_by_index(index, value)
    if self.parameter_values[index + 1] == nil then return false end
    local minimum = self:parameter_minimum_by_index(index)
    local maximum = self:parameter_maximum_by_index(index)
    if minimum == nil or maximum == nil then return false end
    self.parameter_overrides[index + 1] = parameter_utils.clamp_parameter_value(tonumber(value) or 0, minimum, maximum)
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
    return true
end

function ModelRuntime:clear_parameter_overrides()
    for i = 1, #self.parameter_values do
        self.parameter_overrides[i] = nil
    end
end

function ModelRuntime:apply_parameter_overrides()
    for index = 0, #self.parameter_values - 1 do
        local value = self.parameter_overrides[index + 1]
        if value ~= nil then
            self:set_parameter_by_index(index, value)
        end
    end
end

function ModelRuntime:reset_parameters()
    local defaults = self.bindings.parameter_default_values
    for i = 1, #defaults do
        self.parameter_values[i] = defaults[i]
    end
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
    for _, group in ipairs(self.pose_groups) do
        local selection = {}
        for _, part in ipairs(group.members) do
            selection[#selection + 1] = self:part_selection_opacity(part)
        end
        local faded = {}
        for _, part in ipairs(group.members) do
            faded[#faded + 1] = self.pose_opacities[part + 1]
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

function ModelRuntime:update_part_opacities()
    -- Compute base part opacities
    for index = 0, #self.part_opacities - 1 do
        local base = self.part_opacity_overrides[index + 1]
        if base == nil then
            base = self.parts:interpolate_opacity(index, self.bindings, self.parameter_values) or 1.0
        end
        self.part_opacities[index + 1] = base * self.pose_opacities[index + 1]
    end

    -- Multiply by parent opacities (hierarchical)
    for index = 0, #self.part_opacities - 1 do
        local opacity = self.part_opacities[index + 1]
        local parent = self.parts:parent_part_index(index)
        while parent ~= nil and parent >= 0 do
            opacity = opacity * (self.part_opacities[parent + 1] or 1.0)
            parent = self.parts:parent_part_index(parent)
        end
        self.part_opacities[index + 1] = opacity
    end
end

function ModelRuntime:drawable_part_opacities()
    local result = {}
    local mesh_count = #self.art_meshes.meshes
    for i = 0, mesh_count - 1 do
        local part_idx = self.offscreen:drawable_parent_part_index(i)
        local opacity = 1.0
        if part_idx and part_idx >= 0 then
            opacity = self.part_opacities[part_idx + 1] or 1.0
        end
        result[#result + 1] = opacity
    end
    return result
end

function ModelRuntime:update_meshes()
    self:update_part_opacities()
    local drawable_part_opacities = self:drawable_part_opacities()
    local meshes = moc3.mesh_build.build_moc3_drawable_meshes_with_parameters_offscreen_and_part_opacities(
        self.art_meshes,
        self.art_mesh_keyforms,
        self.deformers,
        self.bindings,
        self.ids,
        self.offscreen,
        self.parameter_values,
        drawable_part_opacities
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

    local drawable_draw_orders = {}
    for i, mesh in ipairs(self.meshes) do
        drawable_draw_orders[i] = draw_order_from_raw(mesh.draw_order)
    end

    local part_count = self.parts:part_count()
    local part_draw_orders = {}
    local part_enable = {}
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

    local render_orders = groups:render_orders(
        drawable_draw_orders,
        part_draw_orders,
        part_enable,
        self.offscreen:part_offscreen_indices_list(),
        self.offscreen:offscreen_count()
    )
    if not render_orders then return end
    for i, mesh in ipairs(self.meshes) do
        mesh.render_order = render_orders[i]
    end
end

return ModelRuntime
