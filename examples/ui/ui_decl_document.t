local U = require("unit")
local F = require("fun")
local Text = require("examples.ui.ui_text_resolve")

local unpack_fn = table.unpack or unpack

local function L(xs)
    return terralib.newlist(xs or {})
end

local function chain_lists(lists)
    if #lists == 0 then return L() end
    return L(F.chain(unpack_fn(lists)):totable())
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

local function local_clip_shapes(T, element, border_box, content_box)
    local paint_clips = F.iter(element.paint.ops)
        :map(function(op)
            return U.match(op, {
                Box = function(_) return nil end,
                Shadow = function(_) return nil end,
                Clip = function(v)
                    return clip_shape_for(T, border_box, v.corners)
                end,
                Opacity = function(_) return nil end,
                Transform = function(_) return nil end,
                Blend = function(_) return nil end,
                CustomPaint = function(_) return nil end,
            })
        end)
        :filter(function(v) return v ~= nil end)
        :totable()

    local overflow_clip = (
        element.layout.overflow_x.kind ~= "Visible"
        or element.layout.overflow_y.kind ~= "Visible"
    ) and clip_shape_for(T, content_box, T.UiCore.Corners(0, 0, 0, 0)) or nil

    if overflow_clip then
        paint_clips[#paint_clips + 1] = overflow_clip
    end

    return L(paint_clips)
end

local function text_intrinsic(T, assets, content)
    local m = Text.measure(T, assets, nil, content.value, content.style, content.layout, nil)
    return { w = m.w, h = m.h }
end

local function image_intrinsic()
    return { w = 64, h = 64 }
end

local function content_intrinsic(T, assets, content)
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
end

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

local function content_draws(T, assets, content, content_box)
    return U.match(content, {
        NoContent = function()
            return L()
        end,
        Text = function(v)
            return L {
                T.UiLaid.TextDraw(
                    Text.shape(T, assets, nil, v.value, v.style, v.layout, content_box)
                )
            }
        end,
        Image = function(v)
            return L {
                T.UiLaid.ImageDraw(v.image, content_box, v.style)
            }
        end,
        CustomContent = function(v)
            return L {
                T.UiLaid.CustomDraw(v.kind, v.payload, content_box)
            }
        end,
    })
end

local function paint_draws(T, element, border_box)
    return L(F.iter(element.paint.ops):map(function(op)
        return U.match(op, {
            Box = function(v)
                return T.UiLaid.BoxDraw(border_box, v.fill, v.stroke, v.stroke_width, v.align, v.corners)
            end,
            Shadow = function(v)
                return T.UiLaid.ShadowDraw(border_box, v.brush, v.blur, v.spread, v.dx, v.dy, v.kind, v.corners)
            end,
            Clip = function(v)
                return T.UiLaid.ClipDraw(clip_shape_for(T, border_box, v.corners))
            end,
            Opacity = function(v)
                return T.UiLaid.OpacityDraw(v.value)
            end,
            Transform = function(v)
                return T.UiLaid.TransformDraw(v.xform)
            end,
            Blend = function(v)
                return T.UiLaid.BlendDraw(v.mode)
            end,
            CustomPaint = function(v)
                return T.UiLaid.CustomDraw(v.kind, v.payload, border_box)
            end,
        })
    end):totable())
end

local function pointer_nodes(T, behavior)
    return L(F.iter(behavior.pointer):map(function(rule)
        return U.match(rule, {
            Hover = function(v)
                return T.UiLaid.Hover(v.cursor, v.enter, v.leave)
            end,
            Press = function(v)
                return T.UiLaid.Press(v.button, v.click_count, v.command)
            end,
            Toggle = function(v)
                return T.UiLaid.Toggle(v.value, v.button, v.command)
            end,
            Gesture = function(v)
                return T.UiLaid.Gesture(v.gesture, v.command)
            end,
        })
    end):totable())
end

local function key_nodes(T, behavior)
    return L(F.iter(behavior.keys):map(function(rule)
        return T.UiLaid.KeyNode(rule.chord, rule.when, rule.command, rule.global)
    end):totable())
end

local function drag_nodes(T, behavior)
    return L(F.iter(behavior.drag_drop):map(function(rule)
        return U.match(rule, {
            Draggable = function(v)
                return T.UiLaid.Draggable(v.payload, v.begin, v.finish)
            end,
            DropTarget = function(v)
                return T.UiLaid.DropTarget(v.policy, v.command)
            end,
        })
    end):totable())
end

local function behavior_node(T, element, border_box, content_box, content_size)
    local focus = U.match(element.behavior.focus, {
        NotFocusable = function()
            return nil
        end,
        Focusable = function(v)
            return T.UiLaid.FocusNode(v.mode, v.order or 0, border_box)
        end,
    })

    local hit_shape = U.match(element.behavior.hit, {
        HitNone = function() return nil end,
        HitSelf = function() return hit_shape_for(T, border_box, T.UiCore.Corners(0,0,0,0)) end,
        HitSelfAndChildren = function() return hit_shape_for(T, border_box, T.UiCore.Corners(0,0,0,0)) end,
        HitChildrenOnly = function() return nil end,
    })

    local scroll = element.behavior.scroll and T.UiLaid.ScrollNode(
        element.behavior.scroll.axis,
        element.behavior.scroll.model,
        content_box,
        size(T, content_size.w, content_size.h)
    ) or nil

    local edit = element.behavior.edit and T.UiLaid.EditNode(
        element.behavior.edit.model,
        element.behavior.edit.multiline,
        element.behavior.edit.read_only,
        element.behavior.edit.changed,
        content_box
    ) or nil

    return T.UiLaid.BehaviorNode(
        hit_shape,
        focus,
        pointer_nodes(T, element.behavior),
        scroll,
        key_nodes(T, element.behavior),
        edit,
        drag_nodes(T, element.behavior)
    )
end

local function accessibility_node(T, element, border_box)
    return T.UiLaid.Accessibility(
        element.accessibility.role,
        element.accessibility.label,
        element.accessibility.description,
        element.accessibility.hidden,
        element.accessibility.sort_priority,
        border_box
    )
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
            error("UiDecl.Element:layout_element: Anchored position is not implemented yet", 3)
        end,
    })
