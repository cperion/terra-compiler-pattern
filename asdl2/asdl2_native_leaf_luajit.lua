local ffi = require("ffi")
local unit_core = require("unit_core")

if not rawget(_G, "__asdl2_native_leaf_header_cdef") then
    ffi.cdef[[
        typedef struct {
            uint32_t class_id;
            uint32_t family_id;
            uint32_t variant_tag;
            uint32_t context_id;
        } asdl2_leaf_header_t;
    ]]
    _G.__asdl2_native_leaf_header_cdef = true
end

local M = {}
local ctype_registry = {}
local installed_ctypes = {}
local installed_record_classes = {}
local installed_sum_classes = {}
local context_state_by_id = setmetatable({}, { __mode = "v" })
local next_context_id = 0
local nilkey = {}

unit_core.register_asdl_resolver(function(value)
    if type(value) ~= "cdata" then return nil end
    local ok, ctype = pcall(ffi.typeof, value)
    if not ok then return nil end
    return ctype_registry[tostring(ctype)]
end)

local builtin_checks = {
    number = function(v) return type(v) == "number" end,
    boolean = function(v) return type(v) == "boolean" end,
    string = function(v) return type(v) == "string" end,
    any = function(_) return true end,
    userdata = function(v) return type(v) == "userdata" end,
    cdata = function(v) return type(v) == "cdata" end,
    ["function"] = function(v) return type(v) == "function" end,
}
local optional_check_cache = setmetatable({}, { __mode = "k" })
local list_check_cache = setmetatable({}, { __mode = "k" })
local exact_class_check_cache = {}
local sum_family_check_cache = {}

local function S(v)
    return v
end

local function K(v)
    return v and v.kind
end

local Context = {}
function Context:__index(idx)
    local d = self.definitions[idx] or self.namespaces[idx]
    if d ~= nil then return d end
    return getmetatable(self)[idx]
end

function Context:_SetDefinition(name, value)
    local cache = self.__namespace_cache
    local dot = name:match("^.*()%.")
    if dot == nil then
        self.namespaces[name] = value
        self.definitions[name] = value
        return
    end

    local prefix = name:sub(1, dot - 1)
    local ctx = cache[prefix]
    if ctx == nil then
        ctx = self.namespaces
        local start = 1
        while true do
            local i = name:find(".", start, true)
            if i == nil then break end
            local part = name:sub(start, i - 1)
            local next_ctx = ctx[part]
            if next_ctx == nil then
                next_ctx = {}
                ctx[part] = next_ctx
            end
            ctx = next_ctx
            cache[name:sub(1, i - 1)] = ctx
            if i == dot then break end
            start = i + 1
        end
        cache[prefix] = ctx
    end

    local base = name:sub(dot + 1)
    ctx[base] = value
    self.definitions[name] = value
end

function Context:Extern(name, istype)
    self.extern_checks[name] = istype
end

local function new_class(name)
    return {
        __name = name,
        members = {},
    }
end

local function record_class_isclassof(self, obj)
    return type(obj) == "cdata" and obj.class_id == self.__class_id
end

local function sum_class_isclassof(self, obj)
    return type(obj) == "cdata" and obj.family_id == self.__family_id
end

local function list_values(vs)
    if type(vs) ~= "table" then return nil end
    local n = #vs
    if n > 0 then return vs end
    if next(vs) == nil then return vs end
    local mt = getmetatable(vs)
    if mt and mt.__is_asdl_list then return vs end
    return nil
end

local function checkoptional(checkt)
    local cached = optional_check_cache[checkt]
    if cached ~= nil then return cached end
    cached = function(v)
        return v == nil or checkt(v)
    end
    optional_check_cache[checkt] = cached
    return cached
end

local function checklist(checkt)
    local cached = list_check_cache[checkt]
    if cached ~= nil then return cached end
    cached = function(vs)
        local xs = list_values(vs)
        if not xs then return false end
        for i = 1, #xs do
            if not checkt(xs[i]) then return false end
        end
        return true
    end
    list_check_cache[checkt] = cached
    return cached
