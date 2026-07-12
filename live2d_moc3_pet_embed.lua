-- Compatibility wrapper that exposes the Cubism 3 renderer through the same
-- host-facing shape as live2d_embed.lua.

local ffi = require("ffi")
local gl = require("live2d.gl_loader")
local moc3 = require("live2d_moc3_embed")

local M = {}
local Renderer = {}
Renderer.__index = Renderer

local GL_COLOR_BUFFER_BIT = 0x00004000
local function compute_delta_seconds(state, time_msec)
    time_msec = tonumber(time_msec)
    if time_msec == nil then
        return 0
    end
    local last_time_msec = state.last_time_msec
    state.last_time_msec = time_msec
    if last_time_msec == nil or time_msec <= last_time_msec then
        return 0
    end
    return math.min((time_msec - last_time_msec) / 1000.0, 0.1)
end

-- Drag (head/eye follow) easing half-life in seconds. The Cubism 2 framework
-- drags through a smoothed target point; applying drag instantly on moc3 made
-- the whole body snap between poses whenever the tracking target changed.
local DRAG_SMOOTHING_HALF_LIFE = 0.1

-- Drag offsets are ADDED on top of motion-driven values each frame (the
-- standard Cubism update order), so idle motions keep their sway instead of
-- being frozen by persistent parameter overrides.
local DRAG_PARAM_SPECS = {
    { id = "ParamAngleX", axis = "x", scale = 30.0 },
    { id = "ParamAngleY", axis = "y", scale = -30.0 },
    { id = "ParamEyeBallX", axis = "x", scale = 1.0 },
    { id = "ParamEyeBallY", axis = "y", scale = -1.0 },
}

local PARAM_ALIASES = {
    PARAM_MOUTH_OPEN_Y = "ParamMouthOpenY",
    PARAM_MOUTH_FORM = "ParamMouthForm",
    PARAM_ANGLE_X = "ParamAngleX",
    PARAM_ANGLE_Y = "ParamAngleY",
    PARAM_BODY_ANGLE_X = "ParamBodyAngleX",
    PARAM_EYE_BALL_X = "ParamEyeBallX",
    PARAM_EYE_BALL_Y = "ParamEyeBallY",
}

local function clamp(value, low, high)
    value = tonumber(value) or 0
    if value < low then return low end
    if value > high then return high end
    return value
end

local function parameter_id(param_id)
    local text = tostring(param_id or "")
    return PARAM_ALIASES[text] or text
end

local function new_projection(width, height, runtime, offset_x, offset_y, scale_override)
    width = math.max(tonumber(width) or 1, 1)
    height = math.max(tonumber(height) or 1, 1)
    local canvas = runtime and runtime.canvas or nil
    local model_width = 2.0
    local model_height = 2.0
    if canvas ~= nil and tonumber(canvas.pixels_per_unit) and canvas.pixels_per_unit ~= 0 then
        model_width = math.max(math.abs((tonumber(canvas.width) or 0) / canvas.pixels_per_unit), 0.001)
        model_height = math.max(math.abs((tonumber(canvas.height) or 0) / canvas.pixels_per_unit), 0.001)
    end
    local scale = math.min(width / model_width, height / model_height) * (tonumber(scale_override) or 1.0)
    return ffi.new("float[16]", {
        scale * 2.0 / width, 0, 0, 0,
        0, scale * 2.0 / height, 0, 0,
        0, 0, 1, 0,
        tonumber(offset_x) or 0, tonumber(offset_y) or 0, 0, 1,
    })
end

function M.init()
    gl.ensureExtensions()
end

function M.new(width, height)
    M.init()
    local self = setmetatable({
        width = math.max(tonumber(width) or 1, 1),
        height = math.max(tonumber(height) or 1, 1),
        offset_x = 0,
        offset_y = 0,
        scale = 1,
        renderer = moc3.new({ gl = gl }),
        projection = nil,
        last_time_msec = nil,
        drag_x = 0.0,
        drag_y = 0.0,
        drag_target_x = 0.0,
        drag_target_y = 0.0,
        pending_host_parameters = nil,
    }, Renderer)
    self:resize(self.width, self.height)
    return self
