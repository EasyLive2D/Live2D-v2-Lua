-- Live2DGLWrapper - wraps OpenGL functions for Cubism 2.1 renderer
-- Now backed by real OpenGL FFI calls via gl_loader.lua

local gl = require("live2d.gl_loader")
local ffi = require("ffi")

local Live2DGLWrapper = {}
Live2DGLWrapper.__index = Live2DGLWrapper

-- GL constants
Live2DGLWrapper.FRAMEBUFFER = 0x8D40
Live2DGLWrapper.RENDERBUFFER = 0x8D41
Live2DGLWrapper.COLOR_BUFFER_BIT = 0x00004000
Live2DGLWrapper.RGBA4 = 0x8056
Live2DGLWrapper.COLOR_ATTACHMENT0 = 0x8CE0
Live2DGLWrapper.RGBA = 0x1908
Live2DGLWrapper.UNSIGNED_BYTE = 0x1401
Live2DGLWrapper.TEXTURE_2D = 0x0DE1
Live2DGLWrapper.TEXTURE_MIN_FILTER = 0x2801
Live2DGLWrapper.TEXTURE_MAG_FILTER = 0x2800
Live2DGLWrapper.LINEAR = 0x2601
Live2DGLWrapper.CLAMP_TO_EDGE = 0x812F
Live2DGLWrapper.TEXTURE_WRAP_S = 0x2802
Live2DGLWrapper.TEXTURE_WRAP_T = 0x2803
Live2DGLWrapper.VERTEX_SHADER = 0x8B31
Live2DGLWrapper.FRAGMENT_SHADER = 0x8B30
Live2DGLWrapper.COMPILE_STATUS = 0x8B81
Live2DGLWrapper.LINK_STATUS = 0x8B82
Live2DGLWrapper.SCISSOR_TEST = 0x0C11
Live2DGLWrapper.STENCIL_TEST = 0x0B90
Live2DGLWrapper.DEPTH_TEST = 0x0B71
Live2DGLWrapper.CW = 0x0900
Live2DGLWrapper.CCW = 0x0901
Live2DGLWrapper.BLEND = 0x0BE2
Live2DGLWrapper.ARRAY_BUFFER = 0x8892
Live2DGLWrapper.ELEMENT_ARRAY_BUFFER = 0x8893
Live2DGLWrapper.DYNAMIC_DRAW = 0x88E8
Live2DGLWrapper.FLOAT = 0x1406
Live2DGLWrapper.TEXTURE1 = 0x84C1
Live2DGLWrapper.TEXTURE2 = 0x84C2
Live2DGLWrapper.CULL_FACE = 0x0B44
Live2DGLWrapper.ONE = 1
Live2DGLWrapper.SRC_ALPHA = 0x0302
Live2DGLWrapper.ONE_MINUS_SRC_ALPHA = 0x0303
Live2DGLWrapper.DST_COLOR = 0x0306
Live2DGLWrapper.ZERO = 0
Live2DGLWrapper.FUNC_ADD = 0x8006
Live2DGLWrapper.TRIANGLES = 0x0004
Live2DGLWrapper.UNSIGNED_SHORT = 0x1403
Live2DGLWrapper.FRAMEBUFFER_BINDING = 0x8CA6
Live2DGLWrapper.DEPTH_BUFFER_BIT = 0x00000100
Live2DGLWrapper.ONE_MINUS_SRC_COLOR = 0x0301
Live2DGLWrapper.LINEAR_MIPMAP_LINEAR = 0x2703
Live2DGLWrapper.TEXTURE_MAX_ANISOTROPY = 0x84FE

function Live2DGLWrapper.new()
    local self = setmetatable({}, Live2DGLWrapper)
    self.width = 0
    self.height = 0
    return self
end

function Live2DGLWrapper:resize(w, h)
    self.width = w
    self.height = h
end

-- Static GL method wrappers
function Live2DGLWrapper.getAttribLocation(program, name)
    return gl.glGetAttribLocation(program, name)
end

