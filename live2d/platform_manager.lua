-- PlatformManager - I/O abstraction and texture loading
-- Uses Live2DGLWrapper for OpenGL, image_loader for textures

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
    if type(stream) == "function" or type(stream) == "userdata" then
        local ok, result = pcall(stream, path)
        if ok then stream = result end
    end
    if type(stream) == "table" then
        stream = stream.data or stream.bytes or stream[1]
    end
    if stream == nil then
        error("resource stream data is required: " .. tostring(path), 3)
    end
    return stream
end

local function premultiplyAlpha(w, h, data)
    local pixelCount = w * h
    local out = ffi.new("uint8_t[?]", pixelCount * 4)
    local src = ffi.cast("const uint8_t*", data)
    for i = 0, pixelCount - 1 do
        local base = i * 4
        local a = src[base + 3]
        out[base] = math.floor((src[base] * a + 127) / 255)
        out[base + 1] = math.floor((src[base + 1] * a + 127) / 255)
        out[base + 2] = math.floor((src[base + 2] * a + 127) / 255)
        out[base + 3] = a
    end
    return out
end

local function premultiplyAlphaInPlace(w, h, data)
    local pixelCount = w * h
    local src = ffi.cast("uint8_t*", data)
    for i = 0, pixelCount - 1 do
        local base = i * 4
        local a = src[base + 3]
        src[base] = math.floor((src[base] * a + 127) / 255)
        src[base + 1] = math.floor((src[base + 1] * a + 127) / 255)
        src[base + 2] = math.floor((src[base + 2] * a + 127) / 255)
    end
    return src
end

local function bleedAndPremultiplyAlpha(w, h, data)
    local pixelCount = w * h
    local out = ffi.new("uint8_t[?]", pixelCount * 4)
    local src = ffi.cast("const uint8_t*", data)

    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local base = (y * w + x) * 4
            local a = src[base + 3]
            local sr = src[base]
            local sg = src[base + 1]
            local sb = src[base + 2]
            if a > 0 and a < 255 then
                local total = 0
                local r = 0
                local g = 0
                local b = 0
                for oy = -1, 1 do
                    for ox = -1, 1 do
                        if ox ~= 0 or oy ~= 0 then
                            local nx = x + ox
                            local ny = y + oy
                            if nx >= 0 and nx < w and ny >= 0 and ny < h then
                                local nbase = (ny * w + nx) * 4
                                local na = src[nbase + 3]
                                if na > a then
                                    r = r + src[nbase] * na
                                    g = g + src[nbase + 1] * na
                                    b = b + src[nbase + 2] * na
                                    total = total + na
                                end
                            end
                        end
                    end
                end
                if total > 0 then
                    sr = math.floor((r + total / 2) / total)
                    sg = math.floor((g + total / 2) / total)
                    sb = math.floor((b + total / 2) / total)
                end
            end
            out[base] = math.floor((sr * a + 127) / 255)
            out[base + 1] = math.floor((sg * a + 127) / 255)
            out[base + 2] = math.floor((sb * a + 127) / 255)
            out[base + 3] = a
        end
    end
    return out
end

local function copyRow(dst, src, y, rowBytes)
    ffi.copy(dst, src + y * rowBytes, rowBytes)
end

local function bleedAndPremultiplyAlphaInPlace(w, h, data)
    local rowBytes = w * 4
    local src = ffi.cast("uint8_t*", data)
    local prevRow = ffi.new("uint8_t[?]", rowBytes)
    local currRow = ffi.new("uint8_t[?]", rowBytes)
    local nextRow = ffi.new("uint8_t[?]", rowBytes)

    copyRow(currRow, src, 0, rowBytes)
    if h > 1 then
        copyRow(nextRow, src, 1, rowBytes)
    end

    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local cbase = x * 4
            local a = currRow[cbase + 3]
            local sr = currRow[cbase]
            local sg = currRow[cbase + 1]
            local sb = currRow[cbase + 2]
            if a > 0 and a < 255 then
                local total = 0
                local r = 0
                local g = 0
                local b = 0
                for oy = -1, 1 do
                    local row = oy == -1 and prevRow or (oy == 0 and currRow or nextRow)
                    local ny = y + oy
                    if ny >= 0 and ny < h then
                        for ox = -1, 1 do
                            if ox ~= 0 or oy ~= 0 then
                                local nx = x + ox
                                if nx >= 0 and nx < w then
                                    local nbase = nx * 4
                                    local na = row[nbase + 3]
                                    if na > a then
                                        r = r + row[nbase] * na
                                        g = g + row[nbase + 1] * na
                                        b = b + row[nbase + 2] * na
                                        total = total + na
                                    end
                                end
                            end
                        end
                    end
                end
                if total > 0 then
                    sr = math.floor((r + total / 2) / total)
                    sg = math.floor((g + total / 2) / total)
                    sb = math.floor((b + total / 2) / total)
                end
            end

            local base = (y * w + x) * 4
            src[base] = math.floor((sr * a + 127) / 255)
            src[base + 1] = math.floor((sg * a + 127) / 255)
            src[base + 2] = math.floor((sb * a + 127) / 255)
            src[base + 3] = a
        end

        prevRow, currRow, nextRow = currRow, nextRow, prevRow
        if y + 2 < h then
            copyRow(nextRow, src, y + 2, rowBytes)
        end
    end

    return src
