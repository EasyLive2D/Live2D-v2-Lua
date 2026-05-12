local UtSystem = {}

UtSystem.USER_TIME_AUTO = -1
UtSystem.userTimeMSec = UtSystem.USER_TIME_AUTO

local os_clock = os.clock
local function getTimeMSec()
    return os_clock() * 1000
end

function UtSystem.isBigEndian()
    return true
end

function UtSystem.wait(duration)
    local start_time = getTimeMSec()
    while getTimeMSec() - start_time < duration do
    end
end

function UtSystem.getUserTimeMSec()
    if UtSystem.userTimeMSec == UtSystem.USER_TIME_AUTO then
        return UtSystem.getSystemTimeMSec()
    end
    return UtSystem.userTimeMSec
end

function UtSystem.setUserTimeMSec(aH)
    UtSystem.userTimeMSec = aH
end

function UtSystem.updateUserTimeMSec()
    UtSystem.userTimeMSec = UtSystem.getSystemTimeMSec()
    return UtSystem.userTimeMSec
end

UtSystem.getTimeMSec = getTimeMSec
UtSystem.getSystemTimeMSec = getTimeMSec

function UtSystem.arraycopy(aM, aJ, aI, aL, aH)
    for aK = 1, aH do
        aI[aL + aK] = aM[aJ + aK]
    end
end

return UtSystem
