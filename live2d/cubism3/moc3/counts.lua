-- MOC3 count info parser for Cubism 3
-- Ported from Mocari src/moc3/counts.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")

local counts = {}

local U32_SIZE = 4

-- Read u32 from bytes at offset with endianness
local function read_u32(bytes, offset, endianness)
    local b1, b2, b3, b4 = string.byte(bytes, offset + 1, offset + 4)
    if endianness == header.LITTLE then
        return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    else
        return b4 + b3 * 256 + b2 * 65536 + b1 * 16777216
    end
end

function counts.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then
        return nil, err
    end
    local offs, err = offsets.parse(bytes)
    if not offs then
        return nil, err
    end

    local offset = offs:count_info_offset()
    local word_count = header.count_info_word_count(hdr.version)
    local required_len = word_count * U32_SIZE

    if #bytes < offset + required_len then
        return nil, "MOC3 count info table is incomplete"
    end

    local read = function(index)
        return read_u32(bytes, offset + index * U32_SIZE, hdr.endianness)
    end

    return {
        parts = read(0),
        deformers = read(1),
        warp_deformers = read(2),
        rotation_deformers = read(3),
        art_meshes = read(4),
        parameters = read(5),
        part_keyforms = read(6),
        warp_deformer_keyforms = read(7),
        rotation_deformer_keyforms = read(8),
        art_mesh_keyforms = read(9),
        keyform_positions = read(10),
        parameter_binding_indices = read(11),
        keyform_bindings = read(12),
        parameter_bindings = read(13),
        keys = read(14),
        uvs = read(15),
        position_indices = read(16),
        drawable_masks = read(17),
        draw_order_groups = read(18),
        draw_order_group_objects = read(19),
        glue = read(20),
        glue_info = read(21),
        glue_keyforms = read(22),
    }
end

return counts
