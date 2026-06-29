-- cubism3_renderer_clipping_test.lua - renderer applies Cubism drawable masks
package.path = package.path .. ";./?.lua;./?/init.lua"

local ffi = require("ffi")
local OpenGLRenderer = require("live2d.cubism3.opengl_renderer")

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

local function new_fake_gl()
    local calls = {}
    local gl = { calls = calls }

    local function record(name, ...)
        calls[#calls + 1] = { name = name, args = { ... } }
    end

    gl.glUseProgram = function(...) record("glUseProgram", ...) end
    gl.glEnable = function(...) record("glEnable", ...) end
    gl.glDisable = function(...) record("glDisable", ...) end
    gl.glClear = function(...) record("glClear", ...) end
    gl.glColorMask = function(...) record("glColorMask", ...) end
    gl.glStencilMask = function(...) record("glStencilMask", ...) end
    gl.glStencilFunc = function(...) record("glStencilFunc", ...) end
    gl.glStencilOp = function(...) record("glStencilOp", ...) end
    gl.glAlphaFunc = function(...) record("glAlphaFunc", ...) end
    gl.glBlendFunc = function(...) record("glBlendFunc", ...) end
    gl.glBlendEquationSeparate = function(...) record("glBlendEquationSeparate", ...) end
    gl.glBindBuffer = function(...) record("glBindBuffer", ...) end
    gl.glBufferData = function(...) record("glBufferData", ...) end
    gl.glUniformMatrix4fv = function(...) record("glUniformMatrix4fv", ...) end
    gl.glActiveTexture = function(...) record("glActiveTexture", ...) end
    gl.glBindTexture = function(...) record("glBindTexture", ...) end
    gl.glUniform1i = function(...) record("glUniform1i", ...) end
    gl.glDrawElements = function(...) record("glDrawElements", ...) end
    gl.glGetAttribLocation = function() return -1 end

    return gl
end

local function has_call(calls, name, predicate)
    for _, call in ipairs(calls) do
        if call.name == name and (not predicate or predicate(call.args)) then
            return true
        end
    end
    return false
end

local function mesh(masks)
    return {
        texture_index = 0,
        drawable_flags = 0,
        opacity = 1.0,
        draw_order = 0,
        render_order = 0,
        multiply_color = { 1, 1, 1 },
        screen_color = { 0, 0, 0 },
        vertices = {
            { position = { 0, 0 }, uv = { 0, 0 } },
            { position = { 1, 0 }, uv = { 1, 0 } },
            { position = { 0, 1 }, uv = { 0, 1 } },
        },
        indices = { 0, 1, 2 },
        masks = masks or {},
    }
end

local function bound_textures(calls)
    local textures = {}
    for _, call in ipairs(calls) do
        if call.name == "glBindTexture" and call.args[1] == 0x0DE1 then
            textures[#textures + 1] = call.args[2]
        end
    end
    return textures
end

local gl = new_fake_gl()
local renderer = setmetatable({
    gl = gl,
    shader = 1,
    vbo = 2,
    ibo = 3,
    u_projection = 4,
    u_texture = 5,
    textures = {},
}, { __index = OpenGLRenderer })

local projection = ffi.new("float[16]", {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
})

renderer:render_meshes({ mesh({}), mesh({ 0 }) }, nil, projection)

check("masked drawable enables stencil test",
    has_call(gl.calls, "glEnable", function(args) return args[1] == 0x0B90 end))
check("mask is drawn without writing color",
    has_call(gl.calls, "glColorMask", function(args)
        return args[1] == 0 and args[2] == 0 and args[3] == 0 and args[4] == 0
    end))
check("masked drawable tests stencil equality",
    has_call(gl.calls, "glStencilFunc", function(args) return args[1] == 0x0202 end))
check("stencil is disabled after masked draw",
    has_call(gl.calls, "glDisable", function(args) return args[1] == 0x0B90 end))

local order_gl = new_fake_gl()
local order_renderer = setmetatable({
    gl = order_gl,
    shader = 1,
    vbo = 2,
    ibo = 3,
    u_projection = 4,
    u_texture = 5,
    textures = {},
    ensure_texture = function(_, texture_path) return texture_path end,
}, { __index = OpenGLRenderer })

local first = mesh({})
first.texture_index = 0
first.draw_order = 0
first.render_order = 1

local second = mesh({})
second.texture_index = 1
second.draw_order = 100
second.render_order = 0

order_renderer:render_meshes({ first, second }, { "first", "second" }, projection)
local texture_order = bound_textures(order_gl.calls)
check("expanded total-rank render order controls draw order",
    texture_order[1] == "second" and texture_order[2] == "first",
    string.format("got %s then %s", tostring(texture_order[1]), tostring(texture_order[2])))

print(string.format("\n=== Results: %d/%d passed ===", passed, total))
if passed == total then
    print("ALL TESTS PASSED!")
    os.exit(0)
else
    print("SOME TESTS FAILED!")
    os.exit(1)
end
