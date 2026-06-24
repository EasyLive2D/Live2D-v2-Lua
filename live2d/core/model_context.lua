local def = require("live2d.core.def")
local IDrawData = require("live2d.core.draw.idraw_data")
local ClippingManagerOpenGL = require("live2d.core.graphics.clipping_manager_opengl")
local Id = require("live2d.core.id.id")
local Int16Array = require("live2d.core.type.array").Int16Array
local Float32Array = require("live2d.core.type.array").Float32Array

local ModelContext = {}
ModelContext.__index = ModelContext

ModelContext.NOT_USED_ORDER = -1
ModelContext.NO_NEXT = -1
ModelContext.DEFAULT_PARAM_UPDATE_FLAG = false
ModelContext.PARAM_UPDATED = true
ModelContext.PARAM_FLOAT_MIN = -1000000
ModelContext.PARAM_FLOAT_MAX = 1000000
ModelContext.DEFAULT_ARRAY_LENGTH = 0

function ModelContext.new(model)
    local self = setmetatable({}, ModelContext)
    self.needSetup = true
    self.initVersion = -1
    self.nextParamPos = 0
    self.paramIdList = {}
    self.paramValues = Float32Array(ModelContext.DEFAULT_ARRAY_LENGTH)
    self.lastParamValues = Float32Array(ModelContext.DEFAULT_ARRAY_LENGTH)
    self.paramMinValues = Float32Array(ModelContext.DEFAULT_ARRAY_LENGTH)
    self.paramMaxValues = Float32Array(ModelContext.DEFAULT_ARRAY_LENGTH)
    self.savedParamValues = Float32Array(ModelContext.DEFAULT_ARRAY_LENGTH)
    self.updatedParamFlags = {}
    for i = 1, ModelContext.DEFAULT_ARRAY_LENGTH do
        self.updatedParamFlags[i] = ModelContext.DEFAULT_PARAM_UPDATE_FLAG
    end
    self.deformerList = {}
    self.drawDataList = {}
    self.tmpDrawDataList = nil
    self.partsDataList = {}
    self.deformerContextList = {}
    self.drawContextList = {}
    self.partsContextList = {}
    self.orderList_firstDrawIndex = nil
    self.orderList_lastDrawIndex = nil
    self.nextList_drawIndex = nil
    self.tmpPivotTableIndices = Int16Array(def.PIVOT_TABLE_SIZE)
    self.tempTArray = Float32Array(def.MAX_INTERPOLATION)
    self.model = model
    self.clipManager = nil
    self.dpGL = nil
    return self
end

function ModelContext:getDrawDataIndex(drawDataId)
    for i = #self.drawDataList, 1, -1 do
        local drawData = self.drawDataList[i]
        if drawData ~= nil and tostring(drawData:getId()) == tostring(drawDataId) then
            return i - 1
        end
    end
    return -1
end

function ModelContext:getDrawData(idOrIndex)
    if type(idOrIndex) == "table" and idOrIndex.Id_eq then
        if self.tmpDrawDataList == nil then
            self.tmpDrawDataList = {}
            local count = #self.drawDataList
            for i = 1, count do
                local dd = self.drawDataList[i]
                local dd_id = dd:getId()
                if dd_id ~= nil then
                    self.tmpDrawDataList[dd_id] = dd
                end
            end
        end
        return self.tmpDrawDataList[idOrIndex]
    else
        if idOrIndex < #self.drawDataList then
            return self.drawDataList[idOrIndex + 1]
        else
            return nil
        end
    end
end

function ModelContext:release()
    self.deformerList = {}
    self.drawDataList = {}
    self.partsDataList = {}
    if self.tmpDrawDataList ~= nil then
        self.tmpDrawDataList = {}
    end
    self.deformerContextList = {}
    self.drawContextList = {}
    self.partsContextList = {}
end

