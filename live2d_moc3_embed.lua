-- live2d_moc3_embed.lua - windowless Cubism 3 model runtime for host apps.
--
-- Hosts can load Cubism 3 model resources from files or memory streams, drive
-- parameters/motions, inspect generated drawable meshes, and optionally render
-- them with live2d.cubism3.opengl_renderer when an OpenGL context is current.

package.path = package.path .. ";./?.lua;./?/init.lua"

local moc3 = require("live2d.cubism3.moc3")
local model3 = require("live2d.cubism3.json.model3")
local motion3 = require("live2d.cubism3.json.motion3")
local expression3 = require("live2d.cubism3.json.expression3")
local pose3 = require("live2d.cubism3.json.pose3")
local physics3 = require("live2d.cubism3.json.physics3")
local ModelRuntime = require("live2d.cubism3.runtime")
local MotionPlayer = require("live2d.cubism3.motion")
local expression_runtime = require("live2d.cubism3.expression")
local Physics = require("live2d.cubism3.physics")

local M = {}
local Renderer = {}
Renderer.__index = Renderer

local current_renderer = nil

local function normalize_path(path)
    return (tostring(path or ""):gsub("\\", "/"))
end

local function dirname(path)
    path = normalize_path(path)
    local dir = path:match("^(.*)/[^/]*$")
    if dir == nil or dir == "" then return "" end
    return dir .. "/"
end

local function join_path(base, path)
    path = normalize_path(path)
    if path == "" then return base end
    if path:match("^%a:[/]") or path:sub(1, 1) == "/" then return path end
    return normalize_path((base or "") .. path)
end

local function read_file(path)
    local file, err = io.open(path, "rb")
    if file == nil then return nil, err end
    local data = file:read("*all")
    file:close()
    return data
end

local function resolve_stream(stream, path)
    if type(stream) == "function" or type(stream) == "userdata" then
        stream = stream(path)
    elseif type(stream) == "table" then
        return stream.data or stream.bytes or stream[1]
    end
    return stream
end

local function assert_parsed(name, value, err)
    if value == nil then
        error("failed to parse " .. name .. ": " .. tostring(err), 3)
    end
    return value
end

local function require_runtime(self)
    if self.runtime == nil then
        error("Cubism3 model is not loaded", 3)
    end
    return self.runtime
end

function Renderer:set_resource_stream(path, data)
    self.resource_streams[normalize_path(path)] = data
    return self
end

function Renderer:set_resource_streams(resource_streams)
    self.resource_streams = {}
    for path, data in pairs(resource_streams or {}) do
        self:set_resource_stream(path, data)
    end
    return self
end

function Renderer:clear_resource_streams()
    self.resource_streams = {}
    return self
end

function Renderer:set_texture_stream(path, data)
    self.texture_streams[normalize_path(path)] = data
    if self.gl_renderer ~= nil and self.gl_renderer.set_texture_stream ~= nil then
        self.gl_renderer:set_texture_stream(path, data)
    end
    return self
end

function Renderer:set_texture_streams(texture_streams)
    self.texture_streams = texture_streams or {}
    if self.gl_renderer ~= nil and self.gl_renderer.set_texture_streams ~= nil then
        self.gl_renderer:set_texture_streams(self.texture_streams)
    end
    return self
end

function Renderer:clear_texture_streams()
    self.texture_streams = {}
    if self.gl_renderer ~= nil and self.gl_renderer.clear_texture_streams ~= nil then
        self.gl_renderer:clear_texture_streams()
    end
    return self
end

function Renderer:read_resource(path)
    path = normalize_path(path)
    local data = resolve_stream(self.resource_streams[path], path)
    if data ~= nil then return data end

    for stream_path, stream in pairs(self.resource_streams) do
        if normalize_path(stream_path) == path then
            data = resolve_stream(stream, path)
            if data ~= nil then return data end
        end
    end

    local loader = self.resource_streams.__loader or self.resource_streams["__loader"]
    data = resolve_stream(loader, path)
    if data ~= nil then return data end

    local err
    data, err = read_file(path)
    if data == nil then
        error("failed to read resource " .. path .. ": " .. tostring(err), 3)
    end
    return data
end

