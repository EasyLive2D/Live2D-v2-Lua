-- MOC3 art mesh keyforms parser for Cubism 3
-- Ported from Mocari src/moc3/keyforms.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")

local keyforms = {}

local KEYFORM_BEGIN_INDICES_SLOT = 35
local KEYFORM_COUNTS_SLOT = 36
local VERTEX_COUNTS_SLOT = 43
local ART_MESH_KEYFORM_OPACITIES_SLOT = 68
local ART_MESH_KEYFORM_DRAW_ORDERS_SLOT = 69
local KEYFORM_POSITION_BEGIN_INDICES_SLOT = 70
local KEYFORM_POSITION_XYS_SLOT = 71
local KEYFORM_MULTIPLY_COLOR_SLOTS = { 108, 109, 110 }
local KEYFORM_SCREEN_COLOR_SLOTS = { 111, 112, 113 }

function keyforms.new_art_mesh_keyform_info(opacity, draw_order, position_begin_index)
    return {
        opacity = opacity,
        draw_order = draw_order,
        position_begin_index = position_begin_index,
        multiply_color = { 1, 1, 1 },
        screen_color = { 0, 0, 0 },
    }
end

function keyforms.new_art_mesh_keyform_info_with_colors(opacity, draw_order, position_begin_index, multiply_color, screen_color)
    return {
        opacity = opacity,
        draw_order = draw_order,
        position_begin_index = position_begin_index,
        multiply_color = multiply_color,
        screen_color = screen_color,
    }
end

function keyforms.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end

    local art_mesh_count = parse.to_usize(cnts.art_meshes, "art mesh count")
    local art_mesh_kf_count = parse.to_usize(cnts.art_mesh_keyforms, "art mesh keyform count")
    if not art_mesh_count or not art_mesh_kf_count then
        return nil, "Invalid counts"
    end

    local kf_begin_indices, err = parse.read_i32_section(bytes, offs, KEYFORM_BEGIN_INDICES_SLOT, art_mesh_count)
    if not kf_begin_indices then return nil, err end
    local kf_counts, err = parse.read_i32_section(bytes, offs, KEYFORM_COUNTS_SLOT, art_mesh_count)
    if not kf_counts then return nil, err end
    local vertex_counts, err = parse.read_i32_section(bytes, offs, VERTEX_COUNTS_SLOT, art_mesh_count)
    if not vertex_counts then return nil, err end

    local opacities, err = parse.read_f32_section(bytes, offs, ART_MESH_KEYFORM_OPACITIES_SLOT, art_mesh_kf_count)
    if not opacities then return nil, err end
    local draw_orders, err = parse.read_f32_section(bytes, offs, ART_MESH_KEYFORM_DRAW_ORDERS_SLOT, art_mesh_kf_count)
    if not draw_orders then return nil, err end
    local pos_begin, err = parse.read_i32_section(bytes, offs, KEYFORM_POSITION_BEGIN_INDICES_SLOT, art_mesh_kf_count)
    if not pos_begin then return nil, err end

    local kf_pos_count = parse.to_usize(cnts.keyform_positions, "keyform position count")
    local pos_xys, err = parse.read_f32_section(bytes, offs, KEYFORM_POSITION_XYS_SLOT, kf_pos_count)
    if not pos_xys then return nil, err end

    -- Read color channels (optional, default 1.0 for multiply, 0.0 for screen)
    local function read_color_channels(slots, default_val)
        local r = {}
        local g = {}
        local b = {}
        local rv, gv, bv
        rv, err = parse.read_f32_section_or_default(bytes, offs, slots[1], art_mesh_kf_count, default_val)
        if not rv then return nil, err end
        gv, err = parse.read_f32_section_or_default(bytes, offs, slots[2], art_mesh_kf_count, default_val)
        if not gv then return nil, err end
        bv, err = parse.read_f32_section_or_default(bytes, offs, slots[3], art_mesh_kf_count, default_val)
        if not bv then return nil, err end
        return rv, gv, bv
    end

    local mult_r, mult_g, mult_b, err = read_color_channels(KEYFORM_MULTIPLY_COLOR_SLOTS, 1)
    if not mult_r then return nil, err end
    local scr_r, scr_g, scr_b, err = read_color_channels(KEYFORM_SCREEN_COLOR_SLOTS, 0)
    if not scr_r then return nil, err end

    local kfs = {}
    for i = 0, art_mesh_kf_count - 1 do
        table.insert(kfs, keyforms.new_art_mesh_keyform_info_with_colors(
            opacities[i + 1],
            draw_orders[i + 1],
            pos_begin[i + 1],
            { mult_r[i + 1], mult_g[i + 1], mult_b[i + 1] },
            { scr_r[i + 1], scr_g[i + 1], scr_b[i + 1] }
        ))
    end

    return setmetatable({
        keyform_begin_indices = kf_begin_indices,
        keyform_counts = kf_counts,
        vertex_counts = vertex_counts,
        keyforms = kfs,
        position_xys = pos_xys,
    }, { __index = keyforms })
end

function keyforms.art_mesh_keyforms(self, mesh_index)
    local start = self.keyform_begin_indices[mesh_index + 1]
    if start == nil or start < 0 then return nil end
    local len = self.keyform_counts[mesh_index + 1]
    if len == nil or len < 0 then return nil end
    if start + len > #self.keyforms then return nil end
    local result = {}
    for i = 1, len do
        result[i] = self.keyforms[start + i]
    end
    return result
end

function keyforms.art_mesh_keyform_positions(self, mesh_index, local_keyform_index)
    local kfs = keyforms.art_mesh_keyforms(self, mesh_index)
    if not kfs then return nil end
    local kf = kfs[local_keyform_index + 1]
    if not kf then return nil end
    local vertex_count = self.vertex_counts[mesh_index + 1]
    if vertex_count == nil or vertex_count < 0 then return nil end
    local start = kf.position_begin_index
    if start == nil or start < 0 then return nil end
    local len = vertex_count * 2
    if start + len > #self.position_xys then return nil end
    local result = {}
    for i = 1, len do
        result[i] = self.position_xys[start + i]
    end
    return result
end

return keyforms
