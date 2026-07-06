-- cubism3_runtime_features_test.lua - regressions for Cubism3 runtime/parser APIs
package.path = package.path .. ";./?.lua;./?/init.lua"

local moc3 = require("live2d.cubism3.moc3")
local model3 = require("live2d.cubism3.json.model3")
local pose3 = require("live2d.cubism3.json.pose3")
local ModelRuntime = require("live2d.cubism3.runtime")
local Vector2 = require("live2d.cubism3.core.math").Vector2
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

local function color_close(actual, expected)
    if type(actual) ~= "table" then return false end
    for i = 1, 3 do
        if not close(actual[i], expected[i]) then return false end
    end
    return true
end

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*all")
    file:close()
    return data
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

local function load_hiyori_runtime()
    local base = "resources/Hiyori/"
    local model_data = assert(model3.parse(read_file(base .. "Hiyori.model3.json")))
    local pose_data = assert(pose3.parse(read_file(base .. "Hiyori.pose3.json")))
    local moc_bytes = read_file(base .. "Hiyori.moc3")
    local canvas = assert(moc3.canvas.parse(moc_bytes))
    local art_meshes = assert(moc3.art_meshes.parse(moc_bytes))
    local keyforms = assert(moc3.keyforms.parse(moc_bytes))
    local deformers = assert(moc3.deformers.parse(moc_bytes))
    local bindings = assert(moc3.keyform_bindings.parse(moc_bytes))
    local ids = assert(moc3.ids.parse(moc_bytes))
    local offscreen = assert(moc3.offscreen.parse(moc_bytes))
    local glues = assert(moc3.glues.parse(moc_bytes))
    local parts = assert(moc3.parts.parse(moc_bytes))
    local draw_order_groups = assert(moc3.draw_order_groups.parse(moc_bytes))
    return assert(ModelRuntime.new(
        model_data, canvas, art_meshes, keyforms, deformers, bindings,
        ids, offscreen, glues, parts, draw_order_groups, pose_data
    ))
end

local function load_sakiko_runtime()
    local base = "resources/Sakiko/"
    local model_data = assert(model3.parse(read_file(base .. "adv_live2d_sakiko_010_live_01.model3.json")))
    local moc_bytes = read_file(base .. model_data.file_references.moc)
    local canvas = assert(moc3.canvas.parse(moc_bytes))
    local art_meshes = assert(moc3.art_meshes.parse(moc_bytes))
    local keyforms = assert(moc3.keyforms.parse(moc_bytes))
    local deformers = assert(moc3.deformers.parse(moc_bytes))
    local bindings = assert(moc3.keyform_bindings.parse(moc_bytes))
    local ids = assert(moc3.ids.parse(moc_bytes))
    local offscreen = assert(moc3.offscreen.parse(moc_bytes))
    local glues = assert(moc3.glues.parse(moc_bytes))
    local parts = assert(moc3.parts.parse(moc_bytes))
    local draw_order_groups = assert(moc3.draw_order_groups.parse(moc_bytes))
    return assert(ModelRuntime.new(
        model_data, canvas, art_meshes, keyforms, deformers, bindings,
        ids, offscreen, glues, parts, draw_order_groups, nil
    ))
end

local function max_drawable_opacity_for_part(runtime, part_id)
    local part_index = runtime:part_index_of(part_id)
    if part_index == nil then return nil end
    local max_opacity = nil
    for mesh_index, mesh in ipairs(runtime.meshes) do
        if runtime.offscreen.drawable_parent_part_indices[mesh_index] == part_index then
            local opacity = mesh.opacity or 0
            if max_opacity == nil or opacity > max_opacity then
                max_opacity = opacity
            end
        end
    end
    return max_opacity
end

