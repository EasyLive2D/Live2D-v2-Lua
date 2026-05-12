local L2DTargetPoint = require("live2d.framework.motion.l2d_target_point")
local L2DEyeBlink = require("live2d.framework.motion.l2d_eye_blink")
local L2DBaseModel = require("live2d.framework.model.l2d_base_model")
local L2DExpressionMotion = require("live2d.framework.motion.l2d_expression_motion")
local UtSystem = require("live2d.core.util.ut_system")
local MatrixManager = require("live2d.matrix_manager")
local ModelSettingJson = require("live2d.model_setting_json")
local Parameter = require("live2d.params").Parameter

local MotionPriority = require("live2d.lapp_define").MotionPriority

local LAppModel = setmetatable({}, { __index = L2DBaseModel })
LAppModel.__index = LAppModel

function LAppModel.new()
    local self = setmetatable(L2DBaseModel.new(), LAppModel)
    self.modelHomeDir = ""
    self.modelSetting = nil
    self.matrixManager = MatrixManager.new()
    self.dragMgr = L2DTargetPoint.new()
    self.dragMgr:setPoint(0.0, 0.0)
    self.autoBreath = true
    self.autoBlink = true
    self.finishCallback = nil
    self._clearFlag = false
    return self
end

function LAppModel:getPathDir(path)
    return path:match("^(.*[/\\])") or ""
end

function LAppModel:LoadModelJson(modelSettingPath)
    self:setUpdating(true)
    self:setInitialized(false)
    self.modelHomeDir = self:getPathDir(modelSettingPath)
    self.modelSetting = ModelSettingJson.new()
    self.modelSetting:loadModelSetting(modelSettingPath)

    local path = self.modelHomeDir .. self.modelSetting:getModelFile()
    self:loadModelData(path)

    for i = 0, self.modelSetting:getTextureNum() - 1 do
        local tex_paths = self.modelHomeDir .. self.modelSetting:getTextureFile(i)
        self:loadTexture(i, tex_paths)
    end

    if self.deferExpressions then
        self.expressions = {}
    elseif self.modelSetting:getExpressionNum() > 0 then
        self.expressions = {}
        for j = 0, self.modelSetting:getExpressionNum() - 1 do
            local exp_name = self.modelSetting:getExpressionName(j)
            local exp_file_path = self.modelHomeDir .. self.modelSetting:getExpressionFile(j)
            self:loadExpression(exp_name, exp_file_path)
        end
    else
        self.expressionManager = nil
        self.expressions = {}
    end

    if self.eyeBlink == nil then
        self.eyeBlink = L2DEyeBlink.new()
    end

    if self.modelSetting:getPhysicsFile() ~= nil then
        self:loadPhysics(self.modelHomeDir .. self.modelSetting:getPhysicsFile())
    else
        self.physics = nil
    end

    if self.modelSetting:getPoseFile() ~= nil then
        local pose = self:loadPose(self.modelHomeDir .. self.modelSetting:getPoseFile())
        pose:updateParam(self.live2DModel)
    end

    local layout = self.modelSetting:getLayout()
    if layout ~= nil then
        if layout["width"] ~= nil then self.modelMatrix:setWidth(layout["width"]) end
        if layout["height"] ~= nil then self.modelMatrix:setHeight(layout["height"]) end
        if layout["x"] ~= nil then self.modelMatrix:setX(layout["x"]) end
        if layout["y"] ~= nil then self.modelMatrix:setY(layout["y"]) end
        if layout["center_x"] ~= nil then self.modelMatrix:centerX(layout["center_x"]) end
        if layout["center_y"] ~= nil then self.modelMatrix:centerY(layout["center_y"]) end
        if layout["top"] ~= nil then self.modelMatrix:top(layout["top"]) end
        if layout["bottom"] ~= nil then self.modelMatrix:bottom(layout["bottom"]) end
        if layout["left"] ~= nil then self.modelMatrix:left(layout["left"]) end
        if layout["right"] ~= nil then self.modelMatrix:right(layout["right"]) end
    end

    for j = 0, self.modelSetting:getInitParamNum() - 1 do
        self.live2DModel:setParamFloat(self.modelSetting:getInitParamID(j), self.modelSetting:getInitParamValue(j))
    end

    for j = 0, self.modelSetting:getInitPartsVisibleNum() - 1 do
        self.live2DModel:setPartsOpacity(self.modelSetting:getInitPartsVisibleID(j), self.modelSetting:getInitPartsVisibleValue(j))
    end

    self.live2DModel:saveParam()
    self.mainMotionManager:stopAllMotions()
    self:setUpdating(false)
    self:setInitialized(true)
