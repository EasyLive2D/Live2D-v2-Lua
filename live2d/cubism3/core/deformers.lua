-- Deformer math for Cubism 3
-- Ported from Mocari src/core/deformers.rs

local math_lib = math
local Vector2 = require("live2d.cubism3.core.math").Vector2

local deformers = {}

-- WarpInterpolation
deformers.WARP_QUAD = 0
deformers.WARP_TRIANGLE = 1

-- DeformerTransform enum
deformers.DEFORMER_ROTATION = "rotation"
deformers.DEFORMER_WARP = "warp"

function deformers.new_rotation_transform(angle_degrees, scale, translation, flip_x, flip_y)
    return {
        kind = deformers.DEFORMER_ROTATION,
        angle_degrees = angle_degrees,
        scale = scale,
        translation = translation,
        flip_x = flip_x,
        flip_y = flip_y,
    }
end

function deformers.new_warp_transform(grid, cols, rows, interpolation)
    return {
        kind = deformers.DEFORMER_WARP,
        grid = grid,
        cols = cols,
        rows = rows,
        interpolation = interpolation,
    }
end

local function degrees_to_radian(degrees)
    return (degrees / 180) * math_lib.pi
end

function deformers.rotation_deformer_transform_point(point, angle_degrees, scale, translation, flip_x, flip_y)
    local theta = degrees_to_radian(angle_degrees)
    local cos = math_lib.cos(theta)
    local sin = math_lib.sin(theta)
    local sign_x = flip_x and -1 or 1
    local sign_y = flip_y and -1 or 1

    local m00 = cos * scale * sign_x
    local m01 = -sin * scale * sign_y
    local m10 = sin * scale * sign_x
    local m11 = cos * scale * sign_y

    return Vector2.new(
        m00 * point:x() + m01 * point:y() + translation:x(),
        m10 * point:x() + m11 * point:y() + translation:y()
    )
end

-- Bilinear interpolation
local function bilinear_cell(cellFractionS, cellFractionT, c00, c10, c01, c11)
    local w00 = (1 - cellFractionS) * (1 - cellFractionT)
    local w10 = cellFractionS * (1 - cellFractionT)
    local w01 = (1 - cellFractionS) * cellFractionT
    local w11 = cellFractionS * cellFractionT
    return Vector2.new(
        w00 * c00:x() + w10 * c10:x() + w01 * c01:x() + w11 * c11:x(),
        w00 * c00:y() + w10 * c10:y() + w01 * c01:y() + w11 * c11:y()
    )
end

-- Triangle interpolation
local function triangle_cell(cellFractionS, cellFractionT, c00, c10, c01, c11)
    if cellFractionS + cellFractionT <= 1 then
        return Vector2.new(
            c00:x() + (c10:x() - c00:x()) * cellFractionS + (c01:x() - c00:x()) * cellFractionT,
            c00:y() + (c10:y() - c00:y()) * cellFractionS + (c01:y() - c00:y()) * cellFractionT
        )
    end
    local oneMinusS = 1 - cellFractionS
    local oneMinusT = 1 - cellFractionT
    return Vector2.new(
        c11:x() + (c01:x() - c11:x()) * oneMinusS + (c10:x() - c11:x()) * oneMinusT,
        c11:y() + (c01:y() - c11:y()) * oneMinusS + (c10:y() - c11:y()) * oneMinusT
    )
end

local function outside_cell_index(value, cell_count)
    if value ~= value then -- NaN check
        return nil
    end
    local max_index = cell_count - 1
    local index = math.max(0, math.min(max_index, math.floor(value)))
    if index ~= index then
        return nil
    end
    return index
end

function deformers.warp_deformer_transform_inside(local_point, grid, cols, rows, interpolation)
    local px = local_point:x()
    local py = local_point:y()
    if px < 0 or px > 1 or py < 0 or py > 1 then
        return nil
    end

    local stride = cols + 1
    local required = stride * (rows + 1)
    if #grid < required then
        return nil
    end

    local gridU = px * cols
    local gridV = py * rows
    local cellI = math.floor(gridU)
    local cellJ = math.floor(gridV)
    local cellFractionS = gridU - cellI
    local cellFractionT = gridV - cellJ

    if cellI >= cols or cellJ >= rows then
        return nil
    end

    -- 1-indexed array access
    local flatIndex = cellJ * stride + cellI + 1
    local c00 = grid[flatIndex]
    local c10 = grid[flatIndex + 1]
    local c01 = grid[flatIndex + stride]
    local c11 = grid[flatIndex + stride + 1]

    if interpolation == deformers.WARP_QUAD then
        return bilinear_cell(cellFractionS, cellFractionT, c00, c10, c01, c11)
    else
        return triangle_cell(cellFractionS, cellFractionT, c00, c10, c01, c11)
    end
end

function deformers.warp_deformer_transform_target(local_point, grid, cols, rows, interpolation)
    if local_point:x() >= 0 and local_point:x() <= 1 and local_point:y() >= 0 and local_point:y() <= 1 then
        return deformers.warp_deformer_transform_inside(local_point, grid, cols, rows, interpolation)
    end

    local stride = cols + 1
    local required = stride * (rows + 1)
    if cols == 0 or rows == 0 or #grid < required then
        return nil
    end

    local gridU = local_point:x() * cols
    local gridV = local_point:y() * rows
    local cellI = outside_cell_index(gridU, cols)
    local cellJ = outside_cell_index(gridV, rows)
    if cellI == nil or cellJ == nil then
        return nil
    end
    local cellFractionS = gridU - cellI
    local cellFractionT = gridV - cellJ

    local flatIndex = cellJ * stride + cellI + 1
    local c00 = grid[flatIndex]
    local c10 = grid[flatIndex + 1]
    local c01 = grid[flatIndex + stride]
    local c11 = grid[flatIndex + stride + 1]

    if interpolation == deformers.WARP_QUAD then
        return bilinear_cell(cellFractionS, cellFractionT, c00, c10, c01, c11)
    else
        return triangle_cell(cellFractionS, cellFractionT, c00, c10, c01, c11)
    end
end

function deformers.transform_art_mesh_vertices_by_deformers(vertices, transforms)
    local out = {}
    for _, v in ipairs(vertices) do
        out[#out + 1] = v
    end

    for _, transform in ipairs(transforms) do
        for i = 1, #out do
            if transform.kind == deformers.DEFORMER_ROTATION then
                out[i] = deformers.rotation_deformer_transform_point(
                    out[i],
                    transform.angle_degrees,
                    transform.scale,
                    transform.translation,
                    transform.flip_x,
                    transform.flip_y
                )
            elseif transform.kind == deformers.DEFORMER_WARP then
                local transformResult = deformers.warp_deformer_transform_target(
                    out[i], transform.grid, transform.cols, transform.rows, transform.interpolation
                )
                if transformResult == nil then
                    return nil
                end
                out[i] = transformResult
            end
        end
    end

    return out
end

return deformers
