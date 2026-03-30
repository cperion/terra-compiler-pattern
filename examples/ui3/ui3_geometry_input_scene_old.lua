local asdl = require("asdl")
local U = require("unit")
local F = require("fun")

local L = asdl.List

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

-- ============================================================================
-- UiGeometryInput.Scene -> solve -> UiGeometry.Scene
-- ----------------------------------------------------------------------------
-- ui3 shared solver layer: solve geometry input into shared solved geometry.
--
-- This boundary now executes a compiled geometry language rather than
-- recursively descending through source-shaped layout sums.
--
-- First-pass scope:
--   - supports None / Row / Column / Stack flow
--   - supports inflow / absolute / anchored positioning
--   - treats all nodes as placeable; `included_in_layout` only controls whether
--     a node contributes to parent flow extent/cursor advance
--   - scroll_extent uses zero offsets in this first pass
-- ============================================================================

local MEASURE_AUTO = 0
local MEASURE_PX = 1
local MEASURE_PERCENT = 2
local MEASURE_CONTENT = 3
local MEASURE_FLEX = 4

local EDGE_UNSET = 0
local EDGE_PX = 1
local EDGE_PERCENT = 2

local POSITION_INFLOW = 0
local POSITION_ABSOLUTE = 1
local POSITION_ANCHORED = 2

local ANCHOR_START = 0
local ANCHOR_CENTER = 1
local ANCHOR_END = 2

local FLOW_NONE = 0
local FLOW_ROW = 1
local FLOW_COLUMN = 2
local FLOW_STACK = 3

local function Ls(xs)
    return L(xs or {})
end

local function solve_diag_enabled()
    return os.getenv("UI3_SOLVE_DIAG") == "1"
end

local function now_ms()
    return os.clock() * 1000.0
end

local function add_time(diag, key, dt)
    if diag then diag[key] = (diag[key] or 0) + dt end
end

local function bump(diag, key)
    if diag then diag[key] = (diag[key] or 0) + 1 end
end

local function max2(a, b)
    return a > b and a or b
end

local function clamp(v, lo, hi)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function rect(T, x, y, w, h)
    return T.UiCore.Rect(x, y, max2(0, w), max2(0, h))
end

local function size(T, w, h)
    return T.UiCore.Size(max2(0, w), max2(0, h))
end

local function inset_rect(T, r, insets)
    return rect(
        T,
        r.x + insets.left,
        r.y + insets.top,
        r.w - insets.left - insets.right,
        r.h - insets.top - insets.bottom
    )
end

local function next_sibling_pos(headers, pos)
    if pos == nil then return nil end
    return pos + headers[pos].subtree_count
end

local function measure_value(mode, value, available, content)
    if mode == MEASURE_AUTO or mode == MEASURE_CONTENT then return content end
    if mode == MEASURE_PX then return value end
    if mode == MEASURE_PERCENT then return available * value end
    if mode == MEASURE_FLEX then return available end
    error("UiGeometryInput.Scene:solve: unknown measure mode " .. tostring(mode), 3)
end

local function axis_spec_value(spec, available, content)
    local min_v = measure_value(spec.min_mode, spec.min_value, available, content)
    local pref_v = measure_value(spec.preferred_mode, spec.preferred_value, available, content)
    local max_raw = measure_value(spec.max_mode, spec.max_value, available, content)
    local max_v = (spec.max_mode == MEASURE_AUTO and max_raw <= 0) and nil or max_raw
    return clamp(pref_v, min_v, max_v)
end

local function axis_spec_is_auto(spec)
    return spec.min_mode == MEASURE_AUTO
       and spec.preferred_mode == MEASURE_AUTO
       and spec.max_mode == MEASURE_AUTO
end

local function intrinsic_content_size(T, intrinsic)
    return size(T, intrinsic.ideal_content_w, intrinsic.ideal_content_h)
end

local function edge_value(mode, value, available)
    if mode == EDGE_UNSET then return nil end
    if mode == EDGE_PX then return value end
    if mode == EDGE_PERCENT then return available * value end
    error("UiGeometryInput.Scene:solve: unknown edge mode " .. tostring(mode), 3)