print("\n-- Model3 Expressions --")
local rana_model = assert(model3.parse(read_file("resources/Rana/adv_live2d_rana_003_live_01.model3.json")))
local expressions = rana_model.file_references.expressions
check("model3 parses expression references", expressions ~= nil and #expressions == 19)
check("model3 expression name/file", expressions ~= nil
    and expressions[1].Name == "exp_smile04"
    and expressions[1].File == "expressions/exp_smile04.exp3.json")

print("\n-- Expression3 JSON --")
local ok_expression3, expression3 = pcall(require, "live2d.cubism3.json.expression3")
check("expression3 module exists", ok_expression3, expression3)
local expression
if ok_expression3 then
    expression = assert(expression3.parse([[{
        "Type": "Live2D Expression",
        "Parameters": [
            { "Id": "ParamAngleX", "Value": 10.0, "Blend": 1 },
            { "Id": "ParamBodyAngleX", "Value": 0.5, "Blend": "Multiply" },
            { "Id": "ParamAngleY", "Value": -3.0, "Blend": 3 }
        ]
    }]]))
    check("expression3 parses kind", expression.kind == "Live2D Expression")
    check("expression3 resolves default fade in", close(expression3.resolved_fade_in_time(expression), 1.0))
    check("expression3 resolves default fade out", close(expression3.resolved_fade_out_time(expression), 1.0))
    check("expression3 maps numeric add blend", expression.parameters[1].blend == "Add")
    check("expression3 maps string multiply blend", expression.parameters[2].blend == "Multiply")
    check("expression3 maps numeric overwrite blend", expression.parameters[3].blend == "Overwrite")
else
    check("expression3 parses kind", false, "module missing")
    check("expression3 resolves default fade in", false, "module missing")
    check("expression3 resolves default fade out", false, "module missing")
    check("expression3 maps numeric add blend", false, "module missing")
    check("expression3 maps string multiply blend", false, "module missing")
    check("expression3 maps numeric overwrite blend", false, "module missing")
end

print("\n-- Runtime Parameter API --")
local runtime = load_hiyori_runtime()
local angle_index = runtime:parameter_index_of("ParamAngleX")
local ids = type(runtime.parameter_ids) == "function" and runtime:parameter_ids() or nil
check("runtime exposes parameter ids", ids ~= nil and #ids == 70)
local info = type(runtime.parameter_info_by_index) == "function" and runtime:parameter_info_by_index(angle_index) or nil
check("parameter info exposes range/default/value", info ~= nil
    and info.id == "ParamAngleX"
    and info.minimum < info.maximum
    and info.minimum <= info.default
    and info.default <= info.maximum
    and close(info.value, info.default))
local set_normalized = type(runtime.set_parameter_normalized_by_index) == "function"
    and runtime:set_parameter_normalized_by_index(angle_index, 0.75)
local normalized = type(runtime.parameter_normalized_value_by_index) == "function"
    and runtime:parameter_normalized_value_by_index(angle_index) or nil
check("set parameter normalized maps unit range", set_normalized == true and close(normalized, 0.75))
local maximum = info and info.maximum or nil
local override_ok = type(runtime.set_parameter_override_normalized_by_index) == "function"
    and runtime:set_parameter_override_normalized_by_index(angle_index, 1.0)
if type(runtime.reset_parameters) == "function" then runtime:reset_parameters() end
if type(runtime.apply_parameter_overrides) == "function" then runtime:apply_parameter_overrides() end
check("parameter overrides apply after reset", override_ok == true
    and close(runtime:parameter_value_by_index(angle_index), maximum))
local clear_ok = type(runtime.clear_parameter_override_by_index) == "function"
    and runtime:clear_parameter_override_by_index(angle_index)
if type(runtime.reset_parameters) == "function" then runtime:reset_parameters() end
if type(runtime.apply_parameter_overrides) == "function" then runtime:apply_parameter_overrides() end
check("parameter overrides clear", clear_ok == true
    and info ~= nil
    and close(runtime:parameter_value_by_index(angle_index), info.default))

print("\n-- Part Opacity --")
local sakiko_model_path = "resources/Sakiko/adv_live2d_sakiko_010_live_01.model3.json"
if file_exists(sakiko_model_path) then
    local sakiko_runtime = load_sakiko_runtime()
    check("sakiko static hidden shoe part remains drawable", close(max_drawable_opacity_for_part(sakiko_runtime, "Part72"), 1.0))
    check("sakiko right upper arm part remains drawable", close(max_drawable_opacity_for_part(sakiko_runtime, "Part191"), 1.0))
else
    print("[SKIP] Sakiko resource not found")
end

print("\n-- Expression Runtime --")
local ok_expression_runtime, expression_runtime = pcall(require, "live2d.cubism3.expression")
check("expression runtime module exists", ok_expression_runtime, expression_runtime)
if ok_expression_runtime and ok_expression3 and expression then
    local player = expression_runtime.ExpressionPlayer.new(expression)
    local default = runtime:parameter_value_by_index(angle_index)
    player:tick(0.5)
    player:apply(runtime)
    local faded = runtime:parameter_value_by_index(angle_index)
    player:apply(runtime)
    local repeated = runtime:parameter_value_by_index(angle_index)
    check("expression player applies fade without accumulating", close(faded, default + 5.0)
        and close(repeated, default + 5.0))

    runtime:reset_parameters()
    local manager = expression_runtime.ExpressionManager.new()
    manager:play(expression)
    manager:tick(1.0)
    manager:apply(runtime)
    check("expression manager applies active expression", close(runtime:parameter_value_by_index(angle_index), default + 10.0))

    local second_expression = assert(expression3.parse([[{
        "Type": "Live2D Expression",
        "Parameters": [
            { "Id": "ParamAngleX", "Value": -4.0, "Blend": 1 }
        ]
    }]]))
    manager:play(second_expression)
    manager:tick(0.5)
    manager:apply(runtime)
    manager:tick(0.5)
    manager:apply(runtime)
    check("expression manager switches without inheriting previous expression", close(runtime:parameter_value_by_index(angle_index), default - 4.0))
else
    check("expression player applies fade without accumulating", false, "expression runtime missing")
    check("expression manager applies active expression", false, "expression runtime missing")
    check("expression manager switches without inheriting previous expression", false, "expression runtime missing")
end

print("\n-- Drawable Color Composition --")
local art_mesh_methods = {}
function art_mesh_methods:art_mesh_keyform_binding_band_index()
    return 0
end
function art_mesh_methods:art_mesh_parent_deformer_index()
    return 0
end
function art_mesh_methods:art_mesh_uvs()
    return { 0, 0, 1, 0, 0, 1 }
end
function art_mesh_methods:art_mesh_position_indices()
    return { 0, 1, 2 }
end
function art_mesh_methods:art_mesh_render_order()
    return 0
end
function art_mesh_methods:art_mesh_masks()
    return {}
end
local synthetic_art_meshes = setmetatable({
    meshes = { { texture_index = 0, drawable_flags = 0 } },
}, { __index = art_mesh_methods })
local synthetic_keyforms = {}
function synthetic_keyforms:art_mesh_keyforms()
    return {
        {
            opacity = 1.0,
            draw_order = 0,
            position_begin_index = 0,
            multiply_color = { 0.5, 0.8, 1.0 },
            screen_color = { 0.2, 0.0, 0.3 },
        },
    }
end
function synthetic_keyforms:art_mesh_keyform_positions()
    return { 0, 0, 1, 0, 0, 1 }
end
local synthetic_bindings = {
    keyform_slots = function()
        return { { local_index = 0, weight = 1.0 } }
    end,
}
local synthetic_deformers = {
    compose = function()
        return {
            {
                kind = "rotation",
                origin = Vector2.new(0, 0),
                angle_degrees = 0,
                scale = 1,
                flip_x = false,
                flip_y = false,
                opacity_accum = 1,
                multiply_color = { 0.5, 0.25, 1.0 },
                screen_color = { 0.5, 0.1, 0.0 },
            },
        }
    end,
}
local meshes = moc3.mesh_build.build_moc3_drawable_meshes_with_parameters(
    synthetic_art_meshes,
    synthetic_keyforms,
    synthetic_deformers,
    synthetic_bindings,
    {}
)
check("drawable colors include parent deformer colors", meshes ~= nil
    and color_close(meshes[1].multiply_color, { 0.25, 0.2, 1.0 })
    and color_close(meshes[1].screen_color, { 0.6, 0.1, 0.3 }))

print("\n-- live2d_moc3_embed Integration --")
local renderer = embed.new()
renderer:load_model("resources/Rana/adv_live2d_rana_003_live_01.model3.json")
check("embed exports expression methods", type(renderer.load_expression) == "function"
    and type(renderer.set_expression) == "function"
    and type(renderer.clear_expressions) == "function")
check("embed exports parameter override methods", type(renderer.set_parameter_normalized) == "function"
    and type(renderer.set_parameter_override_normalized) == "function"
    and type(renderer.clear_parameter_overrides) == "function")
if type(renderer.load_expression) == "function" and type(renderer.set_expression) == "function" then
    local loaded_expression = renderer:load_expression("exp_smile04")
    check("embed loads expression by model3 name", loaded_expression ~= nil
        and loaded_expression.parameters ~= nil
        and loaded_expression.parameters[1].id == "ParamEyeLOpen")
    local brow_default = renderer:get_parameter("ParamBrowLY") or 0
    renderer:set_expression("exp_smile04")
    renderer:update(1.0)
    local brow_after = renderer:get_parameter("ParamBrowLY")
    renderer:update(1.0)
    local brow_repeated = renderer:get_parameter("ParamBrowLY")
    check("embed applies expression without accumulation", close(brow_after, brow_default + 0.1)
        and close(brow_repeated, brow_default + 0.1))
else
    check("embed loads expression by model3 name", false, "methods missing")
    check("embed applies expression without accumulation", false, "methods missing")
end
if type(renderer.set_parameter_override_normalized) == "function" then
    local eye_index = renderer:get_runtime():parameter_index_of("ParamEyeLOpen")
    local eye_info = renderer:get_runtime():parameter_info_by_index(eye_index)
    renderer:set_parameter_override_normalized("ParamEyeLOpen", 0.0)
    renderer:update(0.0)
    check("embed applies parameter overrides after update", close(renderer:get_parameter("ParamEyeLOpen"), eye_info.minimum))
else
    check("embed applies parameter overrides after update", false, "override method missing")
end

print(string.format("\n=== Results: %d/%d passed ===", passed, total))
if passed == total then
    print("ALL TESTS PASSED!")
    os.exit(0)
else
    print("SOME TESTS FAILED!")
    os.exit(1)
end
