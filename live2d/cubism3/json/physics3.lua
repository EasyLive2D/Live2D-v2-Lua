-- Physics3 JSON parser for Cubism 3

local json = require("live2d.dkjson")

local physics3 = {}

local function number(value, name)
    value = tonumber(value)
    if value == nil then
        return nil, name .. " must be a number"
    end
    return value
end

local function vector(raw, name)
    if type(raw) ~= "table" then
        return nil, name .. " must be an object"
    end
    local x, err = number(raw.X, name .. ".X")
    if x == nil then return nil, err end
    local y
    y, err = number(raw.Y, name .. ".Y")
    if y == nil then return nil, err end
    return { x = x, y = y }
end

local function normalization(raw, name)
    if type(raw) ~= "table" then
        return nil, name .. " must be an object"
    end
    local minimum, err = number(raw.Minimum, name .. ".Minimum")
    if minimum == nil then return nil, err end
    local maximum
    maximum, err = number(raw.Maximum, name .. ".Maximum")
    if maximum == nil then return nil, err end
    local default
    default, err = number(raw.Default, name .. ".Default")
    if default == nil then return nil, err end
    return { minimum = minimum, maximum = maximum, default = default }
end

local function parse_input(raw, name)
    if type(raw) ~= "table" or type(raw.Source) ~= "table" or raw.Source.Id == nil then
        return nil, name .. ".Source.Id is required"
    end
    local weight, err = number(raw.Weight, name .. ".Weight")
    if weight == nil then return nil, err end
    if raw.Type ~= "X" and raw.Type ~= "Y" and raw.Type ~= "Angle" then
        return nil, name .. ".Type must be X, Y, or Angle"
    end
    return {
        source_id = tostring(raw.Source.Id),
        weight = weight,
        type = raw.Type,
        reflect = raw.Reflect == true,
    }
end

local function parse_output(raw, name)
    if type(raw) ~= "table" or type(raw.Destination) ~= "table" or raw.Destination.Id == nil then
        return nil, name .. ".Destination.Id is required"
    end
    local vertex_index, err = number(raw.VertexIndex, name .. ".VertexIndex")
    if vertex_index == nil then return nil, err end
    local scale
    scale, err = number(raw.Scale, name .. ".Scale")
    if scale == nil then return nil, err end
    local weight
    weight, err = number(raw.Weight, name .. ".Weight")
    if weight == nil then return nil, err end
    if raw.Type ~= "X" and raw.Type ~= "Y" and raw.Type ~= "Angle" then
        return nil, name .. ".Type must be X, Y, or Angle"
    end
    return {
        destination_id = tostring(raw.Destination.Id),
        vertex_index = vertex_index,
        scale = scale,
        weight = weight,
        type = raw.Type,
        reflect = raw.Reflect == true,
    }
end

local function parse_vertex(raw, name)
    if type(raw) ~= "table" then return nil, name .. " must be an object" end
    local position, err = vector(raw.Position, name .. ".Position")
    if position == nil then return nil, err end
    local mobility
    mobility, err = number(raw.Mobility, name .. ".Mobility")
    if mobility == nil then return nil, err end
    local delay
    delay, err = number(raw.Delay, name .. ".Delay")
    if delay == nil then return nil, err end
    local acceleration
    acceleration, err = number(raw.Acceleration, name .. ".Acceleration")
    if acceleration == nil then return nil, err end
    local radius
    radius, err = number(raw.Radius, name .. ".Radius")
    if radius == nil then return nil, err end
    return {
        position = position,
        mobility = mobility,
        delay = delay,
        acceleration = acceleration,
        radius = radius,
    }
end

