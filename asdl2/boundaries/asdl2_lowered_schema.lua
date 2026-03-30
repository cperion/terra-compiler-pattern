local Boot = require("asdl2.asdl2_boot")

local L = Boot.List

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function cache_slot_index(caches)
    local out = {}
    for i = 1, #caches do
        local slot = caches[i]
        out[slot.cache_id] = slot
    end
    return out
end

local function cache_gen_for(T, cache, cache_slots)
    local kind = cache.kind
    if kind == "NoCacheRef" then
        return C(T.Asdl2Machine.NoCache)
    end
    if kind == "CacheSlotRef" then
        local slot = cache_slots[cache.cache_id]
        local slot_kind = slot.kind.kind
        if slot_kind == "SingletonKind" then
            return C(T.Asdl2Machine.SingletonCache)
        end
        if slot_kind == "StructuralKind" then
            return T.Asdl2Machine.StructuralCache(slot.key_arity)
        end
        error("asdl2_machine.define_machine: unknown cache slot kind " .. tostring(slot_kind), 2)
    end
    error("asdl2_machine.define_machine: unknown cache ref kind " .. tostring(kind), 2)
end

local function record_gen_for(T, record, cache_slots)
    local cache = cache_gen_for(T, record.cache, cache_slots)
    local kind = record.kind

    if kind == "ProductRecord" then
        local header = record.header
        return T.Asdl2Machine.ProductGen(header.fqname, header.ctor, cache)
    end

    if kind == "VariantRecord" then
        local header = record.header
        return T.Asdl2Machine.VariantGen(
            header.fqname,
            header.parent_fqname,
            header.kind_name,
            header.ctor,
            cache
        )
    end

    error("asdl2_machine.define_machine: unknown record kind " .. tostring(kind), 2)
end

local function record_gens_for(T, records, cache_slots)
    local out = {}
    for i = 1, #records do
        out[i] = record_gen_for(T, records[i], cache_slots)
    end
    return L(out)
end

return function(T, U, P)
    T.Asdl2Lowered.Schema.define_machine = U.transition(function(schema)
        local cache_slots = cache_slot_index(schema.caches)
        return T.Asdl2Machine.Schema(
            T.Asdl2Machine.SchemaGen(record_gens_for(T, schema.records, cache_slots)),
            T.Asdl2Machine.SchemaParam(schema.records, schema.sums),
            T.Asdl2Machine.SchemaState(schema.arenas, schema.caches)
        )
    end)
end
