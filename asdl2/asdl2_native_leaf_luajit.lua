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
local UINT32 = "uint32_t"

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

local function sanitize(name)
    return (name:gsub("[^%w_]", "_"))
end

local function ctype_name_for_fqname(fqname)
    return "asdl2_" .. sanitize(S(fqname))
end

local function schema_parts(schema)
    if schema.param ~= nil and schema.state ~= nil then
        return schema.param.records, schema.param.sums, schema.state.arenas, schema.state.caches
    end
    return schema.records, schema.sums, schema.arenas, schema.caches
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
    local ctype_name = ctype_name_for_fqname(record.header.fqname)
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
        if kind == "InlineField" then
            lines[#lines + 1] = "  " .. field.c_type .. " " .. field.c_name .. ";"
        elseif kind == "HandleScalarField" or kind == "HandleListField" then
            lines[#lines + 1] = "  " .. field.handle_ctype .. " " .. field.handle_field .. ";"
        else
            error("asdl2_native_leaf_luajit: unknown field kind " .. tostring(kind), 2)
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

local function install_field_runtime(class)
    if class.__has_handle_fields then
        class.__index = function(self, key)
            local value = rawget(class, key)
            if value ~= nil then return value end
            local handle_field = class.__handle_field_by_name[key]
            if handle_field == nil then return nil end
            local arena = arena_for_instance(class, self, class.__handle_arena_id_by_name[key])
            return arena_value(arena, self[handle_field])
        end

        class.__newindex = function(self, key, value)
            local handle_field = class.__handle_field_by_name[key]
            if handle_field == nil then
                error("asdl2_native_leaf_luajit: cannot assign unknown field '" .. tostring(key) .. "' on " .. tostring(class.__name), 2)
            end
            local check = class.__handle_check_by_name[key]
            if not check(value) then
                error(string.format("bad assignment to '%s.%s' expected '%s'", class.__name, key, class.__handle_type_name_by_name[key]), 2)
            end
            local arena = arena_for_instance(class, self, class.__handle_arena_id_by_name[key])
            self[handle_field] = arena_intern(arena, value)
        end
    else
        class.__index = class
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

local function build_bound_ctor(ctx, record, class, state, context_id)
    local header = record.header
    local n = #record.fields
    local checks = class.__field_checks_ordered
    local inline_flags = class.__field_inline_ordered
    local type_names = class.__field_type_name_ordered
    local slot_names = class.__field_slot_name_ordered
    local handle_fields = class.__field_handle_field_ordered
    local arena_ids = class.__field_arena_id_ordered
    local arenas = nil
    local cache_kind = K(record.cache)
    local cache = (cache_kind ~= "NoCacheRef") and state.caches[record.cache.cache_id] or nil
    local ctor = class.__ctor
    local class_name = class.__name

    for i = 1, n do
        local arena_id = arena_ids[i]
        if arena_id ~= nil then
            if arenas == nil then arenas = {} end
            local arena = state.arenas[arena_id]
            if arena == nil then
                error("asdl2_native_leaf_luajit: missing arena_id '" .. tostring(arena_id) .. "' for " .. tostring(class_name), 2)
            end
            arenas[i] = arena
        end
    end

    local is_variant = K(record) == "VariantRecord"
    local class_id = header.class_id
    local family_id = is_variant and header.family_id or 0
    local variant_tag = is_variant and header.variant_tag or 0

    local function init_obj(obj)
        obj.class_id = class_id
        obj.family_id = family_id
        obj.variant_tag = variant_tag
        obj.context_id = context_id
        return obj
    end

    if n == 0 then
        if cache_kind ~= "NoCacheRef" and cache ~= nil and cache.kind == "singleton" then
            return function(_)
                if cache.present then return cache.value end
                local obj = init_obj(ctor())
                cache.present = true
                cache.value = obj
                return obj
            end
        end
        return function(_)
            return init_obj(ctor())
        end
    end

    if n == 1 then
        local check1 = checks[1]
        local inline1 = inline_flags[1]
        local type1 = type_names[1]
        local slot1 = slot_names[1]
        local handle1 = handle_fields[1]
        if cache_kind == "NoCacheRef" and inline1 then
            return function(_, a1)
                if not check1(a1) then
                    error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, type1), 2)
                end
                local obj = init_obj(ctor())
                obj[slot1] = a1
                return obj
            end
        elseif cache_kind == "NoCacheRef" then
            local arena1 = arenas[1]
            if arena1.kind == "value" then
                local by_value = arena1.by_value
                local values = arena1.values
                return function(_, a1)
                    if not check1(a1) then
                        error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, type1), 2)
                    end
                    local obj = init_obj(ctor())
                    if a1 == nil then
                        obj[handle1] = 0
                        return obj
                    end
                    local handle = by_value[a1]
                    if handle == nil then
                        handle = arena1.next_handle
                        arena1.next_handle = handle + 1
                        by_value[a1] = handle
                        values[handle] = a1
                    end
                    obj[handle1] = handle
                    return obj
                end
            end
            return function(_, a1)
                if not check1(a1) then
                    error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, type1), 2)
                end
                local obj = init_obj(ctor())
                obj[handle1] = arena_intern(arena1, arena_normalize(arena1, a1))
                return obj
            end
        elseif inline1 then
            if cache == nil then
                error("asdl2_native_leaf_luajit: missing cache for " .. tostring(class_name), 2)
            end
            if cache.kind == "singleton" then
                return function(_, a1)
                    if not check1(a1) then
                        error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, type1), 2)
                    end
                    if cache.present then return cache.value end
                    local obj = init_obj(ctor())
                    obj[slot1] = a1
                    cache.present = true
                    cache.value = obj
                    return obj
                end
            end
            local root = cache.root
            return function(_, a1)
                if not check1(a1) then
                    error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, type1), 2)
                end
                local key1 = key_for_cache(a1)
                local existing = root[key1]
                if existing ~= nil then return existing end
                local obj = init_obj(ctor())
                obj[slot1] = a1
                root[key1] = obj
                return obj
            end
        end
    elseif n == 2 then
        local check1 = checks[1]
        local check2 = checks[2]
        local inline1 = inline_flags[1]
        local inline2 = inline_flags[2]
        local type1 = type_names[1]
        local type2 = type_names[2]
        local slot1 = slot_names[1]
        local slot2 = slot_names[2]
        if cache_kind == "NoCacheRef" and inline1 and inline2 then
            return function(_, a1, a2)
                if not check1(a1) then
                    error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, type1), 2)
                end
                if not check2(a2) then
                    error(string.format("bad argument #%d to '%s' expected '%s'", 2, class_name, type2), 2)
                end
                local obj = init_obj(ctor())
                obj[slot1] = a1
                obj[slot2] = a2
                return obj
            end
        elseif inline1 and inline2 then
            if cache == nil then
                error("asdl2_native_leaf_luajit: missing cache for " .. tostring(class_name), 2)
            end
            local root = cache.root
            return function(_, a1, a2)
                if not check1(a1) then
                    error(string.format("bad argument #%d to '%s' expected '%s'", 1, class_name, type1), 2)
                end
                if not check2(a2) then
                    error(string.format("bad argument #%d to '%s' expected '%s'", 2, class_name, type2), 2)
                end
                local key1 = key_for_cache(a1)
                local key2 = key_for_cache(a2)
                local node = root[key1]
                if node ~= nil then
                    local existing = node[key2]
                    if existing ~= nil then return existing end
                else
                    node = {}
                    root[key1] = node
                end
                local obj = init_obj(ctor())
                obj[slot1] = a1
                obj[slot2] = a2
                node[key2] = obj
                return obj
            end
        end
    end

    return function(_, ...)
        local argc = select("#", ...)
        if argc ~= n then
            error(string.format("bad argument count to '%s': expected %d but found %d", class_name, n, argc), 2)
        end

        local values = {}
        for i = 1, n do
            local v = select(i, ...)
            if not checks[i](v) then
                error(string.format("bad argument #%d to '%s' expected '%s'", i, class_name, type_names[i]), 2)
            end
            values[i] = inline_flags[i] and v or arena_normalize(arenas[i], v)
        end

        if cache_kind ~= "NoCacheRef" then
            if cache == nil then
                error("asdl2_native_leaf_luajit: missing cache for " .. tostring(class_name), 2)
            end
            local existing = cache_get(cache, values, n)
            if existing ~= nil then return existing end
            local obj = init_obj(ctor())
            for i = 1, n do
                if inline_flags[i] then
                    obj[slot_names[i]] = values[i]
                else
                    obj[handle_fields[i]] = arena_intern(arenas[i], values[i])
                end
            end
            return cache_put(cache, values, n, obj)
        end

        local obj = init_obj(ctor())
        for i = 1, n do
            if inline_flags[i] then
                obj[slot_names[i]] = values[i]
            else
                obj[handle_fields[i]] = arena_intern(arenas[i], values[i])
            end
        end
        return obj
    end
