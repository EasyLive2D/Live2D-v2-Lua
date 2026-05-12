local UtSystem = require("live2d.core.util.ut_system")

local L2DTargetPoint = {}
L2DTargetPoint.__index = L2DTargetPoint

L2DTargetPoint.FRAME_RATE = 30
L2DTargetPoint.TIME_TO_MAX_SPEED = 0.15
L2DTargetPoint.FACE_PARAM_MAX_V = 40.0 / 7.5
L2DTargetPoint.MAX_V = L2DTargetPoint.FACE_PARAM_MAX_V / L2DTargetPoint.FRAME_RATE
L2DTargetPoint.FRAME_TO_MAX_SPEED = L2DTargetPoint.TIME_TO_MAX_SPEED * L2DTargetPoint.FRAME_RATE

function L2DTargetPoint.new()
    local self = setmetatable({}, L2DTargetPoint)
    self.EPSILON = 0.01
    self.faceTargetX = 0
    self.faceTargetY = 0
    self.faceX = 0
    self.faceY = 0
    self.faceVX = 0
    self.faceVY = 0
    self.lastTimeSec = 0
    return self
end

function L2DTargetPoint:setPoint(x, y)
    self.faceTargetX = x
    self.faceTargetY = y
end

function L2DTargetPoint:getX() return self.faceX end
function L2DTargetPoint:getY() return self.faceY end

function L2DTargetPoint:update()
    if self.lastTimeSec == 0 then
        self.lastTimeSec = UtSystem.getUserTimeMSec()
        return
    end
    local cur_time_sec = UtSystem.getUserTimeMSec()
    local delta_time_weight = (cur_time_sec - self.lastTimeSec) * L2DTargetPoint.FRAME_RATE / 1000.0
    self.lastTimeSec = cur_time_sec

    local max_a = delta_time_weight * L2DTargetPoint.MAX_V / L2DTargetPoint.FRAME_TO_MAX_SPEED
    local dx = self.faceTargetX - self.faceX
    local dy = self.faceTargetY - self.faceY
    if math.abs(dx) <= self.EPSILON and math.abs(dy) <= self.EPSILON then return end

    local d = math.sqrt(dx * dx + dy * dy)
    local vx = L2DTargetPoint.MAX_V * dx / d
    local vy = L2DTargetPoint.MAX_V * dy / d
    local ax = vx - self.faceVX
    local ay = vy - self.faceVY
    local a = math.sqrt(ax * ax + ay * ay)
    if a < -max_a or a > max_a then
        ax = ax * max_a / a
        ay = ay * max_a / a
    end
    self.faceVX = self.faceVX + ax
    self.faceVY = self.faceVY + ay

    local max_v = 0.5 * (math.sqrt(max_a * max_a + 16 * max_a * d - 8 * max_a * d) - max_a)
    local cur_v = math.sqrt(self.faceVX * self.faceVX + self.faceVY * self.faceVY)
    if cur_v > max_v then
        self.faceVX = self.faceVX * max_v / cur_v
        self.faceVY = self.faceVY * max_v / cur_v
    end
    self.faceX = self.faceX + self.faceVX
    self.faceY = self.faceY + self.faceVY
end

return L2DTargetPoint
