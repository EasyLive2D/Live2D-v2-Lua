local AMotion = require("live2d.core.motion.amotion")
local Live2DFramework = require("live2d.framework.Live2DFramework")
local L2DExpressionParam = require("live2d.framework.motion.l2d_expression_param")

local L2DExpressionMotion = setmetatable({}, { __index = AMotion })
L2DExpressionMotion.__index = L2DExpressionMotion

L2DExpressionMotion.EXPRESSION_DEFAULT = "DEFAULT"
L2DExpressionMotion.TYPE_SET = 0
L2DExpressionMotion.TYPE_ADD = 1
L2DExpressionMotion.TYPE_MULT = 2

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
    local js = pm:jsonParseFromBytes(buf)
    local fade_in = tonumber(js["fade_in"]) or 0
    local fade_out = tonumber(js["fade_out"]) or 0
    ret:setFadeIn(fade_in > 0 and fade_in or 1000)
    ret:setFadeOut(fade_out > 0 and fade_out or 1000)

    local params = js["params"]
    if params == nil then return ret end

    local param_num = #params
    ret.paramList = {}
    for i = 1, param_num do
        local param = params[i]
        local param_id = tostring(param["id"])
        local value = tonumber(param["val"])
        local calc = param["calc"] or "add"
        local calc_type_int
        if calc == "add" then
            calc_type_int = L2DExpressionMotion.TYPE_ADD
        elseif calc == "mult" then
            calc_type_int = L2DExpressionMotion.TYPE_MULT
        elseif calc == "set" then
            calc_type_int = L2DExpressionMotion.TYPE_SET
        else
            calc_type_int = L2DExpressionMotion.TYPE_ADD
        end

        if calc_type_int == L2DExpressionMotion.TYPE_ADD then
            local default_value = tonumber(param["def"]) or 0
            value = value - default_value
        elseif calc_type_int == L2DExpressionMotion.TYPE_MULT then
            local default_value = tonumber(param["def"]) or 1
            if default_value == 0 then default_value = 1 end
            value = value / default_value
        end

        local item = L2DExpressionParam.new()
        item.id = param_id
        item.type = calc_type_int
        item.value = value
        ret.paramList[#ret.paramList + 1] = item
    end
    return ret
end

return L2DExpressionMotion
