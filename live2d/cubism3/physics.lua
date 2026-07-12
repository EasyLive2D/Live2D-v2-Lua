-- Cubism Physics3 evaluator. Mirrors the native Cubism fixed-step pendulum.

local Physics = {}
Physics.__index = Physics

local AIR_RESISTANCE = 5.0
local MAXIMUM_WEIGHT = 100.0
local MOVEMENT_THRESHOLD = 0.001
local DEFAULT_PHYSICS_FPS = 60.0
local MAX_ACCUMULATED_TIME = 0.25
local MAX_SUBSTEPS = 8
local PI = math.pi
local TWO_PI = PI * 2
local DEG_TO_RAD = PI / 180.0
local abs = math.abs
local atan2 = math.atan2
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt

local function direction_to_radian(from_x, from_y, to_x, to_y)
    local result = atan2(to_y, to_x) - atan2(from_y, from_x)
    -- Both atan2 results are already in [-PI, PI], so one wrap is enough.
    if result < -PI then
        result = result + TWO_PI
    elseif result > PI then
        result = result - TWO_PI
    end
    return result
end

local function normalize(x, y)
    local length = sqrt(x * x + y * y)
    if length == 0 then return 0, 0 end
    return x / length, y / length
end

local function normalize_parameter_value(value, input)
    if value > input.maximum then
        value = input.maximum
    elseif value < input.minimum then
        value = input.minimum
    end

    local parameter_value = value - input.middle
    local result
    if parameter_value > 0 then
        result = parameter_value * input.positive_scale + input.normalization_default
    elseif parameter_value < 0 then
        result = parameter_value * input.negative_scale + input.normalization_default
    else
        result = input.normalization_default
    end
    return result * input.normalized_weight
end

local function update_output_parameter_value(value, output_value, output)
    local next_value = output_value * output.output_scale
    if next_value < output.minimum then
        if next_value < output.value_below_minimum then
            output.value_below_minimum = next_value
        end
        next_value = output.minimum
    elseif next_value > output.maximum then
        if next_value > output.value_exceeded_maximum then
            output.value_exceeded_maximum = next_value
        end
        next_value = output.maximum
    end
    if output.weight_ratio >= 1.0 then return next_value end
    return value * output.inverse_weight + next_value * output.weight_ratio
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

