-- MOC3 ID string table parser for Cubism 3
-- Ported from Mocari src/moc3/ids.rs

local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")

local ids = {}

local STR64_SIZE = 64
local PART_IDS_SLOT = 3
local ART_MESH_IDS_SLOT = 33
local PARAMETER_IDS_SLOT = 50

local function read_str64_section(bytes, offs, slot, count)
    if count == 0 then
        return {}
    end
    local offset = offs:section_offset(slot)
    if offset == nil or offset == 0 then
        return nil, "section slot " .. slot .. " has no offset"
    end
    local byte_len = count * STR64_SIZE
    if #bytes < offset + byte_len then
        return nil, "section slot " .. slot .. " is incomplete"
    end
    local result = {}
    for i = 0, count - 1 do
        local start = offset + i * STR64_SIZE + 1
        local raw = string.sub(bytes, start, start + STR64_SIZE - 1)
        -- Find null terminator
        local null_pos = string.find(raw, "\0")
        if null_pos then
            raw = string.sub(raw, 1, null_pos - 1)
        end
        table.insert(result, raw)
    end
    return result
end

function ids.parse(bytes)
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end

    local parts_list, err = read_str64_section(bytes, offs, PART_IDS_SLOT, cnts.parts)
    if not parts_list then return nil, err end
    local art_meshes_list, err = read_str64_section(bytes, offs, ART_MESH_IDS_SLOT, cnts.art_meshes)
    if not art_meshes_list then return nil, err end
    local parameters_list, err = read_str64_section(bytes, offs, PARAMETER_IDS_SLOT, cnts.parameters)
    if not parameters_list then return nil, err end

    return {
        parts = parts_list,
        art_meshes = art_meshes_list,
        parameters = parameters_list,
    }
end

return ids
