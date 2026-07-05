-- Shared top-left demo selector for motion and expression playback.

local M = {}

local DEFAULT_X = 16
local DEFAULT_Y = 16
local DEFAULT_WIDTH = 300
local DEFAULT_HEIGHT = 42
local DEFAULT_GAP = 12

local GL_QUADS = 0x0007
local GL_BLEND = 0x0BE2
local GL_TEXTURE_2D = 0x0DE1
local GL_ARRAY_BUFFER = 0x8892
local GL_ELEMENT_ARRAY_BUFFER = 0x8893
local GL_SRC_ALPHA = 0x0302
local GL_ONE_MINUS_SRC_ALPHA = 0x0303
local GL_PROJECTION = 0x1701
local GL_MODELVIEW = 0x1700

local FONT = {
    ["A"] = { "01110", "10001", "10001", "11111", "10001", "10001", "10001" },
    ["B"] = { "11110", "10001", "10001", "11110", "10001", "10001", "11110" },
    ["C"] = { "01111", "10000", "10000", "10000", "10000", "10000", "01111" },
    ["D"] = { "11110", "10001", "10001", "10001", "10001", "10001", "11110" },
    ["E"] = { "11111", "10000", "10000", "11110", "10000", "10000", "11111" },
    ["F"] = { "11111", "10000", "10000", "11110", "10000", "10000", "10000" },
    ["G"] = { "01111", "10000", "10000", "10011", "10001", "10001", "01111" },
    ["H"] = { "10001", "10001", "10001", "11111", "10001", "10001", "10001" },
    ["I"] = { "11111", "00100", "00100", "00100", "00100", "00100", "11111" },
    ["J"] = { "00111", "00010", "00010", "00010", "10010", "10010", "01100" },
    ["K"] = { "10001", "10010", "10100", "11000", "10100", "10010", "10001" },
    ["L"] = { "10000", "10000", "10000", "10000", "10000", "10000", "11111" },
    ["M"] = { "10001", "11011", "10101", "10101", "10001", "10001", "10001" },
    ["N"] = { "10001", "11001", "10101", "10011", "10001", "10001", "10001" },
    ["O"] = { "01110", "10001", "10001", "10001", "10001", "10001", "01110" },
    ["P"] = { "11110", "10001", "10001", "11110", "10000", "10000", "10000" },
    ["Q"] = { "01110", "10001", "10001", "10001", "10101", "10010", "01101" },
    ["R"] = { "11110", "10001", "10001", "11110", "10100", "10010", "10001" },
    ["S"] = { "01111", "10000", "10000", "01110", "00001", "00001", "11110" },
    ["T"] = { "11111", "00100", "00100", "00100", "00100", "00100", "00100" },
    ["U"] = { "10001", "10001", "10001", "10001", "10001", "10001", "01110" },
    ["V"] = { "10001", "10001", "10001", "10001", "10001", "01010", "00100" },
    ["W"] = { "10001", "10001", "10001", "10101", "10101", "10101", "01010" },
    ["X"] = { "10001", "10001", "01010", "00100", "01010", "10001", "10001" },
    ["Y"] = { "10001", "10001", "01010", "00100", "00100", "00100", "00100" },
    ["Z"] = { "11111", "00001", "00010", "00100", "01000", "10000", "11111" },
    ["0"] = { "01110", "10001", "10011", "10101", "11001", "10001", "01110" },
    ["1"] = { "00100", "01100", "00100", "00100", "00100", "00100", "01110" },
    ["2"] = { "01110", "10001", "00001", "00010", "00100", "01000", "11111" },
    ["3"] = { "11110", "00001", "00001", "01110", "00001", "00001", "11110" },
    ["4"] = { "00010", "00110", "01010", "10010", "11111", "00010", "00010" },
    ["5"] = { "11111", "10000", "10000", "11110", "00001", "00001", "11110" },
    ["6"] = { "01110", "10000", "10000", "11110", "10001", "10001", "01110" },
    ["7"] = { "11111", "00001", "00010", "00100", "01000", "01000", "01000" },
    ["8"] = { "01110", "10001", "10001", "01110", "10001", "10001", "01110" },
    ["9"] = { "01110", "10001", "10001", "01111", "00001", "00001", "01110" },
    [":"] = { "00000", "00100", "00100", "00000", "00100", "00100", "00000" },
    ["#"] = { "01010", "11111", "01010", "01010", "11111", "01010", "01010" },
    ["_"] = { "00000", "00000", "00000", "00000", "00000", "00000", "11111" },
    ["-"] = { "00000", "00000", "00000", "11111", "00000", "00000", "00000" },
    ["."] = { "00000", "00000", "00000", "00000", "00000", "00100", "00100" },
    ["/"] = { "00001", "00001", "00010", "00100", "01000", "10000", "10000" },
    ["?"] = { "01110", "10001", "00001", "00010", "00100", "00000", "00100" },
}

local Selector = {}
Selector.__index = Selector

local function rect(x, y, width, height)
    return { x = x, y = y, width = width, height = height }
end

local function contains(r, x, y)
    return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

local function item_label(item)
    if item == nil then return nil end
    return item.label or item.name or item.file or tostring(item)
end

local function current_label(items, index, empty_text)
    if #items == 0 then return empty_text end
    if index <= 0 then return "select" end
    return item_label(items[index]) or empty_text
end

local function truncate(text, max_chars)
    if #text <= max_chars then return text end
    if max_chars <= 3 then return string.sub(text, 1, max_chars) end
    return string.sub(text, 1, max_chars - 3) .. "..."
end

