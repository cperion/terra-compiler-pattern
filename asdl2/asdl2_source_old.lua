local Boot = require("asdl2.asdl2_boot")
local U = require("unit")

local L = Boot.List

local BUILTIN = {
    number = true,
    boolean = true,
    string = true,
    any = true,
    userdata = true,
    cdata = true,
    ["function"] = true,
}

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function qualify(prefix, name)
    if prefix == "" then return name end
    return prefix .. "." .. name
end

local function ctor_family_for(T, field_count, variant)
    if field_count == 0 then return C(T.Asdl2Lowered.NullaryCtor) end
    return variant and T.Asdl2Lowered.VariantCtor(field_count) or T.Asdl2Lowered.ProductCtor(field_count)
end

local function push_scope(scopes, scope)
    local out = {}
    for i = 1, #scopes do out[i] = scopes[i] end
    out[#out + 1] = scope
    return out
end

local function lookup_target_for(scopes, query_name)
    for i = #scopes, 1, -1 do
        local lookups = scopes[i].lookups
        for j = 1, #lookups do
            local entry = lookups[j]
            if entry.query_name == query_name then
                return entry.target
            end
        end
    end
    return nil
end

local function catalog_constructors(T, module_prefix, sum_header, attr_count, ctors, state)
    local out_ctors = {}
    local headers = {}
    local class_id = state.class_id

    for i = 1, #ctors do
        local ctor = ctors[i]
        class_id = class_id + 1
        local fqname = qualify(module_prefix, ctor.name)
        local field_count = #ctor.fields + attr_count
        local header = T.Asdl2Catalog.VariantHeader(
            fqname,
            sum_header.fqname,
            ctor.name,
            class_id,
            sum_header.family_id,
            i,
            ctor_family_for(T, field_count, true)
        )
        headers[i] = header
        out_ctors[i] = {
            name = ctor.name,
            header = header,
            fields = ctor.fields,
            unique_flag = ctor.unique_flag and true or false,
        }
    end

    state.class_id = class_id
    return {
        ctors = out_ctors,
        headers = headers,
        state = state,
    }
end

local function catalog_layout(T, prefix, definitions, state)
    local out_defs = {}
    local out_lookups = {}

    for i = 1, #definitions do
        local def = definitions[i]
        local kind = def.kind

        if kind == "ModuleDef" then
            local fqname = qualify(prefix, def.name)
            local child = catalog_layout(T, fqname, def.definitions, state)
            state = child.state
            local scope = T.Asdl2Catalog.Scope(fqname, L(child.lookups))
            out_defs[#out_defs + 1] = {
                kind = "ModuleDef",
                name = def.name,
                fqname = fqname,
                scope = scope,
                definitions = child.definitions,
            }
            for j = 1, #child.lookups do
                local entry = child.lookups[j]
                out_lookups[#out_lookups + 1] = T.Asdl2Catalog.LookupEntry(def.name .. "." .. entry.query_name, entry.target)
            end
        elseif kind == "TypeDef" then
            local fqname = qualify(prefix, def.name)
            local expr = def.type_expr
            local expr_kind = expr.kind

            if expr_kind == "Product" then
                state.class_id = state.class_id + 1
                local header = T.Asdl2Catalog.ProductHeader(
                    fqname,
                    state.class_id,
                    ctor_family_for(T, #expr.fields, false)
                )
                out_defs[#out_defs + 1] = {
                    kind = "ProductDef",
                    name = def.name,
                    header = header,
                    fields = expr.fields,
                    unique_flag = expr.unique_flag and true or false,
                }
                out_lookups[#out_lookups + 1] = T.Asdl2Catalog.LookupEntry(
                    def.name,
                    T.Asdl2Catalog.ProductTarget(header)
                )
            elseif expr_kind == "Sum" then
                state.family_id = state.family_id + 1
                local header = T.Asdl2Catalog.SumHeader(fqname, state.family_id)
                local ctor_rows = catalog_constructors(T, prefix, header, #expr.attribute_fields, expr.constructors, state)
                state = ctor_rows.state
                local variants = L(ctor_rows.headers)
                out_defs[#out_defs + 1] = {
                    kind = "SumDef",
                    name = def.name,
                    header = header,
                    constructors = ctor_rows.ctors,
                    attribute_fields = expr.attribute_fields,
                }
                out_lookups[#out_lookups + 1] = T.Asdl2Catalog.LookupEntry(
                    def.name,
                    T.Asdl2Catalog.SumTarget(header, variants)
                )
            else
                error("asdl2_source.catalog: unknown type expr kind " .. tostring(expr_kind), 2)
            end
        else
            error("asdl2_source.catalog: unknown definition kind " .. tostring(kind), 2)
        end
    end

    return {
        definitions = out_defs,
        lookups = out_lookups,
        state = state,
    }
end

local function resolve_catalog_type_ref(T, scopes, type_ref)
    local kind = type_ref.kind

    if kind == "BuiltinTypeRef" then
        return T.Asdl2Catalog.BuiltinTypeRef(type_ref.name)
    end

    if kind == "UnqualifiedTypeRef" then
        local target = lookup_target_for(scopes, type_ref.name)
        if target == nil then
            error("asdl2_source.catalog: unknown type ref '" .. tostring(type_ref.name) .. "'", 2)
        end
        if target.kind == "ProductTarget" then
            return T.Asdl2Catalog.ProductTargetRef(target.header)
        end
        if target.kind == "SumTarget" then
            return T.Asdl2Catalog.SumTargetRef(target.header, target.variants)
        end
        error("asdl2_source.catalog: unknown lookup target kind " .. tostring(target.kind), 2)
    end

    if kind == "QualifiedTypeRef" then
        local fqname = type_ref.fqname
        local target = lookup_target_for(scopes, fqname)
        if target == nil then
            return T.Asdl2Catalog.ExternalTypeRef(fqname)
        end
        if target.kind == "ProductTarget" then
            return T.Asdl2Catalog.ProductTargetRef(target.header)
        end
        if target.kind == "SumTarget" then
            return T.Asdl2Catalog.SumTargetRef(target.header, target.variants)
        end
        error("asdl2_source.catalog: unknown lookup target kind " .. tostring(target.kind), 2)
    end

    error("asdl2_source.catalog: unknown type ref kind " .. tostring(kind), 2)
end

local function resolve_catalog_fields(T, scopes, fields)
    local out = {}
    for i = 1, #fields do
        local field = fields[i]
        out[i] = T.Asdl2Catalog.Field(
            resolve_catalog_type_ref(T, scopes, field.type_ref),
            field.cardinality,
            field.name
        )
    end
    return L(out)
end

local function resolve_catalog_constructors(T, scopes, ctors)
    local out = {}
    for i = 1, #ctors do
        local ctor = ctors[i]
        out[i] = T.Asdl2Catalog.Constructor(
            ctor.name,
            ctor.header,
            resolve_catalog_fields(T, scopes, ctor.fields),
            ctor.unique_flag and true or false
        )
    end
    return L(out)
end

local function resolve_catalog_definitions(T, scopes, definitions)
    local out = {}

    for i = 1, #definitions do
        local def = definitions[i]
        local kind = def.kind

        if kind == "ModuleDef" then
            out[#out + 1] = T.Asdl2Catalog.ModuleDef(
                def.name,
                def.fqname,
                def.scope,
                resolve_catalog_definitions(T, push_scope(scopes, def.scope), def.definitions)
            )
        elseif kind == "ProductDef" then
            out[#out + 1] = T.Asdl2Catalog.ProductDef(
                def.name,
                def.header,
                resolve_catalog_fields(T, scopes, def.fields),
                def.unique_flag and true or false
            )
        elseif kind == "SumDef" then
            out[#out + 1] = T.Asdl2Catalog.SumDef(
                def.name,
                def.header,
                resolve_catalog_constructors(T, scopes, def.constructors),
                resolve_catalog_fields(T, scopes, def.attribute_fields)
            )
        else
            error("asdl2_source.catalog: unknown raw definition kind " .. tostring(kind), 2)
        end
    end

    return L(out)
end

return function(T)
    T.Asdl2Source.Spec.catalog = U.transition(function(spec)
        local raw = catalog_layout(T, "", spec.definitions, {
            class_id = 0,
            family_id = 0,
        })
        local root_scope = T.Asdl2Catalog.Scope("", L(raw.lookups))
        return T.Asdl2Catalog.Spec(
            root_scope,
            resolve_catalog_definitions(T, { root_scope }, raw.definitions)
        )
    end)

end
