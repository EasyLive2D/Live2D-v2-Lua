-- CDI3 JSON parser for Cubism 3
-- Ported from Mocari src/json/cdi3.rs

local json = require("live2d.dkjson")

local cdi3 = {}

local SUPPORTED_VERSION = 3

function cdi3.parse(source)
    local ok, raw = pcall(json.decode, source)
    if not ok then
        return nil, "Invalid cdi3.json: " .. tostring(raw)
    end

    if raw.Version ~= SUPPORTED_VERSION then
        return nil, "Unsupported cdi3.json version: " .. tostring(raw.Version)
    end

    return {
        version = raw.Version,
        parameters = raw.Parameters or {},
        parameter_groups = raw.ParameterGroups or {},
        parts = raw.Parts or {},
        combined_parameters = raw.CombinedParameters or {},
    }
end

return cdi3
