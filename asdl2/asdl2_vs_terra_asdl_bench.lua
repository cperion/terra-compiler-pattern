#!/usr/bin/env luajit

local ffi = require("ffi")
local Schema = require("asdl2.asdl2_schema")
local Native = require("asdl2.asdl2_native_leaf_luajit")
local T = Schema.ctx

package.loaded["asdl"] = nil
assert(loadfile("terra/src/asdl.lua"))()
local TerraAsdl = assert(package.loaded["asdl"], "failed to load terra/src/asdl.lua")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } asdl2_vs_terra_timespec_t;
    int clock_gettime(int clk_id, asdl2_vs_terra_timespec_t *tp);
]]

local ts = ffi.new("asdl2_vs_terra_timespec_t")
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

local function bench_avg_ns(iters, fn)
    local warm = math.min(iters, 1000)
    local sink = 0
    for i = 1, warm do sink = sink + fn(i) end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do sink = sink + fn(i) end
    local t1 = now_s()
    return ((t1 - t0) * 1e9) / iters, sink
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

local function report_pair(label, unit, a, b)
    local ratio = (b ~= 0) and (a / b) or math.huge
    print(string.format("%-28s asdl2=%9.3f %s   terra=%9.3f %s   ratio=%.2fx", label .. ":", a, unit, b, unit, ratio))
end

local function module_name(seed)
    return "Bench" .. tostring(seed)
end

local function build_text(seed)
    local m = module_name(seed)
    return table.concat({
        "module " .. m .. " {",
        "Pn = (number x, number y)",
        "Pu = (number x, number y) unique",
        "Sn = An(number payload) | Bn(number payload)",
        "Su = Au(number payload) unique | Bu(number payload) unique",
        "}",
    }, "\n")
end

local function install_asdl2(text)
    return T.Asdl2Text.Spec(text)
        :parse()
        :catalog()
        :classify_lower()
        :define_machine()
        :install(Native.new_context())
end

local function install_terra(text)
    local ctx = TerraAsdl.NewContext()
    ctx:Define(text)
    return ctx
end

local install_iters = math.max(1, math.floor(getenv_number("ASDL2_VS_TERRA_INSTALL_ITERS", 20)))
local hot_iters = math.max(1, math.floor(getenv_number("ASDL2_VS_TERRA_HOT_ITERS", 2000000)))

local base_text = build_text(1)
local asdl2_ctx = install_asdl2(base_text)
local terra_ctx = install_terra(base_text)

local A2_Pn = asdl2_ctx.Bench1.Pn
local A2_Pu = asdl2_ctx.Bench1.Pu
local A2_An = asdl2_ctx.Bench1.An
local A2_Au = asdl2_ctx.Bench1.Au
local A2_Sn = asdl2_ctx.Bench1.Sn
local A2_plain = A2_Pn(1.5, 2.5)
local A2_sumv = A2_An(7.0)

local T_Pn = terra_ctx.Bench1.Pn
local T_Pu = terra_ctx.Bench1.Pu
local T_An = terra_ctx.Bench1.An
local T_Au = terra_ctx.Bench1.Au
local T_Sn = terra_ctx.Bench1.Sn
local T_plain = T_Pn(1.5, 2.5)
local T_sumv = T_An(7.0)

assert(A2_Pn:isclassof(A2_plain))
assert(A2_Sn:isclassof(A2_sumv))
assert(T_Pn:isclassof(T_plain))
assert(T_Sn:isclassof(T_sumv))

local asdl2_install_ms = bench_avg_ms(install_iters, function(i)
    return install_asdl2(build_text(i + 1000))[module_name(i + 1000)] ~= nil and 1 or 0
end)
local terra_install_ms = bench_avg_ms(install_iters, function(i)
    return install_terra(build_text(i + 1000))[module_name(i + 1000)] ~= nil and 1 or 0
end)