function Renderer:load_model(model_path, opts)
    if model_path == nil or model_path == "" then
        error("model_path is required", 2)
    end

    opts = opts or {}
    if opts.resource_streams or opts.resourceStreams then
        self:set_resource_streams(opts.resource_streams or opts.resourceStreams)
    end
    if opts.texture_streams or opts.textureStreams then
        self:set_texture_streams(opts.texture_streams or opts.textureStreams)
    end

    local normalized_model_path = normalize_path(model_path)
    local base = dirname(normalized_model_path)
    local model_data = assert_parsed("model3.json", model3.parse(self:read_resource(normalized_model_path)))
    local references = model_data.file_references
    local moc_path = join_path(base, references.moc)
    local moc_bytes = self:read_resource(moc_path)

    local pose_data = nil
    if references.pose ~= nil then
        pose_data = assert_parsed("pose3.json", pose3.parse(self:read_resource(join_path(base, references.pose))))
    end

    local physics_data = nil
    if references.physics ~= nil then
        physics_data = assert_parsed(
            "physics3.json", physics3.parse(self:read_resource(join_path(base, references.physics)))
        )
    end

    local canvas = assert_parsed("moc3 canvas", moc3.canvas.parse(moc_bytes))
    local art_meshes = assert_parsed("moc3 art meshes", moc3.art_meshes.parse(moc_bytes))
    local keyforms = assert_parsed("moc3 keyforms", moc3.keyforms.parse(moc_bytes))
    local deformers = assert_parsed("moc3 deformers", moc3.deformers.parse(moc_bytes))
    local bindings = assert_parsed("moc3 keyform bindings", moc3.keyform_bindings.parse(moc_bytes))
    local ids = assert_parsed("moc3 ids", moc3.ids.parse(moc_bytes))
    local offscreen = assert_parsed("moc3 offscreen", moc3.offscreen.parse(moc_bytes))
    local glues = assert_parsed("moc3 glues", moc3.glues.parse(moc_bytes))
    local parts = assert_parsed("moc3 parts", moc3.parts.parse(moc_bytes))
    local draw_order_groups, draw_order_groups_err = moc3.draw_order_groups.parse(moc_bytes)
    if draw_order_groups_err ~= nil then
        error("failed to parse moc3 draw order groups: " .. tostring(draw_order_groups_err), 2)
    end

    local runtime = ModelRuntime.new(model_data, canvas, art_meshes, keyforms, deformers, bindings, ids, offscreen, glues, parts, draw_order_groups, pose_data)
    if runtime == nil then
        error("failed to create Cubism3 runtime", 2)
    end
    if physics_data ~= nil then
        local physics, physics_err = Physics.new(physics_data)
        if physics == nil then error("failed to create Cubism3 physics: " .. tostring(physics_err), 2) end
        runtime:set_physics(physics)
    end

    self.model_path = normalized_model_path
    self.base_path = base
    self.model_data = model_data
    self.runtime = runtime
    self.saved_parameter_values = nil
    self.textures = references.textures or {}
    self.texture_paths = {}
    for i, texture in ipairs(self.textures) do
        self.texture_paths[i] = join_path(base, texture)
    end
    self.motion_cache = {}
    self.active_motions = {}
    self.expression_cache = {}
    self.expression_manager = expression_runtime.ExpressionManager.new()
    return self
end

function Renderer:get_runtime()
    return self.runtime
end

function Renderer:get_model_data()
    return self.model_data
end

function Renderer:get_physics()
    return require_runtime(self):get_physics()
end

function Renderer:get_meshes()
    return require_runtime(self).meshes
end

function Renderer:get_textures()
    return self.textures
end

function Renderer:get_texture_paths()
    return self.texture_paths
end

function Renderer:get_parameter(param_id)
    return require_runtime(self):parameter_value(param_id)
end

function Renderer:get_parameter_by_index(index)
    return require_runtime(self):parameter_value_by_index(tonumber(index) or 0)
end

function Renderer:set_parameter(param_id, value)
    if not require_runtime(self):set_parameter(param_id, tonumber(value) or 0) then
        error("unknown parameter: " .. tostring(param_id), 2)
    end
    return self
end

function Renderer:set_parameter_by_index(index, value)
    if not require_runtime(self):set_parameter_by_index(tonumber(index) or 0, tonumber(value) or 0) then
        error("unknown parameter index: " .. tostring(index), 2)
    end
    return self
end

function Renderer:reset_parameters()
    require_runtime(self):reset_parameters()
    self.saved_parameter_values = nil
    return self
end

function Renderer:get_parameter_info(param_id)
    return require_runtime(self):parameter_info(param_id)
end

function Renderer:get_parameter_info_by_index(index)
    return require_runtime(self):parameter_info_by_index(tonumber(index) or 0)
end

function Renderer:get_parameter_normalized(param_id)
    return require_runtime(self):parameter_normalized_value(param_id)
end

function Renderer:get_parameter_normalized_by_index(index)
    return require_runtime(self):parameter_normalized_value_by_index(tonumber(index) or 0)
end

function Renderer:set_parameter_normalized(param_id, value)
    if not require_runtime(self):set_parameter_normalized(param_id, tonumber(value) or 0) then
        error("unknown parameter: " .. tostring(param_id), 2)
    end
    return self
end

function Renderer:set_parameter_normalized_by_index(index, value)
    if not require_runtime(self):set_parameter_normalized_by_index(tonumber(index) or 0, tonumber(value) or 0) then
        error("unknown parameter index: " .. tostring(index), 2)
    end
    return self
