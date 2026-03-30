local has_ffi, ffi = pcall(require, "ffi")
if not has_ffi then
    error("bench/unit_report_bench.lua requires LuaJIT FFI")
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
local MEMOS = tonumber(os.getenv("UNIT_REPORT_BENCH_MEMOS") or "96")
local ARITY = tonumber(os.getenv("UNIT_REPORT_BENCH_ARITY") or "4")
local WARMUP = tonumber(os.getenv("UNIT_REPORT_BENCH_WARMUP") or "20")
local ITERS = tonumber(os.getenv("UNIT_REPORT_BENCH_ITERS") or "200")
local CALLS = tonumber(os.getenv("UNIT_REPORT_BENCH_CALLS") or "800")

local memoized = {}
for i = 1, MEMOS do
    memoized[i] = U.transition("bench.memo." .. tostring(i), function(a, b, c, d)
        return (a or 0) + (b or 0) * 3 + (c or 0) * 5 + (d or 0) * 7 + i
    end)
end

local function drive_calls(pass)
    local sink = 0
    for i = 1, MEMOS do
        local fn = memoized[i]
        for j = 1, CALLS do
            local a = (j + i + pass) % 19
            local b = (j * 2 + i) % 17
            local c = (j * 3 + pass) % 13
            local d = (j % 4 == 0) and ((j + pass) % 11) or ((j + i) % 7)
            if ARITY == 1 then
                sink = sink + fn(a)
            elseif ARITY == 2 then
                sink = sink + fn(a, b)
            elseif ARITY == 3 then
                sink = sink + fn(a, b, c)
            else
                sink = sink + fn(a, b, c, d)
            end
        end
    end
    return sink
end

local function prepare()
    U.memo_reset()
    local sink = 0
    sink = sink + drive_calls(1)
    sink = sink + drive_calls(1)
    sink = sink + drive_calls(2)
    sink = sink + drive_calls(2)
    return sink
end

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

local prep_sink = prepare()
local memo = U.memo()
print(string.format(
    "unit report bench memos=%d arity=%d calls=%d warmup=%d iters=%d prep=%d tracked=%d",
    MEMOS, ARITY, CALLS, WARMUP, ITERS, prep_sink, #memo.stats()
))

bench("memo_report", function()
    return #U.memo_report()
end)

bench("memo_quality", function()
    return #U.memo_quality()
end)

bench("memo_diagnose", function()
    return #U.memo_diagnose()
end)

bench("memo_measure_edit", function()
    local text = U.memo_measure_edit("bench edit", function()
        drive_calls(3)
    end)
    return #text
end)