end

local function key_for_cache(v)
    return v == nil and nilkey or v
end

local function make_value_arena(kind)
    return {
        kind = kind,
        next_handle = 1,
        values = {},
        by_value = {},
    }
end

local function make_list_arena()
    return {
        kind = "list",
        next_handle = 1,
        values = {},
        by_value = {},
        trie = {},
    }
end

local function canonicalize_list(arena, value)
    local xs = list_values(value)
    if not xs then return value end
    local node = arena.trie
    for i = 1, #xs do
        local e = xs[i]
        local next_node = node[e]
        if not next_node then
            next_node = {}
            node[e] = next_node
        end
        node = next_node
    end
    local canonical = node[nilkey]
    if not canonical then
        canonical = xs
        node[nilkey] = canonical
    end
    return canonical
end

local function arena_value(arena, handle)
    if not arena or handle == nil or handle == 0 then return nil end
    return arena.values[handle]
end

local function arena_normalize(arena, value)
    if value == nil then return nil end
    if arena.kind == "list" then return canonicalize_list(arena, value) end
    return value
end

local function arena_intern(arena, value)
    if value == nil then return 0 end
    local normalized = arena_normalize(arena, value)
    local handle = arena.by_value[normalized]
    if handle ~= nil then return handle end
    handle = arena.next_handle
    arena.next_handle = handle + 1
    arena.by_value[normalized] = handle
    arena.values[handle] = normalized
    return handle
end

local function make_structural_cache(key_arity)
    return {
        kind = "structural",
        key_arity = key_arity,
        root = {},
    }
end

local function cache_get(cache, values, n)
    if cache.kind == "singleton" then
        if cache.present then return cache.value end
        return nil
    end
    local node = cache.root
    for i = 1, n - 1 do
        node = node[key_for_cache(values[i])]
        if node == nil then return nil end
    end
    return node[key_for_cache(values[n])]
end

local function cache_put(cache, values, n, obj)
    if cache.kind == "singleton" then
        cache.present = true
        cache.value = obj
        return obj
    end
    local node = cache.root
    for i = 1, n - 1 do
        local key = key_for_cache(values[i])
        local next_node = node[key]
        if next_node == nil then
            next_node = {}
            node[key] = next_node
        end
        node = next_node
    end
    node[key_for_cache(values[n])] = obj
    return obj
end

local function exact_class_check(class_id)
    local cached = exact_class_check_cache[class_id]
    if cached ~= nil then return cached end
    cached = function(v)
        return type(v) == "cdata" and v.class_id == class_id
    end
    exact_class_check_cache[class_id] = cached
    return cached
end

local function sum_family_check(family_id)
    local cached = sum_family_check_cache[family_id]
    if cached ~= nil then return cached end
    cached = function(v)
        return type(v) == "cdata" and v.family_id == family_id
    end
    sum_family_check_cache[family_id] = cached
    return cached
end

