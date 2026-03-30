-- js_runtime.lua
--
-- JS semantic primitives: null sentinel, typeof, loose equality,
-- coercion rules, prototype/class support, array/string metatables.
--
-- These are NOT compiled artifacts. They are the semantic vocabulary
-- that compiled closures reference as upvalues.

local bit = require("bit")

local M = {}
local js_callable_meta = setmetatable({}, { __mode = "k" })
local JS_CALL_SENTINEL = {}
M.JS_CALL_SENTINEL = JS_CALL_SENTINEL

function M.js_register_callable(fn, mode)
    js_callable_meta[fn] = mode or "method"
    return fn
end

function M.js_call(fn, this_arg, ...)
    local mode = js_callable_meta[fn]
    if mode == "compiled" then
        return fn(JS_CALL_SENTINEL, this_arg, ...)
    elseif mode == "method" then
        return fn(this_arg, ...)
    end
    return fn(...)
end

-- ═══════════════════════════════════════════════════════════════
-- JS_NULL sentinel
-- ═══════════════════════════════════════════════════════════════
-- JS null ≠ Lua nil. We need a distinct sentinel because nil
-- vanishes from Lua tables.

local JS_NULL = setmetatable({}, {
    __tostring = function() return "null" end,
    __eq = function(a, b) return rawequal(a, b) end,
})
M.JS_NULL = JS_NULL

local JS_TDZ = setmetatable({}, {
    __tostring = function() return "<tdz>" end,
    __eq = function(a, b) return rawequal(a, b) end,
})
M.JS_TDZ = JS_TDZ

-- ═══════════════════════════════════════════════════════════════
-- JS_UNDEFINED (alias for nil in most contexts)
-- ═══════════════════════════════════════════════════════════════
-- We use Lua nil for undefined. When we need a sentinel in tables
-- we fall back to JS_NULL semantics.

-- ═══════════════════════════════════════════════════════════════
-- typeof
-- ═══════════════════════════════════════════════════════════════
function M.js_typeof(v)
    if v == nil then return "undefined" end
    if v == JS_NULL then return "object" end
    local t = type(v)
    if t == "number" then return "number" end
    if t == "string" then return "string" end
    if t == "boolean" then return "boolean" end
    if t == "function" then return "function" end
    if t == "table" then return "object" end
    return "undefined"
end

-- ═══════════════════════════════════════════════════════════════
-- Loose equality (==)
-- ═══════════════════════════════════════════════════════════════
function M.js_loose_equal(a, b)
    if a == b then return true end
    if a == nil and b == JS_NULL then return true end
    if a == JS_NULL and b == nil then return true end
    local ta, tb = type(a), type(b)
    if ta == "number" and tb == "string" then return a == tonumber(b) end
    if ta == "string" and tb == "number" then return tonumber(a) == b end
    if ta == "boolean" then return M.js_loose_equal(a and 1 or 0, b) end
    if tb == "boolean" then return M.js_loose_equal(a, b and 1 or 0) end
    return false
end

-- ═══════════════════════════════════════════════════════════════
-- Truthiness
-- ═══════════════════════════════════════════════════════════════
function M.js_truthy(v)
    if v == nil or v == false or v == 0 or v == "" or v == JS_NULL then
        return false
    end
    -- NaN check
    if v ~= v then return false end
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- JS + operator (overloaded: add or concat)
-- ═══════════════════════════════════════════════════════════════
function M.js_add(a, b)
    if type(a) == "string" or type(b) == "string" then
        return tostring(a) .. tostring(b)
    end
    return (tonumber(a) or 0) + (tonumber(b) or 0)
end

-- ═══════════════════════════════════════════════════════════════
-- Bitwise ops (ensure 32-bit integer semantics)
-- ═══════════════════════════════════════════════════════════════
M.bit = bit

