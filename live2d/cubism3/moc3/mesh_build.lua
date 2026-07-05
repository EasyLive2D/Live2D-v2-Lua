-- MOC3 mesh build pipeline for Cubism 3
-- Ported from Mocari src/moc3/mesh_build.rs

local ffi = require("ffi")
local deformers_mod = require("live2d.cubism3.moc3.deformers")

local mesh_build = {}
local IDENTITY_MULTIPLY = { 1, 1, 1 }
local ZERO_SCREEN = { 0, 0, 0 }

local function static_drawable_mesh(art_meshes, art_mesh_index, vertex_count)
    local cache = art_meshes._static_drawable_meshes
    if not cache then
        cache = {}
        art_meshes._static_drawable_meshes = cache
    end

    local cached = cache[art_mesh_index + 1]
    if cached then return cached end

    local mesh = art_meshes.meshes[art_mesh_index + 1]
    if not mesh then return nil end

    local uvs = art_meshes:art_mesh_uvs(art_mesh_index)
    if not uvs or #uvs ~= vertex_count * 2 then return nil end

    local indices = art_meshes:art_mesh_position_indices(art_mesh_index)
    if not indices then return nil end
    for _, pi in ipairs(indices) do
        if pi < 0 or pi >= vertex_count then
            return nil
        end
    end

    local index_data = ffi.new("uint16_t[?]", #indices)
    for i = 1, #indices do
        index_data[i - 1] = indices[i]
    end

    cached = {
        texture_index = mesh.texture_index,
        drawable_flags = mesh.drawable_flags,
        render_order = art_meshes:art_mesh_render_order(art_mesh_index) or art_mesh_index,
        uvs = uvs,
        indices = indices,
        index_data = index_data,
        masks = art_meshes:art_mesh_masks(art_mesh_index) or {},
    }
    cache[art_mesh_index + 1] = cached
    return cached
end

local function clamp01(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function combine_multiply_color(local_color, parent_color)
    local_color[1] = clamp01((local_color[1] or 1) * (parent_color[1] or 1))
    local_color[2] = clamp01((local_color[2] or 1) * (parent_color[2] or 1))
    local_color[3] = clamp01((local_color[3] or 1) * (parent_color[3] or 1))
    return local_color
end

local function combine_screen_color(local_color, parent_color)
    local r = (local_color[1] or 0) + (parent_color[1] or 0) - (local_color[1] or 0) * (parent_color[1] or 0)
    local g = (local_color[2] or 0) + (parent_color[2] or 0) - (local_color[2] or 0) * (parent_color[2] or 0)
    local b = (local_color[3] or 0) + (parent_color[3] or 0) - (local_color[3] or 0) * (parent_color[3] or 0)
    local_color[1] = clamp01(r)
    local_color[2] = clamp01(g)
    local_color[3] = clamp01(b)
    return local_color
end

local function parent_deformer_colors(composed, parent_index)
    if not composed or parent_index == nil or parent_index < 0 then
        return IDENTITY_MULTIPLY, ZERO_SCREEN
    end
    local def = composed[parent_index + 1]
    if not def then return IDENTITY_MULTIPLY, ZERO_SCREEN end
    return def.multiply_color or IDENTITY_MULTIPLY, def.screen_color or ZERO_SCREEN
end

local function build_moc3_drawable_mesh_for_pose(art_meshes, art_mesh_keyforms, composed, bindings, parameter_values, art_mesh_index, out_mesh)
    local kfs = art_mesh_keyforms:art_mesh_keyforms(art_mesh_index)
    if not kfs then return nil end
    local band_index = art_meshes:art_mesh_keyform_binding_band_index(art_mesh_index)
    if band_index == nil then return nil end
    local slots = bindings:keyform_slots(band_index, #kfs, parameter_values)
    if not slots or #slots == 0 then return nil end

    local parent_deformer_index = art_meshes:art_mesh_keyform_binding_band_index(art_mesh_index) or -1
    -- Actually parent_deformer_index comes from art_meshes
    local def_parent = art_meshes:art_mesh_parent_deformer_index(art_mesh_index) or -1

    -- Interpolate opacity
    local opacity = 0.0
    for _, slot in ipairs(slots) do
        local kfs_list = art_mesh_keyforms:art_mesh_keyforms(art_mesh_index)
        if kfs_list and kfs_list[slot.local_index + 1] then
            opacity = opacity + kfs_list[slot.local_index + 1].opacity * slot.weight
        end
    end

    -- Deformer opacity accumulation
    if composed and def_parent >= 0 then
        local def = composed[def_parent + 1]
        if def then
            local def_opacity = 1.0
            if def.kind == "warp" then def_opacity = def.opacity_accum
            elseif def.kind == "rotation" then def_opacity = def.opacity_accum end
            opacity = opacity * def_opacity
        end
    end

    -- Interpolate draw order
    local draw_order = 0.0
    for _, slot in ipairs(slots) do
        local kfs_list = art_mesh_keyforms:art_mesh_keyforms(art_mesh_index)
        if kfs_list and kfs_list[slot.local_index + 1] then
            draw_order = draw_order + kfs_list[slot.local_index + 1].draw_order * slot.weight
        end
    end

    -- Interpolate colors
    out_mesh = out_mesh or {}
    local multiply_color = out_mesh.multiply_color or { 0, 0, 0 }
    local screen_color = out_mesh.screen_color or { 0, 0, 0 }
    multiply_color[1], multiply_color[2], multiply_color[3] = 0, 0, 0
    screen_color[1], screen_color[2], screen_color[3] = 0, 0, 0
    for _, slot in ipairs(slots) do
        local kfs_list = art_mesh_keyforms:art_mesh_keyforms(art_mesh_index)
        if kfs_list and kfs_list[slot.local_index + 1] then
            local multiplyColor = kfs_list[slot.local_index + 1].multiply_color
            local screenColor = kfs_list[slot.local_index + 1].screen_color
            if multiplyColor then
                multiply_color[1] = multiply_color[1] + multiplyColor[1] * slot.weight
                multiply_color[2] = multiply_color[2] + multiplyColor[2] * slot.weight
                multiply_color[3] = multiply_color[3] + multiplyColor[3] * slot.weight
            end
            if screenColor then
                screen_color[1] = screen_color[1] + screenColor[1] * slot.weight
                screen_color[2] = screen_color[2] + screenColor[2] * slot.weight
                screen_color[3] = screen_color[3] + screenColor[3] * slot.weight
            end
        end
    end
    local parent_multiply, parent_screen = parent_deformer_colors(composed, def_parent)
    multiply_color = combine_multiply_color(multiply_color, parent_multiply)
    screen_color = combine_screen_color(screen_color, parent_screen)

    -- Interpolate positions
    local first_kf = art_mesh_keyforms:art_mesh_keyform_positions(art_mesh_index, slots[1].local_index)
    if not first_kf or #first_kf % 2 ~= 0 then return nil end
    local vertex_count = #first_kf / 2
    local static_mesh = static_drawable_mesh(art_meshes, art_mesh_index, vertex_count)
    if not static_mesh then return nil end
    local positions_x = static_mesh.positions_x or {}
    local positions_y = static_mesh.positions_y or {}
    static_mesh.positions_x = positions_x
    static_mesh.positions_y = positions_y
    for i = 1, vertex_count do
        positions_x[i] = 0
        positions_y[i] = 0
    end

    for _, slot in ipairs(slots) do
        local kf_pos = art_mesh_keyforms:art_mesh_keyform_positions(art_mesh_index, slot.local_index)
        if not kf_pos or #kf_pos ~= #first_kf then return nil end
        for i = 0, vertex_count - 1 do
            local positionIndex = i + 1
            positions_x[positionIndex] = positions_x[positionIndex] + kf_pos[i * 2 + 1] * slot.weight
            positions_y[positionIndex] = positions_y[positionIndex] + kf_pos[i * 2 + 2] * slot.weight
        end
    end

    -- Apply deformer transforms to positions
    if composed and def_parent >= 0 then
        local def = composed[def_parent + 1]
        if def then
            for i = 1, vertex_count do
                local x, y = deformers_mod.apply_one_xy(def, positions_x[i], positions_y[i])
                if not x then return nil end
                positions_x[i] = x
                positions_y[i] = y
            end
        end
    end

    -- Build final vertices: position from deformer, UV from cached static mesh, flip Y
    local final_vertices = out_mesh.vertices or {}
    local uvs = static_mesh.uvs
    local vertex_float_count = vertex_count * 11
    local vertex_data = out_mesh.vertex_data
    if not vertex_data or (out_mesh.vertex_capacity or 0) < vertex_float_count then
        vertex_data = ffi.new("float[?]", vertex_float_count)
        out_mesh.vertex_data = vertex_data
        out_mesh.vertex_capacity = vertex_float_count
    end
    for i = 1, vertex_count do
        local uvIndex = (i - 1) * 2 + 1
        local x = positions_x[i]
        local y = -positions_y[i]
        local u = uvs[uvIndex]
        local v = uvs[uvIndex + 1]
        local vertex = final_vertices[i]
        if vertex then
            local position = vertex.position
            position[1] = x
            position[2] = y
        else
            vertex = {
                position = { x, y },
                uv = { u, v },
            }
            final_vertices[i] = vertex
        end
        local off = (i - 1) * 11
        vertex_data[off + 0] = x
        vertex_data[off + 1] = y
        vertex_data[off + 2] = u
        vertex_data[off + 3] = v
        vertex_data[off + 4] = opacity
        vertex_data[off + 5] = multiply_color[1]
        vertex_data[off + 6] = multiply_color[2]
        vertex_data[off + 7] = multiply_color[3]
        vertex_data[off + 8] = screen_color[1]
        vertex_data[off + 9] = screen_color[2]
        vertex_data[off + 10] = screen_color[3]
    end

    out_mesh.texture_index = static_mesh.texture_index
    out_mesh.drawable_flags = static_mesh.drawable_flags
    out_mesh.opacity = opacity
    out_mesh.draw_order = draw_order
    out_mesh.render_order = static_mesh.render_order
    out_mesh.multiply_color = multiply_color
    out_mesh.screen_color = screen_color
    out_mesh.vertices = final_vertices
    out_mesh.indices = static_mesh.indices
    out_mesh.index_data = static_mesh.index_data
    out_mesh.vertex_float_count = vertex_float_count
    out_mesh._flat_opacity = opacity
    out_mesh._flat_multiply_r = multiply_color[1]
    out_mesh._flat_multiply_g = multiply_color[2]
    out_mesh._flat_multiply_b = multiply_color[3]
    out_mesh._flat_screen_r = screen_color[1]
    out_mesh._flat_screen_g = screen_color[2]
    out_mesh._flat_screen_b = screen_color[3]
    out_mesh.masks = static_mesh.masks
    return out_mesh
end

function mesh_build.build_moc3_drawable_meshes_with_parameters(art_meshes, art_mesh_keyforms, deformers, bindings, parameter_values, out_meshes, out_composed)
    local composed = deformers:compose(bindings, parameter_values, out_composed)
    if not composed then return nil end

    local meshes = out_meshes or {}
    local mesh_count = #art_meshes.meshes
    for i = 0, mesh_count - 1 do
        local m = build_moc3_drawable_mesh_for_pose(
            art_meshes, art_mesh_keyforms, composed, bindings, parameter_values, i, meshes[i + 1]
        )
        if not m then return nil end
        meshes[i + 1] = m
    end
    for i = mesh_count + 1, #meshes do
        meshes[i] = nil
    end
    return meshes
end

function mesh_build.build_moc3_drawable_meshes_with_parameters_offscreen_and_part_opacities(
    art_meshes, art_mesh_keyforms, deformers, bindings, ids, offscreen, parameter_values, drawable_part_opacities, out_meshes, out_composed)
    local meshes = mesh_build.build_moc3_drawable_meshes_with_parameters(
        art_meshes, art_mesh_keyforms, deformers, bindings, parameter_values, out_meshes, out_composed
    )
    if not meshes then return nil end

    -- Apply part opacities
    for i = 1, #meshes do
        local part_opacity = 1.0
        if drawable_part_opacities and drawable_part_opacities[i] then
            part_opacity = drawable_part_opacities[i]
        end
        meshes[i].opacity = meshes[i].opacity * part_opacity
    end

    -- Zero out effect source drawables
    local effect_indices = offscreen:effect_source_drawable_indices(ids)
    for _, idx in ipairs(effect_indices) do
        if meshes[idx + 1] then
            meshes[idx + 1].opacity = 0.0
        end
    end

    return meshes
end

function mesh_build.build_moc3_drawable_meshes_for_default_pose(art_meshes, art_mesh_keyforms, deformers, bindings)
    return mesh_build.build_moc3_drawable_meshes_with_parameters(
        art_meshes, art_mesh_keyforms, deformers, bindings,
        bindings.parameter_default_values
    )
end

return mesh_build