end

local function uploadTexture(live2DModel, no, w, h, data, label, useMipmap, isPremultiplied, edgeBleed, allowInPlace)
    Live2DGLWrapper.enable(Live2DGLWrapper.TEXTURE_2D)
    local texture = Live2DGLWrapper.createTexture()
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, texture)
    if not isPremultiplied then
        if allowInPlace and edgeBleed then
            data = bleedAndPremultiplyAlphaInPlace(w, h, data)
        elseif allowInPlace then
            data = premultiplyAlphaInPlace(w, h, data)
        elseif edgeBleed then
            data = bleedAndPremultiplyAlpha(w, h, data)
        else
            data = premultiplyAlpha(w, h, data)
        end
    end
    Live2DGLWrapper.texImage2D(Live2DGLWrapper.TEXTURE_2D, 0, Live2DGLWrapper.RGBA, w, h, 0, Live2DGLWrapper.RGBA, Live2DGLWrapper.UNSIGNED_BYTE, data)
    if useMipmap then
        Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MIN_FILTER, Live2DGLWrapper.LINEAR_MIPMAP_LINEAR)
    else
        Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MIN_FILTER, Live2DGLWrapper.LINEAR)
    end
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_MAG_FILTER, Live2DGLWrapper.LINEAR)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_WRAP_S, Live2DGLWrapper.CLAMP_TO_EDGE)
    Live2DGLWrapper.texParameteri(Live2DGLWrapper.TEXTURE_2D, Live2DGLWrapper.TEXTURE_WRAP_T, Live2DGLWrapper.CLAMP_TO_EDGE)
    if useMipmap then
        Live2DGLWrapper.generateMipmap(Live2DGLWrapper.TEXTURE_2D)
    end
    Live2DGLWrapper.bindTexture(Live2DGLWrapper.TEXTURE_2D, 0)

    live2DModel:setTexture(no, texture)
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

    local dataIsString = type(data) == "string"
    if dataIsString then
        local required = width * height * 4
        if #data < required then
            error("texture stream data is shorter than width * height * 4 for texture " .. tostring(no), 3)
        end
        data = ffi.cast("const uint8_t*", data)
    else
        data = ffi.cast("const uint8_t*", data)
    end

    local useMipmap = stream.mipmap == true or stream.use_mipmap == true or stream.useMipmap == true
    local isPremultiplied = stream.premultiplied == true or stream.premultiplied_alpha == true or stream.premultipliedAlpha == true
    local edgeBleed = stream.edge_bleed ~= false and stream.edgeBleed ~= false
    local allowInPlace = not dataIsString and (stream.in_place == true or stream.inPlace == true)
    return width, height, data, useMipmap, isPremultiplied, edgeBleed, allowInPlace
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

function PlatformManager:setTextureStreams(textureStreams)
    if textureStreams == nil then return end
    for k, v in pairs(textureStreams) do
        self.textureStreams[k] = v
    end
end

function PlatformManager:jsonParseFromBytes(data)
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
    if stream == nil and self.resourceStreams.__loader ~= nil then
        stream = self.resourceStreams.__loader
    end
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
    if stream == nil and self.textureStreams.__loader ~= nil then
        stream = function(texture_no, texture_path)
            return self.textureStreams.__loader(texture_no, texture_path)
        end
    end
    if stream ~= nil then
        local w, h, data, useMipmap, isPremultiplied, edgeBleed, allowInPlace = normalizeTextureStream(stream, no, path)
        uploadTexture(live2DModel, no, w, h, data, "stream:" .. tostring(no), useMipmap, isPremultiplied, edgeBleed, allowInPlace)
        return
    end

    local w, h, data = imageLoader.loadImage(path)
    uploadTexture(live2DModel, no, w, h, data, path, false, false, true, true)
end

function PlatformManager:jsonParseFromBytes(data)
    return dkjson.decode(data)
end

return PlatformManager
