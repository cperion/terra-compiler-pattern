-- unit_core.lua
--
-- Backend-independent pure helpers for the compiler pattern.
--
-- This module owns the functional layer shared by backends:
--   - LuaFun combinators
--   - identity-based memoize
--   - boundary wrappers
--   - error collection
--   - ASDL helpers (match, with)
--
-- Backend modules add:
--   - Unit construction details
--   - state allocation/layout
--   - hot swap
--   - drivers / runtime hookup

local M = {}

function M.new()
    local U = {}

    local unpack_fn = table.unpack or unpack
    local pack_fn = table.pack or function(...)
        return { n = select("#", ...), ... }
    end
    local rawget_fn = rawget
    local getmetatable_fn = getmetatable
    local type_fn = type
    local next_fn = next

    local fun = require("fun")
    local iter = fun.iter
    local ipairs_gen = ipairs({})
    local pairs_gen = pairs({ a = 0 })

    local function map_gen(tab, key)
        local next_key, value = pairs_gen(tab, key)
        return next_key, next_key, value
    end

    local function rawiter(obj, param, state)
        local obj_t = type_fn(obj)
        if obj_t == "table" then
            local mt = getmetatable_fn(obj)
            if mt ~= nil then
                local gen = rawget_fn(obj, "gen")
                if type_fn(gen) == "function" then
                    return gen, rawget_fn(obj, "param"), rawget_fn(obj, "state")
                elseif mt.__ipairs ~= nil then
                    return mt.__ipairs(obj)
                elseif mt.__pairs ~= nil then
                    return mt.__pairs(obj)
                end
            end
            if #obj > 0 then
                return ipairs_gen, obj, 0
            end
            return map_gen, obj, nil
        elseif obj_t == "function" then
            return obj, param, state
        end
        error("object is not iterable: " .. tostring(obj), 3)
    end

    local function call_if_not_empty(fun_fn, state_x, ...)
        if state_x == nil then
            return nil
        end
        return state_x, fun_fn(...)
    end

    local function fold_call(fun_fn, acc, state_x, ...)
        if state_x == nil then
            return nil, acc
        end
        return state_x, fun_fn(acc, ...)
    end

    U.fun = fun
    U.iter = iter
    U.rawiter = rawiter

    function U.each(xs, fn)
        if type_fn(xs) == "table" and getmetatable_fn(xs) == nil then
            local n = #xs
            if n > 0 then
                for i = 1, n do fn(xs[i]) end
                return
            end
            for k, v in next_fn, xs do fn(k, v) end
            return
        end

        local gen, param, state = rawiter(xs)
        repeat
            state = call_if_not_empty(fn, gen(param, state))
        until state == nil
    end

    function U.fold(xs, fn, init)
        if type_fn(xs) == "table" and getmetatable_fn(xs) == nil then
            local n = #xs
            if n > 0 then
                for i = 1, n do init = fn(init, xs[i]) end
                return init
            end
            for k, v in next_fn, xs do init = fn(init, k, v) end
            return init
        end

        local gen, param, state = rawiter(xs)
        while true do
            state, init = fold_call(fn, init, gen(param, state))
            if state == nil then break end
        end
        return init
    end

    function U.map(xs, fn)
        if type_fn(xs) == "table" and getmetatable_fn(xs) == nil then
            local n = #xs
            local out = {}
            if n > 0 then
                for i = 1, n do out[i] = fn(xs[i]) end
                return out
            end
            local j = 0
            for k, v in next_fn, xs do
                j = j + 1
                out[j] = fn(k, v)
            end
            return out
        end

        local gen, param, state = rawiter(xs)
        local out = {}
        local i = 0
        while true do
            local mapped
            state, mapped = call_if_not_empty(fn, gen(param, state))
            if state == nil then break end
            i = i + 1
            out[i] = mapped
        end
        return out
    end

    function U.reverse_each(xs, fn)
        for i = #xs, 1, -1 do
            fn(xs[i], i)
        end
    end

    function U.each_name(tables, fn)
        local seen = {}
        local names = {}

        U.each(tables, function(t)
            if type(t) == "table" then
                iter(t):each(function(name)
                    if not seen[name] then
                        seen[name] = true
                        names[#names + 1] = name
                    end
                end)
            end
        end)

        table.sort(names)

        if fn then
            U.each(names, fn)
        end

        return names
    end

    function U.append_errors(list, child_errs)
        if not child_errs then return end
        U.each(child_errs, function(e)
            list[#list + 1] = e
        end)
    end

    function U.map_errors(list, items, fn, ref_field, on_error)
        local results = {}
        local i = 0

        U.each(items, function(item)
            i = i + 1
            local ok, result, child_errs = pcall(function()
                return fn(item)
            end)

            if ok then
                U.append_errors(list, child_errs)
                results[i] = result
            else
                list[#list + 1] = {
                    ref = ref_field and item[ref_field] or i,
                    err = tostring(result),
                }
                results[i] = on_error and on_error(item, i, result) or nil
            end
        end)

        return results
    end

    local NIL_KEY = {}

    local function next_memo_node(node, key)
        if key == nil then key = NIL_KEY end

        local t = type(key)
        local weak = t == "table" or t == "function"
            or t == "userdata" or t == "thread"

        local bucket_name = weak and "_weak" or "_strong"
        local bucket = rawget(node, bucket_name)

        if not bucket then
            bucket = weak and setmetatable({}, { __mode = "k" }) or {}
            node[bucket_name] = bucket
        end

        local child = bucket[key]
        if not child then
            child = {}
            bucket[key] = child
        end

        return child
    end

    function U.memoize(fn)
        if type(fn) ~= "function" then
            error("U.memoize: fn must be a function", 2)
        end

        local root = {}

        return function(...)
            local node = root
            local argc = select("#", ...)

            for i = 1, argc do
                node = next_memo_node(node, select(i, ...))
            end

            local cached = rawget(node, "_result")
            if cached then
                return unpack_fn(cached, 1, cached.n)
            end

            local result = pack_fn(fn(...))
            node._result = result
            return unpack_fn(result, 1, result.n)
        end
    end

    function U.transition(fn)
        return U.memoize(fn)
    end

    function U.terminal(fn)
        return U.memoize(fn)
    end

    function U.with_fallback(fn, neutral)
        return function(...)
            local ok, result = pcall(fn, ...)
            if ok then return result end
            return neutral
        end
    end

    function U.with_errors(fn)
        return function(...)
            local errs = U.errors()
            local result = fn(errs, ...)
            return result, errs:get()
        end
    end

    local function get_silent()
        if type(U.silent) ~= "function" then return nil end
        U._silent_unit = U._silent_unit or U.silent()
        return U._silent_unit
    end

    function U.errors()
        local list = {}

        return {
            each = function(self, items, fn, ref_field, neutral_fn)
                return U.map_errors(list, items, fn, ref_field, function(item)
                    if neutral_fn then return neutral_fn(item) end
                    return get_silent()
                end)
            end,

            call = function(self, target, fn, neutral_fn)
                local ok, result, child_errs = pcall(fn, target)
                if ok then
                    U.append_errors(list, child_errs)
                    return result
                end

                list[#list + 1] = {
                    ref = target and target.id or nil,
                    err = tostring(result),
                }

                if neutral_fn then return neutral_fn(target) end
                return nil
            end,

            merge = function(self, child_errs)
                U.append_errors(list, child_errs)
            end,

            get = function(self)
                if #list > 0 then return list end
                return nil
            end,
        }
    end

    function U.match(value, arms)
        local mt = getmetatable(value)

        if mt then
            local parent = mt.__sum_parent
            local variants = mt.__variants
                or (parent and parent.__variants)
                or {}

            for _, vname in ipairs(variants) do
                if not arms[vname] then
                    error(("U.match: missing variant '%s' on %s. All variants must be handled."):format(
                        vname,
                        (parent and parent.__name) or mt.__name or tostring(mt)
                    ), 2)
                end
            end
        end

        local kind = value.kind
        if not kind then
            error("U.match: value has no .kind field — is this an ASDL sum type?", 2)
        end

        local handler = arms[kind]
        if not handler then
            error(("U.match: unhandled variant '%s'"):format(kind), 2)
        end

        return handler(value)
    end

    function U.with(node, overrides)
        local mt = getmetatable(node)
        if not mt then
            error("U.with: node has no metatable — is this an ASDL type?", 2)
        end

        local fields = mt.__fields
        if not fields then
            error("U.with: metatable has no __fields — is this an ASDL type created by context:Define()?", 2)
        end

        local args = U.map(fields, function(field)
            local name = field.name or field[1]
            if overrides[name] ~= nil then
                return overrides[name]
            end
            return node[name]
        end)

        return mt(unpack_fn(args, 1, #fields))
    end

    return U
end

return M
