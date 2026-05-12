local Live2DFramework = require("live2d.framework.Live2DFramework")
local json = require("live2d.dkjson")  -- will need dkjson or use ffi cjson

local ModelSettingJson = {}
ModelSettingJson.__index = ModelSettingJson

function ModelSettingJson.new()
    local self = setmetatable({}, ModelSettingJson)
    self._json = {}
    return self
end

function ModelSettingJson:loadModelSetting(path)
    local pm = Live2DFramework.getPlatformManager()
    local buf = pm:loadBytes(path)
    self._json = pm:jsonParseFromBytes(buf)
end

function ModelSettingJson:getModelFile()
    return self._json["model"]
end

function ModelSettingJson:getTextureNum()
    return self._json["textures"] and #self._json["textures"] or 0
end

function ModelSettingJson:getTextureFile(no)
    return self._json["textures"][no + 1]
end

function ModelSettingJson:getHitAreaNum()
    return self._json["hit_areas"] and #self._json["hit_areas"] or 0
end

function ModelSettingJson:getHitAreaName(i)
    return self._json["hit_areas"][i + 1]["name"]
end

function ModelSettingJson:getHitAreaID(i)
    return self._json["hit_areas"][i + 1]["id"]
end

function ModelSettingJson:getExpressionNum()
    return self._json["expressions"] and #self._json["expressions"] or 0
end

function ModelSettingJson:getExpressionName(j)
    return self._json["expressions"][j + 1]["name"]
end

function ModelSettingJson:getExpressionFile(j)
    return self._json["expressions"][j + 1]["file"]
end

function ModelSettingJson:getPhysicsFile()
    return self._json["physics"]
end

function ModelSettingJson:getPoseFile()
    return self._json["pose"]
end

function ModelSettingJson:getLayout()
    return self._json["layout"]
end

function ModelSettingJson:getInitParamNum()
    return self._json["init_params"] and #self._json["init_params"] or 0
end

function ModelSettingJson:getInitParamID(j)
    return self._json["init_params"][j + 1]["id"]
end

function ModelSettingJson:getInitParamValue(j)
    return self._json["init_params"][j + 1]["value"]
end

function ModelSettingJson:getInitPartsVisibleNum()
    return self._json["init_parts_visible"] and #self._json["init_parts_visible"] or 0
end

function ModelSettingJson:getInitPartsVisibleID(j)
    return self._json["init_parts_visible"][j + 1]["id"]
end

function ModelSettingJson:getInitPartsVisibleValue(j)
    return self._json["init_parts_visible"][j + 1]["value"]
end

function ModelSettingJson:getMotionNames()
    return self._json["motions"] and self._getKeys(self._json["motions"]) or nil
end

function ModelSettingJson:getMotionNum(name)
    local group = self._json["motions"] and self._json["motions"][name]
    if group == nil then return 0 end
    return #group
end

function ModelSettingJson:getMotionFile(name, no)
    local group = self._json["motions"][name]
    if group == nil then return nil end
    return group[no + 1]["file"]
end

function ModelSettingJson:getMotionFadeIn(name, no)
    local group = self._json["motions"][name]
    if group == nil then return 1000 end
    return group[no + 1]["fade_in"] or 1000
end

function ModelSettingJson:getMotionFadeOut(name, no)
    local group = self._json["motions"][name]
    if group == nil then return 1000 end
    return group[no + 1]["fade_out"] or 1000
end

function ModelSettingJson._getKeys(t)
    local keys = {}
    for k, _ in pairs(t) do
        keys[#keys + 1] = k
    end
    return keys
end

return ModelSettingJson
