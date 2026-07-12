-- cubism3_physics_test.lua - Physics3 parsing and runtime regressions
package.path = package.path .. ";./?.lua;./?/init.lua"

local physics3 = require("live2d.cubism3.json.physics3")
local embed = require("live2d_moc3_embed")

local passed = 0
local total = 0

local function check(name, ok, msg)
    total = total + 1
    if ok then
        passed = passed + 1
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name .. ": " .. (msg or "unknown"))
    end
end

local function close(actual, expected)
    return actual ~= nil and math.abs(actual - expected) < 0.0001
end

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*all")
    file:close()
    return data
end

print("\n-- Physics3 JSON --")
local hiyori_data = assert(physics3.parse(read_file("resources/Hiyori/Hiyori.physics3.json")))
local rana_data = assert(physics3.parse(
    read_file("resources/Rana/adv_live2d_rana_003_live_01.physics3.json")
))
check("physics3 parses Hiyori settings and metadata", hiyori_data.version == 3
    and #hiyori_data.settings == 11
    and hiyori_data.meta.total_input_count == 34
    and hiyori_data.meta.total_output_count == 35
    and hiyori_data.meta.vertex_count == 58)
check("physics3 preserves missing FPS as variable-step", close(hiyori_data.fps, 0))
check("physics3 parses Rana fixed FPS", #rana_data.settings == 31 and close(rana_data.fps, 60))
local invalid_data, invalid_err = physics3.parse('{"Version": 2}')
check("physics3 rejects unsupported versions", invalid_data == nil
    and type(invalid_err) == "string" and invalid_err:match("Unsupported"))

print("\n-- Physics Runtime --")
local renderer = embed.new()
renderer:load_model("resources/Hiyori/Hiyori.model3.json")
local physics = renderer:get_physics()
check("embed loads model physics reference", physics ~= nil and #physics.settings == 11)
local before = renderer:get_parameter("ParamHairFront")
renderer:set_parameter("ParamAngleX", 30)
renderer:update(1 / 60)
renderer:update(1 / 60)
local after = renderer:get_parameter("ParamHairFront")
check("physics changes output parameter after pendulum step", before ~= nil and after ~= nil
    and math.abs(after - before) > 0.1)
check("physics only scans parameters used as inputs", #physics.input_slots > 0
    and #physics.input_slots < #renderer:get_runtime().parameter_values)

-- Static parameter indices and ranges must stay off the per-frame hot path.
-- Wrapping the public accessors catches regressions that rescan the complete
-- model or resolve each Physics3 input/output for every substep.
local runtime = renderer:get_runtime()
local indexed_reads, minimum_reads, maximum_reads = 0, 0, 0
local parameter_value_by_index = runtime.parameter_value_by_index
local parameter_minimum_by_index = runtime.parameter_minimum_by_index
local parameter_maximum_by_index = runtime.parameter_maximum_by_index
runtime.parameter_value_by_index = function(self, index)
    indexed_reads = indexed_reads + 1
    return parameter_value_by_index(self, index)
end
runtime.parameter_minimum_by_index = function(self, index)
    minimum_reads = minimum_reads + 1
    return parameter_minimum_by_index(self, index)
end
runtime.parameter_maximum_by_index = function(self, index)
    maximum_reads = maximum_reads + 1
    return parameter_maximum_by_index(self, index)
end
physics:evaluate(runtime, 1 / 60)
check("physics caches parameter metadata across frames",
    indexed_reads == 0 and minimum_reads == 0 and maximum_reads == 0)
physics:reset()
check("physics reset clears elapsed simulation time", close(physics.remaining_time, 0))
local large_delta_ok = pcall(function() physics:evaluate(runtime, 6.0) end)
check("physics ignores oversized elapsed intervals safely", large_delta_ok and close(physics.remaining_time, 0))

print(string.format("\n=== Results: %d/%d passed ===", passed, total))
if passed == total then
    print("ALL TESTS PASSED!")
    os.exit(0)
else
    print("SOME TESTS FAILED!")
    os.exit(1)
end
