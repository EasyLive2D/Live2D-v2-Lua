-- MOC3 keyform bindings parser for Cubism 3
-- Ported from Mocari src/moc3/keyform_bindings.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")
local keyform_bindings = {}
local SINGLE_SLOT = { { local_index = 0, weight = 1.0 } }

local PARAMETER_MAX_VALUES_SLOT = 51
local PARAMETER_MIN_VALUES_SLOT = 52
local PARAMETER_DEFAULT_VALUES_SLOT = 53
local PARAMETER_BINDING_BEGIN_INDICES_SLOT = 56
local KEYFORM_BINDING_INDICES_SLOT = 72
local KEYFORM_BINDING_BAND_BEGIN_INDICES_SLOT = 73
local KEYFORM_BINDING_BAND_COUNTS_SLOT = 74
local KEYFORM_BINDING_KEYS_BEGIN_INDICES_SLOT = 75
local KEYFORM_BINDING_KEYS_COUNTS_SLOT = 76
local KEY_VALUES_SLOT = 77

local function expand_binding_parameter_indices(begin_indices, binding_count)
    local sources = {}
    for i = 1, binding_count do
        sources[i] = nil -- None
    end

    for param_index = 1, #begin_indices do
        local begin_val = begin_indices[param_index]
        if begin_val >= 0 then
            local begin_i = begin_val + 1 -- 1-indexed
            if begin_i <= binding_count then
                -- Find end: next strictly greater begin index
                local end_i = binding_count + 1
                for k = param_index + 1, #begin_indices do
                    local next_val = begin_indices[k]
                    if next_val >= 0 and next_val + 1 > begin_i then
                        end_i = next_val + 1
                        break
                    end
                end
                for slot = begin_i, end_i - 1 do
                    if sources[slot] == nil then
                        sources[slot] = param_index - 1 -- 0-indexed parameter index
                    end
                end
            end
        end
    end

    return sources
end

function keyform_bindings.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end
    local endianness = hdr.endianness

    local parameter_count = parse.to_usize(cnts.parameters, "parameter count")
    local parameter_binding_count = parse.to_usize(cnts.parameter_bindings, "parameter binding count")
    if not parameter_count or not parameter_binding_count then
        return nil, "Invalid counts"
    end

    local parameter_binding_begin_indices, err = parse.read_i32_section(bytes, offs, PARAMETER_BINDING_BEGIN_INDICES_SLOT, parameter_count)
    if not parameter_binding_begin_indices then return nil, err end

    local binding_parameter_indices = expand_binding_parameter_indices(parameter_binding_begin_indices, parameter_binding_count)
    if not binding_parameter_indices then
        return nil, "invalid parameter binding begin indices"
    end

    -- Read sections
    local param_min, err = parse.read_f32_section(bytes, offs, PARAMETER_MIN_VALUES_SLOT, parameter_count)
    if not param_min then return nil, err end
    local param_max, err = parse.read_f32_section(bytes, offs, PARAMETER_MAX_VALUES_SLOT, parameter_count)
    if not param_max then return nil, err end
    local param_default, err = parse.read_f32_section(bytes, offs, PARAMETER_DEFAULT_VALUES_SLOT, parameter_count)
    if not param_default then return nil, err end

    local binding_indices_count = parse.to_usize(cnts.parameter_binding_indices, "keyform binding index count")
    local keyform_bindings_count = parse.to_usize(cnts.keyform_bindings, "keyform binding band count")
    local parameter_bindings_count = parse.to_usize(cnts.parameter_bindings, "keyform binding count")
    local keys_count = parse.to_usize(cnts.keys, "key count")

    local kf_binding_indices, err = parse.read_i32_section(bytes, offs, KEYFORM_BINDING_INDICES_SLOT, binding_indices_count)
    if not kf_binding_indices then return nil, err end
    local band_begin_indices, err = parse.read_i32_section(bytes, offs, KEYFORM_BINDING_BAND_BEGIN_INDICES_SLOT, keyform_bindings_count)
    if not band_begin_indices then return nil, err end
    local band_counts, err = parse.read_i32_section(bytes, offs, KEYFORM_BINDING_BAND_COUNTS_SLOT, keyform_bindings_count)
    if not band_counts then return nil, err end
    local keys_begin_indices, err = parse.read_i32_section(bytes, offs, KEYFORM_BINDING_KEYS_BEGIN_INDICES_SLOT, parameter_bindings_count)
    if not keys_begin_indices then return nil, err end
    local keys_counts, err = parse.read_i32_section(bytes, offs, KEYFORM_BINDING_KEYS_COUNTS_SLOT, parameter_bindings_count)
    if not keys_counts then return nil, err end
    local key_values, err = parse.read_f32_section(bytes, offs, KEY_VALUES_SLOT, keys_count)
    if not key_values then return nil, err end

    return setmetatable({
        parameter_min_values = param_min,
        parameter_max_values = param_max,
        parameter_default_values = param_default,
        binding_parameter_indices = binding_parameter_indices,
        keyform_binding_indices = kf_binding_indices,
        band_begin_indices = band_begin_indices,
        band_counts = band_counts,
        keys_begin_indices = keys_begin_indices,
        keys_counts = keys_counts,
        key_values = key_values,
        _binding_keys_cache = {},
        _band_bindings_cache = {},
        _band_runtime_cache = {},
    }, { __index = keyform_bindings })
end