end

function Renderer:load_model(model_path, width, height, opts)
    opts = opts or {}
    if self.renderer ~= nil then
        self.renderer:dispose()
    end
    self.renderer = moc3.new({
        gl = gl,
        resource_streams = opts.resource_streams or opts.resourceStreams or {},
        texture_streams = opts.texture_streams or opts.textureStreams or {},
    })
    self.renderer:load_model(model_path, opts)
    self.renderer.pre_override_hook = function(runtime, delta_seconds)
        self:_apply_host_state(runtime, delta_seconds)
    end
    self.last_time_msec = nil
    self.drag_x, self.drag_y = 0.0, 0.0
    self.drag_target_x, self.drag_target_y = 0.0, 0.0
    self.pending_host_parameters = nil
    self:resize(width or self.width, height or self.height)
    return self
end

-- Applied from inside Renderer:update, after motions/expressions and before
-- pose, so host writes land on top of motion values for exactly one frame.
function Renderer:_apply_host_state(runtime, delta_seconds)
    local pending = self.pending_host_parameters
    if pending ~= nil then
        self.pending_host_parameters = nil
        for i = 1, #pending do
            local entry = pending[i]
            local index = runtime:parameter_index_of(entry.id)
            if index ~= nil then
                local value = entry.value
                if entry.weight < 1.0 then
                    local current = runtime:parameter_value_by_index(index) or 0
                    value = current + (value - current) * entry.weight
                end
                runtime:set_parameter_by_index(index, value)
            end
        end
    end

    local target_x, target_y = self.drag_target_x, self.drag_target_y
    local drag_x, drag_y = self.drag_x, self.drag_y
    if target_x ~= drag_x or target_y ~= drag_y then
        local dt = tonumber(delta_seconds) or 0
        local ease = 1.0 - 0.5 ^ (dt / DRAG_SMOOTHING_HALF_LIFE)
        drag_x = drag_x + (target_x - drag_x) * ease
        drag_y = drag_y + (target_y - drag_y) * ease
        if math.abs(target_x - drag_x) < 0.001 then drag_x = target_x end
        if math.abs(target_y - drag_y) < 0.001 then drag_y = target_y end
        self.drag_x, self.drag_y = drag_x, drag_y
    end
    if drag_x ~= 0.0 or drag_y ~= 0.0 then
        for i = 1, #DRAG_PARAM_SPECS do
            local spec = DRAG_PARAM_SPECS[i]
            local index = runtime:parameter_index_of(spec.id)
            if index ~= nil then
                local amount = (spec.axis == "x" and drag_x or drag_y) * spec.scale
                local current = runtime:parameter_value_by_index(index) or 0
                runtime:set_parameter_by_index(index, current + amount)
            end
        end
    end
end

function Renderer:resize(width, height)
    self.width = math.max(tonumber(width) or self.width or 1, 1)
    self.height = math.max(tonumber(height) or self.height or 1, 1)
    gl.glViewport(0, 0, self.width, self.height)
    local runtime = self.renderer and self.renderer:get_runtime() or nil
    self.projection = new_projection(self.width, self.height, runtime, self.offset_x, self.offset_y, self.scale)
    return self
end

function Renderer:set_offset(x, y)
    self.offset_x = tonumber(x) or 0
    self.offset_y = tonumber(y) or 0
    return self:resize(self.width, self.height)
end

function Renderer:set_scale(scale)
    self.scale = tonumber(scale) or 1
    return self:resize(self.width, self.height)
end

function Renderer:set_parameter(param_id, value, weight)
    if self.renderer == nil then return self end
    local pending = self.pending_host_parameters
    if pending == nil then
        pending = {}
        self.pending_host_parameters = pending
    end
    pending[#pending + 1] = {
        id = parameter_id(param_id),
        value = tonumber(value) or 0,
        weight = clamp(tonumber(weight) or 1.0, 0.0, 1.0),
    }
    return self
