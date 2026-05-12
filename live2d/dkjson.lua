local dkjson = {}

local function skip_whitespace(s, i)
    while i <= #s do
        local c = s:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
            break
        end
        i = i + 1
    end
    return i
end

local function parse_string(s, i)
    i = i + 1
    local result = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(result), i + 1
        elseif c == '\\' then
            i = i + 1
            local c2 = s:sub(i, i)
            if c2 == 'n' then result[#result + 1] = '\n'
            elseif c2 == 't' then result[#result + 1] = '\t'
            elseif c2 == 'r' then result[#result + 1] = '\r'
            elseif c2 == '\\' then result[#result + 1] = '\\'
            elseif c2 == '"' then result[#result + 1] = '"'
            elseif c2 == '/' then result[#result + 1] = '/'
            elseif c2 == 'u' then
                local hex = s:sub(i + 1, i + 4)
                result[#result + 1] = string.char(tonumber(hex, 16))
                i = i + 4
            else
                result[#result + 1] = c2
            end
        else
            result[#result + 1] = c
        end
        i = i + 1
    end
    error("Unterminated string")
end

local function parse_number(s, i)
    local start = i
    if s:sub(i, i) == '-' then i = i + 1 end
    while i <= #s and s:sub(i, i):match('[0-9]') do i = i + 1 end
    if s:sub(i, i) == '.' then
        i = i + 1
        while i <= #s and s:sub(i, i):match('[0-9]') do i = i + 1 end
    end
    if s:sub(i, i) == 'e' or s:sub(i, i) == 'E' then
        i = i + 1
        if s:sub(i, i) == '+' or s:sub(i, i) == '-' then i = i + 1 end
        while i <= #s and s:sub(i, i):match('[0-9]') do i = i + 1 end
    end
    return tonumber(s:sub(start, i - 1)), i
end

local function parse_value(s, i)
    i = skip_whitespace(s, i)
    local c = s:sub(i, i)
    if c == '"' then
        return parse_string(s, i)
    elseif c == '{' then
        return parse_object(s, i)
    elseif c == '[' then
        return parse_array(s, i)
    elseif c == 't' then
        return true, i + 4
    elseif c == 'f' then
        return false, i + 5
    elseif c == 'n' then
        return nil, i + 4
    else
        return parse_number(s, i)
    end
end

function parse_object(s, i)
    i = i + 1
    local obj = {}
    i = skip_whitespace(s, i)
    if s:sub(i, i) == '}' then
        return obj, i + 1
    end
    while true do
        i = skip_whitespace(s, i)
        local key
        key, i = parse_string(s, i)
        i = skip_whitespace(s, i)
        if s:sub(i, i) ~= ':' then error("Expected colon") end
        i = i + 1
        local val
        val, i = parse_value(s, i)
        obj[key] = val
        i = skip_whitespace(s, i)
        local c = s:sub(i, i)
        if c == '}' then
            return obj, i + 1
        elseif c ~= ',' then
            error("Expected comma or closing bracket, got " .. c)
        end
        i = i + 1
    end
end

function parse_array(s, i)
    i = i + 1
    local arr = {}
    i = skip_whitespace(s, i)
    if s:sub(i, i) == ']' then
        return arr, i + 1
    end
    local idx = 1
    while true do
        local val
        val, i = parse_value(s, i)
        arr[idx] = val
        idx = idx + 1
        i = skip_whitespace(s, i)
        local c = s:sub(i, i)
        if c == ']' then
            return arr, i + 1
        elseif c ~= ',' then
            error("Expected comma or closing bracket")
        end
        i = i + 1
    end
end

function dkjson.decode(s)
    if s == nil or s == "" then return {} end
    local result, pos = parse_value(s, 1)
    return result
end

function dkjson.encode(t)
    error("encode not implemented")
end

return dkjson
