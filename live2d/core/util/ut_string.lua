local UtString = {}

function UtString.startsWith(s, offset, pat)
    local patLen = #pat
    local endPos = offset + patLen
    if endPos > #s then
        return false
    end
    for i = offset, endPos - 1 do
        if string.sub(s, i + 1, i + 1) ~= string.sub(pat, i - offset + 1, i - offset + 1) then
            return false
        end
    end
    return true
end

function UtString.createString(buf, offset, size)
    return string.sub(buf, offset + 1, offset + size)
end

function UtString.strToFloat(s, length, offset, ret)
    local result = 0
    local _n = 10
    local _p = false
    local neg = string.sub(s, offset + 1, offset + 1) == "-"
    if neg then
        offset = offset + 1
    end
    while offset < length do
        local c = string.sub(s, offset + 1, offset + 1)
        if c >= "0" and c <= "9" then
            local digit = tonumber(c)
            if _p then
                result = result + digit / _n
                _n = _n * 10
            else
                result = result * 10 + digit
            end
        elseif c == "." then
            _p = true
        else
            break
        end
        offset = offset + 1
    end
    if neg then
        result = -result
    end
    ret[1] = offset
    return result
end

return UtString
