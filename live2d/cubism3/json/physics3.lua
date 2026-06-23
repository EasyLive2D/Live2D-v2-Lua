-- Physics3 JSON parser for Cubism 3
-- Ported from Mocari src/json/physics3.rs

local json = require("live2d.dkjson")

local physics3 = {}

local SUPPORTED_VERSION = 3

function physics3.parse(source)
    local ok, raw = pcall(json.decode, source)
    if not ok then
        return nil, "Invalid physics3.json: " .. tostring(raw)
    end

    if raw.Version ~= SUPPORTED_VERSION then
        return nil, "Unsupported physics3.json version: " .. tostring(raw.Version)
    end

    return {
        version = raw.Version,
        meta = raw.Meta or {},
        settings = raw.PhysicsSettings or {},
    }
end

return physics3
