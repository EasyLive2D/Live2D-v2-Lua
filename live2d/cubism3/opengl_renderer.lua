-- OpenGL renderer for Cubism 3 drawable meshes
-- Ported from Mocari src/render/ (wgpu backend adapted to OpenGL)

local ffi = require("ffi")
local draw_order_from_raw = require("live2d.cubism3.core.art_mesh").draw_order_from_raw
local drawable = require("live2d.cubism3.moc3.drawable")
local image_loader = require("live2d.image_loader")

local GL_STENCIL_TEST = 0x0B90
local GL_ALPHA_TEST = 0x0BC0
local GL_STENCIL_BUFFER_BIT = 0x00000400
local GL_ALWAYS = 0x0207
local GL_EQUAL = 0x0202
local GL_NOTEQUAL = 0x0205
local GL_KEEP = 0x1E00
local GL_REPLACE = 0x1E01
local GL_GREATER = 0x0204

-- Vertex shader: position + uv + opacity + multiply + screen colors
local VERTEX_SHADER = [[
#version 120
attribute vec2 a_position;
attribute vec2 a_uv;
attribute float a_opacity;
attribute vec3 a_multiply;
attribute vec3 a_screen;

varying vec2 v_uv;
varying float v_opacity;
varying vec3 v_multiply;
varying vec3 v_screen;

uniform mat4 u_projection;

void main() {
    gl_Position = u_projection * vec4(a_position, 0.0, 1.0);
    v_uv = a_uv;
    v_opacity = a_opacity;
    v_multiply = a_multiply;
    v_screen = a_screen;
}
]]

local FRAGMENT_SHADER = [[
#version 120
varying vec2 v_uv;
varying float v_opacity;
varying vec3 v_multiply;
varying vec3 v_screen;

uniform sampler2D u_texture;

void main() {
    vec4 tex = texture2D(u_texture, v_uv);
    // Multiply blend: output = tex * multiply
    // Screen blend: output = 1 - (1-tex)*(1-screen) = tex + screen - tex*screen
    vec3 blended = tex.rgb * v_multiply;
    // Apply screen color (simplified screen blend)
    blended = blended + v_screen * (1.0 - tex.rgb);
    gl_FragColor = vec4(blended, tex.a * v_opacity);
}
]]

local OpenGLRenderer = {}
OpenGLRenderer.__index = OpenGLRenderer

local sort_meshes
local function compare_draw_order(a, b)
    local meshA = sort_meshes[a + 1]
    local meshB = sort_meshes[b + 1]
    local drawOrderA = draw_order_from_raw(meshA.draw_order)
    local drawOrderB = draw_order_from_raw(meshB.draw_order)
    if drawOrderA ~= drawOrderB then return drawOrderA < drawOrderB end
    if meshA.render_order ~= meshB.render_order then return meshA.render_order < meshB.render_order end
    return a < b
end

function OpenGLRenderer.new(gl)
    local self = setmetatable({}, OpenGLRenderer)
    self.gl = gl
    self.shader = nil
    self.textures = {}  -- texture_id -> GL texture object
    self.vao = nil
    self.vbo = nil
    self.ibo = nil
    self.draw_order_indices = {}
    self.vertex_data = nil
    self.vertex_capacity = 0
    self.index_data = nil
    self.index_capacity = 0
    self:init_shader()
    return self
end

