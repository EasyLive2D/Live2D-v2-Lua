-- main.lua - Live2D Interactive Viewer
package.path = package.path .. ";./?.lua;./?/init.lua"
io.stdout:setvbuf("no")

local ffi = require("ffi")

print("=== Live2D Cubism 2.1 Viewer ===")

-- Init SDL2 + GL
local sdl2 = require("live2d.sdl2")
sdl2.init()
local W, H = 400, 650
local win = sdl2.createWindow("Live2D - kasumi2", W, H)
local ctx = sdl2.createGLContext(win)
sdl2.makeCurrent(win, ctx)
sdl2.setSwapInterval(1)

local gl = require("live2d.gl_loader")
gl.ensureExtensions()

-- Init Live2D
local live2d = require("live2d")
local Live2DFramework = live2d.Live2DFramework
local Live2D = live2d.Live2D
local MotionPriority = live2d.MotionPriority
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")

local pm = require("live2d.platform_manager").new()
Live2DFramework.setPlatformManager(pm)
Live2D.init()

-- Load model
local LAppModel = live2d.LAppModel
local model = LAppModel.new()
print("Loading kasumi2...")
model:LoadModelJson("resources/kasumi2/kasumi2.model.json")
model:Resize(W, H)
model:SetAutoBreathEnable(true)
model:SetAutoBlinkEnable(true)
model.modelMatrix:identity()
model.modelMatrix:setWidth(2.0)
model.modelMatrix:setCenterPosition(0, 0)

print("Model loaded.")

local running = true
local drag = false
local dragX, dragY = 0, 0
local offsetX, offsetY = 0, 0
local scale = 1.0
local frameCount = 0
local targetFrameMs = 1000 / 60
local motionNames = model.modelSetting:getMotionNames() or {}
local motionIndex = 1

table.sort(motionNames)

local function isInsideWindow(x, y)
    return x >= 0 and x < W and y >= 0 and y < H
end

local function playNextMotion()
    local total = #motionNames
    if total == 0 then return end

    for _ = 1, total do
        local name = motionNames[motionIndex]
        motionIndex = motionIndex % total + 1
        if model.modelSetting:getMotionNum(name) > 0 then
            print("Motion: " .. name)
            model:StartMotion(name, 0, MotionPriority.FORCE)
            return
        end
    end
end

-- Pre-render first frame to ensure shaders compile
Live2DGLWrapper.clearColor(0.0, 0.0, 0.0, 0.0)
Live2DGLWrapper.clear(Live2DGLWrapper.COLOR_BUFFER_BIT)
model:Update()
model:Draw()
print("First frame rendered (shader init)")

-- Verify rendering
local pix = ffi.new("uint8_t[4]")
gl.glReadPixels(200, 325, 1, 1, 0x1908, 0x1401, pix)
print(string.format("Pixel verification: R=%d G=%d B=%d", pix[0], pix[1], pix[2]))

-- Event loop
while running do
    local frameStart = sdl2.getTicks()

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
                playNextMotion()
            end
        elseif etype == sdl2.SDL_WINDOWEVENT then
            if tonumber(event.window.event) == sdl2.SDL_WINDOWEVENT_SIZE_CHANGED then
                W = tonumber(event.window.data1) or W
                H = tonumber(event.window.data2) or H
                model:Resize(W, H)
                Live2DGLWrapper.viewport(0, 0, W, H)
            end
        end
        event = sdl2.pollEvent()
    end

    local mouseX, mouseY = sdl2.getMouseState()
    if isInsideWindow(mouseX, mouseY) then
        model:Drag(mouseX, mouseY)
    end

    Live2DGLWrapper.clearColor(0.0, 0.0, 0.0, 0.0)
    Live2DGLWrapper.clear(Live2DGLWrapper.COLOR_BUFFER_BIT)
    model:Update()
    model:Draw()
    sdl2.swapWindow(win)
    frameCount = frameCount + 1

    -- Rendering allocates temporary FFI buffers per mesh; keep the viewer from
    -- outrunning GC on drivers where vsync is unavailable or disabled.
    collectgarbage("step", 200)

    local elapsed = sdl2.getTicks() - frameStart
    if elapsed < targetFrameMs then
        sdl2.delay(math.floor(targetFrameMs - elapsed))
    end
end

print(string.format("Exited after %d frames.", frameCount))
sdl2.deleteGLContext(ctx)
sdl2.destroyWindow(win)
sdl2.quit()
print("Done.")