end

local function install_record_class(ctx, record)
    local header = record.header
    local ctype_name = ctype_name_for_fqname(header.fqname)
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
        class.__handle_field_by_name = {}
        class.__handle_arena_id_by_name = {}
        class.__handle_type_name_by_name = {}
        class.__handle_check_by_name = {}
        class.__field_checks_ordered = {}
        class.__field_inline_ordered = {}
        class.__field_type_name_ordered = {}
        class.__field_slot_name_ordered = {}
        class.__field_handle_field_ordered = {}
        class.__field_arena_id_ordered = {}
        class.__has_handle_fields = false
        for i = 1, #record.fields do
            local field = record.fields[i]
            local field_kind = field.kind
            local field_name = S(field.name)
            local check_node = field.check
            local check_kind = K(check_node)
            local scalar_check

            if check_kind == "AnyCheck" then
                scalar_check = builtin_checks.any
            elseif check_kind == "BuiltinCheck" then
                local name = S(check_node.name)
                scalar_check = assert(builtin_checks[name], "unknown builtin check: " .. tostring(name))
            elseif check_kind == "ExternalCheck" then
                local name = S(check_node.fqname)
                scalar_check = assert(ctx.extern_checks[name], "unknown extern check: " .. tostring(name))
            elseif check_kind == "ExactClassCheck" then
                scalar_check = exact_class_check(check_node.class_id)
            elseif check_kind == "SumFamilyCheck" then
                scalar_check = sum_family_check(check_node.family_id)
            else
                error("asdl2_native_leaf_luajit: unknown check kind " .. tostring(check_kind), 2)
            end

            local type_name = S(field.type_name)
            local check = scalar_check
            local is_inline = field_kind == "InlineField"
            local handle_field = nil
            local arena_id = nil
            local slot_name = nil

            if is_inline then
                slot_name = field.c_name
            elseif field_kind == "HandleListField" then
                type_name = type_name .. "*"
                check = checklist(scalar_check)
                handle_field = field.handle_field
                arena_id = field.arena_id
                class.__has_handle_fields = true
            elseif field_kind == "HandleScalarField" then
                if K(field.cardinality) == "Optional" then
                    type_name = type_name .. "?"
                    check = checkoptional(scalar_check)
                end
                handle_field = field.handle_field
                arena_id = field.arena_id
                class.__has_handle_fields = true
            else
                error("asdl2_native_leaf_luajit: unknown field kind " .. tostring(field_kind), 2)
            end

            class.__field_checks_ordered[i] = check
            class.__field_inline_ordered[i] = is_inline
            class.__field_type_name_ordered[i] = type_name
            class.__field_slot_name_ordered[i] = slot_name
            class.__field_handle_field_ordered[i] = handle_field
            class.__field_arena_id_ordered[i] = arena_id

            if not is_inline then
                class.__handle_field_by_name[field_name] = handle_field
                class.__handle_arena_id_by_name[field_name] = arena_id
                class.__handle_type_name_by_name[field_name] = type_name
                class.__handle_check_by_name[field_name] = check
            end
        end
        install_field_runtime(class)
        install_class_runtime(class)
        class.isclassof = record_class_isclassof
    end

    class.__class_id = header.class_id
    class.__family_id = (K(record) == "VariantRecord") and header.family_id or 0
    class.__variant_tag = (K(record) == "VariantRecord") and header.variant_tag or 0
    class.kind = (K(record) == "VariantRecord") and S(header.kind_name) or nil

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
    local records, sums, arenas, caches = schema_parts(schema)
    local state = install_context_state(arenas, caches, ctx)

    local cdefs = {}
    for i = 1, #records do
        local record = records[i]
        local ctype_name = ctype_name_for_fqname(record.header.fqname)
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
        local bound_ctor = build_bound_ctor(ctx, record, class, state, ctx.__context_id)
        local exported = make_record_export(class, bound_ctor)
        if K(record) == "VariantRecord" and #record.fields == 0 then
            exported = bound_ctor(exported)
        end
        ctx:_SetDefinition(S(record.header.fqname), exported)
    end

    return ctx
end

return M
