-- Physics simulation for Cubism 3
-- Ported from Mocari src/core/physics.rs

local math_lib = math
local abs = math_lib.abs
local cos = math_lib.cos
local max = math_lib.max
local min = math_lib.min
local sin = math_lib.sin
local sqrt = math_lib.sqrt
local cubism_math = require("live2d.cubism3.core.math")
local Vector2 = cubism_math.Vector2
local direction_to_radian = cubism_math.direction_to_radian
local radian_to_direction = cubism_math.radian_to_direction
local degrees_to_radian = cubism_math.degrees_to_radian

local physics = {}

local MAXIMUM_WEIGHT = 100

-- PhysicsRange
function physics.new_physics_range(minimum, maximum, default)
    return { minimum = minimum, maximum = maximum, default = default }
end

-- PhysicsInputAccumulator
local PhysicsInputAccumulator = {}
PhysicsInputAccumulator.__index = PhysicsInputAccumulator

function PhysicsInputAccumulator.new()
    return setmetatable({
        translation_x = 0,
        translation_y = 0,
        angle = 0,
    }, PhysicsInputAccumulator)
end

function PhysicsInputAccumulator:add_translation_x(value, parameter, normalization, reflect, weight_percent)
    self.translation_x = self.translation_x +
        weighted_normalized_value(value, parameter, normalization, reflect, weight_percent)
end

function PhysicsInputAccumulator:add_translation_y(value, parameter, normalization, reflect, weight_percent)
    self.translation_y = self.translation_y +
        weighted_normalized_value(value, parameter, normalization, reflect, weight_percent)
end

function PhysicsInputAccumulator:add_angle(value, parameter, normalization, reflect, weight_percent)
    self.angle = self.angle +
        weighted_normalized_value(value, parameter, normalization, reflect, weight_percent)
end

-- PhysicsParticle
local PhysicsParticle = {}
PhysicsParticle.__index = PhysicsParticle

function PhysicsParticle.new(position, last_position, velocity, force, last_gravity, mobility, delay, acceleration, radius)
    return setmetatable({
        position = position or Vector2.new(),
        last_position = last_position or Vector2.new(),
        velocity = velocity or Vector2.new(),
        force = force or Vector2.new(),
        last_gravity = last_gravity or Vector2.new(),
        mobility = mobility or 0,
        delay = delay or 0,
        acceleration = acceleration or 0,
        radius = radius or 0,
    }, PhysicsParticle)
end

-- Vector helpers
local function vec_add(a, b)
    return Vector2.new(a:x() + b:x(), a:y() + b:y())
end

local function vec_sub(a, b)
    return Vector2.new(a:x() - b:x(), a:y() - b:y())
end

local function vec_mul(value, factor)
    return Vector2.new(value:x() * factor, value:y() * factor)
end

local function vec_div(value, factor)
    if factor == 0 then
        return value
    end
    return Vector2.new(value:x() / factor, value:y() / factor)
end

local function vec_normalize(value)
    local length = sqrt(value:x() * value:x() + value:y() * value:y())
    if length == 0 then
        return value
    end
    return vec_div(value, length)
end

function physics.normalize_physics_parameter(value, parameter, normalized, reflect)
    local maximum = max(parameter.maximum, parameter.minimum)
    local minimum = min(parameter.maximum, parameter.minimum)
    value = max(minimum, min(maximum, value))
    local normalized_minimum = min(normalized.minimum, normalized.maximum)
    local normalized_maximum = max(normalized.minimum, normalized.maximum)
    local normalized_middle = normalized.default
    local middle = minimum + abs(maximum - minimum) / 2
    local parameter_value = value - middle

    local result
    if parameter_value > 0 then
        local normalized_length = normalized_maximum - normalized_middle
        local parameter_length = maximum - middle
        if parameter_length == 0 then
            result = 0
        else
            result = parameter_value * (normalized_length / parameter_length) + normalized_middle
        end
    elseif parameter_value < 0 then
        local normalized_length = normalized_minimum - normalized_middle
        local parameter_length = minimum - middle
        if parameter_length == 0 then
            result = 0
        else
            result = parameter_value * (normalized_length / parameter_length) + normalized_middle
        end
    else
        result = normalized_middle
    end

    if reflect then
        return result
    else
        return -result
    end
end

local function weighted_normalized_value(value, parameter, normalization, reflect, weight_percent)
    return physics.normalize_physics_parameter(value, parameter, normalization, reflect)
        * (weight_percent / MAXIMUM_WEIGHT)
end

function physics.physics_output_translation_x(translation, reflect)
    local value = translation:x()
    if reflect then return -value else return value end
end

function physics.physics_output_translation_y(translation, reflect)
    local value = translation:y()
    if reflect then return -value else return value end
