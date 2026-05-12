local L2DExpressionParam = {}
L2DExpressionParam.__index = L2DExpressionParam

function L2DExpressionParam.new()
    local self = setmetatable({}, L2DExpressionParam)
    self.id = ""
    self.type = -1
    self.value = nil
    return self
end

return L2DExpressionParam
