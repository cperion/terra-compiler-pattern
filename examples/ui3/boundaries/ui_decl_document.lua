local U = require("unit")

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
end

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local unpack_fn = table.unpack or unpack
local BIND_DIAG_ENABLED = os.getenv("UI3_BIND_DIAG") == "1"

local DEFAULT_TEXT_SIZE_PX = 16
local DEFAULT_TEXT_LETTER_SPACING_PX = 0
local DEFAULT_TEXT_COLOR = { r = 1, g = 1, b = 1, a = 1 }

local function now_ms()
    return os.clock() * 1000.0
end

local function new_diag()
    if not BIND_DIAG_ENABLED then return nil end
    return {
        node_count = 0,
        text_count = 0,
        image_count = 0,
        inline_custom_count = 0,
        resource_custom_count = 0,
        anchored_count = 0,
        pointer_rule_count = 0,
        key_rule_count = 0,
        drag_drop_rule_count = 0,
        paint_op_count = 0,
        hidden_accessibility_count = 0,
        exposed_accessibility_count = 0,
        ids_collected = 0,
        entry_count = 0,
    }
end

local function record_ms(diag, key, dt)
    if not diag then return end
    diag[key] = (diag[key] or 0) + dt
end

local function record_count(diag, key, n)
    if not diag then return end
    diag[key] = (diag[key] or 0) + (n or 1)
end

local function timed(diag, key, fn)
    if not diag then return fn() end
    local t0 = now_ms()
    local results = { fn() }
    record_ms(diag, key, now_ms() - t0)
    return unpack_fn(results)
end

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

local function collect_entry_node_ids(element, local_ids, global_ids, entry_where, diag)
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
    record_count(diag, "ids_collected")

    for _, child in ipairs(element.children) do
        collect_entry_node_ids(child, local_ids, global_ids, entry_where, diag)
    end
end

local function bind_position(T, position, entry_node_ids, where, diag)
    return timed(diag, "bind_position_ms", function()
        return U.match(position, {
            InFlow = function()
                return C(T.UiBound.InFlow)
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

                record_count(diag, "anchored_count")
                return T.UiBound.AnchoredTo(
                    v.target,
                    v.self_x,
                    v.self_y,
                    v.target_x,
                    v.target_y,
                    v.dx,
                    v.dy
                )
            end,
        })
    end)
end

local function bind_layout(T, layout, entry_node_ids, where, diag)
    return timed(diag, "bind_layout_ms", function()
        return T.UiBound.Layout(
            layout,
            bind_position(T, layout.position, entry_node_ids, where, diag)
        )
    end)
end

