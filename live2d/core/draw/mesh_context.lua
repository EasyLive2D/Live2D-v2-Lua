local IDrawContext = require("live2d.core.draw.idraw_context")
local IDrawData = require("live2d.core.draw.idraw_data")

local MeshContext = setmetatable({}, { __index = IDrawContext })
MeshContext.__index = MeshContext

function MeshContext.new(dd)
    local self = setmetatable(IDrawContext.new(dd), MeshContext)
    self.tmpDeformerIndex = IDrawData.DEFORMER_INDEX_NOT_INIT
    self.interpolatedPoints = nil
    self.transformedPoints = nil
    return self
end

function MeshContext:getTransformedPoints()
    if self.transformedPoints ~= nil then
        return self.transformedPoints
    end
    return self.interpolatedPoints
end

return MeshContext
