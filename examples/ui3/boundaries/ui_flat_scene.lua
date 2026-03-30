local asdl = require("asdl")
local U = require("unit")
local F = require("fun")
local Assets = require("examples.ui.ui_asset_resolve")
local RawText = require("examples.ui.backend_text_sdl_ttf")
local ImageData = require("examples.ui.backend_image_sdl")

local L = asdl.List

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

-- ============================================================================
-- UiFlat.Scene -> lower_render_facts -> UiRenderFacts.Scene
-- ----------------------------------------------------------------------------
-- ui3 Layer 4 (render branch): lower aligned flat/source-side render truth into
-- render-specific facts that can later be joined with solved geometry.
--
-- What this boundary consumes:
--   - shared flat headers/topology
--   - source-side visibility truth
--   - flat content source
--   - flat paint source
--   - render-region facets
--
-- What this boundary produces:
--   - render-region z ordering
--   - node-aligned render facts
--   - explicit effects / decorations / render content / use facts
--
-- What this boundary intentionally does NOT do:
--   - no geometry solving
--   - no occurrence projection
--   - no resource key assignment
--   - no machine packing
-- ============================================================================

local DEFAULT_IMAGE_INTRINSIC_W = 64
local DEFAULT_IMAGE_INTRINSIC_H = 64

local function Ls(xs)
    return L(xs or {})
end

local function require_catalog(catalog, where)
    if catalog then return catalog end
    error((where or "UiFlat.Scene:lower_geometry") .. ": UiAsset.Catalog is required", 3)
end

local function hidden_render_fact(T)
    return T.UiRenderFacts.Fact(
        Ls(),
        Ls(),
        C(T.UiRenderFacts.NoContent),
        C(T.UiRenderFacts.DefaultUse)
    )
end

local function lower_effect(T, op)
    return U.match(op, {
        Box = function(_) return nil end,
        Shadow = function(_) return nil end,
        Clip = function(v)
            return T.UiRenderFacts.LocalClip(v.corners)
        end,
        Opacity = function(v)
            return T.UiRenderFacts.LocalOpacity(v.value)
        end,
        Transform = function(v)
            return T.UiRenderFacts.LocalTransform(v.xform)
        end,
        Blend = function(v)
            return T.UiRenderFacts.LocalBlend(v.mode)
        end,
        CustomPaint = function(_)
            return nil
        end,
    })
end

local function lower_decoration(T, op)
    return U.match(op, {
        Box = function(v)
            return T.UiRenderFacts.BoxDecor(
                v.fill,
                v.stroke,
                v.stroke_width,
                v.align,
                v.corners
            )
        end,
        Shadow = function(v)
            return T.UiRenderFacts.ShadowDecor(
                v.brush,
                v.blur,
                v.spread,
                v.dx,
                v.dy,
                v.shadow_kind,
                v.corners
            )
        end,
        Clip = function(_) return nil end,
        Opacity = function(_) return nil end,
        Transform = function(_) return nil end,
        Blend = function(_) return nil end,
        CustomPaint = function(v)
            return T.UiRenderFacts.CustomDecor(v.family, v.payload)
        end,
    })
end

local function lower_content(T, content)
    return U.match(content, {
        NoContent = function()
            return C(T.UiRenderFacts.NoContent), C(T.UiRenderFacts.DefaultUse)
        end,
        Text = function(v)
            return T.UiRenderFacts.Text(
                T.UiRenderFacts.TextContent(
                    v.text.value,
                    v.text.style.font,
                    v.text.style.size_px,
                    v.text.style.weight,
                    v.text.style.slant,
                    v.text.style.letter_spacing_px,
                    v.text.style.line_height_px,
                    v.text.style.color,
                    v.text.layout.wrap,
                    v.text.layout.overflow,
                    v.text.layout.align,
                    v.text.layout.line_limit
                )
            ), C(T.UiRenderFacts.DefaultUse)
        end,
        Image = function(v)
            return T.UiRenderFacts.Image(
                T.UiRenderFacts.ImageContent(
                    v.image,
                    v.style.fit,
                    v.style.sampling
                )
            ), T.UiRenderFacts.ImageUse(T.UiCore.Corners(0, 0, 0, 0))
        end,
        InlineCustomContent = function(v)
            return T.UiRenderFacts.Custom(
                T.UiRenderFacts.InlineCustomContent(v.family, v.payload)
            ), C(T.UiRenderFacts.DefaultUse)
        end,
        ResourceCustomContent = function(v)
            return T.UiRenderFacts.Custom(
                T.UiRenderFacts.ResourceCustomContent(
                    v.family,
                    v.resource_payload,
                    v.instance_payload
                )
            ), C(T.UiRenderFacts.DefaultUse)
        end,
    })
