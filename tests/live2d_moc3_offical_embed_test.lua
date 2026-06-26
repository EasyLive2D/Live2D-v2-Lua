-- live2d_moc3_offical_embed_test.lua - embedding API for official Cubism Core models
package.path = package.path .. ";./?.lua;./?/init.lua"

local embed = require("live2d_moc3_offical_embed")

local base = "resources/Rana/"
local model_path = base .. "adv_live2d_rana_003_live_01.model3.json"

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local fileContent = file:read("*all")
    file:close()
    return fileContent
end

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

check("module exports constructor", type(embed.new) == "function")
check("module exports singleton loader", type(embed.load_model) == "function")
check("module exports Model class", type(embed.Model) == "table")
check("module exports MotionPlayer class", type(embed.MotionPlayer) == "table")

local renderer = embed.new()
check("new returns renderer", renderer ~= nil)
check("renderer exports load_model", type(renderer.load_model) == "function")
check("renderer exports update", type(renderer.update) == "function")
check("renderer exports get_drawables", type(renderer.get_drawables) == "function")
check("renderer exports set_parameter", type(renderer.set_parameter) == "function")
check("renderer exports start_motion", type(renderer.start_motion) == "function")

renderer:set_resource_stream(model_path, read_file(model_path))
renderer:set_resource_stream(base .. "adv_live2d_rana_003_live_01.moc3", read_file(base .. "adv_live2d_rana_003_live_01.moc3"))
renderer:set_resource_stream(base .. "motions/mtn_idle01_C.motion3.json", read_file(base .. "motions/mtn_idle01_C.motion3.json"))

local loaded, err = renderer:load_model(model_path)
check("loads Rana model from streams", loaded == renderer, err)
check("model created", renderer:get_model() ~= nil)
check("model data available", renderer:get_model_data() ~= nil)
check("drawable count", renderer:get_drawables() and #renderer:get_drawables() == 311)

local default_value = renderer:get_parameter("ParamAngleX")
check("get parameter by id", type(default_value) == "number")
check("set parameter by id", renderer:set_parameter("ParamAngleX", 30) == renderer)
check("parameter value changed", renderer:get_parameter("ParamAngleX") == 30)
check("set parameter by index", renderer:set_parameter_by_index(1, -30) == renderer)
check("get parameter by index", renderer:get_parameter_by_index(1) == -30)
check("reset parameters", renderer:reset_parameters():get_parameter("ParamAngleX") == default_value)
local first_part_id = renderer:get_model().part_ids[1]
check("set part opacity by id", renderer:set_part_opacity(first_part_id, 0.5) == renderer)
check("reset part opacities", renderer:reset_part_opacities() == renderer)

check("start motion from model group", renderer:start_motion("mtn_idle01_C", 0) == renderer)
check("update with motion", renderer:update(0.1) == renderer)
check("clear motions", renderer:clear_motions() == renderer)

local textures = renderer:get_textures()
check("texture references", textures and #textures == 2)

local singleton = embed.load_model(model_path, {
    resource_streams = {
        [model_path] = read_file(model_path),
        [base .. "adv_live2d_rana_003_live_01.moc3"] = read_file(base .. "adv_live2d_rana_003_live_01.moc3"),
    },
})
check("singleton load_model", singleton == embed.current())
check("dispose singleton", embed.dispose() == true)

print(string.format("\n=== Results: %d/%d passed ===", passed, total))
if passed == total then
    print("ALL TESTS PASSED!")
    os.exit(0)
else
    print("SOME TESTS FAILED!")
    os.exit(1)
end
