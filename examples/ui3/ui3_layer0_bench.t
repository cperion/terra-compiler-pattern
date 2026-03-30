local Backend = require("examples.ui.backends.terra_sdl_gl")
local Layer0 = require("examples.ui3.backends.terra_layer0_unit")

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

local function render_once(runtime, unit)
    Backend.render_unit(runtime, unit)
end

local function reset_runtime_unit(runtime)
    if runtime.current_unit then
        Backend.release_unit(runtime.current_unit)
        runtime.current_unit = nil
    end
end

local width = getenv_number("UI3_LAYER0_WIDTH", 1280)
local height = getenv_number("UI3_LAYER0_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_LAYER0_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_LAYER0_ITERS", 60)))
local box_count = math.max(0, math.floor(getenv_number("UI3_LAYER0_BOXES", 1000)))

local runtime = Backend.init_window("ui3-layer0", width, height)
Backend.FFI.SDL_GL_SetSwapInterval(0)

local clear_compile_t0 = now_ns()
local clear_unit = Layer0.new_clear_unit(Backend)
local clear_compile_ms = ms_between(clear_compile_t0, now_ns())

local box_compile_t0 = now_ns()
local box_unit = Layer0.new_box_unit(Backend, box_count)
local box_compile_ms = ms_between(box_compile_t0, now_ns())

for _ = 1, warmup do
    render_once(runtime, clear_unit)
end
reset_runtime_unit(runtime)
for _ = 1, warmup do
    render_once(runtime, box_unit)
end
reset_runtime_unit(runtime)

local clear_first_t0 = now_ns()
render_once(runtime, clear_unit)
local clear_first_ms = ms_between(clear_first_t0, now_ns())
local clear_steady_ms = bench_avg_ms(iters, function()
    render_once(runtime, clear_unit)
end)

reset_runtime_unit(runtime)

local box_first_t0 = now_ns()
render_once(runtime, box_unit)
local box_first_ms = ms_between(box_first_t0, now_ns())
local box_steady_ms = bench_avg_ms(iters, function()
    render_once(runtime, box_unit)
end)

print(("ui3 layer0 backend=terra width=%d height=%d warmup=%d iters=%d boxes=%d")
    :format(width, height, warmup, iters, box_count))
print(("  compile_clear_ms:      %.3f"):format(clear_compile_ms))
print(("  compile_boxes_ms:      %.3f"):format(box_compile_ms))
print(("  first_render_clear_ms: %.3f"):format(clear_first_ms))
print(("  steady_render_clear_ms: %.3f"):format(clear_steady_ms))
print(("  first_render_boxes_ms: %.3f"):format(box_first_ms))
print(("  steady_render_boxes_ms: %.3f"):format(box_steady_ms))

Backend.shutdown_window(runtime)
