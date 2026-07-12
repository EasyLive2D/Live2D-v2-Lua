-- Expression player and manager for Cubism 3

local expression3 = require("live2d.cubism3.json.expression3")
local motion3 = require("live2d.cubism3.json.motion3")

local M = {}

local ExpressionPlayer = {}
ExpressionPlayer.__index = ExpressionPlayer

function ExpressionPlayer.new(expression)
    return setmetatable({
        expression = expression,
        time = 0.0,
        weight = 1.0,
        fade_out_started_at = nil,
        finished = false,
        base_values = {},
    }, ExpressionPlayer)
end

function ExpressionPlayer:set_weight(weight)
    self.weight = math.max(0, math.min(1, tonumber(weight) or 0))
end

function ExpressionPlayer:fade_in_weight()
    local fade_in = expression3.resolved_fade_in_time(self.expression)
    if fade_in == 0 then return 1.0 end
    return motion3.easing_sine(self.time / fade_in)
end

function ExpressionPlayer:fade_out_weight()
    if self.fade_out_started_at == nil then return 1.0 end
    local fade_out = expression3.resolved_fade_out_time(self.expression)
    if fade_out == 0 then return 0.0 end
    return motion3.easing_sine((self.fade_out_started_at + fade_out - self.time) / fade_out)
end

function ExpressionPlayer:fade_weight()
    return self.weight * self:fade_in_weight() * self:fade_out_weight()
end

function ExpressionPlayer:is_finished()
    return self.finished
end

function ExpressionPlayer:is_fading_out()
    return self.fade_out_started_at ~= nil
end

function ExpressionPlayer:restart()
    self.time = 0.0
    self.fade_out_started_at = nil
    self.finished = false
    self.base_values = {}
end

function ExpressionPlayer:start_fade_out()
    if self.finished or self.fade_out_started_at ~= nil then return end
    local fade_out = expression3.resolved_fade_out_time(self.expression)
    if fade_out == 0 then
        self.finished = true
    else
        self.fade_out_started_at = self.time
    end
end

function ExpressionPlayer:tick(delta_seconds)
    if self.finished then return end
    self.time = self.time + math.max(0, tonumber(delta_seconds) or 0)
    if self.fade_out_started_at ~= nil then
        local fade_out = expression3.resolved_fade_out_time(self.expression)
        if self.time >= self.fade_out_started_at + fade_out then
            self.finished = true
        end
    end
end

function ExpressionPlayer:apply(runtime)
    if self.finished then return end
    local weight = self:fade_weight()
    for _, parameter in ipairs(self.expression.parameters or {}) do
        local index = runtime:parameter_index_of(parameter.id)
        if index ~= nil then
            local base = self.base_values[index + 1]
            if base == nil then
                base = runtime:parameter_value_by_index(index)
                self.base_values[index + 1] = base
            end
            if base ~= nil then
                runtime:set_parameter_by_index(
                    index,
                    expression3.apply_expression_parameter(base, parameter, weight)
                )
            end
        end
    end
end

local ExpressionManager = {}
ExpressionManager.__index = ExpressionManager

function ExpressionManager.new()
    return setmetatable({ players = {}, base_values = {}, values = {} }, ExpressionManager)
end

local function clear_table(values)
    for key in pairs(values) do values[key] = nil end
end

function ExpressionManager:play(expression)
    if #self.players == 0 then
        clear_table(self.base_values)
    end
    for _, player in ipairs(self.players) do
        player:start_fade_out()
    end
    local player = ExpressionPlayer.new(expression)
    self.players[#self.players + 1] = player
    return player
end

function ExpressionManager:stop_all()
    for _, player in ipairs(self.players) do
        player:start_fade_out()
    end
end

function ExpressionManager:clear()
    clear_table(self.players)
    clear_table(self.base_values)
    clear_table(self.values)
end

function ExpressionManager:tick(delta_seconds)
    local players = self.players
    local kept_count = 0
    for i = 1, #players do
        local player = players[i]
        player:tick(delta_seconds)
        if not player:is_finished() then
            kept_count = kept_count + 1
            players[kept_count] = player
        end
    end
    for i = kept_count + 1, #players do
        players[i] = nil
    end
    if kept_count == 0 then
        clear_table(self.base_values)
        clear_table(self.values)
    end
end

function ExpressionManager:apply(runtime)
    if #self.players == 0 then return end

    local values = self.values
    clear_table(values)
    for _, player in ipairs(self.players) do
        local weight = player:fade_weight()
        for _, parameter in ipairs(player.expression.parameters or {}) do
            local index = runtime:parameter_index_of(parameter.id)
            if index ~= nil then
                local slot = index + 1
                local base = self.base_values[slot]
                if base == nil then
                    base = runtime:parameter_value_by_index(index)
                    self.base_values[slot] = base
                end
                if base ~= nil then
                    local current = values[slot]
                    if current == nil then current = base end
                    values[slot] = expression3.apply_expression_parameter(current, parameter, weight)
                end
            end
        end
    end

    for slot, value in pairs(values) do
        runtime:set_parameter_by_index(slot - 1, value)
    end
end

function ExpressionManager:active_expression_count()
    return #self.players
end

function ExpressionManager:is_empty()
    return #self.players == 0
end

local function load_expression(path)
    local file, err = io.open(path, "rb")
    if file == nil then return nil, err end
    local data = file:read("*all")
    file:close()
    return expression3.parse(data)
end

M.ExpressionPlayer = ExpressionPlayer
M.ExpressionManager = ExpressionManager
M.load_expression = load_expression

return M
