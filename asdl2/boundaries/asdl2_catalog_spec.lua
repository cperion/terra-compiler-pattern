local Boot = require("asdl2.asdl2_boot")

local L = Boot.List
local UINT32 = "uint32_t"

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function join_lists(a, b)
    local out = {}
    for i = 1, #a do out[#out + 1] = a[i] end
    for i = 1, #b do out[#out + 1] = b[i] end
    return L(out)
end

local function copy_variant_tags(variants)
    local out = {}
    for i = 1, #variants do out[i] = variants[i].variant_tag end
    return L(out)
end

local function inline_c_type_for_builtin(name)
    if name == "number" then return "double" end
    if name == "boolean" then return "uint8_t" end
    if name == "string" then return "const char *" end
    return nil
end

local function ensure_arena_slot(T, acc, arena_kind, check, display_key)
    local key = arena_kind .. ":" .. display_key
    local existing = acc.arena_id_by_key[key]
    if existing ~= nil then return existing end
    acc.next_arena_id = acc.next_arena_id + 1
    local arena_id = acc.next_arena_id
    acc.arena_id_by_key[key] = arena_id
    acc.arenas[#acc.arenas + 1] = (arena_kind == "list")
        and T.Asdl2Lowered.ListArenaSlot(arena_id, check, UINT32)
        or T.Asdl2Lowered.ScalarArenaSlot(arena_id, check, UINT32)
    return arena_id
end

local function cache_ref_for(T, fqname, unique_flag, field_count, acc)
    if not unique_flag then return C(T.Asdl2Lowered.NoCacheRef) end
    local cache_id = acc.cache_id_by_owner[fqname]
    if cache_id == nil then
        acc.next_cache_id = acc.next_cache_id + 1
        cache_id = acc.next_cache_id
        acc.cache_id_by_owner[fqname] = cache_id
        acc.caches[#acc.caches + 1] = T.Asdl2Lowered.CacheSlot(
            cache_id,
            (field_count == 0) and C(T.Asdl2Lowered.SingletonKind) or C(T.Asdl2Lowered.StructuralKind),
            (field_count == 0) and 0 or field_count,
            fqname
        )
    end
    return T.Asdl2Lowered.CacheSlotRef(cache_id)
end

local function lower_fields(T, fields, acc)
    local out = {}

    for i = 1, #fields do
        local field = fields[i]
        local type_ref = field.type_ref
        local kind = type_ref.kind
        local type_name, check, display_key, inline_c_type

        if kind == "BuiltinTypeRef" then
            local name = type_ref.name
            type_name = name
            check = T.Asdl2Lowered.BuiltinCheck(name)
            display_key = "builtin:" .. name
            inline_c_type = inline_c_type_for_builtin(name)
        elseif kind == "ExternalTypeRef" then
            local fqname = type_ref.fqname
            type_name = fqname
            check = T.Asdl2Lowered.ExternalCheck(fqname)
            display_key = "external:" .. fqname
        elseif kind == "ProductTargetRef" then
            local header = type_ref.header
            local fqname = header.fqname
            type_name = fqname
            check = T.Asdl2Lowered.ExactClassCheck(fqname, header.class_id)
            display_key = "type:" .. fqname
        elseif kind == "SumTargetRef" then
            local header = type_ref.header
            local fqname = header.fqname
            type_name = fqname
            check = T.Asdl2Lowered.SumFamilyCheck(fqname, header.family_id, copy_variant_tags(type_ref.variants))
            display_key = "sum:" .. fqname
        else
            error("asdl2_catalog.classify_lower: unknown type ref kind " .. tostring(kind), 2)
        end

        local field_name = field.name
        local handle_field = "h_" .. field_name
        local card_kind = field.cardinality.kind

        if card_kind == "Many" then
            out[i] = T.Asdl2Lowered.HandleListField(
                field_name,
                type_name,
                ensure_arena_slot(T, acc, "list", check, display_key),
                handle_field,
                UINT32,
                check
            )
        elseif card_kind == "ExactlyOne" then
            if inline_c_type ~= nil then
                out[i] = T.Asdl2Lowered.InlineField(
                    field_name,
                    type_name,
                    field_name,
                    inline_c_type,
                    check
                )
            else
                out[i] = T.Asdl2Lowered.HandleScalarField(
                    field_name,
                    type_name,
                    C(T.Asdl2Lowered.ExactlyOne),
                    ensure_arena_slot(T, acc, "scalar", check, display_key),
                    handle_field,
                    UINT32,
                    check
                )
            end
        elseif card_kind == "Optional" then
            out[i] = T.Asdl2Lowered.HandleScalarField(
                field_name,
                type_name,
                C(T.Asdl2Lowered.Optional),
                ensure_arena_slot(T, acc, "scalar", check, display_key),
                handle_field,
                UINT32,
                check
            )
        else
            error("asdl2_catalog.classify_lower: unknown cardinality kind " .. tostring(card_kind), 2)
        end
    end

    return L(out)
end

local function lower_definitions(T, definitions, acc)
    for i = 1, #definitions do
        local def = definitions[i]
        local kind = def.kind

        if kind == "ModuleDef" then
            lower_definitions(T, def.definitions, acc)
        elseif kind == "ProductDef" then
            acc.records[#acc.records + 1] = T.Asdl2Lowered.ProductRecord(
                def.header,
                cache_ref_for(T, def.header.fqname, def.unique_flag and true or false, #def.fields, acc),
                lower_fields(T, def.fields, acc)
            )
        elseif kind == "SumDef" then
            local variants = {}
            for j = 1, #def.constructors do
                variants[j] = def.constructors[j].header
            end
            acc.sums[#acc.sums + 1] = T.Asdl2Lowered.Sum(def.header, L(variants))

            for j = 1, #def.constructors do
                local ctor = def.constructors[j]
                local all_fields = join_lists(ctor.fields, def.attribute_fields)
                acc.records[#acc.records + 1] = T.Asdl2Lowered.VariantRecord(
                    ctor.header,
                    cache_ref_for(T, ctor.header.fqname, ctor.unique_flag and true or false, #all_fields, acc),
                    lower_fields(T, all_fields, acc)
                )
            end
        else
            error("asdl2_catalog.classify_lower: unknown definition kind " .. tostring(kind), 2)
        end
    end
    return acc
end

local function classify_definitions(T, definitions)
    local lowered = lower_definitions(T, definitions, {
        records = {},
        sums = {},
        arenas = {},
        caches = {},
        next_arena_id = 0,
        next_cache_id = 0,
        arena_id_by_key = {},
        cache_id_by_owner = {},
    })

    return T.Asdl2Lowered.Schema(
        L(lowered.records),
        L(lowered.sums),
        L(lowered.arenas),
        L(lowered.caches)
    )
end

return function(T, U, P)
    T.Asdl2Catalog.Spec.classify_lower = U.transition(function(spec)
        return classify_definitions(T, spec.definitions)
    end)
end
