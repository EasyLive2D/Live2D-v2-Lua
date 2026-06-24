local UtMath = {}

UtMath.DEG_TO_RAD = math.pi / 180
UtMath.RAD_TO_DEG = 180 / math.pi

function UtMath.getAngleNotAbs(v1, v2)
    local q1 = math.atan2(v1[2], v1[1])
    local q2 = math.atan2(v2[2], v2[1])
    return UtMath.getAngleDiff(q1, q2)
end

function UtMath.getAngleDiff(q1, q2)
    local angleDiff = q1 - q2
    while angleDiff < -math.pi do
        angleDiff = angleDiff + 2 * math.pi
    end
    while angleDiff > math.pi do
        angleDiff = angleDiff - 2 * math.pi
    end
    return angleDiff
end

return UtMath
