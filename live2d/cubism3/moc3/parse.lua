-- MOC3 binary section reading utilities for Cubism 3
-- Ported from Mocari src/moc3/parse.rs

local bit = require("bit")
local band, bor, brshift, blshift = bit.band, bit.bor, bit.rshift, bit.lshift
local header = require("live2d.cubism3.moc3.header")

local parse = {}

-- Read u32 from bytes at offset
local function read_u32(bytes, offset, endianness)
    local b1, b2, b3, b4 = string.byte(bytes, offset + 1, offset + 4)
    if endianness == header.LITTLE then
        return b1 + blshift(b2, 8) + blshift(b3, 16) + blshift(b4, 24)
    else
        return b4 + blshift(b3, 8) + blshift(b2, 16) + blshift(b1, 24)
    end
end

-- Read i32 from bytes at offset
local function read_i32(bytes, offset, endianness)
    local u = read_u32(bytes, offset, endianness)
    if u >= 2147483648 then
        return u - 4294967296
    end
    return u
end

-- Read i16 from bytes at offset
local function read_i16(bytes, offset, endianness)
    local b1, b2 = string.byte(bytes, offset + 1, offset + 2)
    local u
    if endianness == header.LITTLE then
        u = b1 + blshift(b2, 8)
    else
        u = b2 + blshift(b1, 8)
    end
    if u >= 32768 then
        return u - 65536
    end
    return u
end

-- Read f32 from bytes at offset
local function read_f32(bytes, offset, endianness)
    local u = read_u32(bytes, offset, endianness)
    -- IEEE 754 single-precision float from bits
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

function parse.read_section(bytes, offsets, slot, count, element_size, read_fn)
    if count == 0 then
        return {}
    end
    local offset = offsets:section_offset(slot)
    if offset == nil or offset == 0 then
        return nil, "section slot " .. slot .. " has no offset"
    end
    local byte_len = count * element_size
    if #bytes < offset + byte_len then
        return nil, "section slot " .. slot .. " is incomplete"
    end
    local values = {}
    for i = 0, count - 1 do
        table.insert(values, read_fn(bytes, offset + i * element_size))
    end
    return values
end

function parse.read_i32_section(bytes, offsets, slot, count)
    local endianness = offsets.endianness
    return parse.read_section(bytes, offsets, slot, count, 4, function(b, o) return read_i32(b, o, endianness) end)
end

function parse.read_i32_section_or_default(bytes, offsets, slot, count, default)
    local off = offsets:section_offset(slot)
    if off == nil or off == 0 then
        local values = {}
        for i = 1, count do
            values[i] = default
        end
        return values
    end
    return parse.read_i32_section(bytes, offsets, slot, count)
end

function parse.read_i16_section(bytes, offsets, slot, count)
    local endianness = offsets.endianness
    return parse.read_section(bytes, offsets, slot, count, 2, function(b, o) return read_i16(b, o, endianness) end)
end

function parse.read_f32_section(bytes, offsets, slot, count)
    local endianness = offsets.endianness
    return parse.read_section(bytes, offsets, slot, count, 4, function(b, o) return read_f32(b, o, endianness) end)
end

function parse.read_f32_section_or_default(bytes, offsets, slot, count, default)
    local off = offsets:section_offset(slot)
    if off == nil or off == 0 then
        local values = {}
        for i = 1, count do
            values[i] = default
        end
        return values
    end
    return parse.read_f32_section(bytes, offsets, slot, count)
end

function parse.read_u8_section(bytes, offsets, slot, count)
    return parse.read_section(bytes, offsets, slot, count, 1, function(b, o) return string.byte(b, o + 1) end)
end

function parse.read_bool_section(bytes, offsets, slot, count)
    local values, err = parse.read_i32_section(bytes, offsets, slot, count)
    if not values then return nil, err end
    local result = {}
    for i = 1, #values do
        result[i] = (values[i] == 1)
    end
    return result
end

function parse.to_usize(value, name)
    if value < 0 then
        return nil, name .. " is negative"
    end
    return math.floor(value)
end

return parse
