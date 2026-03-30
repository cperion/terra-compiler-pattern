local asdl = require("asdl")
local L = asdl.List
local Backend = require("examples.ui.backends.terra_sdl_gl")
local Schema = require("unit").load_inspect_spec("examples/ui3")

local T = Schema.ctx

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function getenv_number(name, default)
    local raw = os.getenv(name)
    if not raw or raw == "" then return default end
    local n = tonumber(raw)
    if not n then return default end
    return n
end

local function getenv_string(name, default)
    local raw = os.getenv(name)
    if not raw or raw == "" then return default end
    return raw
end

local function now_ns()
    return tonumber(Backend.FFI.SDL_GetTicksNS())
end

local function ms_between(t0, t1)
    return (t1 - t0) / 1000000.0
end

local function bench_avg_ms(iters, fn)
    local t0 = now_ns()
    for _ = 1, iters do fn() end
    local t1 = now_ns()
    return ms_between(t0, t1) / iters
end

local function auto_size()
    return T.UiCore.SizeSpec(C(T.UiCore.Auto), C(T.UiCore.Auto), C(T.UiCore.Auto))
end

local function base_layout(flow, position)
    return T.UiDecl.Layout(
        auto_size(),
        auto_size(),
        position or C(T.UiCore.InFlow),
        flow or C(T.UiCore.Column),
        nil,
        nil,
        C(T.UiCore.Start),
        C(T.UiCore.CrossStart),
        T.UiCore.Insets(0, 0, 0, 0),
        T.UiCore.Insets(0, 0, 0, 0),
        0,
        C(T.UiCore.Visible),
        C(T.UiCore.Visible),
        nil
    )
end

local function empty_paint()
    return T.UiDecl.Paint(L {})
end

local function box_paint(corners)
    return T.UiDecl.Paint(L {
        T.UiDecl.Box(
            T.UiCore.Solid(T.UiCore.Color(0.2, 0.4, 0.8, 1.0)),
            nil,
            0,
            C(T.UiCore.Inside),
            corners or T.UiCore.Corners(0, 0, 0, 0)
        )
    })
end

local function mixed_paint(i)
    return T.UiDecl.Paint(L {
        T.UiDecl.Clip(T.UiCore.Corners(i % 4, i % 5, i % 6, i % 7)),
        T.UiDecl.Opacity(1 - ((i % 5) * 0.1)),
        T.UiDecl.Blend((i % 2 == 0) and C(T.UiCore.BlendNormal) or C(T.UiCore.BlendAdd))
    })
end

local function no_behavior()
    return T.UiDecl.Behavior(
        C(T.UiDecl.HitNone),
        C(T.UiDecl.NotFocusable),
        L {},
        nil,
        L {},
        nil,
        L {}
    )
end

local function interactive_behavior(i)
    return T.UiDecl.Behavior(
        (i % 3 == 0) and C(T.UiDecl.HitSelfAndChildren) or C(T.UiDecl.HitSelf),
        (i % 2 == 0) and T.UiDecl.Focusable(C(T.UiCore.ClickFocus), i) or C(T.UiDecl.NotFocusable),
        (i % 4 == 0) and L {
            T.UiDecl.Hover(nil, T.UiCore.CommandRef(1000 + i), T.UiCore.CommandRef(2000 + i))
        } or L {
            T.UiDecl.Press(C(T.UiCore.Primary), 1, T.UiCore.CommandRef(3000 + i))
        },
        (i % 5 == 0) and T.UiDecl.ScrollRule(C(T.UiCore.Vertical), T.UiCore.ScrollRef(4000 + i)) or nil,
        (i % 6 == 0) and L {
            T.UiDecl.KeyRule(T.UiCore.KeyChord(false, false, false, false, 13), C(T.UiCore.KeyDown), T.UiCore.CommandRef(5000 + i), true)
        } or L {},
        (i % 7 == 0) and T.UiDecl.EditRule(T.UiCore.TextModelRef(6000 + i), false, false, T.UiCore.CommandRef(7000 + i)) or nil,
        L {}
    )
end

local function hidden_accessibility()
    return T.UiDecl.Accessibility(C(T.UiCore.AccNone), nil, nil, true, 0)
end

local function exposed_accessibility(i)
    return T.UiDecl.Accessibility(C(T.UiCore.AccButton), "item", nil, false, i)
end