end

local function use_for_content(T, content, current_use)
    return U.match(content, {
        NoContent = function()
            return current_use
        end,
        Text = function()
            return current_use
        end,
        Image = function()
            return T.UiRenderFacts.ImageUse(T.UiCore.Corners(0, 0, 0, 0))
        end,
        InlineCustomContent = function()
            return current_use
        end,
        ResourceCustomContent = function()
            return current_use
        end,
    })
end

local function image_use_from_ops(T, ops, current_use)
    return F.iter(ops):reduce(function(use, op)
        return U.match(op, {
            Box = function(v)
                return T.UiRenderFacts.ImageUse(v.corners)
            end,
            Shadow = function(_)
                return use
            end,
            Clip = function(_)
                return use
            end,
            Opacity = function(_)
                return use
            end,
            Transform = function(_)
                return use
            end,
            Blend = function(_)
                return use
            end,
            CustomPaint = function(_)
                return use
            end,
        })
    end, current_use)
end

local function fact_for_node(T, visible, content_facet, paint_facet)
    if not visible then
        return hidden_render_fact(T)
    end

    local content, base_use = lower_content(T, content_facet.content)
    local effects = F.iter(paint_facet.paint.ops):reduce(function(rows, op)
        local lowered = lower_effect(T, op)
        if lowered ~= nil then rows[#rows + 1] = lowered end
        return rows
    end, {})
    local decorations = F.iter(paint_facet.paint.ops):reduce(function(rows, op)
        local lowered = lower_decoration(T, op)
        if lowered ~= nil then rows[#rows + 1] = lowered end
        return rows
    end, {})
    local use = image_use_from_ops(T, paint_facet.paint.ops, use_for_content(T, content_facet.content, base_use))

    return T.UiRenderFacts.Fact(
        Ls(effects),
        Ls(decorations),
        content,
        use
    )
end

local function max2(a, b)
    return a > b and a or b
end

local function text_style_for(T, text)
    return T.UiCore.TextStyle(
        text.style.font,
        text.style.size_px,
        text.style.weight,
        text.style.slant,
        text.style.letter_spacing_px,
        text.style.line_height_px,
        text.style.color
    )
end

local function text_layout_for(T, text, wrap)
    return T.UiCore.TextLayout(
        wrap or text.layout.wrap,
        text.layout.overflow,
        text.layout.align,
        text.layout.line_limit
    )
end

local function font_path_for(assets, caches, font)
    local key = font and font.value or 0
    local cached = caches.font_paths[key]
    if cached ~= nil then return cached end
    local path = Assets.font_path(require_catalog(assets, "UiFlat.Scene:lower_geometry"), font)
    caches.font_paths[key] = path
    return path
end

local function text_string(value)
    local raw = value and value.value or value or ""
    if type(raw) == "cdata" then
        return tostring(raw)
    end
    return raw
end

local function key_part(v)
    if v == nil then return "" end
    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then
        return tostring(v)
    end
    if tv == "cdata" then
        return tostring(v)
    end
    if tv == "table" then
        if v.value ~= nil then return key_part(v.value) end
        if v.kind ~= nil then return tostring(v.kind) end
    end
    return tostring(v)
end

local function text_intrinsic_key(text)
    return table.concat({
        key_part(text.value and text.value.value or text.value),
        key_part(text.style.font and text.style.font.value or text.style.font),
        key_part(text.style.size_px),
        key_part(text.style.weight and text.style.weight.kind or text.style.weight),
        key_part(text.style.slant and text.style.slant.kind or text.style.slant),
        key_part(text.style.letter_spacing_px),
        key_part(text.style.line_height_px),
        key_part(text.layout.wrap and text.layout.wrap.kind or text.layout.wrap),
    }, "\31")
end

local function image_intrinsic_key(image_ref)
    return key_part(image_ref and image_ref.value or image_ref)
end

local function measure_text(T, assets, caches, text, wrap, max_width)
    local measured = RawText.measure(
        nil,
        font_path_for(assets, caches, text.style.font),
        text.value,
        text_style_for(T, text),
        text_layout_for(T, text, wrap),
        max_width
    )
    return T.UiCore.Size(measured.w, measured.h)
end

local function max_word_width(T, assets, caches, text)
    local raw = text_string(text.value)
    local best = 0

    for word in raw:gmatch("%S+") do
        local measured = RawText.measure(
            nil,
            font_path_for(assets, caches, text.style.font),
            T.UiCore.TextValue(word),
            text_style_for(T, text),
            text_layout_for(T, text, C(T.UiCore.NoWrap)),
            nil
        )
        best = max2(best, measured.w)
    end

    return best
end

local function max_char_width(T, assets, caches, text)
    local raw = text_string(text.value)
    local best = 0

    local ok = pcall(function()
        for _, codepoint in utf8.codes(raw) do
            local ch = utf8.char(codepoint)
            local measured = RawText.measure(
                nil,
                font_path_for(assets, caches, text.style.font),
                T.UiCore.TextValue(ch),
                text_style_for(T, text),
                text_layout_for(T, text, C(T.UiCore.NoWrap)),
                nil
            )
            best = max2(best, measured.w)
        end
    end)

    if ok then return best end
    return measure_text(T, assets, caches, text, C(T.UiCore.NoWrap), nil).w
end

local function text_intrinsic(T, assets, caches, text)
    local key = text_intrinsic_key(text)
    local cached = caches.text_intrinsics[key]
    if cached ~= nil then return cached end

    local max_content = measure_text(T, assets, caches, text, C(T.UiCore.NoWrap), nil)
    local min_content_w = U.match(text.layout.wrap, {
        NoWrap = function()
            return max_content.w
        end,
        WrapWord = function()
            return max_word_width(T, assets, caches, text)
        end,
        WrapChar = function()
            return max_char_width(T, assets, caches, text)
        end,
    })

    local intrinsic = T.UiGeometryInput.IntrinsicMetrics(
        min_content_w,
        text.style.line_height_px,
        max_content.w,
        text.style.line_height_px
    )
    caches.text_intrinsics[key] = intrinsic
    return intrinsic
end

local function image_intrinsic(T, assets, caches, image_ref)
    local key = image_intrinsic_key(image_ref)
    local cached = caches.image_intrinsics[key]
    if cached ~= nil then return cached end

    local path = Assets.image_path(require_catalog(assets, "UiFlat.Scene:lower_geometry"), image_ref)
    local ok, w, h = pcall(ImageData.size, path)
    local intrinsic = (ok and w and h)
        and T.UiGeometryInput.IntrinsicMetrics(w, h, w, h)
        or T.UiGeometryInput.IntrinsicMetrics(
            DEFAULT_IMAGE_INTRINSIC_W,
            DEFAULT_IMAGE_INTRINSIC_H,
            DEFAULT_IMAGE_INTRINSIC_W,
            DEFAULT_IMAGE_INTRINSIC_H
        )
    caches.image_intrinsics[key] = intrinsic
    return intrinsic
end

local function intrinsic_for_content(T, assets, caches, content)
    return U.match(content, {
        NoContent = function()
            return T.UiGeometryInput.IntrinsicMetrics(0, 0, 0, 0)
        end,
        Text = function(v)
            return text_intrinsic(T, assets, caches, v.text)
        end,
        Image = function(v)
            return image_intrinsic(T, assets, caches, v.image)
        end,
        InlineCustomContent = function(_)
            error("UiFlat.Scene:lower_geometry: custom content needs an explicit geometry intrinsic contract", 3)
        end,
        ResourceCustomContent = function(_)
            error("UiFlat.Scene:lower_geometry: custom content needs an explicit geometry intrinsic contract", 3)
        end,
    })
end

local function region_id_map(headers)
    return F.iter(headers):reduce(function(acc, header)
        acc[header.id.value] = header.index
        return acc
    end, {})
end

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

local function lower_measure(measure)
    return U.match(measure, {
        Auto = function()
            return MEASURE_AUTO, 0
        end,
        Px = function(v)
            return MEASURE_PX, v.value
        end,
        Percent = function(v)
            return MEASURE_PERCENT, v.value
        end,
        Content = function()
            return MEASURE_CONTENT, 0
        end,
        Flex = function(v)
            return MEASURE_FLEX, v.weight
        end,
    })
end

local function lower_axis_spec(T, spec)
    local min_mode, min_value = lower_measure(spec.min)
    local preferred_mode, preferred_value = lower_measure(spec.preferred)
    local max_mode, max_value = lower_measure(spec.max)
    return T.UiGeometryInput.AxisSpec(
        min_mode,
        min_value,
        preferred_mode,
        preferred_value,
        max_mode,
        max_value
    )
end

local function lower_edge_measure(edge)
    return U.match(edge, {
        Unset = function()
            return EDGE_UNSET, 0
        end,
        EdgePx = function(v)
            return EDGE_PX, v.value
        end,
        EdgePercent = function(v)
            return EDGE_PERCENT, v.value
        end,
    })
end

local function lower_anchor(anchor)
    return U.match(anchor, {
        Left = function() return ANCHOR_START end,
        Top = function() return ANCHOR_START end,
        CenterX = function() return ANCHOR_CENTER end,
        CenterY = function() return ANCHOR_CENTER end,
        Right = function() return ANCHOR_END end,
        Bottom = function() return ANCHOR_END end,
    })
end

local function lower_position_op(T, ids, position)
    return U.match(position, {
        InFlow = function()
            return T.UiGeometryInput.PositionOp(
                POSITION_INFLOW,
                -1,
                EDGE_UNSET, 0,
                EDGE_UNSET, 0,
                EDGE_UNSET, 0,
                EDGE_UNSET, 0,
                ANCHOR_START,
                ANCHOR_START,
                ANCHOR_START,
                ANCHOR_START,
                0,
                0
            )
        end,
        Absolute = function(v)
            local left_mode, left_value = lower_edge_measure(v.left)
            local top_mode, top_value = lower_edge_measure(v.top)
            local right_mode, right_value = lower_edge_measure(v.right)
            local bottom_mode, bottom_value = lower_edge_measure(v.bottom)
            return T.UiGeometryInput.PositionOp(
                POSITION_ABSOLUTE,
                -1,
                left_mode,
                left_value,
                top_mode,
                top_value,
                right_mode,
                right_value,
                bottom_mode,
                bottom_value,
                ANCHOR_START,
                ANCHOR_START,
                ANCHOR_START,
                ANCHOR_START,
                0,
                0
            )
        end,
        AnchoredTo = function(v)
            local target_index = ids[v.target.value]
            if target_index == nil then
                error("UiFlat.Scene:lower_geometry: anchored target is not in the same flat region", 3)
            end
            return T.UiGeometryInput.PositionOp(
                POSITION_ANCHORED,
                target_index,
                EDGE_UNSET, 0,
                EDGE_UNSET, 0,
                EDGE_UNSET, 0,
                EDGE_UNSET, 0,
                lower_anchor(v.self_x),
                lower_anchor(v.self_y),
                lower_anchor(v.target_x),
                lower_anchor(v.target_y),
                v.dx,
                v.dy
            )
        end,
    })
end

local function lower_flow_op(T, layout)
    local source = layout.source
    if source.grid ~= nil then
        error("UiFlat.Scene:lower_geometry: grid template is not yet supported by the solver", 3)
    end
    if source.cell ~= nil then
        error("UiFlat.Scene:lower_geometry: grid cell placement is not yet supported by the solver", 3)
    end
    if source.aspect ~= nil then
        error("UiFlat.Scene:lower_geometry: aspect-constrained geometry is not yet supported by the solver", 3)
    end

    return U.match(source.flow, {
        None = function()
            return T.UiGeometryInput.FlowOp(FLOW_NONE, source.gap)
        end,
        Row = function()
            return T.UiGeometryInput.FlowOp(FLOW_ROW, source.gap)
        end,
        Column = function()
            return T.UiGeometryInput.FlowOp(FLOW_COLUMN, source.gap)
        end,
        Stack = function()
            return T.UiGeometryInput.FlowOp(FLOW_STACK, source.gap)
        end,
        Wrap = function()
            error("UiFlat.Scene:lower_geometry: wrap flow is not yet supported by the solver", 3)
        end,
        Grid = function()
            error("UiFlat.Scene:lower_geometry: grid flow is not yet supported by the solver", 3)
        end,
    })
end

local function lower_scroll_model(T, layout)
    local source = layout.source
    return T.UiGeometryInput.ScrollModel(
        source.overflow_x.kind ~= "Visible",
        source.overflow_y.kind ~= "Visible"
    )
end

local function included_in_layout(_visible, layout_facet)
    return layout_facet.layout.position.kind == "InFlow"
end

local function lower_geometry_region(T, region, assets, caches)
    local n = #region.headers
    if #region.visibility ~= n or #region.layout ~= n or #region.content ~= n then
        error("UiFlat.Scene:lower_geometry: flat region facet lengths do not match headers", 3)
    end

    local ids = region_id_map(region.headers)
    local effective_visible = {}
    local participation = {}
    local width_specs = {}
    local height_specs = {}
    local positions = {}
    local flows = {}
    local paddings = {}
    local margins = {}
    local scroll_models = {}
    local intrinsics = {}

    local i = 1
    while i <= n do
        local header = region.headers[i]
        local parent_visible = true
        if header.parent_index ~= nil then
            parent_visible = effective_visible[header.parent_index + 1]
        end
        local visible = region.visibility[i].visible and parent_visible
        local layout = region.layout[i].layout
        local source = layout.source
        effective_visible[i] = visible
        participation[i] = T.UiGeometryInput.Participation(included_in_layout(visible, region.layout[i]))
        width_specs[i] = lower_axis_spec(T, source.width)
        height_specs[i] = lower_axis_spec(T, source.height)
        positions[i] = lower_position_op(T, ids, layout.position)
        flows[i] = lower_flow_op(T, layout)
        paddings[i] = source.padding
        margins[i] = source.margin
        scroll_models[i] = lower_scroll_model(T, layout)
        intrinsics[i] = intrinsic_for_content(T, assets, caches, region.content[i].content)
        i = i + 1
    end

    return T.UiGeometryInput.Region(
        region.header,
        region.headers,
        Ls(participation),
        Ls(width_specs),
        Ls(height_specs),
        Ls(positions),
        Ls(flows),
        Ls(paddings),
        Ls(margins),
        Ls(scroll_models),
        Ls(intrinsics)
    )
end

local function lower_hit_fact(T, hit)
    return U.match(hit, {
        HitNone = function() return C(T.UiQueryFacts.NoHit) end,
        HitSelf = function() return C(T.UiQueryFacts.SelfHit) end,
        HitSelfAndChildren = function() return C(T.UiQueryFacts.SelfAndChildrenHit) end,
        HitChildrenOnly = function() return C(T.UiQueryFacts.ChildrenOnlyHit) end,
    })
end

local function lower_pointer_binding(T, binding)
    return U.match(binding, {
        Hover = function(v)
            return T.UiQueryFacts.HoverBinding(v.cursor, v.enter, v.leave)
        end,
        Press = function(v)
            return T.UiQueryFacts.PressBinding(v.button, v.click_count, v.command)
        end,
        Toggle = function(v)
            return T.UiQueryFacts.ToggleBinding(v.value, v.button, v.command)
        end,
        Gesture = function(v)
            return T.UiQueryFacts.GestureBinding(v.gesture, v.command)
        end,
    })
end

local function lower_drag_drop_binding(T, binding)
    return U.match(binding, {
        Draggable = function(v)
            return T.UiQueryFacts.DraggableBinding(v.payload, v.begin, v.finish)
        end,
        DropTarget = function(v)
            return T.UiQueryFacts.DropTargetBinding(v.policy, v.command)
        end,
    })
end

local function lower_accessibility_fact(T, visible, accessibility)
    if not visible then return C(T.UiQueryFacts.NoAccessibility) end
    return U.match(accessibility.accessibility, {
        Hidden = function()
            return C(T.UiQueryFacts.NoAccessibility)
        end,
        Exposed = function(v)
            return T.UiQueryFacts.Exposed(v.role, v.label, v.description, v.sort_priority)
        end,
    })
end

local function lower_query_fact(T, visible, enabled, behavior_facet, accessibility_facet)
    if not visible then
        return T.UiQueryFacts.Fact(
            C(T.UiQueryFacts.NoHit),
            nil,
            Ls(),
            nil,
            Ls(),
            nil,
            Ls(),
            C(T.UiQueryFacts.NoAccessibility)
        )
    end

    local behavior = behavior_facet.behavior
    local focus = U.match(behavior.focus, {
        NotFocusable = function() return nil end,
        Focusable = function(v)
            return enabled and T.UiQueryFacts.Focusable(v.mode, v.order) or nil
        end,
    })

    local pointer = (enabled and #behavior.pointer > 0) and F.range(1, #behavior.pointer):map(function(i)
        return lower_pointer_binding(T, behavior.pointer[i])
    end):totable() or {}

    local keys = (enabled and #behavior.keys > 0) and F.range(1, #behavior.keys):map(function(i)
        local binding = behavior.keys[i]
        return T.UiQueryFacts.Key(binding.chord, binding.when, binding.command, binding.global)
    end):totable() or {}

    local drag_drop = (enabled and #behavior.drag_drop > 0) and F.range(1, #behavior.drag_drop):map(function(i)
        return lower_drag_drop_binding(T, behavior.drag_drop[i])
    end):totable() or {}

    return T.UiQueryFacts.Fact(
        enabled and lower_hit_fact(T, behavior.hit) or C(T.UiQueryFacts.NoHit),
        focus,
        Ls(pointer),
        enabled and behavior.scroll and T.UiQueryFacts.Scroll(behavior.scroll.axis, behavior.scroll.model) or nil,
        Ls(keys),
        enabled and behavior.edit and T.UiQueryFacts.Edit(
            behavior.edit.model,
            behavior.edit.multiline,
            behavior.edit.read_only,
            behavior.edit.changed
        ) or nil,
        Ls(drag_drop),
        lower_accessibility_fact(T, visible, accessibility_facet)
    )
end

local function lower_render_region(T, region)
    local n = #region.headers
    if #region.visibility ~= n or #region.content ~= n or #region.paint ~= n then
        error("UiFlat.Scene:lower_render_facts: flat region facet lengths do not match headers", 3)
    end

    local effective_visible = {}
    local facts = {}

    local i = 1
    while i <= n do
        local header = region.headers[i]
        local parent_visible = true
        if header.parent_index ~= nil then
            parent_visible = effective_visible[header.parent_index + 1]
        end
        local visible = region.visibility[i].visible and parent_visible
        effective_visible[i] = visible
        facts[i] = fact_for_node(T, visible, region.content[i], region.paint[i])
        i = i + 1
    end

    return T.UiRenderFacts.Region(
        region.header,
        region.render_region.z_index,
        Ls(facts)
    )
end

local function lower_query_region(T, region)
    local n = #region.headers
    if #region.visibility ~= n or #region.interactivity ~= n or #region.behavior ~= n or #region.accessibility ~= n then
        error("UiFlat.Scene:lower_query_facts: flat region facet lengths do not match headers", 3)
    end

    local effective_visible = {}
    local effective_enabled = {}
    local facts = {}

    local i = 1
    while i <= n do
        local header = region.headers[i]
        local parent_visible = true
        local parent_enabled = true
        if header.parent_index ~= nil then
            parent_visible = effective_visible[header.parent_index + 1]
            parent_enabled = effective_enabled[header.parent_index + 1]
        end
        local visible = region.visibility[i].visible and parent_visible
        local enabled = region.interactivity[i].enabled and parent_enabled
        effective_visible[i] = visible
        effective_enabled[i] = enabled
        facts[i] = lower_query_fact(T, visible, enabled, region.behavior[i], region.accessibility[i])
        i = i + 1
    end

    return T.UiQueryFacts.Region(
        region.header,
        region.render_region.z_index,
        region.query_region.modal,
        region.query_region.consumes_pointer,
        Ls(facts)
    )
end

local function lower_render_facts(T, scene)
    local regions = F.iter(scene.regions):map(function(region)
        return lower_render_region(T, region)
    end):totable()

    return T.UiRenderFacts.Scene(Ls(regions))
end

local function lower_query_facts(T, scene)
    local regions = F.iter(scene.regions):map(function(region)
        return lower_query_region(T, region)
    end):totable()

    return T.UiQueryFacts.Scene(Ls(regions))
end

local function lower_geometry(T, scene, assets)
    local caches = {
        font_paths = {},
        text_intrinsics = {},
        image_intrinsics = {},
    }

    return T.UiGeometryInput.Scene(
        scene.viewport,
        Ls(F.iter(scene.regions):map(function(region)
            return lower_geometry_region(T, region, assets, caches)
        end):totable())
    )
end

return function(T)
    T.UiFlat.Scene.lower_render_facts = U.transition(function(scene)
        return lower_render_facts(T, scene)
    end)

    T.UiFlat.Scene.lower_query_facts = U.transition(function(scene)
        return lower_query_facts(T, scene)
    end)

    T.UiFlat.Scene.lower_geometry = U.transition(function(scene, assets)
        return lower_geometry(T, scene, assets)
    end)
end
