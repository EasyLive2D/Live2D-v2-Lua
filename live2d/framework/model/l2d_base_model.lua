local Live2DModelOpenGL = require("live2d.core.live2d_model_opengl")
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
    self.debugMode = false
    self.initialized = false
    self.updating = false
    self.alpha = 1
    self.accAlpha = 0
    self.accelX = 0
    self.accelY = 0
    self.accelZ = 0
    self.dragX = 0
    self.dragY = 0
    self.startTimeMSec = 0
    self.mainMotionManager = L2DMotionManager.new()
    self.expressionManager = L2DMotionManager.new()
    self.motions = {}
    self.expressions = {}
    self.isTexLoaded = false
    return self
end

function L2DBaseModel:getModelMatrix() return self.modelMatrix end

function L2DBaseModel:setAlpha(a)
    if a > 0.999 then a = 1 end
    if a < 0.001 then a = 0 end
    self.alpha = a
end

function L2DBaseModel:getAlpha() return self.alpha end
function L2DBaseModel:isInitialized() return self.initialized end
function L2DBaseModel:setInitialized(v) self.initialized = v end
function L2DBaseModel:isUpdating() return self.updating end
function L2DBaseModel:setUpdating(v) self.updating = v end
function L2DBaseModel:getLive2DModel() return self.live2DModel end
function L2DBaseModel:setAccel(x, y, z) self.accelX = x; self.accelY = y; self.accelZ = z end
function L2DBaseModel:setDrag(x, y) self.dragX = x; self.dragY = y end
function L2DBaseModel:getMainMotionManager() return self.mainMotionManager end
function L2DBaseModel:getExpressionManager() return self.expressionManager end

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
    if L2DBaseModel.texCount == 0 then
        self.isTexLoaded = true
    end
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

function L2DBaseModel:hitTestSimple(drawID, testX, testY)
    local draw_index = self.live2DModel:getDrawDataIndex(drawID)
    if draw_index < 0 then return false end
    local points = self.live2DModel:getTransformedPoints(draw_index)
    if points == nil then return false end
    local left = self.live2DModel:getCanvasWidth()
    local right = 0
    local top = self.live2DModel:getCanvasHeight()
    local bottom = 0
    for j = 1, #points, 2 do
        local x = points[j]
        local y = points[j + 1]
        if x < left then left = x end
        if x > right then right = x end
        if y < top then top = y end
        if y > bottom then bottom = y end
    end
    local tx = self.modelMatrix:invertTransformX(testX)
    local ty = self.modelMatrix:invertTransformY(testY)
    return left <= tx and tx <= right and top <= ty and ty <= bottom
end

return L2DBaseModel
