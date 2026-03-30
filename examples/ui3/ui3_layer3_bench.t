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

local function default_use()
    return T.UiRenderFacts.DefaultUse()
end

local function no_content()
    return T.UiRenderFacts.NoContent()
end

local function no_effects()
    return L {}
end

local function no_decorations()
    return L {}
end

local function box_fact(i, stroked, clipped)
    local fill = solid(0.12 + (i % 7) * 0.07, 0.18 + (i % 5) * 0.09, 0.30 + (i % 3) * 0.11, 0.88)
    local stroke = stroked and solid(0.95, 0.95, 0.98, 0.35) or nil
    local effects = clipped and L {
        T.UiRenderFacts.LocalClip(zero_corners())
    } or L {}

    return T.UiRenderFacts.Fact(
        effects,
        L {
            T.UiRenderFacts.BoxDecor(
                fill,
                stroke,
                stroked and 1 or 0,
                T.UiCore.CenterStroke(),
                zero_corners()
            )
        },
        no_content(),
        default_use()
    )
end

local function shadow_fact()
    return T.UiRenderFacts.Fact(
        no_effects(),
        L {
            T.UiRenderFacts.ShadowDecor(
                solid(0.0, 0.0, 0.0, 0.30),
                8,
                0,
                0,
                4,
                T.UiCore.DropShadow(),
                rounded(12)
            )
        },
        no_content(),
        default_use()
    )
end

local function text_fact()
    return T.UiRenderFacts.Fact(
        L {
            T.UiRenderFacts.LocalTransform(identity_transform())
        },
        no_decorations(),
        T.UiRenderFacts.Text(
            T.UiRenderFacts.TextContent(
                T.UiCore.TextValue("ui3 layer3 text benchmark"),
                font_ref(1),
                24,
                T.UiCore.Weight400(),
                T.UiCore.Roman(),
                0,
                28,
                T.UiCore.Color(0.96, 0.98, 1.0, 1.0),
                T.UiCore.WrapWord(),
                T.UiCore.ClipText(),
                T.UiCore.TextStart(),
                2
            )
        ),
        default_use()
    )
end

local function image_fact()
    return T.UiRenderFacts.Fact(
        no_effects(),
        no_decorations(),
        T.UiRenderFacts.Image(
            T.UiRenderFacts.ImageContent(
                image_ref(2),
                T.UiCore.StretchImage(),
                T.UiCore.Linear()
            )
        ),
        T.UiRenderFacts.ImageUse(rounded(16))
    )
end

