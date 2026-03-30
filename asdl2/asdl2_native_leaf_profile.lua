local Boot = require("asdl2.asdl2_boot")
local Leaf = require("asdl2.asdl2_native_leaf_luajit")
local Schema = require("asdl2.asdl2_schema")

local T = Schema.ctx
local L = Boot.List
local UINT32 = "uint32_t"

local M = {}
local KEEP = {}

local function KS(s)
    KEEP[#KEEP + 1] = s
    return s
end

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function build_luajit(seed)
    local variant_header = T.Asdl2Catalog.VariantHeader(
        KS("BenchNative" .. tostring(seed) .. ".A"),
        KS("BenchNative" .. tostring(seed) .. ".S"),
        KS("A"),
        2000 + seed,
        3000 + seed,
        1,
        T.Asdl2Lowered.VariantCtor(1)
    )

    return T.Asdl2Lowered.Schema(
        L{
            T.Asdl2Lowered.ProductRecord(
                T.Asdl2Catalog.ProductHeader(KS("BenchNative" .. tostring(seed) .. ".P"), 1000 + seed, T.Asdl2Lowered.ProductCtor(2)),
                C(T.Asdl2Lowered.NoCacheRef),
                L{
                    T.Asdl2Lowered.InlineField(KS("x"), KS("number"), KS("x"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
                    T.Asdl2Lowered.InlineField(KS("y"), KS("number"), KS("y"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
                }
            ),
            T.Asdl2Lowered.ProductRecord(
                T.Asdl2Catalog.ProductHeader(KS("BenchNative" .. tostring(seed) .. ".U"), 1250 + seed, T.Asdl2Lowered.ProductCtor(2)),
                T.Asdl2Lowered.CacheSlotRef(1),
                L{
                    T.Asdl2Lowered.InlineField(KS("x"), KS("number"), KS("x"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
                    T.Asdl2Lowered.InlineField(KS("y"), KS("number"), KS("y"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
                }
            ),
            T.Asdl2Lowered.ProductRecord(
                T.Asdl2Catalog.ProductHeader(KS("BenchNative" .. tostring(seed) .. ".H"), 1500 + seed, T.Asdl2Lowered.ProductCtor(1)),
                C(T.Asdl2Lowered.NoCacheRef),
                L{
                    T.Asdl2Lowered.HandleScalarField(KS("x"), KS("number"), C(T.Asdl2Lowered.Optional), 1, KS("h_x"), KS(UINT32), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
                }
            ),
            T.Asdl2Lowered.VariantRecord(
                variant_header,
                C(T.Asdl2Lowered.NoCacheRef),
                L{
                    T.Asdl2Lowered.InlineField(KS("payload"), KS("number"), KS("payload"), KS("double"), T.Asdl2Lowered.BuiltinCheck(KS("number"))),
                }
            ),
        },
        L{ T.Asdl2Lowered.Sum(T.Asdl2Catalog.SumHeader(KS("BenchNative" .. tostring(seed) .. ".S"), 3000 + seed), L{ variant_header }) },
        L{ T.Asdl2Lowered.ScalarArenaSlot(1, T.Asdl2Lowered.BuiltinCheck(KS("number")), KS(UINT32)) },
        L{ T.Asdl2Lowered.CacheSlot(1, C(T.Asdl2Lowered.StructuralKind), 2, KS("BenchNative" .. tostring(seed) .. ".U")) }
    ):define_machine():lower_luajit()
end

local function new_ctx()
    local ctx = Leaf.new_context()
    ctx:Extern(KS("Extern.Type0"), function(_) return true end)
    return ctx
end

local function env_number(name, default)
    local v = os.getenv(name)
    local n = v and tonumber(v) or nil
    return n or default
end

function M.load_from_env()
    local mode = os.getenv("ASDL2_NATIVE_PROFILE_MODE") or "install_distinct"
    local install_iters = env_number("ASDL2_NATIVE_INSTALL_ITERS", 40)
    local hot_iters = env_number("ASDL2_NATIVE_HOT_ITERS", 2000000)

    local base_luajit = build_luajit(1)
    local base_ctx = Leaf.install(base_luajit, new_ctx())
    local P = base_ctx[KS("BenchNative1.P")]
    local Urec = base_ctx[KS("BenchNative1.U")]
    local H = base_ctx[KS("BenchNative1.H")]
    local A = base_ctx[KS("BenchNative1.A")]
    local Ssum = base_ctx[KS("BenchNative1.S")]
    local a = A(7.0)

    local pool = {}
    local ctx_pool = {}
    for i = 1, install_iters + 64 do
        pool[i] = build_luajit(i + 1000)
        ctx_pool[i] = new_ctx()
    end

    local function run_install_distinct()
        local sink = 0
        for i = 1, install_iters do
            local seed = i + 1000
            local ctx = Leaf.install(pool[i], ctx_pool[i])
            if ctx[KS("BenchNative" .. tostring(seed) .. ".P")] ~= nil then sink = sink + 1 end
        end
        return sink
    end

    local function run_ctor_product()
        local sink = 0
        for i = 1, hot_iters do sink = sink + tonumber(P(i, i + 1).x) end
        return sink
    end

    local function run_ctor_unique_product()
        local sink = 0
        for i = 1, hot_iters do sink = sink + tonumber(Urec(i, i + 1).x) end
        return sink
    end

    local function run_ctor_unique_product_hit()
        local sink = 0
        for i = 1, hot_iters do sink = sink + tonumber(Urec(1, 2).x) end
        return sink
    end

    local function run_ctor_handle_only()
        local sink = 0
        for i = 1, hot_iters do sink = sink + tonumber(H(i).h_x) end
        return sink
    end

    local function run_ctor_handle_plus_read()
        local sink = 0
        for i = 1, hot_iters do sink = sink + tonumber(H(i).x) end
        return sink
    end

    local function run_check_sum()
        local sink = 0
        for i = 1, hot_iters do if Ssum:isclassof(a) then sink = sink + 1 end end
        return sink
    end

    return {
        mode = mode,
        install_iters = install_iters,
        hot_iters = hot_iters,
        run = ({
            install_distinct = run_install_distinct,
            ctor_product = run_ctor_product,
            ctor_unique_product = run_ctor_unique_product,
            ctor_unique_product_hit = run_ctor_unique_product_hit,
            ctor_handle_only = run_ctor_handle_only,
            ctor_handle_plus_read = run_ctor_handle_plus_read,
            check_sum = run_check_sum,
        })[mode],
    }
end

function M.run_from_env()
    local workload = M.load_from_env()
    assert(workload.run, "unknown ASDL2_NATIVE_PROFILE_MODE: " .. tostring(workload.mode))
    print("asdl2_native_leaf_profile", workload.mode, workload.install_iters, workload.hot_iters, workload.run())
end

return M
