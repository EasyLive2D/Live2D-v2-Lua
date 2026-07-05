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

function deformers.rotation_deformer_transform_point_xy(x, y, angle_degrees, scale, translation, flip_x, flip_y)
    local theta = degrees_to_radian(angle_degrees)
    local cos = math_lib.cos(theta)
    local sin = math_lib.sin(theta)
    local sign_x = flip_x and -1 or 1
    local sign_y = flip_y and -1 or 1

    local m00 = cos * scale * sign_x
    local m01 = -sin * scale * sign_y
    local m10 = sin * scale * sign_x
    local m11 = cos * scale * sign_y

    return
        m00 * x + m01 * y + translation:x(),
        m10 * x + m11 * y + translation:y()
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
    if px <= 0 or px >= 1 or py <= 0 or py >= 1 then
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

local function add(a, b)
    return Vector2.new(a:x() + b:x(), a:y() + b:y())
end

local function sub(a, b)
    return Vector2.new(a:x() - b:x(), a:y() - b:y())
end

local function scale(a, s)
    return Vector2.new(a:x() * s, a:y() * s)
end

local function warp_extrap_basis_from_corners(grid, rows, cols, stride)
    local c00 = grid[1]
    local c10 = grid[cols + 1]
    local c01 = grid[rows * stride + 1]
    local c11 = grid[rows * stride + cols + 1]

    local d11_00 = sub(c11, c00)
    local d10_01 = sub(c10, c01)

    local dpdu = scale(sub(d11_00, d10_01), 0.5)
    local dpdv = scale(add(d10_01, d11_00), 0.5)
    local sum = add(add(c00, c10), add(c01, c11))
    local center = sub(scale(sum, 0.25), scale(d11_00, 0.5))

    return { center = center, dpdu = dpdu, dpdv = dpdv }
end

local function clamp_cell(cell, count)
    if cell == count then
        return cell - 1
    end
    return cell
end

local function extrap_cell(basis, x, y, gu, gv, rows, cols, stride, grid)
    local fr = rows
    local fc = cols
    local cen = basis.center
    local du = basis.dpdu
    local dv = basis.dpdv

    if x <= 0.0 then
        if y <= 0.0 then
            return {
                fu = (x + 2.0) * 0.5,
                fv = (y + 2.0) * 0.5,
                p00 = sub(cen, add(scale(du, 2.0), scale(dv, 2.0))),
                p10 = sub(cen, scale(du, 2.0)),
                p01 = sub(cen, scale(dv, 2.0)),
                p11 = grid[1],
            }
        elseif y < 1.0 then
            local cv = clamp_cell(math.floor(gv), rows)
            local vc = cv / fr
            local vn = (cv + 1) / fr
            return {
                fu = (x + 2.0) * 0.5,
                fv = gv - cv,
                p00 = add(sub(cen, scale(dv, 2.0)), scale(du, vc)),
                p10 = grid[cv * stride + 1],
                p01 = add(sub(cen, scale(dv, 2.0)), scale(du, vn)),
                p11 = grid[(cv + 1) * stride + 1],
            }
        else
            return {
                fu = (x + 2.0) * 0.5,
                fv = (y - 1.0) * 0.5,
                p00 = add(sub(cen, scale(dv, 2.0)), du),
                p10 = grid[rows * stride + 1],
                p01 = add(sub(cen, scale(dv, 2.0)), scale(du, 3.0)),
                p11 = add(cen, scale(du, 3.0)),
            }
        end
    elseif x < 1.0 then
        local cu = clamp_cell(math.floor(gu), cols)
        local uc = cu / fc
        local un = (cu + 1) / fc
        if y <= 0.0 then
            return {
                fu = gu - cu,
                fv = (y + 2.0) * 0.5,
                p00 = add(scale(dv, uc), sub(cen, scale(du, 2.0))),
                p10 = add(scale(dv, un), sub(cen, scale(du, 2.0))),
                p01 = grid[cu + 1],
                p11 = grid[cu + 2],
            }
        else
            return {
                fu = gu - cu,
                fv = (y - 1.0) * 0.5,
                p00 = grid[rows * stride + cu + 1],
                p10 = grid[rows * stride + cu + 2],
                p01 = add(add(cen, scale(dv, uc)), scale(du, 3.0)),
                p11 = add(add(cen, scale(dv, un)), scale(du, 3.0)),
            }
        end
    elseif y <= 0.0 then
        return {
            fu = (x - 1.0) * 0.5,
            fv = (y + 2.0) * 0.5,
            p00 = add(sub(cen, scale(du, 2.0)), dv),
            p10 = add(sub(cen, scale(du, 2.0)), scale(dv, 3.0)),
            p01 = grid[cols + 1],
            p11 = add(cen, scale(dv, 3.0)),
        }
    elseif y < 1.0 then
        local cv = clamp_cell(math.floor(gv), rows)
        local vc = cv / fr
        local vn = (cv + 1) / fr
        return {
            fu = (x - 1.0) * 0.5,
            fv = gv - cv,
            p00 = grid[cols + cv * stride + 1],
            p10 = add(add(cen, scale(dv, 3.0)), scale(du, vc)),
            p01 = grid[cols + (cv + 1) * stride + 1],
            p11 = add(add(cen, scale(dv, 3.0)), scale(du, vn)),
        }
    end

    return {
        fu = (x - 1.0) * 0.5,
        fv = (y - 1.0) * 0.5,
        p00 = grid[rows * stride + cols + 1],
        p10 = add(add(cen, scale(dv, 3.0)), du),
        p01 = add(add(cen, scale(du, 3.0)), dv),
        p11 = add(cen, add(scale(dv, 3.0), scale(du, 3.0))),
    }
