local array = {}

function array.Float32Array(size)
    if type(size) ~= "number" then
        error("invalid param")
    end
    local array = {}
    for i = 1, size do
        array[i] = 0.0
    end
    return array
end

function array.Float64Array(size)
    return array.Float32Array(size)
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
    local array = {}
    for i = 1, size do
        array[i] = 0
    end
    return array
end

return array
