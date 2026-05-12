local UtSystem = require("live2d.core.util.ut_system")

local EyeState = {
    STATE_FIRST = "STATE_FIRST",
    STATE_INTERVAL = "STATE_INTERVAL",
    STATE_CLOSING = "STATE_CLOSING",
    STATE_CLOSED = "STATE_CLOSED",
    STATE_OPENING = "STATE_OPENING",
}

local L2DEyeBlink = {}
L2DEyeBlink.__index = L2DEyeBlink

function L2DEyeBlink.new()
    local self = setmetatable({}, L2DEyeBlink)
    self.nextBlinkTime = nil
    self.stateStartTime = nil
    self.blinkIntervalMsec = 4000
    self.eyeState = EyeState.STATE_FIRST
    self.closingMotionMsec = 100
    self.closedMotionMsec = 50
    self.openingMotionMsec = 150
    self.closeIfZero = true
    self.eyeID_L = "PARAM_EYE_L_OPEN"
    self.eyeID_R = "PARAM_EYE_R_OPEN"
    return self
end

function L2DEyeBlink:calcNextBlink()
    local time = UtSystem.getUserTimeMSec()
    local r = math.random()
    return time + r * (2 * self.blinkIntervalMsec - 1)
end

function L2DEyeBlink:setInterval(blinkIntervalMsec)
    self.blinkIntervalMsec = blinkIntervalMsec
end

function L2DEyeBlink:setEyeMotion(closingMotionMsec, closedMotionMsec, openingMotionMsec)
    self.closingMotionMsec = closingMotionMsec
    self.closedMotionMsec = closedMotionMsec
    self.openingMotionMsec = openingMotionMsec
end

function L2DEyeBlink:updateParam(model)
    local time = UtSystem.getUserTimeMSec()
    local eye_param_value = 0

    if self.eyeState == EyeState.STATE_CLOSING then
        local t = (time - self.stateStartTime) / self.closingMotionMsec
        if t >= 1 then
            t = 1
            self.eyeState = EyeState.STATE_CLOSED
            self.stateStartTime = time
        end
        eye_param_value = 1 - t
    elseif self.eyeState == EyeState.STATE_CLOSED then
        local t = (time - self.stateStartTime) / self.closedMotionMsec
        if t >= 1 then
            self.eyeState = EyeState.STATE_OPENING
            self.stateStartTime = time
        end
        eye_param_value = 0
    elseif self.eyeState == EyeState.STATE_OPENING then
        local t = (time - self.stateStartTime) / self.openingMotionMsec
        if t >= 1 then
            t = 1
            self.eyeState = EyeState.STATE_INTERVAL
            self.nextBlinkTime = self:calcNextBlink()
        end
        eye_param_value = t
    elseif self.eyeState == EyeState.STATE_INTERVAL then
        if self.nextBlinkTime < time then
            self.eyeState = EyeState.STATE_CLOSING
            self.stateStartTime = time
        end
        eye_param_value = 1
    else
        self.eyeState = EyeState.STATE_INTERVAL
        self.nextBlinkTime = self:calcNextBlink()
        eye_param_value = 1
    end

    if not self.closeIfZero then
        eye_param_value = -eye_param_value
    end
    model:setParamFloat(self.eyeID_L, eye_param_value)
    model:setParamFloat(self.eyeID_R, eye_param_value)
end

L2DEyeBlink.EyeState = EyeState
return L2DEyeBlink