end

function physics.parent_gravity_for_physics_output(particles, particle_index, parent_gravity)
    -- particles are Vector2[]
    if particle_index >= 2 then
        local current = particles[particle_index]
        local previous = particles[particle_index - 1]
        if current and previous then
            return Vector2.new(
                current:x() - previous:x(),
                current:y() - previous:y()
            )
        end
    end
    return Vector2.new(-parent_gravity:x(), -parent_gravity:y())
end

function physics.physics_output_angle_with_parent_gravity(translation, parent_gravity, reflect)
    local value = direction_to_radian(parent_gravity, translation)
    if reflect then return -value else return value end
end

function physics.update_physics_particles(strand, total_translation, total_angle, wind_direction, threshold_value, delta_time_seconds, air_resistance)
    if #strand < 2 then
        return
    end

    local first = strand[1]
    first.position = total_translation
    local current_gravity = vec_normalize(radian_to_direction(degrees_to_radian(total_angle)))
    local previous_position = first.position
    local current_gravity_x = current_gravity:x()
    local current_gravity_y = current_gravity:y()
    local wind_x = wind_direction:x()
    local wind_y = wind_direction:y()

    for p = 2, #strand do
        local particle = strand[p]
        local force = particle.force
        local force_x = current_gravity_x * particle.acceleration + wind_x
        local force_y = current_gravity_y * particle.acceleration + wind_y
        force._x = force_x
        force._y = force_y

        local position = particle.position
        local last_position = particle.last_position
        local last_x = position:x()
        local last_y = position:y()
        last_position._x = last_x
        last_position._y = last_y

        local delay = particle.delay * delta_time_seconds * 30
        local previous_x = previous_position:x()
        local previous_y = previous_position:y()
        local direction_x = last_x - previous_x
        local direction_y = last_y - previous_y
        local radian = direction_to_radian(particle.last_gravity, current_gravity) / air_resistance
        local sin_radian = sin(radian)
        local cos_radian = cos(radian)

        local rotated_x = cos_radian * direction_x - direction_y * sin_radian
        local rotated_y = sin_radian * direction_x + direction_y * cos_radian

        local delay_sq = delay * delay
        local position_x = previous_x + rotated_x + particle.velocity:x() * delay + force_x * delay_sq
        local position_y = previous_y + rotated_y + particle.velocity:y() * delay + force_y * delay_sq

        local new_direction_x = position_x - previous_x
        local new_direction_y = position_y - previous_y
        local length = sqrt(new_direction_x * new_direction_x + new_direction_y * new_direction_y)
        if length ~= 0 then
            new_direction_x = new_direction_x / length
            new_direction_y = new_direction_y / length
        end
        position_x = previous_x + new_direction_x * particle.radius
        position_y = previous_y + new_direction_y * particle.radius

        if abs(position_x) < threshold_value then
            position_x = 0
        end

        if delay ~= 0 then
            local velocity = particle.velocity
            velocity._x = ((position_x - last_x) / delay) * particle.mobility
            velocity._y = ((position_y - last_y) / delay) * particle.mobility
        end

        position._x = position_x
        position._y = position_y
        force._x = 0
        force._y = 0
        particle.last_gravity = current_gravity
        previous_position = particle.position
    end
end

function physics.stabilize_physics_particles(strand, total_translation, total_angle, wind_direction, threshold_value)
    if #strand < 2 then
        return
    end

    local first = strand[1]
    first.position = total_translation
    local current_gravity = vec_normalize(radian_to_direction(degrees_to_radian(total_angle)))
    local previous_position = first.position
    local current_gravity_x = current_gravity:x()
    local current_gravity_y = current_gravity:y()
    local wind_x = wind_direction:x()
    local wind_y = wind_direction:y()

    for p = 2, #strand do
        local particle = strand[p]
        local force = particle.force
        local force_x = current_gravity_x * particle.acceleration + wind_x
        local force_y = current_gravity_y * particle.acceleration + wind_y
        force._x = force_x
        force._y = force_y

        local position = particle.position
        particle.last_position._x = position:x()
        particle.last_position._y = position:y()
        particle.velocity._x = 0
        particle.velocity._y = 0

        local length = sqrt(force_x * force_x + force_y * force_y)
        if length ~= 0 then
            force_x = force_x / length
            force_y = force_y / length
        end
        local position_x = previous_position:x() + force_x * particle.radius
        local position_y = previous_position:y() + force_y * particle.radius

        if abs(position_x) < threshold_value then
            position_x = 0
        end

        position._x = position_x
        position._y = position_y
        force._x = 0
        force._y = 0
        particle.last_gravity = current_gravity
        previous_position = particle.position
    end
end

return physics