local a2_ctor_product_plain_ns = bench_avg_ns(hot_iters, function(i)
    return tonumber(A2_Pn(i, i + 1).x)
end)
local t_ctor_product_plain_ns = bench_avg_ns(hot_iters, function(i)
    return T_Pn(i, i + 1).x
end)

local a2_ctor_product_unique_ns = bench_avg_ns(hot_iters, function(i)
    return tonumber(A2_Pu(i, i + 1).x)
end)
local t_ctor_product_unique_ns = bench_avg_ns(hot_iters, function(i)
    return T_Pu(i, i + 1).x
end)

local a2_ctor_variant_plain_ns = bench_avg_ns(hot_iters, function(i)
    return tonumber(A2_An(i).payload)
end)
local t_ctor_variant_plain_ns = bench_avg_ns(hot_iters, function(i)
    return T_An(i).payload
end)

local a2_ctor_variant_unique_ns = bench_avg_ns(hot_iters, function(i)
    return tonumber(A2_Au(i).payload)
end)
local t_ctor_variant_unique_ns = bench_avg_ns(hot_iters, function(i)
    return T_Au(i).payload
end)

local a2_ctor_product_unique_hit_ns = bench_avg_ns(hot_iters, function()
    return tonumber(A2_Pu(1, 2).x)
end)
local t_ctor_product_unique_hit_ns = bench_avg_ns(hot_iters, function()
    return T_Pu(1, 2).x
end)

local a2_ctor_variant_unique_hit_ns = bench_avg_ns(hot_iters, function()
    return tonumber(A2_Au(1).payload)
end)
local t_ctor_variant_unique_hit_ns = bench_avg_ns(hot_iters, function()
    return T_Au(1).payload
end)

local a2_check_exact_ns = bench_avg_ns(hot_iters, function()
    return A2_Pn:isclassof(A2_plain) and 1 or 0
end)
local t_check_exact_ns = bench_avg_ns(hot_iters, function()
    return T_Pn:isclassof(T_plain) and 1 or 0
end)

local a2_check_sum_ns = bench_avg_ns(hot_iters, function()
    return A2_Sn:isclassof(A2_sumv) and 1 or 0
end)
local t_check_sum_ns = bench_avg_ns(hot_iters, function()
    return T_Sn:isclassof(T_sumv) and 1 or 0
end)

local a2_read_field_ns = bench_avg_ns(hot_iters, function()
    return tonumber(A2_plain.x + A2_plain.y)
end)
local t_read_field_ns = bench_avg_ns(hot_iters, function()
    return T_plain.x + T_plain.y
end)

print(string.format("asdl2 vs terra/src/asdl.lua install_iters=%d hot_iters=%d", install_iters, hot_iters))
print("schema: overlapping subset only (no handle fields; products/sums/unique/class checks)")
report_pair("full_distinct_install", "ms", asdl2_install_ms, terra_install_ms)
report_pair("ctor_product_plain", "ns", a2_ctor_product_plain_ns, t_ctor_product_plain_ns)
report_pair("ctor_product_unique", "ns", a2_ctor_product_unique_ns, t_ctor_product_unique_ns)
report_pair("ctor_variant_plain", "ns", a2_ctor_variant_plain_ns, t_ctor_variant_plain_ns)
report_pair("ctor_variant_unique", "ns", a2_ctor_variant_unique_ns, t_ctor_variant_unique_ns)
report_pair("ctor_product_unique_hit", "ns", a2_ctor_product_unique_hit_ns, t_ctor_product_unique_hit_ns)
report_pair("ctor_variant_unique_hit", "ns", a2_ctor_variant_unique_hit_ns, t_ctor_variant_unique_hit_ns)
report_pair("check_exact", "ns", a2_check_exact_ns, t_check_exact_ns)
report_pair("check_sum", "ns", a2_check_sum_ns, t_check_sum_ns)
report_pair("read_field", "ns", a2_read_field_ns, t_read_field_ns)
