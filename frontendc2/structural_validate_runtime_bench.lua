#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")
local U = require("unit_luajit")
local Runtime = require("frontendc2.structural_validate_runtime")
local Fixture = require("frontendc2.structural_validate_fixture")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } frontendc2_bench_timespec_t;
    int clock_gettime(int clk_id, frontendc2_bench_timespec_t *tp);
]]

local CLOCK_MONOTONIC = 1
local ts = ffi.new("frontendc2_bench_timespec_t")

local function now_s()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function bench_avg_ms(iters, fn)
    local warm = math.min(iters, 64)
    local sink = 0
    for i = 1, warm do sink = sink + fn(i) end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do sink = sink + fn(i) end
    local t1 = now_s()
    return ((t1 - t0) * 1000) / iters, sink
end

local spec = U.load_inspect_spec("frontendc2")
local T = spec.ctx

local function bench_skip_trivia()
    local text = (" \n\t  "):rep(32) .. "[1,2,3]"
    local len = #text
    local skip_plans = {
        { kind = "WhitespaceSkip" },
    }
    local iters = 100000
    local avg_ms = bench_avg_ms(iters, function()
        return Runtime.skip_trivia(skip_plans, text, len, 1) or 0
    end)
    print(string.format("frontendc2 skip_trivia bench iters=%d avg_ms=%.6f", iters, avg_ms))
end

local function bench_scan_number()
    local text = "-12345.6789e+12"
    local len = #text
    local fmt = T.FrontendSource.NumberFormat(true, true, true, false)
    local iters = 200000
    local avg_ms = bench_avg_ms(iters, function()
        return Runtime.scan_number(text, len, 1, fmt) or 0
    end)
    print(string.format("frontendc2 scan_number bench iters=%d avg_ms=%.6f", iters, avg_ms))
end

local function bench_scan_string()
    local text = [["hello \"world\"\nwith escapes"]]
    local len = #text
    local fmt = T.FrontendSource.StringFormat("\"", true, false)
    local iters = 200000
    local avg_ms = bench_avg_ms(iters, function()
        return Runtime.scan_quoted_string(text, len, 1, fmt) or 0
    end)
    print(string.format("frontendc2 scan_string bench iters=%d avg_ms=%.6f", iters, avg_ms))
end

local function bench_simple_validate()
    local machine_spec = Fixture.new_simple_machine(T)
    local runtime_machine = Runtime.compile_validate_machine(U, machine_spec.products[1].parse)
    local text = "[1,2,3,4,5,6,7,8,9,10]"
    local iters = 100000
    local avg_ms = bench_avg_ms(iters, function()
        local ok = U.machine_run(runtime_machine, nil, text)
        return ok and 1 or 0
    end)
    local mb_s = (#text / (1024 * 1024)) / (avg_ms / 1000)
    print(string.format(
        "frontendc2 simple_validate bench iters=%d bytes=%d avg_ms=%.6f throughput_mb_s=%.3f",
        iters,
        #text,
        avg_ms,
        mb_s
    ))
end

local function bench_json_validate()
    local machine_spec = Fixture.new_json_validate_machine(T)
    local runtime_machine = Runtime.compile_validate_machine(U, machine_spec.products[1].parse)

    local parts = { "{\n  \"items\": [\n" }
    for i = 1, 400 do
        parts[#parts + 1] = string.format(
            "    {\"id\": %d, \"name\": \"item%d\", \"ok\": true, \"value\": %d.25, \"tags\": [1,2,3], \"meta\": {\"x\": null}}%s\n",
            i, i, i * 17,
            i < 400 and "," or ""
        )
    end
    parts[#parts + 1] = "  ]\n}"
    local text = table.concat(parts)

    local iters = 2000
    local avg_ms = bench_avg_ms(iters, function()
        local ok = U.machine_run(runtime_machine, nil, text)
        return ok and 1 or 0
    end)
    local mb_s = (#text / (1024 * 1024)) / (avg_ms / 1000)
    print(string.format(
        "frontendc2 json_validate bench iters=%d bytes=%d avg_ms=%.6f throughput_mb_s=%.3f",
        iters,
        #text,
        avg_ms,
        mb_s
    ))
end

bench_skip_trivia()
bench_scan_number()
bench_scan_string()
bench_simple_validate()
bench_json_validate()
