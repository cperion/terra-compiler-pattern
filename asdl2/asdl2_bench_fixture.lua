local Boot = require("asdl2.asdl2_boot")
local Native = require("asdl2.asdl2_native_leaf_luajit")
local Schema = require("asdl2.asdl2_schema")

local T = Schema.ctx
local L = Boot.List
local UINT32 = "uint32_t"

local M = {
    T = T,
    L = L,
    UINT32 = UINT32,
}

local KEEP = {}
local ARENA_IDS = {
    scalar0 = 1,
    scalar1 = 2,
    scalar2 = 3,
    list0 = 4,
    list1 = 5,
    list2 = 6,
}

local function KS(s)
    KEEP[#KEEP + 1] = s
    return s
end
M.KS = KS

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end
M.C = C

local function check_for(i, exact_class_id, family_id, variant_tags)
    return (i % 6 == 0) and T.Asdl2Lowered.ExactClassCheck(KS("Bench.Product.Exact"), exact_class_id)
        or (i % 5 == 0) and T.Asdl2Lowered.SumFamilyCheck(KS("Bench.Sum.Ref"), family_id, variant_tags)
        or (i % 3 == 0) and T.Asdl2Lowered.ExternalCheck(KS("Extern.Type" .. tostring(i % 4)))
        or (i % 2 == 0) and T.Asdl2Lowered.BuiltinCheck(KS("number"))
        or C(T.Asdl2Lowered.AnyCheck)
end

local function field_for(i, exact_class_id, family_id, variant_tags)
    local check = check_for(i, exact_class_id, family_id, variant_tags)
    local name = KS("field_" .. tostring(i))
    local type_name = KS("Type" .. tostring(i % 7))
    if i % 9 == 0 then
        return T.Asdl2Lowered.HandleListField(name, type_name, ARENA_IDS.list0 + (i % 3), KS("h_field_" .. tostring(i)), KS(UINT32), check)
    elseif i % 4 == 0 then
        return T.Asdl2Lowered.HandleScalarField(name, type_name, C(T.Asdl2Lowered.Optional), ARENA_IDS.scalar0 + (i % 3), KS("h_field_" .. tostring(i)), KS(UINT32), check)
    elseif check.kind == "BuiltinCheck" and check.name == "number" then
        return T.Asdl2Lowered.InlineField(name, type_name, name, KS("double"), check)
    end
    return T.Asdl2Lowered.HandleScalarField(name, type_name, C(T.Asdl2Lowered.ExactlyOne), ARENA_IDS.scalar0 + (i % 3), KS("h_field_" .. tostring(i)), KS(UINT32), check)
end

local function cache_ref_for(owner_fqname, i, field_count, cache_rows)
    if i % 4 ~= 0 and i % 3 ~= 0 then
        return C(T.Asdl2Lowered.NoCacheRef)
    end
    local cache_id = #cache_rows + 1
    cache_rows[cache_id] = T.Asdl2Lowered.CacheSlot(
        cache_id,
        (i % 4 == 0) and C(T.Asdl2Lowered.StructuralKind) or C(T.Asdl2Lowered.SingletonKind),
        (i % 4 == 0) and field_count or 0,
        owner_fqname
    )
    return T.Asdl2Lowered.CacheSlotRef(cache_id)
end

local function product_record(seed, i, field_count, exact_class_id, family_id, variant_tags, cache_rows)
    local fqname = KS("Bench.Product." .. tostring(seed) .. "." .. tostring(i))
    local fields = {}
    for j = 1, field_count do fields[j] = field_for(i * 11 + j, exact_class_id, family_id, variant_tags) end
    local ctor = (field_count == 0) and C(T.Asdl2Lowered.NullaryCtor) or T.Asdl2Lowered.ProductCtor(field_count)
    return T.Asdl2Lowered.ProductRecord(
        T.Asdl2Catalog.ProductHeader(fqname, exact_class_id + i, ctor),
        cache_ref_for(fqname, i, field_count, cache_rows),
        L(fields)
    )
end

local function variant_record(seed, family_id, tag, i, field_count, exact_class_id, variant_tags, cache_rows)
    local fqname = KS("Bench.Sum." .. tostring(seed) .. ".V" .. tostring(tag))
    local fields = {}
    for j = 1, field_count do fields[j] = field_for(i * 13 + j, exact_class_id, family_id, variant_tags) end
    local ctor = (field_count == 0) and C(T.Asdl2Lowered.NullaryCtor) or T.Asdl2Lowered.VariantCtor(field_count)
    return T.Asdl2Lowered.VariantRecord(
        T.Asdl2Catalog.VariantHeader(
            fqname,
            KS("Bench.Sum." .. tostring(seed)),
            KS("Kind" .. tostring(tag)),
            200000 + seed * 1000 + i,
            family_id,
            tag,
            ctor
        ),
        cache_ref_for(fqname, i + 17, field_count, cache_rows),
        L(fields)
    )
end

local function sum_row(seed, record_count, variant_count)
    local variants = {}
    for i = 1, variant_count do
        variants[i] = T.Asdl2Catalog.VariantHeader(
            KS("Bench.Sum." .. tostring(seed) .. ".V" .. tostring(i)),
            KS("Bench.Sum." .. tostring(seed)),
            KS("Kind" .. tostring(i)),
            200000 + seed * 1000 + record_count + i,
            700000 + seed,
            i,
            T.Asdl2Lowered.VariantCtor(0)
        )
    end
    return T.Asdl2Lowered.Sum(T.Asdl2Catalog.SumHeader(KS("Bench.Sum." .. tostring(seed)), 700000 + seed), L(variants))
end

local function arena_rows()
    return L{
        T.Asdl2Lowered.ScalarArenaSlot(ARENA_IDS.scalar0, C(T.Asdl2Lowered.AnyCheck), KS(UINT32)),
        T.Asdl2Lowered.ScalarArenaSlot(ARENA_IDS.scalar1, T.Asdl2Lowered.BuiltinCheck(KS("number")), KS(UINT32)),
        T.Asdl2Lowered.ScalarArenaSlot(ARENA_IDS.scalar2, T.Asdl2Lowered.ExternalCheck(KS("Extern.Type0")), KS(UINT32)),
        T.Asdl2Lowered.ListArenaSlot(ARENA_IDS.list0, C(T.Asdl2Lowered.AnyCheck), KS(UINT32)),
        T.Asdl2Lowered.ListArenaSlot(ARENA_IDS.list1, T.Asdl2Lowered.BuiltinCheck(KS("number")), KS(UINT32)),
        T.Asdl2Lowered.ListArenaSlot(ARENA_IDS.list2, T.Asdl2Lowered.ExternalCheck(KS("Extern.Type0")), KS(UINT32)),
    }
end

function M.build_lowered(seed, record_count, field_count, variant_count)
    local records = {}
    local cache_rows = {}
    local exact_class_id = 100000 + seed * 1000 + 1
    local family_id = 700000 + seed
    local variant_tags = L{ 1, 2, 3, 4, 5, 6, 7, 8 }

    for i = 1, record_count do
        records[#records + 1] = product_record(seed, i, field_count, exact_class_id, family_id, variant_tags, cache_rows)
    end
    for i = 1, variant_count do
        records[#records + 1] = variant_record(seed, family_id, i, record_count + i, field_count, exact_class_id, variant_tags, cache_rows)
    end

    return T.Asdl2Lowered.Schema(L(records), L{ sum_row(seed, record_count, variant_count) }, arena_rows(), L(cache_rows))
end

function M.build_machine(seed, record_count, field_count, variant_count)
    return M.build_lowered(seed, record_count, field_count, variant_count):define_machine()
end

function M.build_luajit(seed, record_count, field_count, variant_count)
    return M.build_machine(seed, record_count, field_count, variant_count):lower_luajit()
end

function M.new_ctx()
    local ctx = Native.new_context()
    for i = 0, 3 do
        ctx:Extern(KS("Extern.Type" .. tostring(i)), function(_) return true end)
    end
    return ctx
end

return M
