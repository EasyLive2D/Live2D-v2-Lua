-- PlatformManager - I/O abstraction and texture loading
-- Uses Live2DGLWrapper for OpenGL, image_loader for textures via GDI+

local Live2DModelOpenGL = require("live2d.core.live2d_model_opengl")
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")
local imageLoader = require("live2d.image_loader")
local dkjson = require("live2d.dkjson")
local ffi = require("ffi")

local PlatformManager = {}
PlatformManager.__index = PlatformManager

function PlatformManager.new()
    return setmetatable({}, PlatformManager)
end

function PlatformManager:loadBytes(path)
    local f = io.open(path, "rb")
    if not f then error("Cannot open file: " .. path) end
    local content = f:read("*all")
    f:close()
    return content
end

function PlatformManager:loadLive2DModel(path)
    local f = io.open(path, "rb")
    if not f then error("Cannot open file: " .. path) end
    local content = f:read("*all")
    f:close()
    return Live2DModelOpenGL.loadModel(content)
end

function PlatformManager:loadTexture(live2DModel, no, path)
    local w, h, data = imageLoader.loadImage(path)
    
    Live2DGLWrapper.enable(Live2DGLWrapper.TEXTURE_2D)
    local texture = Live2DGLWrapper.createTexture()
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, texture)
    Live2DGLWrapper.texImage2D(Live2DGLWrapper.TEXTURE_2D, 0, Live2DGLWrapper.RGBA, w, h, 0, Live2DGLWrapper.RGBA, Live2DGLWrapper.UNSIGNED_BYTE, data)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MIN_FILTER, Live2DGLWrapper.LINEAR_MIPMAP_LINEAR)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MAG_FILTER, Live2DGLWrapper.LINEAR)
    Live2DGLWrapper.generateMipmap(Live2DGLWrapper.TEXTURE_2D)
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, 0)
    
    live2DModel:setTexture(no, texture)
    print("Texture " .. no .. " loaded: " .. path)
end

function PlatformManager:jsonParseFromBytes(data)
    return dkjson.decode(data)
end

function PlatformManager:log(msg)
    print(msg)
end

return PlatformManager
