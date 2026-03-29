local U = require("unit")

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
end

-- ============================================================================
-- UiDecl.Document -> bind -> UiBound.Document
-- ----------------------------------------------------------------------------
-- This file implements the first real ui2 compiler boundary.
--
-- Boundary meaning:
--   source/authored tree -> bound/validated tree
--
-- What bind consumes:
--   - root/overlay split into one canonical Entry list
--   - optional authored text style fields into concrete bound text fields
--   - accessibility hidden flag into an explicit sum type
--   - anchor target references into validated AnchorTarget records
--   - asset-backed refs that can be checked locally (fonts/images)
--
-- What bind intentionally does NOT do:
--   - no flattening
--   - no topology indices
--   - no layout solving
--   - no text measurement / shaping
--   - no draw atoms
--   - no route tables
--   - no backend/runtime state
--
-- Design notes:
--   - bind requires an explicit UiAsset.Catalog argument
--   - bind validates anchors against the current entry subtree only
--   - bind validates font/image refs against the explicit asset catalog
--   - bind preserves authored tree shape exactly
--   - bind keeps most authored numeric layout/paint values unchanged
--
-- This keeps the phase honest: UiBound is still semantic tree data, but with
-- the easy local irregularities already consumed.
-- ============================================================================

local DEFAULT_TEXT_SIZE_PX = 16
local DEFAULT_TEXT_LETTER_SPACING_PX = 0
local DEFAULT_TEXT_COLOR = { r = 1, g = 1, b = 1, a = 1 }

local function require_catalog(assets, where)
    if assets then return assets end
    error((where or "UiDecl.Document:bind") .. ": UiAsset.Catalog is required", 3)
end

local function id_value(id)
    return id and id.value or nil
end

local function default_color(T)
    return T.UiCore.Color(
        DEFAULT_TEXT_COLOR.r,
        DEFAULT_TEXT_COLOR.g,
        DEFAULT_TEXT_COLOR.b,
        DEFAULT_TEXT_COLOR.a
    )
end

local function default_line_height(size_px)
    -- Deliberately semantic and simple.
    --
    -- We do NOT inspect backend font metrics during bind. That would leak
    -- measurement/runtime concerns into the wrong phase. Later shaping/solve
    -- work can still use the bound line height consistently.
    return size_px
end

local function clamp_at_least(v, lo)
    if v < lo then return lo end
    return v
end

local function describe_entry(kind, entry)
    local name = entry and entry.debug_name and (" '" .. entry.debug_name .. "'") or ""
    return kind .. name .. " (ElementId(" .. tostring(id_value(entry and entry.id)) .. "))"
end

local function describe_element(element)
    local name = element and element.debug_name and (" '" .. element.debug_name .. "'") or ""
    return "element" .. name .. " (ElementId(" .. tostring(id_value(element and element.id)) .. "))"
end

local function index_font_assets(assets)
    local catalog = require_catalog(assets, "UiDecl.Document:bind")
    local fonts = {}

    for _, asset in ipairs(catalog.fonts) do
        fonts[id_value(asset.ref)] = true
    end

    if not fonts[id_value(catalog.default_font)] then
        error(
            "UiDecl.Document:bind: catalog.default_font has no matching FontAsset: FontRef("
            .. tostring(id_value(catalog.default_font)) .. ")",
            3
        )
    end

    return fonts
end

local function index_image_assets(assets)
    local catalog = require_catalog(assets, "UiDecl.Document:bind")
    local images = {}

    for _, asset in ipairs(catalog.images) do
        images[id_value(asset.ref)] = true
    end

    return images
end

local function ensure_known_font(assets, fonts, font_ref, where)
    local catalog = require_catalog(assets, where)
    local resolved = font_ref or catalog.default_font
    if not fonts[id_value(resolved)] then
        error(
            (where or "UiDecl.Document:bind")
            .. ": no FontAsset for FontRef(" .. tostring(id_value(resolved)) .. ")",
            3
        )
    end
    return resolved
end

local function ensure_known_image(images, image_ref, where)
    if not images[id_value(image_ref)] then
        error(
            (where or "UiDecl.Document:bind")
            .. ": no ImageAsset for ImageRef(" .. tostring(id_value(image_ref)) .. ")",
            3
        )
    end
    return image_ref
end

local function collect_entry_node_ids(element, local_ids, global_ids, entry_where)
    local key = id_value(element.id)
    local existing = global_ids[key]

    if local_ids[key] then
        error(
            "UiDecl.Document:bind: duplicate element id within "
            .. entry_where
            .. ": ElementId(" .. tostring(key) .. ")",
            3
        )
    end

    if existing then
        error(
            "UiDecl.Document:bind: duplicate element id across document: ElementId("
            .. tostring(key)
            .. ") appears in both "
            .. existing
            .. " and "
            .. entry_where,
            3
        )
    end

    local_ids[key] = true
    global_ids[key] = entry_where

    for _, child in ipairs(element.children) do
        collect_entry_node_ids(child, local_ids, global_ids, entry_where)
    end
