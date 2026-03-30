local has_ffi, ffi = pcall(require, "ffi")
if not has_ffi then
    error("bench/unit_inspect_bench.lua requires LuaJIT FFI")
end

ffi.cdef[[
    typedef long time_t;
    typedef struct timespec { time_t tv_sec; long tv_nsec; } timespec;
    int clock_gettime(int clk_id, struct timespec *tp);
]]

local CLOCK_MONOTONIC = 1
local ts = ffi.new("struct timespec[1]")

local function now_ns()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts[0].tv_sec) * 1000000000 + tonumber(ts[0].tv_nsec)
end

local U = require("unit_core").new()
require("unit_schema").install(U)
local asdl = require("asdl")

local PHASES = { "Editor", "Authored", "Resolved", "Scheduled" }
local TYPE_COUNT = tonumber(os.getenv("UNIT_INSPECT_BENCH_TYPES") or "24")
local LARGE_TYPE_COUNT = tonumber(os.getenv("UNIT_INSPECT_BENCH_LARGE_TYPES") or tostring(TYPE_COUNT * 4))
local PROMPT_DEPTH = tonumber(os.getenv("UNIT_INSPECT_BENCH_PROMPT_DEPTH") or "6")
local WARMUP = tonumber(os.getenv("UNIT_INSPECT_BENCH_WARMUP") or "20")
local ITERS = tonumber(os.getenv("UNIT_INSPECT_BENCH_ITERS") or "200")

local function phase_text(phase_name, type_count)
    local lines = {
        "module " .. phase_name .. " {",
        "  Choice = PickA(number value) | PickB(string label)",
        "  Root = (Choice choice, Node1 first, Node1* items) unique",
    }

    for i = 1, type_count do
        local prev = (i == 1) and "Choice" or ("Node" .. tostring(i - 1))
        lines[#lines + 1] = string.format(
            "  Node%d = (%s prev, %s* many, number score, string label) unique",
            i, prev, prev)
    end

    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

local function build_ctx()
    local ctx = asdl.NewContext()
    for _, phase_name in ipairs(PHASES) do
        ctx:Define(phase_text(phase_name, TYPE_COUNT))
    end

    U.install_stubs(ctx, {
        Editor = { "lower", "project" },
        Authored = { "resolve", "project" },
        Resolved = { "schedule", "compile" },
        Scheduled = { "compile", "emit" },
    })

    return ctx
end

local ctx = build_ctx()
local inspect0 = U.inspect(ctx, PHASES)
local prompt_target = PHASES[1] .. ".Node" .. tostring(math.max(2, math.floor(TYPE_COUNT / 2))) .. ":lower"
local scaffold_target = PHASES[2] .. ".Node" .. tostring(math.max(2, math.floor(TYPE_COUNT / 3))) .. ":resolve"

local function build_large_ctx()
    local ctx = asdl.NewContext()
    for _, phase_name in ipairs(PHASES) do
        ctx:Define(phase_text(phase_name, LARGE_TYPE_COUNT))
    end

    U.install_stubs(ctx, {
        Editor = { "lower", "project" },
        Authored = { "resolve", "project" },
        Resolved = { "schedule", "compile" },
        Scheduled = { "compile", "emit" },
    })

    return ctx
end

local large_ctx = build_large_ctx()
local large_inspect = U.inspect(large_ctx, PHASES)
local large_prompt_target = PHASES[1] .. ".Node" .. tostring(math.max(2, math.floor(LARGE_TYPE_COUNT / 2))) .. ":lower"

local function bench(name, fn)
    local sink = 0

    for _ = 1, WARMUP do
        sink = sink + fn()
    end

    collectgarbage()
    collectgarbage()

    local t0 = now_ns()
    for _ = 1, ITERS do
        sink = sink + fn()
    end
    local dt = now_ns() - t0

    print(string.format(
        "BENCH name=%s total_ms=%.3f iter_us=%.3f sink=%d",
        name,
        dt / 1e6,
        dt / ITERS / 1e3,
        sink
    ))
end

print(string.format(
    "unit inspect bench phases=%d types_per_phase=%d large_types_per_phase=%d prompt_depth=%d warmup=%d iters=%d",
    #PHASES, TYPE_COUNT, LARGE_TYPE_COUNT, PROMPT_DEPTH, WARMUP, ITERS
))
print(string.format(
    "inventory types=%d boundaries=%d prompt=%s scaffold=%s large_prompt=%s",
    #inspect0.types,
    #inspect0.boundaries,
    prompt_target,
    scaffold_target,
    large_prompt_target
))

bench("inspect_build", function()
    local I = U.inspect(ctx, PHASES)
    return #I.types + #I.boundaries
end)

local I = U.inspect(ctx, PHASES)

bench("inspect_status", function()
    return #I.status()
end)

bench("inspect_markdown", function()
    return #I.markdown()
end)

bench("inspect_markdown_large", function()
    return #large_inspect.markdown()
end)

bench("inspect_pipeline", function()
    return #I.pipeline()
end)

bench("inspect_prompt", function()
    return #I.prompt_for(prompt_target)
end)

bench("inspect_prompt_deep", function()
    return #large_inspect.prompt_for(large_prompt_target, PROMPT_DEPTH)
end)

bench("inspect_scaffold", function()
    local out = I.scaffold(scaffold_target)
    return out and #out or 0
end)
