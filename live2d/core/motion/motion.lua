local Motion = {}
Motion.__index = Motion

Motion.MOTION_TYPE_PARAM = 0
Motion.MOTION_TYPE_PARTS_VISIBLE = 1
Motion.MOTION_TYPE_LAYOUT_X = 100
Motion.MOTION_TYPE_LAYOUT_Y = 101
Motion.MOTION_TYPE_LAYOUT_ANCHOR_X = 102
Motion.MOTION_TYPE_LAYOUT_ANCHOR_Y = 103
Motion.MOTION_TYPE_LAYOUT_SCALE_X = 104
Motion.MOTION_TYPE_LAYOUT_SCALE_Y = 105

function Motion.new()
    local self = setmetatable({}, Motion)
    self.paramIdStr = nil
    self.values = nil
    self.mtnType = -1
    return self
end

return Motion
