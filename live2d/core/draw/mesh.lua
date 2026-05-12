local IDrawData = require("live2d.core.draw.idraw_data")
local MeshContext = require("live2d.core.draw.mesh_context")
local def = require("live2d.core.def")
local Live2D = require("live2d.core.live2d")
local Float32Array = require("live2d.core.type.array").Float32Array
local Int16Array = require("live2d.core.type.array").Int16Array
local UtInterpolate = require("live2d.core.util.ut_interpolate")

local Mesh = setmetatable({}, { __index = IDrawData })
Mesh.__index = Mesh

Mesh.INSTANCE_COUNT = 0
Mesh.MASK_COLOR_COMPOSITION = 30
Mesh.COLOR_COMPOSITION_NORMAL = 0
Mesh.COLOR_COMPOSITION_SCREEN = 1
Mesh.COLOR_COMPOSITION_MULTIPLY = 2
Mesh.paramOutside = {false}

function Mesh.new()
    local self = setmetatable(IDrawData.new(), Mesh)
    self.textureNo = -1
    self.pointCount = 0
    self.polygonCount = 0
    self.optionFlag = nil
    self.indexArray = nil
    self.pivotPoints = nil
    self.uvs = nil
    self.colorCompositionType = Mesh.COLOR_COMPOSITION_NORMAL
    self.culling = true
    self.instanceNo = Mesh.INSTANCE_COUNT
    Mesh.INSTANCE_COUNT = Mesh.INSTANCE_COUNT + 1
    return self
end

function Mesh:setTextureNo(aH)
    self.textureNo = aH
end

function Mesh:getTextureNo()
    return self.textureNo
end

function Mesh:getUvs()
    return self.uvs
end

function Mesh:getOptionFlag()
    return self.optionFlag
end

function Mesh:getNumPoints()
    return self.pointCount
end

function Mesh:getType()
    return IDrawData.TYPE_MESH
end

function Mesh:read(br)
    IDrawData.read(self, br)
    self.textureNo = br:readInt32()
    self.pointCount = br:readInt32()
    self.polygonCount = br:readInt32()
    local obj = br:readObject()
    self.indexArray = Int16Array(self.polygonCount * 3)
    for aJ = self.polygonCount * 3, 1, -1 do
        self.indexArray[aJ] = obj[aJ]
    end

    self.pivotPoints = br:readObject()
    self.uvs = br:readObject()
    if br:getFormatVersion() >= def.LIVE2D_FORMAT_VERSION_V2_8_TEX_OPTION then
        self.optionFlag = br:readInt32()
        if self.optionFlag ~= 0 then
            if bit.band(self.optionFlag, 1) ~= 0 then
                br:readInt32()
                error("not handled")
            end
            if bit.band(self.optionFlag, Mesh.MASK_COLOR_COMPOSITION) ~= 0 then
                self.colorCompositionType = bit.rshift(bit.band(self.optionFlag, Mesh.MASK_COLOR_COMPOSITION), 1)
            else
                self.colorCompositionType = Mesh.COLOR_COMPOSITION_NORMAL
            end
            if bit.band(self.optionFlag, 32) ~= 0 then
                self.culling = false
            end
        end
    else
        self.optionFlag = 0
    end
end

function Mesh:init(aL)
    local ctx = MeshContext.new(self)
    local aI = self.pointCount * def.VERTEX_STEP
    local aH = self:needTransform()
    if ctx.interpolatedPoints ~= nil then
        ctx.interpolatedPoints = nil
    end
    ctx.interpolatedPoints = Float32Array(aI)
    if ctx.transformedPoints ~= nil then
        ctx.transformedPoints = nil
    end
    ctx.transformedPoints = nil
    if aH then
        ctx.transformedPoints = Float32Array(aI)
    end
    local aM = def.VERTEX_TYPE

    if aM == def.VERTEX_TYPE_OFFSET0_STEP2 then
        if def.REVERSE_TEXTURE_T then
            for aJ = self.pointCount, 1, -1 do
                local aO = (aJ - 1) * 2
                self.uvs[aO + 2] = 1 - self.uvs[aO + 2]
            end
        end
    elseif aM == def.VERTEX_TYPE_OFFSET2_STEP5 then
        for aJ = self.pointCount, 1, -1 do
            local aO = (aJ - 1) * 2
            local aK = (aJ - 1) * def.VERTEX_STEP
            local aQ = self.uvs[aO + 1]
            local aP = self.uvs[aO + 2]
            ctx.interpolatedPoints[aK + 1] = aQ
            ctx.interpolatedPoints[aK + 2] = aP
            ctx.interpolatedPoints[aK + 5] = 0
            if aH then
                ctx.transformedPoints[aK + 1] = aQ
                ctx.transformedPoints[aK + 2] = aP
                ctx.transformedPoints[aK + 5] = 0
            end
        end
    end

    return ctx
end

function Mesh:setupInterpolate(aJ, aH)
    local aK = aH
    if self ~= aK:getDrawData() then
        print("### assert!! ###")
    end
    if not self.pivotMgr:checkParamUpdated(aJ) then
        return
    end
    IDrawData.setupInterpolate(self, aJ, aK)
    if aK.paramOutside[1] then
        return
    end
    local aI = Mesh.paramOutside
    aI[1] = false
    UtInterpolate.interpolatePoints(aJ, self.pivotMgr, aI, self.pointCount, self.pivotPoints, aK.interpolatedPoints,
                                     def.VERTEX_OFFSET, def.VERTEX_STEP)
end

function Mesh:setupTransform(mc, dc)
    if self ~= dc:getDrawData() then
        error("context not match")
    end
    local aL = false
    if dc.paramOutside[1] then
        aL = true
    end
    if not aL then
        IDrawData.setupTransform(self, mc)
        if self:needTransform() then
            local target_id = self:getTargetId()
            if dc.tmpDeformerIndex == IDrawData.DEFORMER_INDEX_NOT_INIT then
                dc.tmpDeformerIndex = mc:getDeformerIndex(target_id)
            end
            if dc.tmpDeformerIndex < 0 then
                print("deformer not found: " .. tostring(target_id))
            else
                local d = mc:getDeformer(dc.tmpDeformerIndex)
                local dctx = mc:getDeformerContext(dc.tmpDeformerIndex)
                if d ~= nil and not dctx:isOutsideParam() then
                    d:transformPoints(mc, dctx, dc.interpolatedPoints, dc.transformedPoints, self.pointCount,
                                      def.VERTEX_OFFSET, def.VERTEX_STEP)
                    dc.available = true
                else
                    dc.available = false
                end
                dc.baseOpacity = dctx:getTotalOpacity()
            end
        end
    end
end

function Mesh:draw(dp, mctx, dctx)
    if self ~= dctx:getDrawData() then
        error("context not match")
    end
    if dctx.paramOutside[1] then
        return
    end
    local texNr = self.textureNo
    if texNr < 0 then
        texNr = 1
    end
    local opacity = IDrawData.getOpacity(dctx) * dctx.partsOpacity * dctx.baseOpacity
    local vertices
    if dctx.transformedPoints ~= nil then
        vertices = dctx.transformedPoints
    else
        vertices = dctx.interpolatedPoints
    end
    dp:setClipBufPre_clipContextForDraw(dctx.clipBufPre_clipContext)
    dp:setCulling(self.culling)
    local pctx = mctx:getPartsContext(dctx.partsIndex)
    dp:drawTexture(texNr, pctx.screenColor, self.indexArray, vertices, self.uvs, opacity, self.colorCompositionType,
                   pctx.multiplyColor)
end

function Mesh:getIndexArray()
    return self.indexArray
end

return Mesh
