local Deformer = require("live2d.core.deformer.deformer")
local DeformerContext = require("live2d.core.deformer.deformer_context")

local WarpContext = setmetatable({}, { __index = DeformerContext })
WarpContext.__index = WarpContext

function WarpContext.new(dfm)
    local self = setmetatable(DeformerContext.new(dfm), WarpContext)
    self.tmpDeformerIndex = Deformer.DEFORMER_INDEX_NOT_INIT
    self.interpolatedPoints = nil
    self.transformedPoints = nil
    return self
end

return WarpContext
