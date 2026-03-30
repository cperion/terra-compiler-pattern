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

local function font_ref(n)
    return T.UiCore.FontRef(n)
end

local function image_ref(n)
    return T.UiCore.ImageRef(n)
end

local function blend_normal_state(clip, opacity, transform)
    return T.UiRenderMachineIR.DrawState(clip, T.UiCore.BlendNormal(), opacity, transform)
end

local function text_ref(slot)
    return T.UiRenderMachineIR.TextResourceRef(slot)
end

local function image_resource_ref(slot)
    return T.UiRenderMachineIR.ImageResourceRef(slot)
end

local function clip_ref(index)
    return T.UiRenderMachineIR.ClipRef(index)
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

local function build_box_only_render_ir(box_count)
    local boxes = {}
    local cols = math.max(1, math.floor(math.sqrt(math.max(1, box_count))))
    for i = 0, box_count - 1 do
        local col = i % cols
        local row = math.floor(i / cols)
        boxes[#boxes + 1] = T.UiRenderMachineIR.BoxInstance(
            rect(16 + col * 18, 16 + row * 18, 12, 12),
            solid(0.15 + (i % 7) * 0.09, 0.25 + (i % 5) * 0.11, 0.35 + (i % 3) * 0.14, 0.90),
            nil,
            0,
            T.UiCore.CenterStroke(),
            zero_corners()
        )
    end

    return T.UiRenderMachineIR.Render(
        T.UiRenderMachineIR.Shape(L {}),
        T.UiRenderMachineIR.Input(
            L { T.UiRenderMachineIR.RegionSpan(0, box_count > 0 and 1 or 0) },
            L {},
            box_count > 0 and L {
                T.UiRenderMachineIR.BatchHeader(
                    T.UiRenderMachineIR.BoxKind(),
                    blend_normal_state(nil, 1.0, nil),
                    0,
                    box_count
                )
            } or L {},
            L {},
            L {},
            L {},
            L(boxes),
            L {},
            L {},
            L {},
            L {}
        ),
        T.UiRenderMachineIR.StateSchema(L {}, L {}, T.UiRenderMachineIR.CapacityTracking())
    )
end

local function build_mixed_render_ir(box_count)
    local boxes = {}
    local cols = math.max(1, math.floor(math.sqrt(math.max(1, box_count))))
    for i = 0, box_count - 1 do
        local col = i % cols
        local row = math.floor(i / cols)
        boxes[#boxes + 1] = T.UiRenderMachineIR.BoxInstance(
            rect(16 + col * 18, 16 + row * 18, 12, 12),
            solid(0.12 + (i % 7) * 0.07, 0.18 + (i % 5) * 0.09, 0.30 + (i % 3) * 0.11, 0.88),
            solid(0.95, 0.95, 0.98, 0.35),
            1,
            T.UiCore.CenterStroke(),
            zero_corners()
        )
    end

    local clips = L {
        T.UiRenderMachineIR.ClipPath(L {
            T.UiCore.ClipRect(rect(40, 40, 520, 320))
        })
    }

    local text_resources = L {
        T.UiRenderMachineIR.TextResourceSpec(
            1001,
            T.UiCore.TextValue("ui3 layer1 text benchmark"),
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
            2,
            320
        )
    }

    local image_resources = L {
        T.UiRenderMachineIR.ImageResourceSpec(2001, image_ref(2), T.UiCore.Linear())
    }

    local shadows = L {
        T.UiRenderMachineIR.ShadowInstance(
            rect(620, 80, 180, 120),
            solid(0.0, 0.0, 0.0, 0.30),
            8,
            0,
            0,
            4,
            T.UiCore.DropShadow(),
            T.UiCore.Corners(12, 12, 12, 12)
        )
    }

    local texts = L {
        T.UiRenderMachineIR.TextDrawInstance(
            text_ref(0),
            rect(620, 90, 320, 80)
        )
    }

    local images = L {
        T.UiRenderMachineIR.ImageDrawInstance(
            image_resource_ref(0),
            rect(620, 190, 180, 120),
            T.UiCore.StretchImage(),
            T.UiCore.Corners(16, 16, 16, 16)
        )
    }

    local batches = L {
        T.UiRenderMachineIR.BatchHeader(T.UiRenderMachineIR.BoxKind(), blend_normal_state(clip_ref(0), 1.0, nil), 0, box_count),
        T.UiRenderMachineIR.BatchHeader(T.UiRenderMachineIR.ShadowKind(), blend_normal_state(nil, 1.0, nil), 0, 1),
        T.UiRenderMachineIR.BatchHeader(T.UiRenderMachineIR.TextKind(), blend_normal_state(nil, 1.0, T.UiCore.Transform2D(1, 0, 0, 1, 0, 0)), 0, 1),
        T.UiRenderMachineIR.BatchHeader(T.UiRenderMachineIR.ImageKind(), blend_normal_state(nil, 1.0, nil), 0, 1)
    }

    return T.UiRenderMachineIR.Render(
        T.UiRenderMachineIR.Shape(L {}),
        T.UiRenderMachineIR.Input(
            L { T.UiRenderMachineIR.RegionSpan(0, 4) },
            clips,
            batches,
            text_resources,
            image_resources,
            L {},
            L(boxes),
            shadows,
            texts,
            images,
            L {}
        ),
        T.UiRenderMachineIR.StateSchema(
            L { T.UiRenderMachineIR.TextResources(), T.UiRenderMachineIR.ImageResources() },
            L {},
            T.UiRenderMachineIR.CapacityTracking()
        )
    )
end

local function ensure_unit_state(unit)
    if unit.state_t == U.EMPTY then return nil end
    if unit.__state == nil then
        unit.__state = terralib.new(unit.state_t)
        if unit.init then unit.init(unit.__state) end
    end
    return unit.__state
end

local width = getenv_number("UI3_LAYER1_WIDTH", 1280)
local height = getenv_number("UI3_LAYER1_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_LAYER1_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_LAYER1_ITERS", 60)))
local box_count = math.max(0, math.floor(getenv_number("UI3_LAYER1_BOXES", 1000)))
local scenario = os.getenv("UI3_LAYER1_SCENARIO") or "mixed"
local assets = build_assets()

local render_ir = scenario == "boxes"
    and build_box_only_render_ir(box_count)
    or build_mixed_render_ir(box_count)

local define_t0 = now_ns()
local machine = render_ir:define_machine()
local define_ms = ms_between(define_t0, now_ns())

local runtime = Backend.init_window("ui3-layer1", width, height)
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

print(("ui3 layer1 backend=terra scenario=%s width=%d height=%d warmup=%d iters=%d boxes=%d")
    :format(scenario, width, height, warmup, iters, box_count))
print(("  define_machine_ms:     %.3f"):format(define_ms))
print(("  compile_ms:            %.3f"):format(compile_ms))
print(("  materialize_ms:        %.3f"):format(materialize_ms))
print(("  steady_rematerialize_ms: %.3f"):format(steady_rematerialize_ms))
print(("  first_render_ms:       %.3f"):format(first_render_ms))
print(("  steady_render_ms:      %.3f"):format(steady_render_ms))

Backend.shutdown_window(runtime)
