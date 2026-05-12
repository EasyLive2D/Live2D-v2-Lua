local UtMotion = {}

function UtMotion.getEasingSine(value)
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return 0.5 - 0.5 * math.cos(value * math.pi)
end

return UtMotion