local function bind_paint(paint, diag)
    return timed(diag, "bind_paint_ms", function()
        record_count(diag, "paint_op_count", #paint.ops)
        return paint
    end)
end

local function bind_text_content(T, assets, fonts, v, where, diag)
    return timed(diag, "bind_text_content_ms", function()
        record_count(diag, "text_count")
        local font = ensure_known_font(assets, fonts, v.style.font, where)
        local size_px = clamp_at_least(v.style.size_px or DEFAULT_TEXT_SIZE_PX, 1)

        return T.UiBound.BoundText(
            v.value,
            T.UiBound.BoundTextStyle(
                font,
                size_px,
                v.style.weight or C(T.UiCore.Weight400),
                v.style.slant or C(T.UiCore.Roman),
                v.style.letter_spacing_px or DEFAULT_TEXT_LETTER_SPACING_PX,
                clamp_at_least(v.style.line_height_px or default_line_height(size_px), 1),
                v.style.color or default_color(T)
            ),
            T.UiCore.TextLayout(
                v.layout.wrap,
                v.layout.overflow,
                v.layout.align,
                clamp_at_least(v.layout.line_limit, 1)
            )
        )
    end)
end

local function bind_content(T, assets, fonts, images, content, where, diag)
    return timed(diag, "bind_content_ms", function()
        return U.match(content, {
            NoContent = function()
                return C(T.UiBound.NoContent)
            end,
            Text = function(v)
                return T.UiBound.Text(bind_text_content(T, assets, fonts, v, where, diag))
            end,
            Image = function(v)
                record_count(diag, "image_count")
                return T.UiBound.Image(
                    ensure_known_image(images, v.image, where),
                    v.style
                )
            end,
            InlineCustomContent = function(v)
                record_count(diag, "inline_custom_count")
                return T.UiBound.InlineCustomContent(v.family, v.payload)
            end,
            ResourceCustomContent = function(v)
                record_count(diag, "resource_custom_count")
                return T.UiBound.ResourceCustomContent(v.family, v.resource_payload, v.instance_payload)
            end,
        })
    end)
end

local function bind_behavior(behavior, diag)
    return timed(diag, "bind_behavior_ms", function()
        record_count(diag, "pointer_rule_count", #behavior.pointer)
        record_count(diag, "key_rule_count", #behavior.keys)
        record_count(diag, "drag_drop_rule_count", #behavior.drag_drop)
        return behavior
    end)
end

local function bind_accessibility(T, accessibility, diag)
    return timed(diag, "bind_accessibility_ms", function()
        if accessibility.hidden then
            record_count(diag, "hidden_accessibility_count")
            return C(T.UiBound.Hidden)
        end

        record_count(diag, "exposed_accessibility_count")
        return T.UiBound.Exposed(
            accessibility.role,
            accessibility.label,
            accessibility.description,
            accessibility.sort_priority
        )
    end)
end

local function bind_node(T, assets, fonts, images, entry_node_ids, element, diag)
    return timed(diag, "bind_node_ms", function()
        record_count(diag, "node_count")
        local where = "UiDecl.Document:bind: " .. describe_element(element)
        local children = {}

        for _, child in ipairs(element.children) do
            children[#children + 1] = bind_node(T, assets, fonts, images, entry_node_ids, child, diag)
        end

        return T.UiBound.Node(
            element.id,
            element.semantic_ref,
            element.debug_name,
            element.role,
            element.flags,
            bind_layout(T, element.layout, entry_node_ids, where, diag),
            bind_paint(element.paint, diag),
            bind_content(T, assets, fonts, images, element.content, where, diag),
            bind_behavior(element.behavior, diag),
            bind_accessibility(T, element.accessibility, diag),
            L(children)
        )
    end)
end

local function bind_root_entry(T, assets, fonts, images, root, global_node_ids, diag)
    local entry_where = describe_entry("root", root)
    local entry_node_ids = {}
    timed(diag, "collect_ids_ms", function()
        collect_entry_node_ids(root.root, entry_node_ids, global_node_ids, entry_where, diag)
    end)
    record_count(diag, "entry_count")

    return T.UiBound.Entry(
        root.id,
        root.debug_name,
        bind_node(T, assets, fonts, images, entry_node_ids, root.root, diag),
        0,
        false,
        false
    )
end

local function bind_overlay_entry(T, assets, fonts, images, overlay, global_node_ids, diag)
    local entry_where = describe_entry("overlay", overlay)
    local entry_node_ids = {}
    timed(diag, "collect_ids_ms", function()
        collect_entry_node_ids(overlay.root, entry_node_ids, global_node_ids, entry_where, diag)
    end)
    record_count(diag, "entry_count")

    return T.UiBound.Entry(
        overlay.id,
        overlay.debug_name,
        bind_node(T, assets, fonts, images, entry_node_ids, overlay.root, diag),
        overlay.z_index,
        overlay.modal,
        overlay.consumes_pointer
    )
end

return function(T)
    T.UiDecl.Document.bind = U.transition(function(document, assets)
        require_catalog(assets, "UiDecl.Document:bind")

        local diag = new_diag()
        local fonts = timed(diag, "index_assets_ms", function()
            return index_font_assets(assets)
        end)
        local images = timed(diag, "index_assets_ms", function()
            return index_image_assets(assets)
        end)
        local global_node_ids = {}
        local entries = timed(diag, "bind_entries_ms", function()
            local out = {}

            for _, root in ipairs(document.roots) do
                out[#out + 1] = bind_root_entry(T, assets, fonts, images, root, global_node_ids, diag)
            end

            for _, overlay in ipairs(document.overlays) do
                out[#out + 1] = bind_overlay_entry(T, assets, fonts, images, overlay, global_node_ids, diag)
            end

            return out
        end)

        T.UiDecl.__last_bind_diag = diag
        return T.UiBound.Document(L(entries))
    end)
end
