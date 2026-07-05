-- Motion3 JSON parser and curve sampling for Cubism 3
-- Ported from Mocari src/json/motion3.rs

local json = require("live2d.dkjson")
local math_lib = math

local motion3 = {}

local SUPPORTED_VERSION = 3

-- Easing
function motion3.easing_sine(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return 0.5 - 0.5 * math_lib.cos(value * math_lib.pi)
end

function motion3.motion_fade_in_weight(user_time_seconds, fade_in_start_time, fade_in_seconds)
    if fade_in_seconds <= 0 then
        return 1
    end
    return motion3.easing_sine((user_time_seconds - fade_in_start_time) / fade_in_seconds)
end

function motion3.motion_fade_out_weight(user_time_seconds, end_time_seconds, fade_out_seconds)
    if fade_out_seconds <= 0 or end_time_seconds < 0 then
        return 1
    end
    return motion3.easing_sine((end_time_seconds - user_time_seconds) / fade_out_seconds)
end

function motion3.parameter_curve_fade_weight(motion_weight, motion_fade_in, motion_fade_out,
    curve_fade_in_seconds, curve_fade_out_seconds,
    user_time_seconds, fade_in_start_time, end_time_seconds)
    if curve_fade_in_seconds ~= nil and curve_fade_in_seconds < 0 then
        curve_fade_in_seconds = nil
    end
    if curve_fade_out_seconds ~= nil and curve_fade_out_seconds < 0 then
        curve_fade_out_seconds = nil
    end

    if curve_fade_in_seconds == nil and curve_fade_out_seconds == nil then
        return motion_weight * motion_fade_in * motion_fade_out
    end

    local fade_in
    if curve_fade_in_seconds == nil then
        fade_in = motion_fade_in
    elseif curve_fade_in_seconds == 0 then
        fade_in = 1
    else
        fade_in = motion3.easing_sine((user_time_seconds - fade_in_start_time) / curve_fade_in_seconds)
    end

    local fade_out
    if curve_fade_out_seconds == nil then
        fade_out = motion_fade_out
    elseif curve_fade_out_seconds == 0 then
        fade_out = 1
    elseif end_time_seconds < 0 then
        fade_out = 1
    else
        fade_out = motion3.easing_sine((end_time_seconds - user_time_seconds) / curve_fade_out_seconds)
    end

    return motion_weight * fade_in * fade_out
end

function motion3.apply_motion_fade(source_value, target_value, fade_weight)
    return source_value + (target_value - source_value) * fade_weight
end

-- MotionPoint
local MotionPoint = {}
MotionPoint.__index = MotionPoint
function MotionPoint.new(time, value)
    return setmetatable({ time = time, value = value }, MotionPoint)
end

-- Lerp
local function lerp_point(a, b, t)
    return MotionPoint.new(
        a.time + (b.time - a.time) * t,
        a.value + (b.value - a.value) * t
    )
end

-- Cubic bezier
local function cubic_bezier_point(start, control1, control2, end_p, t)
    local p01 = lerp_point(start, control1, t)
    local p12 = lerp_point(control1, control2, t)
    local p23 = lerp_point(control2, end_p, t)
    local p012 = lerp_point(p01, p12, t)
    local p123 = lerp_point(p12, p23, t)
    return lerp_point(p012, p123, t)
end

-- Quadratic equation solver
local function quadratic_equation(a, b, c)
    local EPSILON = 0.00001
    if math_lib.abs(a) < EPSILON then
        if math_lib.abs(b) < EPSILON then
            return -c
        end
        return -c / b
    end
    local sqrt_disc = math_lib.sqrt(b * b - 4 * a * c)
    return -(b + sqrt_disc) / (2 * a)
end

-- Cardano algorithm for cubic bezier time
local function cardano_algorithm_for_bezier(a, b, c, d)
    local EPSILON = 0.00001
    local CENTER = 0.5
    local THRESHOLD = CENTER + 0.01

    if math_lib.abs(a) < EPSILON then
        return math.max(0, math.min(1, quadratic_equation(b, c, d)))
    end

    local normalizedB = b / a
    local normalizedC = c / a
    local normalizedD = d / a
    local depressedP = (3 * normalizedC - normalizedB * normalizedB) / 3
    local pOver3 = depressedP / 3
    local depressedQ = (2 * normalizedB * normalizedB * normalizedB - 9 * normalizedB * normalizedC + 27 * normalizedD) / 27
    local qOver2 = depressedQ / 2
    local discriminant = qOver2 * qOver2 + pOver3 * pOver3 * pOver3

    if discriminant < 0 then
        local negativePOver3 = -depressedP / 3
        local mp3Cubed = negativePOver3 * negativePOver3 * negativePOver3
        local sqrtMp33 = math_lib.sqrt(mp3Cubed)
        local cosPhiRaw = -depressedQ / (2 * sqrtMp33)
        local cos_phi = math.max(-1, math.min(1, cosPhiRaw))
        local phi = math_lib.acos(cos_phi)
        local cubeRootR = sqrtMp33 ^ (1/3)
        local twoTimesCubeRootR = 2 * cubeRootR

        local root1 = twoTimesCubeRootR * math_lib.cos(phi / 3) - normalizedB / 3
        if math_lib.abs(root1 - CENTER) < THRESHOLD then
            return math.max(0, math.min(1, root1))
        end
        local root2 = twoTimesCubeRootR * math_lib.cos((phi + 2 * math_lib.pi) / 3) - normalizedB / 3
        if math_lib.abs(root2 - CENTER) < THRESHOLD then
            return math.max(0, math.min(1, root2))
        end
        local root3 = twoTimesCubeRootR * math_lib.cos((phi + 4 * math_lib.pi) / 3) - normalizedB / 3
        return math.max(0, math.min(1, root3))
    end

    if discriminant == 0 then
        local cubeRootPositive
        if qOver2 < 0 then
            cubeRootPositive = (-qOver2) ^ (1/3)
        else
            cubeRootPositive = -(qOver2 ^ (1/3))
        end
        local root1 = 2 * cubeRootPositive - normalizedB / 3
        if math_lib.abs(root1 - CENTER) < THRESHOLD then
            return math.max(0, math.min(1, root1))
        end
        local root2 = -cubeRootPositive - normalizedB / 3
        return math.max(0, math.min(1, root2))
    end

    local sqrtDiscriminant = math_lib.sqrt(discriminant)
    local cubeRoot = (sqrtDiscriminant - qOver2) ^ (1/3)
    local cubeRootNegative = (sqrtDiscriminant + qOver2) ^ (1/3)
    return math.max(0, math.min(1, cubeRoot - cubeRootNegative - normalizedB / 3))
end

-- Bezier time solver
local function solve_bezier_time(start, control1, control2, end_p, time)
    local a = end_p.time - 3 * control2.time + 3 * control1.time - start.time
    local b = 3 * control2.time - 6 * control1.time + 3 * start.time
    local c = 3 * control1.time - 3 * start.time
    local d = start.time - time
    return cardano_algorithm_for_bezier(a, b, c, d)
end

-- Sample linear
local function sample_linear(start, end_p, time)
    if start.time == end_p.time then
        return end_p.value
    end
    local amount = math.max(0, (time - start.time) / (end_p.time - start.time))
    return start.value + (end_p.value - start.value) * amount
end

-- Sample bezier
local function sample_bezier(start, control1, control2, end_p, time, are_beziers_restricted)
    local t
    if are_beziers_restricted then
        if start.time == end_p.time then
            t = 1
        else
            t = math.max(0, (time - start.time) / (end_p.time - start.time))
        end
    else
        t = solve_bezier_time(start, control1, control2, end_p, time)
    end
    return cubic_bezier_point(start, control1, control2, end_p, t).value
end

-- Parse segments from flat float array
local function parse_segments(values)
    if #values < 2 then
        return nil, "segments must start with a time/value point"
    end

    local first_point = MotionPoint.new(values[1], values[2])
    local cursor = 3
    local start = first_point
    local segments = {}

    while cursor <= #values do
        local segment_type = values[cursor]
        if segment_type ~= math.floor(segment_type) or segment_type < 0 or segment_type > 3 then
            return nil, "unsupported segment type " .. tostring(segment_type)
        end
        cursor = cursor + 1

        local function read_point()
            if cursor + 1 > #values then
                return nil, "segment point is incomplete"
            end
            local motionPoint = MotionPoint.new(values[cursor], values[cursor + 1])
            cursor = cursor + 2
            return motionPoint
        end

        if segment_type == 0 then
            local end_p, err = read_point()
            if not end_p then return nil, err end
            segments[#segments + 1] = {
                kind = "linear",
                start = start,
                ["end"] = end_p,
            }
            start = end_p
        elseif segment_type == 1 then
            local control1, err = read_point()
            if not control1 then return nil, err end
            local control2, err = read_point()
            if not control2 then return nil, err end
            local end_p, err = read_point()
            if not end_p then return nil, err end
            segments[#segments + 1] = {
                kind = "bezier",
                start = start,
                control1 = control1,
                control2 = control2,
                ["end"] = end_p,
            }
            start = end_p
        elseif segment_type == 2 then
            local end_p, err = read_point()
            if not end_p then return nil, err end
            segments[#segments + 1] = {
                kind = "stepped",
                start = start,
                ["end"] = end_p,
            }
            start = end_p
        elseif segment_type == 3 then
            local end_p, err = read_point()
            if not end_p then return nil, err end
            segments[#segments + 1] = {
                kind = "inverse_stepped",
                start = start,
                ["end"] = end_p,
            }
            start = end_p
        end
    end

    return first_point, segments
end

-- MotionCurve constructor
local MotionCurve = {}
MotionCurve.__index = MotionCurve

function MotionCurve.new(raw, are_beziers_restricted)
    local first_point, segments, err = parse_segments(raw.Segments or {})
    if not first_point then
        return nil, err
    end
    return setmetatable({
        target = raw.Target,
        id = raw.Id,
        first_point = first_point,
        segments = segments,
        fade_in_time = raw.FadeInTime,
        fade_out_time = raw.FadeOutTime,
        are_beziers_restricted = are_beziers_restricted,
    }, MotionCurve)
end

function MotionCurve:sample(time)
    if time <= self.first_point.time then
        return self.first_point.value
    end

    for _, segment in ipairs(self.segments) do
        if time < segment["end"].time then
            if segment.kind == "linear" then
                return sample_linear(segment.start, segment["end"], time)
            elseif segment.kind == "bezier" then
                return sample_bezier(segment.start, segment.control1, segment.control2, segment["end"], time, self.are_beziers_restricted)
            elseif segment.kind == "stepped" then
                return segment.start.value
            elseif segment.kind == "inverse_stepped" then
                return segment["end"].value
            end
        end
    end

    local last_segment = self.segments[#self.segments]
    if last_segment then
        return last_segment["end"].value
    end
    return self.first_point.value
end

function motion3.parse(source)
    local ok, raw = pcall(json.decode, source)
    if not ok then
        return nil, "Invalid motion3.json: " .. tostring(raw)
    end

    if raw.Version ~= SUPPORTED_VERSION then
        return nil, "Unsupported motion3.json version: " .. tostring(raw.Version)
    end

    local meta = raw.Meta or {}
    local are_beziers_restricted = meta.AreBeziersRestricted or false

    local curves = {}
    for _, crv in ipairs(raw.Curves or {}) do
        local curve, err = MotionCurve.new(crv, are_beziers_restricted)
        if not curve then
            return nil, err
        end
        curves[#curves + 1] = curve
    end

    return {
        version = raw.Version,
        meta = meta,
        curves = curves,
    }
end

return motion3
