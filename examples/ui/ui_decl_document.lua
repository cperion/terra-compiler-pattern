local U = require("unit")
local F = require("fun")
local Text = require("examples.ui.ui_text_resolve")

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
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

local function corners_are_square(c)
    return c.top_left == 0
       and c.top_right == 0
       and c.bottom_right == 0
       and c.bottom_left == 0
end

local function clip_shape_for(T, r, corners)
    if corners_are_square(corners) then
        return T.UiCore.ClipRect(r)
    end
    return T.UiCore.ClipRoundedRect(r, corners)
end

local function hit_shape_for(T, r, corners)
    if corners_are_square(corners) then
        return T.UiCore.HitRect(r)
    end
    return T.UiCore.HitRoundedRect(r, corners)
end

local function top_clip(clips)
    return clips[#clips]
end

local function local_clip_shapes(T, element, border_box, content_box)
    local out = {}

    for _, op in ipairs(element.paint.ops) do
        if op.kind == "Clip" then
            out[#out + 1] = clip_shape_for(T, border_box, op.corners)
        end
    end

    if element.layout.overflow_x.kind ~= "Visible" or element.layout.overflow_y.kind ~= "Visible" then
        out[#out + 1] = clip_shape_for(T, content_box, T.UiCore.Corners(0, 0, 0, 0))
    end

    return out
end

local text_intrinsic = terralib.memoize(function(T, assets, content)
    local m = Text.measure(T, assets, nil, content.value, content.style, content.layout, nil)
    return { w = m.w, h = m.h }
end)

local function image_intrinsic()
    return { w = 64, h = 64 }
end

local content_intrinsic = terralib.memoize(function(T, assets, content)
    return U.match(content, {
        NoContent = function()
            return { w = 0, h = 0 }
        end,
        Text = function(v)
            return text_intrinsic(T, assets, v)
        end,
        Image = function(_)
            return image_intrinsic()
        end,
        CustomContent = function(_)
            return { w = 0, h = 0 }
        end,
    })
end)

local shape_text = terralib.memoize(function(T, assets, content, x, y, w, h)
    return Text.shape(
        T,
        assets,
        nil,
        content.value,
        content.style,
        content.layout,
        rect(T, x, y, w, h)
    )
end)

local function measure_value(measure, available, content)
    return U.match(measure, {
        Auto = function() return content end,
        Px = function(v) return v.value end,
        Percent = function(v) return available * v.value end,
        Content = function() return content end,
        Flex = function(_) return available end,
    })
end

local function size_spec_value(spec, available, content)
    local min_v = measure_value(spec.min, available, content)
    local pref_v = measure_value(spec.preferred, available, content)
    local max_raw = measure_value(spec.max, available, content)
    local max_v = (max_raw <= 0 and spec.max.kind == "Auto") and nil or max_raw
    return clamp(pref_v, min_v, max_v)
end

local function is_auto_size_spec(spec)
    return spec.min.kind == "Auto"
       and spec.preferred.kind == "Auto"
       and spec.max.kind == "Auto"
end

local function empty_routes()
    return {
        hits = {},
        focus_chain = {},
        pointer_routes = {},
        scroll_routes = {},
        key_routes = {},
        edit_routes = {},
        accessibility = {},
        batches = {},
    }
end

local function append_all(dst, src)
    for i = 1, #src do
        dst[#dst + 1] = src[i]
    end
end

local function merge_flat_routes(dst, src)
    append_all(dst.hits, src.hits)
    append_all(dst.focus_chain, src.focus_chain)
    append_all(dst.pointer_routes, src.pointer_routes)
    append_all(dst.scroll_routes, src.scroll_routes)
    append_all(dst.key_routes, src.key_routes)
    append_all(dst.edit_routes, src.edit_routes)
    append_all(dst.batches, src.batches)
    return dst
end

local function merge_routes(dst, src)
    merge_flat_routes(dst, src)
    append_all(dst.accessibility, src.accessibility)
    return dst
end

local function same_clip(a, b)
    return a == b
end

local function same_sampling(a, b)
    return a == b
end

local function mergeable(prev, batch)
    if not prev or prev.kind ~= batch.kind then return false end
    if not same_clip(prev.clip, batch.clip) then return false end

    if batch.kind == "BoxBatch" or batch.kind == "ShadowBatch" then
        return true
    end
    if batch.kind == "ImageBatch" then
        return prev.image == batch.image and same_sampling(prev.sampling, batch.sampling)
    end
    if batch.kind == "TextBatch" then
        return prev.font == batch.font and prev.size_px == batch.size_px
    end
    return false
end

local function append_batch(_, batches, batch)
    if not batch then return end
    local prev = batches[#batches]
    if not mergeable(prev, batch) then
        batches[#batches + 1] = batch
        return
    end

    append_all(prev.items, batch.items)
end

local function effect_batch(T, clip, item)
    return T.UiBatched.EffectBatch(0, clip, L { item })
end

local function emit_paint_batches(T, assets, batches, clip, border_box, content_box, paint_ops)
    for _, op in ipairs(paint_ops) do
        U.match(op, {
            Box = function(v)
                append_batch(T, batches, T.UiBatched.BoxBatch(0, clip, L {
                    T.UiBatched.BoxItem(border_box, v.fill, v.stroke, v.stroke_width, v.align, v.corners)
                }))
            end,
            Shadow = function(v)
                append_batch(T, batches, T.UiBatched.ShadowBatch(0, clip, L {
                    T.UiBatched.ShadowItem(border_box, v.brush, v.blur, v.spread, v.dx, v.dy, v.kind, v.corners)
                }))
            end,
            Clip = function(v)
                append_batch(T, batches, effect_batch(T, clip, T.UiBatched.PushClip(clip_shape_for(T, border_box, v.corners))))
            end,
            Opacity = function(v)
                append_batch(T, batches, effect_batch(T, clip, T.UiBatched.PushOpacity(v.value)))
            end,
            Transform = function(v)
                append_batch(T, batches, effect_batch(T, clip, T.UiBatched.PushTransform(v.xform)))
            end,
            Blend = function(v)
                append_batch(T, batches, effect_batch(T, clip, T.UiBatched.PushBlend(v.mode)))
            end,
            CustomPaint = function(_)
                error("UiDecl.Document.compile: CustomPaint is not implemented yet", 3)
            end,
        })
    end

    U.match(content_box and content_box.content or { kind = "NoContent" }, {
        NoContent = function() end,
        Text = function(v)
            local box = content_box.box
            local shaped = shape_text(T, assets, v, box.x, box.y, box.w, box.h)
            local first_line = shaped.lines[1]
            local first_run = first_line and first_line.runs[1] or nil
            if first_run then
                append_batch(T, batches, T.UiBatched.TextBatch(0, clip, first_run.font, first_run.size_px, L {
                    T.UiBatched.TextItem(shaped.text, shaped.bounds, first_run.color, shaped.wrap, shaped.align)
                }))
            end
        end,
        Image = function(v)
            append_batch(T, batches, T.UiBatched.ImageBatch(0, clip, v.image, v.style.sampling, L {
                T.UiBatched.ImageItem(content_box.box, v.style)
            }))
        end,
        CustomContent = function(_)
            error("UiDecl.Document.compile: CustomContent is not implemented yet", 3)
        end,
    })
end

local function emit_post_batches(T, batches, clip, paint_ops)
    for i = #paint_ops, 1, -1 do
        local op = paint_ops[i]
        U.match(op, {
            Box = function() end,
            Shadow = function() end,
            CustomPaint = function() end,
            Clip = function()
                append_batch(T, batches, effect_batch(T, clip, T.UiBatched.PopClip()))
            end,
            Opacity = function()
                append_batch(T, batches, effect_batch(T, clip, T.UiBatched.PopOpacity()))
            end,
            Transform = function()
                append_batch(T, batches, effect_batch(T, clip, T.UiBatched.PopTransform()))
            end,
            Blend = function()
                append_batch(T, batches, effect_batch(T, clip, T.UiBatched.PopBlend()))
            end,
        })
    end
end

local bind_element
bind_element = U.transition(function(T, element)
    return T.UiBound.Node(
        element.id,
        element.semantic_ref,
        element.debug_name,
        element.role,
        element.flags,
        element.layout,
        element.paint,
        element.content,
        element.behavior,
        element.accessibility,
        L(F.iter(element.children):map(function(child)
            return bind_element(T, child)
        end):totable())
    )
end)

local function accessibility_tree(T, element, border_box, child_nodes)
    return T.UiRouted.AccessibilityNode(
        element.id,
        element.semantic_ref,
        element.accessibility.role,
        element.accessibility.label,
        element.accessibility.description,
        element.accessibility.hidden,
        element.accessibility.sort_priority,
        border_box,
        L(child_nodes)
    )
end

local function key_route_bucket(map, scope, when, chord)
    local by_scope = map[scope]
    if not by_scope then
        by_scope = {}
        map[scope] = by_scope
    end
    local by_when = by_scope[when]
    if not by_when then
        by_when = {}
        by_scope[when] = by_when
    end
    local rows = by_when[chord]
    if not rows then
        rows = {}
        by_when[chord] = rows
    end
    return rows
end

local function build_route_queries(routes)
    local q = {
        hit_element = {}, hit_semantic_ref = {}, hit_x = {}, hit_y = {}, hit_w = {}, hit_h = {}, hit_z = {},
        hover_element = {}, hover_semantic_ref = {}, hover_cursor = {}, hover_enter = {}, hover_leave = {},
        press_kind = {}, press_element = {}, press_semantic_ref = {}, press_button = {}, press_click_count = {}, press_command = {}, press_value = {},
        focus_element = {}, focus_semantic_ref = {}, focus_order = {}, focus_mode = {}, focus_bounds = {},
        scroll_element = {}, scroll_semantic_ref = {}, scroll_axis = {}, scroll_model = {}, scroll_viewport = {}, scroll_content_size = {},
        edit_element = {}, edit_semantic_ref = {}, edit_model = {}, edit_multiline = {}, edit_read_only = {}, edit_changed = {}, edit_bounds = {},
        key_scope = {}, key_chord = {}, key_when = {}, key_command = {}, key_global = {},
        accessibility = routes.accessibility,

        hover_ix = {},
        press_ix = {},
        focus_ix = {},
        scroll_ix = {},
        edit_ix = {},
        key_ix = {},
        hit_order = {},
    }

    local hit_rows = {}
    for _, hit in ipairs(routes.hits) do
        local r = U.match(hit.shape, {
            HitRect = function(v) return v.rect end,
            HitRoundedRect = function(v) return v.rect end,
        })
        hit_rows[#hit_rows + 1] = {
            element = hit.element,
            semantic_ref = hit.semantic_ref,
            x = r.x,
            y = r.y,
            w = r.w,
            h = r.h,
            z = hit.z_index,
        }
    end
    table.sort(hit_rows, function(a, b) return a.z > b.z end)
    for i, row in ipairs(hit_rows) do
        q.hit_element[i] = row.element
        q.hit_semantic_ref[i] = row.semantic_ref
        q.hit_x[i], q.hit_y[i], q.hit_w[i], q.hit_h[i], q.hit_z[i] = row.x, row.y, row.w, row.h, row.z
        q.hit_order[i] = i
    end

    for _, route in ipairs(routes.pointer_routes) do
        if route.kind == "HoverRoute" then
            local idx = #q.hover_element + 1
            q.hover_element[idx] = route.element
            q.hover_semantic_ref[idx] = route.semantic_ref
            q.hover_cursor[idx] = route.cursor
            q.hover_enter[idx] = route.enter
            q.hover_leave[idx] = route.leave
            q.hover_ix[route.element] = idx
        elseif route.kind == "PressRoute" or route.kind == "ToggleRoute" then
            local idx = #q.press_element + 1
            q.press_kind[idx] = route.kind
            q.press_element[idx] = route.element
            q.press_semantic_ref[idx] = route.semantic_ref
            q.press_button[idx] = route.button
            q.press_click_count[idx] = route.click_count
            q.press_command[idx] = route.command
            q.press_value[idx] = route.value
            local by_button = q.press_ix[route.element]
            if not by_button then
                by_button = {}
                q.press_ix[route.element] = by_button
            end
            local bucket = by_button[route.button]
            if not bucket then
                bucket = {}
                by_button[route.button] = bucket
            end
            bucket[#bucket + 1] = idx
        end
    end

    for _, entry in ipairs(routes.focus_chain) do
        local idx = #q.focus_element + 1
        q.focus_element[idx] = entry.element
        q.focus_semantic_ref[idx] = entry.semantic_ref
        q.focus_order[idx] = entry.order
        q.focus_mode[idx] = entry.mode
        q.focus_bounds[idx] = entry.bounds
        q.focus_ix[entry.element] = idx
    end
    for _, route in ipairs(routes.scroll_routes) do
        local idx = #q.scroll_element + 1
        q.scroll_element[idx] = route.element
        q.scroll_semantic_ref[idx] = route.semantic_ref
        q.scroll_axis[idx] = route.axis
        q.scroll_model[idx] = route.model
        q.scroll_viewport[idx] = route.viewport
        q.scroll_content_size[idx] = route.content_size
        q.scroll_ix[route.element] = idx
    end
    for _, route in ipairs(routes.edit_routes) do
        local idx = #q.edit_element + 1
        q.edit_element[idx] = route.element
        q.edit_semantic_ref[idx] = route.semantic_ref
        q.edit_model[idx] = route.model
        q.edit_multiline[idx] = route.multiline
        q.edit_read_only[idx] = route.read_only
        q.edit_changed[idx] = route.changed
        q.edit_bounds[idx] = route.bounds
        q.edit_ix[route.element] = idx
    end
    for _, route in ipairs(routes.key_routes) do
        local idx = #q.key_chord + 1
        q.key_scope[idx] = route.scope
        q.key_chord[idx] = route.chord
        q.key_when[idx] = route.when
        q.key_command[idx] = route.command
        q.key_global[idx] = route.global
        local scope = route.global and false or route.scope
        local bucket = key_route_bucket(q.key_ix, scope, route.when, route.chord)
        bucket[#bucket + 1] = idx
    end

    function q:hit_test(point)
        for i = 1, #self.hit_order do
            local idx = self.hit_order[i]
            local x, y, w, h = self.hit_x[idx], self.hit_y[idx], self.hit_w[idx], self.hit_h[idx]
            if point.x >= x and point.y >= y and point.x <= x + w and point.y <= y + h then
                return {
                    element = self.hit_element[idx],
                    semantic_ref = self.hit_semantic_ref[idx],
                    x = x, y = y, w = w, h = h, z_index = self.hit_z[idx],
                }
            end
        end
        return nil
    end

    function q:hover_route(element)
        local idx = self.hover_ix[element]
        if not idx then return nil end
        return {
            element = self.hover_element[idx],
            semantic_ref = self.hover_semantic_ref[idx],
            cursor = self.hover_cursor[idx],
            enter = self.hover_enter[idx],
            leave = self.hover_leave[idx],
        }
    end

    function q:press_routes(element, button)
        local by_button = self.press_ix[element]
        local indices = by_button and by_button[button] or nil
        if not indices then return {} end
        local out = {}
        for i = 1, #indices do
            local idx = indices[i]
            out[i] = {
                kind = self.press_kind[idx],
                element = self.press_element[idx],
                semantic_ref = self.press_semantic_ref[idx],
                button = self.press_button[idx],
                click_count = self.press_click_count[idx],
                command = self.press_command[idx],
                value = self.press_value[idx],
            }
        end
        return out
    end

    function q:focus_entry(element)
        local idx = self.focus_ix[element]
        if not idx then return nil end
        return {
            element = self.focus_element[idx],
            semantic_ref = self.focus_semantic_ref[idx],
            order = self.focus_order[idx],
            mode = self.focus_mode[idx],
            bounds = self.focus_bounds[idx],
        }
    end

    function q:scroll_route(element)
        local idx = self.scroll_ix[element]
        if not idx then return nil end
        return {
            element = self.scroll_element[idx],
            semantic_ref = self.scroll_semantic_ref[idx],
            axis = self.scroll_axis[idx],
            model = self.scroll_model[idx],
            viewport = self.scroll_viewport[idx],
            content_size = self.scroll_content_size[idx],
        }
    end

    function q:edit_route(element)
        local idx = self.edit_ix[element]
        if not idx then return nil end
        return {
            element = self.edit_element[idx],
            semantic_ref = self.edit_semantic_ref[idx],
            model = self.edit_model[idx],
            multiline = self.edit_multiline[idx],
            read_only = self.edit_read_only[idx],
            changed = self.edit_changed[idx],
            bounds = self.edit_bounds[idx],
        }
    end

    function q:key_routes_for(focused, chord, when)
        local out = {}
        local global_rows = self.key_ix[false]
        local global_indices = global_rows and global_rows[when] and global_rows[when][chord] or nil
        if global_indices then
            for i = 1, #global_indices do
                local idx = global_indices[i]
                out[#out + 1] = {
                    scope = self.key_scope[idx],
                    chord = self.key_chord[idx],
                    when = self.key_when[idx],
                    command = self.key_command[idx],
                    global = self.key_global[idx],
                }
            end
        end
        if focused ~= nil then
            local scoped_rows = self.key_ix[focused]
            local scoped_indices = scoped_rows and scoped_rows[when] and scoped_rows[when][chord] or nil
            if scoped_indices then
                for i = 1, #scoped_indices do
                    local idx = scoped_indices[i]
                    out[#out + 1] = {
                        scope = self.key_scope[idx],
                        chord = self.key_chord[idx],
                        when = self.key_when[idx],
                        command = self.key_command[idx],
                        global = self.key_global[idx],
                    }
                end
            end
        end
        return out
    end

    return q
end

local function positioned_origin(T, element, content_box, cursor_x, cursor_y, child_outer_w, child_outer_h)
    return U.match(element.layout.position, {
        InFlow = function()
            return { x = cursor_x, y = cursor_y, participates = true }
        end,
        Absolute = function(v)
            local left = U.match(v.left, {
                Unset = function() return nil end,
                EdgePx = function(px) return px.value end,
                EdgePercent = function(p) return content_box.w * p.value end,
            })
            local top = U.match(v.top, {
                Unset = function() return nil end,
                EdgePx = function(px) return px.value end,
                EdgePercent = function(p) return content_box.h * p.value end,
            })
            local right = U.match(v.right, {
                Unset = function() return nil end,
                EdgePx = function(px) return px.value end,
                EdgePercent = function(p) return content_box.w * p.value end,
            })
            local bottom = U.match(v.bottom, {
                Unset = function() return nil end,
                EdgePx = function(px) return px.value end,
                EdgePercent = function(p) return content_box.h * p.value end,
            })
            return {
                x = content_box.x + (left or ((right and (content_box.w - right - child_outer_w)) or 0)),
                y = content_box.y + (top or ((bottom and (content_box.h - bottom - child_outer_h)) or 0)),
                participates = false,
            }
        end,
        Anchored = function(_)
            error("UiDecl.Element.compile: Anchored position is not implemented yet", 3)
        end,
    })
end

local function add_behavior_routes(T, routes, element, border_box, content_box, content_size, depth)
    if not element.flags.visible or not element.flags.enabled then return end

    local semantic_ref = element.semantic_ref

    local hit_shape = U.match(element.behavior.hit, {
        HitNone = function() return nil end,
        HitSelf = function() return hit_shape_for(T, border_box, T.UiCore.Corners(0, 0, 0, 0)) end,
        HitSelfAndChildren = function() return hit_shape_for(T, border_box, T.UiCore.Corners(0, 0, 0, 0)) end,
        HitChildrenOnly = function() return nil end,
    })
    if hit_shape then
        routes.hits[#routes.hits + 1] = T.UiRouted.HitEntry(
            element.id,
            semantic_ref,
            hit_shape,
            depth
        )
    end

    U.match(element.behavior.focus, {
        NotFocusable = function() end,
        Focusable = function(v)
            routes.focus_chain[#routes.focus_chain + 1] = T.UiRouted.FocusEntry(
                element.id,
                semantic_ref,
                v.order or 0,
                v.mode,
                border_box
            )
        end,
    })

    for _, rule in ipairs(element.behavior.pointer) do
        routes.pointer_routes[#routes.pointer_routes + 1] = U.match(rule, {
            Hover = function(v)
                return T.UiRouted.HoverRoute(
                    element.id,
                    semantic_ref,
                    v.cursor,
                    v.enter,
                    v.leave
                )
            end,
            Press = function(v)
                return T.UiRouted.PressRoute(
                    element.id,
                    semantic_ref,
                    v.button,
                    v.click_count,
                    v.command
                )
            end,
            Toggle = function(v)
                return T.UiRouted.ToggleRoute(
                    element.id,
                    semantic_ref,
                    v.value,
                    v.button,
                    v.command
                )
            end,
            Gesture = function(v)
                return T.UiRouted.GestureRoute(
                    element.id,
                    semantic_ref,
                    v.gesture,
                    v.command
                )
            end,
        })
    end

    if element.behavior.scroll then
        routes.scroll_routes[#routes.scroll_routes + 1] = T.UiRouted.ScrollRoute(
            element.id,
            semantic_ref,
            element.behavior.scroll.axis,
            element.behavior.scroll.model,
            content_box,
            size(T, content_size.w, content_size.h)
        )
    end

    for _, rule in ipairs(element.behavior.keys) do
        routes.key_routes[#routes.key_routes + 1] = T.UiRouted.KeyRoute(
            rule.global and nil or element.id,
            rule.chord,
            rule.when,
            rule.command,
            rule.global
        )
    end

    if element.behavior.edit then
        routes.edit_routes[#routes.edit_routes + 1] = T.UiRouted.EditRoute(
            element.id,
            semantic_ref,
            element.behavior.edit.model,
            element.behavior.edit.multiline,
            element.behavior.edit.read_only,
            element.behavior.edit.changed,
            content_box
        )
    end
end

local function next_sibling_index(nodes, index)
    return nodes[index].subtree_end + 1
end

local function size_content_box(T, width, height, padding)
    return rect(T, 0, 0, max2(0, width - padding.left - padding.right), max2(0, height - padding.top - padding.bottom))
end

local function outer_for_child_guess(T, node, demand, available_w, available_h)
    local margin = node.layout.margin
    local padding = node.layout.padding
    local avail_w = max2(0, available_w - margin.left - margin.right)
    local avail_h = max2(0, available_h - margin.top - margin.bottom)
    local border_w = size_spec_value(node.layout.width, avail_w, demand.intrinsic_content.w + padding.left + padding.right)
    local border_h = size_spec_value(node.layout.height, avail_h, demand.intrinsic_content.h + padding.top + padding.bottom)
    return size(T, border_w + margin.left + margin.right, border_h + margin.top + margin.bottom)
end

local function flatten_entry(T, entry)
    local nodes = {}
    local next_index = 1

    local function flatten_node(node, parent_index)
        local index = next_index
        next_index = next_index + 1
        local first_child_index = (#node.children > 0) and next_index or nil

        for _, child in ipairs(node.children) do
            flatten_node(child, index)
        end

        nodes[index] = T.UiFlat.Node(
            index,
            parent_index,
            first_child_index,
            #node.children,
            next_index - 1,
            node.id,
            node.semantic_ref,
            node.debug_name,
            node.role,
            node.flags,
            node.layout,
            node.paint,
            node.content,
            node.behavior,
            node.accessibility
        )

        return index
    end

    return T.UiFlat.Region(
        entry.id,
        entry.debug_name,
        flatten_node(entry.root, nil),
        entry.z_index,
        entry.modal,
        entry.consumes_pointer,
        L(nodes)
    )
end

local function flatten_document(T, document, viewport)
    viewport = viewport or T.UiCore.Size(1280, 720)
    return T.UiFlat.Document(
        L(F.iter(document.entries):map(function(entry)
            return flatten_entry(T, entry)
        end):totable()),
        viewport
    )
end

local function demand_region(T, region, assets)
    return T.UiDemand.Region(
        region,
        L(F.iter(region.nodes):map(function(node)
            local intrinsic = content_intrinsic(T, assets, node.content)
            return T.UiDemand.Node(node.index, size(T, intrinsic.w, intrinsic.h))
        end):totable())
    )
end

local function demand_document(T, document, assets)
    return T.UiDemand.Document(
        L(F.iter(document.regions):map(function(region)
            return demand_region(T, region, assets)
        end):totable()),
        document.viewport
    )
end

local function resolve_region(T, region, viewport)
    local topology = region.topology.nodes
    local demands = region.nodes
    local outer = {}
    local child_extent = {}
    local resolved = {}

    local function compute_outer(index, available_w, available_h)
        if outer[index] then return outer[index] end

        local node = topology[index]
        local demand = demands[index]
        local margin = node.layout.margin
        local padding = node.layout.padding
        local avail_w = max2(0, available_w - margin.left - margin.right)
        local avail_h = max2(0, available_h - margin.top - margin.bottom)
        local border_w = size_spec_value(node.layout.width, avail_w, demand.intrinsic_content.w + padding.left + padding.right)
        local border_h = size_spec_value(node.layout.height, avail_h, demand.intrinsic_content.h + padding.top + padding.bottom)
        local content_box = size_content_box(T, border_w, border_h, padding)
        local flow = node.layout.flow

        if flow.kind ~= "None" and flow.kind ~= "Row" and flow.kind ~= "Column" and flow.kind ~= "Stack" then
            error("UiDecl.Element.compile currently supports only None/Row/Column/Stack flows", 3)
        end

        local cursor_x = content_box.x
        local cursor_y = content_box.y
        local max_w = 0
        local max_h = 0
        local child_index = node.first_child_index

        for _ = 1, node.child_count do
            local child = topology[child_index]
            local child_demand = demands[child_index]
            local remaining_w = (flow.kind == "Row") and max2(0, content_box.w - (cursor_x - content_box.x)) or content_box.w
            local remaining_h = (flow.kind == "Column") and max2(0, content_box.h - (cursor_y - content_box.y)) or content_box.h
            local child_guess = outer_for_child_guess(T, child, child_demand, remaining_w, remaining_h)
            local pos = positioned_origin(T, child, content_box, cursor_x, cursor_y, child_guess.w, child_guess.h)
            local child_outer = compute_outer(child_index, remaining_w, remaining_h)

            if pos.participates then
                if flow.kind == "Row" then
                    cursor_x = cursor_x + child_outer.w + node.layout.gap
                    max_w = max_w + child_outer.w + node.layout.gap
                    max_h = max2(max_h, child_outer.h)
                elseif flow.kind == "Column" then
                    cursor_y = cursor_y + child_outer.h + node.layout.gap
                    max_h = max_h + child_outer.h + node.layout.gap
                    max_w = max2(max_w, child_outer.w)
                else
                    max_w = max2(max_w, child_outer.w)
                    max_h = max2(max_h, child_outer.h)
                end
            else
                max_w = max2(max_w, child_outer.w)
                max_h = max2(max_h, child_outer.h)
            end

            child_index = next_sibling_index(topology, child_index)
        end

        if node.child_count > 0 then
            if flow.kind == "Row" then
                max_w = max_w - node.layout.gap
            elseif flow.kind == "Column" then
                max_h = max_h - node.layout.gap
            end
        end

        child_extent[index] = size(T, max2(0, max_w), max2(0, max_h))

        if is_auto_size_spec(node.layout.width) then
            border_w = max2(border_w, child_extent[index].w + padding.left + padding.right)
        end
        if is_auto_size_spec(node.layout.height) then
            border_h = max2(border_h, child_extent[index].h + padding.top + padding.bottom)
        end

        outer[index] = size(T, border_w + margin.left + margin.right, border_h + margin.top + margin.bottom)
        return outer[index]
    end

    local function place_node(index, origin_x, origin_y, parent_clip)
        local node = topology[index]
        local margin = node.layout.margin
        local padding = node.layout.padding
        local node_outer = outer[index]
        local border_w = max2(0, node_outer.w - margin.left - margin.right)
        local border_h = max2(0, node_outer.h - margin.top - margin.bottom)
        local border_box = rect(T, origin_x + margin.left, origin_y + margin.top, border_w, border_h)
        local content_box = inset_rect(T, border_box, padding)
        local local_clips = L(local_clip_shapes(T, node, border_box, content_box))
        local child_clip = top_clip(local_clips) or parent_clip

        resolved[index] = T.UiResolved.Node(
            index,
            node_outer,
            border_box,
            content_box,
            child_extent[index],
            local_clips,
            child_clip
        )

        local flow = node.layout.flow
        local cursor_x = content_box.x
        local cursor_y = content_box.y
        local child_index = node.first_child_index

        for _ = 1, node.child_count do
            local child = topology[child_index]
            local child_outer = outer[child_index]
            local pos = positioned_origin(T, child, content_box, cursor_x, cursor_y, child_outer.w, child_outer.h)
            place_node(child_index, pos.x, pos.y, child_clip)

            if pos.participates then
                if flow.kind == "Row" then
                    cursor_x = cursor_x + child_outer.w + node.layout.gap
                elseif flow.kind == "Column" then
                    cursor_y = cursor_y + child_outer.h + node.layout.gap
                end
            end

            child_index = next_sibling_index(topology, child_index)
        end
    end

    compute_outer(region.topology.root_index, viewport.w, viewport.h)
    place_node(region.topology.root_index, 0, 0, nil)

    return T.UiResolved.Region(region.topology, demands, L(resolved))
end

local function resolve_document(T, document)
    return T.UiResolved.Document(
        L(F.iter(document.regions):map(function(region)
            return resolve_region(T, region, document.viewport)
        end):totable()),
        document.viewport
    )
end

local function build_routed_scene(T, routes)
    return T.UiRouted.Scene(
        L(routes.hits),
        L(routes.focus_chain),
        L(routes.pointer_routes),
        L(routes.scroll_routes),
        L(routes.key_routes),
        L(routes.edit_routes),
        L(routes.accessibility)
    )
end

local function plan_region(T, region, assets)
    local topology = region.topology.nodes
    local resolved = region.nodes

    local function plan_node(index, parent_clip, depth)
        local node = topology[index]
        local box = resolved[index]
        local routes = empty_routes()

        if not node.flags.visible then
            routes.accessibility[#routes.accessibility + 1] = accessibility_tree(T, node, box.border_box, {})
            return routes
        end

        add_behavior_routes(T, routes, node, box.border_box, box.content_box, box.child_extent, depth)

        local local_batches = {}
        emit_paint_batches(T, assets, local_batches, parent_clip, box.border_box, {
            box = box.content_box,
            content = node.content,
        }, node.paint.ops)

        local accessibility_children = {}
        local child_index = node.first_child_index
        for _ = 1, node.child_count do
            local child_routes = plan_node(child_index, box.active_clip, depth + 1)
            merge_flat_routes(routes, child_routes)
            append_all(accessibility_children, child_routes.accessibility)
            child_index = next_sibling_index(topology, child_index)
        end

        emit_post_batches(T, local_batches, parent_clip, node.paint.ops)
        append_all(routes.batches, local_batches)
        routes.accessibility[#routes.accessibility + 1] = accessibility_tree(T, node, box.border_box, accessibility_children)

        return routes
    end

    local routes = plan_node(region.topology.root_index, nil, region.topology.z_index)
    return T.UiPlan.Region(
        L(routes.batches),
        L(routes.hits),
        L(routes.focus_chain),
        L(routes.pointer_routes),
        L(routes.scroll_routes),
        L(routes.key_routes),
        L(routes.edit_routes),
        L(routes.accessibility)
    )
end

local function plan_document(T, document, assets)
    return T.UiPlan.Component(
        L(F.iter(document.regions):map(function(region)
            return plan_region(T, region, assets)
        end):totable()),
        document.viewport
    )
end

return function(T)
    T.UiDecl.Document.bind = U.transition(function(document)
        local roots = F.iter(document.roots):map(function(root)
            return T.UiBound.Entry(
                root.id,
                root.debug_name,
                bind_element(T, root.root),
                0,
                false,
                false
            )
        end)
        local overlays = F.iter(document.overlays):map(function(overlay)
            return T.UiBound.Entry(
                overlay.id,
                overlay.debug_name,
                bind_element(T, overlay.root),
                overlay.z_index,
                overlay.modal,
                overlay.consumes_pointer
            )
        end)
        return T.UiBound.Document(L(F.chain(roots, overlays):totable()))
    end)

    T.UiBound.Entry.flat = U.transition(function(entry)
        return flatten_entry(T, entry)
    end)

    T.UiBound.Document.flat = U.transition(function(document, viewport)
        viewport = viewport or T.UiCore.Size(1280, 720)
        return T.UiFlat.Document(L(F.iter(document.entries):map(function(entry)
            return entry:flat()
        end):totable()), viewport)
    end)

    T.UiFlat.Region.demand = U.transition(function(region, assets)
        return demand_region(T, region, assets)
    end)

    T.UiFlat.Document.demand = U.transition(function(document, assets)
        return T.UiDemand.Document(L(F.iter(document.regions):map(function(region)
            return region:demand(assets)
        end):totable()), document.viewport)
    end)

    T.UiDemand.Region.resolve = U.transition(function(region, viewport)
        return resolve_region(T, region, viewport)
    end)

    T.UiDemand.Document.resolve = U.transition(function(document)
        return T.UiResolved.Document(L(F.iter(document.regions):map(function(region)
            return region:resolve(document.viewport)
        end):totable()), document.viewport)
    end)

    T.UiResolved.Region.plan = U.transition(function(region, assets)
        return plan_region(T, region, assets)
    end)

    T.UiResolved.Document.plan = U.transition(function(document, assets)
        return T.UiPlan.Component(L(F.iter(document.regions):map(function(region)
            return region:plan(assets)
        end):totable()), document.viewport)
    end)

    T.UiBound.Document.plan = U.transition(function(document, assets, viewport)
        return document:flat(viewport):demand(assets):resolve():plan(assets)
    end)

    T.UiPlan.Component.compile = U.terminal(function(component, assets)
        local routes = empty_routes()
        local batches = {}

        F.iter(component.regions):each(function(region)
            append_all(batches, region.batches)
            append_all(routes.hits, region.hits)
            append_all(routes.focus_chain, region.focus_chain)
            append_all(routes.pointer_routes, region.pointer_routes)
            append_all(routes.scroll_routes, region.scroll_routes)
            append_all(routes.key_routes, region.key_routes)
            append_all(routes.edit_routes, region.edit_routes)
            append_all(routes.accessibility, region.accessibility)
        end)

        local scene = T.UiBatched.Scene(L(batches), rect(T, 0, 0, component.viewport.w, component.viewport.h))
        local routed = build_routed_scene(T, routes)
        local unit = scene:compile(assets)
        unit.routes = routed
        unit.route_queries = build_route_queries(routed)
        unit.viewport = component.viewport
        return unit
    end)

    T.UiDecl.Document.compile = U.terminal(function(document, assets, viewport)
        return document:bind():flat(viewport):demand(assets):resolve():plan(assets):compile(assets)
    end)
end