function OpenGLRenderer:init_shader()
    local gl = self.gl

    -- Compile vertex shader
    local vertexShader = gl.glCreateShader(0x8B31) -- GL_VERTEX_SHADER
    local src = ffi.new("const char*[1]", ffi.new("const char*", VERTEX_SHADER))
    local len = ffi.new("int[1]", #VERTEX_SHADER)
    gl.glShaderSource(vertexShader, 1, src, len)
    gl.glCompileShader(vertexShader)

    local status = ffi.new("int[1]", 0)
    gl.glGetShaderiv(vertexShader, 0x8B81, status) -- GL_COMPILE_STATUS
    if status[0] == 0 then
        local log = ffi.new("char[1024]")
        gl.glGetShaderInfoLog(vertexShader, 1024, nil, log)
        error("Vertex shader compile failed: " .. ffi.string(log))
    end

    -- Compile fragment shader
    local fragmentShader = gl.glCreateShader(0x8B30) -- GL_FRAGMENT_SHADER
    src = ffi.new("const char*[1]", ffi.new("const char*", FRAGMENT_SHADER))
    len[0] = #FRAGMENT_SHADER
    gl.glShaderSource(fragmentShader, 1, src, len)
    gl.glCompileShader(fragmentShader)

    gl.glGetShaderiv(fragmentShader, 0x8B81, status)
    if status[0] == 0 then
        local log = ffi.new("char[1024]")
        gl.glGetShaderInfoLog(fragmentShader, 1024, nil, log)
        error("Fragment shader compile failed: " .. ffi.string(log))
    end

    -- Link program
    local prog = gl.glCreateProgram()
    gl.glAttachShader(prog, vertexShader)
    gl.glAttachShader(prog, fragmentShader)
    gl.glLinkProgram(prog)

    gl.glGetProgramiv(prog, 0x8B82, status) -- GL_LINK_STATUS
    if status[0] == 0 then
        local log = ffi.new("char[1024]")
        gl.glGetProgramInfoLog(prog, 1024, nil, log)
        error("Shader link failed: " .. ffi.string(log))
    end

    gl.glDeleteShader(vertexShader)
    gl.glDeleteShader(fragmentShader)

    self.shader = prog
    self.u_projection = gl.glGetUniformLocation(prog, "u_projection")
    self.u_texture = gl.glGetUniformLocation(prog, "u_texture")
    self.a_position = gl.glGetAttribLocation(prog, "a_position")
    self.a_uv = gl.glGetAttribLocation(prog, "a_uv")
    self.a_opacity = gl.glGetAttribLocation(prog, "a_opacity")
    self.a_multiply = gl.glGetAttribLocation(prog, "a_multiply")
    self.a_screen = gl.glGetAttribLocation(prog, "a_screen")

    -- Create VAO and VBO
    local vao = ffi.new("GLuint[1]")
    local vbo = ffi.new("GLuint[1]")
    local ibo = ffi.new("GLuint[1]")

    -- Only create VAO if the function is available (GL 3.0+)
    local has_vao = pcall(function()
        if gl.glGenVertexArrays then
            gl.glGenVertexArrays(1, vao)
        end
    end)

    if vao[0] and vao[0] ~= 0 then
        self.vao = vao[0]
    end

    gl.glGenBuffers(1, vbo)
    gl.glGenBuffers(1, ibo)
    self.vbo = vbo[0]
    self.ibo = ibo[0]
end

function OpenGLRenderer:load_texture(texture_path)
    local gl = self.gl

    local width, height, data = image_loader.loadImage(texture_path)
    if not width or not data then
        error("Failed to load texture: " .. texture_path)
    end

    local tex_id = ffi.new("GLuint[1]")
    gl.glGenTextures(1, tex_id)

    gl.glBindTexture(0x0DE1, tex_id[0]) -- GL_TEXTURE_2D
    gl.glTexParameteri(0x0DE1, 0x2801, 0x2601) -- GL_MIN_FILTER, GL_LINEAR
    gl.glTexParameteri(0x0DE1, 0x2800, 0x2601) -- GL_MAG_FILTER, GL_LINEAR
    gl.glTexParameteri(0x0DE1, 0x2802, 0x812F) -- GL_WRAP_S, GL_CLAMP_TO_EDGE
    gl.glTexParameteri(0x0DE1, 0x2803, 0x812F) -- GL_WRAP_T, GL_CLAMP_TO_EDGE

    gl.glTexImage2D(0x0DE1, 0, 0x1908, width, height, 0, 0x1908, 0x1401, data)

    self.textures[texture_path] = tex_id[0]
    return tex_id[0]
end

function OpenGLRenderer:ensure_texture(texture_path)
    if self.textures[texture_path] then
        return self.textures[texture_path]
    end
    return self:load_texture(texture_path)
end

function OpenGLRenderer:render_meshes(meshes, textures, projection)
    local gl = self.gl

    gl.glUseProgram(self.shader)

    -- Calculate draw order
    local draw_order_indices = self.draw_order_indices
    if not draw_order_indices then
        draw_order_indices = {}
        self.draw_order_indices = draw_order_indices
    end
    local old_draw_order_count = #draw_order_indices
    for i = 1, #meshes do
        draw_order_indices[i] = i - 1
    end
    for i = #meshes + 1, old_draw_order_count do
        draw_order_indices[i] = nil
    end
    sort_meshes = meshes
    table.sort(draw_order_indices, compare_draw_order)
    sort_meshes = nil

    -- Upload and draw each mesh
    for _, idx in ipairs(draw_order_indices) do
        local mesh = meshes[idx + 1]
        if mesh and mesh.opacity > 0.001 then
            if #mesh.masks > 0 and gl.glStencilFunc and gl.glStencilOp and gl.glStencilMask then
                self:draw_clipped_mesh(mesh, meshes, textures, projection)
            else
                self:draw_mesh(mesh, textures, projection)
            end
        end
    end
end

function OpenGLRenderer:draw_clipped_mesh(mesh, meshes, textures, projection)
    local gl = self.gl

    gl.glEnable(GL_STENCIL_TEST)
    if gl.glAlphaFunc then
        gl.glEnable(GL_ALPHA_TEST)
        gl.glAlphaFunc(GL_GREATER, 0.01)
    end

    gl.glClear(GL_STENCIL_BUFFER_BIT)
    gl.glColorMask(0, 0, 0, 0)
    gl.glStencilMask(0xFF)
    gl.glStencilFunc(GL_ALWAYS, 1, 0xFF)
    gl.glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)

    for _, mask_idx in ipairs(mesh.masks) do
        local mask_mesh = meshes[mask_idx + 1]
        if mask_mesh and mask_mesh.opacity > 0.001 then
            self:draw_mesh(mask_mesh, textures, projection)
        end
    end

    gl.glColorMask(1, 1, 1, 1)
    gl.glStencilMask(0x00)
    local stencil_func = drawable.is_inverted_mask(mesh.drawable_flags) and GL_NOTEQUAL or GL_EQUAL
    gl.glStencilFunc(stencil_func, 1, 0xFF)
    gl.glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP)
    self:draw_mesh(mesh, textures, projection)

    gl.glStencilMask(0xFF)
    gl.glDisable(GL_STENCIL_TEST)
    if gl.glAlphaFunc then
        gl.glDisable(GL_ALPHA_TEST)
    end
