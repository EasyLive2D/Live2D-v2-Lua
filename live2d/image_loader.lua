-- Minimal image loader using Windows GDI+ via FFI
-- Falls back to creating a dummy texture if loading fails

local ffi = require("ffi")

ffi.cdef[[
    typedef void* GpImage;
    typedef void* GpBitmap;
    typedef void* GpGraphics;
    typedef struct { int X, Y, Width, Height; } GpRect;
    int GdipLoadImageFromFile(const wchar_t* filename, GpImage** image);
    int GdipGetImageWidth(GpImage* image, unsigned int* width);
    int GdipGetImageHeight(GpImage* image, unsigned int* height);
    int GdipCreateBitmapFromScan0(int width, int height, int stride, int format, void* scan0, GpBitmap** bitmap);
    int GdipBitmapLockBits(GpBitmap* bitmap, const GpRect* rect, unsigned int flags, int format, void* lockedBitmapData);
    int GdipBitmapUnlockBits(GpBitmap* bitmap, void* lockedBitmapData);
    int GdipDisposeImage(GpImage* image);
    
    typedef struct {
        unsigned int Width;
        unsigned int Height;
        int Stride;
        int PixelFormat;
        void* Scan0;
        uintptr_t Reserved;
    } BitmapData;
    
    int GdipGetImageGraphicsContext(GpImage* image, GpGraphics** graphics);
    int GdipDrawImageRectI(GpGraphics* graphics, GpImage* image, int x, int y, int width, int height);
    int GdipDeleteGraphics(GpGraphics* graphics);
    
    // GDI+ startup
    typedef unsigned long ULONG_PTR;
    typedef struct {
        unsigned int GdiplusVersion;
        void* DebugEventCallback;
        int SuppressBackgroundThread;
        int SuppressExternalCodecs;
    } GdiplusStartupInput;
    
    int GdiplusStartup(ULONG_PTR* token, const GdiplusStartupInput* input, void* output);
    void GdiplusShutdown(ULONG_PTR token);
]]

local gdi = ffi.load("gdiplus")

local gdiToken = nil

local function initGDI()
    if gdiToken then return end
    local input = ffi.new("GdiplusStartupInput")
    input.GdiplusVersion = 1
    local token = ffi.new("ULONG_PTR[1]")
    local status = gdi.GdiplusStartup(token, input, nil)
    if status ~= 0 then
        error("GdiplusStartup failed: " .. status)
    end
    gdiToken = token[0]
end

local function createDummyTexture(w, h)
    local data = ffi.new("uint8_t[?]", w * h * 4)
    for i = 0, w * h * 4 - 1 do
        data[i] = 0xFF
    end
    return w, h, data
end

local M = {}

-- Load image and return width, height, pixel data (RGBA, bottom-up)
function M.loadImage(path)
    initGDI()
    
    -- Convert path to wide string
    local widePath = {}
    for c in path:gmatch(".") do
        widePath[#widePath + 1] = ffi.cast("wchar_t", string.byte(c))
    end
    widePath[#widePath + 1] = 0
    local wstr = ffi.new("wchar_t[?]", #widePath)
    for i = 1, #widePath do
        wstr[i - 1] = widePath[i]
    end

    local imgPtr = ffi.new("GpImage*[1]")
    local status = gdi.GdipLoadImageFromFile(wstr, imgPtr)
    if status ~= 0 then
        print("GDI+ load failed for: " .. path .. " (err:" .. status .. ")")
        return createDummyTexture(4, 4)
    end

    local img = imgPtr[0]
    local w = ffi.new("unsigned int[1]")
    local h = ffi.new("unsigned int[1]")
    gdi.GdipGetImageWidth(img, w)
    gdi.GdipGetImageHeight(img, h)
    local width = tonumber(w[0])
    local height = tonumber(h[0])

    -- Create bitmap in RGBA format (PixelFormat32bppARGB = 2498570)
    local PixelFormat32bppARGB = 2498570
    local bitmapPtr = ffi.new("GpBitmap*[1]")
    status = gdi.GdipCreateBitmapFromScan0(width, height, 0, PixelFormat32bppARGB, nil, bitmapPtr)
    if status ~= 0 then
        gdi.GdipDisposeImage(img)
        print("Failed to create bitmap")
        return createDummyTexture(width, height)
    end

    local bmp = bitmapPtr[0]
    local gfxPtr = ffi.new("GpGraphics*[1]")
    gdi.GdipGetImageGraphicsContext(bmp, gfxPtr)
    local gfx = gfxPtr[0]
    gdi.GdipDrawImageRectI(gfx, img, 0, 0, width, height)
    gdi.GdipDeleteGraphics(gfx)
    gdi.GdipDisposeImage(img)

    -- Lock bits to get pixel data
    local rect = ffi.new("GpRect")
    rect.X = 0; rect.Y = 0; rect.Width = width; rect.Height = height
    local bmpData = ffi.new("BitmapData")
    gdi.GdipBitmapLockBits(bmp, rect, 3, PixelFormat32bppARGB, bmpData)  -- 3 = ImageLockModeRead

    -- GDI+ ARGB is BGRA in memory. Need to convert to RGBA for OpenGL
    local pixelCount = width * height
    local data = ffi.new("uint8_t[?]", pixelCount * 4)
    local src = ffi.cast("uint8_t*", bmpData.Scan0)
    for i = 0, pixelCount - 1 do
        data[i * 4] = src[i * 4 + 2]     -- R ← B
        data[i * 4 + 1] = src[i * 4 + 1] -- G ← G
        data[i * 4 + 2] = src[i * 4]     -- B ← R
        data[i * 4 + 3] = src[i * 4 + 3] -- A ← A
    end

    gdi.GdipBitmapUnlockBits(bmp, bmpData)
    gdi.GdipDisposeImage(bmp)

    print("Loaded texture " .. path .. " (" .. width .. "x" .. height .. ")")
    return width, height, data
end

return M
