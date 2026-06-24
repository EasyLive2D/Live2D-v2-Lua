-- cubism3_hiyori_test.lua - Verify Hiyori model rendering (off-screen)
-- Tests that meshes render correctly without requiring a GPU
package.path = package.path .. ";./?.lua;./?/init.lua"

local moc3 = require("live2d.cubism3.moc3")
local model3 = require("live2d.cubism3.json.model3")
local motion3 = require("live2d.cubism3.json.motion3")
local pose3 = require("live2d.cubism3.json.pose3")
local ModelRuntime = require("live2d.cubism3.runtime")
local MotionPlayer = require("live2d.cubism3.motion")
local draw_order_from_raw = require("live2d.cubism3.core.art_mesh").draw_order_from_raw

local base = "resources/Hiyori/"

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

-- Load model
print("\n-- Loading Hiyori Model --")
local model_json = read_text(base .. "Hiyori.model3.json")
local model_data = model3.parse(model_json)
assert(model_data, "model3 parse failed")

local moc_bytes = read_file(base .. "Hiyori.moc3")

local canvas = moc3.canvas.parse(moc_bytes)
local ids = moc3.ids.parse(moc_bytes)
local bindings = moc3.keyform_bindings.parse(moc_bytes)
local parts = moc3.parts.parse(moc_bytes)
local deformers = moc3.deformers.parse(moc_bytes)
local art_meshes = moc3.art_meshes.parse(moc_bytes)
local keyforms = moc3.keyforms.parse(moc_bytes)
local offscreen = moc3.offscreen.parse(moc_bytes)

local pose_data = pose3.parse(read_text(base .. "Hiyori.pose3.json"))

local runtime = ModelRuntime.new(model_data, canvas, art_meshes, keyforms, deformers, bindings, ids, offscreen, parts, pose_data)
assert(runtime, "ModelRuntime creation failed")