local function build_record_cdef(record)
    local ctype_name = S(record.ctype_name)
    local fields = record.fields
    local n = #fields
    local lines = {
        "typedef struct " .. ctype_name .. " {",
        "  uint32_t class_id;",
        "  uint32_t family_id;",
        "  uint32_t variant_tag;",
        "  uint32_t context_id;",
    }
    if n == 0 then
        lines[6] = "  uint8_t __unit;"
        lines[7] = "} " .. ctype_name .. ";"
        return table.concat(lines, "\n")
    end
    for i = 1, n do
        local field = fields[i]
        local kind = field.kind
        if kind == "InlineFieldPlan" then
            lines[#lines + 1] = "  " .. field.c_type .. " " .. field.slot_name .. ";"
        elseif kind == "HandleScalarFieldPlan" or kind == "HandleListFieldPlan" then
            lines[#lines + 1] = "  " .. field.handle_ctype .. " " .. field.handle_field .. ";"
        else
            error("asdl2_native_leaf_luajit: unknown field plan kind " .. tostring(kind), 2)
        end
    end
    lines[#lines + 1] = "} " .. ctype_name .. ";"
    return table.concat(lines, "\n")
end

local function arena_state_for(install)
    local kind = K(install)
    if kind == "ScalarArenaSlot" then
        return make_value_arena("value")
    elseif kind == "ListArenaSlot" then
        return make_list_arena()
    end
    error("asdl2_native_leaf_luajit: unknown arena family " .. tostring(kind), 2)
end

local function check_key(check)
    local kind = K(check)
    if kind == "AnyCheck" then return "any" end
    if kind == "BuiltinCheck" then return "builtin:" .. S(check.name) end
    if kind == "ExternalCheck" then return "external:" .. S(check.fqname) end
    if kind == "ExactClassCheck" then return "type:" .. S(check.fqname) end
    if kind == "SumFamilyCheck" then return "sum:" .. S(check.fqname) end
    error("asdl2_native_leaf_luajit: unknown check kind " .. tostring(kind), 2)
end

local function arena_state_key(install)
    return K(install) .. ":" .. check_key(install.target) .. ":" .. S(install.handle_ctype)
end

local function cache_state_key(install)
    return K(install.kind) .. ":" .. tostring(install.key_arity) .. ":" .. S(install.owner_fqname)
end

local function cache_state_for(install)
    local kind = K(install.kind)
    if kind == "SingletonKind" then
        return { kind = "singleton", present = false, value = nil }
    elseif kind == "StructuralKind" then
        return make_structural_cache(install.key_arity)
    end
    error("asdl2_native_leaf_luajit: unknown cache kind " .. tostring(kind), 2)
end

local function install_context_state(arenas, caches, ctx)
    local state = rawget(ctx, "__state")
    if state == nil then
        state = {
            arenas = {},
            caches = {},
            arena_slots = {},
            cache_slots = {},
        }
        rawset(ctx, "__state", state)
    end

    for i = 1, #arenas do
        local arena = arenas[i]
        local slot_key = arena_state_key(arena)
        local slot = state.arena_slots[slot_key]
        if slot == nil then
            slot = arena_state_for(arena)
            state.arena_slots[slot_key] = slot
        end
        state.arenas[arena.arena_id] = slot
    end
    for i = 1, #caches do
        local cache = caches[i]
        local slot_key = cache_state_key(cache)
        local slot = state.cache_slots[slot_key]
        if slot == nil then
            slot = cache_state_for(cache)
            state.cache_slots[slot_key] = slot
        end
        state.caches[cache.cache_id] = slot
    end

    context_state_by_id[ctx.__context_id] = state
    return state
end

local function state_for_context_id(context_id)
    return context_state_by_id[context_id]
end

local function arena_for_instance(class, self, arena_id)
    local state = state_for_context_id(self.context_id)
    if state == nil then
        error("asdl2_native_leaf_luajit: missing context state for context_id " .. tostring(self.context_id), 2)
    end
    local arena = state.arenas[arena_id]
    if arena == nil then
        error("asdl2_native_leaf_luajit: missing arena_id '" .. tostring(arena_id) .. "' for " .. tostring(class.__name), 2)
    end
    return arena
end

local function scalar_check_base(ctx, plan)
    local kind = K(plan)
    if kind == "AnyScalarCheck" or kind == "AnyOptionalCheck" or kind == "AnyListCheck" then
        return builtin_checks.any
    elseif kind == "BuiltinScalarCheck" or kind == "BuiltinOptionalCheck" or kind == "BuiltinListCheck" then
        local name = S(plan.name)
        return assert(builtin_checks[name], "unknown builtin check: " .. tostring(name))
    elseif kind == "ExternalScalarCheck" or kind == "ExternalOptionalCheck" or kind == "ExternalListCheck" then
        local name = S(plan.fqname)
        return assert(ctx.extern_checks[name], "unknown extern check: " .. tostring(name))
    elseif kind == "ExactClassScalarCheck" or kind == "ExactClassOptionalCheck" or kind == "ExactClassListCheck" then
        return exact_class_check(plan.class_id)
    elseif kind == "SumFamilyScalarCheck" or kind == "SumFamilyOptionalCheck" or kind == "SumFamilyListCheck" then
        return sum_family_check(plan.family_id)
    end
    error("asdl2_native_leaf_luajit: unknown check plan kind " .. tostring(kind), 2)
end

local function check_plan_fn(ctx, plan)
    local kind = K(plan)
    local scalar = scalar_check_base(ctx, plan)
    if kind == "AnyScalarCheck" or kind == "BuiltinScalarCheck" or kind == "ExternalScalarCheck"
        or kind == "ExactClassScalarCheck" or kind == "SumFamilyScalarCheck" then
        return scalar
    end
    if kind == "AnyOptionalCheck" or kind == "BuiltinOptionalCheck" or kind == "ExternalOptionalCheck"
        or kind == "ExactClassOptionalCheck" or kind == "SumFamilyOptionalCheck" then
        return checkoptional(scalar)
    end
    if kind == "AnyListCheck" or kind == "BuiltinListCheck" or kind == "ExternalListCheck"
        or kind == "ExactClassListCheck" or kind == "SumFamilyListCheck" then
        return checklist(scalar)
    end
    error("asdl2_native_leaf_luajit: unknown check plan kind " .. tostring(kind), 2)
end

local function install_access_runtime(class, record, compiled_fields)
    local kind = K(record.access)
    if kind == "InlineOnlyAccess" then
        class.__has_handle_fields = false
        class.__handle_field_by_name = nil
        class.__handle_arena_id_by_name = nil
        class.__handle_type_name_by_name = nil
        class.__handle_check_by_name = nil
        class.__index = class
        class.__newindex = nil
        return
    end

    local by_name = {}
    local arena_by_name = {}
    local type_by_name = {}
    local check_by_name = {}
    local field_ixs = record.access.field_ixs

    for i = 1, #field_ixs do
        local field = compiled_fields[field_ixs[i]]
        local name = field.name
        by_name[name] = field.handle_field
        arena_by_name[name] = field.arena_id
        type_by_name[name] = field.display_type
        check_by_name[name] = field.check
    end

    class.__has_handle_fields = true
    class.__handle_field_by_name = by_name
    class.__handle_arena_id_by_name = arena_by_name
    class.__handle_type_name_by_name = type_by_name
    class.__handle_check_by_name = check_by_name

    class.__index = function(self, key)
        local value = rawget(class, key)
        if value ~= nil then return value end
        local handle_field = by_name[key]
        if handle_field == nil then return nil end
        local arena = arena_for_instance(class, self, arena_by_name[key])
        return arena_value(arena, self[handle_field])
    end

    class.__newindex = function(self, key, value)
        local handle_field = by_name[key]
        if handle_field == nil then
            error("asdl2_native_leaf_luajit: cannot assign unknown field '" .. tostring(key) .. "' on " .. tostring(class.__name), 2)
        end
        local check = check_by_name[key]
        if not check(value) then
            error(string.format("bad assignment to '%s.%s' expected '%s'", class.__name, key, type_by_name[key]), 2)
        end
        local arena = arena_for_instance(class, self, arena_by_name[key])
        self[handle_field] = arena_intern(arena, value)
    end
end

local function install_class_runtime(class)
    class.members[class] = true
    setmetatable(class, {
        __newindex = function(self, k, v)
            for member, _ in pairs(self.members) do
                rawset(member, k, v)
            end
        end,
        __tostring = function()
            return string.format("Class(%s)", class.__name or "?")
        end,
    })
end

local function cache_runtime(state, cache_plan)
    local kind = K(cache_plan)
    if kind == "NoCachePlan" then return nil end
    if kind == "SingletonCachePlan" then return state.caches[cache_plan.cache_id] end
    if kind == "StructuralCachePlan" then return state.caches[cache_plan.cache_id] end
    error("asdl2_native_leaf_luajit: unknown cache plan kind " .. tostring(kind), 2)
end

local function compile_field(ctx, field, state)
    local kind = K(field)
    local info = {
        kind = kind,
        check = check_plan_fn(ctx, field.check),
        display_type = S(field.display_type),
    }
    if kind == "InlineFieldPlan" then
        info.inline = true
        info.slot_name = S(field.slot_name)
        return info
    end
    info.inline = false
    info.name = S(field.name)
    info.handle_field = S(field.handle_field)
    info.arena_id = field.arena_id
    info.arena = state.arenas[field.arena_id]
    return info
end

local function compile_runtime_fields(ctx, record, state)
    local fields = record.fields
    local out = {}
    for i = 1, #fields do out[i] = compile_field(ctx, fields[i], state) end
    return out
end

local function build_generic_ctor(class, record, compiled_fields, state, context_id)
    local arg_ixs = record.ctor.arg_ixs
    local args = {}
    for i = 1, #arg_ixs do args[i] = compiled_fields[arg_ixs[i]] end
    local n = #args
    local cache = cache_runtime(state, record.ctor.cache)
    local header = class.__header
    local ctor = class.__ctor
    local class_name = class.__name

    local function init_obj(obj)
        obj.class_id = header.class_id
        obj.family_id = header.family_id or 0
        obj.variant_tag = header.variant_tag or 0
        obj.context_id = context_id
        return obj
    end

    return function(_, ...)
        local argc = select("#", ...)
        if argc ~= n then
            error(string.format("bad argument count to '%s': expected %d but found %d", class_name, n, argc), 2)
        end

        local values = {}
        for i = 1, n do
            local info = args[i]
            local v = select(i, ...)
            if not info.check(v) then
                error(string.format("bad argument #%d to '%s' expected '%s'", i, class_name, info.display_type), 2)
            end
            if info.inline then values[i] = v else values[i] = arena_normalize(info.arena, v) end
        end

        if cache ~= nil then
            local existing = cache_get(cache, values, n)
            if existing ~= nil then return existing end
            local obj = init_obj(ctor())
            for i = 1, n do
                local info = args[i]
                if info.inline then obj[info.slot_name] = values[i] else obj[info.handle_field] = arena_intern(info.arena, values[i]) end
            end
            return cache_put(cache, values, n, obj)
        end

        local obj = init_obj(ctor())
        for i = 1, n do
            local info = args[i]
            if info.inline then obj[info.slot_name] = values[i] else obj[info.handle_field] = arena_intern(info.arena, values[i]) end
        end
        return obj
    end
end

local function build_bound_ctor(record, class, compiled_fields, state, context_id)
    local plan = record.ctor
    local kind = K(plan)
    local ctor = class.__ctor
    local header = class.__header
    local class_name = class.__name
    local fields = compiled_fields

    local function init_obj(obj)
        obj.class_id = header.class_id
        obj.family_id = header.family_id or 0
        obj.variant_tag = header.variant_tag or 0
        obj.context_id = context_id
        return obj
    end

    if kind == "NullaryCtorNoCache" then
        return function(_)
            return init_obj(ctor())
        end
    end

    if kind == "NullaryCtorSingletonCache" then
        local cache = state.caches[plan.cache_id]
        return function(_)
            if cache.present then return cache.value end
            local obj = init_obj(ctor())
            cache.present = true
            cache.value = obj
            return obj
        end
    end

    if kind == "Inline1CtorNoCache" then
        local a1 = fields[plan.arg1_ix]
        return function(_, v1)
            if not a1.check(v1) then
                error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, a1.display_type), 2)
            end
            local obj = init_obj(ctor())
            obj[a1.slot_name] = v1
            return obj
        end
    end

    if kind == "Inline1CtorStructuralCache" then
        local a1 = fields[plan.arg1_ix]
        local cache = state.caches[plan.cache_id]
        local root = cache.root
        return function(_, v1)
            if not a1.check(v1) then
                error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, a1.display_type), 2)
            end
            local key1 = key_for_cache(v1)
            local existing = root[key1]
            if existing ~= nil then return existing end
            local obj = init_obj(ctor())
            obj[a1.slot_name] = v1
            root[key1] = obj
            return obj
        end
    end

    if kind == "Inline2CtorNoCache" then
        local a1 = fields[plan.arg1_ix]
        local a2 = fields[plan.arg2_ix]
        return function(_, v1, v2)
            if not a1.check(v1) then
                error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, a1.display_type), 2)
            end
            if not a2.check(v2) then
                error(string.format("bad argument #%d to '%s' expected '%s'", 2, class_name, a2.display_type), 2)
            end
            local obj = init_obj(ctor())
            obj[a1.slot_name] = v1
            obj[a2.slot_name] = v2
            return obj
        end
    end

    if kind == "Inline2CtorStructuralCache" then
        local a1 = fields[plan.arg1_ix]
        local a2 = fields[plan.arg2_ix]
        local cache = state.caches[plan.cache_id]
        local root = cache.root
        return function(_, v1, v2)
            if not a1.check(v1) then
                error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, a1.display_type), 2)
            end
            if not a2.check(v2) then
                error(string.format("bad argument #%d to '%s' expected '%s'", 2, class_name, a2.display_type), 2)
            end
            local key1 = key_for_cache(v1)
            local key2 = key_for_cache(v2)
            local node = root[key1]
            if node ~= nil then
                local existing = node[key2]
                if existing ~= nil then return existing end
            else
                node = {}
                root[key1] = node
            end
            local obj = init_obj(ctor())
            obj[a1.slot_name] = v1
            obj[a2.slot_name] = v2
            node[key2] = obj
            return obj
        end
    end

    if kind == "HandleScalar1CtorNoCache" then
        local a1 = fields[plan.arg1_ix]
        local arena = a1.arena
        if arena.kind == "value" then
            local by_value = arena.by_value
            local values = arena.values
            return function(_, v1)
                if not a1.check(v1) then
                    error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, a1.display_type), 2)
                end
                local obj = init_obj(ctor())
                if v1 == nil then
                    obj[a1.handle_field] = 0
                    return obj
                end
                local handle = by_value[v1]
                if handle == nil then
                    handle = arena.next_handle
                    arena.next_handle = handle + 1
                    by_value[v1] = handle
                    values[handle] = v1
                end
                obj[a1.handle_field] = handle
                return obj
            end
        end
        return function(_, v1)
            if not a1.check(v1) then
                error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, a1.display_type), 2)
            end
            local obj = init_obj(ctor())
            obj[a1.handle_field] = arena_intern(arena, arena_normalize(arena, v1))
            return obj
        end
    end

    if kind == "GenericCtor" then
        return build_generic_ctor(class, record, compiled_fields, state, context_id)
    end

    error("asdl2_native_leaf_luajit: unknown ctor plan kind " .. tostring(kind), 2)
