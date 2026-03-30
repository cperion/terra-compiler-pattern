local asdl = require("asdl")
local L = asdl.List
local Backend = require("examples.ui.backends.terra_sdl_gl")
local Schema = require("unit").load_inspect_spec("examples/ui3")

local T = Schema.ctx

local function getenv_number(name, default)
    local raw = os.getenv(name)
    if not raw or raw == "" then return default end
    local n = tonumber(raw)
    if not n then return default end
    return n
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

local function rect(x, y, w, h)
    return T.UiCore.Rect(x, y, w, h)
end

local function size(w, h)
    return T.UiCore.Size(w, h)
end

local function zero_corners()
    return T.UiCore.Corners(0, 0, 0, 0)
end

local function rounded(v)
    return T.UiCore.Corners(v, v, v, v)
end

local function solid(r, g, b, a)
    return T.UiCore.Solid(T.UiCore.Color(r, g, b, a))
end

local function font_ref(n)
    return T.UiCore.FontRef(n)
end

local function image_ref(n)
    return T.UiCore.ImageRef(n)
end

local function build_assets()
    local font = font_ref(1)
    local image = image_ref(2)
    return T.UiAsset.Catalog(
        font,
        L {
            T.UiAsset.FontAsset(font, "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf")
        },
        L {
            T.UiAsset.ImageAsset(image, "/tmp/ui2-demo-placeholder.png")
        }
    )
end

local function layout(position, flow, gap)
    return T.UiBound.Layout(
        T.UiDecl.Layout(
            T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto()),
            T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto()),
            T.UiCore.InFlow(),
            flow or T.UiCore.None(),
            nil,
            nil,
            T.UiCore.Start(),
            T.UiCore.CrossStart(),
            T.UiCore.Insets(0, 0, 0, 0),
            T.UiCore.Insets(0, 0, 0, 0),
            gap or 0,
            T.UiCore.Visible(),
            T.UiCore.Visible(),
            nil
        ),
        position
    )
end

local function node_header(index, id, debug_name, role, parent_index, first_child_index, child_count, subtree_count)
    return T.UiFlatShape.NodeHeader(
        index,
        parent_index,
        first_child_index,
        child_count or 0,
        subtree_count or 1,
        T.UiCore.ElementId(id),
        nil,
        debug_name,
        role
    )
end

local function default_behavior()
    return T.UiFlat.BehaviorFacet(
        T.UiDecl.Behavior(
            T.UiDecl.HitNone(),
            T.UiDecl.NotFocusable(),
            L {},
            nil,
            L {},
            nil,
            L {}
        )
    )
end

local function hidden_accessibility()
    return T.UiFlat.AccessibilityFacet(T.UiBound.Hidden())
end

