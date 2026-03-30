#!/usr/bin/env luajit

local ffi = require("ffi")
local Fixture = require("asdl2.asdl2_bench_fixture")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } asdl2_install_timespec_t;
    int clock_gettime(int clk_id, asdl2_install_timespec_t *tp);
]]

local ts = ffi.new("asdl2_install_timespec_t")
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
    local warm = math.min(iters, 50)
    for i = 1, warm do fn(i) end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do fn(i) end
    local t1 = now_s()
    return ((t1 - t0) * 1000) / iters
end

local scenario = os.getenv("ASDL2_INSTALL_SCENARIO") or "mixed"
local iters = math.max(1, math.floor(getenv_number("ASDL2_INSTALL_ITERS", 20)))
local products = math.max(1, math.floor(getenv_number("ASDL2_INSTALL_PRODUCTS", 50)))
local fields = math.max(1, math.floor(getenv_number("ASDL2_INSTALL_FIELDS", 6)))
local variants = math.max(1, math.floor(getenv_number("ASDL2_INSTALL_VARIANTS", 4)))

if scenario == "small" then
    products, fields, variants = 8, 3, 3
elseif scenario == "wide" then
    fields, variants = 12, 8
end

local base_luajit = Fixture.build_luajit(1, products, fields, variants)
local base_ctx = Fixture.new_ctx()
assert(base_luajit:install(base_ctx) ~= nil)

local install_existing_ms = bench_avg_ms(iters, function()
    base_luajit:install(base_ctx)
end)

local pool = {}
local ctx_pool = {}
for i = 1, iters + 64 do
    pool[i] = Fixture.build_luajit(i + 1000, products, fields, variants)
    ctx_pool[i] = Fixture.new_ctx()
end

local install_distinct_ms = bench_avg_ms(iters, function(i)
    local ctx = pool[i]:install(ctx_pool[i])
    return ctx ~= nil and 1 or 0
end)

local build_luajit_ms = bench_avg_ms(iters, function(i)
    Fixture.build_luajit(i + 2000, products, fields, variants)
end)

local build_plus_install_ms = bench_avg_ms(iters, function(i)
    Fixture.build_luajit(i + 3000, products, fields, variants):install(Fixture.new_ctx())
end)

print(string.format(
    "asdl2 install bench iters=%d scenario=%s products=%d fields=%d variants=%d",
    iters,
    scenario,
    products,
    fields,
    variants
))
print(string.format("install_existing_avg_ms: %.3f", install_existing_ms))
print(string.format("install_distinct_avg_ms: %.3f", install_distinct_ms))
print(string.format("build_luajit_avg_ms: %.3f", build_luajit_ms))
print(string.format("build_plus_install_avg_ms: %.3f", build_plus_install_ms))
