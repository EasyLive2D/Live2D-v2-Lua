-- Cubism5 draw-order group parser and render-order expander

local header = require("live2d.cubism3.moc3.header")
local offsets = require("live2d.cubism3.moc3.offsets")
local counts = require("live2d.cubism3.moc3.counts")
local parse = require("live2d.cubism3.moc3.parse")

local draw_order_groups = {}

local GROUP_OBJECT_BEGIN_INDICES_SLOT = 81
local GROUP_OBJECT_COUNTS_SLOT = 82
local GROUP_SUBTREE_COUNTS_SLOT = 83
local GROUP_MAX_DRAW_ORDERS_SLOT = 84
local GROUP_BASE_DRAW_ORDERS_SLOT = 85
local OBJECT_TYPES_SLOT = 86
local OBJECT_INDICES_SLOT = 87
local OBJECT_SELF_GROUP_IDX_SLOT = 88

local OBJECT_TYPE_DRAWABLE = 0
local OBJECT_TYPE_PART = 1

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function nonnegative_usize(value)
    if value < 0 then return 0 end
    return math.floor(value)
end

function draw_order_groups.parse(bytes)
    local hdr, err = header.parse(bytes)
    if not hdr then return nil, err end
    local offs, err = offsets.parse(bytes)
    if not offs then return nil, err end
    local cnts, err = counts.parse(bytes)
    if not cnts then return nil, err end

    local group_count = parse.to_usize(cnts.draw_order_groups, "draw order group count")
    local object_count = parse.to_usize(cnts.draw_order_group_objects, "draw order group object count")
    local drawable_count = parse.to_usize(cnts.art_meshes, "art mesh count")
    if not group_count or not object_count or not drawable_count then
        return nil, "Invalid draw order group counts"
    end
    if group_count == 0 or object_count == 0 then
        return nil
    end

    local begin, err = parse.read_i32_section(bytes, offs, GROUP_OBJECT_BEGIN_INDICES_SLOT, group_count)
    if not begin then return nil, err end
    local count, err = parse.read_i32_section(bytes, offs, GROUP_OBJECT_COUNTS_SLOT, group_count)
    if not count then return nil, err end
    local subtree, err = parse.read_i32_section(bytes, offs, GROUP_SUBTREE_COUNTS_SLOT, group_count)
    if not subtree then return nil, err end
    local max_draw, err = parse.read_i32_section(bytes, offs, GROUP_MAX_DRAW_ORDERS_SLOT, group_count)
    if not max_draw then return nil, err end
    local base_draw, err = parse.read_i32_section(bytes, offs, GROUP_BASE_DRAW_ORDERS_SLOT, group_count)
    if not base_draw then return nil, err end
    local types, err = parse.read_i32_section(bytes, offs, OBJECT_TYPES_SLOT, object_count)
    if not types then return nil, err end
    local indices, err = parse.read_i32_section(bytes, offs, OBJECT_INDICES_SLOT, object_count)
    if not indices then return nil, err end
    local self_group_idx, err = parse.read_i32_section(bytes, offs, OBJECT_SELF_GROUP_IDX_SLOT, object_count)
    if not self_group_idx then return nil, err end

    local groups = {}
    for i = 1, group_count do
        groups[i] = {
            object_begin = nonnegative_usize(begin[i]),
            object_count = nonnegative_usize(count[i]),
            subtree_drawable_count = nonnegative_usize(subtree[i]),
            base_draw_order = base_draw[i],
            max_draw_order = max_draw[i],
        }
    end

    local objects = {}
    for i = 1, object_count do
        objects[i] = {
            object_type = types[i],
            object_idx = nonnegative_usize(indices[i]),
            self_group_idx = nonnegative_usize(self_group_idx[i]),
        }
    end

    return setmetatable({
        groups = groups,
        objects = objects,
        drawable_count_value = drawable_count,
    }, { __index = draw_order_groups })
end

function draw_order_groups.drawable_count(self)
    return self.drawable_count_value
end

function draw_order_groups.group_count(self)
    return #self.groups
end

function draw_order_groups.effective_draw_order(self, group_index, object, drawable_draw_orders, part_draw_orders, part_enable)
    local group = self.groups[group_index + 1]
    if not group then return nil end
    local fallback = group.base_draw_order
    if object.object_type == OBJECT_TYPE_PART then
        if part_enable[object.object_idx + 1] then
            return part_draw_orders[object.object_idx + 1]
        end
        return fallback
    elseif object.object_type == OBJECT_TYPE_DRAWABLE then
        return drawable_draw_orders[object.object_idx + 1]
    end
    return fallback
end

function draw_order_groups.expand_group(self, group_index, start_rank, drawable_draw_orders, part_draw_orders, part_enable, part_offscreen_indices, render_orders)
    local group = self.groups[group_index + 1]
    if not group then return nil end

    local bucket_count = math.max(group.max_draw_order - group.base_draw_order, 0) + 1
    local scratch = self._bucket_scratch
    if not scratch then
        scratch = {}
        self._bucket_scratch = scratch
    end
    local buckets = scratch[group_index + 1]
    if not buckets then
        buckets = {}
        scratch[group_index + 1] = buckets
    end
    for i = 1, bucket_count do
        local bucket = buckets[i]
        if bucket then
            for j = #bucket, 1, -1 do bucket[j] = nil end
        else
            buckets[i] = {}
        end
    end
    for i = bucket_count + 1, #buckets do
        buckets[i] = nil
    end

    for offset = 0, group.object_count - 1 do
        local object = self.objects[group.object_begin + offset + 1]
        if not object then return nil end
        local effective = self:effective_draw_order(group_index, object, drawable_draw_orders, part_draw_orders, part_enable)
        if effective == nil then return nil end
        local bucket = clamp(effective - group.base_draw_order, 0, bucket_count - 1)
        local list = buckets[bucket + 1]
        list[#list + 1] = offset
    end

    local rank = start_rank
    for _, bucket in ipairs(buckets) do
        for _, offset in ipairs(bucket) do
            local object = self.objects[group.object_begin + offset + 1]
            if object.object_type == OBJECT_TYPE_PART then
                local offscreen = part_offscreen_indices[object.object_idx + 1]
                if offscreen ~= nil and offscreen >= 0 then
                    render_orders[self.drawable_count_value + offscreen + 1] = rank
                    rank = rank + 1
                end
                local child = object.self_group_idx
                if child < #self.groups and child ~= group_index then
                    local ok = self:expand_group(child, rank, drawable_draw_orders, part_draw_orders, part_enable, part_offscreen_indices, render_orders)
                    if not ok then return nil end
                    rank = rank + self.groups[child + 1].subtree_drawable_count
                end
            else
                if object.object_idx >= self.drawable_count_value then return nil end
                render_orders[object.object_idx + 1] = rank
                rank = rank + 1
            end
        end
    end
    return true
end

function draw_order_groups.render_orders(self, drawable_draw_orders, part_draw_orders, part_enable, part_offscreen_indices, offscreen_count, out_render_orders)
    if #drawable_draw_orders ~= self.drawable_count_value then
        return nil
    end
    offscreen_count = offscreen_count or 0
    local render_orders = out_render_orders or {}
    for i = 1, self.drawable_count_value + offscreen_count do
        render_orders[i] = 0
    end
    for i = self.drawable_count_value + offscreen_count + 1, #render_orders do
        render_orders[i] = nil
    end
    local ok = self:expand_group(0, 0, drawable_draw_orders, part_draw_orders or {}, part_enable or {}, part_offscreen_indices or {}, render_orders)
    if not ok then return nil end
    return render_orders
end

return draw_order_groups
