local TextureInfo = {}
TextureInfo.__index = TextureInfo

function TextureInfo.new()
    local self = setmetatable({}, TextureInfo)
    self.a = 1.0
    self.r = 1.0
    self.g = 1.0
    self.b = 1.0
    return self
end

return TextureInfo
