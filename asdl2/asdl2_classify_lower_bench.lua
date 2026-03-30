#!/usr/bin/env luajit

local ffi = require("ffi")
local Fixture = require("asdl2.asdl2_source_fixture")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } asdl2_classify_lower_timespec_t;
    int clock_gettime(int clk_id, asdl2_classify_lower_timespec_t *tp);
]]

local ts = ffi.new("asdl2_classify_lower_timespec_t")
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

local scenario = os.getenv("ASDL2_CLASSIFY_LOWER_SCENARIO") or "mixed"
local iters = math.max(1, math.floor(getenv_number("ASDL2_CLASSIFY_LOWER_ITERS", 40)))
local types = math.max(1, math.floor(getenv_number("ASDL2_CLASSIFY_LOWER_TYPES", 500)))
local fields = math.max(0, math.floor(getenv_number("ASDL2_CLASSIFY_LOWER_FIELDS", 6)))
local variants = math.max(1, math.floor(getenv_number("ASDL2_CLASSIFY_LOWER_VARIANTS", 4)))

if scenario == "small" then
    types, fields, variants = 64, 3, 3
elseif scenario == "wide" then
    fields, variants = 12, 8
end

local base = Fixture.build_source(1, types, fields, variants):catalog()
local lowered = base:classify_lower()
assert(lowered.records[1] ~= nil)

local classify_existing_ms = bench_avg_ms(iters, function()
    base:classify_lower()
end)

local distinct_pool = {}
for i = 1, iters + 128 do
    distinct_pool[i] = Fixture.build_source(i + 5000, types, fields, variants):catalog()
end

local classify_distinct_ms = bench_avg_ms(iters, function(i)
    return distinct_pool[i]:classify_lower().records[1].header.class_id
end)

local build_catalog_ms = bench_avg_ms(iters, function(i)
    return Fixture.build_source(i + 1000, types, fields, variants):catalog()
end)

local build_plus_lower_ms = bench_avg_ms(iters, function(i)
    Fixture.build_source(i + 2000, types, fields, variants):catalog():classify_lower()
end)

print(string.format(
    "asdl2 classify_lower bench iters=%d scenario=%s types=%d fields=%d variants=%d",
    iters,
    scenario,
    types,
    fields,
    variants
))
print(string.format("classify_existing_catalog_avg_ms: %.3f", classify_existing_ms))
print(string.format("classify_distinct_catalog_avg_ms: %.3f", classify_distinct_ms))
print(string.format("build_catalog_avg_ms: %.3f", build_catalog_ms))
print(string.format("build_plus_lower_avg_ms: %.3f", build_plus_lower_ms))