local function update_particles(particles, particle_count, total_x, total_y, total_angle, wind_x, wind_y, threshold, delta)
    local total_radian = total_angle * DEG_TO_RAD
    -- sin/cos already form a unit vector; normalizing it again is pure cost.
    local gravity_x, gravity_y = sin(total_radian), cos(total_radian)
    particles[1].position_x = total_x
    particles[1].position_y = total_y

    for index = 2, particle_count do
        local particle = particles[index]
        local parent = particles[index - 1]
        local force_x = gravity_x * particle.acceleration + wind_x
        local force_y = gravity_y * particle.acceleration + wind_y
        particle.last_x = particle.position_x
        particle.last_y = particle.position_y

        local delay = particle.delay * delta * 30.0
        local delay_squared = delay * delay
        local direction_x = particle.position_x - parent.position_x
        local direction_y = particle.position_y - parent.position_y
        local radian = direction_to_radian(
            particle.last_gravity_x, particle.last_gravity_y, gravity_x, gravity_y
        ) / AIR_RESISTANCE
        local cosine = cos(radian)
        local sine = sin(radian)
        direction_x = cosine * direction_x - direction_y * sine
        -- Keep the native SDK's in-place rotation order for compatibility.
        direction_y = sine * direction_x + direction_y * cosine

        particle.position_x = parent.position_x + direction_x
        particle.position_y = parent.position_y + direction_y
        particle.position_x = particle.position_x + particle.velocity_x * delay + force_x * delay_squared
        particle.position_y = particle.position_y + particle.velocity_y * delay + force_y * delay_squared

        direction_x, direction_y = normalize(
            particle.position_x - parent.position_x,
            particle.position_y - parent.position_y
        )
        particle.position_x = parent.position_x + direction_x * particle.radius
        particle.position_y = parent.position_y + direction_y * particle.radius
        if abs(particle.position_x) < threshold then particle.position_x = 0 end
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
    local physics_fps = tonumber(data.fps) or 0
    if physics_fps <= 0 then physics_fps = DEFAULT_PHYSICS_FPS end
    local self = setmetatable({
        data = data,
        options = { gravity = { x = 0, y = -1 }, wind = { x = 0, y = 0 } },
        settings = {},
        settings_count = #data.settings,
        physics_delta = 1.0 / physics_fps,
        remaining_time = 0,
        last_substep_count = 0,
        total_substep_count = 0,
        parameter_caches = {},
        parameter_input_caches = {},
        input_slots = {},
        cache_slots = {},
        caches_initialized = false,
        bound_runtime = nil,
        bound_parameter_values = nil,
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
                output_scale = output.type == "Angle" and output.scale or 0,
                weight_ratio = output.weight / MAXIMUM_WEIGHT,
                inverse_weight = 1.0 - output.weight / MAXIMUM_WEIGHT,
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
            particle_count = #setting.vertices,
            input_count = #inputs,
            output_count = #outputs,
            normalization_position = setting.normalization_position,
            normalization_angle = setting.normalization_angle,
            movement_threshold = MOVEMENT_THRESHOLD * setting.normalization_position.maximum,
            current_outputs = current_outputs,
            previous_outputs = previous_outputs,
        }
    end
    return self
end

function Physics:reset()
    self.remaining_time = 0
    self.last_substep_count = 0
    self.total_substep_count = 0
    self.parameter_caches = {}
    self.parameter_input_caches = {}
    self.caches_initialized = false
    for setting_index = 1, self.settings_count do
        local setting_data = self.data.settings[setting_index]
        local setting = self.settings[setting_index]
        setting.particles = make_particles(setting_data.vertices)
        for index = 1, setting.output_count do
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

local function prepare_input(input, normalization, minimum, maximum)
    local minimum_value = math.min(minimum, maximum)
    local maximum_value = math.max(minimum, maximum)
    local normalized_minimum = math.min(normalization.minimum, normalization.maximum)
    local normalized_maximum = math.max(normalization.minimum, normalization.maximum)
    local middle = minimum_value + (maximum_value - minimum_value) * 0.5
    local positive_length = maximum_value - middle
    local negative_length = minimum_value - middle

    input.minimum = minimum_value
    input.maximum = maximum_value
    input.middle = middle
    input.normalization_default = normalization.default
    input.positive_scale = positive_length == 0 and 0
        or (normalized_maximum - normalization.default) / positive_length
    input.negative_scale = negative_length == 0 and 0
        or (normalized_minimum - normalization.default) / negative_length
    input.normalized_weight = (input.reflect and 1.0 or -1.0)
        * input.weight / MAXIMUM_WEIGHT
end

function Physics:_bind_runtime(runtime)
    local parameter_values = runtime.parameter_values
    local parameter_index = runtime.parameter_index
    local bindings = runtime.bindings
    local minimum_values = bindings and bindings.parameter_min_values
    local maximum_values = bindings and bindings.parameter_max_values
    local input_slots = {}
    local cache_slots = {}
    local input_seen = {}
    local cache_seen = {}

    local function index_of(id)
        if parameter_index ~= nil then return parameter_index[id] end
        return runtime:parameter_index_of(id)
    end
    local function limits(index)
        local slot = index + 1
        local minimum = minimum_values and minimum_values[slot]
            or runtime:parameter_minimum_by_index(index)
        local maximum = maximum_values and maximum_values[slot]
            or runtime:parameter_maximum_by_index(index)
        return minimum, maximum
    end
    local function add_cache_slot(slot)
        if not cache_seen[slot] then
            cache_seen[slot] = true
            cache_slots[#cache_slots + 1] = slot
        end
    end

    for setting_index = 1, self.settings_count do
        local setting = self.settings[setting_index]
        for input_index = 1, setting.input_count do
            local input = setting.inputs[input_index]
            local index = index_of(input.source_id)
            input.source_parameter_index = index
            input.source_slot = nil
            if index ~= nil then
                local minimum, maximum = limits(index)
                if minimum ~= nil and maximum ~= nil then
                    local slot = index + 1
                    input.source_slot = slot
                    prepare_input(input, input.type == "Angle"
                        and setting.normalization_angle or setting.normalization_position,
                        minimum, maximum)
                    if not input_seen[slot] then
                        input_seen[slot] = true
                        input_slots[#input_slots + 1] = slot
                    end
                    add_cache_slot(slot)
                end
            end
        end
        for output_index = 1, setting.output_count do
            local output = setting.outputs[output_index]
            local index = index_of(output.destination_id)
            output.destination_parameter_index = index
            output.destination_slot = nil
            output.active = false
            if index ~= nil and output.vertex_index >= 1
                and output.vertex_index < setting.particle_count then
                local minimum, maximum = limits(index)
                if minimum ~= nil and maximum ~= nil then
                    local slot = index + 1
                    output.destination_slot = slot
                    output.minimum = minimum
                    output.maximum = maximum
                    output.active = true
                    add_cache_slot(slot)
                end
            end
        end
    end

    self.bound_runtime = runtime
    self.bound_parameter_values = parameter_values
    self.input_slots = input_slots
    self.cache_slots = cache_slots
    self.caches_initialized = false
end

function Physics:_ensure_parameter_caches(runtime)
    if self.bound_runtime ~= runtime or self.bound_parameter_values ~= runtime.parameter_values then
        self:_bind_runtime(runtime)
    end
    if self.caches_initialized then return end

    local parameter_values = runtime.parameter_values
    local parameter_caches = self.parameter_caches
    local parameter_input_caches = self.parameter_input_caches
    for index = 1, #self.cache_slots do
        local slot = self.cache_slots[index]
        parameter_caches[slot] = parameter_values[slot]
    end
    for index = 1, #self.input_slots do
        local slot = self.input_slots[index]
        parameter_input_caches[slot] = parameter_values[slot]
    end
    self.caches_initialized = true
end

function Physics:_update_setting(setting, delta)
    local total_x, total_y, total_angle = 0, 0, 0
    local parameter_caches = self.parameter_caches
    for input_index = 1, setting.input_count do
        local input = setting.inputs[input_index]
        local slot = input.source_slot
        if slot ~= nil then
            local normalized = normalize_parameter_value(parameter_caches[slot], input)
            if input.type == "X" then
                total_x = total_x + normalized
            elseif input.type == "Y" then
                total_y = total_y + normalized
            else
                total_angle = total_angle + normalized
            end
        end
    end

    local radian = -total_angle * DEG_TO_RAD
    local cosine = cos(radian)
    local sine = sin(radian)
    total_x = total_x * cosine - total_y * sine
    -- Keep the native SDK's in-place rotation order for compatibility.
    total_y = total_x * sine + total_y * cosine
    update_particles(
        setting.particles, setting.particle_count, total_x, total_y, total_angle,
        self.options.wind.x, self.options.wind.y,
        setting.movement_threshold, delta
    )

    for output_index = 1, setting.output_count do
        local output = setting.outputs[output_index]
        local particle_index = output.vertex_index
        if output.active then
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

            local slot = output.destination_slot
            parameter_caches[slot] = update_output_parameter_value(
                parameter_caches[slot], value, output
            )
        end
    end
end

function Physics:_interpolate(runtime, weight)
    local parameter_values = runtime.parameter_values
    local inverse_weight = 1.0 - weight
    local trace_enabled = runtime._parameter_trace ~= nil
    local set_parameter = runtime.set_parameter_by_index
    for setting_index = 1, self.settings_count do
        local setting = self.settings[setting_index]
        for output_index = 1, setting.output_count do
            local output = setting.outputs[output_index]
            local slot = output.destination_slot
            if output.active then
                local output_value = setting.previous_outputs[output_index] * inverse_weight
                    + setting.current_outputs[output_index] * weight
                local next_value = update_output_parameter_value(
                    parameter_values[slot], output_value, output
                )
                if trace_enabled then
                    set_parameter(runtime, output.destination_parameter_index, next_value)
                else
                    -- Avoid another Lua method call on the normal, untraced
                    -- hot path while preserving the setter's final clamp.
                    if next_value < output.minimum then
                        next_value = output.minimum
                    elseif next_value > output.maximum then
                        next_value = output.maximum
                    end
                    parameter_values[slot] = next_value
                end
            end
        end
    end
end

function Physics:evaluate(runtime, delta)
    delta = tonumber(delta) or 0
    self.last_substep_count = 0
    self:_ensure_parameter_caches(runtime)

    local physics_delta = self.physics_delta

    -- The host may render the same simulation state more than once (for
    -- example after an SSAA blit failure).  The outer Cubism update restores
    -- motion parameters before it calls physics, so returning early here
    -- would expose that restored pose for one render and make physics-driven
    -- parts snap back to their base values.  Reapply the last interpolated
    -- state without advancing the pendulum instead.
    if delta <= 0 then
        self:_interpolate(runtime, math.min(self.remaining_time / physics_delta, 1.0))
        return true
    end

    -- A long suspension is not useful simulation input.  Dropping it avoids
    -- a catch-up burst while preserving the last visible physics pose.
    if delta > MAX_ACCUMULATED_TIME then
        local interpolation_weight = math.min(self.remaining_time / physics_delta, 1.0)
        self.remaining_time = 0
        self:_interpolate(runtime, interpolation_weight)
        return true
    end

    self.remaining_time = math.min(self.remaining_time + delta, MAX_ACCUMULATED_TIME)
    local substeps = 0
    while self.remaining_time >= physics_delta and substeps < MAX_SUBSTEPS do
        for setting_index = 1, self.settings_count do
            local setting = self.settings[setting_index]
            -- Both buffers are fixed-size and the update below overwrites
            -- every valid output. Swapping avoids copying all outputs each
            -- physics substep.
            setting.previous_outputs, setting.current_outputs =
                setting.current_outputs, setting.previous_outputs
        end

        local input_weight = physics_delta / self.remaining_time
        local inverse_input_weight = 1.0 - input_weight
        local parameter_values = runtime.parameter_values
        local parameter_caches = self.parameter_caches
        local parameter_input_caches = self.parameter_input_caches
        for index = 1, #self.input_slots do
            local slot = self.input_slots[index]
            local cached_input = parameter_input_caches[slot]
            local value = cached_input * inverse_input_weight
                + parameter_values[slot] * input_weight
            parameter_caches[slot] = value
            parameter_input_caches[slot] = value
        end
        for setting_index = 1, self.settings_count do
            self:_update_setting(self.settings[setting_index], physics_delta)
        end
        self.remaining_time = self.remaining_time - physics_delta
        substeps = substeps + 1
    end

    self.last_substep_count = substeps
    self.total_substep_count = self.total_substep_count + substeps
    if substeps >= MAX_SUBSTEPS and self.remaining_time >= physics_delta then
        -- Drop only excess backlog.  Keeping at most one step preserves a
        -- continuous interpolation endpoint without a death spiral.
        self.remaining_time = math.min(self.remaining_time, physics_delta)
    end

    self:_interpolate(runtime, math.min(self.remaining_time / physics_delta, 1.0))
    return true
end

return Physics