function ModelContext:init()
    self.initVersion = self.initVersion + 1
    if #self.partsDataList > 0 then
        self:release()
    end

    local modelImpl = self.model:getModelImpl()
    local parts_data_list = modelImpl:getPartsDataList()
    local partsCount = #parts_data_list
    local deformerList = {}
    local deformerContextList = {}

    for partIndex = 1, partsCount do
        local partData = parts_data_list[partIndex]
        self.partsDataList[#self.partsDataList + 1] = partData
        self.partsContextList[#self.partsContextList + 1] = partData:init()
        local base_data_list = partData:getDeformer()
        local deformerCount = #base_data_list

        for i = 1, deformerCount do
            deformerList[#deformerList + 1] = base_data_list[i]
        end

        for i = 1, deformerCount do
            local deformerContext = base_data_list[i]:init(self)
            deformerContext:setPartsIndex(partIndex - 1)
            deformerContextList[#deformerContextList + 1] = deformerContext
        end

        local drawDataList = partData:getDrawData()
        local drawDataCount = #drawDataList
        for i = 1, drawDataCount do
            local drawData = drawDataList[i]
            local drawContext = drawData:init(self)
            drawContext.partsIndex = partIndex - 1
            self.drawDataList[#self.drawDataList + 1] = drawData
            self.drawContextList[#self.drawContextList + 1] = drawContext
        end
    end

    local totalDeformerCount = #deformerList
    local baseTargetId = Id.DST_BASE_ID()
    while true do
        local foundNew = false
        for partIndex = 1, totalDeformerCount do
            local deformer = deformerList[partIndex]
            if deformer ~= nil then
                local targetId = deformer:getTargetId()
                if targetId == nil or targetId == baseTargetId or self:getDeformerIndex(targetId) >= 0 then
                    self.deformerList[#self.deformerList + 1] = deformer
                    self.deformerContextList[#self.deformerContextList + 1] = deformerContextList[partIndex]
                    deformerList[partIndex] = nil
                    foundNew = true
                end
            end
        end
        if not foundNew then break end
    end

    local paramDefSet = modelImpl:getParamDefSet()
    if paramDefSet ~= nil then
        local paramDefList = paramDefSet:getParamDefFloatList()
        if paramDefList ~= nil then
            local paramCount = #paramDefList
            for partIndex = 1, paramCount do
                local paramDef = paramDefList[partIndex]
                if paramDef ~= nil then
                    self:extendAndAddParam(paramDef:getParamID(), paramDef:getDefaultValue(), paramDef:getMinValue(), paramDef:getMaxValue())
                end
            end
        end
    end

    self.clipManager = ClippingManagerOpenGL.new(self.dpGL)
    self.clipManager:init(self, self.drawDataList, self.drawContextList)
    self.needSetup = true
end

function ModelContext:update()
    local paramCount = #self.paramValues
    for i = 1, paramCount do
        if self.paramValues[i] ~= self.lastParamValues[i] then
            self.updatedParamFlags[i] = ModelContext.PARAM_UPDATED
            self.lastParamValues[i] = self.paramValues[i]
        end
    end

    local result = false
    local deformerCount = #self.deformerList
    local drawDataCount = #self.drawDataList
    local minDrawOrder = IDrawData.getTotalMinOrder()
    local maxDrawOrder = IDrawData.getTotalMaxOrder()
    local orderRange = maxDrawOrder - minDrawOrder + 1

    if self.orderList_firstDrawIndex == nil or #self.orderList_firstDrawIndex < orderRange then
        self.orderList_firstDrawIndex = Int16Array(orderRange)
        self.orderList_lastDrawIndex = Int16Array(orderRange)
    end

    for i = 1, orderRange do
        self.orderList_firstDrawIndex[i] = ModelContext.NOT_USED_ORDER
        self.orderList_lastDrawIndex[i] = ModelContext.NOT_USED_ORDER
    end

    if self.nextList_drawIndex == nil or #self.nextList_drawIndex < drawDataCount then
        self.nextList_drawIndex = Int16Array(drawDataCount)
    end

    for i = 1, drawDataCount do
        self.nextList_drawIndex[i] = ModelContext.NO_NEXT
    end

    for i = 1, deformerCount do
        local deformer = self.deformerList[i]
        local deformerCtx = self.deformerContextList[i]
        deformer:setupInterpolate(self, deformerCtx)
        deformer:setupTransform(self, deformerCtx)
    end

    for i = 1, drawDataCount do
        local drawData = self.drawDataList[i]
        local drawCtx = self.drawContextList[i]
        drawData:setupInterpolate(self, drawCtx)
        if drawCtx:isParamOutside() then
            -- continue
        else
            drawData:setupTransform(self, drawCtx)
            local orderSlot = math.floor(IDrawData.getDrawOrder(drawCtx) - minDrawOrder + 1)
            local lastDrawIdx = self.orderList_lastDrawIndex[orderSlot]
            if lastDrawIdx == ModelContext.NOT_USED_ORDER then
                self.orderList_firstDrawIndex[orderSlot] = i - 1
            else
                self.nextList_drawIndex[lastDrawIdx + 1] = i - 1
            end
            self.orderList_lastDrawIndex[orderSlot] = i - 1
        end
    end

    for i = #self.updatedParamFlags, 1, -1 do
        self.updatedParamFlags[i] = ModelContext.DEFAULT_PARAM_UPDATE_FLAG
    end

    self.needSetup = false
    return result
end

function ModelContext:preDraw(drawParam)
    drawParam:setupDraw()
    if self.clipManager ~= nil then
        self.clipManager:setupClip(self, drawParam)
    end
end

function ModelContext:draw(drawParam)
    if self.orderList_firstDrawIndex == nil then
        print("call Ri_.update() before Ri_.draw()")
        return
    end

    local orderCount = #self.orderList_firstDrawIndex
    drawParam:setupDraw()

    for orderIndex = 1, orderCount do
        local drawIndex = self.orderList_firstDrawIndex[orderIndex]
        if drawIndex ~= ModelContext.NOT_USED_ORDER then
            while true do
                local drawData = self.drawDataList[drawIndex + 1]
                local drawCtx = self.drawContextList[drawIndex + 1]
                if drawCtx:isAvailable() then
                    local partIdx = drawCtx.partsIndex
                    local partsCtx = self.partsContextList[partIdx + 1]
                    drawCtx.partsOpacity = partsCtx:getPartsOpacity()
                    drawData:draw(drawParam, self, drawCtx)
                end
                local nextDrawIdx = self.nextList_drawIndex[drawIndex + 1]
                if nextDrawIdx <= drawIndex or nextDrawIdx == ModelContext.NO_NEXT then
                    break
                end
                drawIndex = nextDrawIdx
            end
        end
    end
end

function ModelContext:getParamIndex(paramId)
    for i = 1, #self.paramIdList do
        if self.paramIdList[i] == paramId then
            return i - 1
        end
    end
    return self:extendAndAddParam(paramId, 0, ModelContext.PARAM_FLOAT_MIN, ModelContext.PARAM_FLOAT_MAX)
end

function ModelContext:getDeformerIndex(deformerId)
    for i = #self.deformerList, 1, -1 do
        if self.deformerList[i] ~= nil and self.deformerList[i]:getId() == deformerId then
            return i - 1
        end
    end
    return -1
end

function ModelContext:extendAndAddParam(param_id, default_val, max_val, min_val)
    self.paramIdList[#self.paramIdList + 1] = param_id
    self.paramValues[#self.paramValues + 1] = default_val
    self.lastParamValues[#self.lastParamValues + 1] = default_val
    self.paramMinValues[#self.paramMinValues + 1] = max_val
    self.paramMaxValues[#self.paramMaxValues + 1] = min_val
    self.updatedParamFlags[#self.updatedParamFlags + 1] = ModelContext.DEFAULT_PARAM_UPDATE_FLAG
    local paramPosition = self.nextParamPos
    self.nextParamPos = self.nextParamPos + 1
    return paramPosition
end

function ModelContext:setParamFloat(paramIndex, value)
    if value < self.paramMinValues[paramIndex + 1] then
        value = self.paramMinValues[paramIndex + 1]
    end
    if value > self.paramMaxValues[paramIndex + 1] then
        value = self.paramMaxValues[paramIndex + 1]
    end
    self.paramValues[paramIndex + 1] = value
end

function ModelContext:loadParam()
    for idx = 1, #self.savedParamValues do
        self.paramValues[idx] = self.savedParamValues[idx]
    end
end

function ModelContext:saveParam()
    local size = #self.savedParamValues
    for idx = 1, #self.paramValues do
        if idx > size then
            self.savedParamValues[#self.savedParamValues + 1] = self.paramValues[idx]
        else
            self.savedParamValues[idx] = self.paramValues[idx]
        end
    end
end

function ModelContext:getInitVersion()
    return self.initVersion
end

function ModelContext:requireSetup()
    return self.needSetup
end

function ModelContext:isParamUpdated(index)
    return self.updatedParamFlags[index + 1] == ModelContext.PARAM_UPDATED
end

function ModelContext:getTempPivotTableIndices()
    return self.tmpPivotTableIndices
end

function ModelContext:getTempT()
    return self.tempTArray
end

function ModelContext:getDeformer(deformerIndex)
    return self.deformerList[deformerIndex + 1]
end

function ModelContext:getParamFloat(paramIndex)
    return self.paramValues[paramIndex + 1]
end

function ModelContext:getParamMax(paramIndex)
    return self.paramMaxValues[paramIndex + 1]
end

function ModelContext:getParamMin(paramIndex)
    return self.paramMinValues[paramIndex + 1]
end

function ModelContext:setPartsOpacity(partIndex, opacity)
    local partsCtx = self.partsContextList[partIndex + 1]
    partsCtx:setPartsOpacity(opacity)
end

function ModelContext:getPartsOpacity(partIndex)
    local partsCtx = self.partsContextList[partIndex + 1]
    return partsCtx:getPartsOpacity()
end

function ModelContext:getPartsDataIndex(partId)
    for i = #self.partsDataList, 1, -1 do
        if self.partsDataList[i] ~= nil and self.partsDataList[i]:getId() == partId then
            return i - 1
        end
    end
    return -1
end

function ModelContext:getDeformerContext(deformerIndex)
    return self.deformerContextList[deformerIndex + 1]
end

function ModelContext:getDrawContext(drawIndex)
    return self.drawContextList[drawIndex + 1]
end

function ModelContext:getPartsContext(partIndex)
    return self.partsContextList[partIndex + 1]
end

function ModelContext:setDrawParam(drawParam)
    self.dpGL = drawParam
end

return ModelContext
