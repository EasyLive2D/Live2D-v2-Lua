-- main_moc3.lua - Live2D Cubism 3 Interactive Viewer (Rana)
package.path = package.path .. ";./?.lua;./?/init.lua"
io.stdout:setvbuf("no")

local ffi = require("ffi")

print("=== Live2D Cubism 3 Viewer ===")

-- Init SDL2 + GL
local sdl2 = require("live2d.sdl2")
sdl2.enableDPIAwareness()
sdl2.init()
local W, H = 800, 900
local win = sdl2.createWindow("Live2D Cubism3 - Rana", W, H, true)
local ctx = sdl2.createGLContext(win)
sdl2.makeCurrent(win, ctx)
local targetFps = tonumber(os.getenv("LIVE2D_TARGET_FPS")) or 180
local vsync = tonumber(os.getenv("LIVE2D_VSYNC") or "0") or 0
sdl2.setSwapInterval(vsync)

local gl = require("live2d.gl_loader")
gl.ensureExtensions()

-- Load Cubism3 modules
local model3 = require("live2d.cubism3.json.model3")
local moc3 = require("live2d.cubism3.moc3")
local ModelRuntime = require("live2d.cubism3.runtime")
local MotionPlayer = require("live2d.cubism3.motion")
local OpenGLRenderer = require("live2d.cubism3.opengl_renderer")
local pose3 = require("live2d.cubism3.json.pose3")
local physics3 = require("live2d.cubism3.json.physics3")
local Physics = require("live2d.cubism3.physics")
local motion3 = require("live2d.cubism3.json.motion3")
local expression_runtime = require("live2d.cubism3.expression")
local DemoSelector = require("live2d.cubism3.demo_selector")

-- Enable blending
gl.glEnable(0x0BE2) -- GL_BLEND
gl.glEnable(0x0BC0) -- GL_TEXTURE_2D

-- Load model3.json
print("Loading Rana model3.json...")
local base = "resources/Rana/"
local model_path = base .. "adv_live2d_rana_003_live_01.model3.json"
local file = assert(io.open(model_path, "r"))
local model_json = file:read("*all")
file:close()
local model_data, err = model3.parse(model_json)
if not model_data then
    error("Failed to parse model3.json: " .. tostring(err))
end
print("  Version: " .. model_data.version)
print("  MOC: " .. model_data.file_references.moc)

