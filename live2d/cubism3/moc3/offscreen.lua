-- MOC3 offscreen info parser for Cubism 3
-- Ported from Mocari src/moc3/offscreen.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")

local offscreen = {}

local PART_PARENT_PART_INDICES_SLOT = 9
local DRAWABLE_PARENT_PART_INDICES_SLOT = 39
local PART_OFFSCREEN_INDICES_SLOT = 149
local OFFSCREEN_OWNER_PART_INDICES_SLOT = 155
local EFFECT_PART_ID = "PartEffect"

function offscreen.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end

    local part_count = parse.to_usize(cnts.parts, "part count")
    local drawable_count = parse.to_usize(cnts.art_meshes, "art mesh count")
    if not part_count or not drawable_count then
        return nil, "Invalid counts"
    end

    local part_parent_indices, err = parse.read_i32_section(bytes, offs, PART_PARENT_PART_INDICES_SLOT, part_count)
    if not part_parent_indices then return nil, err end

    local drawable_parent_part_indices, err = parse.read_i32_section(bytes, offs, DRAWABLE_PARENT_PART_INDICES_SLOT, drawable_count)
    if not drawable_parent_part_indices then return nil, err end

    -- Part offscreen indices (only for V5_3_0)
    local part_offscreen_indices
    if hdr.version == header.V5_3_0 then
        part_offscreen_indices, err = parse.read_i32_section(bytes, offs, PART_OFFSCREEN_INDICES_SLOT, part_count)
        if not part_offscreen_indices then return nil, err end
    else
        part_offscreen_indices = {}
        for i = 1, part_count do
            part_offscreen_indices[i] = -1
        end
    end

    -- Compute offscreen count from max offscreen index
    local max_offscreen = -1
    for _, idx in ipairs(part_offscreen_indices) do
        if idx >= 0 and idx > max_offscreen then
            max_offscreen = idx
        end
    end

    local offscreen_count
    if max_offscreen >= 0 then
        offscreen_count = max_offscreen + 1
    else
        offscreen_count = 0
    end

    local offscreen_owner_part_indices
    if offscreen_count == 0 then
        offscreen_owner_part_indices = {}
    else
        offscreen_owner_part_indices, err = parse.read_i32_section(bytes, offs, OFFSCREEN_OWNER_PART_INDICES_SLOT, offscreen_count)
        if not offscreen_owner_part_indices then return nil, err end
    end

    return setmetatable({
        part_parent_indices = part_parent_indices,
        drawable_parent_part_indices = drawable_parent_part_indices,
        part_offscreen_indices = part_offscreen_indices,
        offscreen_owner_part_indices = offscreen_owner_part_indices,
    }, { __index = offscreen })
end

function offscreen.drawable_parent_part_index(self, drawable_index)
    return self.drawable_parent_part_indices[drawable_index + 1]
end

function offscreen.part_offscreen_indices_list(self)
    return self.part_offscreen_indices
end

function offscreen.offscreen_count(self)
    return #self.offscreen_owner_part_indices
end

-- Check if a part is descendant of an ancestor (by part index)
local function is_part_descendant_of(self, part_index, ancestor_index)
    local current = part_index
    local guard = 0
    while current >= 0 do
        if current >= #self.part_parent_indices then
            return false
        end
        if current == ancestor_index then
            return true
        end
        current = self.part_parent_indices[current + 1]
        guard = guard + 1
        if guard > #self.part_parent_indices then
            return false
        end
    end
    return false
end

function offscreen.effect_source_drawable_indices(self, ids)
    if self._effect_source_drawable_indices ~= nil then
        return self._effect_source_drawable_indices
    end

    if #self.offscreen_owner_part_indices == 0 then
        self._effect_source_drawable_indices = {}
        return self._effect_source_drawable_indices
    end

    local effect_part_index = nil
    for i, id in ipairs(ids.parts) do
        if id == EFFECT_PART_ID then
            effect_part_index = i - 1 -- 0-indexed
            break
        end
    end
    if effect_part_index == nil then
        self._effect_source_drawable_indices = {}
        return self._effect_source_drawable_indices
    end

    local result = {}
    for i = 0, #self.drawable_parent_part_indices - 1 do
        local parent_part = self.drawable_parent_part_indices[i + 1]
        if parent_part >= 0 then
            if is_part_descendant_of(self, parent_part, effect_part_index) then
                result[#result + 1] = i
            end
        end
    end
    self._effect_source_drawable_indices = result
    return result
end

return offscreen
