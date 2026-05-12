local DeformerContext = {}
DeformerContext.__index = DeformerContext

function DeformerContext.new(deformer)
    local self = setmetatable({}, DeformerContext)
    self.partsIndex = nil
    self.outsideParam = {false}
    self.available = true
    self.deformer = deformer
    self.totalScale = 1.0
    self.interpolatedOpacity = 1.0
    self.totalOpacity = 1.0
    return self
end

function DeformerContext:isAvailable()
    return self.available and not self.outsideParam[1]
end

function DeformerContext:setAvailable(value)
    self.available = value
end

function DeformerContext:getDeformer()
    return self.deformer
end

function DeformerContext:setPartsIndex(aH)
    self.partsIndex = aH
end

function DeformerContext:getPartsIndex()
    return self.partsIndex
end

function DeformerContext:isOutsideParam()
    return self.outsideParam[1]
end

function DeformerContext:setOutsideParam(value)
    self.outsideParam[1] = value
end

function DeformerContext:getTotalScale()
    return self.totalScale
end

function DeformerContext:setTotalScale_notForClient(aH)
    self.totalScale = aH
end

function DeformerContext:getInterpolatedOpacity()
    return self.interpolatedOpacity
end

function DeformerContext:setInterpolatedOpacity(value)
    self.interpolatedOpacity = value
end

function DeformerContext:getTotalOpacity()
    return self.totalOpacity
end

function DeformerContext:setTotalOpacity(aH)
    self.totalOpacity = aH
end

return DeformerContext
