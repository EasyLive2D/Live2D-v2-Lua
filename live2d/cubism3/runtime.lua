-- ModelRuntime for Cubism 3
-- Ported from Mocari src/runtime.rs

local moc3 = require("live2d.cubism3.moc3")
local pose3 = require("live2d.cubism3.json.pose3")
local parameter_utils = require("live2d.cubism3.core.parameters")

local ModelRuntime = {}
ModelRuntime.__index = ModelRuntime

local function build_pose_groups(pose_data, part_index)
    local groups = {}
    for _, group in ipairs(pose_data.groups or {}) do
        local members = {}
        local links = {}
        for _, part in ipairs(group) do
            local part_idx = part_index[part.Id]
            if part_idx ~= nil then
                table.insert(members, part_idx)
                local link_list = {}
                for _, link_id in ipairs(part.Links or {}) do
                    local link_idx = part_index[link_id]
                    if link_idx ~= nil then
                        table.insert(link_list, link_idx)
                    end
                end
                table.insert(links, link_list)
            end
        end
        if #members >= 2 then
            table.insert(groups, { members = members, links = links })
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

function ModelRuntime.new(model, canvas, art_meshes, art_mesh_keyforms, deformers, bindings, ids, offscreen, parts, pose)
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
        parts = parts,
        parameter_index = parameter_index,
        parameter_values = parameter_values,
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
    local slot = self.part_opacity_overrides[index + 1]
    if slot == nil then return false end
    self.part_opacity_overrides[index + 1] = math.max(0, math.min(1, value))
    return true
end

function ModelRuntime:reset_part_opacities()
    for i = 1, #self.part_opacity_overrides do
        self.part_opacity_overrides[i] = nil
    end
end

function ModelRuntime:apply_pose(delta_seconds)
    for _, group in ipairs(self.pose_groups) do
        local selection = {}
        for _, part in ipairs(group.members) do
            table.insert(selection, self:part_selection_opacity(part))
        end
        local faded = {}
        for _, part in ipairs(group.members) do
            table.insert(faded, self.pose_opacities[part + 1])
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
        table.insert(result, opacity)
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
    self.meshes = meshes
    return true
end

return ModelRuntime
