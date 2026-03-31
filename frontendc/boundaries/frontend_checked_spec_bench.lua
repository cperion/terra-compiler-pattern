local ffi = require("ffi")
local Fixture = require("frontendc.frontend_machine_fixture")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } frontendc_bench_timespec_t;
    int clock_gettime(int clk_id, frontendc_bench_timespec_t *tp);
]]

local ts = ffi.new("frontendc_bench_timespec_t")
local CLOCK_MONOTONIC = 1

local function now_s()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function bench_avg_ms(iters, fn)
    local warm = math.min(iters, 50)
    local sink = 0
    for i = 1, warm do sink = sink + fn(i) end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do sink = sink + fn(i) end
    local t1 = now_s()
    return ((t1 - t0) * 1000) / iters, sink
end

return function(T, U, P)
    local benches = {}

    function benches.bench_lower()
        local pool_size = 256
        local iters = 1000
        local pool = {}
        for i = 1, pool_size do
            local source = select(1, Fixture.new_source_spec_and_target_ctx(T))
            pool[i] = source:check()
        end

        local avg_ms = bench_avg_ms(iters, function(i)
            local lowered = pool[((i - 1) % pool_size) + 1]:lower()
            return #lowered.parse.rules + #lowered.tokenize.fixed_dispatches + #lowered.tokenize.ident_dispatches
        end)

        print(string.format(
            "frontendc lower bench iters=%d pool=%d avg_ms=%.6f",
            iters,
            pool_size,
            avg_ms
        ))
    end

    return benches
end
