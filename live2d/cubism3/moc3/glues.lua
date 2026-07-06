-- MOC3 glue parser and deformation for Cubism 3
-- Ported from Mocari src/moc3/glues.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")

local glues = {}

local GLUE_BINDING_INDICES_SLOT = 91
local GLUE_KEYFORM_BEGIN_INDICES_SLOT = 92
local GLUE_KEYFORM_COUNTS_SLOT = 93
local GLUE_ART_MESH_INDICES_A_SLOT = 94
local GLUE_ART_MESH_INDICES_B_SLOT = 95
local GLUE_INFO_BEGIN_INDICES_SLOT = 96
local GLUE_INFO_COUNTS_SLOT = 97
local GLUE_INFO_WEIGHTS_SLOT = 98
local GLUE_INFO_POSITION_INDICES_SLOT = 99
local GLUE_KEYFORM_INTENSITIES_SLOT = 100

local function validate_range(begin_index, count, source_len, index, name)
    if begin_index < 0 or count < 0 then
        return nil, string.format("glue %d %s range is negative", index - 1, name)
    end
    local finish = begin_index + count
    if finish > source_len then
        return nil, string.format("glue %d %s range is outside section", index - 1, name)
    end
    return true
end

function glues.from_parts(
    binding_indices,
    keyform_begin_indices,
    keyform_counts,
    art_mesh_indices_a,
    art_mesh_indices_b,
    info_begin_indices,
    info_counts,
    info_weights,
    info_position_indices,
    keyform_intensities)

    local glue_count = #binding_indices
    if #keyform_begin_indices ~= glue_count
        or #keyform_counts ~= glue_count
        or #art_mesh_indices_a ~= glue_count
        or #art_mesh_indices_b ~= glue_count
        or #info_begin_indices ~= glue_count
        or #info_counts ~= glue_count
        or #info_weights ~= #info_position_indices then
        return nil, "glue metadata lengths do not match"
    end

    for i = 1, glue_count do
        local ok, err = validate_range(info_begin_indices[i], info_counts[i], #info_weights, i, "info")
        if not ok then return nil, err end
        ok, err = validate_range(keyform_begin_indices[i], keyform_counts[i], #keyform_intensities, i, "keyform")
        if not ok then return nil, err end
    end

    return setmetatable({
        binding_indices = binding_indices,
        keyform_begin_indices = keyform_begin_indices,
        keyform_counts = keyform_counts,
        art_mesh_indices_a = art_mesh_indices_a,
        art_mesh_indices_b = art_mesh_indices_b,
        info_begin_indices = info_begin_indices,
        info_counts = info_counts,
        info_weights = info_weights,
        info_position_indices = info_position_indices,
        keyform_intensities = keyform_intensities,
    }, { __index = glues })
end

function glues.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end

    local glue_count = parse.to_usize(cnts.glue, "glue count")
    local glue_info_count = parse.to_usize(cnts.glue_info, "glue info count")
    local glue_keyform_count = parse.to_usize(cnts.glue_keyforms, "glue keyform count")
    if glue_count == nil or glue_info_count == nil or glue_keyform_count == nil then
        return nil, "Invalid glue counts"
    end

    local binding_indices, err = parse.read_i32_section(bytes, offs, GLUE_BINDING_INDICES_SLOT, glue_count)
    if not binding_indices then return nil, err end
    local keyform_begin_indices, err = parse.read_i32_section(bytes, offs, GLUE_KEYFORM_BEGIN_INDICES_SLOT, glue_count)
    if not keyform_begin_indices then return nil, err end
    local keyform_counts, err = parse.read_i32_section(bytes, offs, GLUE_KEYFORM_COUNTS_SLOT, glue_count)
    if not keyform_counts then return nil, err end
    local art_mesh_indices_a, err = parse.read_i32_section(bytes, offs, GLUE_ART_MESH_INDICES_A_SLOT, glue_count)
    if not art_mesh_indices_a then return nil, err end
    local art_mesh_indices_b, err = parse.read_i32_section(bytes, offs, GLUE_ART_MESH_INDICES_B_SLOT, glue_count)
    if not art_mesh_indices_b then return nil, err end
    local info_begin_indices, err = parse.read_i32_section(bytes, offs, GLUE_INFO_BEGIN_INDICES_SLOT, glue_count)
    if not info_begin_indices then return nil, err end
    local info_counts, err = parse.read_i32_section(bytes, offs, GLUE_INFO_COUNTS_SLOT, glue_count)
    if not info_counts then return nil, err end
    local info_weights, err = parse.read_f32_section(bytes, offs, GLUE_INFO_WEIGHTS_SLOT, glue_info_count)
    if not info_weights then return nil, err end
    local info_position_indices, err = parse.read_u16_section(bytes, offs, GLUE_INFO_POSITION_INDICES_SLOT, glue_info_count)
    if not info_position_indices then return nil, err end
    local keyform_intensities, err = parse.read_f32_section(bytes, offs, GLUE_KEYFORM_INTENSITIES_SLOT, glue_keyform_count)
    if not keyform_intensities then return nil, err end

    return glues.from_parts(
        binding_indices,
        keyform_begin_indices,
        keyform_counts,
        art_mesh_indices_a,
        art_mesh_indices_b,
        info_begin_indices,
        info_counts,
        info_weights,
        info_position_indices,
        keyform_intensities
    )
end

function glues:len()
    return #self.binding_indices
end

function glues:is_empty()
    return #self.binding_indices == 0
end

local function mesh_pair(meshes, mesh_a_index, mesh_b_index)
    if mesh_a_index == mesh_b_index then return nil end
    local mesh_a = meshes[mesh_a_index + 1]
    local mesh_b = meshes[mesh_b_index + 1]
    if not mesh_a or not mesh_b then return nil end
    return mesh_a, mesh_b
end

local function ensure_position_arrays(mesh)
    if mesh.positions_x and mesh.positions_y then
        return mesh.positions_x, mesh.positions_y
    end
    local vertices = mesh.vertices
    if not vertices then return nil end
    local xs = {}
    local ys = {}
    for i = 1, #vertices do
        local vertex = vertices[i]
        local position = vertex and vertex.position
        if not position then return nil end
        xs[i] = position[1]
        ys[i] = position[2]
    end
    mesh.positions_x = xs
    mesh.positions_y = ys
    return xs, ys
end

local function apply_glue_to_mesh_pair(meshes, mesh_a_index, mesh_b_index, weights, position_indices, info_begin, info_count, intensity)
    local mesh_a, mesh_b = mesh_pair(meshes, mesh_a_index, mesh_b_index)
    if not mesh_a then return nil end
    local ax_values, ay_values = ensure_position_arrays(mesh_a)
    local bx_values, by_values = ensure_position_arrays(mesh_b)
    if not ax_values or not ay_values or not bx_values or not by_values then return nil end
    local vertices_a = mesh_a.vertices
    local vertices_b = mesh_b.vertices
    local vertex_data_a = mesh_a.vertex_data
    local vertex_data_b = mesh_b.vertex_data

    for offset = 0, info_count - 1, 2 do
        local source_a = info_begin + offset + 1
        local source_b = source_a + 1
        local index_a = position_indices[source_a]
        local index_b = position_indices[source_b]
        local array_index_a = index_a + 1
        local array_index_b = index_b + 1
        local ax, ay = ax_values[array_index_a], ay_values[array_index_a]
        local bx, by = bx_values[array_index_b], by_values[array_index_b]
        if ax == nil or ay == nil or bx == nil or by == nil then return nil end
        local weight_a = weights[source_a]
        local weight_b = weights[source_b]
        if weight_a == nil or weight_b == nil then return nil end

        local new_ax = ax + (bx - ax) * weight_a * intensity
        local new_ay = ay + (by - ay) * weight_a * intensity
        local new_bx = bx + (ax - bx) * weight_b * intensity
        local new_by = by + (ay - by) * weight_b * intensity
        ax_values[array_index_a], ay_values[array_index_a] = new_ax, new_ay
        bx_values[array_index_b], by_values[array_index_b] = new_bx, new_by

        local vertex_a = vertices_a[array_index_a]
        local vertex_b = vertices_b[array_index_b]
        if not vertex_a or not vertex_b then return nil end
        vertex_a.position[1], vertex_a.position[2] = new_ax, new_ay
        vertex_b.position[1], vertex_b.position[2] = new_bx, new_by

        if vertex_data_a then
            local off = index_a * 11
            vertex_data_a[off + 0] = new_ax
            vertex_data_a[off + 1] = new_ay
        end
        if vertex_data_b then
            local off = index_b * 11
            vertex_data_b[off + 0] = new_bx
            vertex_data_b[off + 1] = new_by
        end
    end

    return true
end

function glues:interpolate_intensity(index, bindings, parameter_values)
    local keyform_count = self.keyform_counts[index]
    if keyform_count == nil then return nil end
    local slots = bindings:keyform_slots(self.binding_indices[index], keyform_count, parameter_values)
    if not slots then return nil end

    local begin_index = self.keyform_begin_indices[index]
    if begin_index == nil or begin_index < 0 then return nil end

    local intensity = 0.0
    for _, slot in ipairs(slots) do
        local keyform_index = begin_index + slot.local_index + 1
        local keyform_intensity = self.keyform_intensities[keyform_index]
        if keyform_intensity == nil then return nil end
        intensity = intensity + keyform_intensity * slot.weight
    end
    return intensity
end

function glues:apply(meshes, bindings, parameter_values)
    for index = 1, self:len() do
        local info_count = self.info_counts[index]
        if info_count == nil or info_count < 0 then return nil end
        if info_count > 0 then
            if info_count % 2 ~= 0 then return nil end

            local mesh_a = self.art_mesh_indices_a[index]
            local mesh_b = self.art_mesh_indices_b[index]
            local intensity = self:interpolate_intensity(index, bindings, parameter_values)
            if mesh_a == nil or mesh_b == nil or intensity == nil then return nil end

            local info_begin = self.info_begin_indices[index]
            if info_begin == nil or info_begin < 0 then return nil end

            if not apply_glue_to_mesh_pair(
                meshes,
                mesh_a,
                mesh_b,
                self.info_weights,
                self.info_position_indices,
                info_begin,
                info_count,
                intensity
            ) then
                return nil
            end
        end
    end

    return true
end

return glues
