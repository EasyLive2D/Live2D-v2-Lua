local def = require("live2d.core.def")
local Id = require("live2d.core.id.id")
local BinaryReader = require("live2d.core.io.binary_reader")
local ModelContext = require("live2d.core.model_context")

local ALive2DModel = {}
ALive2DModel.__index = ALive2DModel

function ALive2DModel.new()
    local self = setmetatable({}, ALive2DModel)
    self.modelImpl = nil
    self.modelContext = ModelContext.new(self)
    return self
end

function ALive2DModel:setModelImpl(moc)
    self.modelImpl = moc
end

function ALive2DModel:getModelImpl()
    if self.modelImpl == nil then
        local ModelImpl = require("live2d.core.model.model_impl")
        self.modelImpl = ModelImpl.new()
        self.modelImpl:initDirect()
    end
    return self.modelImpl
end

function ALive2DModel:getCanvasWidth()
    if self.modelImpl == nil then
        return 0
    end
    return self.modelImpl:getCanvasWidth()
end

function ALive2DModel:getCanvasHeight()
    if self.modelImpl == nil then
        return 0
    end
    return self.modelImpl:getCanvasHeight()
end

function ALive2DModel:getParamFloat(x)
    if type(x) ~= "number" then
        x = self.modelContext:getParamIndex(Id.getID(x))
    end
    return self.modelContext:getParamFloat(x)
end

function ALive2DModel:setParamFloat(x, value, weight)
    weight = weight or 1
    if type(x) ~= "number" then
        x = self.modelContext:getParamIndex(Id.getID(x))
    end
    if value == nil then value = 0 end
    self.modelContext:setParamFloat(x, self.modelContext:getParamFloat(x) * (1 - weight) + value * weight)
end

function ALive2DModel:addToParamFloat(x, value, weight)
    weight = weight or 1
    if type(x) ~= "number" then
        x = self.modelContext:getParamIndex(Id.getID(x))
    end
    self.modelContext:setParamFloat(x, self.modelContext:getParamFloat(x) + value * weight)
end

function ALive2DModel:multParamFloat(x, value, weight)
    weight = weight or 1
    if type(x) ~= "number" then
        x = self.modelContext:getParamIndex(Id.getID(x))
    end
    self.modelContext:setParamFloat(x, self.modelContext:getParamFloat(x) * (1 + (value - 1) * weight))
end

function ALive2DModel:getParamIndex(idStr)
    return self.modelContext:getParamIndex(Id.getID(idStr))
end

function ALive2DModel:loadParam()
    self.modelContext:loadParam()
end

function ALive2DModel:saveParam()
    self.modelContext:saveParam()
end

function ALive2DModel:init()
    self.modelContext:init()
end

function ALive2DModel:update()
    self.modelContext:update()
end

function ALive2DModel:draw()
    error("abstract method: draw() not implemented")
end

function ALive2DModel:getModelContext()
    return self.modelContext
end

function ALive2DModel:setPartsOpacity(index, opacity)
    if type(index) ~= "number" then
        index = self.modelContext:getPartsDataIndex(Id.getID(index))
    end
    self.modelContext:setPartsOpacity(index, opacity)
end

function ALive2DModel:getPartsDataIndex(partId)
    if type(partId) == "string" then
        partId = Id.getID(partId)
    end
    return self.modelContext:getPartsDataIndex(partId)
end

function ALive2DModel:getPartsOpacity(partIndex)
    if type(partIndex) ~= "number" then
        partIndex = self.modelContext:getPartsDataIndex(Id.getID(partIndex))
    end
    if partIndex < 0 then
        return 0
    end
    return self.modelContext:getPartsOpacity(partIndex)
end

function ALive2DModel:getDrawParam()
    error("abstract method: getDrawParam() not implemented")
end

function ALive2DModel:getDrawDataIndex(drawId)
    return self.modelContext:getDrawDataIndex(Id.getID(drawId))
end

function ALive2DModel:getDrawData(drawDataIdOrIndex)
    return self.modelContext:getDrawData(drawDataIdOrIndex)
end

function ALive2DModel:getTransformedPoints(drawDataIndex)
    local drawCtx = self.modelContext:getDrawContext(drawDataIndex)
    if drawCtx.getTransformedPoints then
        return drawCtx:getTransformedPoints()
    end
    return nil
end

function ALive2DModel.loadModel_exe(model, buf)
    if type(buf) ~= "string" then
        error("param error")
    end

    local br = BinaryReader.new(buf)
    local magic1 = br:readByte()
    local magic2 = br:readByte()
    local magic3 = br:readByte()

    if magic1 == 109 and magic2 == 111 and magic3 == 99 then
        -- 'moc' magic, skip version byte
    else
        error("Invalid MOC file.")
    end

    local version = br:readByte()
    br:setFormatVersion(version)

    if version > def.LIVE2D_FORMAT_VERSION_AVAILABLE then
        error("Unsupported version " .. tostring(version))
    end

    local modelImpl = br:readObject()
    if version >= def.LIVE2D_FORMAT_VERSION_V2_8_TEX_OPTION then
        local endMarker1 = br:readUShort()
        local endMarker2 = br:readUShort()
        if endMarker1 ~= -30584 or endMarker2 ~= -30584 then
            error("Invalid load EOF")
        end
    end

    model:setModelImpl(modelImpl)
    local model_context = model:getModelContext()
    model_context:setDrawParam(model:getDrawParam())
    model_context:init()
end

return ALive2DModel