end

local function bary3(a, b, c, wa, wb, wc)
    return Vector2.new(
        wa * a:x() + wb * b:x() + wc * c:x(),
        wa * a:y() + wb * b:y() + wc * c:y()
    )
end

local function triangle_interpolate(cell)
    local fu = cell.fu
    local fv = cell.fv
    if fu + fv <= 1.0 then
        return bary3(cell.p00, cell.p10, cell.p01, 1.0 - fu - fv, fu, fv)
    end
    return bary3(
        cell.p10,
        cell.p11,
        cell.p01,
        1.0 - fv,
        fu + fv - 1.0,
        1.0 - fu
    )
end

function deformers.warp_deformer_transform_target(local_point, grid, cols, rows, interpolation)
    if local_point:x() > 0 and local_point:x() < 1 and local_point:y() > 0 and local_point:y() < 1 then
        return deformers.warp_deformer_transform_inside(local_point, grid, cols, rows, interpolation)
    end

    local stride = cols + 1
    local required = stride * (rows + 1)
    if cols == 0 or rows == 0 or #grid < required then
        return nil
    end

    local x = local_point:x()
    local y = local_point:y()
    if x ~= x or y ~= y then return nil end

    local basis = warp_extrap_basis_from_corners(grid, rows, cols, stride)
    if x <= -2.0 or x >= 3.0 or y <= -2.0 or y >= 3.0 then
        return Vector2.new(
            basis.dpdv:x() * x + basis.center:x() + basis.dpdu:x() * y,
            basis.dpdv:y() * x + basis.center:y() + basis.dpdu:y() * y
        )
    end

    local cell = extrap_cell(
        basis,
        x,
        y,
        x * cols,
        y * rows,
        rows,
        cols,
        stride,
        grid
    )
    return triangle_interpolate(cell)
end

local function point_xy(point)
    return point._x or point:x(), point._y or point:y()
end

local function bilinear_cell_xy(cellFractionS, cellFractionT, c00, c10, c01, c11)
    local w00 = (1 - cellFractionS) * (1 - cellFractionT)
    local w10 = cellFractionS * (1 - cellFractionT)
    local w01 = (1 - cellFractionS) * cellFractionT
    local w11 = cellFractionS * cellFractionT
    local c00x, c00y = point_xy(c00)
    local c10x, c10y = point_xy(c10)
    local c01x, c01y = point_xy(c01)
    local c11x, c11y = point_xy(c11)
    return
        w00 * c00x + w10 * c10x + w01 * c01x + w11 * c11x,
        w00 * c00y + w10 * c10y + w01 * c01y + w11 * c11y
end

