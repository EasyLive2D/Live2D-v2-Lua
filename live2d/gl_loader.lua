-- OpenGL loader using LuaJIT FFI
-- GL 1.1 core from opengl32.dll, GL 1.2+ via wglGetProcAddress

local ffi = require("ffi")

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
    
    // GL 1.1 core - available in opengl32.dll
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
    void *wglGetProcAddress(const char *name);
]]

local opengl = ffi.load("opengl32")
local wgl = ffi.load("opengl32")

ffi.cdef[[
    typedef void (__stdcall *PFNGLACTIVETEXTUREPROC)(GLenum texture);
    typedef void (__stdcall *PFNGLBLENDFUNCSEPARATEPROC)(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha);
    typedef void (__stdcall *PFNGLBLENDEQUATIONSEPARATEPROC)(GLenum modeRGB, GLenum modeAlpha);
    typedef GLuint (__stdcall *PFNGLCREATESHADERPROC)(GLenum type);
    typedef void (__stdcall *PFNGLSHADERSOURCEPROC)(GLuint shader, GLsizei count, const GLchar* const* string, const GLint* length);
    typedef void (__stdcall *PFNGLCOMPILESHADERPROC)(GLuint shader);
    typedef void (__stdcall *PFNGLGETSHADERIVPROC)(GLuint shader, GLenum pname, GLint *params);
    typedef void (__stdcall *PFNGLGETSHADERINFOLOGPROC)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
    typedef void (__stdcall *PFNGLDELETESHADERPROC)(GLuint shader);
    typedef GLuint (__stdcall *PFNGLCREATEPROGRAMPROC)(void);
    typedef void (__stdcall *PFNGLATTACHSHADERPROC)(GLuint program, GLuint shader);
    typedef void (__stdcall *PFNGLLINKPROGRAMPROC)(GLuint program);
    typedef void (__stdcall *PFNGLUSEPROGRAMPROC)(GLuint program);
    typedef void (__stdcall *PFNGLGETPROGRAMIVPROC)(GLuint program, GLenum pname, GLint *params);
    typedef void (__stdcall *PFNGLGETPROGRAMINFOLOGPROC)(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
    typedef void (__stdcall *PFNGLDELETEPROGRAMPROC)(GLuint program);
    typedef void (__stdcall *PFNGLGENBUFFERSPROC)(GLsizei n, GLuint *buffers);
    typedef void (__stdcall *PFNGLDELETEBUFFERSPROC)(GLsizei n, const GLuint *buffers);
    typedef void (__stdcall *PFNGLBINDBUFFERPROC)(GLenum target, GLuint buffer);
    typedef void (__stdcall *PFNGLBUFFERDATAPROC)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
    typedef void (__stdcall *PFNGLENABLEVERTEXATTRIBARRAYPROC)(GLuint index);
    typedef void (__stdcall *PFNGLVERTEXATTRIBPOINTERPROC)(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer);
    typedef void (__stdcall *PFNGLUNIFORM1IPROC)(GLint location, GLint v0);
    typedef void (__stdcall *PFNGLUNIFORM4FPROC)(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3);
    typedef void (__stdcall *PFNGLUNIFORMMATRIX4FVPROC)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
    typedef GLint (__stdcall *PFNGLGETATTRIBLOCATIONPROC)(GLuint program, const GLchar *name);
    typedef GLint (__stdcall *PFNGLGETUNIFORMLOCATIONPROC)(GLuint program, const GLchar *name);
    typedef void (__stdcall *PFNGLGENFRAMEBUFFERSPROC)(GLsizei n, GLuint *framebuffers);
    typedef void (__stdcall *PFNGLBINDFRAMEBUFFERPROC)(GLenum target, GLuint framebuffer);
    typedef void (__stdcall *PFNGLFRAMEBUFFERTEXTURE2DPROC)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
    typedef void (__stdcall *PFNGLFRAMEBUFFERRENDERBUFFERPROC)(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer);
    typedef void (__stdcall *PFNGLGENRENDERBUFFERSPROC)(GLsizei n, GLuint *renderbuffers);
    typedef void (__stdcall *PFNGLBINDRENDERBUFFERPROC)(GLenum target, GLuint renderbuffer);
    typedef void (__stdcall *PFNGLRENDERBUFFERSTORAGEPROC)(GLenum target, GLenum internalformat, GLsizei width, GLsizei height);
    typedef void (__stdcall *PFNGLDELETEFRAMEBUFFERSPROC)(GLsizei n, const GLuint *framebuffers);
    typedef void (__stdcall *PFNGLDELETERENDERBUFFERSPROC)(GLsizei n, const GLuint *renderbuffers);
    typedef void (__stdcall *PFNGLGENERATEMIPMAPPROC)(GLenum target);
]]

local gl = setmetatable({}, { __index = opengl })
local extensions_loaded = false

local function loadGL(name, cast_type)
    local ptr = wgl.wglGetProcAddress(name)
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