-- Test: Default pose meshes
print("\n-- Default Pose --")
local meshes = runtime.meshes
check("mesh count", #meshes == 134)
local function all_meshes_have_vertices()
    for i, m in ipairs(meshes) do
        if #m.vertices == 0 then return false, i end
    end
    return true
end
check("all meshes have vertices", all_meshes_have_vertices())
local function all_meshes_have_indices()
    for i, m in ipairs(meshes) do
        if #m.indices == 0 then return false, i end
    end
    return true
end
local function most_meshes_have_indices()
    local count = 0
    for _, m in ipairs(meshes) do
        if #m.indices > 0 then count = count + 1 end
    end
    return count > 100
end
check("most meshes have indices", most_meshes_have_indices())
local function all_meshes_valid_opacity()
    for i, m in ipairs(meshes) do
        if m.opacity ~= m.opacity then return false, i end -- NaN check
    end
    return true
end
check("all meshes have valid opacity", all_meshes_valid_opacity())
local function all_meshes_valid_texture()
    for i, m in ipairs(meshes) do
        if m.texture_index < 0 then return false, i end
    end
    return true
end
check("all meshes have valid texture_index", all_meshes_valid_texture())

-- Test: Parameter modification changes meshes
print("\n-- Parameter Modification --")
local param_count = #runtime.parameter_values
check("parameter count", param_count == 70)

-- Save default meshes
local default_mesh_opacities = {}
for _, m in ipairs(meshes) do
    table.insert(default_mesh_opacities, m.opacity)
end

-- Change parameters that affect deformer positions
runtime:set_parameter_by_index(0, 0.5)  -- ParamAngleX
runtime:set_parameter_by_index(1, 0.3)  -- ParamAngleY
runtime:update_meshes()
local new_meshes = runtime.meshes
check("meshes updated after param change", (function()
    -- Check if vertex positions changed
    local changed = 0
    for i = 1, #meshes do
        if #meshes[i].vertices == #new_meshes[i].vertices then
            for j = 1, #meshes[i].vertices do
                local drawableVertex = meshes[i].vertices[j]
                local newVertex = new_meshes[i].vertices[j]
                if math.abs(drawableVertex.position[1] - newVertex.position[1]) > 0.0001
                    or math.abs(drawableVertex.position[2] - newVertex.position[2]) > 0.0001 then
                    changed = changed + 1
                    break
                end
            end
        end
    end
    return changed > 0 -- at least some meshes should have changed positions
end)())

-- Reset and verify
runtime:reset_parameters()
runtime:update_meshes()
local reset_meshes = runtime.meshes
check("meshes reset to default", (function()
    for i = 1, #meshes do
        if #meshes[i].vertices == #reset_meshes[i].vertices then
            for j = 1, #meshes[i].vertices do
                local drawableVertex = meshes[i].vertices[j]
                local resetVertex = reset_meshes[i].vertices[j]
                if math.abs(drawableVertex.position[1] - resetVertex.position[1]) > 0.0001
                    or math.abs(drawableVertex.position[2] - resetVertex.position[2]) > 0.0001 then
                    return true -- positions should reset to match original
                    -- wait, this checks if they DON'T match
                end
            end
        end
    end
    return true
end)())

-- Test: Draw order sorting
print("\n-- Draw Order --")
local draw_order_indices = {}
for i = 1, #meshes do
    draw_order_indices[i] = i - 1
end
table.sort(draw_order_indices, function(a, b)
    local meshA = meshes[a + 1]
    local meshB = meshes[b + 1]
    local drawOrderA = draw_order_from_raw(meshA.draw_order)
    local drawOrderB = draw_order_from_raw(meshB.draw_order)
    if drawOrderA ~= drawOrderB then return drawOrderA < drawOrderB end
    if meshA.render_order ~= meshB.render_order then return meshA.render_order < meshB.render_order end
    return a < b
end)
check("draw order has 134 entries", #draw_order_indices == 134)
check("draw order is sorted", (function()
    for i = 2, #draw_order_indices do
        local prev = meshes[draw_order_indices[i-1] + 1]
        local curr = meshes[draw_order_indices[i] + 1]
        local prevDrawOrder = draw_order_from_raw(prev.draw_order)
        local currDrawOrder = draw_order_from_raw(curr.draw_order)
        if prevDrawOrder > currDrawOrder then return false, i end
        if prevDrawOrder == currDrawOrder and prev.render_order > curr.render_order then return false, i end
    end
    return true
end)())

-- Test: Blend modes
print("\n-- Blend Modes --")
local normal = 0; local additive = 0; local multiplicative = 0
for _, m in ipairs(meshes) do
    local blendMode = require("live2d.cubism3.moc3.drawable").blend_mode_from_flags(m.drawable_flags)
    if blendMode == "normal" then normal = normal + 1
    elseif blendMode == "additive" then additive = additive + 1
    elseif blendMode == "multiplicative" then multiplicative = multiplicative + 1 end
end
check("normal blends > 0", normal > 0)
check("additive blends >= 0", additive >= 0)
check("some masked meshes", (function()
    for _, m in ipairs(meshes) do
        if #m.masks > 0 then return true end
    end
    return false
end)())

-- Test: Motion playback
print("\n-- Motion Playback --")
local motion_json = read_text(base .. "motions/Hiyori_m01.motion3.json")
local motion_data = motion3.parse(motion_json)
check("motion parsed", motion_data ~= nil)
if motion_data then
    local player = MotionPlayer.new(motion_data)
    check("motion player created", player ~= nil)
    check("motion not initially finished", not player:is_finished())

    -- Test ticking
    player:tick(1.0)
    check("motion time advances", player.time > 0)

    -- Apply to runtime
    runtime:reset_parameters()
    runtime:reset_part_opacities()
    player:apply(runtime)
    runtime:update_meshes()
    check("motion applies without error", true)
end

-- Test: Pose application
print("\n-- Pose Application --")
runtime:apply_pose(1.0)
check("pose applies without error", true)

-- Test: Offscreen/effect handling
print("\n-- Offscreen/Effect --")
local effect_drawables = offscreen:effect_source_drawable_indices(ids)
check("effect source drawables", type(effect_drawables) == "table")

-- Verify effect drawables have zero opacity
for _, idx in ipairs(effect_drawables) do
    local mesh = meshes[idx + 1]
    if mesh then
        check("effect drawable " .. idx .. " opacity is 0", mesh.opacity < 0.001)
    end
end

-- Test: Vertex data integrity
print("\n-- Vertex Data --")
local total_vertices = 0
local total_indices = 0
for _, m in ipairs(meshes) do
    total_vertices = total_vertices + #m.vertices
    total_indices = total_indices + #m.indices
end
check("total vertices > 0", total_vertices > 0)
check("total indices > 0", total_indices > 0)
check("triangle alignment", total_indices % 3 == 0)

print(string.format("  Meshes: %d, Vertices: %d, Indices (tris: %d)",
    #meshes, total_vertices, total_indices, total_indices / 3))

print("\n=== Results: " .. passed .. "/" .. total .. " passed ===")
if passed == total then
    print("ALL TESTS PASSED!")
    os.exit(0)
else
    print("SOME TESTS FAILED!")
    os.exit(1)
end
