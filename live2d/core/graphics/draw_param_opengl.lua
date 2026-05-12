-- DrawParamOpenGL - Full OpenGL renderer with shaders, VBOs, FBO clipping
-- Backed by real OpenGL FFI calls

local DrawParam = require("live2d.core.graphics.draw_param")
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")
local Live2D = require("live2d.core.live2d")
local Mesh = require("live2d.core.draw.mesh")

local FrameBufferObject = {}
FrameBufferObject.__index = FrameBufferObject

function FrameBufferObject.new(fbo, rbo, tex)
    local self = setmetatable({}, FrameBufferObject)
    self.framebuffer = fbo
    self.renderbuffer = rbo
    self.texture = tex
    return self
end

local DrawParamOpenGL = setmetatable({}, { __index = DrawParam })
DrawParamOpenGL.__index = DrawParamOpenGL

function DrawParamOpenGL.new()
    local self = setmetatable(DrawParam.new(), DrawParamOpenGL)
    self.framebufferObject = nil
    self.shaderProgram = nil
    self.shaderProgramOff = nil
    self.textures = {}
    self.transform = nil
    self.gl = Live2DGLWrapper.new()
    self.firstDraw = true
    self.anisotropyExt = nil
    self.maxAnisotropy = 0
    self.uvbo = nil
    self.vbo = nil
    self.ebo = nil
    self.vertShader = nil
    self.fragShader = nil
    self.vertShaderOff = nil
    self.fragShaderOff = nil
    -- Shader uniform/attribute locations
    self.a_position_Loc = nil
    self.a_texCoord_Loc = nil
    self.u_matrix_Loc = nil
    self.s_texture0_Loc = nil
    self.u_channelFlag = nil
    self.u_baseColor_Loc = nil
    self.u_maskFlag_Loc = nil
    self.u_screenColor_Loc = nil
    self.u_multiplyColor_Loc = nil
    self.a_position_Loc_Off = nil
    self.a_texCoord_Loc_Off = nil
    self.u_matrix_Loc_Off = nil
    self.u_clipMatrix_Loc_Off = nil
    self.s_texture0_Loc_Off = nil
    self.s_texture1_Loc_Off = nil
    self.u_channelFlag_Loc_Off = nil
    self.u_baseColor_Loc_Off = nil
    self.u_screenColor_Loc_Off = nil
    self.u_multiplyColor_Loc_Off = nil
    return self
end

function DrawParamOpenGL:getGL()
    return self.gl
end

function DrawParamOpenGL:setGL(aH)
    self.gl = aH
end

function DrawParamOpenGL:resize(ww, wh)
    self.gl:resize(ww, wh)
end

function DrawParamOpenGL:setTransform(aH)
    self.transform = aH
end

function DrawParamOpenGL:setupDraw()
    if self.firstDraw then
        self:initShader()
        self.firstDraw = false
    end
    Live2DGLWrapper.disable(Live2DGLWrapper.SCISSOR_TEST)
    Live2DGLWrapper.disable(Live2DGLWrapper.STENCIL_TEST)
    Live2DGLWrapper.disable(Live2DGLWrapper.DEPTH_TEST)
    Live2DGLWrapper.frontFace(Live2DGLWrapper.CW)
    Live2DGLWrapper.enable(Live2DGLWrapper.BLEND)
    Live2DGLWrapper.colorMask(1, 1, 1, 1)
    Live2DGLWrapper.bindBuffer(Live2DGLWrapper.ARRAY_BUFFER, 0)
    Live2DGLWrapper.bindBuffer(Live2DGLWrapper.ELEMENT_ARRAY_BUFFER, 0)
end

-- Helper functions: create and bind VBO/EBO
local function bindOrCreateVBO(vbo, data)
    if vbo == nil then
        vbo = Live2DGLWrapper.createBuffer()
    end
    Live2DGLWrapper.bindBuffer(Live2DGLWrapper.ARRAY_BUFFER, vbo)
    Live2DGLWrapper.bufferData(Live2DGLWrapper.ARRAY_BUFFER, data, Live2DGLWrapper.DYNAMIC_DRAW)
    return vbo
end

local function bindOrCreateEBO(ebo, data)
    if ebo == nil then
        ebo = Live2DGLWrapper.createBuffer()
    end
    Live2DGLWrapper.bindBuffer(Live2DGLWrapper.ELEMENT_ARRAY_BUFFER, ebo)
    Live2DGLWrapper.bufferData(Live2DGLWrapper.ELEMENT_ARRAY_BUFFER, data, Live2DGLWrapper.DYNAMIC_DRAW)
    return ebo
