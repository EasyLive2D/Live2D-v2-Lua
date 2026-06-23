-- MOC3 art meshes parser for Cubism 3
-- Ported from Mocari src/moc3/art_meshes.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")

local art_meshes = {}

local ART_MESH_KEYFORM_BINDING_BAND_INDICES_SLOT = 34
local ART_MESH_PARENT_DEFORMER_INDICES_SLOT = 40
local TEXTURE_INDICES_SLOT = 41
local DRAWABLE_FLAGS_SLOT = 42
local VERTEX_COUNTS_SLOT = 43
local UV_BEGIN_INDICES_SLOT = 44
local POSITION_INDEX_BEGIN_INDICES_SLOT = 45
local POSITION_INDEX_COUNTS_SLOT = 46
local MASK_BEGIN_INDICES_SLOT = 47
local MASK_COUNTS_SLOT = 48
local UV_XYS_SLOT = 78
local POSITION_INDICES_SLOT = 79
local DRAWABLE_MASKS_SLOT = 80
local RENDER_ORDER_INDICES_SLOT = 87

function art_meshes.new_art_mesh_info(texture_index, drawable_flags, position_index_count, uv_begin_index, position_index_begin_index, vertex_count, mask_begin_index, mask_count)
    return {
        texture_index = texture_index,
        drawable_flags = drawable_flags,
        position_index_count = position_index_count,
        uv_begin_index = uv_begin_index,
        position_index_begin_index = position_index_begin_index,
        vertex_count = vertex_count,
        mask_begin_index = mask_begin_index,
        mask_count = mask_count,
    }
end

local function parse_render_orders(bytes, offs, cnts, art_mesh_count)
    local render_orders = {}
    for i = 0, art_mesh_count - 1 do
        render_orders[i + 1] = i
    end

    local object_count = parse.to_usize(cnts.draw_order_group_objects, "draw order group object count")
    if not object_count or object_count <= 0 then
        return render_orders
    end

    local off_val = offs:section_offset(RENDER_ORDER_INDICES_SLOT)
    if off_val == nil or off_val == 0 then
        return render_orders
    end

    local order_indices, err = parse.read_i32_section(bytes, offs, RENDER_ORDER_INDICES_SLOT, object_count)
    if not order_indices then return nil, err end

    for rank = 0, #order_indices - 1 do
        local drawable_index = order_indices[rank + 1]
        if drawable_index >= 0 and drawable_index < art_mesh_count then
            render_orders[drawable_index + 1] = rank
        end
    end
    return render_orders
end

