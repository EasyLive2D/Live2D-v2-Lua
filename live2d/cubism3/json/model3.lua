-- Model3 JSON parser for Cubism 3
-- Ported from Mocari src/json/model3.rs

local json = require("live2d.dkjson")

local model3 = {}

local SUPPORTED_VERSION = 3

local function parse_expressions(expressions)
    local parsed = {}
    for i, expression in ipairs(expressions or {}) do
        parsed[i] = {
            name = expression.Name or expression.name,
            file = expression.File or expression.file,
        }
    end
    return parsed
end

function model3.parse(source)
    local ok, raw = pcall(json.decode, source)
    if not ok then
        return nil, "Invalid model3.json: " .. tostring(raw)
    end

    if raw.Version ~= SUPPORTED_VERSION then
        return nil, "Unsupported model3.json version: " .. tostring(raw.Version)
    end

    local fr = raw.FileReferences
    if not fr then
        return nil, "Missing FileReferences in model3.json"
    end

    return {
        version = raw.Version,
        file_references = {
            moc = fr.Moc,
            textures = fr.Textures or {},
            physics = fr.Physics,
            pose = fr.Pose,
            display_info = fr.DisplayInfo,
            motions = fr.Motions or {},
            expressions = parse_expressions(fr.Expressions),
        },
        groups = raw.Groups or {},
        hit_areas = raw.HitAreas or {},
    }
end

return model3