-- ═══════════════════════════════════════════════════════════════
-- Array metatable (JS Array methods)
-- ═══════════════════════════════════════════════════════════════
local array_methods = {
    push = function(self, ...)
        local args = { ... }
        for _, v in ipairs(args) do
            self[#self + 1] = v
        end
        return #self
    end,
    pop = function(self)
        local v = self[#self]
        self[#self] = nil
        return v
    end,
    forEach = function(self, fn)
        for i, v in ipairs(self) do M.js_call(fn, nil, v, i - 1, self) end
    end,
    indexOf = function(self, val)
        for i, v in ipairs(self) do
            if v == val then return i - 1 end
        end
        return -1
    end,
    includes = function(self, val)
        for _, v in ipairs(self) do
            if v == val then return true end
        end
        return false
    end,
    join = function(self, sep)
        local parts = {}
        for i, v in ipairs(self) do parts[i] = tostring(v) end
        return table.concat(parts, sep or ",")
    end,
    slice = function(self, s, e)
        s = (s or 0) + 1
        e = e or #self
        local result = M.js_array({})
        for i = s, e do result[#result + 1] = self[i] end
        return result
    end,
}

-- These reference M.js_array which isn't defined yet, so we add them after
local array_mt = {
    __index = function(self, key)
        if key == "length" then return #self end
        return array_methods[key]
    end,
}

function M.js_array(xs)
    return setmetatable(xs or {}, array_mt)
end

for k, fn in pairs(array_methods) do
    if type(fn) == "function" then
        array_methods[k] = M.js_register_callable(fn, "method")
    end
end

-- Now add methods that need M.js_array
array_methods.map = M.js_register_callable(function(self, fn)
    local result = M.js_array({})
    for i, v in ipairs(self) do
        result[i] = M.js_call(fn, nil, v, i - 1, self)
    end
    return result
end, "method")
array_methods.filter = M.js_register_callable(function(self, fn)
    local result = M.js_array({})
    for i, v in ipairs(self) do
        if M.js_call(fn, nil, v, i - 1, self) then
            result[#result + 1] = v
        end
    end
    return result
end, "method")
array_methods.reduce = M.js_register_callable(function(self, fn, init)
    local acc = init
    local start = 1
    if acc == nil then acc = self[1]; start = 2 end
    for i = start, #self do
        acc = M.js_call(fn, nil, acc, self[i], i - 1, self)
    end
    return acc
end, "method")
array_methods.concat = M.js_register_callable(function(self, ...)
    local result = M.js_array({})
    for _, v in ipairs(self) do result[#result + 1] = v end
    for _, arr in ipairs({...}) do
        if type(arr) == "table" then
            for _, v in ipairs(arr) do result[#result + 1] = v end
        else
            result[#result + 1] = arr
        end
    end
    return result
end, "method")

-- ═══════════════════════════════════════════════════════════════
-- JS object creation
-- ═══════════════════════════════════════════════════════════════
function M.js_object(t)
    return t or {}
end

-- ═══════════════════════════════════════════════════════════════
-- JS instanceof
-- ═══════════════════════════════════════════════════════════════
function M.js_instanceof(obj, cls)
    if type(obj) ~= "table" or type(cls) ~= "table" then return false end
    local mt = getmetatable(obj)
    while mt do
        if mt == cls.__proto__ then return true end
        mt = rawget(mt, "__js_super")
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════
-- Class construction helper
-- ═══════════════════════════════════════════════════════════════
function M.js_make_class(super_cls, ctor, specs, bind_self)
    local cls = {}
    local inst_props = {}
    local static_props = {}

    local function bind_method(receiver, fn)
        return function(...)
            return M.js_call(fn, receiver, receiver, ...)
        end
    end

    local function lookup_prop(self_obj, props, super_mt, key)
        local entry = props[key]
        if entry ~= nil then
            if type(entry) == "table" and entry.__js_kind == "method" then
                return bind_method(self_obj, entry.fn)
            elseif type(entry) == "table" and entry.__js_kind == "accessor" and entry.get_fn then
                return M.js_call(entry.get_fn, self_obj, self_obj)
            else
                return entry
            end
        end
        if super_mt and super_mt.__index then
            local idx = super_mt.__index
            if type(idx) == "function" then
                return idx(self_obj, key)
            elseif type(idx) == "table" then
                return idx[key]
            end
        end
        return nil
    end

    local function assign_prop(self_obj, props, key, value)
        local entry = props[key]
        if type(entry) == "table" and entry.__js_kind == "accessor" and entry.set_fn then
            return M.js_call(entry.set_fn, self_obj, self_obj, value)
        end
        rawset(self_obj, key, value)
    end

    local super_mt = super_cls and super_cls.__proto__ or nil
    local class_mt = {
        __call = function(_, instance, ...)
            if specs then
                for i = 1, #specs do
                    local spec = specs[i]
                    if spec.kind == "field" and not spec.static then
                        instance[spec.name] = spec.init and M.js_call(spec.init, instance, instance) or nil
                    end
                end
            end
            if ctor then
                return M.js_call(ctor, instance, instance, ...)
            elseif super_cls then
                return super_cls(instance, ...)
            end
            return nil
        end,
    }

    local instance_mt = {
        __js_super = super_mt,
        __index = function(self, key)
            return lookup_prop(self, inst_props, super_mt, key)
        end,
        __newindex = function(self, key, value)
            return assign_prop(self, inst_props, key, value)
        end,
    }

    cls.__proto__ = instance_mt
    cls.prototype = inst_props

    if bind_self then
        M.js_call(bind_self, nil, cls)
    end

    local class_index = function(self, key)
        local entry = static_props[key]
        if entry ~= nil then
            if type(entry) == "table" and entry.__js_kind == "method" then
                return bind_method(cls, entry.fn)
            elseif type(entry) == "table" and entry.__js_kind == "accessor" and entry.get_fn then
                return M.js_call(entry.get_fn, cls, cls)
            else
                return entry
            end
        end
        if super_cls then return super_cls[key] end
        return nil
    end

    local class_newindex = function(self, key, value)
        local entry = static_props[key]
        if type(entry) == "table" and entry.__js_kind == "accessor" and entry.set_fn then
            return M.js_call(entry.set_fn, cls, cls, value)
        end
        rawset(cls, key, value)
    end

    for i = 1, #(specs or {}) do
        local spec = specs[i]
        local target = spec.static and static_props or inst_props
        if spec.kind == "method" then
            target[spec.name] = { __js_kind = "method", fn = spec.fn }
        elseif spec.kind == "get" then
            local entry = target[spec.name] or { __js_kind = "accessor" }
            entry.get_fn = spec.fn
            target[spec.name] = entry
        elseif spec.kind == "set" then
            local entry = target[spec.name] or { __js_kind = "accessor" }
            entry.set_fn = spec.fn
            target[spec.name] = entry
        elseif spec.kind == "field" and spec.static then
            target[spec.name] = spec.init and M.js_call(spec.init, cls, cls) or nil
        end
    end

    return setmetatable(cls, {
        __call = class_mt.__call,
        __index = class_index,
        __newindex = class_newindex,
    })
end

-- ═══════════════════════════════════════════════════════════════
-- JS globals
-- ═══════════════════════════════════════════════════════════════
M.js_globals = {
    console = {
        log = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                if type(v) == "table" then
                    parts[#parts + 1] = tostring(v)
                else
                    parts[#parts + 1] = tostring(v)
                end
            end
            print(table.concat(parts, "\t"))
        end,
        error = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[#parts + 1] = tostring(select(i, ...))
            end
            io.stderr:write(table.concat(parts, "\t") .. "\n")
        end,
    },
    Math = {
        PI = math.pi,
        E = math.exp(1),
        abs = math.abs,
        floor = math.floor,
        ceil = math.ceil,
        round = function(x) return math.floor(x + 0.5) end,
        max = math.max,
        min = math.min,
        sqrt = math.sqrt,
        sin = math.sin,
        cos = math.cos,
        tan = math.tan,
        atan2 = math.atan2,
        pow = math.pow,
        log = math.log,
        exp = math.exp,
        random = math.random,
    },
    parseInt = function(s, radix)
        return math.floor(tonumber(s, radix) or 0)
    end,
    parseFloat = tonumber,
    isNaN = function(v) return v ~= v end,
    isFinite = function(v)
        return type(v) == "number" and v == v
            and v ~= math.huge and v ~= -math.huge
    end,
    undefined = nil,
    null = JS_NULL,
    NaN = 0/0,
    Infinity = math.huge,
    __js_make_class = M.js_make_class,
}

-- ═══════════════════════════════════════════════════════════════
-- BREAK / CONTINUE / RETURN signals
-- ═══════════════════════════════════════════════════════════════
-- Statement compilation uses these as structured control flow.
-- They are NOT errors — they are the JS control-flow vocabulary
-- lowered into Lua's pcall/error mechanism.

local BREAK = setmetatable({}, { __tostring = function() return "JS_BREAK" end })
local CONTINUE = setmetatable({}, { __tostring = function() return "JS_CONTINUE" end })

M.BREAK = BREAK
M.CONTINUE = CONTINUE

function M.js_break(target_id)
    if target_id == nil then return BREAK end
    return { __js_break = true, target = tonumber(target_id) or target_id }
end

function M.js_continue(target_id)
    if target_id == nil then return CONTINUE end
    return { __js_continue = true, target = tonumber(target_id) or target_id }
end

function M.is_break(v)
    return v == BREAK or (type(v) == "table" and v.__js_break == true)
end

function M.is_continue(v)
    return v == CONTINUE or (type(v) == "table" and v.__js_continue == true)
end

-- Return is signaled by { __js_return = true, value = v }
function M.js_return(v)
    return { __js_return = true, value = v }
end

function M.is_return(v)
    return type(v) == "table" and v.__js_return == true
end

-- Install into T context (no-op for runtime, but keeps schema happy)
M.install = function(T)
    -- Runtime primitives are not ASDL types; they are upvalue vocabulary
    -- used by compiled closures. Store on T for access by other modules.
    T._js_runtime = M
end

return M