end

function Renderer:drag(x, y)
    local nx = ((tonumber(x) or 0) / math.max(self.width, 1) - 0.5) * 2.0
    local ny = ((tonumber(y) or 0) / math.max(self.height, 1) - 0.5) * 2.0
    self.drag_target_x = clamp(nx, -1, 1)
    self.drag_target_y = clamp(ny, -1, 1)
    return self
end

function Renderer:draw(opts)
    opts = opts or {}
    if self.renderer == nil or self.renderer:get_runtime() == nil then return self end

    if opts.clear ~= false then
        gl.glClearColor(tonumber(opts.r) or 0, tonumber(opts.g) or 0, tonumber(opts.b) or 0, tonumber(opts.a) or 0)
        gl.glClear(GL_COLOR_BUFFER_BIT)
    end

    local start = os.clock()
    if opts.parameters ~= nil then
        for i = 1, #opts.parameters do
            local entry = opts.parameters[i]
            if entry ~= nil and entry.id ~= nil then
                self:set_parameter(entry.id, entry.value, entry.weight)
            end
        end
    end

    local delta = compute_delta_seconds(self, opts.time_msec)

    self.renderer:update(delta)
    self.renderer:render(self.projection)
    opts.profile_update_draw_seconds = os.clock() - start

    local gc_start = os.clock()
    collectgarbage("step", tonumber(opts.gc_step) or 200)
    opts.profile_gc_seconds = os.clock() - gc_start
    return self
end

function Renderer:hit_test(_x, _y)
    return {}
end

function Renderer:model_info()
    local info = { motion_names = {}, motions = {}, expressions = {}, hit_area_count = 0 }
    local model_data = self.renderer and self.renderer:get_model_data() or nil
    local refs = model_data and model_data.file_references or nil
    if refs == nil then return info end

    for name, group in pairs(refs.motions or {}) do
        info.motion_names[#info.motion_names + 1] = name
        local files = {}
        for i = 1, #(group or {}) do
            local item = group[i]
            files[#files + 1] = (item and item.File) or ""
        end
        info.motions[name] = files
    end

    for _, reference in ipairs(refs.expressions or {}) do
        if reference.Name ~= nil and reference.Name ~= "" then
            info.expressions[reference.Name] = true
        end
    end

    info.hit_area_count = #(model_data.hit_areas or {})
    return info
end

function Renderer:start_motion(name, no, priority, loop)
    if self.renderer == nil then return self end
    if tonumber(priority) and tonumber(priority) >= 3 then
        self.renderer:clear_motions()
    end
    pcall(function() self.renderer:start_motion(tostring(name), tonumber(no) or 0, 1.0, loop) end)
    return self
end

function Renderer:clear_motions()
    if self.renderer ~= nil then self.renderer:clear_motions() end
    return self
end

function Renderer:is_motion_finished()
    return self.renderer == nil or #(self.renderer.active_motions or {}) == 0
end

function Renderer:preload_motion_group(name)
    if self.renderer == nil then return self end
    local model_data = self.renderer:get_model_data()
    local refs = model_data and model_data.file_references or nil
    local group = refs and refs.motions and refs.motions[tostring(name)] or nil
    for no = 0, #(group or {}) - 1 do
        pcall(function() self.renderer:load_motion(tostring(name), no) end)
    end
    return self
end

function Renderer:set_expression(name)
    if self.renderer ~= nil then
        pcall(function() self.renderer:set_expression(tostring(name), 1.0) end)
    end
    return self
end

function Renderer:preload_expression(name)
    if self.renderer ~= nil then
        pcall(function() self.renderer:load_expression(tostring(name)) end)
    end
    return self
end

function Renderer:reset_expression()
    if self.renderer ~= nil then self.renderer:clear_expressions() end
    return self
end

function Renderer:apply_texture_quality(_profile)
    return self
end

function Renderer:dispose()
    if self.renderer ~= nil then
        self.renderer:dispose()
    end
    self.renderer = nil
    collectgarbage("collect")
    return true
end

return M
