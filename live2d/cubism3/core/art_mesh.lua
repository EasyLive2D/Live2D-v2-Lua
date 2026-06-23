-- Art mesh utilities for Cubism 3
-- Ported from Mocari src/core/art_mesh.rs

local art_mesh = {}
local Vector2 = require("live2d.cubism3.core.math").Vector2

function art_mesh.affect_art_mesh_pair(a, b, weight_a, weight_b, glue_opacity)
    return
        Vector2.new(
            a:x() + (b:x() - a:x()) * weight_a * glue_opacity,
            a:y() + (b:y() - a:y()) * weight_a * glue_opacity
        ),
        Vector2.new(
            b:x() + (a:x() - b:x()) * weight_b * glue_opacity,
            b:y() + (a:y() - b:y()) * weight_b * glue_opacity
        )
end

function art_mesh.apply_art_mesh_blend_shape_delta(positions, deltas, weight)
    if #positions ~= #deltas then
        return nil
    end
    if weight == 0 then
        return true
    end
    for i = 1, #positions do
        positions[i] = positions[i] + deltas[i] * weight
    end
    return true
end

function art_mesh.apply_parent_part_opacity(opacity, parent_opacity)
    return opacity * parent_opacity
end

function art_mesh.reverse_coordinate_y(vertices)
    for i, v in ipairs(vertices) do
        vertices[i] = Vector2.new(v:x(), -v:y())
    end
end

function art_mesh.draw_order_from_raw(raw)
    local tr = raw + 0.001
    local i
    if tr >= 0 then
        i = math.floor(tr)
    else
        i = math.ceil(tr)
    end
    return math.max(0, math.min(1000, i))
end

return art_mesh
