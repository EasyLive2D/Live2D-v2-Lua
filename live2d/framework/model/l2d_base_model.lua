local Live2DMotion = require("live2d.core.motion.live2d_motion")
local Live2DFramework = require("live2d.framework.Live2DFramework")
local L2DModelMatrix = require("live2d.framework.matrix.l2d_model_matrix")
local L2DExpressionMotion = require("live2d.framework.motion.l2d_expression_motion")
local L2DMotionManager = require("live2d.framework.motion.l2d_motion_manager")
local L2DPhysics = require("live2d.framework.physics.l2d_physics")
local L2DPose = require("live2d.framework.pose.l2d_pose")

local L2DBaseModel = {}
L2DBaseModel.__index = L2DBaseModel

L2DBaseModel.texCount = 0

function L2DBaseModel.new()
    local self = setmetatable({}, L2DBaseModel)
    self.live2DModel = nil
    self.modelMatrix = nil
    self.eyeBlink = nil
    self.physics = nil
    self.pose = nil
    self.dragX = 0
    self.dragY = 0
    self.startTimeMSec = 0
    self.mainMotionManager = L2DMotionManager.new()
    self.expressionManager = L2DMotionManager.new()
    self.motions = {}
    self.expressions = {}
    return self
end

function L2DBaseModel:setDrag(x, y) self.dragX = x; self.dragY = y end

function L2DBaseModel:loadModelData(path)
    local pm = Live2DFramework.getPlatformManager()
    self.live2DModel = pm:loadLive2DModel(path)
    self.live2DModel:saveParam()
    self.modelMatrix = L2DModelMatrix.new(self.live2DModel:getCanvasWidth(), self.live2DModel:getCanvasHeight())
    self.modelMatrix:setWidth(2)
    self.modelMatrix:setCenterPosition(0, 0)
    return self.live2DModel
end

function L2DBaseModel:loadTexture(no, path)
    L2DBaseModel.texCount = L2DBaseModel.texCount + 1
    local pm = Live2DFramework.getPlatformManager()
    pm:loadTexture(self.live2DModel, no, path)
    L2DBaseModel.texCount = L2DBaseModel.texCount - 1
end

function L2DBaseModel:loadMotion(name, path)
    local pm = Live2DFramework.getPlatformManager()
    local buf = pm:loadBytes(path)
    local motion = Live2DMotion.loadMotion(buf)
    if name ~= nil then
        self.motions[name] = motion
    end
    return motion
end

function L2DBaseModel:loadExpression(name, path)
    local pm = Live2DFramework.getPlatformManager()
    if name ~= nil then
        local buf = pm:loadBytes(path)
        self.expressions[name] = L2DExpressionMotion.loadJson(buf)
    end
end

function L2DBaseModel:loadPose(path)
    local pm = Live2DFramework.getPlatformManager()
    local buf = pm:loadBytes(path)
    self.pose = L2DPose.load(buf)
    return self.pose
end

function L2DBaseModel:loadPhysics(path)
    local pm = Live2DFramework.getPlatformManager()
    local buf = pm:loadBytes(path)
    self.physics = L2DPhysics.load(buf)
end

return L2DBaseModel