local function text_style()
    return T.UiCore.TextStyle(
        T.UiCore.FontRef(1),
        14,
        C(T.UiCore.Weight400),
        C(T.UiCore.Roman),
        0,
        16,
        T.UiCore.Color(1, 1, 1, 1)
    )
end

local function text_style_defaults()
    return T.UiCore.TextStyle(nil, nil, nil, nil, nil, nil, nil)
end

local function text_layout()
    return T.UiCore.TextLayout(C(T.UiCore.NoWrap), C(T.UiCore.ClipText), C(T.UiCore.TextStart), 1)
end

local function text_content(i)
    return T.UiDecl.Text(T.UiCore.TextValue("node " .. tostring(i)), text_style(), text_layout())
end

local function text_default_content(i)
    return T.UiDecl.Text(T.UiCore.TextValue("node " .. tostring(i)), text_style_defaults(), text_layout())
end

local function image_content()
    return T.UiDecl.Image(
        T.UiCore.ImageRef(2),
        T.UiCore.ImageStyle(C(T.UiCore.Contain), C(T.UiCore.Linear), 1, T.UiCore.Corners(0, 0, 0, 0))
    )
end

local function custom_content(i)
    if i % 2 == 0 then
        return T.UiDecl.InlineCustomContent(900 + (i % 3), i)
    end
    return T.UiDecl.ResourceCustomContent(900 + (i % 3), 10000 + i, 20000 + i)
end

local function element(base, id, debug_name, role, flags, layout, paint, content, behavior, accessibility, children)
    return T.UiDecl.Element(
        T.UiCore.ElementId(base + id),
        T.UiCore.SemanticRef(77, base + id),
        debug_name,
        role,
        flags,
        layout,
        paint,
        content,
        behavior,
        accessibility,
        children or L {}
    )
end

local function bare_leaf(base, i)
    return element(base, i, "bare-" .. tostring(i), C(T.UiCore.View), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), C(T.UiDecl.NoContent), no_behavior(), hidden_accessibility(), L {})
end

local function box_leaf(base, i)
    return element(base, i, "box-" .. tostring(i), C(T.UiCore.View), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), box_paint(T.UiCore.Corners(0, 0, 0, 0)), C(T.UiDecl.NoContent), no_behavior(), hidden_accessibility(), L {})
end

local function behavior_leaf(base, i)
    return element(base, i, "behavior-" .. tostring(i), C(T.UiCore.View), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), C(T.UiDecl.NoContent), interactive_behavior(i), hidden_accessibility(), L {})
end

local function text_leaf(base, i)
    return element(base, i, "text-" .. tostring(i), C(T.UiCore.TextRole), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), text_content(i), no_behavior(), hidden_accessibility(), L {})
end

local function text_default_leaf(base, i)
    return element(base, i, "text-default-" .. tostring(i), C(T.UiCore.TextRole), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), text_default_content(i), no_behavior(), hidden_accessibility(), L {})
end

local function image_leaf(base, i)
    return element(base, i, "image-" .. tostring(i), C(T.UiCore.ImageRole), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), image_content(), no_behavior(), hidden_accessibility(), L {})
end

local function custom_leaf(base, i)
    return element(base, i, "custom-" .. tostring(i), C(T.UiCore.View), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), custom_content(i), no_behavior(), hidden_accessibility(), L {})
end

