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

local function size(w, h)
    return T.UiCore.Size(w, h)
end

local function rect(x, y, w, h)
    return T.UiCore.Rect(x, y, w, h)
end

local function point(x, y)
    return T.UiCore.Point(x, y)
end

local function query_scene(node_count)
    local hits = {}
    local focus = {}
    local focus_order = {}
    local key_routes = {}
    local accessibility = {}
    local cols = math.max(1, math.floor(math.sqrt(math.max(1, node_count))))
    local i = 0
    while i < node_count do
        local id = T.UiCore.ElementId(300000 + i)
        local semantic = T.UiCore.SemanticRef(12, 300000 + i)
        local col = i % cols
        local row = math.floor(i / cols)
        local r = rect(16 + col * 18, 16 + row * 18, 12, 12)
        local pointer = (i % 3 == 0)
            and L { T.UiQueryMachineIR.HoverBinding(nil, T.UiCore.CommandRef(1000 + i), T.UiCore.CommandRef(2000 + i)) }
            or L { T.UiQueryMachineIR.PressBinding(C(T.UiCore.Primary), 1, T.UiCore.CommandRef(3000 + i)) }
        hits[#hits + 1] = T.UiQueryMachineIR.HitInstance(
            id,
            semantic,
            T.UiCore.HitRect(r),
            0,
            pointer,
            (i % 5 == 0) and T.UiQueryMachineIR.ScrollBinding(C(T.UiCore.Vertical), T.UiCore.ScrollRef(4000 + i)) or nil,
            L {}
        )
        if i % 2 == 0 then
            focus[#focus + 1] = T.UiQueryMachineIR.FocusInstance(id, semantic, r, C(T.UiCore.ClickFocus), i)
            focus_order[#focus_order + 1] = T.UiQueryMachineIR.FocusOrderEntry(#focus - 1)
            key_routes[#key_routes + 1] = T.UiQueryMachineIR.KeyRouteInstance(id, T.UiCore.CommandRef(5000 + i))
            accessibility[#accessibility + 1] = T.UiQueryMachineIR.AccessibilityInstance(id, semantic, C(T.UiCore.AccButton), "btn", nil, r, i)
        end
        i = i + 1
    end

    local edit_hosts = L {
        T.UiQueryMachineIR.EditHostInstance(T.UiCore.ElementId(399999), T.UiCore.SemanticRef(12, 399999), T.UiCore.TextModelRef(6000), rect(0, 0, 120, 20), false, false, T.UiCore.CommandRef(6001))
    }

    local regions = L {
        T.UiQueryMachineIR.RegionHeader(
            T.UiCore.ElementId(200000),
            "root",
            0,
            false,
            false,
            0,
            #hits,
            0,
            #focus,
            0,
            #focus_order,
            0,
            2,
            0,
            0,
            0,
            #edit_hosts,
            0,
            #accessibility
        )
    }

    local key_buckets = L {
        T.UiQueryMachineIR.KeyRouteBucket(
            T.UiCore.KeyChord(false, false, false, false, 13),
            C(T.UiCore.KeyDown),
            C(T.UiQueryMachineIR.FocusScope),
            0,
            #key_routes
        ),
        T.UiQueryMachineIR.KeyRouteBucket(
            T.UiCore.KeyChord(false, false, false, false, 27),
            C(T.UiCore.KeyDown),
            C(T.UiQueryMachineIR.GlobalScope),
            #key_routes,
            1
        )
    }

    local all_key_routes = {}
    local j = 1
    while j <= #key_routes do
        all_key_routes[#all_key_routes + 1] = key_routes[j]
        j = j + 1
    end
    all_key_routes[#all_key_routes + 1] = T.UiQueryMachineIR.KeyRouteInstance(T.UiCore.ElementId(1), T.UiCore.CommandRef(7000))

    return T.UiQueryMachineIR.Scene(
        T.UiQueryMachineIR.Input(
            regions,
            L(hits),
            L(focus),
            L(focus_order),
            key_buckets,
            L(all_key_routes),
            L {},
            edit_hosts,
            L(accessibility)
        )
    )
end

local width = getenv_number("UI3_APPLY_WIDTH", 1280)
local height = getenv_number("UI3_APPLY_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_APPLY_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_APPLY_ITERS", 1000)))
local node_count = math.max(1, math.floor(getenv_number("UI3_APPLY_NODES", 1000)))

local query_ir = query_scene(node_count)
local initial = T.UiSession.State.initial(size(width, height))
local focused = T.UiSession.State(
    initial.viewport,
    initial.pointer,
    initial.pointer_in_bounds,
    initial.window_focused,
    initial.pressed,
    initial.hovered,
    T.UiCore.ElementId(399999),
    initial.captured,
    initial.drag
)

local hover_event = T.UiInput.PointerMoved(point(16, 16))
local press_event = T.UiInput.PointerPressed(point(16, 16), C(T.UiCore.Primary))
local wheel_event = T.UiInput.WheelScrolled(point(16, 16), 0, -30)
local key_event = T.UiInput.KeyChanged(C(T.UiCore.KeyDown), T.UiCore.KeyChord(false, false, false, false, 27))
local text_event = T.UiInput.TextEntered("hello")
local tab_event = T.UiInput.KeyChanged(C(T.UiCore.KeyDown), T.UiCore.KeyChord(false, false, false, false, 9))

for _ = 1, warmup do
    initial:apply_with_intents(query_ir, hover_event)
    initial:apply_with_intents(query_ir, press_event)
    initial:apply_with_intents(query_ir, wheel_event)
    focused:apply_with_intents(query_ir, key_event)
    focused:apply_with_intents(query_ir, text_event)
    initial:apply_with_intents(query_ir, tab_event)
end

local hover_ms = bench_avg_ms(iters, function()
    initial:apply_with_intents(query_ir, hover_event)
end)

local press_ms = bench_avg_ms(iters, function()
    initial:apply_with_intents(query_ir, press_event)
end)

local wheel_ms = bench_avg_ms(iters, function()
    initial:apply_with_intents(query_ir, wheel_event)
end)

local key_ms = bench_avg_ms(iters, function()
    focused:apply_with_intents(query_ir, key_event)
end)

local text_ms = bench_avg_ms(iters, function()
    focused:apply_with_intents(query_ir, text_event)
end)

local tab_ms = bench_avg_ms(iters, function()
    initial:apply_with_intents(query_ir, tab_event)
end)

print(string.format(
    "ui3 apply bench width=%d height=%d warmup=%d iters=%d nodes=%d",
    width,
    height,
    warmup,
    iters,
    node_count
))
print(string.format("  hover_apply_with_intents_avg_ms: %.6f", hover_ms))
print(string.format("  press_apply_with_intents_avg_ms: %.6f", press_ms))
print(string.format("  wheel_apply_with_intents_avg_ms: %.6f", wheel_ms))
print(string.format("  key_apply_with_intents_avg_ms: %.6f", key_ms))
print(string.format("  text_apply_with_intents_avg_ms: %.6f", text_ms))
print(string.format("  tab_apply_with_intents_avg_ms: %.6f", tab_ms))
print(string.format("  hits: %d", #query_ir.input.hits))
print(string.format("  focus: %d", #query_ir.input.focus))
print(string.format("  focus_order: %d", #query_ir.input.focus_order))
print(string.format("  key_buckets: %d", #query_ir.input.key_buckets))
print(string.format("  key_routes: %d", #query_ir.input.key_routes))