end

local function install_record_class(ctx, record)
    local header = record.header
    local ctype_name = S(record.ctype_name)
    local fqname = S(header.fqname)
    local class = installed_record_classes[ctype_name]
    if class == nil then
        class = new_class(fqname)
        installed_record_classes[ctype_name] = class
    end

    if class.__ctor == nil then
        local ctype = ffi.typeof(ctype_name)
        class.__ctype = ctype
        class.__ctor = ffi.metatype(ctype, class)
        ctype_registry[tostring(ctype)] = class
        install_class_runtime(class)
        class.isclassof = record_class_isclassof
    end

    class.__header = header
    class.__class_id = header.class_id
    class.__family_id = (K(record) == "VariantClass") and header.family_id or 0
    class.__variant_tag = (K(record) == "VariantClass") and header.variant_tag or 0
    class.kind = (K(record) == "VariantClass") and S(header.kind_name) or nil

    return class
end

local function install_sum_class(sum)
    local header = sum.header
    local fqname = S(header.fqname)
    local class = installed_sum_classes[fqname]
    if class == nil then
        class = new_class(fqname)
        installed_sum_classes[fqname] = class
        install_class_runtime(class)
        class.isclassof = sum_class_isclassof
    end
    class.__family_id = header.family_id
    return class
end