function physics3.parse(source)
    local ok, raw, _, decode_err = pcall(json.decode, source)
    if not ok or type(raw) ~= "table" then
        return nil, "Invalid physics3.json: " .. tostring(decode_err or raw)
    end
    if tonumber(raw.Version) ~= 3 then
        return nil, "Unsupported physics3.json version: " .. tostring(raw.Version)
    end

    local meta = raw.Meta
    local settings = raw.PhysicsSettings
    if type(meta) ~= "table" or type(settings) ~= "table" then
        return nil, "Missing Meta or PhysicsSettings in physics3.json"
    end

    local setting_count, err = number(meta.PhysicsSettingCount, "Meta.PhysicsSettingCount")
    if setting_count == nil then return nil, err end
    local total_input_count
    total_input_count, err = number(meta.TotalInputCount, "Meta.TotalInputCount")
    if total_input_count == nil then return nil, err end
    local total_output_count
    total_output_count, err = number(meta.TotalOutputCount, "Meta.TotalOutputCount")
    if total_output_count == nil then return nil, err end
    local vertex_count
    vertex_count, err = number(meta.VertexCount, "Meta.VertexCount")
    if vertex_count == nil then return nil, err end
    if #settings ~= setting_count then
        return nil, "Meta.PhysicsSettingCount does not match PhysicsSettings"
    end

    local forces = meta.EffectiveForces
    if type(forces) ~= "table" then return nil, "Missing Meta.EffectiveForces" end
    local gravity
    gravity, err = vector(forces.Gravity, "Meta.EffectiveForces.Gravity")
    if gravity == nil then return nil, err end
    local wind
    wind, err = vector(forces.Wind, "Meta.EffectiveForces.Wind")
    if wind == nil then return nil, err end

    local fps = 0
    if meta.Fps ~= nil then
        fps, err = number(meta.Fps, "Meta.Fps")
        if fps == nil then return nil, err end
    end

    local parsed_settings = {}
    local parsed_input_count, parsed_output_count, parsed_vertex_count = 0, 0, 0
    for setting_index, raw_setting in ipairs(settings) do
        if type(raw_setting) ~= "table" then
            return nil, "PhysicsSettings[" .. setting_index .. "] must be an object"
        end
        local name = "PhysicsSettings[" .. setting_index .. "]"
        local raw_normalization = raw_setting.Normalization
        if type(raw_normalization) ~= "table" then return nil, name .. ".Normalization is required" end
        local position_normalization
        position_normalization, err = normalization(raw_normalization.Position, name .. ".Normalization.Position")
        if position_normalization == nil then return nil, err end
        local angle_normalization
        angle_normalization, err = normalization(raw_normalization.Angle, name .. ".Normalization.Angle")
        if angle_normalization == nil then return nil, err end

        local inputs, outputs, vertices = {}, {}, {}
        for input_index, input in ipairs(raw_setting.Input or {}) do
            local parsed
            parsed, err = parse_input(input, name .. ".Input[" .. input_index .. "]")
            if parsed == nil then return nil, err end
            inputs[#inputs + 1] = parsed
        end
        for output_index, output in ipairs(raw_setting.Output or {}) do
            local parsed
            parsed, err = parse_output(output, name .. ".Output[" .. output_index .. "]")
            if parsed == nil then return nil, err end
            outputs[#outputs + 1] = parsed
        end
        for vertex_index, vertex in ipairs(raw_setting.Vertices or {}) do
            local parsed
            parsed, err = parse_vertex(vertex, name .. ".Vertices[" .. vertex_index .. "]")
            if parsed == nil then return nil, err end
            vertices[#vertices + 1] = parsed
        end
        if #vertices == 0 then return nil, name .. ".Vertices must not be empty" end

        parsed_input_count = parsed_input_count + #inputs
        parsed_output_count = parsed_output_count + #outputs
        parsed_vertex_count = parsed_vertex_count + #vertices
        parsed_settings[#parsed_settings + 1] = {
            id = raw_setting.Id,
            inputs = inputs,
            outputs = outputs,
            vertices = vertices,
            normalization_position = position_normalization,
            normalization_angle = angle_normalization,
        }
    end

    if parsed_input_count ~= total_input_count then
        return nil, "Meta.TotalInputCount does not match PhysicsSettings"
    end
    if parsed_output_count ~= total_output_count then
        return nil, "Meta.TotalOutputCount does not match PhysicsSettings"
    end
    if parsed_vertex_count ~= vertex_count then
        return nil, "Meta.VertexCount does not match PhysicsSettings"
    end

    return {
        version = 3,
        fps = fps,
        gravity = gravity,
        wind = wind,
        settings = parsed_settings,
        meta = {
            physics_setting_count = setting_count,
            total_input_count = total_input_count,
            total_output_count = total_output_count,
            vertex_count = vertex_count,
        },
    }
end

return physics3
