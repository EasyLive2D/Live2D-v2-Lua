-- Physics simulation for Cubism 3
-- Ported from Mocari src/core/physics.rs

local math_lib = math
local Vector2 = require("live2d.cubism3.core.math").Vector2
local direction_to_radian = require("live2d.cubism3.core.math").direction_to_radian
local radian_to_direction = require("live2d.cubism3.core.math").radian_to_direction
local degrees_to_radian = require("live2d.cubism3.core.math").degrees_to_radian

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
    local length = math_lib.sqrt(value:x() * value:x() + value:y() * value:y())
    if length == 0 then
        return value
    end
    return vec_div(value, length)
end

function physics.normalize_physics_parameter(value, parameter, normalized, reflect)
    local maximum = math.max(parameter.maximum, parameter.minimum)
    local minimum = math.min(parameter.maximum, parameter.minimum)
    value = math.max(minimum, math.min(maximum, value))
    local normalized_minimum = math.min(normalized.minimum, normalized.maximum)
    local normalized_maximum = math.max(normalized.minimum, normalized.maximum)
    local normalized_middle = normalized.default
    local middle = minimum + math.abs(maximum - minimum) / 2
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

    for p = 2, #strand do
        local particle = strand[p]
        particle.force = vec_add(vec_mul(current_gravity, particle.acceleration), wind_direction)
        particle.last_position = particle.position

        local delay = particle.delay * delta_time_seconds * 30
        local direction = vec_sub(particle.position, previous_position)
        local radian = direction_to_radian(particle.last_gravity, current_gravity) / air_resistance

        local direction_x = math_lib.cos(radian) * direction:x() - direction:y() * math_lib.sin(radian)
        local direction_y = math_lib.sin(radian) * direction:x() + direction:y() * math_lib.cos(radian)
        direction = Vector2.new(direction_x, direction_y)

        particle.position = vec_add(previous_position, direction)
        local velocity = vec_mul(particle.velocity, delay)
        local force = vec_mul(particle.force, delay * delay)
        particle.position = vec_add(vec_add(particle.position, velocity), force)

        local new_direction = vec_normalize(vec_sub(particle.position, previous_position))
        particle.position = vec_add(previous_position, vec_mul(new_direction, particle.radius))

        if math_lib.abs(particle.position:x()) < threshold_value then
            particle.position = Vector2.new(0, particle.position:y())
        end

        if delay ~= 0 then
            particle.velocity = vec_mul(
                vec_div(vec_sub(particle.position, particle.last_position), delay),
                particle.mobility
            )
        end

        particle.force = Vector2.new(0, 0)
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

    for p = 2, #strand do
        local particle = strand[p]
        particle.force = vec_add(vec_mul(current_gravity, particle.acceleration), wind_direction)
        particle.last_position = particle.position
        particle.velocity = Vector2.new(0, 0)

        local force = vec_mul(vec_normalize(particle.force), particle.radius)
        particle.position = vec_add(previous_position, force)

        if math_lib.abs(particle.position:x()) < threshold_value then
            particle.position = Vector2.new(0, particle.position:y())
        end

        particle.force = Vector2.new(0, 0)
        particle.last_gravity = current_gravity
        previous_position = particle.position
    end
end

return physics
