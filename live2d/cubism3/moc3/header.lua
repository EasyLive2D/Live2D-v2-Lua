-- MOC3 binary header parser for Cubism 3
-- Ported from Mocari src/moc3/header.rs

local header = {}

local HEADER_SIZE = 64
local MAGIC = { 77, 79, 67, 51 } -- "MOC3" bytes

-- Moc3Version
header.V3_0_0 = 1
header.V3_3_0 = 2
header.V4_0_0 = 3
header.V4_2_0 = 4
header.V5_0_0 = 5
header.V5_3_0 = 6

-- Endianness
header.LITTLE = 0
header.BIG = 1

-- Count info word count per version
local version_word_counts = {
    [header.V3_0_0] = 23,
    [header.V3_3_0] = 23,
    [header.V4_0_0] = 23,
    [header.V4_2_0] = 32,
    [header.V5_0_0] = 35,
    [header.V5_3_0] = 35,
}

function header.count_info_word_count(version)
    return version_word_counts[version] or 23
end

function header.parse(bytes)
    if #bytes < HEADER_SIZE then
        return nil, "MOC3 header is shorter than 64 bytes"
    end

    local b1, b2, b3, b4 = string.byte(bytes, 1, 4)
    if b1 ~= MAGIC[1] or b2 ~= MAGIC[2] or b3 ~= MAGIC[3] or b4 ~= MAGIC[4] then
        return nil, "MOC3 magic must be MOC3"
    end

    local version_byte = string.byte(bytes, 5)
    if version_byte < 1 or version_byte > 6 then
        return nil, "Unsupported MOC3 version: " .. version_byte
    end

    local endianness_byte = string.byte(bytes, 6)
    if endianness_byte ~= 0 and endianness_byte ~= 1 then
        return nil, "MOC3 endianness flag must be 0 or 1"
    end

    return {
        version = version_byte,
        endianness = endianness_byte,
    }
end

return header
