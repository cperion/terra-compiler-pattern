#!/usr/bin/env luajit

local ffi = require("ffi")
local Boot = require("asdl2.asdl2_boot")
local Native = require("asdl2.asdl2_native_leaf_luajit")
local Schema = require("asdl2.asdl2_schema")

local T = Schema.ctx

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } asdl2_full_timespec_t;
    int clock_gettime(int clk_id, asdl2_full_timespec_t *tp);
]]

local ts = ffi.new("asdl2_full_timespec_t")
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

local KEEP = {}
local function KS(s)
    KEEP[#KEEP + 1] = s
    return s
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

local function type_ref_for(i)
    if i % 11 == 0 then return "Extern.Type" .. tostring(i % 4) end
    if i % 6 == 0 then return "Product1" end
    if i % 5 == 0 then return "Sum" end
    if i % 3 == 0 then return "number" end
    if i % 2 == 0 then return "boolean" end
    return "string"
end

local function card_for(i)
    if i % 5 == 0 then return "?" end
    if i % 7 == 0 then return "*" end
    return ""
end

local function field_line(i)
    return string.format("%s%s field_%d", type_ref_for(i), card_for(i), i)
end

local function product_text(i, field_count)
    local fields = {}
    for j = 1, field_count do fields[j] = field_line(i * 11 + j) end
    return string.format("Product%d = (%s)%s", i, table.concat(fields, ", "), (i % 3 == 0) and " unique" or "")
end

local function ctor_text(i, field_count)
    local fields = {}
    for j = 1, field_count do fields[j] = field_line(i * 13 + j + 1000) end
    return string.format("V%d(%s)%s", i, table.concat(fields, ", "), (i % 2 == 0) and " unique" or "")
end

local function sum_text(variant_count, field_count)
    local ctors = {}
    local attrs = {}
    for i = 1, variant_count do ctors[i] = ctor_text(i, field_count) end
    for i = 1, math.max(1, math.floor(field_count / 2)) do attrs[i] = field_line(5000 + i) end
    return string.format("Sum = %s attributes (%s)", table.concat(ctors, " | "), table.concat(attrs, ", "))
end

local function module_name(seed)
    return "Bench" .. tostring(seed)
end

local function build_text(seed, type_count, field_count, variant_count)
    local lines = { "module " .. module_name(seed) .. " {" }
    for i = 1, type_count do lines[#lines + 1] = product_text(i, field_count) end
    lines[#lines + 1] = sum_text(variant_count, field_count)
    lines[#lines + 1] = "}"
    return KS(table.concat(lines, "\n"))
end

local function new_ctx()
    local ctx = Native.new_context()
    for i = 0, 3 do
        ctx:Extern(KS("Extern.Type" .. tostring(i)), function(_) return true end)
    end
    return ctx
end

local function compile_chain(text, ctx)
    local text_spec = T.Asdl2Text.Spec(text)
    local token_spec = text_spec:tokenize()
    local source = token_spec:parse()
    local catalog = source:catalog()
    local lowered = catalog:classify_lower()
    local machine = lowered:define_machine()
    local luajit = machine:lower_luajit()
    local installed = luajit:install(ctx)
    return {
        text = text_spec,
        token = token_spec,
        source = source,
        catalog = catalog,
        lowered = lowered,
        machine = machine,
        luajit = luajit,
        ctx = installed,
    }
end

local scenario = os.getenv("ASDL2_FULL_SCENARIO") or "mixed"
local iters = math.max(1, math.floor(getenv_number("ASDL2_FULL_ITERS", 20)))
local types = math.max(1, math.floor(getenv_number("ASDL2_FULL_TYPES", 20)))
local fields = math.max(0, math.floor(getenv_number("ASDL2_FULL_FIELDS", 6)))
local variants = math.max(1, math.floor(getenv_number("ASDL2_FULL_VARIANTS", 4)))

if scenario == "small" then
    types, fields, variants = 8, 3, 3
elseif scenario == "wide" then
    fields, variants = 12, 8
end

local base_text = build_text(1, types, fields, variants)
local base_ctx = new_ctx()
local base = compile_chain(base_text, base_ctx)
assert(base.ctx[module_name(1)] ~= nil)

local tokenize_existing_ms = bench_avg_ms(iters, function()
    base.text:tokenize()
end)

local parse_existing_ms = bench_avg_ms(iters, function()
    base.token:parse()
end)

local catalog_existing_ms = bench_avg_ms(iters, function()
    base.source:catalog()
end)

local classify_lower_existing_ms = bench_avg_ms(iters, function()
    base.catalog:classify_lower()
end)

local define_machine_existing_ms = bench_avg_ms(iters, function()
    base.lowered:define_machine()
end)

local lower_luajit_existing_ms = bench_avg_ms(iters, function()
    base.machine:lower_luajit()
end)

local install_existing_ms = bench_avg_ms(iters, function()
    base.luajit:install(base_ctx)
end)

local pool = {}
local ctx_pool = {}
for i = 1, iters + 64 do
    local seed = i + 5000
    pool[i] = build_text(seed, types, fields, variants)
    ctx_pool[i] = new_ctx()
end

local full_distinct_ms
 do
    local next_idx = 0
    full_distinct_ms = bench_avg_ms(iters, function()
        next_idx = next_idx + 1
        local seed = next_idx + 5000
        local chain = compile_chain(pool[next_idx], ctx_pool[next_idx])
        return chain.ctx[module_name(seed)]
    end)
end

local build_text_ms = bench_avg_ms(iters, function(i)
    build_text(i + 1000, types, fields, variants)
end)

local build_plus_full_ms
 do
    local seed = 200000
    build_plus_full_ms = bench_avg_ms(iters, function()
        seed = seed + 1
        return compile_chain(build_text(seed, types, fields, variants), new_ctx())
    end)
end

print(string.format(
    "asdl2 full bench iters=%d scenario=%s types=%d fields=%d variants=%d",
    iters,
    scenario,
    types,
    fields,
    variants
))
print(string.format("tokenize_existing_avg_ms: %.3f", tokenize_existing_ms))
print(string.format("parse_existing_avg_ms: %.3f", parse_existing_ms))
print(string.format("catalog_existing_avg_ms: %.3f", catalog_existing_ms))
print(string.format("classify_lower_existing_avg_ms: %.3f", classify_lower_existing_ms))
print(string.format("define_machine_existing_avg_ms: %.3f", define_machine_existing_ms))
print(string.format("lower_luajit_existing_avg_ms: %.3f", lower_luajit_existing_ms))
print(string.format("install_existing_avg_ms: %.3f", install_existing_ms))
print(string.format("build_text_avg_ms: %.3f", build_text_ms))
print(string.format("full_distinct_avg_ms: %.3f", full_distinct_ms))
print(string.format("build_plus_full_avg_ms: %.3f", build_plus_full_ms))
