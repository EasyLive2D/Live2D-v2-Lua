-- Core math types and functions for Cubism 3
-- Ported from Mocari src/core/math.rs

local math_lib = math
local atan2 = math_lib.atan2
local cos = math_lib.cos
local pi = math_lib.pi
local sin = math_lib.sin

local Vector2 = {}

local function vector2_x(self)
    return self._x
end

local function vector2_y(self)
    return self._y
end

function Vector2.new(x, y)
    return { _x = x or 0, _y = y or 0, x = vector2_x, y = vector2_y }
end

Vector2.x = vector2_x

Vector2.y = vector2_y

-- Matrix44
local Matrix44 = {}
Matrix44.__index = Matrix44

function Matrix44.identity()
    return setmetatable({
        values = {
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        }
    }, Matrix44)
end

function Matrix44:as_list()
    return self.values
end

function Matrix44.multiply(a, b)
    local result = {}
    for i = 0, 3 do
        for j = 0, 3 do
            local sum = 0
            for k = 0, 3 do
                sum = sum + a[k + i * 4 + 1] * b[j + k * 4 + 1]
            end
            result[j + i * 4 + 1] = sum
        end
    end
    return result
end

function Matrix44:translate_relative(x, y)
    local translation = {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        x, y, 0, 1,
    }
    self.values = Matrix44.multiply(translation, self.values)
end

function Matrix44:translate(x, y)
    self.values[13] = x
    self.values[14] = y
end

function Matrix44:translate_x(x)
    self.values[13] = x
end

function Matrix44:translate_y(y)
    self.values[14] = y
end

function Matrix44:scale_relative(x, y)
    local scale = {
        x, 0, 0, 0,
        0, y, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }
    self.values = Matrix44.multiply(scale, self.values)
end

function Matrix44:scale(x, y)
    self.values[1] = x
    self.values[6] = y
end

function Matrix44:scale_x()
    return self.values[1]
end

function Matrix44:scale_y()
    return self.values[6]
end

function Matrix44:transform_x(value)
    return self.values[1] * value + self.values[13]
end

function Matrix44:transform_y(value)
    return self.values[6] * value + self.values[14]
end

function Matrix44:invert_transform_x(value)
    return (value - self.values[13]) / self.values[1]
end

function Matrix44:invert_transform_y(value)
    return (value - self.values[14]) / self.values[6]
end

-- ModelMatrix
local ModelMatrix = {}
ModelMatrix.__index = ModelMatrix

function ModelMatrix.new(width, height)
    local self = setmetatable({
        width = width,
        height = height,
        matrix = Matrix44.identity(),
    }, ModelMatrix)
    self:set_height(2)
    return self
end

function ModelMatrix:setup_from_layout(layout)
    if layout.width ~= nil then self:set_width(layout.width) end
    if layout.height ~= nil then self:set_height(layout.height) end
    if layout.x ~= nil then self:set_x(layout.x) end
    if layout.y ~= nil then self:set_y(layout.y) end
    if layout.center_x ~= nil then self:center_x(layout.center_x) end
    if layout.center_y ~= nil then self:center_y(layout.center_y) end
    if layout.top ~= nil then self:top(layout.top) end
    if layout.bottom ~= nil then self:bottom(layout.bottom) end
    if layout.left ~= nil then self:left(layout.left) end
    if layout.right ~= nil then self:right(layout.right) end
end

function ModelMatrix:set_position(x, y)
    self.matrix:translate(x, y)
end

function ModelMatrix:set_center_position(x, y)
    self:center_x(x)
    self:center_y(y)
end

function ModelMatrix:top(y)
    self:set_y(y)
end

function ModelMatrix:bottom(y)
    local height = self.height * self.matrix:scale_y()
    self.matrix:translate_y(y - height)
end

function ModelMatrix:left(x)
    self:set_x(x)
end

function ModelMatrix:right(x)
    local width = self.width * self.matrix:scale_x()
    self.matrix:translate_x(x - width)
end

function ModelMatrix:center_x(x)
    local width = self.width * self.matrix:scale_x()
    self.matrix:translate_x(x - width / 2)
end

function ModelMatrix:center_y(y)
    local height = self.height * self.matrix:scale_y()
    self.matrix:translate_y(y - height / 2)
end

function ModelMatrix:set_x(x)
    self.matrix:translate_x(x)
end

function ModelMatrix:set_y(y)
    self.matrix:translate_y(y)
end

function ModelMatrix:set_width(width)
    local scale = width / self.width
    self.matrix:scale(scale, scale)
end

function ModelMatrix:set_height(height)
    local scale = height / self.height
    self.matrix:scale(scale, scale)
end

function ModelMatrix:transform_x(value)
    return self.matrix:transform_x(value)
end

function ModelMatrix:transform_y(value)
    return self.matrix:transform_y(value)
end

function ModelMatrix:get_matrix()
    return self.matrix
end

-- Angle utilities
local function degrees_to_radian(degrees)
    return (degrees / 180) * pi
end

local function radian_to_degrees(radian)
    return (radian * 180) / pi
end

local function direction_to_radian(from, to)
    local result = atan2(to:y(), to:x()) - atan2(from:y(), from:x())
    while result < -pi do
        result = result + pi * 2
    end
    while result > pi do
        result = result - pi * 2
    end
    return result
end

local function radian_to_direction(radian)
    return Vector2.new(sin(radian), cos(radian))
end

return {
    Vector2 = Vector2,
    Matrix44 = Matrix44,
    ModelMatrix = ModelMatrix,
    degrees_to_radian = degrees_to_radian,
    radian_to_degrees = radian_to_degrees,
    direction_to_radian = direction_to_radian,
    radian_to_direction = radian_to_direction,
}
