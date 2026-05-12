-- simple.lua: Minimal Live2D demo using Core SDK directly
-- Equivalent to simple.py

package.path = package.path .. ";./?.lua;./?/init.lua"

local Live2D = require("live2d.core.live2d")
local Live2DModelOpenGL = require("live2d.core.live2d_model_opengl")
local UtSystem = require("live2d.core.util.ut_system")

print("Live2D Simple Demo (LuaJIT)")
print("Load and render a .moc model file with OpenGL")

-- Stub: actual implementation requires SDL2 + OpenGL via FFI
-- The model loading and parameter animation logic is complete.
-- Render loop will be implemented once SDL2/OpenGL FFI bindings are ready.

local function loadImage(path)
    -- Placeholder: load texture via stb_image FFI
    print("loadImage:", path)
    return 0
end

local function main()
    -- Init Live2D
    Live2D.init()

    -- Load model
    local model_path = "test-data/epsilon/Epsilon.moc"  -- adjust as needed
    print("Loading model:", model_path)

    -- Create OpenGL window (SDL2)
    print("SDL2/OpenGL window initialization requires FFI bindings (TBD)")
end

main()