local function triangle_cell_xy(cellFractionS, cellFractionT, c00, c10, c01, c11)
    local c00x, c00y = point_xy(c00)
    local c10x, c10y = point_xy(c10)
    local c01x, c01y = point_xy(c01)
    if cellFractionS + cellFractionT <= 1 then
        return
            c00x + (c10x - c00x) * cellFractionS + (c01x - c00x) * cellFractionT,
            c00y + (c10y - c00y) * cellFractionS + (c01y - c00y) * cellFractionT
    end
    local c11x, c11y = point_xy(c11)
    local oneMinusS = 1 - cellFractionS
    local oneMinusT = 1 - cellFractionT
    return
        c11x + (c01x - c11x) * oneMinusS + (c10x - c11x) * oneMinusT,
        c11y + (c01y - c11y) * oneMinusS + (c10y - c11y) * oneMinusT
end

local function warp_inside_xy(px, py, grid, cols, rows, interpolation)
    if px <= 0 or px >= 1 or py <= 0 or py >= 1 then
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

    local flatIndex = cellJ * stride + cellI + 1
    local c00 = grid[flatIndex]
    local c10 = grid[flatIndex + 1]
    local c01 = grid[flatIndex + stride]
    local c11 = grid[flatIndex + stride + 1]

    if interpolation == deformers.WARP_QUAD then
        return bilinear_cell_xy(cellFractionS, cellFractionT, c00, c10, c01, c11)
    end
    return triangle_cell_xy(cellFractionS, cellFractionT, c00, c10, c01, c11)
end

local function basis_from_corners_xy(grid, rows, cols, stride)
    local c00x, c00y = point_xy(grid[1])
    local c10x, c10y = point_xy(grid[cols + 1])
    local c01x, c01y = point_xy(grid[rows * stride + 1])
    local c11x, c11y = point_xy(grid[rows * stride + cols + 1])
    local d11_00x, d11_00y = c11x - c00x, c11y - c00y
    local d10_01x, d10_01y = c10x - c01x, c10y - c01y
    local dpdux, dpduy = (d11_00x - d10_01x) * 0.5, (d11_00y - d10_01y) * 0.5
    local dpdvx, dpdvy = (d10_01x + d11_00x) * 0.5, (d10_01y + d11_00y) * 0.5
    local centerx = (c00x + c10x + c01x + c11x) * 0.25 - d11_00x * 0.5
    local centery = (c00y + c10y + c01y + c11y) * 0.25 - d11_00y * 0.5
    return centerx, centery, dpdux, dpduy, dpdvx, dpdvy
end

local function bary3_xy(ax, ay, bx, by, cx, cy, wa, wb, wc)
    return wa * ax + wb * bx + wc * cx, wa * ay + wb * by + wc * cy
end

local function triangle_interpolate_xy(fu, fv, p00x, p00y, p10x, p10y, p01x, p01y, p11x, p11y)
    if fu + fv <= 1.0 then
        return bary3_xy(p00x, p00y, p10x, p10y, p01x, p01y, 1.0 - fu - fv, fu, fv)
    end
    return bary3_xy(p10x, p10y, p11x, p11y, p01x, p01y, 1.0 - fv, fu + fv - 1.0, 1.0 - fu)
end