end

local function layout_children(T, assets, children, flow, gap, content_box, inherited_clips, available_inner)
    local cursor_x = content_box.x
    local cursor_y = content_box.y
    local max_w = 0
    local max_h = 0

    local laid = F.iter(children):map(function(child)
        local child_intrinsic = content_intrinsic(T, assets, child.content)
        local child_avail = size(T, available_inner.w, available_inner.h)
        local margin = child.layout.margin
        local child_outer_guess_w = size_spec_value(child.layout.width, available_inner.w, child_intrinsic.w) + margin.left + margin.right
        local child_outer_guess_h = size_spec_value(child.layout.height, available_inner.h, child_intrinsic.h) + margin.top + margin.bottom
        local pos = positioned_origin(T, child, content_box, cursor_x, cursor_y, child_outer_guess_w, child_outer_guess_h)
        local laid_child, outer = layout_element(T, assets, child, pos.x, pos.y, child_avail, inherited_clips)

        if pos.participates then
            if flow.kind == "Row" then
                cursor_x = cursor_x + outer.w + gap
                max_w = max_w + outer.w + gap
                max_h = max2(max_h, outer.h)
            elseif flow.kind == "Column" then
                cursor_y = cursor_y + outer.h + gap
                max_h = max_h + outer.h + gap
                max_w = max2(max_w, outer.w)
            else
                max_w = max2(max_w, outer.w)
                max_h = max2(max_h, outer.h)
            end
        else
            max_w = max2(max_w, outer.w)
            max_h = max2(max_h, outer.h)
        end

        return laid_child
    end):totable()

    if #laid > 0 then
        if flow.kind == "Row" then
            max_w = max_w - gap
        elseif flow.kind == "Column" then
            max_h = max_h - gap
        end
    end

    return L(laid), { w = max2(0, max_w), h = max2(0, max_h) }
