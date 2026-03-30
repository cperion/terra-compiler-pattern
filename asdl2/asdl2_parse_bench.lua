#!/usr/bin/env luajit

local ffi = require("ffi")
local Schema = require("asdl2.asdl2_schema")

local T = Schema.ctx

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } asdl2_l5_timespec_t;
    int clock_gettime(int clk_id, asdl2_l5_timespec_t *tp);
]]

local ts = ffi.new("asdl2_l5_timespec_t")
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

local BENCH_SINK = 0

local function bench_avg_ms(iters, fn)
    local warm = math.min(iters, 100)
    local sink = 0
    for i = 1, warm do sink = sink + fn(i) end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do sink = sink + fn(i) end
    local t1 = now_s()
    BENCH_SINK = BENCH_SINK + sink
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
    for j = 1, field_count do
        fields[j] = field_line(i * 11 + j)
    end
    return string.format("Product%d = (%s)%s", i, table.concat(fields, ", "), (i % 3 == 0) and " unique" or "")
end

local function ctor_text(i, field_count)
    local fields = {}
    for j = 1, field_count do
        fields[j] = field_line(i * 13 + j + 1000)
    end
    return string.format("V%d(%s)%s", i, table.concat(fields, ", "), (i % 2 == 0) and " unique" or "")
end

local function sum_text(variant_count, field_count)
    local ctors = {}
    local attrs = {}
    for i = 1, variant_count do
        ctors[i] = ctor_text(i, field_count)
    end
    for i = 1, math.max(1, math.floor(field_count / 2)) do
        attrs[i] = field_line(5000 + i)
    end
    return string.format("Sum = %s attributes (%s)", table.concat(ctors, " | "), table.concat(attrs, ", "))
end

local function module_name(seed)
    return "Bench" .. tostring(seed)
end

local function build_text(seed, type_count, field_count, variant_count)
    local lines = { "module " .. module_name(seed) .. " {" }
    for i = 1, type_count do
        lines[#lines + 1] = product_text(i, field_count)
    end
    lines[#lines + 1] = sum_text(variant_count, field_count)
    lines[#lines + 1] = "}"
    return KS(table.concat(lines, "\n"))
end

local scenario = os.getenv("ASDL2_PARSE_SCENARIO") or "mixed"
local iters = math.max(1, math.floor(getenv_number("ASDL2_PARSE_ITERS", 40)))
local types = math.max(1, math.floor(getenv_number("ASDL2_PARSE_TYPES", 500)))
local fields = math.max(0, math.floor(getenv_number("ASDL2_PARSE_FIELDS", 6)))
local variants = math.max(1, math.floor(getenv_number("ASDL2_PARSE_VARIANTS", 4)))

if scenario == "small" then
    types, fields, variants = 64, 3, 3
elseif scenario == "wide" then
    fields, variants = 12, 8
end

local base = T.Asdl2Text.Spec(build_text(1, types, fields, variants))
local parsed = base:parse()
assert(parsed.definitions[1].kind == "ModuleDef")

local parse_existing_ms = bench_avg_ms(iters, function()
    return #base:parse().definitions
end)

local distinct_pool = {}
do
    local total = iters + math.min(iters, 100)
    for i = 1, total do
        distinct_pool[i] = T.Asdl2Text.Spec(build_text(i + 5000, types, fields, variants))
    end
end

local parse_distinct_ms
 do
    local next_idx = 0
    parse_distinct_ms = bench_avg_ms(iters, function()
        next_idx = next_idx + 1
        local x = distinct_pool[next_idx]:parse()
        return #x.definitions
    end)
end

local build_text_ms = bench_avg_ms(iters, function(i)
    return #build_text(i + 1000, types, fields, variants)
end)

local build_plus_parse_ms
 do
    local next_seed = 2000
    build_plus_parse_ms = bench_avg_ms(iters, function()
        next_seed = next_seed + 1
        return #T.Asdl2Text.Spec(build_text(next_seed, types, fields, variants)):parse().definitions
    end)
end

print(string.format(
    "asdl2 parse bench iters=%d scenario=%s types=%d fields=%d variants=%d",
    iters,
    scenario,
    types,
    fields,
    variants
))
print(string.format("parse_existing_text_avg_ms: %.3f", parse_existing_ms))
print(string.format("parse_distinct_text_avg_ms: %.3f", parse_distinct_ms))
print(string.format("build_text_avg_ms: %.3f", build_text_ms))
print(string.format("build_plus_parse_avg_ms: %.3f", build_plus_parse_ms))
print(string.format("bench_sink=%d", BENCH_SINK))
