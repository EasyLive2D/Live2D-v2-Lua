local AMotion = require("live2d.core.motion.amotion")
local Live2DFramework = require("live2d.framework.Live2DFramework")
local L2DExpressionParam = require("live2d.framework.motion.l2d_expression_param")
local json = require("live2d.dkjson")

local L2DExpressionMotion = setmetatable({}, { __index = AMotion })
L2DExpressionMotion.__index = L2DExpressionMotion

L2DExpressionMotion.EXPRESSION_DEFAULT = "DEFAULT"
L2DExpressionMotion.TYPE_SET = 0
L2DExpressionMotion.TYPE_ADD = 1
L2DExpressionMotion.TYPE_MULT = 2

local function first_number(obj, keys, default)
    for _, key in ipairs(keys) do
        local value = tonumber(obj[key])
        if value ~= nil then return value end
    end
    return default
end

local function positive_or_default(value, default)
    if value == nil then return default end
    return value > 0 and value or default
end

local function get_blend_type(blend)
    if blend == nil then return L2DExpressionMotion.TYPE_ADD end

    if type(blend) == "number" then
        if blend == 1 then return L2DExpressionMotion.TYPE_ADD end
        if blend == 2 then return L2DExpressionMotion.TYPE_MULT end
        if blend == 3 then return L2DExpressionMotion.TYPE_SET end
    end

    blend = tostring(blend)
    if blend == "add" or blend == "Add" then
        return L2DExpressionMotion.TYPE_ADD
    elseif blend == "mult" or blend == "Multiply" then
        return L2DExpressionMotion.TYPE_MULT
    elseif blend == "set" or blend == "Overwrite" then
        return L2DExpressionMotion.TYPE_SET
    end

    return L2DExpressionMotion.TYPE_ADD
end

function L2DExpressionMotion.new()
    local self = setmetatable(AMotion.new(), L2DExpressionMotion)
    self.paramList = {}
    return self
end

function L2DExpressionMotion:updateParamExe(model, timeMSec, weight, motionQueueEnt)
    for i = #self.paramList, 1, -1 do
        local param = self.paramList[i]
        if param.type == L2DExpressionMotion.TYPE_ADD then
            model:addToParamFloat(param.id, param.value, weight)
        elseif param.type == L2DExpressionMotion.TYPE_MULT then
            model:multParamFloat(param.id, param.value, weight)
        elseif param.type == L2DExpressionMotion.TYPE_SET then
            model:setParamFloat(param.id, param.value, weight)
        end
    end
end

function L2DExpressionMotion.loadJson(buf)
    local ret = L2DExpressionMotion.new()
    local pm = Live2DFramework.getPlatformManager()
    local js = pm and pm:jsonParseFromBytes(buf) or json.decode(buf)
    local is_exp3 = js["Parameters"] ~= nil
    local fade_in = first_number(js, is_exp3 and { "FadeInTime" } or { "fade_in" }, nil)
    local fade_out = first_number(js, is_exp3 and { "FadeOutTime" } or { "fade_out" }, nil)
    if is_exp3 then
        ret:setFadeIn(fade_in ~= nil and fade_in * 1000 or 1000)
        ret:setFadeOut(fade_out ~= nil and fade_out * 1000 or 1000)
    else
        ret:setFadeIn(positive_or_default(fade_in, 1000))
        ret:setFadeOut(positive_or_default(fade_out, 1000))
    end

    local params = is_exp3 and js["Parameters"] or js["params"]
    if params == nil then return ret end

    local param_num = #params
    ret.paramList = {}
    for i = 1, param_num do
        local param = params[i]
        local param_id = tostring(is_exp3 and param["Id"] or param["id"])
        local value = tonumber(is_exp3 and param["Value"] or param["val"])
        local calc_type_int = get_blend_type(is_exp3 and param["Blend"] or param["calc"])

        if not is_exp3 and calc_type_int == L2DExpressionMotion.TYPE_ADD then
            local default_value = tonumber(param["def"]) or 0
            value = value - default_value
        elseif not is_exp3 and calc_type_int == L2DExpressionMotion.TYPE_MULT then
            local default_value = tonumber(param["def"]) or 1
            if default_value == 0 then default_value = 1 end
            value = value / default_value
        end

        local expressionParam = L2DExpressionParam.new()
        expressionParam.id = param_id
        expressionParam.type = calc_type_int
        expressionParam.value = value
        ret.paramList[#ret.paramList + 1] = expressionParam
    end
    return ret
end

return L2DExpressionMotion
