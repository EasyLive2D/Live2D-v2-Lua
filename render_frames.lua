-- render_frames.lua - Render 20 frames of kasumi2 and save as BMP
package.path = package.path .. ";./?.lua;./?/init.lua"
io.stdout:setvbuf("no")

local ffi = require("ffi")

print("=== Live2D Frame Renderer ===")

-- Init SDL2 + GL
local sdl2 = require("live2d.sdl2"); sdl2.init()
local W, H = 400, 650
local win = sdl2.createWindow("Live2D Render", W, H)
local ctx = sdl2.createGLContext(win); sdl2.makeCurrent(win, ctx)
local gl = require("live2d.gl_loader"); gl.ensureExtensions()

-- Init Live2D
local live2d = require("live2d")
local Live2DFramework = live2d.Live2DFramework
local Live2D = live2d.Live2D
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

-- Override model matrix to center and zoom the model
model.modelMatrix:identity()
model.modelMatrix:setWidth(2.0)
model.modelMatrix:setCenterPosition(0, 0)

print("Model loaded.")

-- Function: read framebuffer pixels
local function readPixels(w, h)
    local size = w * h * 4
    local pixels = ffi.new("uint8_t[?]", size)
    gl.glReadPixels(0, 0, w, h, 0x1908, 0x1401, pixels) -- GL_RGBA, GL_UNSIGNED_BYTE
    return pixels, size
end

-- Helper: write little-endian values to file
local function writeLE(f, value, bytes)
    for i = 0, bytes - 1 do
        local b = bit.band(bit.rshift(value, i * 8), 0xFF)
        f:write(string.char(b))
    end
end

-- Function: save BMP file
local function saveBMP(path, pixels, w, h)
    local rowSize = bit.band(w * 3 + 3, bit.bnot(3))  -- padded to 4 bytes
    local pixelDataSize = rowSize * h
    local fileSize = 54 + pixelDataSize
    
    local f = io.open(path, "wb")
    f:write("BM")
    writeLE(f, fileSize, 4)
    writeLE(f, 0, 4)       -- reserved
    writeLE(f, 54, 4)      -- offset to pixel data
    writeLE(f, 40, 4)      -- header size
    writeLE(f, w, 4)
    writeLE(f, h, 4)
    writeLE(f, 1, 2)       -- planes
    writeLE(f, 24, 2)      -- bits per pixel
    writeLE(f, 0, 4)       -- no compression
    writeLE(f, pixelDataSize, 4)
    writeLE(f, 2835, 4)    -- 72 DPI horizontal
    writeLE(f, 2835, 4)    -- 72 DPI vertical
    writeLE(f, 0, 4)       -- no palette
    writeLE(f, 0, 4)
    
    -- Pixel data (BMP is bottom-up, OpenGL also bottom-up after glReadPixels, so same order)
    -- But OpenGL gives RGBA, BMP expects BGR (no alpha)
    local row = ffi.new("uint8_t[?]", rowSize)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local srcIdx = (y * w + x) * 4
            local dstIdx = x * 3
            row[dstIdx] = pixels[srcIdx + 2]     -- B ← R
            row[dstIdx + 1] = pixels[srcIdx + 1] -- G ← G
            row[dstIdx + 2] = pixels[srcIdx]     -- R ← B
        end
        -- Pad remaining bytes to zero
        for x = w * 3, rowSize - 1 do
            row[x] = 0
        end
        f:write(ffi.string(row, rowSize))
    end
    f:close()
end

-- Render loop
local frameTime = 1.0 / 20.0  -- 20 FPS = 50ms per frame
local totalFrames = 20

print(string.format("Rendering %d frames at %.0f FPS...", totalFrames, 1.0/frameTime))

for i = 1, totalFrames do
    -- Advance model state
    local dt = frameTime * 1000  -- ms
    model.startTimeMSec = model.startTimeMSec + dt
    
    -- Clear and render
    Live2DGLWrapper.clearColor(0.0, 0.0, 0.0, 0.0)
    Live2DGLWrapper.clear(Live2DGLWrapper.COLOR_BUFFER_BIT)
    model:Update()
    model:Draw()
    
    -- Read pixels BEFORE swap (from back buffer which has our render)
    local pixels = readPixels(W, H)
    
    sdl2.swapWindow(win)
    
    -- Save frame from captured pixels
    local path = string.format("frames_output/frame_%04d.bmp", i)
    saveBMP(path, pixels, W, H)
    
    if i % 5 == 0 then
        print(string.format("  Frame %d/%d saved", i, totalFrames))
    end
end

print(string.format("All %d frames saved to frames_output/ as BMP", totalFrames))
sdl2.destroyWindow(win)
sdl2.quit()