function M.new(opts)
    opts = opts or {}
    return setmetatable({
        x = opts.x or DEFAULT_X,
        y = opts.y or DEFAULT_Y,
        width = opts.width or DEFAULT_WIDTH,
        height = opts.height or DEFAULT_HEIGHT,
        gap = opts.gap or DEFAULT_GAP,
        motions = opts.motions or {},
        expressions = opts.expressions or {},
        motion_index = opts.motion_index or 0,
        expression_index = opts.expression_index or 0,
    }, Selector)
end

function Selector:motion_rect()
    return rect(self.x, self.y, self.width, self.height)
end

function Selector:expression_rect()
    return rect(self.x, self.y + self.height + self.gap, self.width, self.height)
end

function Selector:hit_test(x, y)
    x = tonumber(x) or -1
    y = tonumber(y) or -1
    if contains(self:motion_rect(), x, y) then return "motion" end
    if contains(self:expression_rect(), x, y) then return "expression" end
    return nil
end

function Selector:_select_next(items_key, index_key)
    local items = self[items_key]
    if #items == 0 then return nil, nil end
    self[index_key] = self[index_key] % #items + 1
    return items[self[index_key]], self[index_key]
end

function Selector:select_next_motion()
    return self:_select_next("motions", "motion_index")
end

function Selector:select_next_expression()
    return self:_select_next("expressions", "expression_index")
end

function Selector:handle_click(x, y, on_motion, on_expression)
    local hit = self:hit_test(x, y)
    if hit == "motion" then
        local item, index = self:select_next_motion()
        if item ~= nil and on_motion ~= nil then on_motion(item, index) end
        return hit, item, index
    elseif hit == "expression" then
        local item, index = self:select_next_expression()
        if item ~= nil and on_expression ~= nil then on_expression(item, index) end
        return hit, item, index
    end
    return nil
end

function Selector:motion_label()
    return "Motion: " .. current_label(self.motions, self.motion_index, "none")
end

function Selector:expression_label()
    return "Expression: " .. current_label(self.expressions, self.expression_index, "none")
end

local function color(gl, rgba)
    gl.glColor4f(rgba[1] / 255, rgba[2] / 255, rgba[3] / 255, rgba[4] / 255)
end

local function fill_rect(gl, x, y, width, height, rgba)
    color(gl, rgba)
    gl.glBegin(GL_QUADS)
    gl.glVertex2f(x, y)
    gl.glVertex2f(x + width, y)
    gl.glVertex2f(x + width, y + height)
    gl.glVertex2f(x, y + height)
    gl.glEnd()
end

local function draw_text(gl, text, x, y, scale, rgba, max_chars)
    text = truncate(string.upper(text or ""), max_chars)
    local cursor_x = x
    for i = 1, #text do
        local ch = string.sub(text, i, i)
        local glyph = FONT[ch] or FONT["?"]
        if ch ~= " " then
            for row = 1, 7 do
                local bits = glyph[row]
                for col = 1, 5 do
                    if string.sub(bits, col, col) == "1" then
                        fill_rect(gl, cursor_x + (col - 1) * scale, y + (row - 1) * scale, scale, scale, rgba)
                    end
                end
            end
        end
        cursor_x = cursor_x + 6 * scale
    end
end

function Selector:_draw_button(gl, button_rect, label, enabled)
    local bg = enabled and { 46, 65, 78, 235 } or { 46, 50, 54, 210 }
    local border = enabled and { 76, 149, 208, 245 } or { 96, 100, 104, 220 }
    local text = enabled and { 232, 238, 242, 255 } or { 176, 184, 190, 255 }
    local scale = 2
    local text_height = 7 * scale
    local max_chars = math.floor((button_rect.width - 24) / (6 * scale))

    fill_rect(gl, button_rect.x, button_rect.y, button_rect.width, button_rect.height, bg)
    fill_rect(gl, button_rect.x, button_rect.y, button_rect.width, 2, border)
    fill_rect(gl, button_rect.x, button_rect.y + button_rect.height - 2, button_rect.width, 2, border)
    fill_rect(gl, button_rect.x, button_rect.y, 2, button_rect.height, border)
    fill_rect(gl, button_rect.x + button_rect.width - 2, button_rect.y, 2, button_rect.height, border)
    draw_text(gl, label, button_rect.x + 12, button_rect.y + (button_rect.height - text_height) / 2, scale, text, max_chars)
end

function Selector:draw(gl, width, height)
    if gl == nil or gl.glBegin == nil or gl.glMatrixMode == nil then return false end
    width = tonumber(width) or 0
    height = tonumber(height) or 0
    if width <= 0 or height <= 0 then return false end

    if gl.glUseProgram then gl.glUseProgram(0) end
    if gl.glBindBuffer then
        gl.glBindBuffer(GL_ARRAY_BUFFER, 0)
        gl.glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0)
    end
    gl.glDisable(GL_TEXTURE_2D)
    gl.glEnable(GL_BLEND)
    gl.glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    gl.glMatrixMode(GL_PROJECTION)
    gl.glPushMatrix()
    gl.glLoadIdentity()
    gl.glOrtho(0, width, height, 0, -1, 1)
    gl.glMatrixMode(GL_MODELVIEW)
    gl.glPushMatrix()
    gl.glLoadIdentity()

    self:_draw_button(gl, self:motion_rect(), self:motion_label(), #self.motions > 0)
    self:_draw_button(gl, self:expression_rect(), self:expression_label(), #self.expressions > 0)

    gl.glPopMatrix()
    gl.glMatrixMode(GL_PROJECTION)
    gl.glPopMatrix()
    gl.glMatrixMode(GL_MODELVIEW)
    return true
end

M.Selector = Selector

return M
