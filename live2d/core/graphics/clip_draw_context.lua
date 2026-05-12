local ClipDrawContext = {}
ClipDrawContext.__index = ClipDrawContext

function ClipDrawContext.new(aI, aH)
    local self = setmetatable({}, ClipDrawContext)
    self.drawDataId = aI
    self.drawDataIndex = aH
    return self
end

return ClipDrawContext
