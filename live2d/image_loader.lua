local ffi = require("ffi")
local is_win = ffi.os == "Windows"

if is_win then
    -- Windows: GDI+ path
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

    function M.loadImage(path)
        initGDI()

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

        local rect = ffi.new("GpRect")
        rect.X = 0; rect.Y = 0; rect.Width = width; rect.Height = height
        local bmpData = ffi.new("BitmapData")
        gdi.GdipBitmapLockBits(bmp, rect, 3, PixelFormat32bppARGB, bmpData)

        local pixelCount = width * height
        local data = ffi.new("uint8_t[?]", pixelCount * 4)
        local src = ffi.cast("uint8_t*", bmpData.Scan0)
        for i = 0, pixelCount - 1 do
            data[i * 4] = src[i * 4 + 2]
            data[i * 4 + 1] = src[i * 4 + 1]
            data[i * 4 + 2] = src[i * 4]
            data[i * 4 + 3] = src[i * 4 + 3]
        end

        gdi.GdipBitmapUnlockBits(bmp, bmpData)
        gdi.GdipDisposeImage(bmp)

        print("Loaded texture " .. path .. " (" .. width .. "x" .. height .. ")")
        return width, height, data
    end

    return M

else
    -- Linux / macOS: Pure Lua PNG decoder using zlib via FFI

    ffi.cdef[[
        typedef struct z_stream_s {
            const unsigned char *next_in;
            unsigned int avail_in;
            unsigned long total_in;
            unsigned char *next_out;
            unsigned int avail_out;
            unsigned long total_out;
            const char *msg;
            void *state;
            void *(*zalloc)(void *opaque, unsigned int items, unsigned int size);
            void (*zfree)(void *opaque, void *address);
            void *opaque;
            int data_type;
            unsigned long adler;
            unsigned long reserved;
        } z_stream;

        int inflateInit2_(z_stream *strm, int windowBits, const char *version, int stream_size);
        int inflate(z_stream *strm, int flush);
        int inflateEnd(z_stream *strm);
    ]]

    local zlib = ffi.load("z")

    local M = {}

    local function readBE4(bytes, pos)
        local a, b, c, d = string.byte(bytes, pos, pos + 3)
        return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
    end

    local function createDummyTexture(w, h)
        local data = ffi.new("uint8_t[?]", w * h * 4)
        for i = 0, w * h * 4 - 1 do
            data[i] = 0xFF
        end
        return w, h, data
    end

    local function inflateZlib(compressed)
        local strm = ffi.new("z_stream")
        local ret = zlib.inflateInit2_(strm, 15 + 32, "1.2.13", ffi.sizeof(strm))
        if ret ~= 0 then
            error("inflateInit2_ failed: " .. ret)
        end

        strm.next_in = ffi.cast("const unsigned char *", compressed)
        strm.avail_in = #compressed

        local chunks = {}
        local bufferSize = 65536

        repeat
            local outBuf = ffi.new("uint8_t[?]", bufferSize)
            strm.next_out = outBuf
            strm.avail_out = bufferSize
            ret = zlib.inflate(strm, 0) -- Z_NO_FLUSH
            if ret < 0 then
                zlib.inflateEnd(strm)
                error("inflate error: " .. ret)
            end
            local written = bufferSize - strm.avail_out
            if written > 0 then
                chunks[#chunks + 1] = ffi.string(outBuf, written)
            end
        until ret == 1 -- Z_STREAM_END
        zlib.inflateEnd(strm)

        if ret ~= 1 then
            error("inflate failed: " .. ret)
        end

        return table.concat(chunks)
    end

    local function paethPredictor(a, b, c)
        local p = a + b - c
        local pa = math.abs(p - a)
        local pb = math.abs(p - b)
        local pc = math.abs(p - c)
        if pa <= pb and pa <= pc then return a end
        if pb <= pc then return b end
        return c
    end

    local function applyFilters(raw, width, height, bytesPerPixel)
        local rowBytes = width * bytesPerPixel
        local out = ffi.new("uint8_t[?]", rowBytes)
        local prevRow = ffi.new("uint8_t[?]", rowBytes) -- previous row output
        local unfiltered = {}
        local pos = 0

        for y = 0, height - 1 do
            local filterType = string.byte(raw, pos + 1)
            pos = pos + 1

            local filtered = {}
            for x = 0, rowBytes - 1 do
                filtered[x] = string.byte(raw, pos + 1 + x)
            end
            pos = pos + rowBytes

            if filterType == 0 then
                -- None
                for x = 0, rowBytes - 1 do
                    out[x] = filtered[x]
                end
            elseif filterType == 1 then
                -- Sub: out[x] = filtered[x] + out[x - bpp]
                for x = 0, rowBytes - 1 do
                    local left = (x >= bytesPerPixel) and out[x - bytesPerPixel] or 0
                    out[x] = (filtered[x] + left) % 256
                end
            elseif filterType == 2 then
                -- Up: out[x] = filtered[x] + prevRow[x]
                for x = 0, rowBytes - 1 do
                    out[x] = (filtered[x] + prevRow[x]) % 256
                end
            elseif filterType == 3 then
                -- Average: out[x] = filtered[x] + floor((out[x - bpp] + prevRow[x]) / 2)
                for x = 0, rowBytes - 1 do
                    local left = (x >= bytesPerPixel) and out[x - bytesPerPixel] or 0
                    local avg = math.floor((left + prevRow[x]) / 2)
                    out[x] = (filtered[x] + avg) % 256
                end
            elseif filterType == 4 then
                -- Paeth: a = out[x - bpp], b = prevRow[x], c = prevRow[x - bpp]
                for x = 0, rowBytes - 1 do
                    local a = (x >= bytesPerPixel) and out[x - bytesPerPixel] or 0
                    local b = prevRow[x]
                    local c = (x >= bytesPerPixel) and prevRow[x - bytesPerPixel] or 0
                    out[x] = (filtered[x] + paethPredictor(a, b, c)) % 256
                end
            else
                -- Unknown filter: copy raw bytes
                print("Warning: unknown PNG filter " .. filterType)
                for x = 0, rowBytes - 1 do
                    out[x] = filtered[x]
                end
            end

            -- Build output string and save for next row's "Up" reference
            local rowStr = {}
            for x = 0, rowBytes - 1 do
                rowStr[#rowStr + 1] = string.char(out[x])
                prevRow[x] = out[x]
            end
            unfiltered[y + 1] = table.concat(rowStr)
        end

        return table.concat(unfiltered)
    end

    local function decodePNG(path)
        local f = io.open(path, "rb")
        if not f then
            error("Cannot open file: " .. path)
        end
        local raw = f:read("*all")
        f:close()

        -- Verify PNG signature
        local sig = { string.byte(raw, 1, 8) }
        if sig[1] ~= 137 or sig[2] ~= 80 or sig[3] ~= 78 or sig[4] ~= 71
            or sig[5] ~= 13 or sig[6] ~= 10 or sig[7] ~= 26 or sig[8] ~= 10 then
            error(path .. " is not a valid PNG file")
        end

        local width, height, bitDepth, colorType, interlace
        local idatChunks = {}
        local palette = {}
        local pos = 9

        while pos <= #raw do
            local length = readBE4(raw, pos)
            pos = pos + 4
            local chunkType = raw:sub(pos, pos + 3)
            pos = pos + 4
            local chunkData = raw:sub(pos, pos + length - 1)
            pos = pos + length
            pos = pos + 4 -- CRC

            if chunkType == "IHDR" then
                width = readBE4(chunkData, 1)
                height = readBE4(chunkData, 5)
                bitDepth = string.byte(chunkData, 9)
                colorType = string.byte(chunkData, 10)
                interlace = string.byte(chunkData, 13)
            elseif chunkType == "IDAT" then
                idatChunks[#idatChunks + 1] = chunkData
            elseif chunkType == "PLTE" then
                for i = 0, length / 3 - 1 do
                    local r = string.byte(chunkData, i * 3 + 1)
                    local g = string.byte(chunkData, i * 3 + 2)
                    local b = string.byte(chunkData, i * 3 + 3)
                    palette[i] = { r, g, b }
                end
            elseif chunkType == "tRNS" then
                -- Transparency chunk
                if colorType == 3 then
                    for i = 1, length do
                        palette[i - 1][4] = string.byte(chunkData, i)
                    end
                elseif colorType == 0 then
                    -- Grayscale: 2-byte big-endian gray value that maps to transparent
                    palette._tRNS_gray = string.byte(chunkData, 1) * 256 + string.byte(chunkData, 2)
                elseif colorType == 2 then
                    -- RGB: 2 bytes per channel big-endian
                    palette._tRNS_r = string.byte(chunkData, 1) * 256 + string.byte(chunkData, 2)
                    palette._tRNS_g = string.byte(chunkData, 3) * 256 + string.byte(chunkData, 4)
                    palette._tRNS_b = string.byte(chunkData, 5) * 256 + string.byte(chunkData, 6)
                end
            elseif chunkType == "IEND" then
                break
            end
        end

        if not width or not height then
            error("PNG missing IHDR: " .. path)
        end

        local compressed = table.concat(idatChunks)
        local rawImage = inflateZlib(compressed)

        -- Even for 16-bit PNGs, we only handle the simplified case
        -- Most Live2D textures are 8-bit

        -- For now, only handle 8-bit color types
        if bitDepth ~= 8 then
            print("Warning: bit depth " .. bitDepth .. " not supported, using dummy for " .. path)
            return createDummyTexture(width, height)
        end

        -- Interlaced images are more complex; skip for now
        if interlace ~= 0 then
            print("Warning: interlaced PNG not supported, using dummy for " .. path)
            return createDummyTexture(width, height)
        end

        local bytesPerPixel
        if colorType == 0 then
            -- Grayscale
            bytesPerPixel = 1
        elseif colorType == 2 then
            -- RGB
            bytesPerPixel = 3
        elseif colorType == 3 then
            -- Indexed
            bytesPerPixel = 1
        elseif colorType == 4 then
            -- Grayscale + Alpha
            bytesPerPixel = 2
        elseif colorType == 6 then
            -- RGBA
            bytesPerPixel = 4
        else
            error("Unsupported PNG color type: " .. colorType)
        end

        -- Check if tRNS applies for RGB (colorType 2)
        local hasTRNS = palette._tRNS_r ~= nil or palette._tRNS_gray ~= nil

        local imageData
        if colorType == 6 then
            -- RGBA: no conversion needed
            imageData = applyFilters(rawImage, width, height, bytesPerPixel)
        elseif colorType == 2 then
            -- RGB → RGBA
            local filtered = applyFilters(rawImage, width, height, bytesPerPixel)
            local rgba = {}
            local tr, tg, tb = palette._tRNS_r, palette._tRNS_g, palette._tRNS_b
            for i = 1, #filtered, 3 do
                local r = string.byte(filtered, i)
                local g = string.byte(filtered, i + 1)
                local b = string.byte(filtered, i + 2)
                local a = 255
                if hasTRNS and r == tr and g == tg and b == tb then
                    a = 0
                end
                rgba[#rgba + 1] = string.char(r, g, b, a)
            end
            imageData = table.concat(rgba)
        elseif colorType == 0 then
            -- Grayscale → RGBA
            local filtered = applyFilters(rawImage, width, height, bytesPerPixel)
            local rgba = {}
            local transparentGray = palette._tRNS_gray
            for i = 1, #filtered do
                local v = string.byte(filtered, i)
                local a = 255
                if hasTRNS and v == transparentGray then
                    a = 0
                end
                rgba[#rgba + 1] = string.char(v, v, v, a)
            end
            imageData = table.concat(rgba)
        elseif colorType == 3 then
            -- Indexed → RGBA
            local filtered = applyFilters(rawImage, width, height, bytesPerPixel)
            local rgba = {}
            for i = 1, #filtered do
                local idx = string.byte(filtered, i)
                local entry = palette[idx]
                if not entry then
                    -- Invalid palette index
                    rgba[#rgba + 1] = string.char(0, 0, 0, 0)
                else
                    local r = entry[1] or 0
                    local g = entry[2] or 0
                    local b = entry[3] or 0
                    local a = entry[4] or 255
                    rgba[#rgba + 1] = string.char(r, g, b, a)
                end
            end
            imageData = table.concat(rgba)
        elseif colorType == 4 then
            -- Grayscale + Alpha → RGBA
            local filtered = applyFilters(rawImage, width, height, bytesPerPixel)
            local rgba = {}
            for i = 1, #filtered, 2 do
                local v = string.byte(filtered, i)
                local a = string.byte(filtered, i + 1)
                rgba[#rgba + 1] = string.char(v, v, v, a)
            end
            imageData = table.concat(rgba)
        end

        -- Copy to FFI cdata (uint8_t*) for return
        local data = ffi.new("uint8_t[?]", width * height * 4)
        for i = 0, width * height * 4 - 1 do
            data[i] = string.byte(imageData, i + 1)
        end

        print("Loaded texture " .. path .. " (" .. width .. "x" .. height .. ")")
        return width, height, data
    end

    function M.loadImage(path)
        local ok, w, h, data = pcall(decodePNG, path)
        if not ok then
            print("PNG load failed for: " .. path .. " (" .. tostring(w) .. ")")
            return createDummyTexture(4, 4)
        end
        return w, h, data
    end

    return M
end