function art_meshes.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end

    local art_mesh_count = parse.to_usize(cnts.art_meshes, "art mesh count")
    if not art_mesh_count then return nil, "Invalid art mesh count" end

    local render_orders, err = parse_render_orders(bytes, offs, cnts, art_mesh_count)
    if not render_orders then return nil, err end

    local kf_binding_band, err = parse.read_i32_section_or_default(bytes, offs, ART_MESH_KEYFORM_BINDING_BAND_INDICES_SLOT, art_mesh_count, 0)
    if not kf_binding_band then return nil, err end
    local texture_indices, err = parse.read_i32_section(bytes, offs, TEXTURE_INDICES_SLOT, art_mesh_count)
    if not texture_indices then return nil, err end
    local drawable_flags, err = parse.read_u8_section(bytes, offs, DRAWABLE_FLAGS_SLOT, art_mesh_count)
    if not drawable_flags then return nil, err end
    local vertex_counts, err = parse.read_i32_section(bytes, offs, VERTEX_COUNTS_SLOT, art_mesh_count)
    if not vertex_counts then return nil, err end
    local uv_begin_indices, err = parse.read_i32_section(bytes, offs, UV_BEGIN_INDICES_SLOT, art_mesh_count)
    if not uv_begin_indices then return nil, err end
    local pos_index_begin, err = parse.read_i32_section(bytes, offs, POSITION_INDEX_BEGIN_INDICES_SLOT, art_mesh_count)
    if not pos_index_begin then return nil, err end
    local pos_index_counts, err = parse.read_i32_section(bytes, offs, POSITION_INDEX_COUNTS_SLOT, art_mesh_count)
    if not pos_index_counts then return nil, err end
    local mask_begin_indices, err = parse.read_i32_section(bytes, offs, MASK_BEGIN_INDICES_SLOT, art_mesh_count)
    if not mask_begin_indices then return nil, err end
    local mask_counts, err = parse.read_i32_section(bytes, offs, MASK_COUNTS_SLOT, art_mesh_count)
    if not mask_counts then return nil, err end
    local parent_deformer, err = parse.read_i32_section_or_default(bytes, offs, ART_MESH_PARENT_DEFORMER_INDICES_SLOT, art_mesh_count, -1)
    if not parent_deformer then return nil, err end

    local uv_count = parse.to_usize(cnts.uvs, "uv count")
    local pos_idx_count = parse.to_usize(cnts.position_indices, "position index count")
    local mask_count = parse.to_usize(cnts.drawable_masks, "drawable mask count")

    local uv_xys, err = parse.read_f32_section(bytes, offs, UV_XYS_SLOT, uv_count)
    if not uv_xys then return nil, err end
    local position_indices, err = parse.read_i16_section(bytes, offs, POSITION_INDICES_SLOT, pos_idx_count)
    if not position_indices then return nil, err end
    local drawable_masks, err = parse.read_i32_section(bytes, offs, DRAWABLE_MASKS_SLOT, mask_count)
    if not drawable_masks then return nil, err end

    local meshes = {}
    for i = 0, art_mesh_count - 1 do
        table.insert(meshes, art_meshes.new_art_mesh_info(
            texture_indices[i + 1],
            drawable_flags[i + 1],
            pos_index_counts[i + 1],
            uv_begin_indices[i + 1],
            pos_index_begin[i + 1],
            vertex_counts[i + 1],
            mask_begin_indices[i + 1],
            mask_counts[i + 1]
        ))
    end

    return setmetatable({
        meshes = meshes,
        keyform_binding_band_indices = kf_binding_band,
        parent_deformer_indices = parent_deformer,
        render_orders = render_orders,
        uv_xys = uv_xys,
        position_indices = position_indices,
        drawable_masks = drawable_masks,
    }, { __index = art_meshes })
end

function art_meshes.art_mesh_uvs(self, index)
    local mesh = self.meshes[index + 1]
    if not mesh then return nil end
    local start = mesh.uv_begin_index
    if start < 0 then return nil end
    local count = mesh.vertex_count
    if count < 0 then return nil end
    local len = count * 2
    if start + len > #self.uv_xys then return nil end
    local result = {}
    for i = 1, len do
        result[i] = self.uv_xys[start + i]
    end
    return result
end

function art_meshes.art_mesh_position_indices(self, index)
    local mesh = self.meshes[index + 1]
    if not mesh then return nil end
    local start = mesh.position_index_begin_index
    if start < 0 then return nil end
    local count = mesh.position_index_count
    if count < 0 then return nil end
    if start + count > #self.position_indices then return nil end
    local result = {}
    for i = 1, count do
        result[i] = self.position_indices[start + i]
    end
    return result
end

function art_meshes.art_mesh_masks(self, index)
    local mesh = self.meshes[index + 1]
    if not mesh then return nil end
    local start = mesh.mask_begin_index
    if start < 0 then return nil end
    local count = mesh.mask_count
    if count < 0 then return nil end
    if start + count > #self.drawable_masks then return nil end
    local result = {}
    for i = 1, count do
        result[i] = self.drawable_masks[start + i]
    end
    return result
end

function art_meshes.art_mesh_keyform_binding_band_index(self, index)
    return self.keyform_binding_band_indices[index + 1]
end

function art_meshes.art_mesh_parent_deformer_index(self, index)
    return self.parent_deformer_indices[index + 1]
end

function art_meshes.art_mesh_render_order(self, index)
    return self.render_orders[index + 1]
end

return art_meshes
