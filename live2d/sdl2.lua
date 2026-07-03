-- SDL2 FFI binding for LuaJIT
-- Minimal wrapper for window creation, OpenGL context, and event handling

local ffi = require("ffi")
local is_win = ffi.os == "Windows"

ffi.cdef[[
    // SDL types
    typedef struct SDL_Window SDL_Window;
    typedef void *SDL_GLContext;
    typedef uint32_t SDL_GLContextFlag;
    typedef uint32_t SDL_GLattr;
    typedef uint32_t SDL_GLprofile;
    
    typedef struct {
        uint32_t type;
        uint32_t timestamp;
    } SDL_CommonEvent;
    
    typedef struct {
        uint32_t scancode;
        int32_t sym;
        uint16_t mod;
    } SDL_Keysym;
    
    typedef struct {
        uint32_t type;
        uint32_t timestamp;
        uint32_t windowID;
        uint8_t state;
        uint8_t repeat;
        uint8_t padding2[2];
        SDL_Keysym keysym;
    } SDL_KeyboardEvent;
    
    typedef struct {
        uint32_t type;
        uint32_t timestamp;
        uint32_t windowID;
        uint32_t which;
        uint8_t button;
        uint8_t state;
        uint8_t clicks;
        uint8_t padding1;
        int32_t x;
        int32_t y;
    } SDL_MouseButtonEvent;
    
    typedef struct {
        uint32_t type;
        uint32_t timestamp;
        uint32_t windowID;
        uint32_t which;
        uint32_t state;
        int32_t x;
        int32_t y;
        int32_t xrel;
        int32_t yrel;
    } SDL_MouseMotionEvent;
    
    typedef struct {
        uint32_t type;
        uint32_t timestamp;
        uint32_t windowID;
        uint8_t event;
        uint8_t padding1;
        uint8_t padding2;
        uint8_t padding3;
        int32_t data1;
        int32_t data2;
    } SDL_WindowEvent;
    
    typedef struct {
        uint32_t type;
        uint32_t timestamp;
    } SDL_QuitEvent;
    
    typedef union {
        uint32_t type;
        SDL_CommonEvent common;
        SDL_KeyboardEvent key;
        SDL_MouseButtonEvent button;
        SDL_MouseMotionEvent motion;
        SDL_WindowEvent window;
        SDL_QuitEvent quit;
        uint8_t padding[56];
    } SDL_Event;

    // SDL functions
    int SDL_Init(uint32_t flags);
    void SDL_Quit(void);
    const char *SDL_GetError(void);
    int SDL_GL_SetAttribute(SDL_GLattr attr, int value);
    
    SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, uint32_t flags);
    void SDL_DestroyWindow(SDL_Window *window);
    
    SDL_GLContext SDL_GL_CreateContext(SDL_Window *window);
    void SDL_GL_DeleteContext(SDL_GLContext context);
    int SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context);
    int SDL_GL_SetSwapInterval(int interval);
    void SDL_GL_SwapWindow(SDL_Window *window);
    void SDL_GL_GetDrawableSize(SDL_Window *window, int *w, int *h);
    
    int SDL_PollEvent(SDL_Event *event);
    uint32_t SDL_GetTicks(void);
    void SDL_Delay(uint32_t ms);
    void SDL_GetWindowSize(SDL_Window *window, int *w, int *h);
    uint32_t SDL_GetMouseState(int *x, int *y);
]]

if is_win then
    ffi.cdef[[
        typedef void *DPI_AWARENESS_CONTEXT;
        int SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT value);
        int SetProcessDPIAware(void);
    ]]
end

local sdl
local user32

