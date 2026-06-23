-- MOC3 canvas info parser for Cubism 3
-- Ported from Mocari src/moc3/canvas.rs

local bit = require("bit")
local band, brshift = bit.band, bit.rshift
local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")

local canvas = {}

local CANVAS_INFO_SIZE = 64
local F32_SIZE = 4

-- Read f32 from bytes
local function read_f32(bytes, offset, endianness)
    local b1, b2, b3, b4 = string.byte(bytes, offset + 1, offset + 4)
    local u
    if endianness == header.LITTLE then
        u = b1 + bit.lshift(b2, 8) + bit.lshift(b3, 16) + bit.lshift(b4, 24)
    else
        u = b4 + bit.lshift(b3, 8) + bit.lshift(b2, 16) + bit.lshift(b1, 24)
    end
    if u == 0 then return 0.0 end
    local sign = band(brshift(u, 31), 1)
    local exponent = band(brshift(u, 23), 0xFF) - 127
    local mantissa = band(u, 0x7FFFFF) / 0x800000 + 1
    if exponent == -127 then
        mantissa = band(u, 0x7FFFFF) / 0x800000
        exponent = -126
    end
    local value = mantissa * (2 ^ exponent)
    if sign == 1 then value = -value end
    return value
end

function canvas.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end

    local offset = offs:canvas_info_offset()
    if #bytes < offset + CANVAS_INFO_SIZE then
        return nil, "MOC3 canvas info is incomplete"
    end

    return {
        pixels_per_unit = read_f32(bytes, offset, hdr.endianness),
        origin_x = read_f32(bytes, offset + F32_SIZE, hdr.endianness),
        origin_y = read_f32(bytes, offset + F32_SIZE * 2, hdr.endianness),
        width = read_f32(bytes, offset + F32_SIZE * 3, hdr.endianness),
        height = read_f32(bytes, offset + F32_SIZE * 4, hdr.endianness),
        flags = string.byte(bytes, offset + F32_SIZE * 5 + 1),
    }
end

function canvas.reverse_y_coordinate(self)
    return band(self.flags, 1) == 1
end

return canvas
