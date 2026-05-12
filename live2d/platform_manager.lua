-- PlatformManager - I/O abstraction and texture loading
-- Uses Live2DGLWrapper for OpenGL, image_loader for textures via GDI+

local Live2DModelOpenGL = require("live2d.core.live2d_model_opengl")
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")
local imageLoader = require("live2d.image_loader")
local dkjson = require("live2d.dkjson")
local ffi = require("ffi")

local PlatformManager = {}
PlatformManager.__index = PlatformManager

local function normalizePath(path)
    path = tostring(path):gsub("\\", "/")
    path = path:gsub("^%./", "")
    return path
end

local function streamData(stream, path)
    if type(stream) == "function" then
        stream = stream(path)
    end
    if type(stream) == "table" then
        stream = stream.data or stream.bytes or stream[1]
    end
    if stream == nil then
        error("resource stream data is required: " .. tostring(path), 3)
    end
    return stream
end

local function uploadTexture(live2DModel, no, w, h, data, label)
    Live2DGLWrapper.enable(Live2DGLWrapper.TEXTURE_2D)
    local texture = Live2DGLWrapper.createTexture()
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, texture)
    Live2DGLWrapper.texImage2D(Live2DGLWrapper.TEXTURE_2D, 0, Live2DGLWrapper.RGBA, w, h, 0, Live2DGLWrapper.RGBA, Live2DGLWrapper.UNSIGNED_BYTE, data)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MIN_FILTER, Live2DGLWrapper.LINEAR_MIPMAP_LINEAR)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MAG_FILTER, Live2DGLWrapper.LINEAR)
    Live2DGLWrapper.generateMipmap(Live2DGLWrapper.TEXTURE_2D)
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, 0)

    live2DModel:setTexture(no, texture)
    print("Texture " .. no .. " loaded: " .. label)
end

local function normalizeTextureStream(stream, no, path)
    if type(stream) == "function" then
        stream = stream(no, path)
    end
    if type(stream) ~= "table" then
        error("texture stream must be a table or function result for texture " .. tostring(no), 3)
    end

    local width = tonumber(stream.width or stream.w)
    local height = tonumber(stream.height or stream.h)
    local data = stream.data or stream.pixels or stream[1]
    if width == nil or height == nil or width <= 0 or height <= 0 then
        error("texture stream width/height must be positive for texture " .. tostring(no), 3)
    end
    if data == nil then
        error("texture stream data is required for texture " .. tostring(no), 3)
    end

    if type(data) == "string" then
        local required = width * height * 4
        if #data < required then
            error("texture stream data is shorter than width * height * 4 for texture " .. tostring(no), 3)
        end
        data = ffi.cast("const uint8_t*", data)
    else
        data = ffi.cast("const uint8_t*", data)
    end

    return width, height, data
end

function PlatformManager.new(opts)
    opts = opts or {}
    local self = setmetatable({ resourceStreams = {}, textureStreams = {} }, PlatformManager)
    self:setResourceStreams(opts.resource_streams or opts.resourceStreams)
    self:setTextureStreams(opts.texture_streams or opts.textureStreams)
    return self
end

function PlatformManager:setResourceStream(path, data)
    self.resourceStreams[normalizePath(path)] = data
end

function PlatformManager:setResourceStreams(resourceStreams)
    if resourceStreams == nil then return end
    for k, v in pairs(resourceStreams) do
        self.resourceStreams[normalizePath(k)] = v
    end
end

function PlatformManager:clearResourceStreams()
    self.resourceStreams = {}
end

function PlatformManager:setTextureStream(no, width, height, data)
    self.textureStreams[tonumber(no)] = {
        width = width,
        height = height,
        data = data,
    }
end

function PlatformManager:setTextureStreams(textureStreams)
    if textureStreams == nil then return end
    for k, v in pairs(textureStreams) do
        self.textureStreams[k] = v
    end
end

function PlatformManager:clearTextureStreams()
    self.textureStreams = {}
end

function PlatformManager:clearStreams()
    self:clearResourceStreams()
    self:clearTextureStreams()
end

function PlatformManager:loadBytes(path)
    local normalized = normalizePath(path)
    local stream = self.resourceStreams[normalized]
    if stream ~= nil then
        return streamData(stream, normalized)
    end

    local f = io.open(path, "rb")
    if not f then error("Cannot open file: " .. path) end
    local content = f:read("*all")
    f:close()
    return content
end

function PlatformManager:loadLive2DModel(path)
    return Live2DModelOpenGL.loadModel(self:loadBytes(path))
end

function PlatformManager:loadTexture(live2DModel, no, path)
    local normalized = normalizePath(path)
    local stream = self.textureStreams[no] or self.textureStreams[no + 1] or self.textureStreams[path] or self.textureStreams[normalized]
    if stream ~= nil then
        local w, h, data = normalizeTextureStream(stream, no, path)
        uploadTexture(live2DModel, no, w, h, data, "stream:" .. tostring(no))
        return
    end

    local w, h, data = imageLoader.loadImage(path)
    uploadTexture(live2DModel, no, w, h, data, path)
end

function PlatformManager:jsonParseFromBytes(data)
    return dkjson.decode(data)
end

function PlatformManager:log(msg)
    print(msg)
end

return PlatformManager
