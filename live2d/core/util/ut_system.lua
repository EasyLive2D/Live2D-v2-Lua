local UtSystem = {}

UtSystem.USER_TIME_AUTO = -1
UtSystem.userTimeMSec = UtSystem.USER_TIME_AUTO

local os_clock = os.clock
local getTimeMSec

local ok_ffi, ffi = pcall(require, "ffi")
if ok_ffi and ffi.os == "Linux" then
    local ok_cdef = pcall(ffi.cdef, [[
        typedef long time_t;
        struct timespec {
            time_t tv_sec;
            long tv_nsec;
        };
        int clock_gettime(int clk_id, struct timespec *tp);
    ]])

    if ok_cdef then
        local CLOCK_MONOTONIC = 1
        local ts = ffi.new("struct timespec[1]")
        getTimeMSec = function()
            if ffi.C.clock_gettime(CLOCK_MONOTONIC, ts) == 0 then
                return tonumber(ts[0].tv_sec) * 1000 + tonumber(ts[0].tv_nsec) / 1000000
            end
            return os_clock() * 1000
        end
    else
        getTimeMSec = function()
            return os_clock() * 1000
        end
    end
else
    getTimeMSec = function()
        return os_clock() * 1000
    end
end

function UtSystem.getUserTimeMSec()
    if UtSystem.userTimeMSec == UtSystem.USER_TIME_AUTO then
        return UtSystem.getSystemTimeMSec()
    end
    return UtSystem.userTimeMSec
end

UtSystem.getSystemTimeMSec = getTimeMSec

function UtSystem.arraycopy(aM, aJ, aI, aL, aH)
    for aK = 1, aH do
        aI[aL + aK] = aM[aJ + aK]
    end
end

return UtSystem
