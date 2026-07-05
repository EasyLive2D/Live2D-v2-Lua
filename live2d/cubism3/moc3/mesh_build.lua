-- MOC3 mesh build pipeline for Cubism 3
-- Ported from Mocari src/moc3/mesh_build.rs

local Vector2 = require("live2d.cubism3.core.math").Vector2
local drawable = require("live2d.cubism3.moc3.drawable")
local deformers_mod = require("live2d.cubism3.moc3.deformers")

local new_vertex = drawable.new_vertex

local mesh_build = {}

local function clamp01(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function combine_multiply_color(local_color, parent_color)
    return {
        clamp01((local_color[1] or 1) * (parent_color[1] or 1)),
        clamp01((local_color[2] or 1) * (parent_color[2] or 1)),
        clamp01((local_color[3] or 1) * (parent_color[3] or 1)),
    }
end

local function combine_screen_color(local_color, parent_color)
    local r = (local_color[1] or 0) + (parent_color[1] or 0) - (local_color[1] or 0) * (parent_color[1] or 0)
    local g = (local_color[2] or 0) + (parent_color[2] or 0) - (local_color[2] or 0) * (parent_color[2] or 0)
    local b = (local_color[3] or 0) + (parent_color[3] or 0) - (local_color[3] or 0) * (parent_color[3] or 0)
    return { clamp01(r), clamp01(g), clamp01(b) }
end

local function parent_deformer_colors(composed, parent_index)
    if not composed or parent_index == nil or parent_index < 0 then
        return { 1, 1, 1 }, { 0, 0, 0 }
    end
    local def = composed[parent_index + 1]
    if not def then return { 1, 1, 1 }, { 0, 0, 0 } end
    return def.multiply_color or { 1, 1, 1 }, def.screen_color or { 0, 0, 0 }
end

local function build_moc3_drawable_mesh_for_pose(art_meshes, art_mesh_keyforms, composed, bindings, parameter_values, art_mesh_index)
    local kfs = art_mesh_keyforms:art_mesh_keyforms(art_mesh_index)
    if not kfs then return nil end
    local band_index = art_meshes:art_mesh_keyform_binding_band_index(art_mesh_index)
    if band_index == nil then return nil end
    local slots = bindings:keyform_slots(band_index, #kfs, parameter_values)
    if not slots or #slots == 0 then return nil end

    local base_local_index = slots[1].local_index
    local mesh = drawable.build_moc3_drawable_mesh(art_meshes, art_mesh_keyforms, art_mesh_index, base_local_index)
    if not mesh then return nil end

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
    local multiply_color = { 0, 0, 0 }
    local screen_color = { 0, 0, 0 }
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
    local positions_x = {}
    local positions_y = {}
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
                local deformedPosition = deformers_mod.apply_one(def, Vector2.new(positions_x[i], positions_y[i]))
                if not deformedPosition then return nil end
                positions_x[i] = deformedPosition:x()
                positions_y[i] = deformedPosition:y()
            end
        end
    end

    -- Build final vertices: position from deformer, UV from base mesh, flip Y
    local final_vertices = {}
    for i = 1, #mesh.vertices do
        local vertex = mesh.vertices[i]
        final_vertices[i] = new_vertex(
            { positions_x[i], -positions_y[i] },
            vertex.uv
        )
    end

    return {
        texture_index = mesh.texture_index,
        drawable_flags = mesh.drawable_flags,
        opacity = opacity,
        draw_order = draw_order,
        render_order = mesh.render_order,
        multiply_color = multiply_color,
        screen_color = screen_color,
        vertices = final_vertices,
        indices = mesh.indices,
        masks = mesh.masks,
    }
end

function mesh_build.build_moc3_drawable_meshes_with_parameters(art_meshes, art_mesh_keyforms, deformers, bindings, parameter_values)
    local composed = deformers:compose(bindings, parameter_values)
    if not composed then return nil end

    local meshes = {}
    local mesh_count = #art_meshes.meshes
    for i = 0, mesh_count - 1 do
        local m = build_moc3_drawable_mesh_for_pose(
            art_meshes, art_mesh_keyforms, composed, bindings, parameter_values, i
        )
        if not m then return nil end
        meshes[#meshes + 1] = m
    end
    return meshes
end

function mesh_build.build_moc3_drawable_meshes_with_parameters_offscreen_and_part_opacities(
    art_meshes, art_mesh_keyforms, deformers, bindings, ids, offscreen, parameter_values, drawable_part_opacities)
    local meshes = mesh_build.build_moc3_drawable_meshes_with_parameters(
        art_meshes, art_mesh_keyforms, deformers, bindings, parameter_values
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