end

function LAppModel:Resize(ww, wh)
    self.matrixManager:onResize(ww, wh)
    self.live2DModel:resize(ww, wh)
end

function LAppModel:Drag(x, y)
    local scx, scy = self.matrixManager:screenToScene(x, y)
    self.dragMgr:setPoint(scx, scy)
end

function LAppModel:IsMotionFinished()
    return self.mainMotionManager:isFinished()
end

function LAppModel:SetOffset(dx, dy)
    self.matrixManager:setOffset(dx, dy)
end

function LAppModel:SetScale(scale)
    self.matrixManager:setScale(scale)
end

function LAppModel:SetParameterValue(paramId, value, weight)
    weight = weight or 1.0
    self.live2DModel:setParamFloat(paramId, value, weight)
end

function LAppModel:AddParameterValue(paramId, value, weight)
    weight = weight or 1.0
    self.live2DModel:addToParamFloat(paramId, value, weight)
end

function LAppModel:SetAutoBreathEnable(enable)
    self.autoBreath = enable
end

function LAppModel:SetAutoBlinkEnable(enable)
    self.autoBlink = enable
end

function LAppModel:GetParameterCount()
    return #self.live2DModel:getModelContext().paramIdList
end

function LAppModel:GetParameter(index)
    local p = Parameter.new()
    p.value = self.live2DModel:getParamFloat(index)
    p.max = self.live2DModel:getModelContext():getParamMax(index)
    p.min = self.live2DModel:getModelContext():getParamMin(index)
    local inner_params = self.live2DModel:getModelImpl().paramDefSet:getParamDefFloatList()
    local is_inner = index < #inner_params
    p.type = is_inner and Parameter.TYPE_INNER or Parameter.TYPE_OUTER
    p.default = is_inner and inner_params[index + 1]:getDefaultValue() or 0
    p.id = self.live2DModel:getModelContext().paramIdList[index + 1]
    return p
end

function LAppModel:GetPartCount()
    return #self.live2DModel:getModelImpl():getPartsDataList()
end

function LAppModel:GetPartId(index)
    return self.live2DModel:getModelContext():getPartsContext(index).partsData.id.id
end