end

function layout_element(T, assets, element, origin_x, origin_y, available_size, inherited_clips)
    local intrinsic = content_intrinsic(T, assets, element.content)
    local margin = element.layout.margin
    local padding = element.layout.padding

    local avail_w = max2(0, available_size.w - margin.left - margin.right)
    local avail_h = max2(0, available_size.h - margin.top - margin.bottom)

    local border_w = size_spec_value(element.layout.width, avail_w, intrinsic.w + padding.left + padding.right)
    local border_h = size_spec_value(element.layout.height, avail_h, intrinsic.h + padding.top + padding.bottom)

    local border_box = rect(T, origin_x + margin.left, origin_y + margin.top, border_w, border_h)
    local content_box = inset_rect(T, border_box, padding)
    local inner_avail = size(T, content_box.w, content_box.h)
    local tentative_local_clips = local_clip_shapes(T, element, border_box, content_box)
    local tentative_child_clips = chain_lists { inherited_clips, tentative_local_clips }

    local flow = element.layout.flow
    if flow.kind ~= "None" and flow.kind ~= "Row" and flow.kind ~= "Column" and flow.kind ~= "Stack" then
        error("UiDecl.Document:layout currently supports only None/Row/Column/Stack flows", 3)
    end

    local laid_children, child_extent = layout_children(
        T,
        assets,
        element.children,
        flow,
        element.layout.gap,
        content_box,
        tentative_child_clips,
        inner_avail
    )

    if is_auto_size_spec(element.layout.width) then
        border_w = max2(border_w, child_extent.w + padding.left + padding.right)
    end
    if is_auto_size_spec(element.layout.height) then
        border_h = max2(border_h, child_extent.h + padding.top + padding.bottom)
    end

    border_box = rect(T, origin_x + margin.left, origin_y + margin.top, border_w, border_h)
    content_box = inset_rect(T, border_box, padding)

    local local_clips = local_clip_shapes(T, element, border_box, content_box)

    local scroll_extent = (element.behavior.scroll or element.layout.overflow_x.kind ~= "Visible" or element.layout.overflow_y.kind ~= "Visible")
        and T.UiCore.ScrollExtent(child_extent.w, child_extent.h, 0, 0)
        or nil

    local draws = chain_lists {
        paint_draws(T, element, border_box),
        content_draws(T, assets, element.content, content_box),
    }

    local laid = T.UiLaid.Element(
        element.id,
        element.semantic_ref,
        element.debug_name,
        element.role,
        element.flags.visible,
        element.flags.enabled,
        border_box,
        content_box,
        content_box,
        scroll_extent,
        inherited_clips,
        draws,
        behavior_node(T, element, border_box, content_box, child_extent),
        accessibility_node(T, element, border_box),
        laid_children
    )

    return laid, {
        w = border_box.w + margin.left + margin.right,
        h = border_box.h + margin.top + margin.bottom,
    }
end

return function(T)
    T.UiDecl.Document.layout = U.transition(function(document, assets, viewport)
        viewport = viewport or T.UiCore.Size(1280, 720)
        local root_bounds = size(T, viewport.w, viewport.h)
        local clips = L()

        local roots = L(F.iter(document.roots):map(function(root)
            local laid_root = select(1, layout_element(T, assets, root.root, 0, 0, root_bounds, clips))
            return T.UiLaid.Root(root.id, root.debug_name, laid_root)
        end):totable())

        local overlays = L(F.iter(document.overlays):map(function(overlay)
            local laid_root = select(1, layout_element(T, assets, overlay.root, 0, 0, root_bounds, clips))
            return T.UiLaid.Overlay(
                overlay.id,
                overlay.debug_name,
                laid_root,
                overlay.z_index,
                overlay.modal,
                overlay.consumes_pointer
            )
        end):totable())

        return T.UiLaid.Scene(roots, overlays, viewport)
    end)
end
