-- asdl.lua
--
-- Single-file ASDL implementation.
--
-- Structure:
--   1. tiny list helper
--   2. LuaJIT leaf installer/runtime
--   3. handwritten internal IR types for the ASDL language itself
--   4. pure ASDL compiler: parse -> resolve -> lower -> emit
--   5. public API
--
-- Public API:
--   asdl.List(xs?)
--   asdl.parse(text)
--   asdl.resolve(source_spec)
--   asdl.lower_luajit(resolved_spec, opts?)
--   asdl.emit_luajit(layout_spec)
--   asdl.compile_luajit(layout_spec, ctx?)
--   asdl.NewContext(opts?)
--   asdl.bootstrap_context()               -- returns handwritten internal IR
--   asdl.compile_into(ctx, lowered)        -- low-level leaf hook
--   asdl.new_leaf_context()                -- low-level leaf hook

local ffi = require("ffi")
local unit_core = require("unit_core")
local U = unit_core.new()

-- ═══════════════════════════════════════════════════════════════
-- 1. LIST HELPER
-- ═══════════════════════════════════════════════════════════════

local function asdl_list_insert(self, value)
    self[#self + 1] = value
    return self
end

local function List(xs)
    local ys = xs or {}
    if ys.insert == nil then ys.insert = asdl_list_insert end
    return setmetatable(ys, { __is_asdl_list = true })
end

-- ═══════════════════════════════════════════════════════════════
-- 2. LUAJIT LEAF
-- ═══════════════════════════════════════════════════════════════

local leaf = {}
local ctype_registry = {}
local next_context_id = 0

-- Leaf responsibility:
--   lowered runtime plan -> installed LuaJIT/FFI constructors/classes

unit_core.register_asdl_resolver(function(value)
    if type(value) ~= "cdata" then return nil end
    local ok, ctype = pcall(ffi.typeof, value)
    if not ok then return nil end
    return ctype_registry[tostring(ctype)]
end)

-- Leaf-local validation helpers.
local builtin_checks = {
    number = function(v) return type(v) == "number" end,
    boolean = function(v) return type(v) == "boolean" end,
    string = function(v) return type(v) == "string" end,
}

local valuekey = {}
local nilkey = {}

local function basename(name)
    return name:match("([^.]*)$")
end

local function deepcopy_field(f)
    local r = {}
    for k, v in pairs(f) do r[k] = v end
    return r
end

local function deepcopy_fields(fields)
    local out = {}
    for i = 1, #fields do
        out[i] = deepcopy_field(fields[i])
    end
    return out
end

local function reporterr(i, name, tn, v, ii)
    local fmt = "bad argument #%d to '%s' expected '%s' but found '%s'"
    if ii then
        if type(v) == "table" then v = v[ii] end
        fmt = fmt .. " at list index %d"
    end
    local err = string.format(fmt, i, name, tn, type(v), ii)
    error(err, 3)
end

local Context = {}
function Context:__index(idx)
    local d = self.definitions[idx] or self.namespaces[idx]
    if d ~= nil then return d end
    return getmetatable(self)[idx]
end

function Context:_SetDefinition(name, value)
    local ctx = self.namespaces
    for part in name:gmatch("([^.]*)%.") do
        ctx[part] = ctx[part] or {}
        ctx = ctx[part]
    end
    local base = basename(name)
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

local function install_class_runtime(class, construct)
    class.__index = class.__index or class
    class.members[class] = true

    setmetatable(class, {
        __call = function(self, ...)
            return construct(self, ...)
        end,
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

local function list_values(vs)
    if type(vs) ~= "table" then return nil end
    local n = #vs
    if n > 0 then return vs end
    if next(vs) == nil then return vs end
    local mt = getmetatable(vs)
    if mt and mt.__is_asdl_list then return vs end
    return nil
end

local function checklist(checkt)
    return function(vs)
        local xs = list_values(vs)
        if not xs then return false end
        for i = 1, #xs do
            if not checkt(xs[i]) then return false, i end
        end
        return true
    end
end

local function checkoptional(checkt)
    return function(v)
        return v == nil or checkt(v)
    end
end

local function checkuniquelist(checkt, listcache)
    return function(vs)
        local xs = list_values(vs)
        if not xs then return false end
        local node = listcache
        for i = 1, #xs do
            local e = xs[i]
            if not checkt(e) then return false, i end
            local next_node = node[e]
            if not next_node then
                next_node = {}
                node[e] = next_node
            end
            node = next_node
        end
        local r = node[valuekey]
        if not r then
            r = xs
            node[valuekey] = r
        end
        return true, r
    end
end

local function build_scalar_check(ctx, type_name)
    if builtin_checks[type_name] then return builtin_checks[type_name], type_name end
    if ctx.extern_checks[type_name] then return ctx.extern_checks[type_name], type_name end
    local class = ctx.definitions[type_name]
    if type(class) == "table" and (type(class.isclassof) == "function" or type(class.members) == "table") then
        return function(v)
            return class:isclassof(v)
        end, type_name
    end
    error("asdl_luajit: unknown field type '" .. tostring(type_name) .. "'")
end

local function build_check(ctx, field, unique, listcache)
    local check, tn = build_scalar_check(ctx, field.type)
    if field.list then
        return (unique and checkuniquelist(check, listcache or {}) or checklist(check)), tn .. "*"
    end
    if field.optional then
        return checkoptional(check), tn .. "?"
    end
    return check, tn
end

local function build_tostring(class)
    return function(self)
        local members = {}
        local fields = class.__fields or {}
        for i = 1, #fields do
            local f = fields[i]
            members[#members + 1] = string.format("%s = %s", f.name, tostring(self[f.name]))
        end
        return string.format("%s(%s)", class.__name, table.concat(members, ","))
    end
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
    local canonical = node[valuekey]
    if not canonical then
        canonical = xs
        node[valuekey] = canonical
    end
    return canonical
end

local function arena_value(arena, handle)
    if not arena or handle == nil or handle == 0 then return nil end
    return arena.values[handle]
end

local function arena_intern(arena, value)
    if value == nil then return 0 end
    local normalized = arena.kind == "list" and canonicalize_list(arena, value) or value
    local handle = arena.by_value[normalized]
    if handle ~= nil then return handle end
    handle = arena.next_handle
    arena.next_handle = handle + 1
    arena.by_value[normalized] = handle
    arena.values[handle] = normalized
    return handle
end

local function key_for_cache(v)
    return v == nil and nilkey or v
end

local SPECIALIZED_CTOR_LIMIT = 20
local specialized_ctor_factories = {}

local function compile_chunk(source, chunkname)
    local loader = loadstring or load
    local fn, err = loader(source, chunkname)
    if not fn then error(err, 2) end
    return fn
end

local function specialized_ctor_factory(field_count, has_cache)
    local cache_key = (has_cache and "cache:" or "plain:") .. tostring(field_count)
    local existing = specialized_ctor_factories[cache_key]
    if existing ~= nil then return existing end

    local args = {}
    local lines = {}
    for i = 1, field_count do
        args[i] = "a" .. tostring(i)
        lines[#lines + 1] = string.format("a%d = validate(%d, a%d)", i, i, i)
    end

    if has_cache then
        lines[#lines + 1] = "local node = cache"
        for i = 1, field_count - 1 do
            lines[#lines + 1] = string.format("local k%d = key_for_cache(a%d)", i, i)
            lines[#lines + 1] = string.format("local n%d = node[k%d]", i, i)
            lines[#lines + 1] = string.format("if not n%d then n%d = {}; node[k%d] = n%d end", i, i, i, i)
            lines[#lines + 1] = string.format("node = n%d", i)
        end
        lines[#lines + 1] = string.format("local k%d = key_for_cache(a%d)", field_count, field_count)
        lines[#lines + 1] = string.format("local existing = node[k%d]", field_count)
        lines[#lines + 1] = "if existing ~= nil then return existing end"
    end

    lines[#lines + 1] = "local obj = ctor()"
    for i = 1, field_count do
        lines[#lines + 1] = string.format("assign(obj, %d, a%d)", i, i)
    end

    if has_cache then
        lines[#lines + 1] = string.format("node[k%d] = obj", field_count)
    end
    lines[#lines + 1] = "return obj"

    local source = string.format(
        "return function(validate, assign, ctor, cache, key_for_cache) return function(_, %s) %s end end",
        table.concat(args, ", "),
        table.concat(lines, " ")
    )

    local factory = compile_chunk(source, "asdl_specialized_ctor_" .. cache_key)()
    specialized_ctor_factories[cache_key] = factory
    return factory
end

local function build_ctor(self_name, ctor, cache, field_count, checks, type_names, field_names, handle_fields, inline_flags, intern_handle)
    local function assign(obj, i, value)
        if inline_flags[i] then
            obj[field_names[i]] = value
        else
            obj[handle_fields[i]] = intern_handle(field_names[i], value)
        end
    end

    local function validate(i, value)
        local ok, normalized = checks[i](value)
        if not ok then reporterr(i, self_name(), type_names[i], value, normalized) end
        return normalized or value
    end

    if field_count == 0 then
        if cache then
            return function()
                local existing = cache[valuekey]
                if existing ~= nil then return existing end
                local obj = ctor()
                cache[valuekey] = obj
                return obj
            end
        end
        return function()
            return ctor()
        end
    end

    if field_count == 1 then
        if cache then
            return function(_, a1)
                a1 = validate(1, a1)
                local k1 = key_for_cache(a1)
                local existing = cache[k1]
                if existing ~= nil then return existing end
                local obj = ctor()
                assign(obj, 1, a1)
                cache[k1] = obj
                return obj
            end
        end
        return function(_, a1)
            a1 = validate(1, a1)
            local obj = ctor()
            assign(obj, 1, a1)
            return obj
        end
    end

    if field_count == 2 then
        if cache then
            return function(_, a1, a2)
                a1 = validate(1, a1)
                a2 = validate(2, a2)
                local k1 = key_for_cache(a1)
                local node = cache[k1]
                if not node then
                    node = {}
                    cache[k1] = node
                end
                local k2 = key_for_cache(a2)
                local existing = node[k2]
                if existing ~= nil then return existing end
                local obj = ctor()
                assign(obj, 1, a1)
                assign(obj, 2, a2)
                node[k2] = obj
                return obj
            end
        end
        return function(_, a1, a2)
            a1 = validate(1, a1)
            a2 = validate(2, a2)
            local obj = ctor()
            assign(obj, 1, a1)
            assign(obj, 2, a2)
            return obj
        end
    end

    if field_count == 3 then
        if cache then
            return function(_, a1, a2, a3)
                a1 = validate(1, a1)
                a2 = validate(2, a2)
                a3 = validate(3, a3)
                local k1 = key_for_cache(a1)
                local n1 = cache[k1]
                if not n1 then
                    n1 = {}
                    cache[k1] = n1
                end
                local k2 = key_for_cache(a2)
                local n2 = n1[k2]
                if not n2 then
                    n2 = {}
                    n1[k2] = n2
                end
                local k3 = key_for_cache(a3)
                local existing = n2[k3]
                if existing ~= nil then return existing end
                local obj = ctor()
                assign(obj, 1, a1)
                assign(obj, 2, a2)
                assign(obj, 3, a3)
                n2[k3] = obj
                return obj
            end
        end
        return function(_, a1, a2, a3)
            a1 = validate(1, a1)
            a2 = validate(2, a2)
            a3 = validate(3, a3)
            local obj = ctor()
            assign(obj, 1, a1)
            assign(obj, 2, a2)
            assign(obj, 3, a3)
            return obj
        end
    end

    if field_count <= SPECIALIZED_CTOR_LIMIT then
        local factory = specialized_ctor_factory(field_count, cache ~= nil)
        return factory(validate, assign, ctor, cache, key_for_cache)
    end

    return function(_, ...)
        local values = {}
        for iarg = 1, field_count do
            local v = select(iarg, ...)
            local ok, normalized = checks[iarg](v)
            if not ok then reporterr(iarg, self_name(), type_names[iarg], v, normalized) end
            values[iarg] = normalized or v
        end

        if cache then
            local node = cache
            for iarg = 1, field_count - 1 do
                local key = key_for_cache(values[iarg])
                local next_node = node[key]
                if not next_node then
                    next_node = {}
                    node[key] = next_node
                end
                node = next_node
            end
            local last_key = key_for_cache(values[field_count])
            local existing = node[last_key]
            if existing ~= nil then return existing end
            local obj = ctor()
            for ifield = 1, field_count do assign(obj, ifield, values[ifield]) end
            node[last_key] = obj
            return obj
        end

        local obj = ctor()
        for ifield = 1, field_count do assign(obj, ifield, values[ifield]) end
        return obj
    end
end

-- Install one lowered backend plan into a context.
function leaf.compile_into(ctx, lowered)
    if #lowered.cdefs > 0 then
        ffi.cdef(table.concat(lowered.cdefs, "\n\n"))
    end

    local classes = {}

    for i = 1, #lowered.records do
        local record = lowered.records[i]
        classes[record.fqname] = new_class(record.fqname)
    end

    for fqname, layout in pairs(lowered.definitions) do
        if layout.kind == "sum" and not classes[fqname] then
            classes[fqname] = new_class(fqname)
        end
    end

    for fqname, class in pairs(classes) do
        ctx:_SetDefinition(fqname, class)
    end

    for i = 1, #lowered.records do
        local record = lowered.records[i]
        local class = classes[record.fqname]
        class.__fields = deepcopy_fields(record.fields)
        class.kind = record.kind_name
        class.__field_meta = {}
        class.__field_checks = {}
        class.__arenas = {}

        local fields = record.fields
        local field_count = #fields
        local checks = {}
        local type_names = {}
        local field_names = {}
        local handle_fields = {}
        local inline_flags = {}
        local listcache = {}
        local has_handle_fields = false

        for j = 1, field_count do
            local field = fields[j]
            local check, tn = build_check(ctx, field, record.unique, listcache)
            checks[j] = check
            type_names[j] = field.display_type or tn
            field_names[j] = field.name
            handle_fields[j] = field.handle_field
            inline_flags[j] = field.inline and true or false
            class.__field_checks[field.name] = check
            class.__field_meta[field.name] = {
                inline = field.inline and true or false,
                handle_field = field.handle_field,
                storage_kind = field.storage_kind,
                type_name = field.display_type or field.type,
            }
            if field.handle_field then
                has_handle_fields = true
                class.__arenas[field.name] = (field.arena_kind or field.storage_kind) == "list"
                    and make_list_arena()
                    or make_value_arena(field.arena_kind or field.storage_kind)
            end
        end

        local function resolve_handle(key, handle)
            return arena_value(class.__arenas[key], handle)
        end

        local function intern_handle(key, value)
            local arena = class.__arenas[key]
            if not arena then
                error("asdl_luajit: no arena for field '" .. tostring(key) .. "' on " .. tostring(class.__name), 2)
            end
            return arena_intern(arena, value)
        end

        if has_handle_fields then
            class.__index = function(self, key)
                local value = class[key]
                if value ~= nil then return value end
                local meta = class.__field_meta[key]
                if not meta then return nil end
                if meta.inline then return nil end
                return resolve_handle(key, self[meta.handle_field])
            end

            class.__newindex = function(self, key, value)
                local meta = class.__field_meta[key]
                if not meta then
                    error("asdl_luajit: cannot assign unknown field '" .. tostring(key) .. "' on " .. tostring(class.__name), 2)
                end
                if meta.inline then
                    error("asdl_luajit: cannot assign inline field through __newindex '" .. tostring(key) .. "' on " .. tostring(class.__name), 2)
                end
                local check = class.__field_checks[key]
                local ok, normalized = check(value)
                if not ok then
                    reporterr(1, class.__name .. "." .. key, meta.type_name, value)
                end
                self[meta.handle_field] = intern_handle(key, normalized or value)
            end
        else
            class.__index = class
        end

        local ctype = ffi.typeof(record.ctype_name)
        class.__ctype = ctype
        class.__ctor = ffi.metatype(ctype, class)
        class.__tostring = build_tostring(class)
        ctype_registry[tostring(ctype)] = class

        local cache = record.unique and {} or nil
        local ctor_name = function() return class.__name end

        install_class_runtime(class, build_ctor(
            ctor_name,
            class.__ctor,
            cache,
            field_count,
            checks,
            type_names,
            field_names,
            handle_fields,
            inline_flags,
            intern_handle
        ))

        function class:isclassof(obj)
            return type(obj) == "cdata" and ffi.istype(class.__ctype, obj) or false
        end
    end

    for fqname, layout in pairs(lowered.definitions) do
        if layout.kind == "sum" then
            local parent = classes[fqname]
            parent.__variants = {}
            install_class_runtime(parent, function()
                error("cannot construct sum parent '" .. fqname .. "' directly", 2)
            end)

            for i = 1, #layout.variants do
                local variant_layout = layout.variants[i]
                local child = classes[variant_layout.fqname]
                child.__sum_parent = parent
                parent.members[child] = true
                parent.__variants[#parent.__variants + 1] = variant_layout.kind_name
            end

            table.sort(parent.__variants)

            local variant_ctypes = {}
            for child, _ in pairs(parent.members) do
                if child ~= parent and child.__ctype then
                    variant_ctypes[#variant_ctypes + 1] = child.__ctype
                end
            end

            function parent:isclassof(obj)
                if type(obj) ~= "cdata" then return false end
                for i = 1, #variant_ctypes do
                    if ffi.istype(variant_ctypes[i], obj) then return true end
                end
                return false
            end

            ctx:_SetDefinition(fqname, parent)
        end
    end

    for i = 1, #lowered.records do
        local record = lowered.records[i]
        local class = classes[record.fqname]
        local exported = class
        if record.kind_name and #record.fields == 0 then
            exported = class()
        end
        ctx:_SetDefinition(record.fqname, exported)
    end

    return ctx
end

-- Create an empty leaf context. Compiler contexts layer Define(...) on top.
function leaf.NewContext()
    next_context_id = next_context_id + 1
    return setmetatable({
        definitions = {},
        namespaces = {},
        extern_checks = {},
        __context_id = next_context_id,
    }, Context)
end


-- ═══════════════════════════════════════════════════════════════
-- 3. HANDWRITTEN INTERNAL IR TYPES
-- ═══════════════════════════════════════════════════════════════

local function ir_record_ctor(kind, names)
    return function(...)
        local node = { kind = kind }
        for i = 1, #names do
            node[names[i]] = select(i, ...)
        end
        return node
    end
end

local function ir_singleton(kind)
    return { kind = kind }
end

local function build_internal_ir()
    local Asdl = {
        Source = {},
        Resolved = {},
        LuaJit = {},
    }

    local S = Asdl.Source
    S.Spec = ir_record_ctor("Spec", { "definitions" })
    S.SourceModuleDef = ir_record_ctor("SourceModuleDef", { "name", "definitions" })
    S.SourceTypeDef = ir_record_ctor("SourceTypeDef", { "name", "type_expr" })
    S.SourceProduct = ir_record_ctor("SourceProduct", { "fields", "unique_flag" })
    S.SourceSum = ir_record_ctor("SourceSum", { "constructors", "attribute_fields" })
    S.Constructor = ir_record_ctor("Constructor", { "name", "fields", "unique_flag" })
    S.Field = ir_record_ctor("Field", { "type_ref", "arity", "name" })
    S.BuiltinTypeRef = ir_record_ctor("BuiltinTypeRef", { "name" })
    S.NamedTypeRef = ir_record_ctor("NamedTypeRef", { "parts" })
    S.ArityOne = ir_singleton("ArityOne")
    S.ArityOptional = ir_singleton("ArityOptional")
    S.ArityMany = ir_singleton("ArityMany")

    local R = Asdl.Resolved
    R.Spec = ir_record_ctor("Spec", { "definitions" })
    R.ResolvedModuleDef = ir_record_ctor("ResolvedModuleDef", { "fqname", "definitions" })
    R.ResolvedTypeDef = ir_record_ctor("ResolvedTypeDef", { "fqname", "type_expr" })
    R.ResolvedProduct = ir_record_ctor("ResolvedProduct", { "fields", "unique_flag" })
    R.ResolvedSum = ir_record_ctor("ResolvedSum", { "constructors", "attribute_fields" })
    R.Constructor = ir_record_ctor("Constructor", { "fqname", "kind_name", "fields", "unique_flag" })
    R.Field = ir_record_ctor("Field", { "type_ref", "arity", "name" })
    R.ResolvedBuiltinTypeRef = ir_record_ctor("ResolvedBuiltinTypeRef", { "name" })
    R.ResolvedDefinedTypeRef = ir_record_ctor("ResolvedDefinedTypeRef", { "fqname" })
    R.ResolvedArityOne = ir_singleton("ResolvedArityOne")
    R.ResolvedArityOptional = ir_singleton("ResolvedArityOptional")
    R.ResolvedArityMany = ir_singleton("ResolvedArityMany")

    local LJ = Asdl.LuaJit
    LJ.Spec = ir_record_ctor("Spec", { "types" })
    LJ.ProductLayout = ir_record_ctor("ProductLayout", { "fqname", "ctype_name", "slots", "unique_flag" })
    LJ.SumLayout = ir_record_ctor("SumLayout", { "fqname", "tag_ctype", "variants" })
    LJ.VariantLayout = ir_record_ctor("VariantLayout", { "fqname", "kind_name", "tag_value", "ctype_name", "slots", "unique_flag" })
    LJ.Slot = ir_record_ctor("Slot", { "name", "source_type_name", "slot_type", "optional_flag" })
    LJ.ScalarSlotType = ir_record_ctor("ScalarSlotType", { "c_name" })
    LJ.RefSlotType = ir_record_ctor("RefSlotType", { "target_ctype" })
    LJ.ListRefSlotType = ir_record_ctor("ListRefSlotType", { "elem_ctype" })

    return { Asdl = Asdl }
end

local INTERNAL_IR = build_internal_ir()

-- ═══════════════════════════════════════════════════════════════
-- 4. PURE ASDL COMPILER
-- ═══════════════════════════════════════════════════════════════

local compiler = {}

-- Compiler responsibility:
--   text -> Source ASDL -> Resolved ASDL -> LuaJIT layout ASDL -> lowered leaf plan

-- Small pure helpers used throughout the compiler stages.
-- L: normalize iterable -> plain array.
local function L(xs)
    return U.copy(xs or {})
end

-- S: normalize string-like cdata -> Lua string.
local function S(v)
    if type(v) == "cdata" then return ffi.string(v) end
    return v
end

local function join_parts(parts)
    return table.concat(U.map(parts, function(part) return S(part) end), ".")
end

local function sanitize(name)
    return (name:gsub("[^%w_]", "_"))
end

local function T()
    return INTERNAL_IR.Asdl
end

local builtin_names = {
    ["nil"] = true,
    number = true,
    string = true,
    boolean = true,
    table = true,
    thread = true,
    userdata = true,
    cdata = true,
    ["function"] = true,
    any = true,
}

local function source_typeref(parts)
    local S = T().Source
    local joined = join_parts(parts)
    if #parts == 1 and builtin_names[joined] then
        return S.BuiltinTypeRef(joined)
    end
    return S.NamedTypeRef(L(parts))
end

local tokens = "=|?*,(){}."
local keywords = { attributes = true, unique = true, module = true }
for i = 1, #tokens do
    keywords[tokens:sub(i, i)] = true
end

-- Stage 1: raw text -> Asdl.Source.Spec
compiler.parse = U.transition("asdl_asdl.parse", function(text)
    local S = T().Source
    local pos = 1
    local cur = nil
    local value = nil

    local function err(what)
        error(string.format("expected %s but found '%s' here:\n%s", what, value,
            text:sub(1, pos) .. "<--##    " .. text:sub(pos + 1, -1)))
    end

    local function skip(pattern)
        local matched = text:match(pattern, pos)
        pos = pos + #matched
        if pos <= #text then return false end
        cur, value = "EOF", "EOF"
        return true
    end

    local function next_token()
        if skip("^%s*") then return end

        local c = text:sub(pos, pos)
        if c == "#" then
            if skip("^[^\n]*\n") then return end
            return next_token()
        end

        if keywords[c] then
            cur, value, pos = c, c, pos + 1
            return
        end

        local ident = text:match("^[%a_][%a_%d]*", pos)
        if not ident then
            value = text:sub(pos, pos)
            err("valid token")
        end

        cur, value = keywords[ident] and ident or "Ident", ident
        pos = pos + #ident
    end

    local function nextif(kind)
        if cur ~= kind then return false end
        next_token()
        return true
    end

    local function expect(kind)
        if cur ~= kind then err(kind) end
        local v = value
        next_token()
        return v
    end

    local function parse_parts()
        local parts = { expect("Ident") }
        while nextif(".") do
            parts[#parts + 1] = expect("Ident")
        end
        return parts
    end

    local function parse_arity()
        if nextif("?") then return S.ArityOptional end
        if nextif("*") then return S.ArityMany end
        return S.ArityOne
    end

    local function parse_field()
        local parts = parse_parts()
        local arity = parse_arity()
        local name = expect("Ident")
        return S.Field(source_typeref(parts), arity, name)
    end

    local function parse_fields()
        expect("(")
        local fields = {}
        if cur ~= ")" then
            repeat
                fields[#fields + 1] = parse_field()
            until not nextif(",")
        end
        expect(")")
        return L(fields)
    end

    local function parse_product()
        local fields = parse_fields()
        local unique_flag = nextif("unique") and true or false
        return S.SourceProduct(fields, unique_flag)
    end

    local function parse_constructor()
        local name = expect("Ident")
        local fields = cur == "(" and parse_fields() or L()
        local unique_flag = nextif("unique") and true or false
        return S.Constructor(name, fields, unique_flag)
    end

    local function parse_sum()
        local ctors = { parse_constructor() }
        while nextif("|") do
            ctors[#ctors + 1] = parse_constructor()
        end
        local attribute_fields = nextif("attributes") and parse_fields() or L()
        return S.SourceSum(L(ctors), attribute_fields)
    end

    local function parse_type_expr()
        if cur == "(" then return parse_product() end
        return parse_sum()
    end

    local parse_definitions

    local function parse_module_def()
        expect("module")
        local name = expect("Ident")
        expect("{")
        local definitions = parse_definitions()
        expect("}")
        return S.SourceModuleDef(name, definitions)
    end

    local function parse_type_def()
        local name = expect("Ident")
        expect("=")
        return S.SourceTypeDef(name, parse_type_expr())
    end

    function parse_definitions()
        local defs = {}
        while cur ~= "EOF" and cur ~= "}" do
            defs[#defs + 1] = (cur == "module") and parse_module_def() or parse_type_def()
        end
        return L(defs)
    end

    next_token()
    local spec = S.Spec(parse_definitions())
    expect("EOF")
    return spec
end)

local function collect_type_fqnames(definitions, prefix, index)
    index = index or {}
    return U.fold(definitions, function(acc, definition)
        return U.match(definition, {
            SourceModuleDef = function(v)
                local next_prefix = prefix == "" and S(v.name) or (prefix .. "." .. S(v.name))
                return collect_type_fqnames(v.definitions, next_prefix, acc)
            end,

            SourceTypeDef = function(v)
                local fqname = prefix == "" and S(v.name) or (prefix .. "." .. S(v.name))
                acc[fqname] = true
                return acc
            end,
        })
    end, index)
end

local function resolve_fqname(index, ns_parts, named_parts)
    local joined = join_parts(named_parts)

    if index[joined] then return joined end

    for i = #ns_parts, 1, -1 do
        local prefix = table.concat(ns_parts, ".", 1, i)
        local candidate = prefix == "" and joined or (prefix .. "." .. joined)
        if index[candidate] then return candidate end
    end

    error("asdl_asdl.resolve: unknown type ref '" .. joined .. "'")
end

local function resolved_arity(arity)
    local R = T().Resolved
    return U.match(arity, {
        ArityOne = function() return R.ResolvedArityOne end,
        ArityOptional = function() return R.ResolvedArityOptional end,
        ArityMany = function() return R.ResolvedArityMany end,
    })
end

local function resolve_type_ref(index, ns_parts, type_ref)
    local R = T().Resolved
    return U.match(type_ref, {
        BuiltinTypeRef = function(v)
            return R.ResolvedBuiltinTypeRef(S(v.name))
        end,

        NamedTypeRef = function(v)
            local parts = U.copy(v.parts)
            return R.ResolvedDefinedTypeRef(resolve_fqname(index, ns_parts, parts))
        end,
    })
end

local function resolve_fields(index, ns_parts, fields)
    local R = T().Resolved
    return U.map(fields, function(field)
        return R.Field(
            resolve_type_ref(index, ns_parts, field.type_ref),
            resolved_arity(field.arity),
            S(field.name)
        )
    end)
end

local function resolve_type_expr(index, ns_parts, type_expr)
    local R = T().Resolved
    local module_prefix = join_parts(ns_parts)

    return U.match(type_expr, {
        SourceProduct = function(v)
            return R.ResolvedProduct(
                resolve_fields(index, ns_parts, v.fields),
                v.unique_flag
            )
        end,

        SourceSum = function(v)
            return R.ResolvedSum(
                U.map(v.constructors, function(ctor)
                    local fqname = module_prefix == "" and S(ctor.name) or (module_prefix .. "." .. S(ctor.name))
                    return R.Constructor(
                        fqname,
                        S(ctor.name),
                        resolve_fields(index, ns_parts, ctor.fields),
                        ctor.unique_flag
                    )
                end),
                resolve_fields(index, ns_parts, v.attribute_fields)
            )
        end,
    })
end

local function resolve_definitions(index, ns_parts, definitions)
    local R = T().Resolved
    return U.map(definitions, function(definition)
        return U.match(definition, {
            SourceModuleDef = function(v)
                local next_parts = U.copy(ns_parts)
                next_parts[#next_parts + 1] = S(v.name)
                local fqname = join_parts(next_parts)
                return R.ResolvedModuleDef(
                    fqname,
                    resolve_definitions(index, next_parts, v.definitions)
                )
            end,

            SourceTypeDef = function(v)
                local next_parts = U.copy(ns_parts)
                local fqname = (#next_parts == 0) and S(v.name) or (join_parts(next_parts) .. "." .. S(v.name))
                return R.ResolvedTypeDef(
                    fqname,
                    resolve_type_expr(index, next_parts, v.type_expr)
                )
            end,
        })
    end)
end

-- Stage 2: Asdl.Source.Spec -> Asdl.Resolved.Spec
compiler.resolve = U.transition("asdl_asdl.resolve", function(source_spec)
    local R = T().Resolved
    local index = collect_type_fqnames(source_spec.definitions, "")
    return R.Spec(resolve_definitions(index, {}, source_spec.definitions))
end)

local builtin_scalar_ctype = {
    number = "double",
    boolean = "bool",
    string = "const char *",
}

local function ctype_name_for(fqname, prefix)
    return prefix .. "_" .. sanitize(fqname)
end

local function source_type_name(type_ref)
    return U.match(type_ref, {
        ResolvedBuiltinTypeRef = function(v)
            return S(v.name)
        end,
        ResolvedDefinedTypeRef = function(v)
            return S(v.fqname)
        end,
    })
end

local function lower_slot_type(type_ref, arity, prefix)
    local LJ = T().LuaJit

    local optional_flag = U.match(arity, {
        ResolvedArityOne = function() return false end,
        ResolvedArityOptional = function() return true end,
        ResolvedArityMany = function() return false end,
    })

    local list_flag = U.match(arity, {
        ResolvedArityOne = function() return false end,
        ResolvedArityOptional = function() return false end,
        ResolvedArityMany = function() return true end,
    })

    local slot_type = U.match(type_ref, {
        ResolvedBuiltinTypeRef = function(v)
            local c_name = builtin_scalar_ctype[S(v.name)] or "void *"
            if list_flag then return LJ.ListRefSlotType(c_name) end
            return LJ.ScalarSlotType(c_name)
        end,

        ResolvedDefinedTypeRef = function(v)
            local target_ctype = ctype_name_for(S(v.fqname), prefix)
            if list_flag then return LJ.ListRefSlotType(target_ctype) end
            return LJ.RefSlotType(target_ctype)
        end,
    })

    return slot_type, optional_flag
end

local function lower_slots(fields, prefix)
    local LJ = T().LuaJit
    return U.map(fields, function(field)
        local slot_type, optional_flag = lower_slot_type(field.type_ref, field.arity, prefix)
        return LJ.Slot(S(field.name), source_type_name(field.type_ref), slot_type, optional_flag)
    end)
end

local function lower_type_layouts(definitions, prefix)
    local LJ = T().LuaJit

    local function lower_definition(definition)
        return U.match(definition, {
            ResolvedModuleDef = function(v)
                return lower_type_layouts(v.definitions, prefix)
            end,

            ResolvedTypeDef = function(v)
                return U.match(v.type_expr, {
                    ResolvedProduct = function(x)
                        return {
                            LJ.ProductLayout(
                                S(v.fqname),
                                ctype_name_for(S(v.fqname), prefix),
                                lower_slots(x.fields, prefix),
                                x.unique_flag
                            )
                        }
                    end,

                    ResolvedSum = function(x)
                        local variants = {}
                        local i = 0
                        U.each(x.constructors, function(ctor)
                            i = i + 1
                            variants[i] = LJ.VariantLayout(
                                S(ctor.fqname),
                                S(ctor.kind_name),
                                i,
                                ctype_name_for(S(ctor.fqname), prefix),
                                lower_slots(ctor.fields, prefix),
                                ctor.unique_flag
                            )
                        end)

                        return {
                            LJ.SumLayout(
                                S(v.fqname),
                                "uint8_t",
                                variants
                            )
                        }
                    end,
                })
            end,
        })
    end

    return U.fold(definitions, function(acc, definition)
        U.each(lower_definition(definition), function(layout)
            acc[#acc + 1] = layout
        end)
        return acc
    end, {})
end

-- Stage 3: Asdl.Resolved.Spec -> Asdl.LuaJit.Spec
compiler.lower_luajit = U.transition("asdl_asdl.lower_luajit", function(resolved_spec, opts)
    local LJ = T().LuaJit
    local prefix = (opts and opts.prefix) or "asdl_lj"
    return LJ.Spec(L(lower_type_layouts(resolved_spec.definitions, prefix)))
end)

local function handle_field_name(slot)
    return S(slot.name) .. "__h"
end

local function display_type_name(type_name, optional_flag, list_flag)
    return type_name .. (list_flag and "*" or (optional_flag and "?" or ""))
end

local function emit_field(slot)
    return U.match(slot.slot_type, {
        ScalarSlotType = function(v)
            local type_name = S(slot.source_type_name)
            local optional_flag = slot.optional_flag and true or false
            return {
                name = S(slot.name),
                type = type_name,
                display_type = display_type_name(type_name, optional_flag, false),
                optional = optional_flag,
                list = false,
                inline = not optional_flag,
                storage_kind = optional_flag and "optional_scalar" or "inline_scalar",
                arena_kind = optional_flag and "optional_scalar" or nil,
                handle_field = optional_flag and handle_field_name(slot) or nil,
                c_name = S(v.c_name),
            }
        end,

        RefSlotType = function(_v)
            local type_name = S(slot.source_type_name)
            local optional_flag = slot.optional_flag and true or false
            return {
                name = S(slot.name),
                type = type_name,
                display_type = display_type_name(type_name, optional_flag, false),
                optional = optional_flag,
                list = false,
                inline = false,
                storage_kind = "ref",
                arena_kind = "ref",
                handle_field = handle_field_name(slot),
            }
        end,

        ListRefSlotType = function(_v)
            local type_name = S(slot.source_type_name)
            return {
                name = S(slot.name),
                type = type_name,
                display_type = display_type_name(type_name, false, true),
                optional = false,
                list = true,
                inline = false,
                storage_kind = "list",
                arena_kind = "list",
                handle_field = handle_field_name(slot),
            }
        end,
    })
end

local function emit_record_cdef(ctype_name, slots)
    local acc = U.fold(slots, function(state, slot)
        return U.match(slot.slot_type, {
            ScalarSlotType = function(v)
                local line = slot.optional_flag
                    and string.format("  uint32_t %s;", handle_field_name(slot))
                    or string.format("  %s %s;", S(v.c_name), S(slot.name))
                state.lines[#state.lines + 1] = line
                state.emitted = state.emitted + 1
                return state
            end,
            RefSlotType = function(_v)
                state.lines[#state.lines + 1] = string.format("  uint32_t %s;", handle_field_name(slot))
                state.emitted = state.emitted + 1
                return state
            end,
            ListRefSlotType = function(_v)
                state.lines[#state.lines + 1] = string.format("  uint32_t %s;", handle_field_name(slot))
                state.emitted = state.emitted + 1
                return state
            end,
        })
    end, {
        lines = { "typedef struct " .. ctype_name .. " {" },
        emitted = 0,
    })

    if acc.emitted == 0 then
        acc.lines[#acc.lines + 1] = "  uint8_t __unit;"
    end
    acc.lines[#acc.lines + 1] = "} " .. ctype_name .. ";"
    return table.concat(acc.lines, "\n")
end

-- Stage 4: Asdl.LuaJit.Spec -> lowered leaf installation plan
compiler.emit_luajit = U.transition("asdl_asdl.emit_luajit", function(layout_spec)
    local function append_record(acc, record, cdef)
        acc.records[#acc.records + 1] = record
        acc.definitions[record.fqname] = record
        acc.cdefs[#acc.cdefs + 1] = cdef
        return acc
    end

    return U.fold(layout_spec.types, function(acc, layout)
        return U.match(layout, {
            ProductLayout = function(v)
                local record = {
                    kind = "record",
                    fqname = S(v.fqname),
                    ctype_name = S(v.ctype_name),
                    fields = U.map(v.slots, emit_field),
                    unique = v.unique_flag,
                    kind_name = nil,
                    sum_parent = nil,
                }
                return append_record(acc, record, emit_record_cdef(S(v.ctype_name), v.slots))
            end,

            SumLayout = function(v)
                local variant_entries = U.map(v.variants, function(variant)
                    local record = {
                        kind = "record",
                        fqname = S(variant.fqname),
                        ctype_name = S(variant.ctype_name),
                        fields = U.map(variant.slots, emit_field),
                        unique = variant.unique_flag,
                        kind_name = S(variant.kind_name),
                        sum_parent = S(v.fqname),
                    }
                    return {
                        record = record,
                        cdef = emit_record_cdef(S(variant.ctype_name), variant.slots),
                    }
                end)

                local variants = U.map(variant_entries, function(entry)
                    return entry.record
                end)

                acc.definitions[S(v.fqname)] = {
                    kind = "sum",
                    fqname = S(v.fqname),
                    variants = variants,
                }

                return U.fold(variant_entries, function(inner, entry)
                    inner.records[#inner.records + 1] = entry.record
                    inner.cdefs[#inner.cdefs + 1] = entry.cdef
                    inner.definitions[entry.record.fqname] = entry.record
                    return inner
                end, acc)
            end,
        })
    end, {
        kind = "LoweredLuaJitBackend",
        records = {},
        definitions = {},
        cdefs = {},
    })
end)

-- Final leaf handoff: lowered plan -> installed context.
compiler.compile_luajit = function(layout_spec, ctx)
    local lowered = compiler.emit_luajit(layout_spec)
    return leaf.compile_into(ctx or leaf.NewContext(), lowered)
end

-- User-facing context: Define(text) runs the whole compiler pipeline.
compiler.NewContext = function(opts)
    local ctx = leaf.NewContext()
    local base_prefix = (opts and opts.prefix) or ("asdl_asdl_" .. tostring(ctx.__context_id))
    local define_count = 0

    function ctx:Define(text)
        define_count = define_count + 1
        local source = compiler.parse(text)
        local resolved = compiler.resolve(source)
        local layout = compiler.lower_luajit(resolved, { prefix = base_prefix .. "_" .. tostring(define_count) })
        return compiler.compile_luajit(layout, self)
    end

    return ctx
end

-- Introspection hook for the handwritten ASDL-language IR.
compiler.bootstrap_context = function()
    return INTERNAL_IR
end


-- ═══════════════════════════════════════════════════════════════
-- 5. PUBLIC API
-- ═══════════════════════════════════════════════════════════════

local M = compiler

-- Convenience list constructor used by examples/tests.
M.List = List

-- Low-level leaf hooks are exposed, but remain downstream of the
-- pure compiler pipeline.
M.compile_into = leaf.compile_into
M.new_leaf_context = leaf.NewContext

return M
