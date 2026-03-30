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

local function occurrence_state(clips, opacity, transform)
    return T.UiRenderScene.OccurrenceState(clips or L {}, T.UiCore.BlendNormal(), opacity or 1.0, transform)
end

local function clip_rect_shape(x, y, w, h)
    return T.UiCore.ClipRect(rect(x, y, w, h))
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

local function box_occurrence(i, col, row, stroked, clipped)
    return T.UiRenderScene.Box(
        T.UiRenderScene.BoxOccurrence(
            occurrence_state(
                clipped and L { clip_rect_shape(40, 40, 520, 320) } or L {},
                1.0,
                nil
            ),
            rect(16 + col * 18, 16 + row * 18, 12, 12),
            solid(0.12 + (i % 7) * 0.07, 0.18 + (i % 5) * 0.09, 0.30 + (i % 3) * 0.11, 0.88),
            stroked and solid(0.95, 0.95, 0.98, 0.35) or nil,
            stroked and 1 or 0,
            T.UiCore.CenterStroke(),
            zero_corners()
        )
    )
end

local function text_occurrence()
    return T.UiRenderScene.Text(
        T.UiRenderScene.TextOccurrence(
            occurrence_state(L {}, 1.0, T.UiCore.Transform2D(1, 0, 0, 1, 0, 0)),
            T.UiRenderFacts.TextContent(
                T.UiCore.TextValue("ui3 layer2 text benchmark"),
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
            ),
            rect(620, 90, 320, 80)
        )
    )
end

local function image_occurrence()
    return T.UiRenderScene.Image(
        T.UiRenderScene.ImageOccurrence(
            occurrence_state(L {}, 1.0, nil),
            T.UiRenderFacts.ImageContent(
                image_ref(2),
                T.UiCore.StretchImage(),
                T.UiCore.Linear()
            ),
            rect(620, 190, 180, 120),
            rounded(16)
        )
    )
end

local function shadow_occurrence()
    return T.UiRenderScene.Shadow(
        T.UiRenderScene.ShadowOccurrence(
            occurrence_state(L {}, 1.0, nil),
            rect(620, 80, 180, 120),
            solid(0.0, 0.0, 0.0, 0.30),
            8,
            0,
            0,
            4,
            T.UiCore.DropShadow(),
            rounded(12)
        )
    )
end

local function box_occurrences(box_count, stroked, clipped)
    local occurrences = {}
    local cols = math.max(1, math.floor(math.sqrt(math.max(1, box_count))))
    for i = 0, box_count - 1 do
        local col = i % cols
        local row = math.floor(i / cols)
        occurrences[#occurrences + 1] = box_occurrence(i, col, row, stroked, clipped)
    end
    return occurrences
end

local function build_render_scene_with(label, root_id, box_count, extras, stroked, clipped)
    local occurrences = box_occurrences(box_count, stroked, clipped)
    for i = 1, #extras do
        occurrences[#occurrences + 1] = extras[i]
    end

    return T.UiRenderScene.Scene(
        L {
            T.UiRenderScene.Region(
                T.UiFlatShape.RegionHeader(T.UiCore.ElementId(root_id), label, 0),
                0,
                0,
                #occurrences
            )
        },
        L(occurrences)
    )
end

local function build_box_only_render_scene(box_count)
    return build_render_scene_with("boxes", 8001, box_count, {}, false, false)
end

local function build_box_styled_render_scene(box_count)
    return build_render_scene_with("boxstyled", 8006, box_count, {}, true, true)
end

local function build_box_shadow_render_scene(box_count)
    return build_render_scene_with("boxshadow", 8003, box_count, { shadow_occurrence() }, true, true)
end

local function build_box_text_render_scene(box_count)
    return build_render_scene_with("boxtext", 8004, box_count, { text_occurrence() }, true, true)
end

local function build_box_image_render_scene(box_count)
    return build_render_scene_with("boximage", 8005, box_count, { image_occurrence() }, true, true)
end

local function build_mixed_render_scene(box_count)
    return build_render_scene_with("mixed", 8002, box_count, {
        shadow_occurrence(),
        text_occurrence(),
        image_occurrence(),
    }, true, true)
end

local function ensure_unit_state(unit)
    if unit.state_t == U.EMPTY then return nil end
    if unit.__state == nil then
        unit.__state = terralib.new(unit.state_t)
        if unit.init then unit.init(unit.__state) end
    end
    return unit.__state
end

local width = getenv_number("UI3_LAYER2_WIDTH", 1280)
local height = getenv_number("UI3_LAYER2_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_LAYER2_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_LAYER2_ITERS", 60)))
local box_count = math.max(0, math.floor(getenv_number("UI3_LAYER2_BOXES", 1000)))
local scenario = os.getenv("UI3_LAYER2_SCENARIO") or "mixed"
local assets = build_assets()

local build_render_scene = ({
    boxes = build_box_only_render_scene,
    boxstyled = build_box_styled_render_scene,
    boxshadow = build_box_shadow_render_scene,
    boxtext = build_box_text_render_scene,
    boximage = build_box_image_render_scene,
    mixed = build_mixed_render_scene,
})[scenario] or build_mixed_render_scene

local render_scene = build_render_scene(box_count)

local build_scene_avg_ms = bench_avg_ms(iters, function()
    build_render_scene(box_count)
end)

local schedule_t0 = now_ns()
local render_ir = render_scene:schedule_render_machine_ir()
local schedule_ms = ms_between(schedule_t0, now_ns())

local schedule_existing_scene_avg_ms = bench_avg_ms(iters, function()
    render_scene:schedule_render_machine_ir()
end)

local build_plus_schedule_avg_ms = bench_avg_ms(iters, function()
    build_render_scene(box_count):schedule_render_machine_ir()
end)

local define_t0 = now_ns()
local machine = render_ir:define_machine()
local define_ms = ms_between(define_t0, now_ns())

local runtime = Backend.init_window("ui3-layer2", width, height)
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

print(("ui3 layer2 backend=terra scenario=%s width=%d height=%d warmup=%d iters=%d boxes=%d")
    :format(scenario, width, height, warmup, iters, box_count))
print(("  build_scene_avg_ms:    %.3f"):format(build_scene_avg_ms))
print(("  schedule_ms:           %.3f"):format(schedule_ms))
print(("  schedule_existing_scene_avg_ms: %.3f"):format(schedule_existing_scene_avg_ms))
print(("  build_plus_schedule_avg_ms:  %.3f"):format(build_plus_schedule_avg_ms))
print(("  define_machine_ms:     %.3f"):format(define_ms))
print(("  compile_ms:            %.3f"):format(compile_ms))
print(("  materialize_ms:        %.3f"):format(materialize_ms))
print(("  steady_rematerialize_ms: %.3f"):format(steady_rematerialize_ms))
print(("  first_render_ms:       %.3f"):format(first_render_ms))
print(("  steady_render_ms:      %.3f"):format(steady_render_ms))

Backend.shutdown_window(runtime)
