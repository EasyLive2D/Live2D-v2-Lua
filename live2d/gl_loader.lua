-- OpenGL loader using LuaJIT FFI
-- Cross-platform: Windows (opengl32 + wglGetProcAddress) and Linux (libGL + glXGetProcAddress)

local ffi = require("ffi")
local is_win = ffi.os == "Windows"

-- Calling convention: __stdcall on Windows, default (blank) on Linux
local CC = is_win and "__stdcall " or ""

-- GL library name(s)
local gl_lib_names = is_win and {"opengl32"} or {"GL", "GL.so.1", "GL.so"}
local gl_lib
for _, name in ipairs(gl_lib_names) do
    local ok, lib = pcall(ffi.load, name)
    if ok then
        gl_lib = lib
        break
    end
end
if gl_lib == nil then
    error("Cannot load GL library. Tried: " .. table.concat(gl_lib_names, ", "))
end

-- GL 1.1 core cdef (same across platforms)
ffi.cdef[[
    typedef unsigned int GLenum;
    typedef unsigned char GLboolean;
    typedef unsigned int GLbitfield;
    typedef signed char GLbyte;
    typedef short GLshort;
    typedef int GLint;
    typedef int GLsizei;
    typedef unsigned char GLubyte;
    typedef unsigned short GLushort;
    typedef unsigned int GLuint;
    typedef float GLfloat;
    typedef float GLclampf;
    typedef double GLdouble;
    typedef double GLclampd;
    typedef void *GLvoid;
    typedef char GLchar;
    typedef ptrdiff_t GLintptr;
    typedef ptrdiff_t GLsizeiptr;

    // GL 1.1 core
    void glClear(GLbitfield mask);
    void glClearColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
    void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
    void glEnable(GLenum cap);
    void glDisable(GLenum cap);
    void glColorMask(GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha);
    void glFrontFace(GLenum mode);
    void glBindTexture(GLenum target, GLuint texture);
    void glDeleteTextures(GLsizei n, const GLuint *textures);
    void glGetIntegerv(GLenum pname, GLint *data);
    void glGenTextures(GLsizei n, GLuint *textures);
    void glTexParameteri(GLenum target, GLenum pname, GLint param);
    void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
    void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices);
    void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels);
    void glDrawArrays(GLenum mode, GLint first, GLsizei count);
    void glBlendFunc(GLenum sfactor, GLenum dfactor);
]]

-- Platform-specific extension loader declaration
if is_win then
    ffi.cdef[[ void *wglGetProcAddress(const char *name); ]]
else
    ffi.cdef[[ void *glXGetProcAddress(const char *name); ]]
end

-- Extension function pointer typedefs (calling convention varies by platform)
ffi.cdef("typedef void (" .. CC .. "*PFNGLACTIVETEXTUREPROC)(GLenum texture);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLBLENDFUNCSEPARATEPROC)(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLBLENDEQUATIONSEPARATEPROC)(GLenum modeRGB, GLenum modeAlpha);")
ffi.cdef("typedef GLuint (" .. CC .. "*PFNGLCREATESHADERPROC)(GLenum type);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLSHADERSOURCEPROC)(GLuint shader, GLsizei count, const GLchar* const* string, const GLint* length);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLCOMPILESHADERPROC)(GLuint shader);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLGETSHADERIVPROC)(GLuint shader, GLenum pname, GLint *params);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLGETSHADERINFOLOGPROC)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLDELETESHADERPROC)(GLuint shader);")
ffi.cdef("typedef GLuint (" .. CC .. "*PFNGLCREATEPROGRAMPROC)(void);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLATTACHSHADERPROC)(GLuint program, GLuint shader);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLLINKPROGRAMPROC)(GLuint program);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLUSEPROGRAMPROC)(GLuint program);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLGETPROGRAMIVPROC)(GLuint program, GLenum pname, GLint *params);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLGETPROGRAMINFOLOGPROC)(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLDELETEPROGRAMPROC)(GLuint program);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLGENBUFFERSPROC)(GLsizei n, GLuint *buffers);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLDELETEBUFFERSPROC)(GLsizei n, const GLuint *buffers);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLBINDBUFFERPROC)(GLenum target, GLuint buffer);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLBUFFERDATAPROC)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLENABLEVERTEXATTRIBARRAYPROC)(GLuint index);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLVERTEXATTRIBPOINTERPROC)(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLUNIFORM1IPROC)(GLint location, GLint v0);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLUNIFORM4FPROC)(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLUNIFORMMATRIX4FVPROC)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);")
ffi.cdef("typedef GLint (" .. CC .. "*PFNGLGETATTRIBLOCATIONPROC)(GLuint program, const GLchar *name);")
ffi.cdef("typedef GLint (" .. CC .. "*PFNGLGETUNIFORMLOCATIONPROC)(GLuint program, const GLchar *name);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLGENFRAMEBUFFERSPROC)(GLsizei n, GLuint *framebuffers);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLBINDFRAMEBUFFERPROC)(GLenum target, GLuint framebuffer);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLFRAMEBUFFERTEXTURE2DPROC)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLFRAMEBUFFERRENDERBUFFERPROC)(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLGENRENDERBUFFERSPROC)(GLsizei n, GLuint *renderbuffers);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLBINDRENDERBUFFERPROC)(GLenum target, GLuint renderbuffer);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLRENDERBUFFERSTORAGEPROC)(GLenum target, GLenum internalformat, GLsizei width, GLsizei height);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLDELETEFRAMEBUFFERSPROC)(GLsizei n, const GLuint *framebuffers);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLDELETERENDERBUFFERSPROC)(GLsizei n, const GLuint *renderbuffers);")
ffi.cdef("typedef void (" .. CC .. "*PFNGLGENERATEMIPMAPPROC)(GLenum target);")