function deformers.warp_deformer_transform_target_xy(x, y, grid, cols, rows, interpolation)
    if x > 0 and x < 1 and y > 0 and y < 1 then
        return warp_inside_xy(x, y, grid, cols, rows, interpolation)
    end

    local stride = cols + 1
    local required = stride * (rows + 1)
    if cols == 0 or rows == 0 or #grid < required then
        return nil
    end
    if x ~= x or y ~= y then return nil end

    local cenx, ceny, dux, duy, dvx, dvy = basis_from_corners_xy(grid, rows, cols, stride)
    if x <= -2.0 or x >= 3.0 or y <= -2.0 or y >= 3.0 then
        return dvx * x + cenx + dux * y, dvy * x + ceny + duy * y
    end

    local gu = x * cols
    local gv = y * rows
    local fu, fv, p00x, p00y, p10x, p10y, p01x, p01y, p11x, p11y

    if x <= 0.0 then
        if y <= 0.0 then
            fu, fv = (x + 2.0) * 0.5, (y + 2.0) * 0.5
            p00x, p00y = cenx - dux * 2.0 - dvx * 2.0, ceny - duy * 2.0 - dvy * 2.0
            p10x, p10y = cenx - dux * 2.0, ceny - duy * 2.0
            p01x, p01y = cenx - dvx * 2.0, ceny - dvy * 2.0
            p11x, p11y = point_xy(grid[1])
        elseif y < 1.0 then
            local cv = clamp_cell(math.floor(gv), rows)
            local vc = cv / rows
            local vn = (cv + 1) / rows
            fu, fv = (x + 2.0) * 0.5, gv - cv
            p00x, p00y = cenx - dvx * 2.0 + dux * vc, ceny - dvy * 2.0 + duy * vc
            p10x, p10y = point_xy(grid[cv * stride + 1])
            p01x, p01y = cenx - dvx * 2.0 + dux * vn, ceny - dvy * 2.0 + duy * vn
            p11x, p11y = point_xy(grid[(cv + 1) * stride + 1])
        else
            fu, fv = (x + 2.0) * 0.5, (y - 1.0) * 0.5
            p00x, p00y = cenx - dvx * 2.0 + dux, ceny - dvy * 2.0 + duy
            p10x, p10y = point_xy(grid[rows * stride + 1])
            p01x, p01y = cenx - dvx * 2.0 + dux * 3.0, ceny - dvy * 2.0 + duy * 3.0
            p11x, p11y = cenx + dux * 3.0, ceny + duy * 3.0
        end
    elseif x < 1.0 then
        local cu = clamp_cell(math.floor(gu), cols)
        local uc = cu / cols
        local un = (cu + 1) / cols
        if y <= 0.0 then
            fu, fv = gu - cu, (y + 2.0) * 0.5
            p00x, p00y = dvx * uc + cenx - dux * 2.0, dvy * uc + ceny - duy * 2.0
            p10x, p10y = dvx * un + cenx - dux * 2.0, dvy * un + ceny - duy * 2.0
            p01x, p01y = point_xy(grid[cu + 1])
            p11x, p11y = point_xy(grid[cu + 2])
        else
            fu, fv = gu - cu, (y - 1.0) * 0.5
            p00x, p00y = point_xy(grid[rows * stride + cu + 1])
            p10x, p10y = point_xy(grid[rows * stride + cu + 2])
            p01x, p01y = cenx + dvx * uc + dux * 3.0, ceny + dvy * uc + duy * 3.0
            p11x, p11y = cenx + dvx * un + dux * 3.0, ceny + dvy * un + duy * 3.0
        end
    elseif y <= 0.0 then
        fu, fv = (x - 1.0) * 0.5, (y + 2.0) * 0.5
        p00x, p00y = cenx - dux * 2.0 + dvx, ceny - duy * 2.0 + dvy
        p10x, p10y = cenx - dux * 2.0 + dvx * 3.0, ceny - duy * 2.0 + dvy * 3.0
        p01x, p01y = point_xy(grid[cols + 1])
        p11x, p11y = cenx + dvx * 3.0, ceny + dvy * 3.0
    elseif y < 1.0 then
        local cv = clamp_cell(math.floor(gv), rows)
        local vc = cv / rows
        local vn = (cv + 1) / rows
        fu, fv = (x - 1.0) * 0.5, gv - cv
        p00x, p00y = point_xy(grid[cols + cv * stride + 1])
        p10x, p10y = cenx + dvx * 3.0 + dux * vc, ceny + dvy * 3.0 + duy * vc
        p01x, p01y = point_xy(grid[cols + (cv + 1) * stride + 1])
        p11x, p11y = cenx + dvx * 3.0 + dux * vn, ceny + dvy * 3.0 + duy * vn
    else
        fu, fv = (x - 1.0) * 0.5, (y - 1.0) * 0.5
        p00x, p00y = point_xy(grid[rows * stride + cols + 1])
        p10x, p10y = cenx + dvx * 3.0 + dux, ceny + dvy * 3.0 + duy
        p01x, p01y = cenx + dux * 3.0 + dvx, ceny + duy * 3.0 + dvy
        p11x, p11y = cenx + dvx * 3.0 + dux * 3.0, ceny + dvy * 3.0 + duy * 3.0
    end

    return triangle_interpolate_xy(fu, fv, p00x, p00y, p10x, p10y, p01x, p01y, p11x, p11y)
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
