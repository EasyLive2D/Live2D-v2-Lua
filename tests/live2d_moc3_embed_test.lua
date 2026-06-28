-- live2d_moc3_embed_test.lua - embedding API for Cubism 3 models
package.path = package.path .. ";./?.lua;./?/init.lua"

local embed = require("live2d_moc3_embed")

local base = "resources/Hiyori/"
local rana_base = "resources/Rana/"

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
check("module exports runtime class", type(embed.ModelRuntime) == "table")
check("module exports motion player class", type(embed.MotionPlayer) == "table")

local renderer = embed.new()
check("new returns renderer", renderer ~= nil)
check("renderer exports load_model", type(renderer.load_model) == "function")
check("renderer exports update", type(renderer.update) == "function")
check("renderer exports get_meshes", type(renderer.get_meshes) == "function")
check("renderer exports set_parameter", type(renderer.set_parameter) == "function")
check("renderer exports start_motion", type(renderer.start_motion) == "function")
check("renderer exports set_expression", type(renderer.set_expression) == "function")

renderer:set_resource_stream(base .. "Hiyori.model3.json", read_file(base .. "Hiyori.model3.json"))
renderer:set_resource_stream(base .. "Hiyori.moc3", read_file(base .. "Hiyori.moc3"))
renderer:set_resource_stream(base .. "Hiyori.pose3.json", read_file(base .. "Hiyori.pose3.json"))
renderer:set_resource_stream(base .. "motions/Hiyori_m01.motion3.json", read_file(base .. "motions/Hiyori_m01.motion3.json"))

local loaded, err = renderer:load_model(base .. "Hiyori.model3.json")
check("loads model from streams", loaded == renderer, err)
check("runtime created", renderer:get_runtime() ~= nil)
check("model data available", renderer:get_model_data() ~= nil)
check("mesh count", renderer:get_meshes() and #renderer:get_meshes() == 134)

local default_value = renderer:get_parameter("ParamAngleX")
check("get parameter by id", default_value ~= nil)
check("set parameter by id", renderer:set_parameter("ParamAngleX", 30) == renderer)
check("parameter value changed", renderer:get_parameter("ParamAngleX") == 30)
check("set parameter by index", renderer:set_parameter_by_index(0, -30) == renderer)
check("get parameter by index", renderer:get_parameter_by_index(0) == -30)
check("reset parameters", renderer:reset_parameters():get_parameter_by_index(0) == default_value)
check("set part opacity by id", renderer:set_part_opacity("PartArmA", 0.5) == renderer)
check("reset part opacities", renderer:reset_part_opacities() == renderer)

check("start motion from model group", renderer:start_motion("Idle", 0) == renderer)
check("update with motion", renderer:update(0.1) == renderer)
check("clear motions", renderer:clear_motions() == renderer)

local textures = renderer:get_textures()
check("texture references", textures and #textures == 2)

local rana = embed.new({
    resource_streams = {
        [rana_base .. "adv_live2d_rana_003_live_01.model3.json"] = read_file(rana_base .. "adv_live2d_rana_003_live_01.model3.json"),
        [rana_base .. "adv_live2d_rana_003_live_01.moc3"] = read_file(rana_base .. "adv_live2d_rana_003_live_01.moc3"),
        [rana_base .. "expressions/exp_smile01.exp3.json"] = read_file(rana_base .. "expressions/exp_smile01.exp3.json"),
    },
})
rana:load_model(rana_base .. "adv_live2d_rana_003_live_01.model3.json")
local smile_default = rana:get_parameter("Paramsmile01")
local brow_default = rana:get_parameter("ParamBrowLY")
rana:set_expression("exp_smile01")
rana:update(1.0)
local smile_applied = rana:get_parameter("Paramsmile01")
local brow_applied = rana:get_parameter("ParamBrowLY")
rana:update(1.0)
check("Rana expression changes parameter", smile_default ~= nil and smile_applied > smile_default)
check("Rana expression does not accumulate", brow_default ~= nil and brow_applied > brow_default and rana:get_parameter("ParamBrowLY") == brow_applied)

local singleton = embed.load_model(base .. "Hiyori.model3.json", {
    resource_streams = {
        [base .. "Hiyori.model3.json"] = read_file(base .. "Hiyori.model3.json"),
        [base .. "Hiyori.moc3"] = read_file(base .. "Hiyori.moc3"),
        [base .. "Hiyori.pose3.json"] = read_file(base .. "Hiyori.pose3.json"),
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
