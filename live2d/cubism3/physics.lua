-- Cubism Physics3 evaluator. Mirrors the native Cubism fixed-step pendulum.

local Physics = {}
Physics.__index = Physics

local AIR_RESISTANCE = 5.0
local MAXIMUM_WEIGHT = 100.0
local MOVEMENT_THRESHOLD = 0.001
local MAX_DELTA_TIME = 5.0
local PI = math.pi

local function direction_to_radian(from_x, from_y, to_x, to_y)
    local result = math.atan2(to_y, to_x) - math.atan2(from_y, from_x)
    while result < -PI do result = result + PI * 2 end
    while result > PI do result = result - PI * 2 end
    return result
end

local function normalize(x, y)
    local length = math.sqrt(x * x + y * y)
    if length == 0 then return 0, 0 end
    return x / length, y / length
end

local function normalize_parameter_value(value, minimum, maximum, normalization, reflected)
    local maximum_value = math.max(maximum, minimum)
    value = math.min(value, maximum_value)
    local minimum_value = math.min(maximum, minimum)
    value = math.max(value, minimum_value)

    local normalized_minimum = math.min(normalization.minimum, normalization.maximum)
    local normalized_maximum = math.max(normalization.minimum, normalization.maximum)
    local parameter_middle = minimum_value + (maximum_value - minimum_value) * 0.5
    local parameter_value = value - parameter_middle
    local result
    if parameter_value > 0 then
        local parameter_length = maximum_value - parameter_middle
        if parameter_length == 0 then
            result = 0
        else
            result = parameter_value * (normalized_maximum - normalization.default) / parameter_length
                + normalization.default
        end
    elseif parameter_value < 0 then
        local parameter_length = minimum_value - parameter_middle
        if parameter_length == 0 then
            result = 0
        else
            result = parameter_value * (normalized_minimum - normalization.default) / parameter_length
                + normalization.default
        end
    else
        result = normalization.default
    end
    return reflected and result or -result
end

local function update_output_parameter_value(value, minimum, maximum, output_value, output)
    local scale = output.type == "Angle" and output.scale or 0
    local next_value = output_value * scale
    if next_value < minimum then
        output.value_below_minimum = math.min(output.value_below_minimum, next_value)
        next_value = minimum
    elseif next_value > maximum then
        output.value_exceeded_maximum = math.max(output.value_exceeded_maximum, next_value)
        next_value = maximum
    end
    local weight = output.weight / MAXIMUM_WEIGHT
    if weight >= 1.0 then return next_value end
    return value * (1.0 - weight) + next_value * weight
end

local function make_particles(vertices)
    local particles = {}
    for index, vertex in ipairs(vertices) do
        particles[index] = {
            mobility = vertex.mobility,
            delay = vertex.delay,
            acceleration = vertex.acceleration,
            radius = vertex.radius,
            initial_x = 0,
            initial_y = 0,
            position_x = 0,
            position_y = 0,
            last_x = 0,
            last_y = 0,
            last_gravity_x = 0,
            last_gravity_y = 1,
            velocity_x = 0,
            velocity_y = 0,
            force_x = 0,
            force_y = 0,
        }
    end
    for index = 2, #particles do
        local particle = particles[index]
        local parent = particles[index - 1]
        particle.initial_x = parent.initial_x
        particle.initial_y = parent.initial_y + particle.radius
        particle.position_x = particle.initial_x
        particle.position_y = particle.initial_y
        particle.last_x = particle.initial_x
        particle.last_y = particle.initial_y
    end
    return particles
end

local function update_particles(particles, total_x, total_y, total_angle, wind_x, wind_y, threshold, delta)
    local total_radian = total_angle * PI / 180.0
    local gravity_x, gravity_y = normalize(math.sin(total_radian), math.cos(total_radian))
    particles[1].position_x = total_x
    particles[1].position_y = total_y

    for index = 2, #particles do
        local particle = particles[index]
        local parent = particles[index - 1]
        particle.force_x = gravity_x * particle.acceleration + wind_x
        particle.force_y = gravity_y * particle.acceleration + wind_y
        particle.last_x = particle.position_x
        particle.last_y = particle.position_y

        local delay = particle.delay * delta * 30.0
        local direction_x = particle.position_x - parent.position_x
        local direction_y = particle.position_y - parent.position_y
        local radian = direction_to_radian(
            particle.last_gravity_x, particle.last_gravity_y, gravity_x, gravity_y
        ) / AIR_RESISTANCE
        local cosine = math.cos(radian)
        local sine = math.sin(radian)
        direction_x = cosine * direction_x - direction_y * sine
        -- Keep the native SDK's in-place rotation order for compatibility.
        direction_y = sine * direction_x + direction_y * cosine

        particle.position_x = parent.position_x + direction_x
        particle.position_y = parent.position_y + direction_y
        particle.position_x = particle.position_x + particle.velocity_x * delay + particle.force_x * delay * delay
        particle.position_y = particle.position_y + particle.velocity_y * delay + particle.force_y * delay * delay

        direction_x, direction_y = normalize(
            particle.position_x - parent.position_x,
            particle.position_y - parent.position_y
        )
        particle.position_x = parent.position_x + direction_x * particle.radius
        particle.position_y = parent.position_y + direction_y * particle.radius
        if math.abs(particle.position_x) < threshold then particle.position_x = 0 end
        if delay ~= 0 then
            particle.velocity_x = (particle.position_x - particle.last_x) / delay * particle.mobility
            particle.velocity_y = (particle.position_y - particle.last_y) / delay * particle.mobility
        end
        particle.force_x = 0
        particle.force_y = 0
        particle.last_gravity_x = gravity_x
        particle.last_gravity_y = gravity_y
    end
