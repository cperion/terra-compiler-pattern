local asdl = require("asdl")
local U = require("unit")
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

local function solid(r, g, b, a)
    return T.UiCore.Solid(T.UiCore.Color(r, g, b, a))
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

local function font_ref(n)
    return T.UiCore.FontRef(n)
end

local function image_ref(n)
    return T.UiCore.ImageRef(n)
end

local function identity_transform()
    return T.UiCore.Transform2D(1, 0, 0, 1, 0, 0)
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

local function layout()
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
        T.UiBound.InFlow()
    )
end

local function placed_node(r)
    return T.UiGeometry.Placed(
        T.UiGeometry.PlacedNode(
            r,
            r,
            r,
            size(r.w, r.h),
            nil
        )
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

local function append_node(rows, role, debug_name, r, content, paint, parent_index, first_child_index, child_count, subtree_count)
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
    rows.visibility[#rows.visibility + 1] = T.UiFlat.VisibilityFacet(true)
    rows.interactivity[#rows.interactivity + 1] = T.UiFlat.InteractivityFacet(true)
    rows.layout[#rows.layout + 1] = T.UiFlat.LayoutFacet(layout())
    rows.content[#rows.content + 1] = T.UiFlat.ContentFacet(content)
    rows.paint[#rows.paint + 1] = T.UiFlat.PaintFacet(T.UiDecl.Paint(L(paint)))
    rows.behavior[#rows.behavior + 1] = default_behavior()
    rows.accessibility[#rows.accessibility + 1] = hidden_accessibility()
    rows.geometry[#rows.geometry + 1] = placed_node(r)
    return rows
end

local function box_rect(i, col, row)
    return rect(16 + col * 18, 16 + row * 18, 12, 12)
end

local width, height

local function box_content()
    return T.UiBound.NoContent()
end

local function box_paint(i, stroked)
    return {
        T.UiDecl.Box(
            solid(0.12 + (i % 7) * 0.07, 0.18 + (i % 5) * 0.09, 0.30 + (i % 3) * 0.11, 0.88),
            stroked and solid(0.95, 0.95, 0.98, 0.35) or nil,
            stroked and 1 or 0,
            T.UiCore.CenterStroke(),
            zero_corners()
        )
    }
end

local function clip_host_content()
    return T.UiBound.NoContent()
end

local function clip_host_paint()
    return {
        T.UiDecl.Clip(zero_corners())
    }
end

local function shadow_content()
    return T.UiBound.NoContent()
end

local function shadow_paint()
    return {
        T.UiDecl.Shadow(
            solid(0.0, 0.0, 0.0, 0.30),
            8,
            0,
            0,
            4,
            T.UiCore.DropShadow(),
            rounded(12)
        )
    }
end

local function text_content()
    return T.UiBound.Text(
        T.UiBound.BoundText(
            T.UiCore.TextValue("ui3 layer4 text benchmark"),
            T.UiBound.BoundTextStyle(
                font_ref(1),
                24,
                T.UiCore.Weight400(),
                T.UiCore.Roman(),
                0,
                28,
                T.UiCore.Color(0.96, 0.98, 1.0, 1.0)
            ),
            T.UiCore.TextLayout(T.UiCore.WrapWord(), T.UiCore.ClipText(), T.UiCore.TextStart(), 2)
        )
    )
end

local function text_paint()
    return {
        T.UiDecl.Transform(identity_transform())
    }
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
            solid(1.0, 1.0, 1.0, 1.0),
            nil,
            0,
            T.UiCore.CenterStroke(),
            rounded(16)
        )
    }
end

local function build_inputs(box_count, scenario)
    local styled = scenario ~= "boxes"
    local root_id = ({
        boxes = 92001,
        boxstyled = 92002,
        boxshadow = 92003,
        boxtext = 92004,
        boximage = 92005,
        mixed = 92006,
    })[scenario] or 92099

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
        geometry = {},
    }

    local extra_count = 0
    if scenario == "boxshadow" or scenario == "mixed" then extra_count = extra_count + 1 end
    if scenario == "boxtext" or scenario == "mixed" then extra_count = extra_count + 1 end
    if scenario == "boximage" or scenario == "mixed" then extra_count = extra_count + 1 end

    if styled then
        append_node(
            rows,
            T.UiCore.View(),
            "clip-host",
            rect(40, 40, 520, 320),
            clip_host_content(),
            clip_host_paint(),
            nil,
            1,
            box_count + extra_count,
            1 + box_count + extra_count
        )
    end

    local parent_index = styled and 0 or nil
    local cols = math.max(1, math.floor(math.sqrt(math.max(1, box_count))))
    local i = 0
    while i < box_count do
        local col = i % cols
        local row = math.floor(i / cols)
        append_node(
            rows,
            T.UiCore.View(),
            "box",
            box_rect(i, col, row),
            box_content(),
            box_paint(i, styled),
            parent_index
        )
        i = i + 1
    end

    if scenario == "boxshadow" or scenario == "mixed" then
        append_node(rows, T.UiCore.View(), "shadow", rect(620, 80, 180, 120), shadow_content(), shadow_paint(), parent_index)
    end

    if scenario == "boxtext" or scenario == "mixed" then
        append_node(rows, T.UiCore.TextRole(), "text", rect(620, 90, 320, 80), text_content(), text_paint(), parent_index)
    end

    if scenario == "boximage" or scenario == "mixed" then
        append_node(rows, T.UiCore.ImageRole(), "image", rect(620, 190, 180, 120), image_content(), image_paint(), parent_index)
    end

    local region_header = T.UiFlatShape.RegionHeader(T.UiCore.ElementId(root_id), scenario, 0)

    local flat = T.UiFlat.Scene(
        size(width, height),
        L {
            T.UiFlat.Region(
                region_header,
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

    local geometry = T.UiGeometry.Scene(
        size(width, height),
        L {
            T.UiGeometry.Region(
                region_header,
                L(rows.headers),
                L(rows.geometry)
            )
        }
    )

    return flat, geometry
end

local function ensure_unit_state(unit)
    if unit.state_t == U.EMPTY then return nil end
    if unit.__state == nil then
        unit.__state = terralib.new(unit.state_t)
        if unit.init then unit.init(unit.__state) end
    end
    return unit.__state
end

width = getenv_number("UI3_LAYER4_WIDTH", 1280)
height = getenv_number("UI3_LAYER4_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_LAYER4_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_LAYER4_ITERS", 60)))
local box_count = math.max(0, math.floor(getenv_number("UI3_LAYER4_BOXES", 1000)))
local scenario = os.getenv("UI3_LAYER4_SCENARIO") or "mixed"
local assets = build_assets()

local flat, geometry = build_inputs(box_count, scenario)

local build_inputs_avg_ms = bench_avg_ms(iters, function()
    build_inputs(box_count, scenario)
end)

local lower_t0 = now_ns()
local render_facts = flat:lower_render_facts()
local lower_ms = ms_between(lower_t0, now_ns())

local lower_existing_scene_avg_ms = bench_avg_ms(iters, function()
    flat:lower_render_facts()
end)

local build_plus_lower_avg_ms = bench_avg_ms(iters, function()
    local fresh_flat = build_inputs(box_count, scenario)
    fresh_flat:lower_render_facts()
end)

local project_t0 = now_ns()
local render_scene = geometry:project_render_scene(render_facts)
local project_ms = ms_between(project_t0, now_ns())

local schedule_t0 = now_ns()
local render_ir = render_scene:schedule_render_machine_ir()
local schedule_ms = ms_between(schedule_t0, now_ns())

local define_t0 = now_ns()
local machine = render_ir:define_machine()
local define_ms = ms_between(define_t0, now_ns())

local runtime = Backend.init_window("ui3-layer4-render", width, height)
Backend.FFI.SDL_GL_SetSwapInterval(0)

local compile_t0 = now_ns()
local unit = machine.gen:compile(Backend)
local compile_ms = ms_between(compile_t0, now_ns())

local unit_state = ensure_unit_state(unit)

local materialize_t0 = now_ns()
unit.__payload_keep = machine:materialize(Backend, assets, unit_state)
local materialize_ms = ms_between(materialize_t0, now_ns())

local steady_rematerialize_ms = bench_avg_ms(iters, function()
    unit.__payload_keep = machine:materialize(Backend, assets, unit_state)
end)

for _ = 1, warmup do
    Backend.render_unit(runtime, unit)
end

local first_t0 = now_ns()
Backend.render_unit(runtime, unit)
local first_render_ms = ms_between(first_t0, now_ns())

local steady_render_ms = bench_avg_ms(iters, function()
    Backend.render_unit(runtime, unit)
end)

print(("ui3 layer4-render backend=terra scenario=%s width=%d height=%d warmup=%d iters=%d boxes=%d")
    :format(scenario, width, height, warmup, iters, box_count))
print(("  build_inputs_avg_ms:   %.3f"):format(build_inputs_avg_ms))
print(("  lower_ms:              %.3f"):format(lower_ms))
print(("  lower_existing_scene_avg_ms: %.3f"):format(lower_existing_scene_avg_ms))
print(("  build_plus_lower_avg_ms: %.3f"):format(build_plus_lower_avg_ms))
print(("  project_ms:            %.3f"):format(project_ms))
print(("  schedule_ms:           %.3f"):format(schedule_ms))
print(("  define_machine_ms:     %.3f"):format(define_ms))
print(("  compile_ms:            %.3f"):format(compile_ms))
print(("  materialize_ms:        %.3f"):format(materialize_ms))
print(("  steady_rematerialize_ms: %.3f"):format(steady_rematerialize_ms))
print(("  first_render_ms:       %.3f"):format(first_render_ms))
print(("  steady_render_ms:      %.3f"):format(steady_render_ms))

Backend.shutdown_window(runtime)