function Live2DGLWrapper.getUniformLocation(program, name)
    return gl.glGetUniformLocation(program, name)
end

function Live2DGLWrapper.createFramebuffer()
    local fbo = ffi.new("GLuint[1]")
    gl.glGenFramebuffers(1, fbo)
    return fbo[0]
end

function Live2DGLWrapper.bindFramebuffer(t, fbo)
    gl.glBindFramebuffer(t, fbo)
end

function Live2DGLWrapper.createRenderbuffer()
    local rbo = ffi.new("GLuint[1]")
    gl.glGenRenderbuffers(1, rbo)
    return rbo[0]
end

function Live2DGLWrapper.bindRenderbuffer(t, rbo)
    gl.glBindRenderbuffer(t, rbo)
end

function Live2DGLWrapper.renderbufferStorage(t, fat, w, h)
    gl.glRenderbufferStorage(t, fat, w, h)
end

function Live2DGLWrapper.framebufferRenderbuffer(t, att, rbt, rb)
    gl.glFramebufferRenderbuffer(t, att, rbt, rb)
end

function Live2DGLWrapper.createTexture()
    local tex = ffi.new("GLuint[1]")
    gl.glGenTextures(1, tex)
    return tex[0]
end

function Live2DGLWrapper.bindTexture(t, tid)
    gl.glBindTexture(t, tid)
end

function Live2DGLWrapper.texImage2D(t, level, fmt, w, h, border, dataFmt, dataType, pixels)
    gl.glTexImage2D(t, level, fmt, w, h, border, dataFmt, dataType, pixels)
end

function Live2DGLWrapper.texParameteri(t, pname, param)
    gl.glTexParameteri(t, pname, param)
end

function Live2DGLWrapper.framebufferTexture2D(t, att, texTarget, tex, level)
    gl.glFramebufferTexture2D(t, att, texTarget, tex, level)
end

function Live2DGLWrapper.createProgram()
    return gl.glCreateProgram()
end

function Live2DGLWrapper.compileShader(s)
    gl.glCompileShader(s)
end

function Live2DGLWrapper.createShader(t)
    return gl.glCreateShader(t)
end

function Live2DGLWrapper.shaderSource(s, src)
    local src_arr = ffi.new("const char *[1]")
    src_arr[0] = ffi.cast("const char *", src)
    gl.glShaderSource(s, 1, src_arr, nil)
end

function Live2DGLWrapper.getShaderParameter(s, pname)
    local v = ffi.new("GLint[1]")
    gl.glGetShaderiv(s, pname, v)
    return v[0] ~= 0
end

function Live2DGLWrapper.getShaderInfoLog(s)
    local buf = ffi.new("GLchar[1024]")
    local len = ffi.new("GLsizei[1]")
    gl.glGetShaderInfoLog(s, 1024, len, buf)
    return ffi.string(buf, len[0])
end

function Live2DGLWrapper.attachShader(p, s)
    gl.glAttachShader(p, s)
end

function Live2DGLWrapper.linkProgram(p)
    gl.glLinkProgram(p)
end

function Live2DGLWrapper.getProgramParameter(p, pname)
    local v = ffi.new("GLint[1]")
    gl.glGetProgramiv(p, pname, v)
    return v[0] ~= 0
end

function Live2DGLWrapper.getProgramInfoLog(p)
    local buf = ffi.new("GLchar[1024]")
    local len = ffi.new("GLsizei[1]")
    gl.glGetProgramInfoLog(p, 1024, len, buf)
    return ffi.string(buf, len[0])
end

function Live2DGLWrapper.disable(t)
    gl.glDisable(t)
end

function Live2DGLWrapper.bindBuffer(t, b)
    gl.glBindBuffer(t, b)
end

function Live2DGLWrapper.enable(t)
    gl.glEnable(t)
end

function Live2DGLWrapper.colorMask(r, g, b, a)
    gl.glColorMask(r, g, b, a)
end

function Live2DGLWrapper.frontFace(t)
    gl.glFrontFace(t)
