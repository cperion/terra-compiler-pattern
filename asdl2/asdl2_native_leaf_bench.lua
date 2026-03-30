#!/usr/bin/env luajit

local ffi = require("ffi")
local Boot = require("asdl2.asdl2_boot")
local Leaf = require("asdl2.asdl2_native_leaf_luajit")
local Schema = require("asdl2.asdl2_schema")

local T = Schema.ctx
local L = Boot.List
local UINT32 = "uint32_t"

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } asdl2_native_leaf_timespec_t;
    int clock_gettime(int clk_id, asdl2_native_leaf_timespec_t *tp);
]]

local ts = ffi.new("asdl2_native_leaf_timespec_t")
local CLOCK_MONOTONIC = 1
local KEEP = {}

local function KS(s)
    KEEP[#KEEP + 1] = s
    return s
end

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

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

local function report(name, avg_ns, sink)
    print(string.format("%-28s %.1f ns   sink=%d", name .. ":", avg_ns, sink))
end

local function no_cache()
    return C(T.Asdl2Lowered.NoCacheRef)
end

local function structural_cache()
    return T.Asdl2Lowered.CacheSlotRef(1)
end

local function product_header(seed, suffix, class_id, field_count)
    return T.Asdl2Catalog.ProductHeader(
        KS("BenchNative" .. tostring(seed) .. "." .. suffix),
        class_id,
        T.Asdl2Lowered.ProductCtor(field_count)
    )
end

local function variant_header(seed)
    return T.Asdl2Catalog.VariantHeader(
        KS("BenchNative" .. tostring(seed) .. ".A"),
        KS("BenchNative" .. tostring(seed) .. ".S"),
        KS("A"),
        2000 + seed,
        3000 + seed,
        1,
        T.Asdl2Lowered.VariantCtor(1)
    )
end

local function product_record(seed)
    return T.Asdl2Lowered.ProductRecord(
        product_header(seed, "P", 1000 + seed, 2),
        no_cache(),
        L{
            T.Asdl2Lowered.InlineField(KS("x"), KS("number"), KS("x"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
            T.Asdl2Lowered.InlineField(KS("y"), KS("number"), KS("y"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
        }
    )
end

local function unique_product_record(seed)
    return T.Asdl2Lowered.ProductRecord(
        product_header(seed, "U", 1250 + seed, 2),
        structural_cache(),
        L{
            T.Asdl2Lowered.InlineField(KS("x"), KS("number"), KS("x"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
            T.Asdl2Lowered.InlineField(KS("y"), KS("number"), KS("y"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
        }
    )
end

local function handle_record(seed)
    return T.Asdl2Lowered.ProductRecord(
        product_header(seed, "H", 1500 + seed, 1),
        no_cache(),
        L{
            T.Asdl2Lowered.HandleScalarField(KS("x"), KS("number"), C(T.Asdl2Lowered.Optional), 1, KS("h_x"), KS(UINT32), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
        }
    )
end

local function variant_record(seed)
    return T.Asdl2Lowered.VariantRecord(
        variant_header(seed),
        no_cache(),
        L{
            T.Asdl2Lowered.InlineField(KS("payload"), KS("number"), KS("payload"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
        }
    )
end

local function sum_row(seed)
    return T.Asdl2Lowered.Sum(
        T.Asdl2Catalog.SumHeader(KS("BenchNative" .. tostring(seed) .. ".S"), 3000 + seed),
        L{ variant_header(seed) }
    )
end

local function build_luajit(seed)
    return T.Asdl2Lowered.Schema(
        L{ product_record(seed), unique_product_record(seed), handle_record(seed), variant_record(seed) },
        L{ sum_row(seed) },
        L{ T.Asdl2Lowered.ScalarArenaSlot(1, T.Asdl2Lowered.BuiltinCheck(KS("number")), KS(UINT32)) },
        L{ T.Asdl2Lowered.CacheSlot(1, C(T.Asdl2Lowered.StructuralKind), 2, KS("BenchNative" .. tostring(seed) .. ".U")) }
    ):define_machine():lower_luajit()
end

local function new_ctx()
    local ctx = Leaf.new_context()
    ctx:Extern(KS("Extern.Type0"), function(_) return true end)
    return ctx
end

local install_iters = math.max(1, math.floor(getenv_number("ASDL2_NATIVE_INSTALL_ITERS", 20)))
local hot_iters = math.max(1, math.floor(getenv_number("ASDL2_NATIVE_HOT_ITERS", 2000000)))

local base_seed = 1
local base_luajit = build_luajit(base_seed)
local base_ctx = Leaf.install(base_luajit, new_ctx())
local P = base_ctx[KS("BenchNative1.P")]
local Urec = base_ctx[KS("BenchNative1.U")]
local H = base_ctx[KS("BenchNative1.H")]
local A = base_ctx[KS("BenchNative1.A")]
local Ssum = base_ctx[KS("BenchNative1.S")]
local p = P(1.5, 2.5)
local u = Urec(1.5, 2.5)
local h = H(3.5)
local a = A(7.0)
assert(P:isclassof(p))
assert(Urec:isclassof(u))
assert(H:isclassof(h))
assert(A:isclassof(a))
assert(Ssum:isclassof(a))

print(string.format("asdl2 native leaf bench install_iters=%d hot_iters=%d", install_iters, hot_iters))

local install_existing_ns, sink1 = bench_avg_ns(install_iters, function()
    local ctx = Leaf.install(base_luajit, base_ctx)
    return ctx[KS("BenchNative1.P")] ~= nil and 1 or 0
end)
report("install_existing", install_existing_ns, sink1)

local distinct_pool = {}
local ctx_pool = {}
for i = 1, install_iters + 64 do
    distinct_pool[i] = build_luajit(i + 1000)
    ctx_pool[i] = new_ctx()
end
local next_idx = 0
local install_distinct_ns, sink2 = bench_avg_ns(install_iters, function()
    next_idx = next_idx + 1
    local seed = next_idx + 1000
    local ctx = Leaf.install(distinct_pool[next_idx], ctx_pool[next_idx])
    return ctx[KS("BenchNative" .. tostring(seed) .. ".P")] ~= nil and 1 or 0
end)
report("install_distinct", install_distinct_ns, sink2)

local ctor_product_ns, sink3 = bench_avg_ns(hot_iters, function(i)
    local v = P(i, i + 1)
    return tonumber(v.x)
end)
report("ctor_product", ctor_product_ns, sink3)

local ctor_variant_ns, sink4 = bench_avg_ns(hot_iters, function(i)
    local v = A(i)
    return tonumber(v.payload)
end)
report("ctor_variant", ctor_variant_ns, sink4)

local ctor_unique_product_ns, sink4b = bench_avg_ns(hot_iters, function(i)
    local v = Urec(i, i + 1)
    return tonumber(v.x)
end)
report("ctor_unique_product", ctor_unique_product_ns, sink4b)

local ctor_unique_product_hit_ns, sink4c = bench_avg_ns(hot_iters, function(_)
    local v = Urec(1, 2)
    return tonumber(v.x)
end)
report("ctor_unique_product_hit", ctor_unique_product_hit_ns, sink4c)

local ctor_handle_only_ns, sink5 = bench_avg_ns(hot_iters, function(i)
    local v = H(i)
    return tonumber(v.h_x)
end)
report("ctor_handle_only", ctor_handle_only_ns, sink5)

local ctor_handle_plus_read_ns, sink6 = bench_avg_ns(hot_iters, function(i)
    local v = H(i)
    return tonumber(v.x)
end)
report("ctor_handle_plus_read", ctor_handle_plus_read_ns, sink6)

local check_exact_ns, sink7 = bench_avg_ns(hot_iters, function(_)
    return P:isclassof(p) and 1 or 0
end)
report("check_exact", check_exact_ns, sink7)

local check_sum_ns, sink8 = bench_avg_ns(hot_iters, function(_)
    return Ssum:isclassof(a) and 1 or 0
end)
report("check_sum", check_sum_ns, sink8)

local read_field_ns, sink9 = bench_avg_ns(hot_iters, function(_)
    return tonumber(p.x + p.y)
end)
report("read_field", read_field_ns, sink9)

local read_handle_ns, sink10 = bench_avg_ns(hot_iters, function(_)
    return tonumber(h.x)
end)
report("read_handle", read_handle_ns, sink10)
