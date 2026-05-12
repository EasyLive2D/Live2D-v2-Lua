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

function IDrawData:read(aH)
    self.id = aH:readObject()
    self.targetId = aH:readObject()
    self.pivotMgr = aH:readObject()
    self.averageDrawOrder = aH:readInt32()
    self.pivotDrawOrders = aH:readInt32Array()
    self.pivotOpacities = aH:readFloat32Array()
    if aH:getFormatVersion() >= def.LIVE2D_FORMAT_VERSION_AVAILABLE then
        self.clipID = aH:readObject()
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

function IDrawData:setupInterpolate(aI, aH)
    aH.paramOutside = {false}
    aH.interpolatedDrawOrder = UtInterpolate.interpolateInt(aI, self.pivotMgr, aH.paramOutside, self.pivotDrawOrders)
    if not Live2D.L2D_OUTSIDE_PARAM_AVAILABLE and aH.paramOutside[1] then
        return
    end
    aH.interpolatedOpacity = UtInterpolate.interpolateFloat(aI, self.pivotMgr, aH.paramOutside, self.pivotOpacities)
end

function IDrawData:setupTransform(mc, dc)
    -- no-op: abstract, overridden by subclasses
end

function IDrawData:getId()
    return self.id
end

function IDrawData:setId(value)
    self.id = value
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

function IDrawData:setTargetId(aH)
    self.targetId = aH
end

function IDrawData:needTransform()
    return self.targetId ~= nil and self.targetId ~= Id.DST_BASE_ID()
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
