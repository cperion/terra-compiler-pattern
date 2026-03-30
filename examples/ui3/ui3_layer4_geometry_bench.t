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

local function layout(position)
    return T.UiBound.Layout(
        T.UiDecl.Layout(
            T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto()),
            T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto()),
            T.UiCore.InFlow(),
            T.UiCore.None(),
            nil,
            nil,
            T.UiCore.Start(),
            T.UiCore.CrossStart(),
            T.UiCore.Insets(0, 0, 0, 0),
            T.UiCore.Insets(0, 0, 0, 0),
            0,
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

local function append_node(rows, role, debug_name, position, content, paint, visible, parent_index, first_child_index, child_count, subtree_count)
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
    rows.layout[#rows.layout + 1] = T.UiFlat.LayoutFacet(layout(position))
    rows.content[#rows.content + 1] = T.UiFlat.ContentFacet(content)
    rows.paint[#rows.paint + 1] = T.UiFlat.PaintFacet(T.UiDecl.Paint(L(paint)))
    rows.behavior[#rows.behavior + 1] = default_behavior()
    rows.accessibility[#rows.accessibility + 1] = hidden_accessibility()
    return rows
end

local width, height

local function box_paint(i, styled)
    return {
        T.UiDecl.Box(
            solid(0.12 + (i % 7) * 0.07, 0.18 + (i % 5) * 0.09, 0.30 + (i % 3) * 0.11, 0.88),
            styled and solid(0.95, 0.95, 0.98, 0.35) or nil,
            styled and 1 or 0,
            T.UiCore.CenterStroke(),
            zero_corners()
        )
    }
end

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

local function image_paint()
    return {
        T.UiDecl.Box(
            solid(1, 1, 1, 1),
            nil,
            0,
            T.UiCore.CenterStroke(),
            rounded(16)
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

local function add_anchor_root(rows, child_count)
    append_node(
        rows,
        T.UiCore.View(),
        "anchor-root",
        T.UiBound.InFlow(),
        T.UiBound.NoContent(),
        { T.UiDecl.Clip(zero_corners()) },
        true,
        nil,
        1,
        child_count,
        1 + child_count
    )
end

local function add_clip_host(rows, child_count)
    append_node(
        rows,
        T.UiCore.View(),
        "clip-host",
        T.UiBound.InFlow(),
        T.UiBound.NoContent(),
        { T.UiDecl.Clip(zero_corners()) },
        true,
        nil,
        1,
        child_count,
        1 + child_count
    )
end

local function build_inputs(box_count, scenario)
    local root_id = ({
        boxes = 93001,
        mixed = 93003,
        anchored_boxes = 93004,
        inflow_text = 93005,
        anchored_text = 93006,
        image_grid = 93007,
    })[scenario] or 93099

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

    if scenario == "anchored_boxes" then
        add_anchor_root(rows, box_count)
        local i = 0
        while i < box_count do
            append_node(
                rows,
                T.UiCore.View(),
                "anchored-box",
                anchored_to_root(rows),
                T.UiBound.NoContent(),
                box_paint(i, false),
                true,
                0
            )
            i = i + 1
        end
    elseif scenario == "anchored_text" then
        add_anchor_root(rows, box_count)
        local i = 0
        while i < box_count do
            append_node(
                rows,
                T.UiCore.TextRole(),
                "anchored-text",
                anchored_to_root(rows),
                text_content("anchored item"),
                {},
                true,
                0
            )
            i = i + 1
        end
    elseif scenario == "inflow_text" then
        local i = 0
        while i < box_count do
            append_node(
                rows,
                T.UiCore.TextRole(),
                "text",
                T.UiBound.InFlow(),
                text_content("inflow item"),
                {},
                true,
                nil
            )
            i = i + 1
        end
    elseif scenario == "image_grid" then
        local i = 0
        while i < box_count do
            append_node(
                rows,
                T.UiCore.ImageRole(),
                "image",
                T.UiBound.InFlow(),
                image_content(),
                image_paint(),
                true,
                nil
            )
            i = i + 1
        end
    else
        local styled = scenario == "mixed"
        if styled then
            add_clip_host(rows, box_count + 2)
        end

        local parent_index = styled and 0 or nil
        local i = 0
        while i < box_count do
            append_node(
                rows,
                T.UiCore.View(),
                "box",
                T.UiBound.InFlow(),
                T.UiBound.NoContent(),
                box_paint(i, styled),
                true,
                parent_index
            )
            i = i + 1
        end

        if styled then
            append_node(
                rows,
                T.UiCore.TextRole(),
                "text",
                T.UiBound.InFlow(),
                text_content("ui3 geometry mixed"),
                {},
                true,
                parent_index
            )
            append_node(
                rows,
                T.UiCore.ImageRole(),
                "image",
                T.UiBound.InFlow(),
                image_content(),
                image_paint(),
                true,
                parent_index
            )
        end
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

width = getenv_number("UI3_LAYER4_GEOMETRY_WIDTH", 1280)
height = getenv_number("UI3_LAYER4_GEOMETRY_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_LAYER4_GEOMETRY_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_LAYER4_GEOMETRY_ITERS", 60)))
local box_count = math.max(0, math.floor(getenv_number("UI3_LAYER4_GEOMETRY_BOXES", 1000)))
local scenario = os.getenv("UI3_LAYER4_GEOMETRY_SCENARIO") or "mixed"
local assets = build_assets()

local flat = build_inputs(box_count, scenario)

local build_inputs_avg_ms = bench_avg_ms(iters, function()
    build_inputs(box_count, scenario)
end)

local lower_t0 = now_ns()
local geometry_input = flat:lower_geometry(assets)
local lower_geometry_ms = ms_between(lower_t0, now_ns())

local lower_geometry_existing_scene_avg_ms = bench_avg_ms(iters, function()
    flat:lower_geometry(assets)
end)

local build_plus_lower_geometry_avg_ms = bench_avg_ms(iters, function()
    build_inputs(box_count, scenario):lower_geometry(assets)
end)

for _ = 1, warmup do
    flat:lower_geometry(assets)
end

print(("ui3 layer4-geometry backend=terra scenario=%s width=%d height=%d warmup=%d iters=%d boxes=%d")
    :format(scenario, width, height, warmup, iters, box_count))
print(("  build_inputs_avg_ms: %.3f"):format(build_inputs_avg_ms))
print(("  lower_geometry_ms: %.3f"):format(lower_geometry_ms))
print(("  lower_geometry_existing_scene_avg_ms: %.3f"):format(lower_geometry_existing_scene_avg_ms))
print(("  build_plus_lower_geometry_avg_ms: %.3f"):format(build_plus_lower_geometry_avg_ms))
print(("  regions: %d"):format(#geometry_input.regions))
print(("  nodes: %d"):format(#geometry_input.regions[1].headers))
