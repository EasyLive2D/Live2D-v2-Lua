-- MOC3 parts parser for Cubism 3
-- Ported from Mocari src/moc3/parts.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")

local parts = {}

local PART_KEYFORM_BINDING_BAND_INDICES_SLOT = 4
local PART_KEYFORM_BEGIN_INDICES_SLOT = 5
local PART_KEYFORM_COUNTS_SLOT = 6
local PART_PARENT_PART_INDICES_SLOT = 9
local PART_KEYFORM_OPACITIES_SLOT = 59

function parts.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end

    local part_count = parse.to_usize(cnts.parts, "part count")
    local part_keyform_count = parse.to_usize(cnts.part_keyforms, "part keyform count")
    if not part_count then return nil, "Invalid part count" end
    if not part_keyform_count then part_keyform_count = 0 end
    local endianness = hdr.endianness

    local parent_part_indices, err = parse.read_i32_section(bytes, offs, PART_PARENT_PART_INDICES_SLOT, part_count)
    if not parent_part_indices then return nil, err end
    local kf_binding_band_indices, err = parse.read_i32_section(bytes, offs, PART_KEYFORM_BINDING_BAND_INDICES_SLOT, part_count)
    if not kf_binding_band_indices then return nil, err end
    local kf_begin_indices, err = parse.read_i32_section(bytes, offs, PART_KEYFORM_BEGIN_INDICES_SLOT, part_count)
    if not kf_begin_indices then return nil, err end
    local kf_counts, err = parse.read_i32_section(bytes, offs, PART_KEYFORM_COUNTS_SLOT, part_count)
    if not kf_counts then return nil, err end
    local kf_opacities
    if part_keyform_count > 0 then
        kf_opacities, err = parse.read_f32_section(bytes, offs, PART_KEYFORM_OPACITIES_SLOT, part_keyform_count)
        if not kf_opacities then return nil, err end
    else
        kf_opacities = {}
    end

    return setmetatable({
        parent_part_indices = parent_part_indices,
        keyform_binding_band_indices = kf_binding_band_indices,
        keyform_begin_indices = kf_begin_indices,
        keyform_counts = kf_counts,
        keyform_opacities = kf_opacities,
    }, { __index = parts })
end

function parts.part_count(self)
    return #self.parent_part_indices
end

function parts.parent_part_index(self, part_index)
    return self.parent_part_indices[part_index + 1]
end

function parts.interpolate_opacity(self, part_index, bindings, parameter_values)
    local kf_count = self.keyform_counts[part_index + 1]
    if kf_count == nil then
        return nil
    end
    if kf_count == 0 then
        return 1.0
    end
    local begin = self.keyform_begin_indices[part_index + 1]
    if begin == nil or begin < 0 then
        return nil
    end
    local band_index = self.keyform_binding_band_indices[part_index + 1]
    if band_index == nil then
        return nil
    end
    local slots = bindings:keyform_slots(band_index, kf_count, parameter_values)
    if not slots then
        return nil
    end
    local opacity = 0.0
    for _, slot in ipairs(slots) do
        local kf_idx = begin + slot.local_index
        if kf_idx + 1 > #self.keyform_opacities then
            return nil
        end
        opacity = opacity + self.keyform_opacities[kf_idx + 1] * slot.weight
    end
    return opacity
end

return parts
