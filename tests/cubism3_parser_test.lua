-- cubism3_parser_test.lua - Verify all MOC3 binary parsing for Hiyori
package.path = package.path .. ";./?.lua;./?/init.lua"

local moc3 = require("live2d.cubism3.moc3")
local model3 = require("live2d.cubism3.json.model3")
local motion3 = require("live2d.cubism3.json.motion3")
local pose3 = require("live2d.cubism3.json.pose3")
local ModelRuntime = require("live2d.cubism3.runtime")

local base = "resources/Hiyori/"
local rana_base = "resources/Rana/"

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local fileContent = file:read("*all")
    file:close()
    return fileContent
end

local function read_text(path)
    local file = assert(io.open(path, "r"))
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

-- Test model3.json parsing
print("\n-- Model3 JSON --")
local model_json = read_text(base .. "Hiyori.model3.json")
local model_data, err = model3.parse(model_json)
check("model3.json parse", model_data ~= nil, err)
check("model3 version", model_data and model_data.version == 3)
check("model3 moc", model_data and model_data.file_references.moc == "Hiyori.moc3")
check("model3 textures", model_data and #model_data.file_references.textures == 2)
check("model3 physics", model_data and model_data.file_references.physics ~= nil)
check("model3 pose", model_data and model_data.file_references.pose ~= nil)
check("model3 groups", model_data and #model_data.groups == 2)
check("model3 motions", model_data and next(model_data.file_references.motions) ~= nil)

-- Test MOC3 parsing
print("\n-- MOC3 Binary Parsing --")
local moc_bytes = read_file(base .. "Hiyori.moc3")
print("MOC3 size: " .. #moc_bytes .. " bytes")

local hdr, err = moc3.header.parse(moc_bytes)
check("header parse", hdr ~= nil, err)
check("header version", hdr and hdr.version == moc3.header.V4_0_0)
check("header endianness", hdr and hdr.endianness == moc3.header.LITTLE)

local offs, err = moc3.offsets.parse(moc_bytes)
check("offsets parse", offs ~= nil, err)

local cnts, err = moc3.counts.parse(moc_bytes)
check("counts parse", cnts ~= nil, err)
check("counts parts", cnts and cnts.parts == 24)
check("counts parameters", cnts and cnts.parameters == 70)
check("counts art_meshes", cnts and cnts.art_meshes == 134)
check("counts warp_deformers", cnts and cnts.warp_deformers >= 0)

local ids, err = moc3.ids.parse(moc_bytes)
check("ids parse", ids ~= nil, err)
check("ids parts", ids and #ids.parts == 24)
check("ids art_meshes", ids and #ids.art_meshes == 134)
check("ids parameters", ids and #ids.parameters == 70)

local canvas, err = moc3.canvas.parse(moc_bytes)
check("canvas parse", canvas ~= nil, err)
check("canvas width", canvas and canvas.width > 0)
check("canvas height", canvas and canvas.height > 0)
check("canvas PPU", canvas and canvas.pixels_per_unit > 0)

local parts, err = moc3.parts.parse(moc_bytes)
check("parts parse", parts ~= nil, err)
check("parts count", parts and parts:part_count() == 24)

local bindings, err = moc3.keyform_bindings.parse(moc_bytes)
check("bindings parse", bindings ~= nil, err)
check("bindings param count", bindings and #bindings.parameter_default_values == 70)
check("bindings default values", bindings and #bindings.parameter_default_values > 0)

local art_meshes, err = moc3.art_meshes.parse(moc_bytes)
check("art_meshes parse", art_meshes ~= nil, err)
check("art_meshes count", art_meshes and #art_meshes.meshes == 134)
check("art_meshes uv_xys", art_meshes and #art_meshes.uv_xys > 0)

local kfs, err = moc3.keyforms.parse(moc_bytes)
check("keyforms parse", kfs ~= nil, err)
check("keyforms count", kfs and #kfs.keyforms > 0)

local defs, err = moc3.deformers.parse(moc_bytes)
check("deformers parse", defs ~= nil, err)
check("deformers kind count", defs and #defs.deformer_kinds > 0)

local offscr, err = moc3.offscreen.parse(moc_bytes)
check("offscreen parse", offscr ~= nil, err)

-- Test pose
print("\n-- Pose3 --")
local pose_json = read_text(base .. "Hiyori.pose3.json")
local pose, err = pose3.parse(pose_json)
check("pose parse", pose ~= nil, err)
check("pose groups", pose and #pose.groups > 0)

-- Test motion3 parsing
print("\n-- Motion3 --")
local motion_json = read_text(base .. "motions/Hiyori_m01.motion3.json")
local motion, err = motion3.parse(motion_json)
check("motion3 parse", motion ~= nil, err)
check("motion3 version", motion and motion.version == 3)
check("motion3 curves", motion and #motion.curves > 0)
check("motion3 sample", motion and motion.curves[1]:sample(0) ~= nil)
check(
    "negative curve fade times inherit motion fade",
    math.abs(motion3.parameter_curve_fade_weight(0.9, 1.0, 1.0, -1.0, -1.0, 1.5, 0.0, -1.0) - 0.9) < 0.0001
)

-- Cubism5 draw-order groups supersede slot 87 object order. Art meshes keep
-- identity render order until the runtime expands draw-order groups.
print("\n-- Cubism5 Draw Order Groups --")
local rana_moc_bytes = read_file(rana_base .. "adv_live2d_rana_003_live_01.moc3")
local rana_cnts, err = moc3.counts.parse(rana_moc_bytes)
check("rana counts parse", rana_cnts ~= nil, err)
check("rana has draw order groups", rana_cnts and rana_cnts.draw_order_groups == 9)
check("rana has draw order group objects", rana_cnts and rana_cnts.draw_order_group_objects == 319)

local rana_art_meshes, err = moc3.art_meshes.parse(rana_moc_bytes)
check("rana art meshes parse", rana_art_meshes ~= nil, err)
check("rana art mesh render order defaults to identity", (function()
    if not rana_art_meshes then return false end
    for i = 1, #rana_art_meshes.render_orders do
        if rana_art_meshes.render_orders[i] ~= i - 1 then
            return false, i
        end
    end
    return true
end)())

local rana_groups, err = moc3.draw_order_groups.parse(rana_moc_bytes)
check("rana draw order groups parse", rana_groups ~= nil, err)
check("rana draw order group count", rana_groups and rana_groups:group_count() == 9)
check("rana draw order group drawable count", rana_groups and rana_groups:drawable_count() == 311)
if rana_groups then
    local drawable_orders = {}
    for i = 1, rana_groups:drawable_count() do drawable_orders[i] = 0 end
    local part_orders = {}
    local part_enabled = {}
    local part_offscreens = {}
    for i = 1, rana_cnts.parts do
        part_orders[i] = 0
        part_enabled[i] = false
        part_offscreens[i] = -1
    end
    local expanded = rana_groups:render_orders(drawable_orders, part_orders, part_enabled, part_offscreens, 0)
    check("rana draw order groups expand", expanded ~= nil and #expanded == 311)
    check("rana draw order groups affect ordering", (function()
        if not expanded then return false end
        for i = 1, #expanded do
            if expanded[i] ~= i - 1 then return true end
        end
        return false
    end)())
end

-- Test ModelRuntime construction
print("\n-- ModelRuntime --")
local runtime = ModelRuntime.new(
    model_data, canvas, art_meshes, kfs, defs, bindings,
    ids, offscr, parts, pose
)
check("runtime create", runtime ~= nil)
check("runtime meshes", runtime and #runtime.meshes == 134)
check("runtime default param", runtime and runtime:parameter_value_by_index(0) ~= nil)

-- Test parameter setting
if runtime then
    runtime:set_parameter_by_index(0, 0.5)
    local updateSuccess = runtime:update_meshes()
    check("runtime update after param change", updateSuccess == true)
end

-- Test keyform slots
local slots = bindings:keyform_slots(0, 1, bindings.parameter_default_values)
check("keyform slots default", slots ~= nil and #slots > 0)

-- Test deformer composition
local composed = defs:compose(bindings, bindings.parameter_default_values)
check("deformer compose", composed ~= nil and #composed > 0)

-- Regression: nested rotation deformers must derive parent angle from the local +Y axis.
-- A reflected parent has a flipped +X axis, but its rotational direction is still read from +Y.
local test_defs = setmetatable({
    parent_deformer_indices = { -1, 0 },
    deformer_kinds = { 1, 1 },
    specific_indices = { 0, 1 },
    warp_keyform_binding_band_indices = {},
    warp_keyform_begin_indices = {},
    warp_keyform_counts = {},
    warp_vertex_counts = {},
    warp_rows = {},
    warp_cols = {},
    warp_keyform_opacities = {},
    rotation_keyform_binding_band_indices = { -1, -1 },
    rotation_keyform_begin_indices = { 0, 1 },
    rotation_keyform_counts = { 1, 1 },
    rotation_base_angles = { 0, 0 },
    warp_keyform_position_begin_indices = {},
    rotation_keyform_angles = { 0, 10 },
    rotation_keyform_origin_xs = { 0, 0 },
    rotation_keyform_origin_ys = { 0, 0 },
    rotation_keyform_scales = { 1, 1 },
    rotation_keyform_reflect_xs = { true, false },
    rotation_keyform_reflect_ys = { false, false },
    rotation_keyform_opacities = { 1, 1 },
    keyform_position_xys = {},
}, { __index = moc3.deformers })
local test_bindings = {
    keyform_slots = function()
        return { { local_index = 0, weight = 0.5 } }
    end,
}
local reflected_parent_composed = test_defs:compose(test_bindings, {})
local child_rotation = reflected_parent_composed and reflected_parent_composed[2]
check(
    "rotation parent angle uses plus-y probe",
    child_rotation and math.abs(child_rotation.angle_degrees - 5) < 0.0001,
    child_rotation and ("child angle was " .. tostring(child_rotation.angle_degrees)) or "compose failed"
)

local half_reflect_defs = setmetatable({
    parent_deformer_indices = { -1 },
    deformer_kinds = { 1 },
    specific_indices = { 0 },
    warp_keyform_binding_band_indices = {},
    warp_keyform_begin_indices = {},
    warp_keyform_counts = {},
    warp_vertex_counts = {},
    warp_rows = {},
    warp_cols = {},
    warp_keyform_opacities = {},
    rotation_keyform_binding_band_indices = { 0 },
    rotation_keyform_begin_indices = { 0 },
    rotation_keyform_counts = { 2 },
    rotation_base_angles = { 0 },
    warp_keyform_position_begin_indices = {},
    rotation_keyform_angles = { 0, 0 },
    rotation_keyform_origin_xs = { 0, 0 },
    rotation_keyform_origin_ys = { 0, 0 },
    rotation_keyform_scales = { 1, 1 },
    rotation_keyform_reflect_xs = { true, false },
    rotation_keyform_reflect_ys = { false, false },
    rotation_keyform_opacities = { 1, 1 },
    keyform_position_xys = {},
}, { __index = moc3.deformers })
local half_reflect_bindings = {
    keyform_slots = function()
        return { { local_index = 0, weight = 0.5 }, { local_index = 1, weight = 0.5 } }
    end,
}
local half_reflect_composed = half_reflect_defs:compose(half_reflect_bindings, {})
check(
    "rotation reflect interpolation uses floor sentinel",
    half_reflect_composed and half_reflect_composed[1] and half_reflect_composed[1].flip_x == false,
    half_reflect_composed and ("flip_x was " .. tostring(half_reflect_composed[1].flip_x)) or "compose failed"
)

print("\n=== Results: " .. passed .. "/" .. total .. " passed ===")
if passed == total then
    print("ALL TESTS PASSED!")
    os.exit(0)
else
    print("SOME TESTS FAILED!")
    os.exit(1)
end