end

function Physics.new(data)
    if type(data) ~= "table" or type(data.settings) ~= "table" then
        return nil, "invalid Physics3 data"
    end
    local self = setmetatable({
        data = data,
        options = { gravity = { x = 0, y = -1 }, wind = { x = 0, y = 0 } },
        settings = {},
        remaining_time = 0,
        parameter_caches = {},
        parameter_input_caches = {},
    }, Physics)
    for _, setting in ipairs(data.settings) do
        local outputs = {}
        for index, output in ipairs(setting.outputs) do
            outputs[index] = {
                destination_id = output.destination_id,
                vertex_index = output.vertex_index,
                scale = output.scale,
                weight = output.weight,
                type = output.type,
                reflect = output.reflect,
                value_below_minimum = math.huge,
                value_exceeded_maximum = -math.huge,
            }
        end
        local inputs = {}
        for index, input in ipairs(setting.inputs) do
            inputs[index] = {
                source_id = input.source_id,
                weight = input.weight,
                type = input.type,
                reflect = input.reflect,
            }
        end
        local current_outputs = {}
        local previous_outputs = {}
        for index = 1, #outputs do
            current_outputs[index] = 0
            previous_outputs[index] = 0
        end
        self.settings[#self.settings + 1] = {
            inputs = inputs,
            outputs = outputs,
            particles = make_particles(setting.vertices),
            normalization_position = setting.normalization_position,
            normalization_angle = setting.normalization_angle,
            current_outputs = current_outputs,
            previous_outputs = previous_outputs,
        }
    end
    return self
end

function Physics:reset()
    self.remaining_time = 0
    self.parameter_caches = {}
    self.parameter_input_caches = {}
    for setting_index, setting_data in ipairs(self.data.settings) do
        local setting = self.settings[setting_index]
        setting.particles = make_particles(setting_data.vertices)
        for index = 1, #setting.outputs do
            setting.current_outputs[index] = 0
            setting.previous_outputs[index] = 0
        end
    end
end

function Physics:set_options(options)
    options = options or {}
    local gravity = options.gravity
    if type(gravity) == "table" then
        self.options.gravity.x = tonumber(gravity.x) or self.options.gravity.x
        self.options.gravity.y = tonumber(gravity.y) or self.options.gravity.y
    end
    local wind = options.wind
    if type(wind) == "table" then
        self.options.wind.x = tonumber(wind.x) or self.options.wind.x
        self.options.wind.y = tonumber(wind.y) or self.options.wind.y
    end
end

function Physics:_ensure_parameter_caches(runtime)
    for index = 0, #runtime.parameter_values - 1 do
        local slot = index + 1
        local value = runtime:parameter_value_by_index(index)
        if self.parameter_input_caches[slot] == nil then
            self.parameter_input_caches[slot] = value
        end
        if self.parameter_caches[slot] == nil then
            self.parameter_caches[slot] = value
        end
    end
end

