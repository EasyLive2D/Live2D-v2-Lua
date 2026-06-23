-- MOC3 section offsets parser for Cubism 3
-- Ported from Mocari src/moc3/offsets.rs

local bit = require("bit")
local blshift = bit.lshift
local header_parser = require("live2d.cubism3.moc3.header")

local OFFSET_TABLE_START = 64
local OFFSET_COUNT = 160
local U32_SIZE = 4

local offset_methods = {}

function offset_methods:count_info_offset()
    return self.offsets[0]
end

function offset_methods:canvas_info_offset()
    return self.offsets[1]
end

function offset_methods:section_offset(index)
    if index >= 0 and index < OFFSET_COUNT then
        return self.offsets[index]
    end
    return nil
end

local M = setmetatable({}, { __index = offset_methods })

function M.parse(bytes)
    local hdr, err = header_parser.parse(bytes)
    if not hdr then
        return nil, err
    end

    local table_len = OFFSET_COUNT * U32_SIZE
    if #bytes < OFFSET_TABLE_START + table_len then
        return nil, "MOC3 section offset table is incomplete"
    end

    local section_offsets = {}
    for i = 0, OFFSET_COUNT - 1 do
        local offset = OFFSET_TABLE_START + i * U32_SIZE
        local b1, b2, b3, b4 = string.byte(bytes, offset + 1, offset + 4)
        local u
        if hdr.endianness == header_parser.LITTLE then
            u = b1 + blshift(b2, 8) + blshift(b3, 16) + blshift(b4, 24)
        else
            u = b4 + blshift(b3, 8) + blshift(b2, 16) + blshift(b1, 24)
        end
        section_offsets[i] = u
    end

    local self = setmetatable({
        offsets = section_offsets,
        endianness = hdr.endianness,
        version = hdr.version,
    }, { __index = offset_methods })

    return self
end

return M