local function root_with_children(base, node_count, child_builder, root_paint, root_behavior)
    local children = {}
    local i = 1
    while i <= node_count do
        children[#children + 1] = child_builder(base, i)
        i = i + 1
    end
    return element(
        base,
        0,
        "root",
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        root_paint or empty_paint(),
        C(T.UiDecl.NoContent),
        root_behavior or no_behavior(),
        hidden_accessibility(),
        L(children)
    )
end

local function mixed_leaf(base, i)
    local role = (i % 4 == 0) and C(T.UiCore.ImageRole)
        or (i % 4 == 1) and C(T.UiCore.TextRole)
        or C(T.UiCore.View)
    local content = (i % 4 == 0) and image_content()
        or (i % 4 == 1) and text_content(i)
        or (i % 4 == 2) and custom_content(i)
        or C(T.UiDecl.NoContent)
    return element(
        base,
        i,
        "mixed-" .. tostring(i),
        role,
        T.UiDecl.Flags(i % 9 ~= 0, i % 11 ~= 0),
        base_layout(C(T.UiCore.Column)),
        mixed_paint(i),
        content,
        interactive_behavior(i),
        (i % 3 == 0) and exposed_accessibility(i) or hidden_accessibility(),
        L {}
    )
end

local function mixed_root(base, node_count)
    return root_with_children(base, node_count, mixed_leaf, mixed_paint(0), interactive_behavior(0))
end

local function nested_root(base, node_count)
    local current = element(
        base,
        node_count,
        "nested-" .. tostring(node_count),
        (node_count % 2 == 0) and C(T.UiCore.TextRole) or C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        mixed_paint(node_count),
        (node_count % 2 == 0) and text_content(node_count) or C(T.UiDecl.NoContent),
        interactive_behavior(node_count),
        hidden_accessibility(),
        L {}
    )

    local i = node_count - 1
    while i >= 1 do
        current = element(
            base,
            i,
            "nested-" .. tostring(i),
            C(T.UiCore.View),
            T.UiDecl.Flags(true, true),
            base_layout(C(T.UiCore.Column)),
            mixed_paint(i),
            C(T.UiDecl.NoContent),
            interactive_behavior(i),
            hidden_accessibility(),
            L { current }
        )
        i = i - 1
    end

    return element(base, 0, "root", C(T.UiCore.View), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), C(T.UiDecl.NoContent), no_behavior(), hidden_accessibility(), L { current })
end

local function nested_bare_root(base, node_count)
    local current = bare_leaf(base, node_count)
    local i = node_count - 1
    while i >= 1 do
        current = element(base, i, "nested-bare-" .. tostring(i), C(T.UiCore.View), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), C(T.UiDecl.NoContent), no_behavior(), hidden_accessibility(), L { current })
        i = i - 1
    end
    return element(base, 0, "root", C(T.UiCore.View), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), C(T.UiDecl.NoContent), no_behavior(), hidden_accessibility(), L { current })
end

local function anchored_bare_root(base, node_count)
    local root_id = T.UiCore.ElementId(base)
    local children = {}
    local i = 1
    while i <= node_count do
        children[#children + 1] = element(
            base,
            i,
            "anchored-bare-" .. tostring(i),
            C(T.UiCore.View),
            T.UiDecl.Flags(true, true),
            base_layout(
                C(T.UiCore.Column),
                T.UiCore.Anchored(root_id, C(T.UiCore.Left), C(T.UiCore.Top), C(T.UiCore.Right), C(T.UiCore.Bottom), 4, 6)
            ),
            empty_paint(),
            C(T.UiDecl.NoContent),
            no_behavior(),
            hidden_accessibility(),
            L {}
        )
        i = i + 1
    end
    return element(base, 0, "root", C(T.UiCore.View), T.UiDecl.Flags(true, true), base_layout(C(T.UiCore.Column)), empty_paint(), C(T.UiDecl.NoContent), no_behavior(), hidden_accessibility(), L(children))
end

local function build_document(node_count, scenario, seed)
    local base = 1000000 + (seed * 10000)
    local root_element = (scenario == "bare") and root_with_children(base, node_count, bare_leaf)
        or (scenario == "boxes") and root_with_children(base, node_count, box_leaf)
        or (scenario == "behavior") and root_with_children(base, node_count, behavior_leaf)
        or (scenario == "text") and root_with_children(base, node_count, text_leaf)
        or (scenario == "text_defaults") and root_with_children(base, node_count, text_default_leaf)
        or (scenario == "image") and root_with_children(base, node_count, image_leaf)
        or (scenario == "custom") and root_with_children(base, node_count, custom_leaf)
        or (scenario == "mixed") and mixed_root(base, node_count)
        or (scenario == "nested") and nested_root(base, node_count)
        or (scenario == "nested_bare") and nested_bare_root(base, node_count)
        or (scenario == "anchored_bare") and anchored_bare_root(base, node_count)
        or root_with_children(base, node_count, box_leaf)

    return T.UiDecl.Document(
        1,
        L { T.UiDecl.Root(T.UiCore.ElementId(base - 1), scenario .. "-root", root_element) },
        L {}
    )
end

local function build_assets()
    return T.UiAsset.Catalog(
        T.UiCore.FontRef(1),
        L {
            T.UiAsset.FontAsset(T.UiCore.FontRef(1), "/tmp/ui3-bind-bench-font.ttf")
        },
        L {
            T.UiAsset.ImageAsset(T.UiCore.ImageRef(2), "/tmp/ui3-bind-bench-image.png")
        }
    )
