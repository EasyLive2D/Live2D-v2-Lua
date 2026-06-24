-- MOC3 drawable mesh construction for Cubism 3
-- Ported from Mocari src/moc3/drawable.rs

local draw_order_from_raw = require("live2d.cubism3.core.art_mesh").draw_order_from_raw

local bit = require("bit")
local band = bit.band

local drawable = {}

local DRAWABLE_BLEND_ADDITIVE = 1
local DRAWABLE_BLEND_MULTIPLICATIVE = 2
local DRAWABLE_MASK_INVERTED = 8

function drawable.blend_mode_from_flags(flags)
    if band(flags, DRAWABLE_BLEND_ADDITIVE) ~= 0 then
        return "additive"
    elseif band(flags, DRAWABLE_BLEND_MULTIPLICATIVE) ~= 0 then
        return "multiplicative"
    else
        return "normal"
    end
end

function drawable.is_inverted_mask(flags)
    return band(flags, DRAWABLE_MASK_INVERTED) ~= 0
end

-- Moc3DrawableVertex
function drawable.new_vertex(position, uv)
    return {
        position = position,  -- {x, y}
        uv = uv,              -- {u, v}
    }
end

local function build_moc3_drawable_mesh(art_meshes, keyforms, art_mesh_index, local_keyform_index)
    local mesh = art_meshes.meshes[art_mesh_index + 1]
    if not mesh then return nil end
    local kfs = keyforms:art_mesh_keyforms(art_mesh_index)
    if not kfs then return nil end
    local keyform = kfs[local_keyform_index + 1]
    if not keyform then return nil end
    local positions = keyforms:art_mesh_keyform_positions(art_mesh_index, local_keyform_index)
    if not positions then return nil end
    local uvs = art_meshes:art_mesh_uvs(art_mesh_index)
    if not uvs then return nil end
    if #positions ~= #uvs or #positions % 2 ~= 0 then
        return nil
    end

    local vertices = {}
    for i = 0, #positions / 2 - 1 do
        local positionIndex = i * 2 + 1
        vertices[#vertices + 1] = drawable.new_vertex(
            { positions[positionIndex], positions[positionIndex + 1] },
            { uvs[positionIndex], uvs[positionIndex + 1] }
        )
    end

    local indices = {}
    local pos_indices = art_meshes:art_mesh_position_indices(art_mesh_index)
    if not pos_indices then return nil end
    for _, pi in ipairs(pos_indices) do
        if pi < 0 or pi >= #vertices then
            return nil
        end
        indices[#indices + 1] = pi
    end

    local render_order = art_meshes:art_mesh_render_order(art_mesh_index) or art_mesh_index

    local masks = art_meshes:art_mesh_masks(art_mesh_index) or {}

    return {
        texture_index = mesh.texture_index,
        drawable_flags = mesh.drawable_flags,
        opacity = keyform.opacity,
        draw_order = keyform.draw_order,
        render_order = render_order,
        multiply_color = keyform.multiply_color or { 1, 1, 1 },
        screen_color = keyform.screen_color or { 0, 0, 0 },
        vertices = vertices,
        indices = indices,
        masks = masks,
    }
end

drawable.build_moc3_drawable_mesh = build_moc3_drawable_mesh

return drawable