end

function DrawParamOpenGL:drawTexture(texNo, screenColor, indexArray, vertexArray, uvArray, opacity, comp, multiplyColor)
    if opacity < 0.01 and self.clipBufPre_clipContextMask == nil then
        return
    end

    local a_w = self.baseRed * opacity
    local a2 = self.baseGreen * opacity
    local a5 = self.baseBlue * opacity
    local a7 = self.baseAlpha * opacity

    if self.clipBufPre_clipContextMask ~= nil then
        -- Mask rendering
        Live2DGLWrapper.frontFace(Live2DGLWrapper.CCW)
        Live2DGLWrapper.useProgram(self.shaderProgram)
        self.vbo = bindOrCreateVBO(self.vbo, vertexArray)
        self.ebo = bindOrCreateEBO(self.ebo, indexArray)
        Live2DGLWrapper.vertexAttribPointer(self.a_position_Loc, 2, Live2DGLWrapper.FLOAT, false, 0, nil)
        Live2DGLWrapper.enableVertexAttribArray(self.a_position_Loc)
        self.uvbo = bindOrCreateVBO(self.uvbo, uvArray)
        Live2DGLWrapper.activeTexture(Live2DGLWrapper.TEXTURE1)
        Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, self.textures[texNo + 1] or 0)
        Live2DGLWrapper.uniform1i(self.s_texture0_Loc, 1)
        Live2DGLWrapper.vertexAttribPointer(self.a_texCoord_Loc, 2, Live2DGLWrapper.FLOAT, false, 0, nil)
        Live2DGLWrapper.enableVertexAttribArray(self.a_texCoord_Loc)
        Live2DGLWrapper.uniformMatrix4fv(self.u_matrix_Loc, false, self:getClipBufPre_clipContextMask().matrixForMask)
        local aY = self:getClipBufPre_clipContextMask().layoutChannelNo
        local a4 = self:getChannelFlagAsColor(aY)
        Live2DGLWrapper.uniform4f(self.u_channelFlag, a4.r, a4.g, a4.b, a4.a)
        local aI = self:getClipBufPre_clipContextMask().layoutBounds
        Live2DGLWrapper.uniform4f(self.u_baseColor_Loc, aI.x * 2.0 - 1.0, aI.y * 2.0 - 1.0,
                                   aI:getRight() * 2.0 - 1.0, aI:getBottom() * 2.0 - 1.0)
        Live2DGLWrapper.uniform1i(self.u_maskFlag_Loc, 1)
        Live2DGLWrapper.uniform4f(self.u_screenColor_Loc, screenColor[1] or 0, screenColor[2] or 0, screenColor[3] or 0, screenColor[4] or 0)
        Live2DGLWrapper.uniform4f(self.u_multiplyColor_Loc, multiplyColor[1] or 1, multiplyColor[2] or 1, multiplyColor[3] or 1, multiplyColor[4] or 0)
    elseif self.clipBufPre_clipContextDraw ~= nil then
        -- Draw with clipping
        Live2DGLWrapper.useProgram(self.shaderProgramOff)
        self.vbo = bindOrCreateVBO(self.vbo, vertexArray)
        self.ebo = bindOrCreateEBO(self.ebo, indexArray)
        Live2DGLWrapper.enableVertexAttribArray(self.a_position_Loc_Off)
        Live2DGLWrapper.vertexAttribPointer(self.a_position_Loc_Off, 2, Live2DGLWrapper.FLOAT, false, 0, nil)
        self.uvbo = bindOrCreateVBO(self.uvbo, uvArray)
        Live2DGLWrapper.activeTexture(Live2DGLWrapper.TEXTURE1)
        Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, self.textures[texNo + 1] or 0)
        Live2DGLWrapper.uniform1i(self.s_texture0_Loc_Off, 1)
        Live2DGLWrapper.enableVertexAttribArray(self.a_texCoord_Loc_Off)
        Live2DGLWrapper.vertexAttribPointer(self.a_texCoord_Loc_Off, 2, Live2DGLWrapper.FLOAT, false, 0, nil)
        Live2DGLWrapper.uniformMatrix4fv(self.u_clipMatrix_Loc_Off, false, self:getClipBufPre_clipContextDraw().matrixForDraw)
        Live2DGLWrapper.uniformMatrix4fv(self.u_matrix_Loc_Off, false, self.matrix4x4)
        Live2DGLWrapper.activeTexture(Live2DGLWrapper.TEXTURE2)
        if self.framebufferObject then
            Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, self.framebufferObject.texture)
        end
        Live2DGLWrapper.uniform1i(self.s_texture1_Loc_Off, 2)
        local aY = self:getClipBufPre_clipContextDraw().layoutChannelNo
        local a4 = self:getChannelFlagAsColor(aY)
        Live2DGLWrapper.uniform4f(self.u_channelFlag_Loc_Off, a4.r, a4.g, a4.b, a4.a)
        Live2DGLWrapper.uniform4f(self.u_baseColor_Loc_Off, a_w, a2, a5, a7)
        Live2DGLWrapper.uniform4f(self.u_screenColor_Loc_Off, screenColor[1] or 0, screenColor[2] or 0, screenColor[3] or 0, screenColor[4] or 0)
        Live2DGLWrapper.uniform4f(self.u_multiplyColor_Loc_Off, multiplyColor[1] or 1, multiplyColor[2] or 1, multiplyColor[3] or 1, multiplyColor[4] or 0)
    else
        -- Normal draw
        Live2DGLWrapper.useProgram(self.shaderProgram)
        self.vbo = bindOrCreateVBO(self.vbo, vertexArray)
        self.ebo = bindOrCreateEBO(self.ebo, indexArray)
        Live2DGLWrapper.enableVertexAttribArray(self.a_position_Loc)
        Live2DGLWrapper.vertexAttribPointer(self.a_position_Loc, 2, Live2DGLWrapper.FLOAT, false, 0, nil)
        self.uvbo = bindOrCreateVBO(self.uvbo, uvArray)
        Live2DGLWrapper.activeTexture(Live2DGLWrapper.TEXTURE1)
        Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, self.textures[texNo + 1] or 0)
        Live2DGLWrapper.uniform1i(self.s_texture0_Loc, 1)
        Live2DGLWrapper.enableVertexAttribArray(self.a_texCoord_Loc)
        Live2DGLWrapper.vertexAttribPointer(self.a_texCoord_Loc, 2, Live2DGLWrapper.FLOAT, false, 0, nil)
        Live2DGLWrapper.uniformMatrix4fv(self.u_matrix_Loc, false, self.matrix4x4)
        Live2DGLWrapper.uniform4f(self.u_baseColor_Loc, a_w, a2, a5, a7)
        Live2DGLWrapper.uniform1i(self.u_maskFlag_Loc, 0)
        Live2DGLWrapper.uniform4f(self.u_screenColor_Loc, screenColor[1] or 0, screenColor[2] or 0, screenColor[3] or 0, screenColor[4] or 0)
        Live2DGLWrapper.uniform4f(self.u_multiplyColor_Loc, multiplyColor[1] or 1, multiplyColor[2] or 1, multiplyColor[3] or 1, multiplyColor[4] or 0)
    end

    if self.culling then
        Live2DGLWrapper.enable(Live2DGLWrapper.CULL_FACE)
    else
        Live2DGLWrapper.disable(Live2DGLWrapper.CULL_FACE)
    end

    Live2DGLWrapper.enable(Live2DGLWrapper.BLEND)

    local src_color, src_factor, dst_color, dst_factor
    if self.clipBufPre_clipContextMask ~= nil then
        src_color = Live2DGLWrapper.ONE
        src_factor = Live2DGLWrapper.ONE_MINUS_SRC_ALPHA
        dst_color = Live2DGLWrapper.ONE
        dst_factor = Live2DGLWrapper.ONE_MINUS_SRC_ALPHA
    elseif comp == Mesh.COLOR_COMPOSITION_NORMAL then
        src_color = Live2DGLWrapper.ONE
        src_factor = Live2DGLWrapper.ONE_MINUS_SRC_ALPHA
        dst_color = Live2DGLWrapper.ONE
        dst_factor = Live2DGLWrapper.ONE_MINUS_SRC_ALPHA
    elseif comp == Mesh.COLOR_COMPOSITION_SCREEN then
        src_color = Live2DGLWrapper.ONE
        src_factor = Live2DGLWrapper.ONE
        dst_color = Live2DGLWrapper.ZERO
        dst_factor = Live2DGLWrapper.ONE
    elseif comp == Mesh.COLOR_COMPOSITION_MULTIPLY then
        src_color = Live2DGLWrapper.DST_COLOR
        src_factor = Live2DGLWrapper.ONE_MINUS_SRC_ALPHA
        dst_color = Live2DGLWrapper.ZERO
        dst_factor = Live2DGLWrapper.ONE
    else
        error("unknown comp")
    end

    Live2DGLWrapper.blendEquationSeparate(Live2DGLWrapper.FUNC_ADD, Live2DGLWrapper.FUNC_ADD)
    Live2DGLWrapper.blendFuncSeparate(src_color, src_factor, dst_color, dst_factor)

    local count = #indexArray
    Live2DGLWrapper.drawElements(Live2DGLWrapper.TRIANGLES, count, Live2DGLWrapper.UNSIGNED_SHORT, nil)
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, 0)
end