local function record_export_index(self, k)
    return self.__class[k]
end

local function record_export_newindex(self, k, v)
    self.__class[k] = v
end

local function record_export_call(self, ...)
    return self.__bound_ctor(self, ...)
end

local function export_tostring(self)
    local class = self.__class or self
    return string.format("Class(%s)", class.__name or "?")
end

local function sum_export_call(self)
    error("cannot construct sum parent '" .. tostring(self.__class.__name) .. "' directly", 2)
end

local RECORD_EXPORT_MT = {
    __index = record_export_index,
    __newindex = record_export_newindex,
    __call = record_export_call,
    __tostring = export_tostring,
}

local SUM_EXPORT_MT = {
    __index = record_export_index,
    __newindex = record_export_newindex,
    __call = sum_export_call,
    __tostring = export_tostring,
}

local function make_record_export(class, bound_ctor)
    return setmetatable({ __class = class, __bound_ctor = bound_ctor }, RECORD_EXPORT_MT)
end

local function make_sum_export(class)
    local exported = class.__sum_export
    if exported ~= nil then return exported end
    exported = setmetatable({ __class = class }, SUM_EXPORT_MT)
    class.__sum_export = exported
    return exported
end

function M.new_context()
    next_context_id = next_context_id + 1
    local namespaces = {}
    return setmetatable({
        definitions = {},
        namespaces = namespaces,
        extern_checks = {},
        __namespace_cache = {},
        __context_id = next_context_id,
        __state = {
            arenas = {},
            caches = {},
            arena_slots = {},
            cache_slots = {},
        },
    }, Context)