local function append_node(rows, role, debug_name, r, fact, parent_index, first_child_index, child_count, subtree_count)
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
    rows.nodes[#rows.nodes + 1] = placed_node(r)
    rows.facts[#rows.facts + 1] = fact
    return rows
end

local function box_rect(i, col, row)
    return rect(16 + col * 18, 16 + row * 18, 12, 12)
end

local width, height

local function build_inputs(box_count, scenario)
    local styled = scenario ~= "boxes"
    local label = scenario
    local root_id = ({
        boxes = 91001,
        boxstyled = 91002,
        boxshadow = 91003,
        boxtext = 91004,
        boximage = 91005,
        mixed = 91006,
    })[scenario] or 91099

    local rows = {
        node_id_base = root_id + 1000,
        headers = {},
        nodes = {},
        facts = {},
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
            T.UiRenderFacts.Fact(
                L { T.UiRenderFacts.LocalClip(zero_corners()) },
                no_decorations(),
                no_content(),
                default_use()
            ),
            nil,
            1,
            box_count + extra_count,
            1 + box_count + extra_count
        )
    end

    local box_parent_index = styled and 0 or nil
    local cols = math.max(1, math.floor(math.sqrt(math.max(1, box_count))))
    local i = 0
    while i < box_count do
        local col = i % cols
        local row = math.floor(i / cols)
        append_node(rows, T.UiCore.View(), "box", box_rect(i, col, row), box_fact(i, styled, false), box_parent_index)
        i = i + 1
    end

    if scenario == "boxshadow" or scenario == "mixed" then
        append_node(rows, T.UiCore.View(), "shadow", rect(620, 80, 180, 120), shadow_fact(), box_parent_index)
    end

    if scenario == "boxtext" or scenario == "mixed" then
        append_node(rows, T.UiCore.TextRole(), "text", rect(620, 90, 320, 80), text_fact(), box_parent_index)
    end

    if scenario == "boximage" or scenario == "mixed" then
        append_node(rows, T.UiCore.ImageRole(), "image", rect(620, 190, 180, 120), image_fact(), box_parent_index)
    end

    local header = T.UiFlatShape.RegionHeader(T.UiCore.ElementId(root_id), label, 0)

    local geometry = T.UiGeometry.Scene(
        size(width, height),
        L {
            T.UiGeometry.Region(
                header,
                L(rows.headers),
                L(rows.nodes)
            )
        }
    )

    local render_facts = T.UiRenderFacts.Scene(
        L {
            T.UiRenderFacts.Region(
                header,
                0,
                L(rows.facts)
            )
        }
    )

    return geometry, render_facts
end

local function ensure_unit_state(unit)
    if unit.state_t == U.EMPTY then return nil end
    if unit.__state == nil then
        unit.__state = terralib.new(unit.state_t)
        if unit.init then unit.init(unit.__state) end
    end
    return unit.__state
end

width = getenv_number("UI3_LAYER3_WIDTH", 1280)
height = getenv_number("UI3_LAYER3_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_LAYER3_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_LAYER3_ITERS", 60)))
local box_count = math.max(0, math.floor(getenv_number("UI3_LAYER3_BOXES", 1000)))
local scenario = os.getenv("UI3_LAYER3_SCENARIO") or "mixed"
local assets = build_assets()

local geometry, render_facts = build_inputs(box_count, scenario)

local build_inputs_avg_ms = bench_avg_ms(iters, function()
    build_inputs(box_count, scenario)
end)

local project_t0 = now_ns()
local render_scene = geometry:project_render_scene(render_facts)
local project_ms = ms_between(project_t0, now_ns())

local project_existing_inputs_avg_ms = bench_avg_ms(iters, function()
    geometry:project_render_scene(render_facts)
end)

local build_plus_project_avg_ms = bench_avg_ms(iters, function()
    local g, rf = build_inputs(box_count, scenario)
    g:project_render_scene(rf)
end)

local schedule_t0 = now_ns()
local render_ir = render_scene:schedule_render_machine_ir()
local schedule_ms = ms_between(schedule_t0, now_ns())

local define_t0 = now_ns()
local machine = render_ir:define_machine()
local define_ms = ms_between(define_t0, now_ns())

local runtime = Backend.init_window("ui3-layer3", width, height)
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

print(("ui3 layer3 backend=terra scenario=%s width=%d height=%d warmup=%d iters=%d boxes=%d")
    :format(scenario, width, height, warmup, iters, box_count))
print(("  build_inputs_avg_ms:  %.3f"):format(build_inputs_avg_ms))
print(("  project_ms:           %.3f"):format(project_ms))
print(("  project_existing_inputs_avg_ms: %.3f"):format(project_existing_inputs_avg_ms))
print(("  build_plus_project_avg_ms:  %.3f"):format(build_plus_project_avg_ms))
print(("  schedule_ms:          %.3f"):format(schedule_ms))
print(("  define_machine_ms:    %.3f"):format(define_ms))
print(("  compile_ms:           %.3f"):format(compile_ms))
print(("  materialize_ms:       %.3f"):format(materialize_ms))
print(("  steady_rematerialize_ms: %.3f"):format(steady_rematerialize_ms))
print(("  first_render_ms:      %.3f"):format(first_render_ms))
print(("  steady_render_ms:     %.3f"):format(steady_render_ms))

Backend.shutdown_window(runtime)