end

function OpenGLRenderer:draw_mesh(mesh, textures, projection)
    local gl = self.gl
    local vertices = mesh.vertices
    local indices = mesh.indices
    if #vertices == 0 or #indices == 0 then
        return
    end

    -- Build vertex data: position(2) + uv(2) + opacity(1) + multiply(3) + screen(3) = 11 floats
    local vertex_count = #vertices
    local index_count = #indices
    local vertex_float_count = vertex_count * 11
    if (self.vertex_capacity or 0) < vertex_float_count then
        self.vertex_data = ffi.new("float[?]", vertex_float_count)
        self.vertex_capacity = vertex_float_count
    end
    local vertex_data = self.vertex_data
    for i = 1, #vertices do
        local vertex = vertices[i]
        local off = (i - 1) * 11
        vertex_data[off + 0] = vertex.position[1]
        vertex_data[off + 1] = vertex.position[2]
        vertex_data[off + 2] = vertex.uv[1]
        vertex_data[off + 3] = vertex.uv[2]
        vertex_data[off + 4] = mesh.opacity
        vertex_data[off + 5] = mesh.multiply_color[1]
        vertex_data[off + 6] = mesh.multiply_color[2]
        vertex_data[off + 7] = mesh.multiply_color[3]
        vertex_data[off + 8] = mesh.screen_color[1]
        vertex_data[off + 9] = mesh.screen_color[2]
        vertex_data[off + 10] = mesh.screen_color[3]
    end

    if (self.index_capacity or 0) < index_count then
        self.index_data = ffi.new("uint16_t[?]", index_count)
        self.index_capacity = index_count
    end
    local index_data = self.index_data
    for i = 1, index_count do
        index_data[i - 1] = indices[i]
    end

    -- Get texture
    local tex_idx = mesh.texture_index
    local tex_path
    if textures then
        tex_path = textures[tex_idx + 1]
    end
    local tex_id = 0
    if tex_path then
        tex_id = self:ensure_texture(tex_path)
    end

    -- Set blend mode
    local blend = drawable.blend_mode_from_flags(mesh.drawable_flags)
    if blend == "normal" then
        gl.glBlendFunc(0x0302, 0x0303) -- GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA
        gl.glBlendEquationSeparate(0x8006, 0x8006) -- GL_FUNC_ADD
    elseif blend == "additive" then
        gl.glBlendFunc(0x0302, 0x0001) -- GL_SRC_ALPHA, GL_ONE
        gl.glBlendEquationSeparate(0x8006, 0x8006) -- GL_FUNC_ADD
    elseif blend == "multiplicative" then
        gl.glBlendFunc(0x0300, 0x0302) -- GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA
        gl.glBlendEquationSeparate(0x8006, 0x8006) -- GL_FUNC_ADD
    end

    -- Upload geometry
    gl.glBindBuffer(0x8892, self.vbo) -- GL_ARRAY_BUFFER
    gl.glBufferData(0x8892, vertex_float_count * 4, vertex_data, 0x88E4) -- GL_DYNAMIC_DRAW

    gl.glBindBuffer(0x8893, self.ibo) -- GL_ELEMENT_ARRAY_BUFFER
    gl.glBufferData(0x8893, index_count * 2, index_data, 0x88E4) -- GL_DYNAMIC_DRAW

    -- Set vertex attributes
    local stride = 11 * 4 -- 11 floats * 4 bytes

    if self.a_position == nil then
        self.a_position = gl.glGetAttribLocation(self.shader, "a_position")
        self.a_uv = gl.glGetAttribLocation(self.shader, "a_uv")
        self.a_opacity = gl.glGetAttribLocation(self.shader, "a_opacity")
        self.a_multiply = gl.glGetAttribLocation(self.shader, "a_multiply")
        self.a_screen = gl.glGetAttribLocation(self.shader, "a_screen")
    end

    local a_pos = self.a_position
    local a_uv = self.a_uv
    local a_opacity = self.a_opacity
    local a_multiply = self.a_multiply
    local a_screen = self.a_screen

    if a_pos >= 0 then
        gl.glEnableVertexAttribArray(a_pos)
        gl.glVertexAttribPointer(a_pos, 2, 0x1406, 0, stride, ffi.cast("void*", ffi.cast("intptr_t", 0)))
    end
    if a_uv >= 0 then
        gl.glEnableVertexAttribArray(a_uv)
        gl.glVertexAttribPointer(a_uv, 2, 0x1406, 0, stride, ffi.cast("void*", ffi.cast("intptr_t", 8)))
    end
    if a_opacity >= 0 then
        gl.glEnableVertexAttribArray(a_opacity)
        gl.glVertexAttribPointer(a_opacity, 1, 0x1406, 0, stride, ffi.cast("void*", ffi.cast("intptr_t", 16)))
    end
    if a_multiply >= 0 then
        gl.glEnableVertexAttribArray(a_multiply)
        gl.glVertexAttribPointer(a_multiply, 3, 0x1406, 0, stride, ffi.cast("void*", ffi.cast("intptr_t", 20)))
    end
    if a_screen >= 0 then
        gl.glEnableVertexAttribArray(a_screen)
        gl.glVertexAttribPointer(a_screen, 3, 0x1406, 0, stride, ffi.cast("void*", ffi.cast("intptr_t", 32)))
    end

    -- Set projection matrix
    gl.glUniformMatrix4fv(self.u_projection, 1, 0, projection)

    -- Bind texture
    gl.glActiveTexture(0x84C0) -- GL_TEXTURE0
    gl.glBindTexture(0x0DE1, tex_id)
    gl.glUniform1i(self.u_texture, 0)

    -- Draw
    gl.glDrawElements(0x0004, index_count, 0x1403, nil) -- GL_TRIANGLES, GL_UNSIGNED_SHORT

    -- Disable attributes
    if a_pos >= 0 then gl.glDisableVertexAttribArray(a_pos) end
    if a_uv >= 0 then gl.glDisableVertexAttribArray(a_uv) end
    if a_opacity >= 0 then gl.glDisableVertexAttribArray(a_opacity) end
    if a_multiply >= 0 then gl.glDisableVertexAttribArray(a_multiply) end
    if a_screen >= 0 then gl.glDisableVertexAttribArray(a_screen) end
end

function OpenGLRenderer:destroy()
    local gl = self.gl
    if self.shader then
        gl.glDeleteProgram(self.shader)
    end
    if self.vbo then
        gl.glDeleteBuffers(1, ffi.new("GLuint[1]", self.vbo))
    end
    if self.ibo then
        gl.glDeleteBuffers(1, ffi.new("GLuint[1]", self.ibo))
    end
    for _, tex_id in pairs(self.textures) do
        gl.glDeleteTextures(1, ffi.new("GLuint[1]", tex_id))
    end
    self.textures = {}
end

return OpenGLRenderer