end

function Renderer:set_parameter_override(param_id, value)
    if not require_runtime(self):set_parameter_override(param_id, tonumber(value) or 0) then
        error("unknown parameter: " .. tostring(param_id), 2)
    end
    return self
end

function Renderer:set_parameter_override_by_index(index, value)
    if not require_runtime(self):set_parameter_override_by_index(tonumber(index) or 0, tonumber(value) or 0) then
        error("unknown parameter index: " .. tostring(index), 2)
    end
    return self
end

function Renderer:set_parameter_override_normalized(param_id, value)
    if not require_runtime(self):set_parameter_override_normalized(param_id, tonumber(value) or 0) then
        error("unknown parameter: " .. tostring(param_id), 2)
    end
    return self
end

function Renderer:set_parameter_override_normalized_by_index(index, value)
    if not require_runtime(self):set_parameter_override_normalized_by_index(tonumber(index) or 0, tonumber(value) or 0) then
        error("unknown parameter index: " .. tostring(index), 2)
    end
    return self
end

function Renderer:clear_parameter_override(param_id)
    if not require_runtime(self):clear_parameter_override(param_id) then
        error("unknown parameter: " .. tostring(param_id), 2)
    end
    return self
end

function Renderer:clear_parameter_override_by_index(index)
    if not require_runtime(self):clear_parameter_override_by_index(tonumber(index) or 0) then
        error("unknown parameter index: " .. tostring(index), 2)
    end
    return self
end

function Renderer:clear_parameter_overrides()
    require_runtime(self):clear_parameter_overrides()
    return self
end

function Renderer:set_part_opacity(part_id, value)
    if not require_runtime(self):set_part_opacity(part_id, tonumber(value) or 0) then
        error("unknown part: " .. tostring(part_id), 2)
    end
    return self
end

function Renderer:set_part_opacity_by_index(index, value)
    if not require_runtime(self):set_part_opacity_by_index(tonumber(index) or 0, tonumber(value) or 0) then
        error("unknown part index: " .. tostring(index), 2)
    end
    return self
end

function Renderer:reset_part_opacities()
    require_runtime(self):reset_part_opacities()
    return self
end

function Renderer:load_motion(group, no)
    local references = self.model_data and self.model_data.file_references
    local groups = references and references.motions or {}
    local entry = groups[group]
    if entry == nil then
        error("unknown motion group: " .. tostring(group), 2)
    end

    no = (tonumber(no) or 0) + 1
    local motion_ref = entry[no]
    if motion_ref == nil or motion_ref.File == nil then
        error("unknown motion index: " .. tostring(no - 1), 2)
    end

    local motion_path = join_path(self.base_path, motion_ref.File)
    if self.motion_cache[motion_path] == nil then
        self.motion_cache[motion_path] = assert_parsed("motion3.json", motion3.parse(self:read_resource(motion_path)))
    end
    return self.motion_cache[motion_path]
end