function LAppModel:GetPartIds()
    local ids = {}
    local ctx = self.live2DModel:getModelContext()
    for i = 1, #ctx.partsDataList do
        ids[#ids + 1] = tostring(ctx.partsDataList[i].id)
    end
    return ids
end

function LAppModel:SetPartOpacity(index, opacity)
    self.live2DModel:setPartsOpacity(index, opacity)
end

function LAppModel:Update()
    self.dragMgr:update()
    self:setDrag(self.dragMgr:getX(), self.dragMgr:getY())

    local time_m_sec = UtSystem.getUserTimeMSec() - self.startTimeMSec
    local time_sec = time_m_sec / 1000.0
    local t = time_sec * 2 * math.pi

    if self.mainMotionManager:isFinished() and self.finishCallback then
        self.finishCallback()
        self.finishCallback = nil
    end

    local updated = false
    if self._clearFlag then
        self.mainMotionManager:stopAllMotions()
        if self.pose then
            self.pose:initParam(self.live2DModel)
        end
        self._clearFlag = false
    else
        self.live2DModel:loadParam()
        updated = self.mainMotionManager:updateParam(self.live2DModel)
    end
    self.live2DModel:saveParam()

    if not updated then
        if self.autoBlink and self.eyeBlink ~= nil then
            self.eyeBlink:updateParam(self.live2DModel)
        end
    end

    if self.expressionManager ~= nil and self.expressions ~= nil and not self.expressionManager:isFinished() then
        self.expressionManager:updateParam(self.live2DModel)
    end

    self.live2DModel:addToParamFloat("PARAM_ANGLE_X", self.dragX * 30, 1)
    self.live2DModel:addToParamFloat("PARAM_ANGLE_Y", self.dragY * 30, 1)
    self.live2DModel:addToParamFloat("PARAM_ANGLE_Z", (self.dragX * self.dragY) * -30, 1)
    self.live2DModel:addToParamFloat("PARAM_BODY_ANGLE_X", self.dragX * 10, 1)
    self.live2DModel:addToParamFloat("PARAM_EYE_BALL_X", self.dragX, 1)
    self.live2DModel:addToParamFloat("PARAM_EYE_BALL_Y", self.dragY, 1)

    if self.autoBreath then
        self.live2DModel:addToParamFloat("PARAM_ANGLE_X", 15 * math.sin(t / 6.5345), 0.5)
        self.live2DModel:addToParamFloat("PARAM_ANGLE_Y", 8 * math.sin(t / 3.5345), 0.5)
        self.live2DModel:addToParamFloat("PARAM_ANGLE_Z", 10 * math.sin(t / 5.5345), 0.5)
        self.live2DModel:addToParamFloat("PARAM_BODY_ANGLE_X", 4 * math.sin(t / 15.5345), 0.5)
        self.live2DModel:setParamFloat("PARAM_BREATH", 0.5 + 0.5 * math.sin(t / 3.2345), 1)
    end

    if self.physics ~= nil then
        self.physics:updateParam(self.live2DModel)
    end

    if self.pose ~= nil then
        self.pose:updateParam(self.live2DModel)
    end
end

function LAppModel:Draw()
    self.live2DModel:update()
    local model_matrix = self.modelMatrix
    local tmp_matrix = self.matrixManager:getMvp(model_matrix)
    self.live2DModel:setMatrix(tmp_matrix)
    self.live2DModel:draw()
end

function LAppModel:HitTest(hitAreaName, testX, testY)
    local size = self.modelSetting:getHitAreaNum()
    for i = 0, size - 1 do
        local area_id = self.modelSetting:getHitAreaName(i)
        local draw_id = self.modelSetting:getHitAreaID(i)
        if self:hitTestSimple(draw_id, testX, testY) then
            return area_id
        end
    end
    return nil
end

function LAppModel:ClearMotions()
    self._clearFlag = true
end

function LAppModel:ResetExpression()
    self.expressionManager:stopAllMotions()
end

function LAppModel:SetExpression(name)
    if self.expressions[name] == nil then
        for j = 0, self.modelSetting:getExpressionNum() - 1 do
            if self.modelSetting:getExpressionName(j) == name then
                self:loadExpression(name, self.modelHomeDir .. self.modelSetting:getExpressionFile(j))
                break
            end
        end
    end
    local motion = self.expressions[name]
    if motion == nil then return end
    self.expressionManager:startMotion(motion, false)
end

function LAppModel:StartRandomMotion(name, priority, onStartMotionHandler, onFinishMotionHandler)
    priority = priority or MotionPriority.IDLE
    if name == nil then
        local names = self.modelSetting:getMotionNames()
        if names ~= nil and #names > 0 then
            name = names[math.random(#names)]
        else
            name = "idle"
        end
    end
    local count = self.modelSetting:getMotionNum(name)
    local no = math.random(count - 1)
    self:StartMotion(name, no, priority, onStartMotionHandler, onFinishMotionHandler)
end

function LAppModel:StartMotion(name, no, priority, onStartMotionHandler, onFinishMotionHandler)
    local motion_name = self.modelSetting:getMotionFile(name, no)
    if motion_name == nil or motion_name == "" then
        if onStartMotionHandler then onStartMotionHandler(name, no) end
        if onFinishMotionHandler then onFinishMotionHandler() end
        return
    end
    if priority == MotionPriority.FORCE then
        self.mainMotionManager:setReservePriority(priority)
    elseif not self.mainMotionManager:reserveMotion(priority) then
        return
    end

    local mtn
    if self.motions[name] == nil then
        mtn = self:loadMotion(nil, self.modelHomeDir .. motion_name)
    else
        mtn = self.motions[name]
    end

    self.finishCallback = onFinishMotionHandler
    if onStartMotionHandler then onStartMotionHandler(name, no) end
    self:_setFadeInFadeOut(name, no, priority, mtn)
end

function LAppModel:HitPart(src_x, src_y, topOnly)
    topOnly = topOnly or false
    src_x, src_y = self.matrixManager:screenToScene(src_x, src_y)
    local mx, my = self.matrixManager:invertTransform(src_x, src_y)
    local mctx = self.live2DModel:getModelContext()
    local draw_orders = mctx.nextList_drawIndex
    if not draw_orders then return {} end

    local hit_part_ids = {}
    for i = #draw_orders, 1, -1 do
        local idx = draw_orders[i]
        if idx ~= -1 then
            local ddcxt = mctx:getDrawContext(idx)
            local pctx = mctx:getPartsContext(ddcxt.partsIndex)
            local parent_part = pctx.partsData
            if not parent_part.visible or pctx.partsOpacity < 0.1 then
                -- skip
            else
                local part_id = tostring(parent_part.id)
                local already_hit = false
                for _, v in ipairs(hit_part_ids) do
                    if v == part_id then already_hit = true; break end
                end
                if not already_hit then
                    local dd = ddcxt.drawData
                    local vertices = ddcxt:getTransformedPoints()
                    local indices = dd.indexArray
                    local size = #indices
                    for ii = 1, size, 3 do
                        local p1_idx = indices[ii] * 2
                        local p2_idx = indices[ii + 1] * 2
                        local p3_idx = indices[ii + 2] * 2
                        if LAppModel._isInTriangle(mx, my,
                            vertices[p1_idx + 1], vertices[p1_idx + 2],
                            vertices[p2_idx + 1], vertices[p2_idx + 2],
                            vertices[p3_idx + 1], vertices[p3_idx + 2]) then
                            hit_part_ids[#hit_part_ids + 1] = part_id
                            if topOnly then return hit_part_ids end
                            break
                        end
                    end
                end
            end
        end
    end
    return hit_part_ids
end

function LAppModel._isInTriangle(x, y, x0, y0, x1, y1, x2, y2)
    if x < math.min(x0, x1, x2) then return false end
    if x > math.max(x0, x1, x2) then return false end
    if y < math.min(y0, y1, y2) then return false end
    if y > math.max(y0, y1, y2) then return false end
    local d_x = x - x2
    local d_y = y - y2
    local d_x21 = x2 - x1
    local d_y12 = y1 - y2
    local D = d_y12 * (x0 - x2) + d_x21 * (y0 - y2)
    local s = d_y12 * d_x + d_x21 * d_y
    local t = (y2 - y0) * d_x + (x0 - x2) * d_y
    if D < 0 then
        return s <= 0 and t <= 0 and s + t >= D
    end
    return s >= 0 and t >= 0 and s + t <= D
end

function LAppModel:_preloadMotionGroup(name)
    for i = 0, self.modelSetting:getMotionNum(name) - 1 do
        local file = self.modelSetting:getMotionFile(name, i)
        local motion = self:loadMotion(file, self.modelHomeDir .. file)
        motion:setFadeIn(self.modelSetting:getMotionFadeIn(name, i))
        motion:setFadeOut(self.modelSetting:getMotionFadeOut(name, i))
    end
end

function LAppModel:_setFadeInFadeOut(name, no, priority, motion)
    motion:setFadeIn(self.modelSetting:getMotionFadeIn(name, no))
    motion:setFadeOut(self.modelSetting:getMotionFadeOut(name, no))
    self.mainMotionManager:startMotionPrio(motion, priority)
end

return LAppModel