-- Get binding keys for a binding index
local function binding_keys(self, binding_index)
    local cache = self._binding_keys_cache
    local cached = cache and cache[binding_index + 1]
    if cached then return cached end

    local begin = self.keys_begin_indices[binding_index + 1]
    if begin == nil or begin < 0 then
        return nil
    end
    local keyCount = self.keys_counts[binding_index + 1]
    if keyCount == nil or keyCount < 0 then
        return nil
    end
    local keyData = {}
    for i = 0, keyCount - 1 do
        keyData[#keyData + 1] = self.key_values[begin + i + 1]
    end
    if cache then cache[binding_index + 1] = keyData end
    return keyData
end

-- Get keyform bindings for a band index
local function band_keyform_bindings(self, band_index)
    if band_index < 0 then
        return nil
    end
    local cache = self._band_bindings_cache
    local cached = cache and cache[band_index + 1]
    if cached then return cached end

    local begin = self.band_begin_indices[band_index + 1]
    if begin == nil or begin < 0 then
        return nil
    end
    local bandCount = self.band_counts[band_index + 1]
    if bandCount == nil or bandCount < 0 then
        return nil
    end
    local bandData = {}
    for i = 0, bandCount - 1 do
        bandData[#bandData + 1] = self.keyform_binding_indices[begin + i + 1]
    end
    if cache then cache[band_index + 1] = bandData end
    return bandData
end

local function compute_axis_interval(keys, value)
    local key_count = #keys
    if key_count == 0 then return nil end
    if value <= keys[1] then return 0, 0 end
    local last_index = key_count - 1
    if value >= keys[key_count] then return last_index, 0 end
    for i = 0, last_index - 1 do
        local left = keys[i + 1]
        local right = keys[i + 2]
        if left <= value and value <= right then
            return i, (value - left) / (right - left)
        end
    end
    return last_index, 0
end

local function band_metadata(self, band_index)
    local cache = self._band_runtime_cache
    local cached = cache and cache[band_index + 1]
    if cached then return cached end

    local bindings = band_keyform_bindings(self, band_index)
    if not bindings or #bindings == 0 then return nil end

    local meta = { axes = {}, values = nil, slots = nil }
    local stride = 1
    for _, binding_idx in ipairs(bindings) do
        if binding_idx < 0 then return nil end
        local keys = binding_keys(self, binding_idx)
        if not keys then return nil end
        local param_idx = self.binding_parameter_indices[binding_idx + 1]
        if param_idx == nil then return nil end
        meta.axes[#meta.axes + 1] = {
            keys = keys,
            param_index = param_idx,
            stride = stride,
        }
        stride = stride * #keys
        if not stride then return nil end
    end

    if cache then cache[band_index + 1] = meta end
    return meta
end

local function cached_slots_valid(meta, parameter_values)
    local cached_values = meta.values
    if not cached_values then return false end
    for i, axis in ipairs(meta.axes) do
        if cached_values[i] ~= (parameter_values[axis.param_index + 1] or 0) then
            return false
        end
    end
    return true
end

function keyform_bindings.keyform_slots(self, band_index, keyform_count, parameter_values)
    if keyform_count == 0 then
        return nil
    end

    if keyform_count == 1 then
        return SINGLE_SLOT
    end

    if band_index < 0 then
        return SINGLE_SLOT
    end

    local meta = band_metadata(self, band_index)
    if not meta or #meta.axes == 0 then
        return SINGLE_SLOT
    end

    if meta.keyform_count == keyform_count and cached_slots_valid(meta, parameter_values) then
        return meta.slots
    end

    local axes = meta.axes
    local values = meta.values or {}
    local active_count = 0
    for axis_index, axis in ipairs(axes) do
        local param_value = parameter_values[axis.param_index + 1] or 0
        values[axis_index] = param_value
        local left_index, t = compute_axis_interval(axis.keys, param_value)
        if left_index == nil then return nil end
        local active_index = left_index
        if t ~= 0 then active_index = active_index + 1 end
        if active_index >= #axis.keys then return nil end
        axis.left_index = left_index
        axis.t = t
        if t ~= 0 then active_count = active_count + 1 end
    end

    local slot_count = 1
    for _ = 1, active_count do slot_count = slot_count * 2 end
    local result = meta.slots or {}
    for mask = 0, slot_count - 1 do
        local flat_index = 0
        local weight = 1
        local bit = 1
        for _, axis in ipairs(axes) do
            local t = axis.t
            if t == 0 then
                flat_index = flat_index + axis.left_index * axis.stride
            else
                if math.floor(mask / bit) % 2 ~= 0 then
                    flat_index = flat_index + (axis.left_index + 1) * axis.stride
                    weight = weight * t
                else
                    flat_index = flat_index + axis.left_index * axis.stride
                    weight = weight * (1 - t)
                end
                bit = bit * 2
            end
        end
        if flat_index >= keyform_count then return nil end
        local slot_index = mask + 1
        local slot = result[slot_index]
        if slot then
            slot.local_index = flat_index
            slot.weight = weight
        else
            result[slot_index] = { local_index = flat_index, weight = weight }
        end
    end
    for i = slot_count + 1, #result do
        result[i] = nil
    end
    meta.keyform_count = keyform_count
    meta.values = values
    meta.slots = result
    return result
end

function keyform_bindings.default_keyform_index(self, band_index, keyform_count)
    local slots = keyform_bindings.keyform_slots(self, band_index, keyform_count, self.parameter_default_values)
    if not slots then
        return nil
    end
    -- Find slot with max weight
    local best = slots[1]
    for _, s in ipairs(slots) do
        if s.weight > best.weight then
            best = s
        end
    end
    return best.local_index
end

return keyform_bindings
