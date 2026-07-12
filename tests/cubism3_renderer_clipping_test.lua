-- cubism3_renderer_clipping_test.lua - renderer applies Cubism drawable masks
package.path = package.path .. ";./?.lua;./?/init.lua"

local ffi = require("ffi")
local OpenGLRenderer = require("live2d.cubism3.opengl_renderer")

pcall(ffi.cdef, "typedef unsigned int GLuint;")

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
    gl.glBlendFuncSeparate = function(...) record("glBlendFuncSeparate", ...) end
    gl.glBlendEquationSeparate = function(...) record("glBlendEquationSeparate", ...) end
    gl.glBindBuffer = function(...) record("glBindBuffer", ...) end
    gl.glBufferData = function(...) record("glBufferData", ...) end
    gl.glBufferSubData = function(...) record("glBufferSubData", ...) end
    gl.glGenBuffers = function(count, out)
        for i = 0, count - 1 do out[i] = #calls + i + 1 end
    end
    gl.glUniformMatrix4fv = function(...) record("glUniformMatrix4fv", ...) end
    gl.glUniform4f = function(...) record("glUniform4f", ...) end
    gl.glActiveTexture = function(...) record("glActiveTexture", ...) end
    gl.glBindTexture = function(...) record("glBindTexture", ...) end
    gl.glUniform1i = function(...) record("glUniform1i", ...) end
    gl.glEnableVertexAttribArray = function(...) record("glEnableVertexAttribArray", ...) end
    gl.glDisableVertexAttribArray = function(...) record("glDisableVertexAttribArray", ...) end
    gl.glVertexAttribPointer = function(...) record("glVertexAttribPointer", ...) end
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

local function count_calls(calls, name)
    local count = 0
    for _, call in ipairs(calls) do
        if call.name == name then count = count + 1 end
    end
    return count
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

local function new_shader_capture_gl()
    local shader_id = 0
    local program_id = 100
    local gl = {
        shader_sources = {},
        calls = {},
    }

    local function record(name, ...)
        gl.calls[#gl.calls + 1] = { name = name, args = { ... } }
    end

    gl.glCreateShader = function(kind)
        shader_id = shader_id + 1
        gl.shader_sources[shader_id] = { kind = kind, source = "" }
        return shader_id
    end
    gl.glShaderSource = function(shader, count, strings, lengths)
        local chunks = {}
        for i = 0, count - 1 do
            chunks[#chunks + 1] = ffi.string(strings[i], lengths and lengths[i] or nil)
        end
        gl.shader_sources[shader].source = table.concat(chunks)
    end
    gl.glCompileShader = function(...) record("glCompileShader", ...) end
    gl.glGetShaderiv = function(_, _, status) status[0] = 1 end
    gl.glGetShaderInfoLog = function() end
    gl.glCreateProgram = function()
        program_id = program_id + 1
        return program_id
    end
    gl.glAttachShader = function(...) record("glAttachShader", ...) end
    gl.glLinkProgram = function(...) record("glLinkProgram", ...) end
    gl.glGetProgramiv = function(_, _, status) status[0] = 1 end
    gl.glGetProgramInfoLog = function() end
    gl.glDeleteShader = function(...) record("glDeleteShader", ...) end
    gl.glGetUniformLocation = function() return 0 end
    gl.glGetAttribLocation = function() return -1 end
    gl.glGenBuffers = function(count, out)
        for i = 0, count - 1 do out[i] = i + 1 end
    end

    return gl
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

local shader_gl = new_shader_capture_gl()
OpenGLRenderer.new(shader_gl)
local fragment_source
for _, shader in pairs(shader_gl.shader_sources) do
    if shader.kind == 0x8B30 then
        fragment_source = shader.source
    end
end
check("shader applies screen color before premultiplying alpha",
    fragment_source ~= nil
    and fragment_source:find("blended = blended + v_screen * tex.a - blended * v_screen", 1, true) ~= nil
    and fragment_source:find("gl_FragColor = vec4(blended * v_opacity, alpha)", 1, true) ~= nil,
    fragment_source or "fragment shader was not captured")

local projection = ffi.new("float[16]", {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
})

local zero_opacity_mask = mesh({})
zero_opacity_mask.opacity = 0.0
renderer:render_meshes({ zero_opacity_mask, mesh({ 0 }) }, nil, projection)

check("normal blend uses premultiplied alpha",
    has_call(gl.calls, "glBlendFuncSeparate", function(args)
        return args[1] == 0x0001 and args[2] == 0x0303
            and args[3] == 0x0001 and args[4] == 0x0303
    end),
    "expected GL_ONE/GL_ONE_MINUS_SRC_ALPHA for color and alpha")

local additive_mesh = mesh({})
additive_mesh.drawable_flags = 1
renderer:draw_mesh(additive_mesh, nil, projection)
check("additive blend preserves destination alpha",
    has_call(gl.calls, "glBlendFuncSeparate", function(args)
        return args[1] == 0x0001 and args[2] == 0x0001
            and args[3] == 0x0000 and args[4] == 0x0001
    end),
    "expected GL_ONE/GL_ONE/GL_ZERO/GL_ONE")

local multiplicative_mesh = mesh({})
multiplicative_mesh.drawable_flags = 2
renderer:draw_mesh(multiplicative_mesh, nil, projection)
check("multiplicative blend uses destination color",
    has_call(gl.calls, "glBlendFuncSeparate", function(args)
        return args[1] == 0x0306 and args[2] == 0x0303
            and args[3] == 0x0000 and args[4] == 0x0001
    end),
    "expected GL_DST_COLOR/GL_ONE_MINUS_SRC_ALPHA/GL_ZERO/GL_ONE")

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
check("zero-opacity masks still draw into stencil",
    zero_opacity_mask.opacity == 0.0 and count_calls(gl.calls, "glDrawElements") >= 2,
    "mask opacity should be restored after stencil draw")

local grouped_gl = new_fake_gl()
local grouped_renderer = setmetatable({
    gl = grouped_gl,
    shader = 1,
    u_projection = 4,
    u_texture = 5,
    u_options = 6,
    textures = {},
}, { __index = OpenGLRenderer })
local grouped_mask = mesh({})
grouped_mask.opacity = 0
local grouped_first = mesh({ 0 })
grouped_first.render_order = 1
local grouped_second = mesh({ 0 })
grouped_second.render_order = 2
grouped_renderer:render_meshes({ grouped_mask, grouped_first, grouped_second }, nil, projection)
check("consecutive equal masks reuse stencil build",
    count_calls(grouped_gl.calls, "glClear") == 1,
    "expected one stencil clear")
check("grouped clipping preserves all target draws",
    count_calls(grouped_gl.calls, "glDrawElements") == 3,
    "expected one mask and two target draws")

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
