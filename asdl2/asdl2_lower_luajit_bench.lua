#!/usr/bin/env luajit

local ffi = require("ffi")
local Fixture = require("asdl2.asdl2_bench_fixture")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } asdl2_lower_luajit_timespec_t;
    int clock_gettime(int clk_id, asdl2_lower_luajit_timespec_t *tp);
]]

local ts = ffi.new("asdl2_lower_luajit_timespec_t")
local CLOCK_MONOTONIC = 1

local function now_s()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function getenv_number(name, default)
    local v = os.getenv(name)
    if not v or v == "" then return default end
    local n = tonumber(v)
    if n == nil then return default end
    return n
end

local function bench_avg_ms(iters, fn)
    local warm = math.min(iters, 100)
    for i = 1, warm do fn(i) end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do fn(i) end
    local t1 = now_s()
    return ((t1 - t0) * 1000) / iters
end

local scenario = os.getenv("ASDL2_LOWER_LUAJIT_SCENARIO") or "mixed"
local iters = math.max(1, math.floor(getenv_number("ASDL2_LOWER_LUAJIT_ITERS", 50)))
local records = math.max(1, math.floor(getenv_number("ASDL2_LOWER_LUAJIT_RECORDS", 1000)))
local fields = math.max(0, math.floor(getenv_number("ASDL2_LOWER_LUAJIT_FIELDS", 6)))
local variants = math.max(1, math.floor(getenv_number("ASDL2_LOWER_LUAJIT_VARIANTS", 4)))

if scenario == "small" then
    records, fields, variants = 64, 3, 3
elseif scenario == "wide" then
    fields, variants = 12, 8
end

local base = Fixture.build_machine(1, records, fields, variants)
assert(base:lower_luajit().records[1] ~= nil)

local lower_existing_ms = bench_avg_ms(iters, function()
    base:lower_luajit()
end)

local distinct_pool = {}
for i = 1, iters + 128 do
    distinct_pool[i] = Fixture.build_machine(i + 5000, records, fields, variants)
end

local lower_distinct_ms = bench_avg_ms(iters, function(i)
    return distinct_pool[i]:lower_luajit().records[1].header.class_id
end)

local build_machine_ms = bench_avg_ms(iters, function(i)
    Fixture.build_machine(i + 1000, records, fields, variants)
end)

local build_plus_lower_ms = bench_avg_ms(iters, function(i)
    Fixture.build_machine(i + 2000, records, fields, variants):lower_luajit()
end)

print(string.format(
    "asdl2 lower_luajit bench iters=%d scenario=%s records=%d fields=%d variants=%d",
    iters,
    scenario,
    records,
    fields,
    variants
))
print(string.format("lower_existing_machine_avg_ms: %.3f", lower_existing_ms))
print(string.format("lower_distinct_machine_avg_ms: %.3f", lower_distinct_ms))
print(string.format("build_machine_avg_ms: %.3f", build_machine_ms))
print(string.format("build_plus_lower_luajit_avg_ms: %.3f", build_plus_lower_ms))
