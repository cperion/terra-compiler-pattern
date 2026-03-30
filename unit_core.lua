-- unit_core.lua
--
-- Backend-independent pure helpers for the compiler pattern.
--
-- This module owns the functional layer shared by backends:
--   - canonical gen/param/state traversal helpers
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
local asdl_resolvers = {}

function M.register_asdl_resolver(fn)
    if type(fn) ~= "function" then
        error("register_asdl_resolver: fn must be a function", 2)
    end
    asdl_resolvers[#asdl_resolvers + 1] = fn
    return fn
end

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
    local debug_getinfo = debug and debug.getinfo

    local iterator_mt = {}
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

    local function wrap(gen, param, state)
        return setmetatable({
            gen = gen,
            param = param,
            state = state,
        }, iterator_mt)
    end

    function U.iter(obj, param, state)
        local gen, iter_param, iter_state = rawiter(obj, param, state)
        return wrap(gen, iter_param, iter_state)
    end

    function U.wrap(gen, param, state)
        return wrap(gen, param, state)
    end

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

    function U.copy(xs)
        if xs == nil then return {} end
        return U.map(xs, function(...)
            return ...
        end)
    end

    function U.map_into(dst, xs, fn)
        if type_fn(dst) ~= "table" then
            error("U.map_into: dst must be a table", 2)
        end
        if xs == nil then return dst end

        if type_fn(xs) == "table" and getmetatable_fn(xs) == nil then
            local n = #xs
            local j = #dst
            if n > 0 then
                for i = 1, n do
                    j = j + 1
                    dst[j] = fn(xs[i])
                end
                return dst
            end
            for k, v in next_fn, xs do
                j = j + 1
                dst[j] = fn(k, v)
            end
            return dst
        end

        local gen, param, state = rawiter(xs)
        local j = #dst
        while true do
            local mapped
            state, mapped = call_if_not_empty(fn, gen(param, state))
            if state == nil then break end
            j = j + 1
            dst[j] = mapped
        end
        return dst
    end

    function U.filter_map_into(dst, xs, fn)
        if type_fn(dst) ~= "table" then
            error("U.filter_map_into: dst must be a table", 2)
        end
        if xs == nil then return dst end

        if type_fn(xs) == "table" and getmetatable_fn(xs) == nil then
            local n = #xs
            local j = #dst
            if n > 0 then
                for i = 1, n do
                    local mapped = fn(xs[i])
                    if mapped ~= nil then
                        j = j + 1
                        dst[j] = mapped
                    end
                end
                return dst
            end
            for k, v in next_fn, xs do
                local mapped = fn(k, v)
                if mapped ~= nil then
                    j = j + 1
                    dst[j] = mapped
                end
            end
            return dst
        end

        local gen, param, state = rawiter(xs)
        local j = #dst
        while true do
            local state_x, a, b, c, d, e = gen(param, state)
            state = state_x
            if state == nil then break end
            local mapped = fn(a, b, c, d, e)
            if mapped ~= nil then
                j = j + 1
                dst[j] = mapped
            end
        end
        return dst
    end

    function U.find(xs, pred)
        if xs == nil then return nil end

        if type_fn(xs) == "table" and getmetatable_fn(xs) == nil then
            local n = #xs
            if n > 0 then
                for i = 1, n do
                    local x = xs[i]
                    if pred(x) then return x end
                end
                return nil
            end
            for k, v in next_fn, xs do
                if pred(k, v) then return k, v end
            end
            return nil
        end

        local gen, param, state = rawiter(xs)
        while true do
            local state_x, a, b, c, d, e = gen(param, state)
            state = state_x
            if state == nil then return nil end
            if pred(a, b, c, d, e) then return a, b, c, d, e end
        end
    end

    function U.any(xs, pred)
        pred = pred or function(v) return v end
        return U.find(xs, pred) ~= nil
    end

    function U.all(xs, pred)
        pred = pred or function(v) return v end
        if xs == nil then return true end

        if type_fn(xs) == "table" and getmetatable_fn(xs) == nil then
            local n = #xs
            if n > 0 then
                for i = 1, n do
                    if not pred(xs[i]) then return false end
                end
                return true
            end
            for k, v in next_fn, xs do
                if not pred(k, v) then return false end
            end
            return true
        end

        local gen, param, state = rawiter(xs)
        while true do
            local state_x, a, b, c, d, e = gen(param, state)
            state = state_x
            if state == nil then return true end
            if not pred(a, b, c, d, e) then return false end
        end
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
                U.each(t, function(name)
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
    local memo_stats_registry = {}
    local memo_stats_by_fn = setmetatable({}, { __mode = "k" })

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

    local function infer_memo_name(kind, fn)
        if debug_getinfo then
            local info = debug_getinfo(fn, "S")
            if info then
                local src = info.short_src or info.source or "?"
                local line = info.linedefined or 0
                return string.format("%s@%s:%d", kind, src, line)
            end
        end
        return kind
    end

    local function parse_memo_args(kind, name_or_fn, maybe_fn)
        local name, fn

        if type_fn(name_or_fn) == "string" then
            name = name_or_fn
            fn = maybe_fn
        else
            fn = name_or_fn
        end

        if type_fn(fn) ~= "function" then
            error(kind .. ": fn must be a function", 2)
        end

        return name or infer_memo_name(kind, fn), fn
    end

    local function describe_value(value)
        local t = type_fn(value)

        if value == nil then return "nil" end
        if t == "number" or t == "boolean" then return tostring(value) end
        if t == "string" then
            if #value > 48 then
                return string.format("%q…", value:sub(1, 48))
            end
            return string.format("%q", value)
        end

        if t == "table" then
            local kind = rawget_fn(value, "kind")
            local id = rawget_fn(value, "id")
            local mt = getmetatable_fn(value)
            local mt_name = mt and rawget_fn(mt, "__name") or nil
            local label = kind or mt_name or "table"
            if id ~= nil then
                return string.format("%s#%s", tostring(label), tostring(id))
            end
            return tostring(label)
        end

        if t == "function" then
            if debug_getinfo then
                local info = debug_getinfo(value, "S")
                if info then
                    return string.format("function@%s:%d",
                        info.short_src or info.source or "?",
                        info.linedefined or 0)
                end
            end
            return "function"
        end

        return t
    end

    local function describe_args(...)
        local argc = select("#", ...)
        if argc == 0 then return "()" end

        local parts = {}
        local shown = math.min(argc, 4)
        for i = 1, shown do
            parts[i] = describe_value(select(i, ...))
        end
        if argc > shown then
            parts[#parts + 1] = string.format("…+%d", argc - shown)
        end
        return table.concat(parts, ", ")
    end

    local function register_stats(stats)
        memo_stats_registry[#memo_stats_registry + 1] = stats
        return stats
    end

    local function backend_memoize(fn)
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

    function U._memoize_with(backend, kind, name_or_fn, maybe_fn)
        if type_fn(backend) ~= "function" then
            error("U._memoize_with: backend must be a function", 2)
        end

        local name, fn = parse_memo_args(kind, name_or_fn, maybe_fn)
        local tracker_root = {}
        local stats = register_stats({
            name = name,
            kind = kind,
            calls = 0,
            hits = 0,
            misses = 0,
            unique_keys = 0,
            last_miss_reason = nil,
        })
        local memoized = backend(fn)

        local wrapped = function(...)
            stats.calls = stats.calls + 1

            local node = tracker_root
            local argc = select("#", ...)
            for i = 1, argc do
                node = next_memo_node(node, select(i, ...))
            end

            if rawget(node, "_seen") then
                stats.hits = stats.hits + 1
                return memoized(...)
            end

            local result = pack_fn(memoized(...))
            node._seen = true
            stats.misses = stats.misses + 1
            stats.unique_keys = stats.unique_keys + 1
            stats.last_miss_reason = describe_args(...)
            return unpack_fn(result, 1, result.n)
        end

        memo_stats_by_fn[wrapped] = stats
        return wrapped
    end

    function U.memoize(name_or_fn, maybe_fn)
        return U._memoize_with(backend_memoize, "memoize", name_or_fn, maybe_fn)
    end

    function U.transition(name_or_fn, maybe_fn)
        return U._memoize_with(backend_memoize, "transition", name_or_fn, maybe_fn)
    end

    function U.terminal(name_or_fn, maybe_fn)
        return U._memoize_with(backend_memoize, "terminal", name_or_fn, maybe_fn)
    end

    function U.memo_stats(memoized_fn)
        return memoized_fn and memo_stats_by_fn[memoized_fn] or nil
    end

    function U.memo_inspector()
        local I = {}

        function I.track(memoized_fn)
            local stats = U.memo_stats(memoized_fn)
            if not stats then return false end

            local seen = false
            U.each(memo_stats_registry, function(existing)
                if existing == stats then seen = true end
            end)
            if not seen then
                memo_stats_registry[#memo_stats_registry + 1] = stats
            end
            return true
        end

        function I.stats()
            return memo_stats_registry
        end

        function I.reset()
            U.each(memo_stats_registry, function(stats)
                stats.hits = 0
                stats.misses = 0
                stats.calls = 0
                stats.last_miss_reason = nil
            end)
        end

        local HR72 = string.rep("═", 72)
        local HR60 = string.rep("═", 60)
        local RULE72 = string.rep("─", 72)
        local RULE60 = string.rep("─", 60)

        local function sorted_stats()
            local copy = U.copy(memo_stats_registry)
            table.sort(copy, function(a, b)
                local ar = a.calls > 0 and (a.hits / a.calls) or 0
                local br = b.calls > 0 and (b.hits / b.calls) or 0
                if ar == br then return a.name < b.name end
                return ar < br
            end)
            return copy
        end

        function I.report()
            local lines = {}
            local function add(line)
                lines[#lines + 1] = line
            end
            local function addf(fmt, ...)
                lines[#lines + 1] = string.format(fmt, ...)
            end

            add("")
            add("MEMOIZE REPORT")
            add(HR72)
            addf("  %-30s  %6s  %6s  %6s  %7s",
                "boundary", "calls", "hits", "miss", "hit %")
            add(RULE72)

            local total_calls, total_hits, total_misses = 0, 0, 0
            U.each(sorted_stats(), function(stats)
                local ratio = stats.calls > 0 and (stats.hits / stats.calls * 100) or 0
                local indicator = ratio >= 80 and "✓" or (ratio >= 50 and "△" or "✗")
                addf("%s %-30s  %6d  %6d  %6d  %6.1f%%",
                    indicator, stats.name, stats.calls, stats.hits, stats.misses, ratio)
                total_calls = total_calls + stats.calls
                total_hits = total_hits + stats.hits
                total_misses = total_misses + stats.misses
            end)

            add(RULE72)
            local total_ratio = total_calls > 0 and (total_hits / total_calls * 100) or 0
            addf("  %-30s  %6d  %6d  %6d  %6.1f%%",
                "TOTAL", total_calls, total_hits, total_misses, total_ratio)
            add("")
            return table.concat(lines, "\n")
        end

        function I.measure_edit(description, edit_fn)
            I.reset()
            edit_fn()

            local lines = {}
            local function add(line)
                lines[#lines + 1] = line
            end
            local function addf(fmt, ...)
                lines[#lines + 1] = string.format(fmt, ...)
            end

            add("")
            add("EDIT: " .. description)
            add(RULE60)

            local total_calls, total_misses = 0, 0
            U.each(memo_stats_registry, function(stats)
                total_calls = total_calls + stats.calls
                total_misses = total_misses + stats.misses
                if stats.misses > 0 then
                    addf("  RECOMPILED: %-25s  %d/%d",
                        stats.name, stats.misses, stats.calls)
                    if stats.last_miss_reason then
                        add("              reason: " .. stats.last_miss_reason)
                    end
                end
            end)

            local reuse = total_calls > 0 and ((total_calls - total_misses) / total_calls * 100) or 0
            add(RULE60)
            addf("  Reuse: %d/%d (%.1f%%)",
                total_calls - total_misses, total_calls, reuse)
            addf("  Work:  %d recompilations out of %d calls",
                total_misses, total_calls)
            add("")
            return table.concat(lines, "\n")
        end

        function I.quality()
            local lines = {}
            local function add(line)
                lines[#lines + 1] = line
            end
            local function addf(fmt, ...)
                lines[#lines + 1] = string.format(fmt, ...)
            end

            add("")
            add("DESIGN QUALITY")
            add(HR60)

            local total_hits, total_calls = 0, 0
            U.each(memo_stats_registry, function(stats)
                total_hits = total_hits + stats.hits
                total_calls = total_calls + stats.calls
            end)
            local overall = total_calls > 0 and (total_hits / total_calls * 100) or 0
            addf("  Overall cache hit ratio:     %6.1f%%", overall)

            local worst_name = "none"
            local worst_ratio = 100
            U.each(memo_stats_registry, function(stats)
                if stats.calls > 5 then
                    local ratio = stats.hits / stats.calls * 100
                    if ratio < worst_ratio then
                        worst_ratio = ratio
                        worst_name = stats.name
                    end
                end
            end)
            if worst_name == "none" then worst_ratio = 0 end
            addf("  Worst boundary:              %s (%.1f%%)",
                worst_name, worst_ratio)

            local total_entries = 0
            U.each(memo_stats_registry, function(stats)
                total_entries = total_entries + stats.unique_keys
            end)
            addf("  Cache entries:               %d", total_entries)
            add("")

            if overall >= 90 then
                add("  ✓ EXCELLENT: ASDL decomposition is well-suited for incremental compilation.")
            elseif overall >= 70 then
                add("  △ GOOD: Most edits reuse cached results.")
                add("    Check '" .. worst_name .. "' — it may have too-coarse granularity.")
            elseif overall >= 50 then
                add("  △ FAIR: Significant recompilation per edit.")
                add("    Consider splitting coarse-grained types into finer ASDL nodes.")
            else
                add("  ✗ POOR: Most calls miss the cache.")
                add("    The ASDL decomposition is too coarse, structural sharing is broken, or memoize keys include volatile data.")
            end

            add("")
            return table.concat(lines, "\n")
        end

        function I.diagnose()
            local problems = {}

            U.each(memo_stats_registry, function(stats)
                if stats.calls < 2 then return end
                local ratio = stats.calls > 0 and (stats.hits / stats.calls) or 0

                if ratio == 0 and stats.calls > 3 then
                    problems[#problems + 1] = {
                        severity = "critical",
                        message = stats.name .. " never hits the cache (" .. stats.calls
                            .. " calls, 0 hits). This may be expected for the root boundary, but otherwise suggests volatile keys or broken structural sharing.",
                    }
                elseif ratio < 0.5 and stats.calls > 5 then
                    problems[#problems + 1] = {
                        severity = "warning",
                        message = stats.name .. " has low reuse ("
                            .. string.format("%.0f%%", ratio * 100)
                            .. "). The ASDL granularity may be too coarse, or a single edit may be invalidating too many nodes.",
                    }
                elseif stats.unique_keys > 10000 then
                    problems[#problems + 1] = {
                        severity = "info",
                        message = stats.name .. " has " .. stats.unique_keys
                            .. " cache entries. The memoization granularity may be too fine.",
                    }
                end
            end)

            local total_entries = 0
            U.each(memo_stats_registry, function(stats)
                total_entries = total_entries + stats.unique_keys
            end)
            if total_entries > 50000 then
                problems[#problems + 1] = {
                    severity = "warning",
                    message = "Total cache entries: " .. total_entries
                        .. ". Consider adding eviction or memoizing at a coarser boundary.",
                }
            end

            if #problems == 0 then
                return "  ✓ No memoize design problems detected.\n"
            end

            local lines = {}
            U.each(problems, function(problem)
                local icon = problem.severity == "critical" and "✗"
                    or (problem.severity == "warning" and "△" or "○")
                lines[#lines + 1] = "  " .. icon .. " " .. problem.message
            end)
            return table.concat(lines, "\n\n") .. "\n"
        end

        return I
    end

    function U.memo()
        U._memo_singleton = U._memo_singleton or U.memo_inspector()
        return U._memo_singleton
    end

    function U.memo_report()
        return U.memo().report()
    end

    function U.memo_quality()
        return U.memo().quality()
    end

    function U.memo_diagnose()
        return U.memo().diagnose()
    end

    function U.memo_measure_edit(description, fn)
        return U.memo().measure_edit(description, fn)
    end

    function U.memo_reset()
        return U.memo().reset()
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

    local function asdl_mt(value)
        local mt = getmetatable(value)
        if type(mt) == "table" then return mt end

        if debug and type(debug.getmetatable) == "function" then
            local dbg_mt = debug.getmetatable(value)
            if type(dbg_mt) == "table" and (dbg_mt.__fields or dbg_mt.__sum_parent or dbg_mt.__variants or dbg_mt.__name) then
                return dbg_mt
            end
        end

        for i = 1, #asdl_resolvers do
            local resolved = asdl_resolvers[i](value)
            if type(resolved) == "table" then return resolved end
        end

        return nil
    end

    function U.match(value, arms)
        local mt = asdl_mt(value)

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
        local mt = asdl_mt(node)
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

    U.register_asdl_resolver = M.register_asdl_resolver

    return U
end

return M
