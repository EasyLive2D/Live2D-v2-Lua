local Live2DFramework = require("live2d.framework.Live2DFramework")
local L2DPartsParam = require("live2d.framework.pose.l2d_parts_param")
local UtSystem = require("live2d.core.util.ut_system")

local L2DPose = {}
L2DPose.__index = L2DPose

function L2DPose.new()
    local self = setmetatable({}, L2DPose)
    self.lastTime = 0
    self.lastModel = nil
    self.partsGroups = {}
    return self
end

function L2DPose:updateParam(model)
    if model ~= self.lastModel then
        self:initParam(model)
    end
    self.lastModel = model
    local cur_time = UtSystem.getUserTimeMSec()
    local delta_time_sec = (self.lastTime == 0) and 0 or ((cur_time - self.lastTime) / 1000.0)
    self.lastTime = cur_time
    if delta_time_sec < 0 then delta_time_sec = 0 end
    for i = 1, #self.partsGroups do
        L2DPose.normalizePartsOpacityGroup(model, self.partsGroups[i], delta_time_sec)
        L2DPose.copyOpacityOtherParts(model, self.partsGroups[i])
    end
end

function L2DPose:initParam(model)
    for i = 1, #self.partsGroups do
        local parts_group = self.partsGroups[i]
        for j = 1, #parts_group do
            parts_group[j]:initIndex(model)
            local parts_index = parts_group[j].partsIndex
            local param_index = parts_group[j].paramIndex
            if parts_index >= 0 then
                local v = model:getParamFloat(param_index) ~= 0
                model:setPartsOpacity(parts_index, v and 1.0 or 0.0)
                model:setParamFloat(param_index, v and 1.0 or 0.0)
            end
            if parts_group[j].link ~= nil then
                for k = 1, #parts_group[j].link do
                    parts_group[j].link[k]:initIndex(model)
                end
            end
        end
    end
end

function L2DPose.normalizePartsOpacityGroup(model, partsGroup, deltaTimeSec)
    local visible_parts = -1
    local visible_opacity = 1.0
    local clear_time_sec = 0.5
    local phi = 0.5
    local max_back_opacity = 0.15

    for i = 1, #partsGroup do
        local parts_index = partsGroup[i].partsIndex
        local param_index = partsGroup[i].paramIndex
        if parts_index >= 0 and model:getParamFloat(param_index) ~= 0 then
            if visible_parts >= 0 then break end
            visible_parts = i
            visible_opacity = model:getPartsOpacity(parts_index)
            visible_opacity = visible_opacity + deltaTimeSec / clear_time_sec
            if visible_opacity > 1 then visible_opacity = 1 end
        end
    end

    if visible_parts < 0 then
        visible_parts = 1
        visible_opacity = 1
    end

    for i = 1, #partsGroup do
        local parts_index = partsGroup[i].partsIndex
        if parts_index >= 0 then
            if visible_parts == i then
                model:setPartsOpacity(parts_index, visible_opacity)
            else
                local opacity = model:getPartsOpacity(parts_index)
                local a1
                if visible_opacity < phi then
                    a1 = visible_opacity * (phi - 1) / phi + 1
                else
                    a1 = (1 - visible_opacity) * phi / (1 - phi)
                end
                local back_op = (1 - a1) * (1 - visible_opacity)
                if back_op > max_back_opacity then
                    a1 = 1 - max_back_opacity / (1 - visible_opacity)
                end
                opacity = math.min(opacity, a1)
                model:setPartsOpacity(parts_index, opacity)
            end
        end
    end
end

function L2DPose.copyOpacityOtherParts(model, partsGroup)
    for i = 1, #partsGroup do
        local parts_param = partsGroup[i]
        if parts_param.link ~= nil and parts_param.partsIndex >= 0 then
            local opacity = model:getPartsOpacity(parts_param.partsIndex)
            for l = 1, #parts_param.link do
                local link_parts = parts_param.link[l]
                if link_parts.partsIndex >= 0 then
                    model:setPartsOpacity(link_parts.partsIndex, opacity)
                end
            end
        end
    end
end

function L2DPose.load(buf)
    local ret = L2DPose.new()
    local pm = Live2DFramework.getPlatformManager()
    local json = pm:jsonParseFromBytes(buf)
    local pose_list_info = json["parts_visible"]
    if pose_list_info == nil then return ret end
    local pose_num = #pose_list_info
    for ip = 1, pose_num do
        local pose_info = pose_list_info[ip]
        local id_list_info = pose_info["group"]
        if id_list_info then
            local id_num = #id_list_info
            local parts_group = {}
            for ig = 1, id_num do
                local parts_info = id_list_info[ig]
                local parts = L2DPartsParam.new(parts_info["id"])
                parts_group[#parts_group + 1] = parts
                local link_list_info = parts_info["link"]
                if link_list_info then
                    parts.link = {}
                    for il = 1, #link_list_info do
                        local link_parts = L2DPartsParam.new(link_list_info[il])
                        parts.link[#parts.link + 1] = link_parts
                    end
                end
            end
            ret.partsGroups[#ret.partsGroups + 1] = parts_group
        end
    end
    return ret
end

return L2DPose