end

local function anchor_coord(kind, start, extent)
    if kind == ANCHOR_START then return start end
    if kind == ANCHOR_CENTER then return start + extent / 2 end
    if kind == ANCHOR_END then return start + extent end
    error("UiGeometryInput.Scene:solve: unknown anchor kind " .. tostring(kind), 3)
end

local function anchor_offset(kind, extent)
    if kind == ANCHOR_START then return 0 end
    if kind == ANCHOR_CENTER then return extent / 2 end
    if kind == ANCHOR_END then return extent end
    error("UiGeometryInput.Scene:solve: unknown anchor kind " .. tostring(kind), 3)
end

local function positioned_origin_for_flow(participation, position, content_box, cursor_x, cursor_y, child_outer_w, child_outer_h)
    if position.kind == POSITION_INFLOW then
        return {
            x = cursor_x,
            y = cursor_y,
            participates = participation.included_in_layout,
        }
    end

    if position.kind == POSITION_ABSOLUTE then
        local left = edge_value(position.left_mode, position.left_value, content_box.w)
        local top = edge_value(position.top_mode, position.top_value, content_box.h)
        local right = edge_value(position.right_mode, position.right_value, content_box.w)
        local bottom = edge_value(position.bottom_mode, position.bottom_value, content_box.h)
        return {
            x = content_box.x + (left or ((right and (content_box.w - right - child_outer_w)) or 0)),
            y = content_box.y + (top or ((bottom and (content_box.h - bottom - child_outer_h)) or 0)),
            participates = false,
        }
    end

    if position.kind == POSITION_ANCHORED then
        return {
            x = content_box.x,
            y = content_box.y,
            participates = false,
        }
    end

    error("UiGeometryInput.Scene:solve: unknown position kind " .. tostring(position.kind), 3)
end

local function anchored_origin(placed, position, child_outer_w, child_outer_h)
    local target = placed[position.target_index + 1]
    if not target then
        error(
            "UiGeometryInput.Scene:solve: anchored target must already be placed in the current implementation; target index "
            .. tostring(position.target_index),
            3
        )
    end

    local border = target.border_box
    local target_x = anchor_coord(position.target_x, border.x, border.w)
    local target_y = anchor_coord(position.target_y, border.y, border.h)
    local self_dx = anchor_offset(position.self_x, child_outer_w)
    local self_dy = anchor_offset(position.self_y, child_outer_h)

    return {
        x = target_x - self_dx + position.dx,
        y = target_y - self_dy + position.dy,
        participates = false,
    }
end

local function content_extent_for(T, intrinsic, child_extent)
    return size(
        T,
        max2(intrinsic.ideal_content_w, child_extent.w),
        max2(intrinsic.ideal_content_h, child_extent.h)
    )
end

local function scroll_extent_for(T, scroll_model, content_extent)
    if not scroll_model.needs_scroll_x and not scroll_model.needs_scroll_y then
        return nil
    end
    return T.UiCore.ScrollExtent(content_extent.w, content_extent.h, 0, 0)
end