-- Parse .moc3 binary
local moc_path = base .. model_data.file_references.moc
print("Loading " .. moc_path .. "...")
local file = assert(io.open(moc_path, "rb"))
local moc_bytes = file:read("*all")
file:close()
print("  Size: " .. #moc_bytes .. " bytes")

local canvas, err = moc3.canvas.parse(moc_bytes)
if not canvas then error("Canvas parse: " .. tostring(err)) end
print("  Canvas: " .. canvas.width .. "x" .. canvas.height .. " PPU=" .. canvas.pixels_per_unit)

local ids, err = moc3.ids.parse(moc_bytes)
if not ids then error("IDs parse: " .. tostring(err)) end
print("  Parts: " .. #ids.parts .. " ArtMeshes: " .. #ids.art_meshes .. " Parameters: " .. #ids.parameters)

local bindings, err = moc3.keyform_bindings.parse(moc_bytes)
if not bindings then error("Bindings parse: " .. tostring(err)) end
print("  Parameters: " .. #bindings.parameter_default_values)

local parts, err = moc3.parts.parse(moc_bytes)
if not parts then error("Parts parse: " .. tostring(err)) end
print("  Part count: " .. parts:part_count())

local deformers, err = moc3.deformers.parse(moc_bytes)
if not deformers then error("Deformers parse: " .. tostring(err)) end
print("  Deformers: " .. #deformers.deformer_kinds)

local art_meshes, err = moc3.art_meshes.parse(moc_bytes)
if not art_meshes then error("ArtMeshes parse: " .. tostring(err)) end
print("  Art meshes: " .. #art_meshes.meshes)

local keyforms, err = moc3.keyforms.parse(moc_bytes)
if not keyforms then error("Keyforms parse: " .. tostring(err)) end
print("  Keyforms: " .. #keyforms.keyforms)

local offscreen, err = moc3.offscreen.parse(moc_bytes)
if not offscreen then error("Offscreen parse: " .. tostring(err)) end
print("  Offscreen count: " .. #offscreen.offscreen_owner_part_indices)

local glues, err = moc3.glues.parse(moc_bytes)
if not glues then error("Glues parse: " .. tostring(err)) end
print("  Glues: " .. glues:len())

-- Load pose
local pose = nil
if model_data.file_references.pose then
    local pose_path = base .. model_data.file_references.pose
    print("Loading pose: " .. pose_path)
    local file = assert(io.open(pose_path, "r"))
    local pose_json = file:read("*all")
    file:close()
    local pose_data, err = pose3.parse(pose_json)
    if pose_data then
        pose = pose_data
        print("  Pose groups: " .. #pose.groups)
    else
        print("  Pose parse warning: " .. tostring(err))
    end
end

-- Create runtime
print("Creating ModelRuntime...")
local draw_order_groups = moc3.draw_order_groups.parse(moc_bytes)
local runtime = ModelRuntime.new(
    model_data, canvas, art_meshes, keyforms, deformers, bindings,
    ids, offscreen, glues, parts, draw_order_groups, pose
)
if not runtime then
    error("Failed to create ModelRuntime")
end
print("  Meshes: " .. #runtime.meshes)

if model_data.file_references.physics then
    local physics_path = base .. model_data.file_references.physics
    print("Loading physics: " .. physics_path)
    local physics_file = assert(io.open(physics_path, "r"))
    local physics_data, physics_err = physics3.parse(physics_file:read("*all"))
    physics_file:close()
    if not physics_data then error("Physics parse: " .. tostring(physics_err)) end
    local physics, create_err = Physics.new(physics_data)
    if not physics then error("Physics create: " .. tostring(create_err)) end
    runtime:set_physics(physics)
    print("  Physics settings: " .. #physics.settings)
end

-- Setup textures
print("Loading textures...")
local textures = {}
for i, tex_path in ipairs(model_data.file_references.textures) do
    local full_path = base .. tex_path
    textures[i] = full_path
end

-- Load motions
print("Loading motions...")
local motions = {}
local motion_groups = model_data.file_references.motions
for group_name, refs in pairs(motion_groups) do
    for motion_no, ref in ipairs(refs) do
        local motion_path = base .. ref.File
        local ok, mf = pcall(io.open, motion_path, "r")
        if ok and mf then
            local motion_json = mf:read("*all")
            mf:close()
            local motion_data, err = motion3.parse(motion_json)
            if motion_data then
                local player = MotionPlayer.new(motion_data)
                table.insert(motions, {
                    name = group_name,
                    file = ref.File,
                    label = string.format("%s #%d", group_name, motion_no),
                    player = player,
                })
                print("  Motion: " .. group_name .. " - " .. ref.File)
            else
                print("  Motion parse warning: " .. tostring(err))
            end
        end
    end
end

-- Load expressions
print("Loading expressions...")
local expressions = {}
for _, ref in ipairs(model_data.file_references.expressions or {}) do
    local expression_path = base .. ref.File
    local expression_data, err = expression_runtime.load_expression(expression_path)
    if expression_data then
        table.insert(expressions, {
            name = ref.Name,
            file = ref.File,
            label = ref.Name or ref.File,
            expression = expression_data,
        })
        print("  Expression: " .. (ref.Name or ref.File))
    else
        print("  Expression parse warning: " .. tostring(err))
    end
end
if #expressions == 0 then
    print("  No expressions")
end

-- Create renderer
print("Creating OpenGL renderer...")
local renderer = OpenGLRenderer.new(gl)

-- Load textures
for _, tex_path in ipairs(textures) do
    print("  Texture: " .. tex_path)
    renderer:load_texture(tex_path)
end

-- Setup projection matrix (orthographic projection matching canvas)
-- Compute model scale to fit window
local model_width = canvas.width / canvas.pixels_per_unit
local model_height = canvas.height / canvas.pixels_per_unit
local drawW, drawH = sdl2.getDrawableSize(win)
local proj

local function updateProjection()
    local nextDrawW, nextDrawH = sdl2.getDrawableSize(win)
    if nextDrawW <= 0 then nextDrawW = W end
    if nextDrawH <= 0 then nextDrawH = H end
    if proj and nextDrawW == drawW and nextDrawH == drawH then return end

    drawW, drawH = nextDrawW, nextDrawH

    local scale = math.min(drawW / model_width, drawH / model_height) * 0.8
    proj = ffi.new("float[16]", {
        scale * 2.0 / drawW, 0, 0, 0,
        0, scale * 2.0 / drawH, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    })
    gl.glViewport(0, 0, drawW, drawH)
end

updateProjection()

print("\n=== Starting render loop ===")

local running = true
local frameCount = 0
local targetFrameMs = targetFps > 0 and (1000 / targetFps) or 0
local motionIndex = 0
local currentMotion = nil
local lastTime = sdl2.getTicks()
local expressionManager = expression_runtime.ExpressionManager.new()
local selector = DemoSelector.new({ motions = motions, expressions = expressions })

local function isInsideWindow(x, y)
    return x >= 0 and x < W and y >= 0 and y < H
end

local function applyMouseGaze()
    local mouseX, mouseY = sdl2.getMouseState()
    if not isInsideWindow(mouseX, mouseY) then return end

    local x = (mouseX / W - 0.5) * 2.0
    local y = (mouseY / H - 0.5) * -2.0
    runtime:set_parameter("ParamAngleX", x * 30.0)
    runtime:set_parameter("ParamAngleY", y * 30.0)
    runtime:set_parameter("ParamEyeBallX", x)
    runtime:set_parameter("ParamEyeBallY", y)
end

local function playMotion(motionData, selectedIndex)
    if motionData == nil then return end
    motionIndex = selectedIndex or motionIndex
    currentMotion = motionData.player
    currentMotion:restart()
    print("Motion: " .. (motionData.label or motionData.name))
end

local function playNextMotion()
    if #motions == 0 then return end
    local motionData, selectedIndex = selector:select_next_motion()
    playMotion(motionData, selectedIndex)
end

local function playExpression(expressionData)
    if expressionData == nil then return end
    expressionManager:play(expressionData.expression)
    print("Expression: " .. (expressionData.label or expressionData.name or expressionData.file))
end

-- Event loop
while running do
    local frameStart = sdl2.getTicks()
    local now = frameStart
    local delta = math.min((now - lastTime) / 1000.0, 0.1)
    lastTime = now

    local event = sdl2.pollEvent()
    while event ~= nil do
        local etype = tonumber(event.type) or 0
        if etype == sdl2.SDL_QUIT then
            running = false
        elseif etype == sdl2.SDL_KEYDOWN then
            local key = tonumber(event.key.keysym.sym) or 0
            if key == sdl2.SDLK_ESCAPE then running = false end
        elseif etype == sdl2.SDL_MOUSEBUTTONDOWN then
            local x = tonumber(event.button.x) or -1
            local y = tonumber(event.button.y) or -1
            if tonumber(event.button.button) == 1 and isInsideWindow(x, y) then
                local hit = selector:handle_click(x, y, playMotion, playExpression)
                if hit == nil then
                    playNextMotion()
                end
            end
        elseif etype == sdl2.SDL_WINDOWEVENT then
            if tonumber(event.window.event) == sdl2.SDL_WINDOWEVENT_SIZE_CHANGED then
                W = tonumber(event.window.data1) or W
                H = tonumber(event.window.data2) or H
                updateProjection()
            end
        end
        event = sdl2.pollEvent()
    end

    -- Apply motion
    if currentMotion then
        currentMotion:tick(delta)
        currentMotion:apply(runtime)
        if currentMotion:is_finished() then
            playNextMotion()
        end
    end

    expressionManager:tick(delta)
    expressionManager:apply(runtime)

    applyMouseGaze()

    runtime:update_physics(delta)

    -- Apply pose
    runtime:apply_pose(delta)

    -- Update meshes with current parameter values
    runtime:update_meshes()

    -- Clear and draw
    updateProjection()
    gl.glClearColor(0.18, 0.20, 0.22, 1.0)
    gl.glClear(0x4000) -- GL_COLOR_BUFFER_BIT

    renderer:render_meshes(runtime.meshes, textures, proj)
    selector:draw(gl, W, H)

    sdl2.swapWindow(win)
    frameCount = frameCount + 1

    collectgarbage("step", 200)

    local elapsed = sdl2.getTicks() - frameStart
    if targetFrameMs > 0 and elapsed < targetFrameMs then
        sdl2.delay(math.floor(targetFrameMs - elapsed))
    end
end

print(string.format("Exited after %d frames.", frameCount))
renderer:destroy()
sdl2.deleteGLContext(ctx)
sdl2.destroyWindow(win)
sdl2.quit()
print("Done.")
