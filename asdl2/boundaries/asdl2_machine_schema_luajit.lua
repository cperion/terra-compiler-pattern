local Boot = require("asdl2.asdl2_boot")

local L = Boot.List

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function ctype_name_for(fqname)
    return "asdl2_" .. fqname:gsub("%.", "_")
end

return function(T, U, P)
    local function inline_check_plan_for(v)
        return U.match(v.check, {
            AnyCheck = function()
                return C(T.Asdl2LuaJIT.AnyScalarCheck)
            end,
            BuiltinCheck = function(check)
                return T.Asdl2LuaJIT.BuiltinScalarCheck(check.name)
            end,
            ExternalCheck = function(check)
                return T.Asdl2LuaJIT.ExternalScalarCheck(check.fqname)
            end,
            ExactClassCheck = function(check)
                return T.Asdl2LuaJIT.ExactClassScalarCheck(check.class_id)
            end,
            SumFamilyCheck = function(check)
                return T.Asdl2LuaJIT.SumFamilyScalarCheck(check.family_id)
            end,
        })
    end

    local function handle_scalar_check_plan_for(v)
        return U.match(v.check, {
            AnyCheck = function()
                return C(T.Asdl2LuaJIT.AnyScalarCheck)
            end,
            BuiltinCheck = function(check)
                return T.Asdl2LuaJIT.BuiltinScalarCheck(check.name)
            end,
            ExternalCheck = function(check)
                return T.Asdl2LuaJIT.ExternalScalarCheck(check.fqname)
            end,
            ExactClassCheck = function(check)
                return T.Asdl2LuaJIT.ExactClassScalarCheck(check.class_id)
            end,
            SumFamilyCheck = function(check)
                return T.Asdl2LuaJIT.SumFamilyScalarCheck(check.family_id)
            end,
        })
    end

    local function handle_optional_check_plan_for(v)
        return U.match(v.check, {
            AnyCheck = function()
                return C(T.Asdl2LuaJIT.AnyOptionalCheck)
            end,
            BuiltinCheck = function(check)
                return T.Asdl2LuaJIT.BuiltinOptionalCheck(check.name)
            end,
            ExternalCheck = function(check)
                return T.Asdl2LuaJIT.ExternalOptionalCheck(check.fqname)
            end,
            ExactClassCheck = function(check)
                return T.Asdl2LuaJIT.ExactClassOptionalCheck(check.class_id)
            end,
            SumFamilyCheck = function(check)
                return T.Asdl2LuaJIT.SumFamilyOptionalCheck(check.family_id)
            end,
        })
    end

    local function handle_list_check_plan_for(v)
        return U.match(v.check, {
            AnyCheck = function()
                return C(T.Asdl2LuaJIT.AnyListCheck)
            end,
            BuiltinCheck = function(check)
                return T.Asdl2LuaJIT.BuiltinListCheck(check.name)
            end,
            ExternalCheck = function(check)
                return T.Asdl2LuaJIT.ExternalListCheck(check.fqname)
            end,
            ExactClassCheck = function(check)
                return T.Asdl2LuaJIT.ExactClassListCheck(check.class_id)
            end,
            SumFamilyCheck = function(check)
                return T.Asdl2LuaJIT.SumFamilyListCheck(check.family_id)
            end,
        })
    end

    local function field_plan_for(field)
        return U.match(field, {
            InlineField = function(v)
                return T.Asdl2LuaJIT.InlineFieldPlan(
                    v.name,
                    v.c_name,
                    v.c_type,
                    inline_check_plan_for(v),
                    v.type_name
                )
            end,
            HandleScalarField = function(v)
                return U.match(v.cardinality, {
                    ExactlyOne = function()
                        return T.Asdl2LuaJIT.HandleScalarFieldPlan(
                            v.name,
                            v.handle_field,
                            v.arena_id,
                            v.handle_ctype,
                            handle_scalar_check_plan_for(v),
                            v.type_name
                        )
                    end,
                    Optional = function()
                        return T.Asdl2LuaJIT.HandleScalarFieldPlan(
                            v.name,
                            v.handle_field,
                            v.arena_id,
                            v.handle_ctype,
                            handle_optional_check_plan_for(v),
                            v.type_name .. "?"
                        )
                    end,
                })
            end,
            HandleListField = function(v)
                return T.Asdl2LuaJIT.HandleListFieldPlan(
                    v.name,
                    v.handle_field,
                    v.arena_id,
                    v.handle_ctype,
                    handle_list_check_plan_for(v),
                    v.type_name .. "*"
                )
            end,
        })
    end

    local function field_plans_for(fields)
        return L(U.map_into({}, fields, field_plan_for))
    end

    local function cache_plan_for(record, caches)
        if record.cache.kind == "NoCacheRef" then
            return C(T.Asdl2LuaJIT.NoCachePlan)
        end
        local ref = record.cache
        local slot = U.find(caches, function(v)
            return v.cache_id == ref.cache_id
        end)
        assert(slot ~= nil, "asdl2_machine.lower_luajit: missing cache slot " .. tostring(ref.cache_id))
        local kind = slot.kind.kind
        if kind == "SingletonKind" then
            return T.Asdl2LuaJIT.SingletonCachePlan(slot.cache_id)
        end
        return T.Asdl2LuaJIT.StructuralCachePlan(slot.cache_id, slot.key_arity)
    end

    local function handle_field_ixs_for(fields)
        local out = {}
        for i = 1, #fields do
            local kind = fields[i].kind
            if kind == "HandleScalarFieldPlan" or kind == "HandleListFieldPlan" then
                out[#out + 1] = i
            end
        end
        return L(out)
    end

    local function access_plan_for(fields)
        local handle_ixs = handle_field_ixs_for(fields)
        if #handle_ixs == 0 then return C(T.Asdl2LuaJIT.InlineOnlyAccess) end
        return T.Asdl2LuaJIT.HandleAccess(handle_ixs)
    end

    local function cache_kind(cache_plan)
        local kind = cache_plan.kind
        if kind == "NoCachePlan" then return "none" end
        if kind == "SingletonCachePlan" then return "singleton" end
        if kind == "StructuralCachePlan" then return "structural" end
        return "other"
    end

    local function field_shape(field)
        local kind = field.kind
        if kind == "InlineFieldPlan" then return "inline" end
        if kind == "HandleScalarFieldPlan" then return "handle_scalar" end
        return "other"
    end

    local function ctor_plan_for(fields, cache_plan)
        local n = #fields
        local cache = cache_kind(cache_plan)

        if n == 0 then
            if cache == "none" then return C(T.Asdl2LuaJIT.NullaryCtorNoCache) end
            if cache == "singleton" then return T.Asdl2LuaJIT.NullaryCtorSingletonCache(cache_plan.cache_id) end
            return T.Asdl2LuaJIT.GenericCtor(L({}), cache_plan)
        end

        if n == 1 then
            local arg1 = field_shape(fields[1])
            if arg1 == "inline" then
                if cache == "none" then return T.Asdl2LuaJIT.Inline1CtorNoCache(1) end
                if cache == "structural" then return T.Asdl2LuaJIT.Inline1CtorStructuralCache(cache_plan.cache_id, 1) end
                return T.Asdl2LuaJIT.GenericCtor(L({ 1 }), cache_plan)
            end
            if arg1 == "handle_scalar" and cache == "none" then
                return T.Asdl2LuaJIT.HandleScalar1CtorNoCache(1)
            end
            return T.Asdl2LuaJIT.GenericCtor(L({ 1 }), cache_plan)
        end

        if n == 2 and field_shape(fields[1]) == "inline" and field_shape(fields[2]) == "inline" then
            if cache == "none" then return T.Asdl2LuaJIT.Inline2CtorNoCache(1, 2) end
            if cache == "structural" then return T.Asdl2LuaJIT.Inline2CtorStructuralCache(cache_plan.cache_id, 1, 2) end
        end

        local arg_ixs = {}
        for i = 1, n do arg_ixs[i] = i end
        return T.Asdl2LuaJIT.GenericCtor(L(arg_ixs), cache_plan)
    end

    local function export_plan_for(record)
        if record.kind == "VariantRecord" and #record.fields == 0 then
            return C(T.Asdl2LuaJIT.NullaryValueExport)
        end
        return C(T.Asdl2LuaJIT.CallableExport)
    end

    local function record_class_for(record, caches)
        local header = record.header
        local fields = field_plans_for(record.fields)
        local cache = cache_plan_for(record, caches)
        local access = access_plan_for(fields)
        local ctor = ctor_plan_for(fields, cache)
        local export = export_plan_for(record)
        local ctype_name = ctype_name_for(header.fqname)

        if record.kind == "ProductRecord" then
            return T.Asdl2LuaJIT.ProductClass(header, ctype_name, fields, cache, access, ctor, export)
        end
        return T.Asdl2LuaJIT.VariantClass(header, ctype_name, fields, cache, access, ctor, export)
    end

    local function record_classes_for(records, caches)
        return L(U.map_into({}, records, function(record)
            return record_class_for(record, caches)
        end))
    end

    local function sum_class_for(sum)
        return T.Asdl2LuaJIT.SumClass(sum.header, sum.variants)
    end

    local function sum_classes_for(sums)
        return L(U.map_into({}, sums, sum_class_for))
    end

    T.Asdl2Machine.Schema.lower_luajit = U.transition(function(schema)
        return T.Asdl2LuaJIT.Schema(
            record_classes_for(schema.param.records, schema.state.caches),
            sum_classes_for(schema.param.sums),
            schema.state.arenas,
            schema.state.caches
        )
    end)
end
