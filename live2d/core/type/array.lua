local array = {}

function array.Float32Array(size)
    if type(size) ~= "number" then
        error("invalid param")
    end
    local t = {}
    for i = 1, size do
        t[i] = 0.0
    end
    return t
end

function array.Float64Array(size)
    return array.Float32Array(size)
end

function array.Int8Array(size)
    return array.Int32Array(size)
end

function array.Int16Array(size)
    return array.Int32Array(size)
end

function array.Int32Array(size)
    if size == nil then
        return {}
    end
    if type(size) ~= "number" then
        error("invalid param")
    end
    local t = {}
    for i = 1, size do
        t[i] = 0
    end
    return t
end

function array.Array(size)
    if size == nil then
        return {}
    end
    if type(size) ~= "number" then
        error("invalid param")
    end
    local t = {}
    for i = 1, size do
        t[i] = nil
    end
    return t
end

return array
