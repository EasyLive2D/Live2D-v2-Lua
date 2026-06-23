-- MOC3 keyform bindings parser for Cubism 3
-- Ported from Mocari src/moc3/keyform_bindings.rs

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")
local keyforms_core = require("live2d.cubism3.core.keyforms")

local keyform_bindings = {}

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
    }, { __index = keyform_bindings })
end

-- Get binding keys for a binding index
local function binding_keys(self, binding_index)
    local begin = self.keys_begin_indices[binding_index + 1]
    if begin == nil or begin < 0 then
        return nil
    end
    local len = self.keys_counts[binding_index + 1]
    if len == nil or len < 0 then
        return nil
    end
    local result = {}
    for i = 0, len - 1 do
        table.insert(result, self.key_values[begin + i + 1])
    end
    return result
end

-- Get keyform bindings for a band index
local function band_keyform_bindings(self, band_index)
    if band_index < 0 then
        return nil
    end
    local begin = self.band_begin_indices[band_index + 1]
    if begin == nil or begin < 0 then
        return nil
    end
    local len = self.band_counts[band_index + 1]
    if len == nil or len < 0 then
        return nil
    end
    local result = {}
    for i = 0, len - 1 do
        table.insert(result, self.keyform_binding_indices[begin + i + 1])
    end
    return result
end

function keyform_bindings.keyform_slots(self, band_index, keyform_count, parameter_values)
    if keyform_count == 0 then
        return nil
    end

    if band_index < 0 then
        return { { local_index = 0, weight = 1 } }
    end

    local bindings = band_keyform_bindings(self, band_index)
    if not bindings or #bindings == 0 then
        return { { local_index = 0, weight = 1 } }
    end

    local axes = {}
    local stride = 1
    for _, binding_idx in ipairs(bindings) do
        if binding_idx < 0 then
            return nil
        end
        local keys = binding_keys(self, binding_idx)
        if not keys then
            return nil
        end
        local param_idx = self.binding_parameter_indices[binding_idx + 1]
        if param_idx == nil then
            return nil
        end
        local param_value = parameter_values[param_idx + 1] or 0
        local interval = keyforms_core.compute_keyform_axis_interval(keys, param_value)
        if not interval then
            return nil
        end
        local active_index = interval.left_index
        if interval.t ~= 0 then
            active_index = active_index + 1
        end
        if active_index >= #keys then
            return nil
        end
        table.insert(axes, keyforms_core.new_keyform_axis(
            interval.left_index,
            interval.t,
            stride
        ))
        stride = stride * #keys
        if not stride then
            return nil
        end
    end

    local slots = keyforms_core.expand_keyform_runtime_slots(axes)
    local result = {}
    for _, slot in ipairs(slots) do
        if slot.flat_index < keyform_count then
            table.insert(result, {
                local_index = slot.flat_index,
                weight = slot.weight,
            })
        else
            return nil -- All flat_indices must be < keyform_count
        end
    end
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