end

function M.install(schema, ctx)
    ctx = ctx or M.new_context()
    local records, sums, arenas, caches = schema.records, schema.sums, schema.arenas, schema.caches
    local state = install_context_state(arenas, caches, ctx)

    local cdefs = {}
    for i = 1, #records do
        local record = records[i]
        local ctype_name = S(record.ctype_name)
        if not installed_ctypes[ctype_name] then
            installed_ctypes[ctype_name] = true
            cdefs[#cdefs + 1] = build_record_cdef(record)
        end
    end
    if #cdefs > 0 then
        ffi.cdef(table.concat(cdefs, "\n\n"))
    end

    local classes = {}
    for i = 1, #records do
        local record = records[i]
        local class = install_record_class(ctx, record)
        classes[S(record.header.fqname)] = class
    end
    for i = 1, #sums do
        local sum = sums[i]
        classes[S(sum.header.fqname)] = install_sum_class(sum)
    end

    for _, class in pairs(classes) do
        for k, v in pairs(class) do
            if type(k) == "string" and type(v) == "function"
                and k ~= "isclassof"
                and not k:match("^__") then
                class[k] = nil
            end
        end
        local fresh_members = {}
        fresh_members[class] = true
        class.members = fresh_members
        class.__sum_parent = nil
    end

    for i = 1, #sums do
        local sum = sums[i]
        local parent = classes[S(sum.header.fqname)]
        for j = 1, #sum.variants do
            local variant = sum.variants[j]
            local child = classes[S(variant.fqname)]
            if child ~= nil then
                parent.members[child] = true
                child.__sum_parent = parent
            end
        end
        ctx:_SetDefinition(S(sum.header.fqname), make_sum_export(parent))
    end

    for i = 1, #records do
        local record = records[i]
        local class = classes[S(record.header.fqname)]
        local compiled_fields = compile_runtime_fields(ctx, record, state)
        install_access_runtime(class, record, compiled_fields)
        local bound_ctor = build_bound_ctor(record, class, compiled_fields, state, ctx.__context_id)
        local exported = make_record_export(class, bound_ctor)
        if K(record.export) == "NullaryValueExport" then
            exported = bound_ctor(exported)
        end
        ctx:_SetDefinition(S(record.header.fqname), exported)
    end

    return ctx
end

return M
