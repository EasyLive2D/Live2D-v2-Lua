-- live2d_embed.lua - windowless Live2D renderer for host applications.
--
-- The host application must create and make current an OpenGL context before
-- calling init/load_model/draw. This module intentionally does not create an
-- SDL window or run an event loop, so it can be driven from Python, C#, etc.

package.path = package.path .. ";./?.lua;./?/init.lua"

local gl = require("live2d.gl_loader")
local live2d = require("live2d")
local Live2DFramework = live2d.Live2DFramework
local Live2D = live2d.Live2D
local MotionPriority = live2d.MotionPriority
local LAppModel = live2d.LAppModel
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")

local M = {}
local Renderer = {}
Renderer.__index = Renderer

local runtime_initialized = false
local current_renderer = nil

local function init_runtime()
    if runtime_initialized then return end

    -- Requires an active WGL context; extension pointers are context-bound.
    gl.ensureExtensions()

    local pm = require("live2d.platform_manager").new()
    Live2DFramework.setPlatformManager(pm)
    Live2D.init()
    runtime_initialized = true
end

local function require_model(self)
    if self.model == nil then
        error("Live2D model is not loaded", 3)
    end
    return self.model
end

function Renderer:load_model(model_path, width, height, opts)
    if model_path == nil or model_path == "" then
        error("model_path is required", 2)
    end

    opts = opts or {}
    self.width = tonumber(width) or self.width
    self.height = tonumber(height) or self.height

    local model = LAppModel.new()
    model:LoadModelJson(model_path)
    model:Resize(self.width, self.height)
    model:SetAutoBreathEnable(opts.auto_breath ~= false)
    model:SetAutoBlinkEnable(opts.auto_blink ~= false)

    if opts.center ~= false then
        model.modelMatrix:identity()
        model.modelMatrix:setWidth(tonumber(opts.model_width) or 2.0)
        model.modelMatrix:setCenterPosition(
            tonumber(opts.center_x) or 0,
            tonumber(opts.center_y) or 0
        )
    end

    self.model = model
    self.model_path = model_path
    self:resize(self.width, self.height)
    return self
end

function Renderer:resize(width, height)
    self.width = tonumber(width) or self.width
    self.height = tonumber(height) or self.height

    if self.width <= 0 or self.height <= 0 then
        error("width and height must be positive", 2)
    end

    Live2DGLWrapper.viewport(0, 0, self.width, self.height)
    if self.model ~= nil then
        self.model:Resize(self.width, self.height)
    end
    return self
end

function Renderer:clear(r, g, b, a)
    Live2DGLWrapper.clearColor(r or 0.0, g or 0.0, b or 0.0, a or 0.0)
    Live2DGLWrapper.clear(Live2DGLWrapper.COLOR_BUFFER_BIT)
    return self
end

function Renderer:update()
    require_model(self):Update()
    return self
end

function Renderer:draw(opts)
    opts = opts or {}
    local model = require_model(self)

    if opts.clear ~= false then
        self:clear(opts.r, opts.g, opts.b, opts.a)
    end

    model:Update()
    model:Draw()

    -- Draw allocates short-lived FFI buffers per mesh. Keep memory stable when
    -- the host renders faster than display refresh.
    collectgarbage("step", tonumber(opts.gc_step) or 200)
    return self
end

function Renderer:drag(x, y)
    require_model(self):Drag(tonumber(x) or 0, tonumber(y) or 0)
    return self
end

function Renderer:set_offset(x, y)
    require_model(self):SetOffset(tonumber(x) or 0, tonumber(y) or 0)
    return self
end

function Renderer:set_scale(scale)
    require_model(self):SetScale(tonumber(scale) or 1.0)
    return self
end

function Renderer:set_parameter(param_id, value, weight)
    require_model(self):SetParameterValue(param_id, tonumber(value) or 0, tonumber(weight) or 1.0)
    return self
end

function Renderer:add_parameter(param_id, value, weight)
    require_model(self):AddParameterValue(param_id, tonumber(value) or 0, tonumber(weight) or 1.0)
    return self
end

function Renderer:set_expression(name)
    require_model(self):SetExpression(name)
    return self
end

function Renderer:reset_expression()
    require_model(self):ResetExpression()
    return self
end

function Renderer:start_motion(name, no, priority)
    priority = priority or MotionPriority.FORCE
    require_model(self):StartMotion(name, tonumber(no) or 0, priority)
    return self
end

function Renderer:clear_motions()
    require_model(self):ClearMotions()
    return self
end

function Renderer:hit_test(x, y)
    return require_model(self):HitPart(tonumber(x) or 0, tonumber(y) or 0, true)
end

function Renderer:get_model()
    return self.model
end


function M.init()
    init_runtime()
    return true
end

function M.new(width, height, opts)
    init_runtime()
    opts = opts or {}

    local renderer = setmetatable({
        width = tonumber(width) or 400,
        height = tonumber(height) or 650,
        model = nil,
        model_path = nil,
    }, Renderer)

    if opts.model_path ~= nil then
        renderer:load_model(opts.model_path, renderer.width, renderer.height, opts)
    else
        renderer:resize(renderer.width, renderer.height)
    end

    return renderer
end

-- Singleton API for hosts that prefer simple global-style calls through Lua C API.
function M.load_model(model_path, width, height, opts)
    current_renderer = M.new(width, height)
    current_renderer:load_model(model_path, width, height, opts)
    return current_renderer
end

function M.current()
    return current_renderer
end

function M.resize(width, height)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:resize(width, height)
end

function M.draw(opts)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:draw(opts)
end

function M.update()
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:update()
end

function M.clear(r, g, b, a)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:clear(r, g, b, a)
end

function M.drag(x, y)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:drag(x, y)
end

function M.set_offset(x, y)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:set_offset(x, y)
end

function M.set_scale(scale)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:set_scale(scale)
end

function M.set_parameter(param_id, value, weight)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:set_parameter(param_id, value, weight)
end

function M.add_parameter(param_id, value, weight)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:add_parameter(param_id, value, weight)
end

function M.start_motion(name, no, priority)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:start_motion(name, no, priority)
end

function M.set_expression(name)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:set_expression(name)
end

function M.hit_test(x, y)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:hit_test(x, y)
end

function M.dispose()
    current_renderer = nil
    Live2D.dispose()
    runtime_initialized = false
end

M.Renderer = Renderer
M.MotionPriority = MotionPriority

return M
