local Deformer = require("live2d.core.deformer.deformer")
local DeformerContext = require("live2d.core.deformer.deformer_context")

local RotationContext = setmetatable({}, { __index = DeformerContext })
RotationContext.__index = RotationContext

function RotationContext.new(dfm)
    local self = setmetatable(DeformerContext.new(dfm), RotationContext)
    self.tmpDeformerIndex = Deformer.DEFORMER_INDEX_NOT_INIT
    self.interpolatedAffine = nil
    self.transformedAffine = nil
    return self
end

return RotationContext
