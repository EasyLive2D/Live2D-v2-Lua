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
    for aH = #self.drawDataList, 1, -1 do
        local drawData = self.drawDataList[aH]
        if drawData ~= nil and tostring(drawData:getId()) == tostring(drawDataId) then
            return aH - 1
        end
    end
    return -1
end

function ModelContext:getDrawData(aH)
    if type(aH) == "table" and aH.Id_eq then
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
        return self.tmpDrawDataList[aH]
    else
        if aH < #self.drawDataList then
            return self.drawDataList[aH + 1]
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

    local aO = self.model:getModelImpl()
    local parts_data_list = aO:getPartsDataList()
    local aS = #parts_data_list
    local aH = {}
    local a3 = {}

    for aV = 1, aS do
        local a4 = parts_data_list[aV]
        self.partsDataList[#self.partsDataList + 1] = a4
        self.partsContextList[#self.partsContextList + 1] = a4:init()
        local base_data_list = a4:getDeformer()
        local aR = #base_data_list

        for aU = 1, aR do
            aH[#aH + 1] = base_data_list[aU]
        end

        for aU = 1, aR do
            local aM = base_data_list[aU]:init(self)
            aM:setPartsIndex(aV - 1)
            a3[#a3 + 1] = aM
        end

        local a1 = a4:getDrawData()
        local aP = #a1
        for aU = 1, aP do
            local aZ = a1[aU]
            local a0 = aZ:init(self)
            a0.partsIndex = aV - 1
            self.drawDataList[#self.drawDataList + 1] = aZ
            self.drawContextList[#self.drawContextList + 1] = a0
        end
    end

    local aY = #aH
    local aN = Id.DST_BASE_ID()
    while true do
        local aX = false
        for aV = 1, aY do
            local aL = aH[aV]
            if aL ~= nil then
                local a2 = aL:getTargetId()
                if a2 == nil or a2 == aN or self:getDeformerIndex(a2) >= 0 then
                    self.deformerList[#self.deformerList + 1] = aL
                    self.deformerContextList[#self.deformerContextList + 1] = a3[aV]
                    aH[aV] = nil
                    aX = true
                end
            end
        end
        if not aX then break end
    end

    local aI = aO:getParamDefSet()
    if aI ~= nil then
        local aJ = aI:getParamDefFloatList()
        if aJ ~= nil then
            local aW = #aJ
            for aV = 1, aW do
                local aQ = aJ[aV]
                if aQ ~= nil then
                    self:extendAndAddParam(aQ:getParamID(), aQ:getDefaultValue(), aQ:getMinValue(), aQ:getMaxValue())
                end
            end
        end
    end

    self.clipManager = ClippingManagerOpenGL.new(self.dpGL)
    self.clipManager:init(self, self.drawDataList, self.drawContextList)
    self.needSetup = true
end

function ModelContext:update()
    local aK = #self.paramValues
    for i = 1, aK do
        if self.paramValues[i] ~= self.lastParamValues[i] then
            self.updatedParamFlags[i] = ModelContext.PARAM_UPDATED
            self.lastParamValues[i] = self.paramValues[i]
        end
    end

    local aX = false
    local aQ = #self.deformerList
    local aN = #self.drawDataList
    local aS = IDrawData.getTotalMinOrder()
    local aZ = IDrawData.getTotalMaxOrder()
    local aU = aZ - aS + 1

    if self.orderList_firstDrawIndex == nil or #self.orderList_firstDrawIndex < aU then
        self.orderList_firstDrawIndex = Int16Array(aU)
        self.orderList_lastDrawIndex = Int16Array(aU)
    end

    for i = 1, aU do
        self.orderList_firstDrawIndex[i] = ModelContext.NOT_USED_ORDER
        self.orderList_lastDrawIndex[i] = ModelContext.NOT_USED_ORDER
    end

    if self.nextList_drawIndex == nil or #self.nextList_drawIndex < aN then
        self.nextList_drawIndex = Int16Array(aN)
    end

    for i = 1, aN do
        self.nextList_drawIndex[i] = ModelContext.NO_NEXT
    end

    for aV = 1, aQ do
        local aJ = self.deformerList[aV]
        local aH = self.deformerContextList[aV]
        aJ:setupInterpolate(self, aH)
        aJ:setupTransform(self, aH)
    end

    for aO = 1, aN do
        local aM = self.drawDataList[aO]
        local aI = self.drawContextList[aO]
        aM:setupInterpolate(self, aI)
        if aI:isParamOutside() then
            -- continue
        else
            aM:setupTransform(self, aI)
            local aT = math.floor(IDrawData.getDrawOrder(aI) - aS + 1)
            local aP = self.orderList_lastDrawIndex[aT]
            if aP == ModelContext.NOT_USED_ORDER then
                self.orderList_firstDrawIndex[aT] = aO - 1
            else
                self.nextList_drawIndex[aP + 1] = aO - 1
            end
            self.orderList_lastDrawIndex[aT] = aO - 1
        end
    end

    for i = #self.updatedParamFlags, 1, -1 do
        self.updatedParamFlags[i] = ModelContext.DEFAULT_PARAM_UPDATE_FLAG
    end

    self.needSetup = false
    return aX
end

function ModelContext:preDraw(aH)
    aH:setupDraw()
    if self.clipManager ~= nil then
        self.clipManager:setupClip(self, aH)
    end
end

function ModelContext:draw(aM)
    if self.orderList_firstDrawIndex == nil then
        print("call Ri_.update() before Ri_.draw()")
        return
    end

    local aP = #self.orderList_firstDrawIndex
    aM:setupDraw()

    for aK = 1, aP do
        local aN = self.orderList_firstDrawIndex[aK]
        if aN ~= ModelContext.NOT_USED_ORDER then
            while true do
                local aH = self.drawDataList[aN + 1]
                local aI = self.drawContextList[aN + 1]
                if aI:isAvailable() then
                    local aJ = aI.partsIndex
                    local aL = self.partsContextList[aJ + 1]
                    aI.partsOpacity = aL:getPartsOpacity()
                    aH:draw(aM, self, aI)
                end
                local aO = self.nextList_drawIndex[aN + 1]
                if aO <= aN or aO == ModelContext.NO_NEXT then
                    break
                end
                aN = aO
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

function ModelContext:getDeformerIndex(aH)
    for aI = #self.deformerList, 1, -1 do
        if self.deformerList[aI] ~= nil and self.deformerList[aI]:getId() == aH then
            return aI - 1
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
    local ret = self.nextParamPos
    self.nextParamPos = self.nextParamPos + 1
    return ret
end

function ModelContext:setDeformer(aI, aH)
    self.deformerList[aI + 1] = aH
end

function ModelContext:setParamFloat(aH, aI)
    if aI < self.paramMinValues[aH + 1] then
        aI = self.paramMinValues[aH + 1]
    end
    if aI > self.paramMaxValues[aH + 1] then
        aI = self.paramMaxValues[aH + 1]
    end
    self.paramValues[aH + 1] = aI
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

function ModelContext:getDeformer(aH)
    return self.deformerList[aH + 1]
end

function ModelContext:getParamFloat(aH)
    return self.paramValues[aH + 1]
end

function ModelContext:getParamMax(aH)
    return self.paramMaxValues[aH + 1]
end

function ModelContext:getParamMin(aH)
    return self.paramMinValues[aH + 1]
end

function ModelContext:setPartsOpacity(aJ, aH)
    local aI = self.partsContextList[aJ + 1]
    aI:setPartsOpacity(aH)
end

function ModelContext:getPartsOpacity(aI)
    local aH = self.partsContextList[aI + 1]
    return aH:getPartsOpacity()
end

function ModelContext:getPartsDataIndex(aI)
    for aH = #self.partsDataList, 1, -1 do
        if self.partsDataList[aH] ~= nil and self.partsDataList[aH]:getId() == aI then
            return aH - 1
        end
    end
    return -1
end

function ModelContext:getDeformerContext(aH)
    return self.deformerContextList[aH + 1]
end

function ModelContext:getDrawContext(aH)
    return self.drawContextList[aH + 1]
end

function ModelContext:getPartsContext(aH)
    return self.partsContextList[aH + 1]
end

function ModelContext:setPartMultiplyColor(aH, r, g, b, a)
    local aI = self.partsContextList[aH + 1]
    aI.multiplyColor[1] = r
    aI.multiplyColor[2] = g
    aI.multiplyColor[3] = b
    aI.multiplyColor[4] = a
end

function ModelContext:getPartMultiplyColor(aH)
    return self.partsContextList[aH + 1].multiplyColor
end

function ModelContext:setPartScreenColor(aH, r, g, b, a)
    local aI = self.partsContextList[aH + 1]
    aI.screenColor[1] = r
    aI.screenColor[2] = g
    aI.screenColor[3] = b
    aI.screenColor[4] = a
end

function ModelContext:getPartScreenColor(aH)
    return self.partsContextList[aH + 1].screenColor
end

function ModelContext:setDrawParam(aH)
    self.dpGL = aH
end

function ModelContext:getDrawParam()
    return self.dpGL
end

return ModelContext
