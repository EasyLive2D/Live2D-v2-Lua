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
local ART_MESH_KEYFORM_COLOR_BEGIN_INDICES_SLOT = 107
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

    local color_begin_indices, err = parse.read_i32_section_or_default(
        bytes, offs, ART_MESH_KEYFORM_COLOR_BEGIN_INDICES_SLOT, art_mesh_count, -1
    )
    if not color_begin_indices then return nil, err end

    -- Read color channels (optional, default 1.0 for multiply, 0.0 for screen)
    local function read_color_channels(slots, count, default_val)
        local r = {}
        local g = {}
        local b = {}
        local rv, gv, bv
        rv, err = parse.read_f32_section_or_default(bytes, offs, slots[1], count, default_val)
        if not rv then return nil, err end
        gv, err = parse.read_f32_section_or_default(bytes, offs, slots[2], count, default_val)
        if not gv then return nil, err end
        bv, err = parse.read_f32_section_or_default(bytes, offs, slots[3], count, default_val)
        if not bv then return nil, err end
        return rv, gv, bv
    end

    local multiply_color_count = cnts.keyform_multiply_colors or 0
    local screen_color_count = cnts.keyform_screen_colors or 0
    local mult_r, mult_g, mult_b, err = read_color_channels(KEYFORM_MULTIPLY_COLOR_SLOTS, multiply_color_count, 1)
    if not mult_r then return nil, err end
    local scr_r, scr_g, scr_b, err = read_color_channels(KEYFORM_SCREEN_COLOR_SLOTS, screen_color_count, 0)
    if not scr_r then return nil, err end

    local kfs = {}
    for i = 0, art_mesh_kf_count - 1 do
        kfs[#kfs + 1] = keyforms.new_art_mesh_keyform_info_with_colors(
            opacities[i + 1],
            draw_orders[i + 1],
            pos_begin[i + 1],
            { 1, 1, 1 },
            { 0, 0, 0 }
        )
    end

    for mesh_index = 0, art_mesh_count - 1 do
        local keyform_begin = kf_begin_indices[mesh_index + 1]
        local keyform_count = kf_counts[mesh_index + 1]
        local color_begin = color_begin_indices[mesh_index + 1]
        if keyform_begin == nil or keyform_begin < 0 then return nil, "art mesh keyform begin index is negative" end
        if keyform_count == nil or keyform_count < 0 then return nil, "art mesh keyform count is negative" end
        if color_begin ~= nil and color_begin >= 0 then
            for local_index = 0, keyform_count - 1 do
                local keyform_index = keyform_begin + local_index
                local color_index = color_begin + local_index
                local keyform = kfs[keyform_index + 1]
                if keyform == nil then return nil, "art mesh keyform color index is outside keyforms" end
                keyform.multiply_color = {
                    mult_r[color_index + 1] or 1,
                    mult_g[color_index + 1] or 1,
                    mult_b[color_index + 1] or 1,
                }
                keyform.screen_color = {
                    scr_r[color_index + 1] or 0,
                    scr_g[color_index + 1] or 0,
                    scr_b[color_index + 1] or 0,
                }
            end
        end
    end

    return setmetatable({
        keyform_begin_indices = kf_begin_indices,
        keyform_counts = kf_counts,
        vertex_counts = vertex_counts,
        keyforms = kfs,
        position_xys = pos_xys,
        _art_mesh_keyforms_cache = {},
        _art_mesh_positions_cache = {},
    }, { __index = keyforms })
end

function keyforms.art_mesh_keyforms(self, mesh_index)
    local cache = self._art_mesh_keyforms_cache
    local cached = cache and cache[mesh_index + 1]
    if cached then return cached end

    local start = self.keyform_begin_indices[mesh_index + 1]
    if start == nil or start < 0 then return nil end
    local keyformCount = self.keyform_counts[mesh_index + 1]
    if keyformCount == nil or keyformCount < 0 then return nil end
    if start + keyformCount > #self.keyforms then return nil end
    local keyformData = {}
    for i = 1, keyformCount do
        keyformData[i] = self.keyforms[start + i]
    end
    if cache then cache[mesh_index + 1] = keyformData end
    return keyformData
end

function keyforms.art_mesh_keyform_positions(self, mesh_index, local_keyform_index)
    local mesh_cache = self._art_mesh_positions_cache and self._art_mesh_positions_cache[mesh_index + 1]
    if mesh_cache then
        local cached = mesh_cache[local_keyform_index + 1]
        if cached then return cached end
    end

    local kfs = keyforms.art_mesh_keyforms(self, mesh_index)
    if not kfs then return nil end
    local kf = kfs[local_keyform_index + 1]
    if not kf then return nil end
    local vertex_count = self.vertex_counts[mesh_index + 1]
    if vertex_count == nil or vertex_count < 0 then return nil end
    local start = kf.position_begin_index
    if start == nil or start < 0 then return nil end
    local positionArrayLength = vertex_count * 2
    if start + positionArrayLength > #self.position_xys then return nil end
    local positions = {}
    for i = 1, positionArrayLength do
        positions[i] = self.position_xys[start + i]
    end
    if self._art_mesh_positions_cache then
        mesh_cache = mesh_cache or {}
        self._art_mesh_positions_cache[mesh_index + 1] = mesh_cache
        mesh_cache[local_keyform_index + 1] = positions
    end
    return positions
end

return keyforms
