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

local function viewport(w, h)
    return T.UiCore.Size(w, h)
end

local function auto_size()
    return T.UiCore.SizeSpec(C(T.UiCore.Auto), C(T.UiCore.Auto), C(T.UiCore.Auto))
end

local function base_layout(flow)
    return T.UiBound.Layout(
        T.UiDecl.Layout(
            auto_size(),
            auto_size(),
            C(T.UiCore.InFlow),
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
        ),
        C(T.UiBound.InFlow)
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
    return C(T.UiBound.Hidden)
end

local function exposed_accessibility(i)
    return T.UiBound.Exposed(C(T.UiCore.AccButton), "item", nil, i)
end

local function text_content(i)
    return T.UiBound.Text(T.UiBound.BoundText(
        T.UiCore.TextValue("node " .. tostring(i)),
        T.UiBound.BoundTextStyle(
            T.UiCore.FontRef(1),
            14,
            C(T.UiCore.Weight400),
            C(T.UiCore.Roman),
            0,
            16,
            T.UiCore.Color(1, 1, 1, 1)
        ),
        T.UiCore.TextLayout(C(T.UiCore.NoWrap), C(T.UiCore.ClipText), C(T.UiCore.TextStart), 0)
    ))
end

local function image_content()
    return T.UiBound.Image(
        T.UiCore.ImageRef(2),
        T.UiCore.ImageStyle(C(T.UiCore.Contain), C(T.UiCore.Linear), 1, T.UiCore.Corners(0, 0, 0, 0))
    )
end

local function custom_content(i)
    if i % 2 == 0 then
        return T.UiBound.InlineCustomContent(900 + (i % 3), i)
    end
    return T.UiBound.ResourceCustomContent(900 + (i % 3), 10000 + i, 20000 + i)
end

local function node(base, id, debug_name, role, flags, layout, paint, content, behavior, accessibility, children)
    return T.UiBound.Node(
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

local function mixed_leaf(base, i)
    local role = (i % 4 == 0) and C(T.UiCore.ImageRole)
        or (i % 4 == 1) and C(T.UiCore.TextRole)
        or C(T.UiCore.View)
    local content = (i % 4 == 0) and image_content()
        or (i % 4 == 1) and text_content(i)
        or (i % 4 == 2) and custom_content(i)
        or C(T.UiBound.NoContent)
    return node(
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

local function bare_leaf(base, i)
    return node(
        base,
        i,
        "bare-" .. tostring(i),
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        empty_paint(),
        C(T.UiBound.NoContent),
        no_behavior(),
        hidden_accessibility(),
        L {}
    )
end

local function box_leaf(base, i)
    return node(
        base,
        i,
        "box-" .. tostring(i),
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        box_paint(T.UiCore.Corners(0, 0, 0, 0)),
        C(T.UiBound.NoContent),
        no_behavior(),
        hidden_accessibility(),
        L {}
    )
end

local function behavior_leaf(base, i)
    return node(
        base,
        i,
        "behavior-" .. tostring(i),
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        empty_paint(),
        C(T.UiBound.NoContent),
        interactive_behavior(i),
        hidden_accessibility(),
        L {}
    )
end

local function text_leaf(base, i)
    return node(
        base,
        i,
        "text-" .. tostring(i),
        C(T.UiCore.TextRole),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        empty_paint(),
        text_content(i),
        no_behavior(),
        hidden_accessibility(),
        L {}
    )
end

local function image_leaf(base, i)
    return node(
        base,
        i,
        "image-" .. tostring(i),
        C(T.UiCore.ImageRole),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        empty_paint(),
        image_content(),
        no_behavior(),
        hidden_accessibility(),
        L {}
    )
end

local function custom_leaf(base, i)
    return node(
        base,
        i,
        "custom-" .. tostring(i),
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        empty_paint(),
        custom_content(i),
        no_behavior(),
        hidden_accessibility(),
        L {}
    )
end

local function root_with_children(base, node_count, child_builder, root_paint, root_behavior)
    local children = {}
    local i = 1
    while i <= node_count do
        children[#children + 1] = child_builder(base, i)
        i = i + 1
    end
    return node(
        base,
        0,
        "root",
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        root_paint or empty_paint(),
        C(T.UiBound.NoContent),
        root_behavior or no_behavior(),
        hidden_accessibility(),
        L(children)
    )
end

local function mixed_root(base, node_count)
    local children = {}
    local i = 1
    while i <= node_count do
        children[#children + 1] = mixed_leaf(base, i)
        i = i + 1
    end
    return node(
        base,
        0,
        "root",
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        mixed_paint(0),
        C(T.UiBound.NoContent),
        interactive_behavior(0),
        hidden_accessibility(),
        L(children)
    )
end

local function nested_root(base, node_count)
    local current = node(
        base,
        node_count,
        "nested-" .. tostring(node_count),
        (node_count % 2 == 0) and C(T.UiCore.TextRole) or C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        mixed_paint(node_count),
        (node_count % 2 == 0) and text_content(node_count) or C(T.UiBound.NoContent),
        interactive_behavior(node_count),
        hidden_accessibility(),
        L {}
    )

    local i = node_count - 1
    while i >= 1 do
        current = node(
            base,
            i,
            "nested-" .. tostring(i),
            C(T.UiCore.View),
            T.UiDecl.Flags(true, true),
            base_layout(C(T.UiCore.Column)),
            mixed_paint(i),
            C(T.UiBound.NoContent),
            interactive_behavior(i),
            hidden_accessibility(),
            L { current }
        )
        i = i - 1
    end

    return node(
        base,
        0,
        "root",
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        empty_paint(),
        C(T.UiBound.NoContent),
        no_behavior(),
        hidden_accessibility(),
        L { current }
    )
end

local function nested_bare_root(base, node_count)
    local current = bare_leaf(base, node_count)
    local i = node_count - 1
    while i >= 1 do
        current = node(
            base,
            i,
            "nested-bare-" .. tostring(i),
            C(T.UiCore.View),
            T.UiDecl.Flags(true, true),
            base_layout(C(T.UiCore.Column)),
            empty_paint(),
            C(T.UiBound.NoContent),
            no_behavior(),
            hidden_accessibility(),
            L { current }
        )
        i = i - 1
    end

    return node(
        base,
        0,
        "root",
        C(T.UiCore.View),
        T.UiDecl.Flags(true, true),
        base_layout(C(T.UiCore.Column)),
        empty_paint(),
        C(T.UiBound.NoContent),
        no_behavior(),
        hidden_accessibility(),
        L { current }
    )
end

local function build_document(node_count, scenario, seed)
    local base = 1000000 + (seed * 10000)
    local root = (scenario == "bare") and root_with_children(base, node_count, bare_leaf)
        or (scenario == "boxes") and root_with_children(base, node_count, box_leaf)
        or (scenario == "behavior") and root_with_children(base, node_count, behavior_leaf)
        or (scenario == "text") and root_with_children(base, node_count, text_leaf)
        or (scenario == "image") and root_with_children(base, node_count, image_leaf)
        or (scenario == "custom") and root_with_children(base, node_count, custom_leaf)
        or (scenario == "mixed") and mixed_root(base, node_count)
        or (scenario == "nested") and nested_root(base, node_count)
        or (scenario == "nested_bare") and nested_bare_root(base, node_count)
        or root_with_children(base, node_count, box_leaf)
    return T.UiBound.Document(L {
        T.UiBound.Entry(T.UiCore.ElementId(base - 1), scenario .. "-entry", root, 0, false, false)
    })
end

local width = getenv_number("UI3_FLATTEN_WIDTH", 1280)
local height = getenv_number("UI3_FLATTEN_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_FLATTEN_WARMUP", 3)))
local iters = math.max(1, math.floor(getenv_number("UI3_FLATTEN_ITERS", 50)))
local node_count = math.max(1, math.floor(getenv_number("UI3_FLATTEN_NODES", 1000)))
local scenario = getenv_string("UI3_FLATTEN_SCENARIO", "boxes")
local vp = viewport(width, height)

local doc = build_document(node_count, scenario, 1)
local flatten_ms = bench_avg_ms(1, function()
    doc:flatten(vp)
end)

for _ = 1, warmup do
    doc:flatten(vp)
end

local flatten_existing_doc_avg_ms = bench_avg_ms(iters, function()
    doc:flatten(vp)
end)

local build_seed = 500
local build_document_avg_ms = bench_avg_ms(iters, function()
    build_seed = build_seed + 1
    build_document(node_count, scenario, build_seed)
end)

local seed = 1000
local build_plus_flatten_avg_ms = bench_avg_ms(iters, function()
    seed = seed + 1
    local fresh = build_document(node_count, scenario, seed)
    fresh:flatten(vp)
end)

local sample = doc:flatten(vp)
print(string.format(
    "ui3 flatten bench width=%d height=%d warmup=%d iters=%d nodes=%d scenario=%s",
    width,
    height,
    warmup,
    iters,
    node_count,
    scenario
))
print(string.format("  flatten_ms: %.6f", flatten_ms))
print(string.format("  flatten_existing_doc_avg_ms: %.6f", flatten_existing_doc_avg_ms))
print(string.format("  build_document_avg_ms: %.6f", build_document_avg_ms))
print(string.format("  build_plus_flatten_avg_ms: %.6f", build_plus_flatten_avg_ms))
print(string.format("  fresh_flatten_suffix_avg_ms: %.6f", build_plus_flatten_avg_ms - build_document_avg_ms))
print(string.format("  regions: %d", #sample.regions))
print(string.format("  flat_nodes: %d", #sample.regions[1].headers))