end

local function bind_position(T, position, entry_node_ids, where)
    return U.match(position, {
        InFlow = function()
            return T.UiBound.InFlow()
        end,
        Absolute = function(v)
            return T.UiBound.Absolute(v.left, v.top, v.right, v.bottom)
        end,
        Anchored = function(v)
            local target_id = id_value(v.target)
            if not entry_node_ids[target_id] then
                error(
                    (where or "UiDecl.Document:bind")
                    .. ": anchored position target must be inside the same entry subtree: ElementId("
                    .. tostring(target_id)
                    .. ")",
                    3
                )
            end

            return T.UiBound.Anchored(
                T.UiBound.AnchorTarget(v.target),
                v.self_x,
                v.self_y,
                v.target_x,
                v.target_y,
                v.dx,
                v.dy
            )
        end,
    })
end

local function bind_layout(T, layout, entry_node_ids, where)
    return T.UiBound.Layout(
        layout.width,
        layout.height,
        bind_position(T, layout.position, entry_node_ids, where),
        layout.flow,
        layout.grid,
        layout.cell,
        layout.main_align,
        layout.cross_align,
        layout.padding,
        layout.margin,
        layout.gap,
        layout.overflow_x,
        layout.overflow_y,
        layout.aspect
    )
end

local function bind_paint_op(T, op)
    return U.match(op, {
        Box = function(v)
            return T.UiBound.Box(
                v.fill,
                v.stroke,
                v.stroke_width,
                v.align,
                v.corners
            )
        end,
        Shadow = function(v)
            return T.UiBound.Shadow(
                v.brush,
                v.blur,
                v.spread,
                v.dx,
                v.dy,
                v.shadow_kind,
                v.corners
            )
        end,
        Clip = function(v)
            return T.UiBound.Clip(v.corners)
        end,
        Opacity = function(v)
            return T.UiBound.Opacity(v.value)
        end,
        Transform = function(v)
            return T.UiBound.Transform(v.xform)
        end,
        Blend = function(v)
            return T.UiBound.Blend(v.mode)
        end,
        CustomPaint = function(v)
            return T.UiBound.CustomPaint(v.family, v.payload)
        end,
    })
end