-- Try common SDL2 library names across platforms. macOS Homebrew on Apple
-- Silicon installs to /opt/homebrew/lib, which is NOT in dyld's default
-- fallback search path, so the full path must be listed explicitly.
local sdl_names
if ffi.os == "OSX" then
    sdl_names = {
        "SDL2",
        "/opt/homebrew/lib/libSDL2.dylib",         -- Homebrew (Apple Silicon)
        "/usr/local/lib/libSDL2.dylib",            -- Homebrew (Intel)
        "/opt/local/lib/libSDL2.dylib",            -- MacPorts
        "/Library/Frameworks/SDL2.framework/SDL2", -- System-wide framework
        "libSDL2-2.0.0.dylib",
    }
    local home = os.getenv("HOME")
    if home then
        sdl_names[#sdl_names + 1] = home .. "/Library/Frameworks/SDL2.framework/SDL2"
    end
else
    sdl_names = { "SDL2", "SDL2-2.0", "libSDL2-2.0.so.0" }
end
for _, name in ipairs(sdl_names) do
    local ok, lib = pcall(ffi.load, name)
    if ok then
        sdl = lib
        break
    end
end
if sdl == nil then
    error("Cannot load SDL2 library. Tried: " .. table.concat(sdl_names, ", "))
end

if is_win then
    pcall(function() user32 = ffi.load("user32") end)
end

-- Init flags
local SDL_INIT_VIDEO = 0x00000020

-- Window flags
local SDL_WINDOW_OPENGL = 0x00000002
local SDL_WINDOW_SHOWN = 0x00000004
local SDL_WINDOW_RESIZABLE = 0x00000020
local SDL_WINDOW_ALLOW_HIGHDPI = 0x00002000

-- GL attributes
local SDL_GL_CONTEXT_MAJOR_VERSION = 17
local SDL_GL_CONTEXT_MINOR_VERSION = 18
local SDL_GL_CONTEXT_PROFILE_MASK = 19
local SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 2
local SDL_GL_DOUBLEBUFFER = 5
local SDL_GL_STENCIL_SIZE = 7

-- Event types
local SDL_QUIT = 0x100
local SDL_WINDOWEVENT = 0x200
local SDL_KEYDOWN = 0x300
local SDL_MOUSEBUTTONDOWN = 0x401

-- Window event types
local SDL_WINDOWEVENT_SIZE_CHANGED = 6

-- Keycodes
local SDLK_ESCAPE = 27

local M = {}

function M.enableDPIAwareness()
    if not is_win or not user32 then return false end

    local ok, enabled = pcall(function()
        -- DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
        return user32.SetProcessDpiAwarenessContext(ffi.cast("DPI_AWARENESS_CONTEXT", -4)) ~= 0
    end)
    if ok and enabled then return true end

    ok, enabled = pcall(function()
        return user32.SetProcessDPIAware() ~= 0
    end)
    return ok and enabled or false
end

function M.init()
    local initStatus = sdl.SDL_Init(SDL_INIT_VIDEO)
    if initStatus ~= 0 then
        error("SDL_Init failed: " .. ffi.string(sdl.SDL_GetError()))
    end
end

function M.quit()
    sdl.SDL_Quit()
end

function M.createWindow(title, width, height, allowHighDPI)
    sdl.SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8)
    local flags = bit.bor(SDL_WINDOW_OPENGL, SDL_WINDOW_SHOWN, SDL_WINDOW_RESIZABLE)
    if allowHighDPI then
        flags = bit.bor(flags, SDL_WINDOW_ALLOW_HIGHDPI)
    end
    local win = sdl.SDL_CreateWindow(title, 0x1FFF0000, 0x1FFF0000, width, height, flags)
    if win == nil then
        error("SDL_CreateWindow failed: " .. ffi.string(sdl.SDL_GetError()))
    end
    return win
end

function M.destroyWindow(win)
    sdl.SDL_DestroyWindow(win)
end

function M.createGLContext(win)
    local ctx = sdl.SDL_GL_CreateContext(win)
    if ctx == nil then
        error("SDL_GL_CreateContext failed: " .. ffi.string(sdl.SDL_GetError()))
    end
    return ctx
end

function M.deleteGLContext(ctx)
    sdl.SDL_GL_DeleteContext(ctx)
end

function M.makeCurrent(win, ctx)
    sdl.SDL_GL_MakeCurrent(win, ctx)
end

function M.setSwapInterval(interval)
    sdl.SDL_GL_SetSwapInterval(interval)
end

function M.swapWindow(win)
    sdl.SDL_GL_SwapWindow(win)
end

function M.pollEvent()
    local evt = ffi.new("SDL_Event[1]")
    local hasEvent = sdl.SDL_PollEvent(evt) ~= 0
    if hasEvent then
        return evt[0]
    end
    return nil
end

function M.getTicks()
    return tonumber(sdl.SDL_GetTicks())
end

function M.delay(ms)
    sdl.SDL_Delay(ms)
end

function M.getMouseState()
    local mouseX = ffi.new("int[1]")
    local mouseY = ffi.new("int[1]")
    sdl.SDL_GetMouseState(mouseX, mouseY)
    return mouseX[0], mouseY[0]
end

function M.getDrawableSize(win)
    local width = ffi.new("int[1]")
    local height = ffi.new("int[1]")
    sdl.SDL_GL_GetDrawableSize(win, width, height)
    return tonumber(width[0]), tonumber(height[0])
end

-- Exports
M.SDL_QUIT = SDL_QUIT
M.SDL_WINDOWEVENT = SDL_WINDOWEVENT
M.SDL_KEYDOWN = SDL_KEYDOWN
M.SDL_MOUSEBUTTONDOWN = SDL_MOUSEBUTTONDOWN
M.SDL_WINDOWEVENT_SIZE_CHANGED = SDL_WINDOWEVENT_SIZE_CHANGED
M.SDLK_ESCAPE = SDLK_ESCAPE

return M