function Renderer:start_motion(group, no, weight, loop)
    local motion = self:load_motion(group, no)
    -- model3.json motion references may override the motion3.json fades
    local reference
    local references = self.model_data and self.model_data.file_references
    local groups = references and references.motions or {}
    local entry = groups[group]
    if entry ~= nil then
        reference = entry[(tonumber(no) or 0) + 1]
    end
    local player = MotionPlayer.new(
        motion,
        loop,
        reference and reference.FadeInTime,
        reference and reference.FadeOutTime
    )
    if weight ~= nil then player:set_weight(tonumber(weight) or 1.0) end
    self.active_motions[#self.active_motions + 1] = player
    return self
end

function Renderer:clear_motions()
    self.active_motions = {}
    return self
end

function Renderer:expression_reference(name_or_index)
    local references = self.model_data and self.model_data.file_references
    local expressions = references and references.expressions or {}
    if type(name_or_index) == "number" then
        return expressions[name_or_index + 1]
    end
    for _, reference in ipairs(expressions) do
        if reference.Name == name_or_index then
            return reference
        end
    end
    return nil
end

function Renderer:load_expression(name_or_index)
    local reference = self:expression_reference(name_or_index)
    if reference == nil or reference.File == nil then
        error("unknown expression: " .. tostring(name_or_index), 2)
    end

    local expression_path = join_path(self.base_path, reference.File)
    if self.expression_cache[expression_path] == nil then
        self.expression_cache[expression_path] = assert_parsed(
            "exp3.json",
            expression3.parse(self:read_resource(expression_path))
        )
    end
    return self.expression_cache[expression_path]
end

function Renderer:set_expression(name_or_index, weight)
    local player = self.expression_manager:play(self:load_expression(name_or_index))
    if weight ~= nil then player:set_weight(tonumber(weight) or 1.0) end
    return self
end

function Renderer:clear_expressions()
    self.expression_manager:clear()
    return self
end

function Renderer:clear_expression()
    return self:clear_expressions()
end

function Renderer:update(delta_seconds)
    local runtime = require_runtime(self)
    delta_seconds = tonumber(delta_seconds) or 0
    -- Restore the motion-driven base pose (SDK LoadParameters) so add-ons
    -- applied after the snapshot below never leak into motion fade blending.
    if self.saved_parameter_values ~= nil then
        runtime:load_parameter_snapshot(self.saved_parameter_values)
    end
    local motions = self.active_motions
    local kept_count = 0
    for i = 1, #motions do
        local player = motions[i]
        player:tick(delta_seconds)
        player:apply(runtime)
        if not player:is_finished() then
            kept_count = kept_count + 1
            motions[kept_count] = player
        end
    end
    for i = kept_count + 1, #motions do
        motions[i] = nil
    end
    self.expression_manager:tick(delta_seconds)
    self.expression_manager:apply(runtime)
    self.saved_parameter_values = runtime:save_parameter_snapshot(self.saved_parameter_values)
    if self.pre_override_hook ~= nil then
        self.pre_override_hook(runtime, delta_seconds)
    end
    runtime:apply_parameter_overrides()
    runtime:update_physics(delta_seconds)
    runtime:apply_pose(delta_seconds)
    runtime:update_meshes()
    return self
end

function Renderer:set_gl(gl)
    self.gl = gl
    self.gl_renderer = nil
    return self
end

function Renderer:get_gl_renderer()
    if self.gl_renderer == nil then
        if self.gl == nil then error("OpenGL table is required", 2) end
        self.gl_renderer = require("live2d.cubism3.opengl_renderer").new(self.gl, {
            texture_streams = self.texture_streams,
        })
    end
    return self.gl_renderer
end

function Renderer:render(projection, texture_paths)
    return self:get_gl_renderer():render_meshes(self:get_meshes(), texture_paths or self:get_texture_paths(), projection)
end

function Renderer:dispose()
    self.runtime = nil
    self.saved_parameter_values = nil
    self.model_data = nil
    self.model_path = nil
    self.base_path = nil
    self.textures = {}
    self.texture_paths = {}
    self.motion_cache = {}
    self.active_motions = {}
    self.expression_cache = {}
    self.expression_manager = expression_runtime.ExpressionManager.new()
    if self.gl_renderer ~= nil and self.gl_renderer.destroy ~= nil then
        pcall(function() self.gl_renderer:destroy() end)
    end
    self.gl_renderer = nil
    collectgarbage("collect")
    return true
end

function M.new(opts)
    opts = opts or {}
    local renderer = setmetatable({
        resource_streams = {},
        texture_streams = {},
        textures = {},
        texture_paths = {},
        motion_cache = {},
        active_motions = {},
        expression_cache = {},
        expression_manager = expression_runtime.ExpressionManager.new(),
        gl = opts.gl,
    }, Renderer)
    renderer:set_resource_streams(opts.resource_streams or opts.resourceStreams or {})
    renderer:set_texture_streams(opts.texture_streams or opts.textureStreams or {})
    if opts.model_path ~= nil then
        renderer:load_model(opts.model_path, opts)
    end
    return renderer
end

function M.load_model(model_path, opts)
    current_renderer = M.new(opts)
    current_renderer:load_model(model_path, opts)
    return current_renderer
end

function M.current()
    return current_renderer
end

function M.update(delta_seconds)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:update(delta_seconds)
end

function M.get_meshes()
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:get_meshes()
end

function M.set_parameter(param_id, value)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:set_parameter(param_id, value)
end

function M.start_motion(group, no, weight, loop)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:start_motion(group, no, weight, loop)
end

function M.clear_motions()
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:clear_motions()
end

function M.set_expression(name_or_index, weight)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:set_expression(name_or_index, weight)
end

function M.clear_expressions()
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:clear_expressions()
end

function M.clear_expression()
    return M.clear_expressions()
end

function M.render(projection, texture_paths)
    if current_renderer == nil then error("no current renderer", 2) end
    return current_renderer:render(projection, texture_paths)
end

function M.dispose()
    if current_renderer ~= nil then
        current_renderer:dispose()
    end
    current_renderer = nil
    return true
end

M.Renderer = Renderer
M.ModelRuntime = ModelRuntime
M.MotionPlayer = MotionPlayer
M.ExpressionPlayer = expression_runtime.ExpressionPlayer
M.ExpressionManager = expression_runtime.ExpressionManager
M.moc3 = moc3
M.model3 = model3
M.motion3 = motion3
M.expression3 = expression3
M.pose3 = pose3
M.physics3 = physics3
M.Physics = Physics

return M