local function solve_region(T, region, viewport, diag)
    local headers = region.headers
    local participation = region.participation
    local width_specs = region.width_specs
    local height_specs = region.height_specs
    local positions = region.positions
    local flows = region.flows
    local paddings = region.paddings
    local margins = region.margins
    local scroll_models = region.scroll_models
    local intrinsics = region.intrinsics
    local n = #headers

    if #participation ~= n
        or #width_specs ~= n
        or #height_specs ~= n
        or #positions ~= n
        or #flows ~= n
        or #paddings ~= n
        or #margins ~= n
        or #scroll_models ~= n
        or #intrinsics ~= n then
        error("UiGeometryInput.Scene:solve: region plane lengths do not match headers", 3)
    end

    local outer = {}
    local child_extent = {}
    local placed = {}
    local out_nodes = F.iter(headers):map(function(_)
        return C(T.UiGeometry.Excluded)
    end):totable()

    local function compute_outer(pos, available_w, available_h)
        local t0 = diag and now_ms() or nil
        if outer[pos] then
            if diag then add_time(diag, "compute_outer_ms", now_ms() - t0) end
            return outer[pos]
        end
        bump(diag, "compute_outer_calls")

        local header = headers[pos]
        local intrinsic = intrinsics[pos]
        local margin = margins[pos]
        local padding = paddings[pos]
        local width_spec = width_specs[pos]
        local height_spec = height_specs[pos]
        local flow = flows[pos]
        local avail_w = max2(0, available_w - margin.left - margin.right)
        local avail_h = max2(0, available_h - margin.top - margin.bottom)
        local border_w = axis_spec_value(width_spec, avail_w, intrinsic.ideal_content_w + padding.left + padding.right)
        local border_h = axis_spec_value(height_spec, avail_h, intrinsic.ideal_content_h + padding.top + padding.bottom)
        local content_box = rect(T, 0, 0, border_w - padding.left - padding.right, border_h - padding.top - padding.bottom)

        if flow.kind ~= FLOW_NONE and flow.kind ~= FLOW_ROW and flow.kind ~= FLOW_COLUMN and flow.kind ~= FLOW_STACK then
            error("UiGeometryInput.Scene:solve currently supports only None/Row/Column/Stack flows", 3)
        end

        local cursor_x = content_box.x
        local cursor_y = content_box.y
        local max_w = intrinsic.ideal_content_w
        local max_h = intrinsic.ideal_content_h
        local child_pos = header.first_child_index and (header.first_child_index + 1) or nil
        local gap = flow.gap

        for _ = 1, header.child_count do
            local child_intrinsic = intrinsics[child_pos]
            local child_margin = margins[child_pos]
            local child_padding = paddings[child_pos]
            local child_width_spec = width_specs[child_pos]
            local child_height_spec = height_specs[child_pos]
            local child_position = positions[child_pos]
            local child_participation = participation[child_pos]
            local remaining_w = (flow.kind == FLOW_ROW) and max2(0, content_box.w - (cursor_x - content_box.x)) or content_box.w
            local remaining_h = (flow.kind == FLOW_COLUMN) and max2(0, content_box.h - (cursor_y - content_box.y)) or content_box.h
            local child_guess_w = axis_spec_value(
                child_width_spec,
                remaining_w,
                child_intrinsic.ideal_content_w + child_padding.left + child_padding.right
            )
            local child_guess_h = axis_spec_value(
                child_height_spec,
                remaining_h,
                child_intrinsic.ideal_content_h + child_padding.top + child_padding.bottom
            )
            local child_guess = size(
                T,
                child_guess_w + child_margin.left + child_margin.right,
                child_guess_h + child_margin.top + child_margin.bottom
            )
            local posn = positioned_origin_for_flow(
                child_participation,
                child_position,
                content_box,
                cursor_x,
                cursor_y,
                child_guess.w,
                child_guess.h
            )
            local child_outer = compute_outer(child_pos, remaining_w, remaining_h)

            if posn.participates then
                if flow.kind == FLOW_ROW then
                    cursor_x = cursor_x + child_outer.w + gap
                    max_w = max_w + child_outer.w + gap
                    max_h = max2(max_h, child_outer.h)
                elseif flow.kind == FLOW_COLUMN then
                    cursor_y = cursor_y + child_outer.h + gap
                    max_h = max_h + child_outer.h + gap
                    max_w = max2(max_w, child_outer.w)
                else
                    max_w = max2(max_w, child_outer.w)
                    max_h = max2(max_h, child_outer.h)
                end
            else
                max_w = max2(max_w, child_outer.w)
                max_h = max2(max_h, child_outer.h)
            end

            child_pos = next_sibling_pos(headers, child_pos)
        end

        if header.child_count > 0 then
            if flow.kind == FLOW_ROW then
                max_w = max_w - gap
            elseif flow.kind == FLOW_COLUMN then
                max_h = max_h - gap
            end
        end

        child_extent[pos] = size(T, max2(0, max_w), max2(0, max_h))

        if axis_spec_is_auto(width_spec) then
            border_w = max2(border_w, child_extent[pos].w + padding.left + padding.right)
        end
        if axis_spec_is_auto(height_spec) then
            border_h = max2(border_h, child_extent[pos].h + padding.top + padding.bottom)
        end

        outer[pos] = size(T, border_w + margin.left + margin.right, border_h + margin.top + margin.bottom)
        if diag then add_time(diag, "compute_outer_ms", now_ms() - t0) end
        return outer[pos]
    end

    local function place_node(pos, origin_x, origin_y)
        local t0 = diag and now_ms() or nil
        bump(diag, "place_node_calls")
        local header = headers[pos]
        local margin = margins[pos]
        local padding = paddings[pos]
        local intrinsic = intrinsics[pos]
        local flow = flows[pos]
        local node_outer = outer[pos]
        local border_w = max2(0, node_outer.w - margin.left - margin.right)
        local border_h = max2(0, node_outer.h - margin.top - margin.bottom)
        local border_box = rect(T, origin_x + margin.left, origin_y + margin.top, border_w, border_h)
        local padding_box = border_box
        local content_box = inset_rect(T, border_box, padding)
        local content_extent = content_extent_for(T, intrinsic, child_extent[pos])
        local scroll_extent = scroll_extent_for(T, scroll_models[pos], content_extent)

        placed[pos] = {
            border_box = border_box,
            padding_box = padding_box,
            content_box = content_box,
            content_extent = content_extent,
            scroll_extent = scroll_extent,
        }
        local construct_t0 = diag and now_ms() or nil
        out_nodes[pos] = T.UiGeometry.Placed(
            T.UiGeometry.PlacedNode(
                border_box,
                padding_box,
                content_box,
                content_extent,
                scroll_extent
            )
        )
        bump(diag, "placed_node_count")
        if diag then add_time(diag, "placed_node_construct_ms", now_ms() - construct_t0) end

        local cursor_x = content_box.x
        local cursor_y = content_box.y
        local child_pos = header.first_child_index and (header.first_child_index + 1) or nil
        local gap = flow.gap

        for _ = 1, header.child_count do
            local child_outer = outer[child_pos]
            local child_position = positions[child_pos]
            local posn = (child_position.kind == POSITION_ANCHORED)
                and anchored_origin(placed, child_position, child_outer.w, child_outer.h)
                or positioned_origin_for_flow(
                    participation[child_pos],
                    child_position,
                    content_box,
                    cursor_x,
                    cursor_y,
                    child_outer.w,
                    child_outer.h
                )

            place_node(child_pos, posn.x, posn.y)

            if posn.participates then
                if flow.kind == FLOW_ROW then
                    cursor_x = cursor_x + child_outer.w + gap
                elseif flow.kind == FLOW_COLUMN then
                    cursor_y = cursor_y + child_outer.h + gap
                end
            end

            child_pos = next_sibling_pos(headers, child_pos)
        end
        if diag then add_time(diag, "place_node_ms", now_ms() - t0) end
    end

    local root_pos = region.header.root_index + 1
    compute_outer(root_pos, viewport.w, viewport.h)
    place_node(root_pos, 0, 0)

    return T.UiGeometry.Region(
        region.header,
        region.headers,
        Ls(out_nodes)
    )
end

local function solve_scene(T, scene)
    local diag = solve_diag_enabled() and {
        compute_outer_ms = 0,
        place_node_ms = 0,
        placed_node_construct_ms = 0,
        compute_outer_calls = 0,
        place_node_calls = 0,
        placed_node_count = 0,
    } or nil

    local out = T.UiGeometry.Scene(
        scene.viewport,
        Ls(F.iter(scene.regions):map(function(region)
            return solve_region(T, region, scene.viewport, diag)
        end):totable())
    )

    if diag then
        T.UiGeometryInput.__last_solve_diag = diag
    end
    return out
end

return function(T)
    T.UiGeometryInput.Scene.solve = U.transition(function(scene)
        return solve_scene(T, scene)
    end)
end