local function append_node(rows, role, debug_name, position, flow, gap, content, paint, visible, parent_index, first_child_index, child_count, subtree_count)
    local index = #rows.headers
    rows.headers[#rows.headers + 1] = node_header(
        index,
        rows.node_id_base + index,
        debug_name,
        role,
        parent_index,
        first_child_index,
        child_count,
        subtree_count
    )
    rows.visibility[#rows.visibility + 1] = T.UiFlat.VisibilityFacet(visible)
    rows.interactivity[#rows.interactivity + 1] = T.UiFlat.InteractivityFacet(true)
    rows.layout[#rows.layout + 1] = T.UiFlat.LayoutFacet(layout(position, flow, gap))
    rows.content[#rows.content + 1] = T.UiFlat.ContentFacet(content)
    rows.paint[#rows.paint + 1] = T.UiFlat.PaintFacet(T.UiDecl.Paint(L(paint)))
    rows.behavior[#rows.behavior + 1] = default_behavior()
    rows.accessibility[#rows.accessibility + 1] = hidden_accessibility()
    return rows
end

local width, height

local function text_content(label)
    return T.UiBound.Text(
        T.UiBound.BoundText(
            T.UiCore.TextValue(label),
            T.UiBound.BoundTextStyle(
                font_ref(1),
                16,
                T.UiCore.Weight400(),
                T.UiCore.Roman(),
                0,
                20,
                T.UiCore.Color(1, 1, 1, 1)
            ),
            T.UiCore.TextLayout(T.UiCore.WrapWord(), T.UiCore.ClipText(), T.UiCore.TextStart(), 2)
        )
    )
end

local function image_content()
    return T.UiBound.Image(
        image_ref(2),
        T.UiCore.ImageStyle(
            T.UiCore.StretchImage(),
            T.UiCore.Linear(),
            1,
            zero_corners()
        )
    )
end

local function box_paint(i)
    return {
        T.UiDecl.Box(
            solid(0.12 + (i % 7) * 0.07, 0.18 + (i % 5) * 0.09, 0.30 + (i % 3) * 0.11, 0.88),
            nil,
            0,
            T.UiCore.CenterStroke(),
            zero_corners()
        )
    }
end

local function anchored_to_root(rows)
    return T.UiBound.AnchoredTo(
        T.UiCore.ElementId(rows.node_id_base),
        T.UiCore.Left(),
        T.UiCore.Top(),
        T.UiCore.Right(),
        T.UiCore.Bottom(),
        4,
        6
    )
end

local function add_root(rows, scenario, child_count)
    local flow = (scenario == "row" and T.UiCore.Row())
        or (scenario == "column" and T.UiCore.Column())
        or T.UiCore.None()
    append_node(
        rows,
        T.UiCore.View(),
        "root",
        T.UiBound.InFlow(),
        flow,
        4,
        T.UiBound.NoContent(),
        { T.UiDecl.Clip(zero_corners()) },
        true,
        nil,
        1,
        child_count,
        1 + child_count
    )
end

local function build_flat(box_count, scenario)
    local root_id = ({
        boxes = 94001,
        row = 94002,
        column = 94003,
        anchored = 94004,
        mixed = 94005,
    })[scenario] or 94099

    local rows = {
        node_id_base = root_id + 1000,
        headers = {},
        visibility = {},
        interactivity = {},
        layout = {},
        content = {},
        paint = {},
        behavior = {},
        accessibility = {},
    }

    local extra = (scenario == "mixed") and 2 or 0
    add_root(rows, scenario, box_count + extra)

    local i = 0
    while i < box_count do
        local role = (scenario == "mixed" and (i % 2 == 0)) and T.UiCore.TextRole() or T.UiCore.View()
        local content = role.kind == "TextRole"
            and text_content("solve bench item")
            or T.UiBound.NoContent()
        local position = (scenario == "anchored") and anchored_to_root(rows) or T.UiBound.InFlow()
        append_node(
            rows,
            role,
            "item",
            position,
            T.UiCore.None(),
            0,
            content,
            box_paint(i),
            true,
            0
        )
        i = i + 1
    end

    if scenario == "mixed" then
        append_node(
            rows,
            T.UiCore.ImageRole(),
            "image",
            T.UiBound.InFlow(),
            T.UiCore.None(),
            0,
            image_content(),
            { T.UiDecl.Box(solid(1,1,1,1), nil, 0, T.UiCore.CenterStroke(), rounded(12)) },
            true,
            0
        )
        append_node(
            rows,
            T.UiCore.View(),
            "abs",
            T.UiBound.Absolute(T.UiCore.EdgePx(20), T.UiCore.EdgePx(30), T.UiCore.Unset(), T.UiCore.Unset()),
            T.UiCore.None(),
            0,
            T.UiBound.NoContent(),
            box_paint(9999),
            true,
            0
        )
    end

    return T.UiFlat.Scene(
        size(width, height),
        L {
            T.UiFlat.Region(
                T.UiFlatShape.RegionHeader(T.UiCore.ElementId(root_id), scenario, 0),
                T.UiFlat.RenderRegionFacet(0),
                T.UiFlat.QueryRegionFacet(false, false),
                L(rows.headers),
                L(rows.visibility),
                L(rows.interactivity),
                L(rows.layout),
                L(rows.content),
                L(rows.paint),
                L(rows.behavior),
                L(rows.accessibility)
            )
        }
    )
end

width = getenv_number("UI3_LAYER5_WIDTH", 1280)
height = getenv_number("UI3_LAYER5_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_LAYER5_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_LAYER5_ITERS", 60)))
local box_count = math.max(0, math.floor(getenv_number("UI3_LAYER5_BOXES", 1000)))
local scenario = os.getenv("UI3_LAYER5_SCENARIO") or "mixed"
local assets = build_assets()

local flat = build_flat(box_count, scenario)
local geometry_input = flat:lower_geometry(assets)

local build_inputs_avg_ms = bench_avg_ms(iters, function()
    build_flat(box_count, scenario)
end)

local lower_geometry_existing_flat_avg_ms = bench_avg_ms(iters, function()
    flat:lower_geometry(assets)
end)

local solve_t0 = now_ns()
local geometry = geometry_input:solve()
local solve_ms = ms_between(solve_t0, now_ns())

local solve_existing_input_avg_ms = bench_avg_ms(iters, function()
    geometry_input:solve()
end)

local build_plus_lower_plus_solve_avg_ms = bench_avg_ms(iters, function()
    build_flat(box_count, scenario):lower_geometry(assets):solve()
end)

for _ = 1, warmup do
    geometry_input:solve()
end

print(("ui3 layer5-solve backend=terra scenario=%s width=%d height=%d warmup=%d iters=%d boxes=%d")
    :format(scenario, width, height, warmup, iters, box_count))
print(("  build_inputs_avg_ms: %.3f"):format(build_inputs_avg_ms))
print(("  lower_geometry_existing_flat_avg_ms: %.3f"):format(lower_geometry_existing_flat_avg_ms))
print(("  solve_ms: %.3f"):format(solve_ms))
print(("  solve_existing_input_avg_ms: %.3f"):format(solve_existing_input_avg_ms))
print(("  build_plus_lower_plus_solve_avg_ms: %.3f"):format(build_plus_lower_plus_solve_avg_ms))
print(("  regions: %d"):format(#geometry.regions))
print(("  nodes: %d"):format(#geometry.regions[1].nodes))