local function bind_paint(T, paint)
    local ops = {}
    for _, op in ipairs(paint.ops) do
        ops[#ops + 1] = bind_paint_op(T, op)
    end
    return T.UiBound.Paint(L(ops))
end

local function bind_text_content(T, assets, fonts, v, where)
    local font = ensure_known_font(assets, fonts, v.style.font, where)
    local size_px = clamp_at_least(v.style.size_px or DEFAULT_TEXT_SIZE_PX, 1)

    return T.UiBound.BoundText(
        v.value,
        font,
        size_px,
        v.style.weight or T.UiCore.Weight400(),
        v.style.slant or T.UiCore.Roman(),
        v.style.letter_spacing_px or DEFAULT_TEXT_LETTER_SPACING_PX,
        clamp_at_least(v.style.line_height_px or default_line_height(size_px), 1),
        v.style.color or default_color(T),
        v.layout.wrap,
        v.layout.overflow,
        v.layout.align,
        clamp_at_least(v.layout.line_limit, 1)
    )
end

local function bind_image_content(T, images, v, where)
    return T.UiBound.BoundImage(
        ensure_known_image(images, v.image, where),
        v.style
    )
end

local function bind_content(T, assets, fonts, images, content, where)
    return U.match(content, {
        NoContent = function()
            return T.UiBound.NoContent()
        end,
        Text = function(v)
            return T.UiBound.Text(bind_text_content(T, assets, fonts, v, where))
        end,
        Image = function(v)
            return T.UiBound.Image(bind_image_content(T, images, v, where))
        end,
        CustomContent = function(v)
            return T.UiBound.CustomContent(v.family, v.payload)
        end,
    })
end

local function bind_pointer_rule(T, rule)
    return U.match(rule, {
        Hover = function(v)
            return T.UiBound.Hover(v.cursor, v.enter, v.leave)
        end,
        Press = function(v)
            return T.UiBound.Press(v.button, v.click_count, v.command)
        end,
        Toggle = function(v)
            return T.UiBound.Toggle(v.value, v.button, v.command)
        end,
        Gesture = function(v)
            return T.UiBound.Gesture(v.gesture, v.command)
        end,
    })
end

local function bind_focus_policy(T, focus)
    return U.match(focus, {
        NotFocusable = function()
            return T.UiBound.NotFocusable()
        end,
        Focusable = function(v)
            return T.UiBound.Focusable(v.mode, v.order)
        end,
    })
end

local function bind_hit_policy(T, hit)
    return U.match(hit, {
        HitNone = function() return T.UiBound.HitNone() end,
        HitSelf = function() return T.UiBound.HitSelf() end,
        HitSelfAndChildren = function() return T.UiBound.HitSelfAndChildren() end,
        HitChildrenOnly = function() return T.UiBound.HitChildrenOnly() end,
    })
end

local function bind_drag_drop_rule(T, rule)
    return U.match(rule, {
        Draggable = function(v)
            return T.UiBound.Draggable(v.payload, v.begin, v.finish)
        end,
        DropTarget = function(v)
            return T.UiBound.DropTarget(v.policy, v.command)
        end,
    })
end

local function bind_behavior(T, behavior)
    local pointer = {}
    for _, rule in ipairs(behavior.pointer) do
        pointer[#pointer + 1] = bind_pointer_rule(T, rule)
    end

    local keys = {}
    for _, rule in ipairs(behavior.keys) do
        keys[#keys + 1] = T.UiBound.KeyRule(
            rule.chord,
            rule.when,
            rule.command,
            rule.global
        )
    end

    local drag_drop = {}
    for _, rule in ipairs(behavior.drag_drop) do
        drag_drop[#drag_drop + 1] = bind_drag_drop_rule(T, rule)
    end

    return T.UiBound.Behavior(
        bind_hit_policy(T, behavior.hit),
        bind_focus_policy(T, behavior.focus),
        L(pointer),
        behavior.scroll and T.UiBound.ScrollRule(behavior.scroll.axis, behavior.scroll.model) or nil,
        L(keys),
        behavior.edit and T.UiBound.EditRule(
            behavior.edit.model,
            behavior.edit.multiline,
            behavior.edit.read_only,
            behavior.edit.changed
        ) or nil,
        L(drag_drop)
    )
end

local function bind_accessibility(T, accessibility)
    if accessibility.hidden then
        return T.UiBound.Hidden()
    end

    return T.UiBound.Exposed(
        accessibility.role,
        accessibility.label,
        accessibility.description,
        accessibility.sort_priority
    )
end

local function bind_flags(T, flags)
    return T.UiBound.Flags(flags.visible, flags.enabled)
end

local function bind_node(T, assets, fonts, images, entry_node_ids, element)
    local where = "UiDecl.Document:bind: " .. describe_element(element)
    local children = {}

    for _, child in ipairs(element.children) do
        children[#children + 1] = bind_node(T, assets, fonts, images, entry_node_ids, child)
    end

    return T.UiBound.Node(
        element.id,
        element.semantic_ref,
        element.debug_name,
        element.role,
        bind_flags(T, element.flags),
        bind_layout(T, element.layout, entry_node_ids, where),
        bind_paint(T, element.paint),
        bind_content(T, assets, fonts, images, element.content, where),
        bind_behavior(T, element.behavior),
        bind_accessibility(T, element.accessibility),
        L(children)
    )
end

local function bind_root_entry(T, assets, fonts, images, root, global_node_ids)
    local entry_where = describe_entry("root", root)
    local entry_node_ids = {}
    collect_entry_node_ids(root.root, entry_node_ids, global_node_ids, entry_where)

    return T.UiBound.Entry(
        root.id,
        root.debug_name,
        bind_node(T, assets, fonts, images, entry_node_ids, root.root),
        0,
        false,
        false
    )
end

local function bind_overlay_entry(T, assets, fonts, images, overlay, global_node_ids)
    local entry_where = describe_entry("overlay", overlay)
    local entry_node_ids = {}
    collect_entry_node_ids(overlay.root, entry_node_ids, global_node_ids, entry_where)

    return T.UiBound.Entry(
        overlay.id,
        overlay.debug_name,
        bind_node(T, assets, fonts, images, entry_node_ids, overlay.root),
        overlay.z_index,
        overlay.modal,
        overlay.consumes_pointer
    )
end

return function(T)
    -- ---------------------------------------------------------------------
    -- Public boundary: UiDecl.Document:bind(assets) -> UiBound.Document
    -- ---------------------------------------------------------------------
    -- Required side input:
    --   assets : UiAsset.Catalog
    --
    -- The side-input policy is explicit on purpose. Font/image validation and
    -- default font selection depend on compiler-side resource data, so bind
    -- takes that catalog as a normal argument instead of consulting hidden
    -- globals.
    T.UiDecl.Document.bind = U.transition(function(document, assets)
        require_catalog(assets, "UiDecl.Document:bind")

        local fonts = index_font_assets(assets)
        local images = index_image_assets(assets)
        local global_node_ids = {}
        local entries = {}

        -- Canonical entry order:
        --   roots first, overlays second, preserving authored order within each
        --   source list. This keeps top-level authored structure stable while
        --   consuming the source distinction into one UiBound.Entry list.
        for _, root in ipairs(document.roots) do
            entries[#entries + 1] = bind_root_entry(T, assets, fonts, images, root, global_node_ids)
        end

        for _, overlay in ipairs(document.overlays) do
            entries[#entries + 1] = bind_overlay_entry(T, assets, fonts, images, overlay, global_node_ids)
        end

        return T.UiBound.Document(L(entries))
    end)
end
