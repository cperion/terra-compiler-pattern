local has_ffi, ffi = pcall(require, "ffi")
if not has_ffi then
    error("bench/unit_core_iter.lua requires LuaJIT FFI")
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

jit.opt.start("hotloop=1")

local U = require("unit_core").new()
local has_fun, F = pcall(require, "fun")

local N = tonumber(os.getenv("UNIT_ITER_BENCH_N") or "4096")
local WARMUP = tonumber(os.getenv("UNIT_ITER_BENCH_WARMUP") or "200")
local ITERS = tonumber(os.getenv("UNIT_ITER_BENCH_ITERS") or "4000")

local xs = {}
for i = 1, N do
    xs[i] = i
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
        "BENCH name=%s total_ms=%.3f iter_ns=%.1f elem_ns=%.3f sink=%d",
        name,
        dt / 1e6,
        dt / ITERS,
        dt / (ITERS * N),
        sink
    ))
end

local function sum_for()
    local acc = 0
    for i = 1, #xs do
        acc = acc + xs[i]
    end
    return acc
end

local function sum_u_each()
    local acc = 0
    U.each(xs, function(x)
        acc = acc + x
    end)
    return acc
end

local function sum_u_fold()
    return U.fold(xs, function(acc, x)
        return acc + x
    end, 0)
end

local function sum_rawiter_inline()
    local acc = 0
    local gen, param, state = U.rawiter(xs)
    while true do
        local x
        state, x = gen(param, state)
        if state == nil then break end
        acc = acc + x
    end
    return acc
end

local function fused_for_filter_map_reduce()
    local acc = 0
    for i = 1, #xs do
        local x = xs[i]
        if x % 2 == 0 then
            acc = acc + x * 2
        end
    end
    return acc
end

local function u_fold_fused()
    return U.fold(xs, function(acc, x)
        if x % 2 == 0 then
            return acc + x * 2
        end
        return acc
    end, 0)
end

print(string.format(
    "unit_core iterator bench n=%d warmup=%d iters=%d fun=%s",
    N, WARMUP, ITERS, has_fun and "yes" or "no"
))

bench("sum_for", sum_for)
bench("sum_u_each", sum_u_each)
bench("sum_u_fold", sum_u_fold)
bench("sum_rawiter_inline", sum_rawiter_inline)
print("---")
bench("fused_for_fmr", fused_for_filter_map_reduce)
bench("u_fold_fused", u_fold_fused)

if has_fun then
    local function sum_fun_each()
        local acc = 0
        F.iter(xs):each(function(x)
            acc = acc + x
        end)
        return acc
    end

    local function sum_fun_reduce()
        return F.iter(xs):reduce(function(acc, x)
            return acc + x
        end, 0)
    end

    local function fun_chain_fmr()
        return F.iter(xs)
            :filter(function(x) return x % 2 == 0 end)
            :map(function(x) return x * 2 end)
            :reduce(function(acc, x) return acc + x end, 0)
    end

    print("---")
    bench("sum_fun_each", sum_fun_each)
    bench("sum_fun_reduce", sum_fun_reduce)
    bench("fun_chain_fmr", fun_chain_fmr)
end
