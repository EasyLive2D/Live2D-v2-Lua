local Id = {}
Id.__index = Id

local instances = {}

function Id.new(aH)
    local self = setmetatable({}, Id)
    self.id = aH
    return self
end

function Id:__tostring()
    return self.id
end

function Id:__eq(other)
    if type(other) == "table" and other.Id_eq then
        return rawequal(other, self) or other.id == self.id
    elseif type(other) == "string" then
        return other == self.id
    end
    return false
end

Id.Id_eq = true

function Id.DST_BASE_ID()
    return Id.getID("DST_BASE")
end

function Id.getID(idStr)
    if type(idStr) ~= "string" then
        error("invalid param", 2)
    end
    local obj = instances[idStr]
    if obj == nil then
        obj = Id.new(idStr)
        instances[idStr] = obj
    end
    return obj
end

function Id.releaseStored()
    instances = {}
end

return Id