function Physics:_update_setting(runtime, setting, delta)
    local total_x, total_y, total_angle = 0, 0, 0
    for _, input in ipairs(setting.inputs) do
        if input.source_parameter_index == nil then
            input.source_parameter_index = runtime:parameter_index_of(input.source_id)
        end
        local index = input.source_parameter_index
        if index ~= nil then
            local value = self.parameter_caches[index + 1]
            local minimum = runtime:parameter_minimum_by_index(index)
            local maximum = runtime:parameter_maximum_by_index(index)
            if value ~= nil and minimum ~= nil and maximum ~= nil then
                local normalization = input.type == "Angle"
                    and setting.normalization_angle or setting.normalization_position
                local normalized = normalize_parameter_value(
                    value, minimum, maximum, normalization, input.reflect
                ) * input.weight / MAXIMUM_WEIGHT
                if input.type == "X" then
                    total_x = total_x + normalized
                elseif input.type == "Y" then
                    total_y = total_y + normalized
                else
                    total_angle = total_angle + normalized
                end
            end
        end
    end

    local radian = -total_angle * PI / 180.0
    local cosine = math.cos(radian)
    local sine = math.sin(radian)
    total_x = total_x * cosine - total_y * sine
    -- Keep the native SDK's in-place rotation order for compatibility.
    total_y = total_x * sine + total_y * cosine
    update_particles(
        setting.particles, total_x, total_y, total_angle,
        self.options.wind.x, self.options.wind.y,
        MOVEMENT_THRESHOLD * setting.normalization_position.maximum, delta
    )

    for output_index, output in ipairs(setting.outputs) do
        if output.destination_parameter_index == nil then
            output.destination_parameter_index = runtime:parameter_index_of(output.destination_id)
        end
        local particle_index = output.vertex_index
        if output.destination_parameter_index ~= nil
            and particle_index >= 1 and particle_index < #setting.particles then
            local particle = setting.particles[particle_index + 1]
            local parent = setting.particles[particle_index]
            local translation_x = particle.position_x - parent.position_x
            local translation_y = particle.position_y - parent.position_y
            local value
            if output.type == "X" then
                value = translation_x
            elseif output.type == "Y" then
                value = translation_y
            else
                local gravity_x, gravity_y = -self.options.gravity.x, -self.options.gravity.y
                if particle_index >= 2 then
                    local previous = setting.particles[particle_index]
                    local before_previous = setting.particles[particle_index - 1]
                    gravity_x = previous.position_x - before_previous.position_x
                    gravity_y = previous.position_y - before_previous.position_y
                end
                value = direction_to_radian(gravity_x, gravity_y, translation_x, translation_y)
            end
            if output.reflect then value = -value end
            setting.current_outputs[output_index] = value

            local index = output.destination_parameter_index
            local minimum = runtime:parameter_minimum_by_index(index)
            local maximum = runtime:parameter_maximum_by_index(index)
            local parameter_value = self.parameter_caches[index + 1]
            if minimum ~= nil and maximum ~= nil and parameter_value ~= nil then
                self.parameter_caches[index + 1] = update_output_parameter_value(
                    parameter_value, minimum, maximum, value, output
                )
            end
        end
    end
end

function Physics:_interpolate(runtime, weight)
    for _, setting in ipairs(self.settings) do
        for output_index, output in ipairs(setting.outputs) do
            local index = output.destination_parameter_index
            if index ~= nil then
                local value = runtime:parameter_value_by_index(index)
                local minimum = runtime:parameter_minimum_by_index(index)
                local maximum = runtime:parameter_maximum_by_index(index)
                if value ~= nil and minimum ~= nil and maximum ~= nil then
                    local output_value = setting.previous_outputs[output_index] * (1.0 - weight)
                        + setting.current_outputs[output_index] * weight
                    runtime:set_parameter_by_index(index, update_output_parameter_value(
                        value, minimum, maximum, output_value, output
                    ))
                end
            end
        end
    end
end

function Physics:evaluate(runtime, delta)
    delta = tonumber(delta) or 0
    if delta <= 0 then return false end
    self.remaining_time = self.remaining_time + delta
    if self.remaining_time > MAX_DELTA_TIME then self.remaining_time = 0 end
    self:_ensure_parameter_caches(runtime)

    local physics_delta = self.data.fps > 0 and 1.0 / self.data.fps or delta
    while self.remaining_time >= physics_delta do
        for _, setting in ipairs(self.settings) do
            for output_index = 1, #setting.outputs do
                setting.previous_outputs[output_index] = setting.current_outputs[output_index] or 0
            end
        end

        local input_weight = physics_delta / self.remaining_time
        for index = 0, #runtime.parameter_values - 1 do
            local slot = index + 1
            local current = runtime:parameter_value_by_index(index)
            local cached_input = self.parameter_input_caches[slot]
            self.parameter_caches[slot] = cached_input * (1.0 - input_weight) + current * input_weight
            self.parameter_input_caches[slot] = self.parameter_caches[slot]
        end
        for _, setting in ipairs(self.settings) do
            self:_update_setting(runtime, setting, physics_delta)
        end
        self.remaining_time = self.remaining_time - physics_delta
    end

    self:_interpolate(runtime, self.remaining_time / physics_delta)
    return true
end

return Physics
