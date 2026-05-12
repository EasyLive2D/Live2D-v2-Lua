local PhysicsHair = require("live2d.core.physics.physics_hair")
local UtSystem = require("live2d.core.util.ut_system")
local Live2DFramework = require("live2d.framework.Live2DFramework")

local L2DPhysics = {}
L2DPhysics.__index = L2DPhysics

function L2DPhysics.new()
    local self = setmetatable({}, L2DPhysics)
    self.physicsList = {}
    self.startTimeMSec = UtSystem.getUserTimeMSec()
    return self
end

function L2DPhysics:updateParam(model)
    local time_m_sec = UtSystem.getUserTimeMSec() - self.startTimeMSec
    for i = 1, #self.physicsList do
        self.physicsList[i]:update(model, time_m_sec)
    end
end

function L2DPhysics.load(buf)
    local ret = L2DPhysics.new()
    local pm = Live2DFramework.getPlatformManager()
    local json = pm:jsonParseFromBytes(buf)
    local params = json["physics_hair"]
    if params == nil then return ret end
    local param_num = #params
    for i = 1, param_num do
        local param = params[i]
        local physics = PhysicsHair.new()
        local setup = param["setup"]
        local length = tonumber(setup["length"])
        local resist = tonumber(setup["regist"])
        local mass = tonumber(setup["mass"])
        physics:setup(length, resist, mass)

        local src_list = param["src"]
        if src_list then
            for j = 1, #src_list do
                local src = src_list[j]
                local tid = src["id"]
                local type_str = src["ptype"]
                local t
                if type_str == "x" then t = PhysicsHair.SRC_TO_X
                elseif type_str == "y" then t = PhysicsHair.SRC_TO_Y
                elseif type_str == "angle" then t = PhysicsHair.SRC_TO_G_ANGLE
                else error("error") end
                local scale = tonumber(src["scale"])
                local weight = tonumber(src["weight"])
                physics:addSrcParam(t, tid, scale, weight)
            end
        end

        local target_list = param["targets"]
        if target_list then
            for j = 1, #target_list do
                local target = target_list[j]
                local tid = target["id"]
                local type_str = target["ptype"]
                local t
                if type_str == "angle" then t = PhysicsHair.TARGET_FROM_ANGLE
                elseif type_str == "angle_v" then t = PhysicsHair.TARGET_FROM_ANGLE_V
                else error("Invalid parameter:PhysicsHair.Target") end
                local scale = tonumber(target["scale"])
                local weight = tonumber(target["weight"])
                physics:addTargetParam(t, tid, scale, weight)
            end
        end
        ret.physicsList[#ret.physicsList + 1] = physics
    end
    return ret
end

return L2DPhysics
