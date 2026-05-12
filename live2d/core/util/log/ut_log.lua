local M = {}

local RESET = "\27[0m"
local RED = "\27[31m"
local GREEN = "\27[32m"
local YELLOW = "\27[33m"
local BLUE = "\27[34m"
local MAGENTA = "\27[35m"
local CYAN = "\27[36m"
local WHITE = "\27[37m"

local enable = true

function M.setLogEnable(v)
    enable = v
end

function M.logEnable()
    return enable
end

local function timestamp()
    return os.date("%H:%M:%S")
end

function M.Debug(...)
    if enable then
        io.write(BLUE .. "[DEBUG " .. timestamp() .. "] ")
        io.write(table.concat({...}, " "))
        io.write(RESET .. "\n")
    end
end

function M.Info(...)
    if enable then
        io.write("[INFO " .. timestamp() .. "] ")
        io.write(table.concat({...}, " "))
        io.write("\n")
    end
end

function M.Error(...)
    if enable then
        io.write(RED .. "[ERROR " .. timestamp() .. "] ")
        io.write(table.concat({...}, " "))
        io.write(RESET .. "\n")
    end
end

return M
