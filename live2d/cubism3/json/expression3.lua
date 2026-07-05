-- Expression3 JSON parser for Cubism 3

local json = require("live2d.dkjson")

local expression3 = {}

expression3.DEFAULT_EXPRESSION_FADE_IN_TIME = 1.0
expression3.DEFAULT_EXPRESSION_FADE_OUT_TIME = 1.0

local function normalize_blend(value)
    if value == 2 or value == "Multiply" or value == "multiply" or value == "mult" then
        return "Multiply"
    end
    if value == 3 or value == "Overwrite" or value == "overwrite" or value == "set" then
        return "Overwrite"
    end
    return "Add"
end

local function clamp01(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function expression3.resolved_expression_fade_in_time(fade_in_time)
    if fade_in_time == nil then return expression3.DEFAULT_EXPRESSION_FADE_IN_TIME end
    return math.max(0, tonumber(fade_in_time) or 0)
end

function expression3.resolved_expression_fade_out_time(fade_out_time)
    if fade_out_time == nil then return expression3.DEFAULT_EXPRESSION_FADE_OUT_TIME end
    return math.max(0, tonumber(fade_out_time) or 0)
end

function expression3.resolved_fade_in_time(expression)
    return expression3.resolved_expression_fade_in_time(expression and expression.fade_in_time)
end

function expression3.resolved_fade_out_time(expression)
    return expression3.resolved_expression_fade_out_time(expression and expression.fade_out_time)
end

function expression3.apply_expression_blend(current, value, blend, weight)
    weight = clamp01(tonumber(weight) or 0)
    current = tonumber(current) or 0
    value = tonumber(value) or 0
    blend = normalize_blend(blend)

    if blend == "Multiply" then
        return current * (1.0 + (value - 1.0) * weight)
    elseif blend == "Overwrite" then
        if weight == 1.0 then return value end
        return current * (1.0 - weight) + value * weight
    end
    return current + value * weight
end

function expression3.apply_expression_parameter(current, parameter, weight)
    return expression3.apply_expression_blend(current, parameter.value, parameter.blend, weight)
end

function expression3.parse(source)
    local ok, raw = pcall(json.decode, source)
    if not ok then
        return nil, "Invalid exp3.json: " .. tostring(raw)
    end

    local parameters = {}
    for _, parameter in ipairs(raw.Parameters or {}) do
        parameters[#parameters + 1] = {
            id = tostring(parameter.Id),
            value = tonumber(parameter.Value) or 0,
            blend = normalize_blend(parameter.Blend),
        }
    end

    return {
        kind = raw.Type,
        fade_in_time = raw.FadeInTime,
        fade_out_time = raw.FadeOutTime,
        parameters = parameters,
    }
end

return expression3
