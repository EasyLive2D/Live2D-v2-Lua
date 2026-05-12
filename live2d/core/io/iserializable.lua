local ISerializable = {}
ISerializable.__index = ISerializable

function ISerializable.new()
    local self = setmetatable({}, ISerializable)
    return self
end

function ISerializable:read(br)
    error("abstract method: read() not implemented")
end

return ISerializable