end

function Live2DGLWrapper.useProgram(p)
    gl.glUseProgram(p)
end

function Live2DGLWrapper.createBuffer()
    local buf = ffi.new("GLuint[1]")
    gl.glGenBuffers(1, buf)
    return buf[0]
end

function Live2DGLWrapper.bufferData(t, data, usage)
    if t == Live2DGLWrapper.ARRAY_BUFFER then
        local arr = ffi.new("float[?]", #data)
        for i = 1, #data do
            arr[i - 1] = data[i]
        end
        gl.glBufferData(t, #data * ffi.sizeof("float"), arr, usage)
    elseif t == Live2DGLWrapper.ELEMENT_ARRAY_BUFFER then
        local arr = ffi.new("uint16_t[?]", #data)
        for i = 1, #data do
            arr[i - 1] = data[i]
        end
        gl.glBufferData(t, #data * ffi.sizeof("uint16_t"), arr, usage)
    end
end

function Live2DGLWrapper.enableVertexAttribArray(vao)
    gl.glEnableVertexAttribArray(vao)
end

function Live2DGLWrapper.vertexAttribPointer(idx, size, dtype, normalized, stride, ptr)
    gl.glVertexAttribPointer(idx, size, dtype, normalized, stride, ptr)
end

function Live2DGLWrapper.activeTexture(t)
    gl.glActiveTexture(t)
end

function Live2DGLWrapper.uniform1i(loc, v)
    gl.glUniform1i(loc, v)
end

function Live2DGLWrapper.uniformMatrix4fv(loc, transpose, value)
    local arr = ffi.new("float[16]")
    for i = 1, 16 do
        arr[i - 1] = value[i] or 0
    end
    gl.glUniformMatrix4fv(loc, 1, transpose and 1 or 0, arr)
end

function Live2DGLWrapper.uniform4f(loc, a, b, c, d)
    gl.glUniform4f(loc, a, b, c, d)
end

function Live2DGLWrapper.blendEquationSeparate(a, b)
    gl.glBlendEquationSeparate(a, b)
end

function Live2DGLWrapper.blendFuncSeparate(a, b, c, d)
    gl.glBlendFuncSeparate(a, b, c, d)
end

function Live2DGLWrapper.drawElements(t, size, dt, data)
    gl.glDrawElements(t, size, dt, data)
end

function Live2DGLWrapper.getParameter(t)
    local v = ffi.new("GLint[1]")
    gl.glGetIntegerv(t, v)
    return v[0]
end

function Live2DGLWrapper.viewport(a, b, c, d)
    gl.glViewport(a, b, c, d)
end

function Live2DGLWrapper.clearColor(a, b, c, d)
    gl.glClearColor(a, b, c, d)
end

function Live2DGLWrapper.clear(t)
    gl.glClear(t)
end

function Live2DGLWrapper.deleteFramebuffer(t)
    local fb = ffi.new("GLuint[1]", t)
    gl.glDeleteFramebuffers(1, fb)
end

function Live2DGLWrapper.deleteShader(s)
    gl.glDeleteShader(s)
end

function Live2DGLWrapper.deleteTexture(t)
    local tex = ffi.new("GLuint[1]", t)
    gl.glDeleteTextures(1, tex)
end

function Live2DGLWrapper.deleteBuffer(b)
    local buf = ffi.new("GLuint[1]", b)
    gl.glDeleteBuffers(1, buf)
end

function Live2DGLWrapper.deleteProgram(p)
    gl.glDeleteProgram(p)
end

function Live2DGLWrapper.deleteRenderbuffer(r)
    local rb = ffi.new("GLuint[1]", r)
    gl.glDeleteRenderbuffers(1, rb)
end

function Live2DGLWrapper.generateMipmap(t)
    gl.glGenerateMipmap(t)
end

function Live2DGLWrapper.genTextures(n)
    local tex = ffi.new("GLuint[?]", n)
    gl.glGenTextures(n, tex)
    return tex[0]
end

return Live2DGLWrapper