end

local warmup = math.max(0, math.floor(getenv_number("UI3_BIND_WARMUP", 3)))
local iters = math.max(1, math.floor(getenv_number("UI3_BIND_ITERS", 50)))
local node_count = math.max(1, math.floor(getenv_number("UI3_BIND_NODES", 1000)))
local scenario = getenv_string("UI3_BIND_SCENARIO", "boxes")
local assets = build_assets()
local diag_enabled = os.getenv("UI3_BIND_DIAG") == "1"

local document = build_document(node_count, scenario, 1)
local bind_ms = bench_avg_ms(1, function()
    document:bind(assets)
end)

for _ = 1, warmup do
    document:bind(assets)
end

local bind_existing_doc_avg_ms = bench_avg_ms(iters, function()
    document:bind(assets)
end)

local build_seed = 500
local build_document_avg_ms = bench_avg_ms(iters, function()
    build_seed = build_seed + 1
    build_document(node_count, scenario, build_seed)
end)

local seed = 1000
local build_plus_bind_avg_ms = bench_avg_ms(iters, function()
    seed = seed + 1
    local fresh = build_document(node_count, scenario, seed)
    fresh:bind(assets)
end)

local sample_seed = diag_enabled and 999999 or 1
local sample = build_document(node_count, scenario, sample_seed):bind(assets)
print(string.format(
    "ui3 bind bench warmup=%d iters=%d nodes=%d scenario=%s",
    warmup,
    iters,
    node_count,
    scenario
))
print(string.format("  bind_ms: %.6f", bind_ms))
print(string.format("  bind_existing_doc_avg_ms: %.6f", bind_existing_doc_avg_ms))
print(string.format("  build_document_avg_ms: %.6f", build_document_avg_ms))
print(string.format("  build_plus_bind_avg_ms: %.6f", build_plus_bind_avg_ms))
print(string.format("  fresh_bind_suffix_avg_ms: %.6f", build_plus_bind_avg_ms - build_document_avg_ms))
print(string.format("  entries: %d", #sample.entries))
print(string.format("  bound_root_children: %d", #sample.entries[1].root.children))

if diag_enabled and T.UiDecl.__last_bind_diag then
    local d = T.UiDecl.__last_bind_diag
    print(string.format("  diag.index_assets_ms: %.3f", d.index_assets_ms or 0))
    print(string.format("  diag.collect_ids_ms: %.3f", d.collect_ids_ms or 0))
    print(string.format("  diag.bind_entries_ms: %.3f", d.bind_entries_ms or 0))
    print(string.format("  diag.bind_node_ms: %.3f", d.bind_node_ms or 0))
    print(string.format("  diag.bind_layout_ms: %.3f", d.bind_layout_ms or 0))
    print(string.format("  diag.bind_position_ms: %.3f", d.bind_position_ms or 0))
    print(string.format("  diag.bind_paint_ms: %.3f", d.bind_paint_ms or 0))
    print(string.format("  diag.bind_content_ms: %.3f", d.bind_content_ms or 0))
    print(string.format("  diag.bind_text_content_ms: %.3f", d.bind_text_content_ms or 0))
    print(string.format("  diag.bind_image_content_ms: %.3f", d.bind_image_content_ms or 0))
    print(string.format("  diag.bind_behavior_ms: %.3f", d.bind_behavior_ms or 0))
    print(string.format("  diag.bind_accessibility_ms: %.3f", d.bind_accessibility_ms or 0))
    print(string.format("  diag.node_count: %d", d.node_count or 0))
    print(string.format("  diag.ids_collected: %d", d.ids_collected or 0))
    print(string.format("  diag.anchored_count: %d", d.anchored_count or 0))
    print(string.format("  diag.text_count: %d", d.text_count or 0))
    print(string.format("  diag.image_count: %d", d.image_count or 0))
    print(string.format("  diag.inline_custom_count: %d", d.inline_custom_count or 0))
    print(string.format("  diag.resource_custom_count: %d", d.resource_custom_count or 0))
    print(string.format("  diag.paint_op_count: %d", d.paint_op_count or 0))
    print(string.format("  diag.pointer_rule_count: %d", d.pointer_rule_count or 0))
    print(string.format("  diag.key_rule_count: %d", d.key_rule_count or 0))
    print(string.format("  diag.drag_drop_rule_count: %d", d.drag_drop_rule_count or 0))
end
