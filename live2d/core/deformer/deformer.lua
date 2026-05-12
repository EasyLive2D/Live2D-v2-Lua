local ISerializable = require("live2d.core.io.iserializable")
local def = require("live2d.core.def")
local Id = require("live2d.core.id.id")
local UtInterpolate = require("live2d.core.util.ut_interpolate")

local Deformer = setmetatable({}, { __index = ISerializable })
Deformer.__index = Deformer

Deformer.DEFORMER_INDEX_NOT_INIT = -2
Deformer.TYPE_ROTATION = 1
Deformer.TYPE_WARP = 2

function Deformer.new()
    local self = setmetatable(ISerializable.new(), Deformer)
    self.id = nil
    self.targetId = nil
    self.dirty = true
    self.pivotOpacities = nil
    return self
end

function Deformer:read(br)
    self.id = br:readObject()
    self.targetId = br:readObject()
end

function Deformer:readOpacity(br)
    if br:getFormatVersion() >= def.LIVE2D_FORMAT_VERSION_V2_10_SDK2 then
        self.pivotOpacities = br:readFloat32Array()
    end
end

function Deformer:init(mc)
    error("abstract method: init() not implemented")
end

function Deformer:setupInterpolate(modelContext, deformerContext)
    error("abstract method: setupInterpolate() not implemented")
end

function Deformer:interpolateOpacity(mdc, pivotMgr, bctx, ret)
    if self.pivotOpacities == nil then
        bctx:setInterpolatedOpacity(1)
    else
        bctx:setInterpolatedOpacity(UtInterpolate.interpolateFloat(mdc, pivotMgr, ret, self.pivotOpacities))
    end
end

function Deformer:setupTransform(mc, dc)
    -- no-op: abstract
end

function Deformer:transformPoints(mc, dc, srcPoints, dstPoints, numPoint, ptOffset, ptStep)
    error("abstract method: transformPoints() not implemented")
end

function Deformer:getType()
    error("abstract method: getType() not implemented")
end

function Deformer:setTargetId(aH)
    self.targetId = aH
end

function Deformer:setId(aH)
    self.id = aH
end

function Deformer:getTargetId()
    return self.targetId
end

function Deformer:getId()
    return self.id
end

function Deformer:needTransform()
    return self.targetId ~= nil and self.targetId ~= Id.DST_BASE_ID()
end

return Deformer