function DrawParamOpenGL:setTexture(aH, aI)
    local size = #self.textures
    if aH >= size then
        for i = size, aH do
            self.textures[#self.textures + 1] = nil
        end
    end
    self.textures[aH + 1] = aI
end

function DrawParamOpenGL:initShader()
    self:loadShaders2()
    self.a_position_Loc = Live2DGLWrapper.getAttribLocation(self.shaderProgram, "a_position")
    self.a_texCoord_Loc = Live2DGLWrapper.getAttribLocation(self.shaderProgram, "a_texCoord")
    self.u_matrix_Loc = Live2DGLWrapper.getUniformLocation(self.shaderProgram, "u_mvpMatrix")
    self.s_texture0_Loc = Live2DGLWrapper.getUniformLocation(self.shaderProgram, "s_texture0")
    self.u_channelFlag = Live2DGLWrapper.getUniformLocation(self.shaderProgram, "u_channelFlag")
    self.u_baseColor_Loc = Live2DGLWrapper.getUniformLocation(self.shaderProgram, "u_baseColor")
    self.u_maskFlag_Loc = Live2DGLWrapper.getUniformLocation(self.shaderProgram, "u_maskFlag")
    self.u_screenColor_Loc = Live2DGLWrapper.getUniformLocation(self.shaderProgram, "u_screenColor")
    self.u_multiplyColor_Loc = Live2DGLWrapper.getUniformLocation(self.shaderProgram, "u_multiplyColor")
    self.a_position_Loc_Off = Live2DGLWrapper.getAttribLocation(self.shaderProgramOff, "a_position")
    self.a_texCoord_Loc_Off = Live2DGLWrapper.getAttribLocation(self.shaderProgramOff, "a_texCoord")
    self.u_matrix_Loc_Off = Live2DGLWrapper.getUniformLocation(self.shaderProgramOff, "u_mvpMatrix")
    self.u_clipMatrix_Loc_Off = Live2DGLWrapper.getUniformLocation(self.shaderProgramOff, "u_clipMatrix")
    self.s_texture0_Loc_Off = Live2DGLWrapper.getUniformLocation(self.shaderProgramOff, "s_texture0")
    self.s_texture1_Loc_Off = Live2DGLWrapper.getUniformLocation(self.shaderProgramOff, "s_texture1")
    self.u_channelFlag_Loc_Off = Live2DGLWrapper.getUniformLocation(self.shaderProgramOff, "u_channelFlag")
    self.u_baseColor_Loc_Off = Live2DGLWrapper.getUniformLocation(self.shaderProgramOff, "u_baseColor")
    self.u_screenColor_Loc_Off = Live2DGLWrapper.getUniformLocation(self.shaderProgramOff, "u_screenColor")
    self.u_multiplyColor_Loc_Off = Live2DGLWrapper.getUniformLocation(self.shaderProgramOff, "u_multiplyColor")
end

function DrawParamOpenGL:disposeShader()
    if self.shaderProgram and self.shaderProgram ~= 0 then
        Live2DGLWrapper.deleteProgram(self.shaderProgram)
        self.shaderProgram = nil
    end
    if self.shaderProgramOff and self.shaderProgramOff ~= 0 then
        Live2DGLWrapper.deleteProgram(self.shaderProgramOff)
        self.shaderProgramOff = nil
    end
end

function DrawParamOpenGL:compileShader(aJ, aN)
    local aK = Live2DGLWrapper.createShader(aJ)
    if aK == 0 then
        print("_L0 to create shader")
        return nil
    end
    Live2DGLWrapper.shaderSource(aK, aN)
    Live2DGLWrapper.compileShader(aK)
    local aH = Live2DGLWrapper.getShaderParameter(aK, Live2DGLWrapper.COMPILE_STATUS)
    if not aH then
        local aI = Live2DGLWrapper.getShaderInfoLog(aK)
        print("_L0 to compile shader : " .. aI)
        Live2DGLWrapper.deleteShader(aK)
        return nil
    end
    return aK
end

function DrawParamOpenGL:loadShaders2()
    self.shaderProgram = Live2DGLWrapper.createProgram()
    if self.shaderProgram == 0 then return false end

    self.shaderProgramOff = Live2DGLWrapper.createProgram()
    if self.shaderProgramOff == 0 then return false end

    local aK = [[
#version 120
attribute vec2 a_position;
attribute vec2 a_texCoord;
varying vec2 v_texCoord;
varying vec4 v_clipPos;
uniform mat4 u_mvpMatrix;
void main(){
    gl_Position = u_mvpMatrix * vec4(a_position, 0.0, 1.0);
    v_clipPos = gl_Position;
    v_texCoord = a_texCoord;
    v_texCoord.y = 1.0 - v_texCoord.y;
}
]]
    local aM = [[
#version 120
precision mediump float;
varying vec2       v_texCoord;
varying vec4       v_clipPos;
uniform sampler2D  s_texture0;
uniform vec4       u_channelFlag;
uniform vec4       u_baseColor;
uniform bool       u_maskFlag;
uniform vec4       u_screenColor;
uniform vec4       u_multiplyColor;
void main(){
    vec4 smpColor;
    if(u_maskFlag){
        float isInside = 
            step(u_baseColor.x, v_clipPos.x/v_clipPos.w)
          * step(u_baseColor.y, v_clipPos.y/v_clipPos.w)
          * step(v_clipPos.x/v_clipPos.w, u_baseColor.z)
          * step(v_clipPos.y/v_clipPos.w, u_baseColor.w);
        smpColor = u_channelFlag * texture2D(s_texture0, v_texCoord).a * isInside;
    }else{
        smpColor = texture2D(s_texture0 , v_texCoord);
        smpColor.rgb = smpColor.rgb * smpColor.a;
        smpColor.rgb = smpColor.rgb * u_multiplyColor.rgb;
        smpColor.rgb = smpColor.rgb + u_screenColor.rgb - (smpColor.rgb * u_screenColor.rgb);
        smpColor = smpColor * u_baseColor;
    }
    gl_FragColor = smpColor;
}
]]
    local aL = [[
#version 120
attribute vec2     a_position;
attribute vec2     a_texCoord;
varying vec2       v_texCoord;
varying vec4       v_clipPos;
uniform mat4       u_mvpMatrix;
uniform mat4       u_clipMatrix;
void main(){
    vec4 pos = vec4(a_position, 0, 1.0);
    gl_Position = u_mvpMatrix * pos;
    v_clipPos = u_clipMatrix * pos;
    v_texCoord = a_texCoord;
    v_texCoord.y = 1.0 - v_texCoord.y;
}
]]
    local aJ = [[
#version 120
precision mediump float;
varying   vec2   v_texCoord;
varying   vec4   v_clipPos;
uniform sampler2D  s_texture0;
uniform sampler2D  s_texture1;
uniform vec4       u_channelFlag;
uniform vec4       u_baseColor;
uniform vec4       u_screenColor;
uniform vec4       u_multiplyColor;
void main(){
    vec4 col_formask = texture2D(s_texture0, v_texCoord);
    col_formask.rgb = col_formask.rgb * col_formask.a;
    col_formask.rgb = col_formask.rgb * u_multiplyColor.rgb;
    col_formask.rgb = col_formask.rgb + u_screenColor.rgb - (col_formask.rgb * u_screenColor.rgb);
    col_formask = col_formask * u_baseColor;
    vec4 clipMask = texture2D(s_texture1, v_clipPos.xy / v_clipPos.w) * u_channelFlag;
    float maskVal = clipMask.r + clipMask.g + clipMask.b + clipMask.a;
    col_formask = col_formask * maskVal;
    gl_FragColor = col_formask;
}
]]
    self.vertShader = self:compileShader(Live2DGLWrapper.VERTEX_SHADER, aK)
    if not self.vertShader then print("Vertex shader compile error!"); return false end

    self.vertShaderOff = self:compileShader(Live2DGLWrapper.VERTEX_SHADER, aL)
    if not self.vertShaderOff then print("OffVertex shader compile error!"); return false end

    self.fragShader = self:compileShader(Live2DGLWrapper.FRAGMENT_SHADER, aM)
    if not self.fragShader then print("Fragment shader compile error!"); return false end

    self.fragShaderOff = self:compileShader(Live2DGLWrapper.FRAGMENT_SHADER, aJ)
    if not self.fragShaderOff then print("OffFragment shader compile error!"); return false end

    Live2DGLWrapper.attachShader(self.shaderProgram, self.vertShader)
    Live2DGLWrapper.attachShader(self.shaderProgram, self.fragShader)
    Live2DGLWrapper.attachShader(self.shaderProgramOff, self.vertShaderOff)
    Live2DGLWrapper.attachShader(self.shaderProgramOff, self.fragShaderOff)

    Live2DGLWrapper.linkProgram(self.shaderProgram)
    Live2DGLWrapper.linkProgram(self.shaderProgramOff)

    local aH = Live2DGLWrapper.getProgramParameter(self.shaderProgram, Live2DGLWrapper.LINK_STATUS)
    local aX = Live2DGLWrapper.getProgramParameter(self.shaderProgramOff, Live2DGLWrapper.LINK_STATUS)

    if not aH or not aX then
        local aI = aH and Live2DGLWrapper.getProgramInfoLog(self.shaderProgram) or Live2DGLWrapper.getProgramInfoLog(self.shaderProgramOff)
        print("failed to link program: " .. aI)
        if self.vertShader then Live2DGLWrapper.deleteShader(self.vertShader); self.vertShader = 0 end
        if self.fragShader then Live2DGLWrapper.deleteShader(self.fragShader); self.fragShader = 0 end
        if self.shaderProgram and self.shaderProgram ~= 0 then Live2DGLWrapper.deleteProgram(self.shaderProgram); self.shaderProgram = 0 end
        if self.vertShaderOff then Live2DGLWrapper.deleteShader(self.vertShaderOff); self.vertShaderOff = 0 end
        if self.fragShaderOff then Live2DGLWrapper.deleteShader(self.fragShaderOff); self.fragShaderOff = 0 end
        if self.shaderProgramOff and self.shaderProgramOff ~= 0 then Live2DGLWrapper.deleteProgram(self.shaderProgramOff); self.shaderProgramOff = 0 end
        return false
    end
    return true
end

function DrawParamOpenGL:createFramebuffer()
    local aK = Live2D.clippingMaskBufferSize
    local aJ = Live2DGLWrapper.createFramebuffer()
    Live2DGLWrapper.bindFramebuffer(Live2DGLWrapper.FRAMEBUFFER, aJ)
    local aH = Live2DGLWrapper.createRenderbuffer()
    Live2DGLWrapper.bindRenderbuffer(Live2DGLWrapper.RENDERBUFFER, aH)
    Live2DGLWrapper.renderbufferStorage(Live2DGLWrapper.RENDERBUFFER, Live2DGLWrapper.RGBA4, aK, aK)
    Live2DGLWrapper.framebufferRenderbuffer(Live2DGLWrapper.FRAMEBUFFER, Live2DGLWrapper.COLOR_ATTACHMENT0, Live2DGLWrapper.RENDERBUFFER, aH)
    local aI = Live2DGLWrapper.createTexture()
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, aI)
    Live2DGLWrapper.texImage2D(Live2DGLWrapper.TEXTURE_2D, 0, Live2DGLWrapper.RGBA, aK, aK, 0, Live2DGLWrapper.RGBA, Live2DGLWrapper.UNSIGNED_BYTE, nil)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MIN_FILTER, Live2DGLWrapper.LINEAR)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MAG_FILTER, Live2DGLWrapper.LINEAR)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_WRAP_S, Live2DGLWrapper.CLAMP_TO_EDGE)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_WRAP_T, Live2DGLWrapper.CLAMP_TO_EDGE)
    Live2DGLWrapper.framebufferTexture2D(Live2DGLWrapper.FRAMEBUFFER, Live2DGLWrapper.COLOR_ATTACHMENT0, Live2DGLWrapper.TEXTURE_2D, aI, 0)
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, 0)
    Live2DGLWrapper.bindRenderbuffer(Live2DGLWrapper.RENDERBUFFER, 0)
    Live2DGLWrapper.bindFramebuffer(Live2DGLWrapper.FRAMEBUFFER, 0)
    self.framebufferObject = FrameBufferObject.new(aJ, aH, aI)
end

DrawParamOpenGL.FrameBufferObject = FrameBufferObject

return DrawParamOpenGL