local gl = setmetatable({}, { __index = gl_lib })
local extensions_loaded = false

local function loadGL(name, cast_type)
    local ptr
    if is_win then
        ptr = gl_lib.wglGetProcAddress(name)
    else
        ptr = gl_lib.glXGetProcAddress(name)
    end
    if ptr == nil then
        error("Failed to load GL function: " .. name)
    end
    return ffi.cast(cast_type, ptr)
end

function gl.ensureExtensions()
    if extensions_loaded then return end
    gl.glActiveTexture = loadGL("glActiveTexture", "PFNGLACTIVETEXTUREPROC")
    gl.glBlendFuncSeparate = loadGL("glBlendFuncSeparate", "PFNGLBLENDFUNCSEPARATEPROC")
    gl.glBlendEquationSeparate = loadGL("glBlendEquationSeparate", "PFNGLBLENDEQUATIONSEPARATEPROC")
    gl.glCreateShader = loadGL("glCreateShader", "PFNGLCREATESHADERPROC")
    gl.glShaderSource = loadGL("glShaderSource", "PFNGLSHADERSOURCEPROC")
    gl.glCompileShader = loadGL("glCompileShader", "PFNGLCOMPILESHADERPROC")
    gl.glGetShaderiv = loadGL("glGetShaderiv", "PFNGLGETSHADERIVPROC")
    gl.glGetShaderInfoLog = loadGL("glGetShaderInfoLog", "PFNGLGETSHADERINFOLOGPROC")
    gl.glDeleteShader = loadGL("glDeleteShader", "PFNGLDELETESHADERPROC")
    gl.glCreateProgram = loadGL("glCreateProgram", "PFNGLCREATEPROGRAMPROC")
    gl.glAttachShader = loadGL("glAttachShader", "PFNGLATTACHSHADERPROC")
    gl.glLinkProgram = loadGL("glLinkProgram", "PFNGLLINKPROGRAMPROC")
    gl.glUseProgram = loadGL("glUseProgram", "PFNGLUSEPROGRAMPROC")
    gl.glGetProgramiv = loadGL("glGetProgramiv", "PFNGLGETPROGRAMIVPROC")
    gl.glGetProgramInfoLog = loadGL("glGetProgramInfoLog", "PFNGLGETPROGRAMINFOLOGPROC")
    gl.glDeleteProgram = loadGL("glDeleteProgram", "PFNGLDELETEPROGRAMPROC")
    gl.glGenBuffers = loadGL("glGenBuffers", "PFNGLGENBUFFERSPROC")
    gl.glDeleteBuffers = loadGL("glDeleteBuffers", "PFNGLDELETEBUFFERSPROC")
    gl.glBindBuffer = loadGL("glBindBuffer", "PFNGLBINDBUFFERPROC")
    gl.glBufferData = loadGL("glBufferData", "PFNGLBUFFERDATAPROC")
    gl.glEnableVertexAttribArray = loadGL("glEnableVertexAttribArray", "PFNGLENABLEVERTEXATTRIBARRAYPROC")
    gl.glVertexAttribPointer = loadGL("glVertexAttribPointer", "PFNGLVERTEXATTRIBPOINTERPROC")
    gl.glUniform1i = loadGL("glUniform1i", "PFNGLUNIFORM1IPROC")
    gl.glUniform4f = loadGL("glUniform4f", "PFNGLUNIFORM4FPROC")
    gl.glUniformMatrix4fv = loadGL("glUniformMatrix4fv", "PFNGLUNIFORMMATRIX4FVPROC")
    gl.glGetAttribLocation = loadGL("glGetAttribLocation", "PFNGLGETATTRIBLOCATIONPROC")
    gl.glGetUniformLocation = loadGL("glGetUniformLocation", "PFNGLGETUNIFORMLOCATIONPROC")
    gl.glGenFramebuffers = loadGL("glGenFramebuffers", "PFNGLGENFRAMEBUFFERSPROC")
    gl.glBindFramebuffer = loadGL("glBindFramebuffer", "PFNGLBINDFRAMEBUFFERPROC")
    gl.glFramebufferTexture2D = loadGL("glFramebufferTexture2D", "PFNGLFRAMEBUFFERTEXTURE2DPROC")
    gl.glFramebufferRenderbuffer = loadGL("glFramebufferRenderbuffer", "PFNGLFRAMEBUFFERRENDERBUFFERPROC")
    gl.glGenRenderbuffers = loadGL("glGenRenderbuffers", "PFNGLGENRENDERBUFFERSPROC")
    gl.glBindRenderbuffer = loadGL("glBindRenderbuffer", "PFNGLBINDRENDERBUFFERPROC")
    gl.glRenderbufferStorage = loadGL("glRenderbufferStorage", "PFNGLRENDERBUFFERSTORAGEPROC")
    gl.glDeleteFramebuffers = loadGL("glDeleteFramebuffers", "PFNGLDELETEFRAMEBUFFERSPROC")
    gl.glDeleteRenderbuffers = loadGL("glDeleteRenderbuffers", "PFNGLDELETERENDERBUFFERSPROC")
    gl.glGenerateMipmap = loadGL("glGenerateMipmap", "PFNGLGENERATEMIPMAPPROC")
    extensions_loaded = true
end

return gl
