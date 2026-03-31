local ffi = require("ffi")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } frontendc_profile_timespec_t;
    int clock_gettime(int clk_id, frontendc_profile_timespec_t *tp);
]]

local ts = ffi.new("frontendc_profile_timespec_t")
local CLOCK_MONOTONIC = 1

local M = {}

local function now_s()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

function M.profile_run(iters, fn)
    local sink = 0
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do sink = sink + fn(i) end
    local t1 = now_s()
    return {
        iters = iters,
        total_s = t1 - t0,
        avg_ms = ((t1 - t0) * 1000) / iters,
        sink = sink,
    }
end

function M.print_summary(label, info)
    print(string.format(
        "%s profile iters=%d total_s=%.6f avg_ms=%.6f sink=%d",
        label,
        info.iters,
        info.total_s,
        info.avg_ms,
        info.sink
    ))
end

return M
