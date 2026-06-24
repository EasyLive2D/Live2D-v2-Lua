local def = require("live2d.core.def")
local Id = require("live2d.core.id.id")
local ISerializable = require("live2d.core.io.iserializable")
local Live2D = require("live2d.core.live2d")
local UtInterpolate = require("live2d.core.util.ut_interpolate")

local IDrawData = setmetatable({}, { __index = ISerializable })
IDrawData.__index = IDrawData

IDrawData.DEFORMER_INDEX_NOT_INIT = -2
IDrawData.DEFAULT_ORDER = 500
IDrawData.TYPE_MESH = 2
IDrawData.totalMinOrder = IDrawData.DEFAULT_ORDER
IDrawData.totalMaxOrder = IDrawData.DEFAULT_ORDER

function IDrawData.new()
    local self = setmetatable(ISerializable.new(), IDrawData)
    self.clipIDList = nil
    self.clipID = nil
    self.id = nil
    self.targetId = nil
    self.pivotMgr = nil
    self.averageDrawOrder = nil
    self.pivotDrawOrders = nil
    self.pivotOpacities = nil
    return self
end

function IDrawData:read(binaryReader)
    self.id = binaryReader:readObject()
    self.targetId = binaryReader:readObject()
    self.pivotMgr = binaryReader:readObject()
    self.averageDrawOrder = binaryReader:readInt32()
    self.pivotDrawOrders = binaryReader:readInt32Array()
    self.pivotOpacities = binaryReader:readFloat32Array()
    if binaryReader:getFormatVersion() >= def.LIVE2D_FORMAT_VERSION_AVAILABLE then
        self.clipID = binaryReader:readObject()
        self.clipIDList = IDrawData.convertClipIDForV2_11(self.clipID)
    else
        self.clipIDList = nil
    end
    IDrawData.setDrawOrders(self.pivotDrawOrders)
end

function IDrawData:getClipIDList()
    return self.clipIDList
end

function IDrawData.convertClipIDForV2_11(s)
    if s == nil then
        return nil
    end
    local sid
    if type(s) == "table" and s.id then
        sid = s.id
    else
        sid = tostring(s)
    end
    if #sid == 0 then
        return nil
    end
    if not string.find(sid, ",") then
        return {sid}
    end
    local ls = {}
    for part in string.gmatch(sid, "[^,]+") do
        ls[#ls + 1] = part
    end
    return ls
end

function IDrawData:setupInterpolate(modelContext, drawContext)
    drawContext.paramOutside = {false}
    drawContext.interpolatedDrawOrder = UtInterpolate.interpolateInt(modelContext, self.pivotMgr, drawContext.paramOutside, self.pivotDrawOrders)
    if not Live2D.L2D_OUTSIDE_PARAM_AVAILABLE and drawContext.paramOutside[1] then
        return
    end
    drawContext.interpolatedOpacity = UtInterpolate.interpolateFloat(modelContext, self.pivotMgr, drawContext.paramOutside, self.pivotOpacities)
end

function IDrawData:setupTransform(mc, dc)
    -- no-op: abstract, overridden by subclasses
end

function IDrawData:getId()
    return self.id
end

function IDrawData.getOpacity(ctx)
    return ctx.interpolatedOpacity
end

function IDrawData.getDrawOrder(ctx)
    return ctx.interpolatedDrawOrder
end

function IDrawData:getTargetId()
    return self.targetId
end

function IDrawData:needTransform()
    return type(self.targetId) == "table" and self.targetId.Id_eq and self.targetId ~= Id.DST_BASE_ID()
end

function IDrawData:getType()
    error("abstract method: getType() not implemented")
end

function IDrawData.setDrawOrders(orders)
    for i = #orders, 1, -1 do
        local order = orders[i]
        if order < IDrawData.totalMinOrder then
            IDrawData.totalMinOrder = order
        elseif order > IDrawData.totalMaxOrder then
            IDrawData.totalMaxOrder = order
        end
    end
end

function IDrawData.getTotalMinOrder()
    return IDrawData.totalMinOrder
end

function IDrawData.getTotalMaxOrder()
    return IDrawData.totalMaxOrder
end

return IDrawData
