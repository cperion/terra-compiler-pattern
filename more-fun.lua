---
--- more-fun.lua
---
--- A LuaJIT-first, compiler-pattern-inspired iterator library.
---
--- Publicly, the important modeling move is:
---
---   Source + Pipe + Terminal -> installed runner
---
--- Instead of caching only a generic `runner(sink)` and deciding the terminal
--- late, this module now caches terminal-specific compiled runners for the hot
--- source families. The generic sink path remains as fallback machinery for
--- residual shapes that are still not classified into a direct public leaf.
---
--- Canonical public API:
---
---   F.from(x) / F.of(...) / F.empty()
---   F.range(a, b[, step])
---   F.chars(text) / F.bytes(text)
---   F.generate(gen, param, state)
---   F.chain(...)
---
---   :map(fn) :filter(fn) :take(n) :drop(n)
---   :each(fn) :fold(fn, init) :collect() :count()
---   :head() :nth(n) :any(fn) :all(fn) :sum() :min() :max()
---   :plan(kind) :compile(kind) :shape()
---

local C = require("crochet")

local M = {}
local methods = {}

local STOP = {}

local SOURCE_EMPTY  = 0
local SOURCE_ARRAY  = 1
local SOURCE_RANGE  = 2
local SOURCE_STRING = 3
local SOURCE_BYTES  = 4
local SOURCE_RAW    = 5
local SOURCE_CHAIN  = 6

local OP_MAP    = 1
local OP_FILTER = 2
local OP_TAKE   = 3
local OP_DROP   = 4

local PIPE_PLAIN         = 0
local PIPE_MAP_ONLY      = 1
local PIPE_FILTER_ONLY   = 2
local PIPE_MAP_FILTER    = 3
local PIPE_CONTROL_ONLY  = 4
local PIPE_GENERIC       = 5

local EXEC_EMPTY         = 0
local EXEC_STRING_PLAIN  = 1
local EXEC_CHAIN         = 2
local EXEC_GENERAL       = 3

local _loadstring = loadstring
local _setfenv = setfenv
local _load = load
local _string_sub = string.sub
local _string_byte = string.byte
local _string_char = string.char
local _type = type
local _getmetatable = getmetatable
local _select = select
local _assert = assert
local _ipairs = ipairs
local _error = error
local _tostring = tostring
local _table_concat = table.concat
local _math_floor = math.floor
local _string_format = string.format
local _rawlen = rawlen or function(t)
    return #t
end

local pipeline_mt = {
    __index = methods,
    __tostring = function()
        return "<more-fun pipeline>"
    end,
}

local function load_in_env(source, chunkname, env)
    if _loadstring then
        local fn, err = _loadstring(source, chunkname)
        if not fn then
            return nil, err
        end
        if env then
            _setfenv(fn, env)
        end
        return fn
    end
    return _load(source, chunkname, "t", env)
end

local function proto_name_for_chunk(chunkname)
    local name = _tostring(chunkname or "more-fun")
    if name:sub(1, 1) == "@" then
        name = name:sub(2)
    end
    return name
end

local function compile_proto(chunkname, params, env, body)
    local keys = {}
    env = env or {}
    for k, _ in pairs(env) do
        keys[#keys + 1] = k
    end
    table.sort(keys)

    local captures = {}
    for i = 1, #keys do
        local name = keys[i]
        captures[i] = C.capture(name, env[name])
    end

    local name = proto_name_for_chunk(chunkname)
    local artifact = C.compile(C.catalog({
        C.proto(name, params, captures, body),
    }, name, "closure"))
    return artifact.entry
end

local function append_nodes(dst, src)
    for i = 1, #src do
        dst[#dst + 1] = src[i]
    end
end

local function is_pipeline(x)
    return _getmetatable(x) == pipeline_mt
end

local function new_source(source_kind, a, b, c)
    return setmetatable({
        prev = false,
        source_kind = source_kind,
        a = a,
        b = b,
        c = c,
        _run = false,
        _shape = false,
        _plan_cache = false,
        _terminal_cache = false,
    }, pipeline_mt)
end

local function new_op(prev, op_kind, op_arg)
    return setmetatable({
        prev = prev,
        op_kind = op_kind,
        op_arg = op_arg,
        _run = false,
        _shape = false,
        _plan_cache = false,
        _terminal_cache = false,
    }, pipeline_mt)
end

local function flatten_pipeline(self)
    local ops = {}
    local n = 0
    local node = self
    while node.prev do
        n = n + 1
        ops[n] = {
            kind = node.op_kind,
            arg = node.op_arg,
        }
        node = node.prev
    end

    for i = 1, _math_floor(n / 2) do
        local j = n - i + 1
        ops[i], ops[j] = ops[j], ops[i]
    end

    return node, ops, n
end

local function pipe_kind_name(kind)
    if kind == PIPE_PLAIN then return "plain" end
    if kind == PIPE_MAP_ONLY then return "map_only" end
    if kind == PIPE_FILTER_ONLY then return "filter_only" end
    if kind == PIPE_MAP_FILTER then return "map_filter" end
    if kind == PIPE_CONTROL_ONLY then return "control_only" end
    return "generic"
end

local function source_kind_name(kind)
    if kind == SOURCE_EMPTY then return "empty" end
    if kind == SOURCE_ARRAY then return "array" end
    if kind == SOURCE_RANGE then return "range" end
    if kind == SOURCE_STRING then return "string" end
    if kind == SOURCE_BYTES then return "bytes" end
    if kind == SOURCE_RAW then return "raw" end
    return "chain"
end

local function exec_kind_name(kind)
    if kind == EXEC_EMPTY then return "empty" end
    if kind == EXEC_STRING_PLAIN then return "string_plain" end
    if kind == EXEC_CHAIN then return "chain" end
    return "general"
end

local function source_proto_name(kind)
    if kind == SOURCE_EMPTY then return "empty_source" end
    if kind == SOURCE_ARRAY then return "array_source" end
    if kind == SOURCE_RANGE then return "range_source" end
    if kind == SOURCE_STRING then return "char_source" end
    if kind == SOURCE_BYTES then return "byte_source" end
    if kind == SOURCE_RAW then return "raw_source" end
    return "chain_source"
end

local function pipe_proto_name(pipe)
    return pipe.name .. "_pipe"
end

local function exec_proto_name(kind)
    if kind == EXEC_EMPTY then return "empty_exec" end
    if kind == EXEC_STRING_PLAIN then return "string_plain_exec" end
    if kind == EXEC_CHAIN then return "chain_exec" end
    return "general_exec"
end

local function normalize_terminal_kind(kind)
    if kind == "foldl" or kind == "reduce" then return "fold" end
    if kind == "totable" or kind == "to_table" then return "collect" end
    if kind == "length" then return "count" end
    if kind == "first" then return "head" end
    if kind == "some" then return "any" end
    if kind == "every" then return "all" end
    return kind
end

local function classify_pipe(ops, nops)
    local map_count = 0
    local filter_count = 0
    local take_count = 0
    local drop_count = 0
    local ordered_map_filter = true
    local ordered_control = true
    local seen_filter = false
    local seen_take = false

    for i = 1, nops do
        local kind = ops[i].kind
        if kind == OP_MAP then
            map_count = map_count + 1
            if seen_filter then
                ordered_map_filter = false
            end
            ordered_control = false
        elseif kind == OP_FILTER then
            filter_count = filter_count + 1
            seen_filter = true
            ordered_control = false
        elseif kind == OP_TAKE then
            take_count = take_count + 1
            seen_take = true
            if map_count > 0 or filter_count > 0 then
                ordered_control = false
            end
        elseif kind == OP_DROP then
            drop_count = drop_count + 1
            if seen_take then
                ordered_control = false
            end
            if map_count > 0 or filter_count > 0 then
                ordered_control = false
            end
        end
    end

    local kind = PIPE_GENERIC
    if nops == 0 then
        kind = PIPE_PLAIN
    elseif filter_count == 0 and take_count == 0 and drop_count == 0 then
        kind = PIPE_MAP_ONLY
    elseif map_count == 0 and take_count == 0 and drop_count == 0 then
        kind = PIPE_FILTER_ONLY
    elseif take_count == 0 and drop_count == 0 and ordered_map_filter then
        kind = PIPE_MAP_FILTER
    elseif map_count == 0 and filter_count == 0 and ordered_control then
        kind = PIPE_CONTROL_ONLY
    end

    return {
        kind = kind,
        name = pipe_kind_name(kind),
        map_count = map_count,
        filter_count = filter_count,
        take_count = take_count,
        drop_count = drop_count,
        ordered_map_filter = ordered_map_filter,
        ordered_control = ordered_control,
        is_plain = kind == PIPE_PLAIN,
    }
end

local function classify_exec(source_kind, pipe)
    if source_kind == SOURCE_EMPTY then
        return EXEC_EMPTY
    end
    if source_kind == SOURCE_CHAIN then
        return EXEC_CHAIN
    end
    if source_kind == SOURCE_STRING and pipe.kind == PIPE_PLAIN then
        return EXEC_STRING_PLAIN
    end
    return EXEC_GENERAL
end

local function shape_for(self)
    if self._shape then
        return self._shape
    end

    local root, ops, nops = flatten_pipeline(self)
    local pipe = classify_pipe(ops, nops)
    local exec_kind = classify_exec(root.source_kind, pipe)
    local root_name = source_kind_name(root.source_kind)
    local exec_name = exec_kind_name(exec_kind)
    local shape = {
        root = root,
        root_kind = root.source_kind,
        root_name = root_name,
        root_proto = source_proto_name(root.source_kind),
        ops = ops,
        nops = nops,
        pipe = pipe,
        pipe_proto = pipe_proto_name(pipe),
        exec_kind = exec_kind,
        exec_name = exec_name,
        exec_proto = exec_proto_name(exec_kind),
        shape_key = root_name .. ":" .. pipe.name .. ":" .. exec_name,
    }
    self._shape = shape
    return shape
end

-- -----------------------------------------------------------------------------
-- Generic fallback path: source runner + sink builder
-- -----------------------------------------------------------------------------

local function compile_ops_builder(ops, nops)
    if nops == 0 then
        return function(next_sink)
            return next_sink
        end
    end

    local env = {
        STOP = STOP,
    }

    local header_lines = {
        "return function(next_sink)",
    }

    local body_lines = {
        "  return function(__v)",
        "    local __emit = true",
    }

    local map_ix = 0
    local filter_ix = 0
    local take_ix = 0
    local drop_ix = 0

    for i = 1, nops do
        local op = ops[i]
        if op.kind == OP_MAP then
            map_ix = map_ix + 1
            local name = "map_fn_" .. map_ix
            env[name] = op.arg
            body_lines[#body_lines + 1] = "    if __emit then __v = " .. name .. "(__v) end"
        elseif op.kind == OP_FILTER then
            filter_ix = filter_ix + 1
            local name = "filter_fn_" .. filter_ix
            env[name] = op.arg
            body_lines[#body_lines + 1] = "    if __emit and not " .. name .. "(__v) then __emit = false end"
        elseif op.kind == OP_TAKE then
            take_ix = take_ix + 1
            local count_name = "take_count_" .. take_ix
            local limit_name = "take_limit_" .. take_ix
            env[limit_name] = op.arg
            header_lines[#header_lines + 1] = "  local " .. count_name .. " = 0"
            body_lines[#body_lines + 1] = "    if __emit then"
            body_lines[#body_lines + 1] = "      " .. count_name .. " = " .. count_name .. " + 1"
            body_lines[#body_lines + 1] = "      if " .. count_name .. " > " .. limit_name .. " then return STOP end"
            body_lines[#body_lines + 1] = "    end"
        elseif op.kind == OP_DROP then
            drop_ix = drop_ix + 1
            local count_name = "drop_count_" .. drop_ix
            local limit_name = "drop_limit_" .. drop_ix
            env[limit_name] = op.arg
            header_lines[#header_lines + 1] = "  local " .. count_name .. " = 0"
            body_lines[#body_lines + 1] = "    if __emit then"
            body_lines[#body_lines + 1] = "      " .. count_name .. " = " .. count_name .. " + 1"
            body_lines[#body_lines + 1] = "      if " .. count_name .. " <= " .. limit_name .. " then __emit = false end"
            body_lines[#body_lines + 1] = "    end"
        else
            _error("unknown op kind: " .. _tostring(op.kind))
        end
    end

    body_lines[#body_lines + 1] = "    if __emit then return next_sink(__v) end"
    body_lines[#body_lines + 1] = "  end"
    body_lines[#body_lines + 1] = "end"

    local source = _table_concat(header_lines, "\n") .. "\n" .. _table_concat(body_lines, "\n")
    local chunk, err = load_in_env(source, "@more-fun:ops", env)
    if not chunk then
        _error(err)
    end
    return chunk()
end

local function compile_source_runner(root)
    local kind = root.source_kind

    if kind == SOURCE_EMPTY then
        return function(_sink)
            return nil
        end
    end

    if kind == SOURCE_ARRAY then
        local xs = root.a
        local i0 = root.b or 1
        local i1 = root.c or _rawlen(xs)
        return function(sink)
            for i = i0, i1 do
                if sink(xs[i]) == STOP then
                    return STOP
                end
            end
            return nil
        end
    end

    if kind == SOURCE_RANGE then
        local start = root.a
        local stop = root.b
        local step = root.c
        return function(sink)
            for i = start, stop, step do
                if sink(i) == STOP then
                    return STOP
                end
            end
            return nil
        end
    end

    if kind == SOURCE_STRING then
        local s = root.a
        local i0 = root.b or 1
        local i1 = root.c or #s
        return function(sink)
            for i = i0, i1 do
                if sink(_string_sub(s, i, i)) == STOP then
                    return STOP
                end
            end
            return nil
        end
    end

    if kind == SOURCE_BYTES then
        local s = root.a
        local i0 = root.b or 1
        local i1 = root.c or #s
        return function(sink)
            for i = i0, i1 do
                if sink(_string_byte(s, i)) == STOP then
                    return STOP
                end
            end
            return nil
        end
    end

    if kind == SOURCE_RAW then
        local gen = root.a
        local param = root.b
        local state0 = root.c
        return function(sink)
            local state = state0
            while true do
                local new_state, value = gen(param, state)
                if new_state == nil then
                    return nil
                end
                state = new_state
                if sink(value) == STOP then
                    return STOP
                end
            end
        end
    end

    if kind == SOURCE_CHAIN then
        local subrunners = {}
        for i, src in _ipairs(root.a) do
            subrunners[i] = src:_runner()
        end
        return function(sink)
            for i = 1, #subrunners do
                if subrunners[i](sink) == STOP then
                    return STOP
                end
            end
            return nil
        end
    end

    _error("unknown source kind: " .. _tostring(kind))
end

local function string_plain_supports_terminal(kind)
    return kind == "head"
        or kind == "nth"
        or kind == "any"
        or kind == "all"
        or kind == "min"
        or kind == "max"
end

local function generated_supports_source(kind)
    return kind == SOURCE_ARRAY
        or kind == SOURCE_RANGE
        or kind == SOURCE_STRING
        or kind == SOURCE_BYTES
        or kind == SOURCE_RAW
end

local function install_kind_for(shape, terminal_kind)
    if shape.exec_kind == EXEC_EMPTY then
        return "empty"
    end
    if shape.exec_kind == EXEC_STRING_PLAIN and string_plain_supports_terminal(terminal_kind) then
        return "string_plain"
    end
    if shape.exec_kind == EXEC_CHAIN then
        return "chain"
    end
    if generated_supports_source(shape.root_kind) then
        return "generated"
    end
    return "generic"
end

local function plan_for(self, terminal_kind)
    _assert(_type(terminal_kind) == "string", "plan expects a terminal kind string")
    terminal_kind = normalize_terminal_kind(terminal_kind)

    local cache = self._plan_cache
    if not cache then
        cache = {}
        self._plan_cache = cache
    end

    local plan = cache[terminal_kind]
    if plan then
        return plan
    end

    local shape = shape_for(self)
    local install_kind = install_kind_for(shape, terminal_kind)

    plan = {
        shape = shape,
        terminal_kind = terminal_kind,
        terminal_name = terminal_kind,
        terminal_proto = terminal_kind .. "_terminal",
        install_kind = install_kind,
        install_proto = install_kind .. "_install",
        shape_key = shape.shape_key,
        artifact_key = shape.shape_key .. ":" .. terminal_kind .. ":" .. install_kind,
        source = {
            kind = shape.root_kind,
            name = shape.root_name,
            proto = shape.root_proto,
        },
        pipe = {
            kind = shape.pipe.kind,
            name = shape.pipe.name,
            proto = shape.pipe_proto,
        },
        exec = {
            kind = shape.exec_kind,
            name = shape.exec_name,
            proto = shape.exec_proto,
        },
        terminal = {
            kind = terminal_kind,
            name = terminal_kind,
            proto = terminal_kind .. "_terminal",
        },
        install = {
            kind = install_kind,
            name = install_kind,
            proto = install_kind .. "_install",
        },
    }

    cache[terminal_kind] = plan
    return plan
end

local compiled0
local compile_terminal_executor

function methods:_shape_info()
    return shape_for(self)
end

function methods:shape()
    return shape_for(self)
end

function methods:plan(terminal_kind)
    return plan_for(self, terminal_kind)
end

function methods:_plan_info(terminal_kind)
    return plan_for(self, terminal_kind)
end

function methods:compile(terminal_kind)
    _assert(_type(terminal_kind) == "string", "compile expects a terminal kind string")
    terminal_kind = normalize_terminal_kind(terminal_kind)
    return compiled0(self, terminal_kind, function()
        return compile_terminal_executor(self, terminal_kind)
    end)
end

function methods:_runner()
    if self._run then
        return self._run
    end

    local shape = shape_for(self)
    local source_runner = compile_source_runner(shape.root)
    local build_sink = compile_ops_builder(shape.ops, shape.nops)

    local function run(sink)
        return source_runner(build_sink(sink))
    end

    self._run = run
    return run
end

-- -----------------------------------------------------------------------------
-- Terminal-specific compiled runners
-- -----------------------------------------------------------------------------

compiled0 = function(self, kind, compiler)
    local cache = self._terminal_cache
    if not cache then
        cache = {}
        self._terminal_cache = cache
    end
    local fn = cache[kind]
    if not fn then
        fn = compiler()
        cache[kind] = fn
    end
    return fn
end

local function empty_terminal_executor(kind)
    if kind == "each" then
        return function(_arg1, _arg2)
            return nil
        end
    end
    if kind == "fold" then
        return function(_arg1, arg2)
            return arg2
        end
    end
    if kind == "collect" then
        return function(_arg1, _arg2)
            return {}
        end
    end
    if kind == "count" then
        return function(_arg1, _arg2)
            return 0
        end
    end
    if kind == "head" then
        return function(_arg1, _arg2)
            return nil
        end
    end
    if kind == "nth" then
        return function(_arg1, _arg2)
            return nil
        end
    end
    if kind == "any" then
        return function(_arg1, _arg2)
            return false
        end
    end
    if kind == "all" then
        return function(_arg1, _arg2)
            return true
        end
    end
    if kind == "sum" then
        return function(_arg1, _arg2)
            return 0
        end
    end
    if kind == "min" then
        return function(_arg1, _arg2)
            return nil
        end
    end
    if kind == "max" then
        return function(_arg1, _arg2)
            return nil
        end
    end
    _error("unknown terminal kind: " .. _tostring(kind))
end

local function generic_terminal_executor(self, kind)
    local run = self:_runner()

    if kind == "each" then
        return function(arg1, _arg2)
            run(function(v)
                arg1(v)
                return nil
            end)
            return nil
        end
    end

    if kind == "fold" then
        return function(arg1, arg2)
            local acc = arg2
            run(function(v)
                acc = arg1(acc, v)
                return nil
            end)
            return acc
        end
    end

    if kind == "collect" then
        return function(_arg1, _arg2)
            local out = {}
            local n = 0
            run(function(v)
                n = n + 1
                out[n] = v
                return nil
            end)
            return out
        end
    end

    if kind == "count" then
        return function(_arg1, _arg2)
            local n = 0
            run(function(_v)
                n = n + 1
                return nil
            end)
            return n
        end
    end

    if kind == "head" then
        return function(_arg1, _arg2)
            local found = nil
            run(function(v)
                found = v
                return STOP
            end)
            return found
        end
    end

    if kind == "nth" then
        return function(arg1, _arg2)
            local i = 0
            local found = nil
            run(function(v)
                i = i + 1
                if i == arg1 then
                    found = v
                    return STOP
                end
                return nil
            end)
            return found
        end
    end

    if kind == "any" then
        return function(arg1, _arg2)
            local ok = false
            run(function(v)
                if arg1(v) then
                    ok = true
                    return STOP
                end
                return nil
            end)
            return ok
        end
    end

    if kind == "all" then
        return function(arg1, _arg2)
            local ok = true
            run(function(v)
                if not arg1(v) then
                    ok = false
                    return STOP
                end
                return nil
            end)
            return ok
        end
    end

    if kind == "sum" then
        return function(_arg1, _arg2)
            local acc = 0
            run(function(v)
                acc = acc + v
                return nil
            end)
            return acc
        end
    end

    if kind == "min" then
        return function(_arg1, _arg2)
            local first = true
            local acc = nil
            run(function(v)
                if first then
                    first = false
                    acc = v
                elseif v < acc then
                    acc = v
                end
                return nil
            end)
            return acc
        end
    end

    if kind == "max" then
        return function(_arg1, _arg2)
            local first = true
            local acc = nil
            run(function(v)
                if first then
                    first = false
                    acc = v
                elseif v > acc then
                    acc = v
                end
                return nil
            end)
            return acc
        end
    end

    _error("unknown terminal kind: " .. _tostring(kind))
end

local function bind_ops(ops, nops, env)
    local bound = {}
    local state_nodes = {}
    local map_ix = 0
    local filter_ix = 0
    local take_ix = 0
    local drop_ix = 0

    for i = 1, nops do
        local op = ops[i]
        if op.kind == OP_MAP then
            map_ix = map_ix + 1
            local name = "map_fn_" .. map_ix
            env[name] = op.arg
            bound[i] = { kind = OP_MAP, fn = name }
        elseif op.kind == OP_FILTER then
            filter_ix = filter_ix + 1
            local name = "filter_fn_" .. filter_ix
            env[name] = op.arg
            bound[i] = { kind = OP_FILTER, fn = name }
        elseif op.kind == OP_TAKE then
            take_ix = take_ix + 1
            local count_name = "take_count_" .. take_ix
            local limit_name = "take_limit_" .. take_ix
            env[limit_name] = op.arg
            state_nodes[#state_nodes + 1] = C.stmt("local ", count_name, " = 0")
            bound[i] = { kind = OP_TAKE, count = count_name, limit = limit_name }
        elseif op.kind == OP_DROP then
            drop_ix = drop_ix + 1
            local count_name = "drop_count_" .. drop_ix
            local limit_name = "drop_limit_" .. drop_ix
            env[limit_name] = op.arg
            state_nodes[#state_nodes + 1] = C.stmt("local ", count_name, " = 0")
            bound[i] = { kind = OP_DROP, count = count_name, limit = limit_name }
        else
            _error("unknown op kind: " .. _tostring(op.kind))
        end
    end

    return bound, state_nodes
end

local function terminal_plan(kind, _env)
    if kind == "each" then
        return {
            init = {},
            final_expr = "nil",
            step = {
                C.stmt("term_arg1(__v)"),
            },
        }
    end

    if kind == "fold" then
        return {
            init = {
                C.stmt("local acc = term_arg2"),
            },
            final_expr = "acc",
            step = {
                C.stmt("acc = term_arg1(acc, __v)"),
            },
        }
    end

    if kind == "collect" then
        return {
            init = {
                C.stmt("local out = {}"),
                C.stmt("local n = 0"),
            },
            final_expr = "out",
            step = {
                C.stmt("n = n + 1"),
                C.stmt("out[n] = __v"),
            },
        }
    end

    if kind == "count" then
        return {
            init = {
                C.stmt("local n = 0"),
            },
            final_expr = "n",
            step = {
                C.stmt("n = n + 1"),
            },
        }
    end

    if kind == "head" then
        return {
            init = {},
            final_expr = "nil",
            step = {
                C.stmt("do return __v end"),
            },
        }
    end

    if kind == "nth" then
        return {
            init = {
                C.stmt("local nth_count = 0"),
            },
            final_expr = "nil",
            step = {
                C.stmt("nth_count = nth_count + 1"),
                C.stmt("if nth_count == term_arg1 then do return __v end end"),
            },
        }
    end

    if kind == "any" then
        return {
            init = {},
            final_expr = "false",
            step = {
                C.stmt("if term_arg1(__v) then do return true end end"),
            },
        }
    end

    if kind == "all" then
        return {
            init = {},
            final_expr = "true",
            step = {
                C.stmt("if not term_arg1(__v) then do return false end end"),
            },
        }
    end

    if kind == "sum" then
        return {
            init = {
                C.stmt("local acc = 0"),
            },
            final_expr = "acc",
            step = {
                C.stmt("acc = acc + __v"),
            },
        }
    end

    if kind == "min" then
        return {
            init = {
                C.stmt("local seen = false"),
                C.stmt("local acc = nil"),
            },
            final_expr = "acc",
            step = {
                C.stmt("if not seen then"),
                C.stmt("seen = true"),
                C.stmt("acc = __v"),
                C.stmt("elseif __v < acc then"),
                C.stmt("acc = __v"),
                C.stmt("end"),
            },
        }
    end

    if kind == "max" then
        return {
            init = {
                C.stmt("local seen = false"),
                C.stmt("local acc = nil"),
            },
            final_expr = "acc",
            step = {
                C.stmt("if not seen then"),
                C.stmt("seen = true"),
                C.stmt("acc = __v"),
                C.stmt("elseif __v > acc then"),
                C.stmt("acc = __v"),
                C.stmt("end"),
            },
        }
    end

    _error("unknown terminal kind: " .. _tostring(kind))
end

local function process_nodes(value_expr, bound_ops, nops, term)
    local nodes = {
        C.stmt("local __v = ", value_expr),
    }

    if nops > 0 then
        nodes[#nodes + 1] = C.stmt("local __emit = true")
    end

    for i = 1, nops do
        local op = bound_ops[i]
        if op.kind == OP_MAP then
            nodes[#nodes + 1] = C.stmt("if __emit then __v = ", op.fn, "(__v) end")
        elseif op.kind == OP_FILTER then
            nodes[#nodes + 1] = C.stmt("if __emit and not ", op.fn, "(__v) then __emit = false end")
        elseif op.kind == OP_TAKE then
            nodes[#nodes + 1] = C.stmt("if __emit then")
            nodes[#nodes + 1] = C.stmt(op.count, " = ", op.count, " + 1")
            nodes[#nodes + 1] = C.stmt("if ", op.count, " > ", op.limit, " then do return ", term.final_expr, " end end")
            nodes[#nodes + 1] = C.stmt("end")
        elseif op.kind == OP_DROP then
            nodes[#nodes + 1] = C.stmt("if __emit then")
            nodes[#nodes + 1] = C.stmt(op.count, " = ", op.count, " + 1")
            nodes[#nodes + 1] = C.stmt("if ", op.count, " <= ", op.limit, " then __emit = false end")
            nodes[#nodes + 1] = C.stmt("end")
        else
            _error("unknown op kind: " .. _tostring(op.kind))
        end
    end

    if nops > 0 then
        nodes[#nodes + 1] = C.stmt("if __emit then")
        append_nodes(nodes, term.step)
        nodes[#nodes + 1] = C.stmt("end")
    else
        append_nodes(nodes, term.step)
    end

    return nodes
end

local function terminal_sink_plan(kind, _env)
    if kind == "each" then
        return {
            init = {},
            final_expr = "nil",
            step = {
                C.stmt("term_arg1(__v)"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "fold" then
        return {
            init = {
                C.stmt("local acc = term_arg2"),
            },
            final_expr = "acc",
            step = {
                C.stmt("acc = term_arg1(acc, __v)"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "collect" then
        return {
            init = {
                C.stmt("local out = {}"),
                C.stmt("local n = 0"),
            },
            final_expr = "out",
            step = {
                C.stmt("n = n + 1"),
                C.stmt("out[n] = __v"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "count" then
        return {
            init = {
                C.stmt("local n = 0"),
            },
            final_expr = "n",
            step = {
                C.stmt("n = n + 1"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "head" then
        return {
            init = {
                C.stmt("local found = nil"),
            },
            final_expr = "found",
            step = {
                C.stmt("found = __v"),
                C.stmt("return STOP"),
            },
        }
    end

    if kind == "nth" then
        return {
            init = {
                C.stmt("local nth_count = 0"),
                C.stmt("local found = nil"),
            },
            final_expr = "found",
            step = {
                C.stmt("nth_count = nth_count + 1"),
                C.stmt("if nth_count == term_arg1 then"),
                C.stmt("found = __v"),
                C.stmt("return STOP"),
                C.stmt("end"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "any" then
        return {
            init = {
                C.stmt("local ok = false"),
            },
            final_expr = "ok",
            step = {
                C.stmt("if term_arg1(__v) then"),
                C.stmt("ok = true"),
                C.stmt("return STOP"),
                C.stmt("end"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "all" then
        return {
            init = {
                C.stmt("local ok = true"),
            },
            final_expr = "ok",
            step = {
                C.stmt("if not term_arg1(__v) then"),
                C.stmt("ok = false"),
                C.stmt("return STOP"),
                C.stmt("end"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "sum" then
        return {
            init = {
                C.stmt("local acc = 0"),
            },
            final_expr = "acc",
            step = {
                C.stmt("acc = acc + __v"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "min" then
        return {
            init = {
                C.stmt("local seen = false"),
                C.stmt("local acc = nil"),
            },
            final_expr = "acc",
            step = {
                C.stmt("if not seen then"),
                C.stmt("seen = true"),
                C.stmt("acc = __v"),
                C.stmt("elseif __v < acc then"),
                C.stmt("acc = __v"),
                C.stmt("end"),
                C.stmt("return nil"),
            },
        }
    end

    if kind == "max" then
        return {
            init = {
                C.stmt("local seen = false"),
                C.stmt("local acc = nil"),
            },
            final_expr = "acc",
            step = {
                C.stmt("if not seen then"),
                C.stmt("seen = true"),
                C.stmt("acc = __v"),
                C.stmt("elseif __v > acc then"),
                C.stmt("acc = __v"),
                C.stmt("end"),
                C.stmt("return nil"),
            },
        }
    end

    _error("unknown terminal kind: " .. _tostring(kind))
end

local function process_sink_nodes(value_expr, bound_ops, nops, term)
    local nodes = {
        C.stmt("local __v = ", value_expr),
    }

    if nops > 0 then
        nodes[#nodes + 1] = C.stmt("local __emit = true")
    end

    for i = 1, nops do
        local op = bound_ops[i]
        if op.kind == OP_MAP then
            nodes[#nodes + 1] = C.stmt("if __emit then __v = ", op.fn, "(__v) end")
        elseif op.kind == OP_FILTER then
            nodes[#nodes + 1] = C.stmt("if __emit and not ", op.fn, "(__v) then __emit = false end")
        elseif op.kind == OP_TAKE then
            nodes[#nodes + 1] = C.stmt("if __emit then")
            nodes[#nodes + 1] = C.stmt(op.count, " = ", op.count, " + 1")
            nodes[#nodes + 1] = C.stmt("if ", op.count, " > ", op.limit, " then return STOP end")
            nodes[#nodes + 1] = C.stmt("end")
        elseif op.kind == OP_DROP then
            nodes[#nodes + 1] = C.stmt("if __emit then")
            nodes[#nodes + 1] = C.stmt(op.count, " = ", op.count, " + 1")
            nodes[#nodes + 1] = C.stmt("if ", op.count, " <= ", op.limit, " then __emit = false end")
            nodes[#nodes + 1] = C.stmt("end")
        else
            _error("unknown op kind: " .. _tostring(op.kind))
        end
    end

    if nops > 0 then
        nodes[#nodes + 1] = C.stmt("if __emit then")
        append_nodes(nodes, term.step)
        nodes[#nodes + 1] = C.stmt("end")
        nodes[#nodes + 1] = C.stmt("return nil")
    else
        append_nodes(nodes, term.step)
    end

    return nodes
end

local function source_body_nodes(root, bound_ops, nops, term, env)
    local kind = root.source_kind

    if kind == SOURCE_ARRAY then
        env.xs = root.a
        env.i0 = root.b or 1
        env.i1 = root.c or _rawlen(root.a)
        return {
            C.nest(C.clause("for i = i0, i1 do"), C.body(process_nodes("xs[i]", bound_ops, nops, term)), C.clause("end")),
        }
    end

    if kind == SOURCE_RANGE then
        env.range_start = root.a
        env.range_stop = root.b
        env.range_step = root.c
        return {
            C.nest(C.clause("for i = range_start, range_stop, range_step do"), C.body(process_nodes("i", bound_ops, nops, term)), C.clause("end")),
        }
    end

    if kind == SOURCE_STRING then
        env.s = root.a
        env.i0 = root.b or 1
        env.i1 = root.c or #root.a
        env.string_sub = _string_sub
        return {
            C.nest(C.clause("for i = i0, i1 do"), C.body(process_nodes("string_sub(s, i, i)", bound_ops, nops, term)), C.clause("end")),
        }
    end

    if kind == SOURCE_BYTES then
        env.s = root.a
        env.i0 = root.b or 1
        env.i1 = root.c or #root.a
        env.string_byte = _string_byte
        return {
            C.nest(C.clause("for i = i0, i1 do"), C.body(process_nodes("string_byte(s, i)", bound_ops, nops, term)), C.clause("end")),
        }
    end

    if kind == SOURCE_RAW then
        env.gen = root.a
        env.param = root.b
        env.state0 = root.c
        local inner = {
            C.stmt("local new_state, value = gen(param, state)"),
            C.stmt("if new_state == nil then break end"),
            C.stmt("state = new_state"),
        }
        append_nodes(inner, process_nodes("value", bound_ops, nops, term))
        return {
            C.stmt("local state = state0"),
            C.nest(C.clause("while true do"), C.body(inner), C.clause("end")),
        }
    end

    return nil
end

local function string_plain_terminal_executor(shape, kind)
    if shape.exec_kind ~= EXEC_STRING_PLAIN then
        return nil
    end

    local root = shape.root
    local env = {
        s = root.a,
        i0 = root.b or 1,
        i1 = root.c or #root.a,
        string_sub = _string_sub,
        string_byte = _string_byte,
        string_char = _string_char,
    }

    local body

    if kind == "head" then
        body = C.body({
            C.stmt("if i0 <= i1 then"),
            C.stmt("return string_sub(s, i0, i0)"),
            C.stmt("end"),
            C.stmt("return nil"),
        })
    elseif kind == "nth" then
        body = C.body({
            C.stmt("local i = i0 + term_arg1 - 1"),
            C.stmt("if i <= i1 then"),
            C.stmt("return string_sub(s, i, i)"),
            C.stmt("end"),
            C.stmt("return nil"),
        })
    elseif kind == "any" then
        body = C.body({
            C.nest(C.clause("for i = i0, i1 do"), C.body({
                C.stmt("if term_arg1(string_sub(s, i, i)) then"),
                C.stmt("return true"),
                C.stmt("end"),
            }), C.clause("end")),
            C.stmt("return false"),
        })
    elseif kind == "all" then
        body = C.body({
            C.nest(C.clause("for i = i0, i1 do"), C.body({
                C.stmt("if not term_arg1(string_sub(s, i, i)) then"),
                C.stmt("return false"),
                C.stmt("end"),
            }), C.clause("end")),
            C.stmt("return true"),
        })
    elseif kind == "min" then
        body = C.body({
            C.stmt("if i0 > i1 then return nil end"),
            C.stmt("local acc = string_byte(s, i0)"),
            C.nest(C.clause("for i = i0 + 1, i1 do"), C.body({
                C.stmt("local b = string_byte(s, i)"),
                C.stmt("if b < acc then acc = b end"),
            }), C.clause("end")),
            C.stmt("return string_char(acc)"),
        })
    elseif kind == "max" then
        body = C.body({
            C.stmt("if i0 > i1 then return nil end"),
            C.stmt("local acc = string_byte(s, i0)"),
            C.nest(C.clause("for i = i0 + 1, i1 do"), C.body({
                C.stmt("local b = string_byte(s, i)"),
                C.stmt("if b > acc then acc = b end"),
            }), C.clause("end")),
            C.stmt("return string_char(acc)"),
        })
    end

    if not body then
        return nil
    end

    return compile_proto(_string_format("@more-fun:string-%s", kind), { "term_arg1", "term_arg2" }, env, body)
end

local function chain_terminal_executor(shape, kind)
    if shape.exec_kind ~= EXEC_CHAIN then
        return nil
    end

    local env = {
        STOP = STOP,
    }
    local bound_ops, op_state_nodes = bind_ops(shape.ops, shape.nops, env)
    local term = terminal_sink_plan(kind, env)

    local body = {}
    append_nodes(body, term.init)
    append_nodes(body, op_state_nodes)
    body[#body + 1] = C.stmt("local function process(__v)")
    append_nodes(body, process_sink_nodes("__v", bound_ops, shape.nops, term))
    body[#body + 1] = C.stmt("end")

    local sources = shape.root.a
    for i = 1, #sources do
        local name = "subrunner_" .. i
        env[name] = sources[i]:_runner()
        body[#body + 1] = C.stmt("if ", name, "(process) == STOP then return ", term.final_expr, " end")
    end

    body[#body + 1] = C.stmt("return ", term.final_expr)

    return compile_proto(_string_format("@more-fun:chain-%s", kind), { "term_arg1", "term_arg2" }, env, C.body(body))
end

local function generated_terminal_executor(shape, kind)
    local env = {}
    local bound_ops, op_state_nodes = bind_ops(shape.ops, shape.nops, env)
    local term = terminal_plan(kind, env)
    local loop_nodes = source_body_nodes(shape.root, bound_ops, shape.nops, term, env)
    if not loop_nodes then
        return nil
    end

    local body = {}
    append_nodes(body, term.init)
    append_nodes(body, op_state_nodes)
    append_nodes(body, loop_nodes)
    body[#body + 1] = C.stmt("return ", term.final_expr)

    return compile_proto(
        _string_format("@more-fun:%s:%d", kind, shape.root.source_kind),
        { "term_arg1", "term_arg2" },
        env,
        C.body(body)
    )
end

compile_terminal_executor = function(self, kind)
    local plan = plan_for(self, kind)
    local runner

    if plan.install_kind == "empty" then
        return empty_terminal_executor(kind)
    end

    if plan.install_kind == "string_plain" then
        runner = string_plain_terminal_executor(plan.shape, kind)
        if runner then
            return runner
        end
    end

    if plan.install_kind == "chain" then
        runner = chain_terminal_executor(plan.shape, kind)
        if runner then
            return runner
        end
    end

    if plan.install_kind == "generated" then
        runner = generated_terminal_executor(plan.shape, kind)
        if runner then
            return runner
        end
    end

    return generic_terminal_executor(self, kind)
end

-- -----------------------------------------------------------------------------
-- Public combinators
-- -----------------------------------------------------------------------------

function methods:map(fn)
    _assert(_type(fn) == "function", "map expects a function")
    return new_op(self, OP_MAP, fn)
end

function methods:filter(fn)
    _assert(_type(fn) == "function", "filter expects a function")
    return new_op(self, OP_FILTER, fn)
end

function methods:take(n)
    _assert(_type(n) == "number" and n >= 0, "take expects a non-negative number")
    return new_op(self, OP_TAKE, n)
end

function methods:drop(n)
    _assert(_type(n) == "number" and n >= 0, "drop expects a non-negative number")
    return new_op(self, OP_DROP, n)
end

function methods:each(fn)
    _assert(_type(fn) == "function", "each expects a function")
    return self:compile("each")(fn)
end

methods.for_each = methods.each
methods.foreach = methods.each

function methods:fold(fn, init)
    _assert(_type(fn) == "function", "fold expects a function")
    return self:compile("fold")(fn, init)
end

methods.foldl = methods.fold
methods.reduce = methods.fold

function methods:collect()
    return self:compile("collect")()
end

methods.totable = methods.collect
methods.to_table = methods.collect

function methods:count()
    return self:compile("count")()
end

methods.length = methods.count

function methods:head()
    return self:compile("head")()
end

methods.first = methods.head

function methods:nth(n)
    _assert(_type(n) == "number" and n >= 1, "nth expects a positive number")
    return self:compile("nth")(n)
end

function methods:any(fn)
    _assert(_type(fn) == "function", "any expects a function")
    return self:compile("any")(fn)
end

methods.some = methods.any

function methods:all(fn)
    _assert(_type(fn) == "function", "all expects a function")
    return self:compile("all")(fn)
end

methods.every = methods.all

function methods:sum()
    return self:compile("sum")()
end

methods.skip = methods.drop

function methods:min()
    return self:compile("min")()
end

function methods:max()
    return self:compile("max")()
end

-- -----------------------------------------------------------------------------
-- Sources
-- -----------------------------------------------------------------------------

local function empty()
    return new_source(SOURCE_EMPTY)
end

local function chars(text)
    _assert(_type(text) == "string", "chars expects a string")
    if #text == 0 then
        return empty()
    end
    return new_source(SOURCE_STRING, text, 1, #text)
end

local function bytes(text)
    _assert(_type(text) == "string", "bytes expects a string")
    if #text == 0 then
        return empty()
    end
    return new_source(SOURCE_BYTES, text, 1, #text)
end

local function generate(gen, param, state)
    _assert(_type(gen) == "function", "generate expects a generator function")
    return new_source(SOURCE_RAW, gen, param, state)
end

local function from(obj, param, state)
    if is_pipeline(obj) then
        return obj
    end

    local t = _type(obj)

    if t == "table" then
        local mt = _getmetatable(obj)
        if mt == pipeline_mt then
            return obj
        end

        if _type(obj.gen) == "function" then
            return generate(obj.gen, obj.param, obj.state)
        end

        local n = _rawlen(obj)
        if n > 0 then
            return new_source(SOURCE_ARRAY, obj, 1, n)
        end

        return empty()
    end

    if t == "function" then
        return generate(obj, param, state)
    end

    if t == "string" then
        return chars(obj)
    end

    if obj == nil then
        return empty()
    end

    _error(_string_format('object %s of type "%s" is not iterable by more-fun', obj, t))
end

local function iter(obj, param, state)
    return from(obj, param, state)
end

local function wrap(gen, param, state)
    return generate(gen, param, state)
end

local function range(start, stop, step)
    if step == nil then
        if stop == nil then
            if start == 0 then
                return empty()
            end
            stop = start
            start = stop > 0 and 1 or -1
        end
        step = start <= stop and 1 or -1
    end

    _assert(_type(start) == "number", "start must be a number")
    _assert(_type(stop) == "number", "stop must be a number")
    _assert(_type(step) == "number", "step must be a number")
    _assert(step ~= 0, "step must not be zero")

    if step > 0 and start > stop then
        return empty()
    end
    if step < 0 and start < stop then
        return empty()
    end

    return new_source(SOURCE_RANGE, start, stop, step)
end

local function chain(...)
    local n = _select("#", ...)
    if n == 0 then
        return empty()
    end

    local sources = {}
    for i = 1, n do
        sources[i] = from(_select(i, ...))
    end
    return new_source(SOURCE_CHAIN, sources)
end

local function concat(...)
    return chain(...)
end

local function of(...)
    local n = _select("#", ...)
    if n == 0 then
        return empty()
    end
    local xs = {}
    for i = 1, n do
        xs[i] = _select(i, ...)
    end
    return new_source(SOURCE_ARRAY, xs, 1, n)
end

local function export0(method_name)
    return function(gen, param, state)
        local it = from(gen, param, state)
        return it[method_name](it)
    end
end

local function export1(method_name)
    return function(arg1, gen, param, state)
        local it = from(gen, param, state)
        return it[method_name](it, arg1)
    end
end

local function export2(method_name)
    return function(arg1, arg2, gen, param, state)
        local it = from(gen, param, state)
        return it[method_name](it, arg1, arg2)
    end
end

M.from = from
M.iter = from
M.empty = empty
M.of = of
M.range = range
M.chars = chars
M.bytes = bytes
M.generate = generate
M.wrap = generate
M.chain = chain
M.concat = chain

M.map = export1("map")
M.filter = export1("filter")
M.take = export1("take")
M.drop = export1("drop")
M.skip = export1("skip")
M.each = export1("each")
M.for_each = M.each
M.foreach = M.each
M.fold = export2("fold")
M.foldl = M.fold
M.reduce = M.fold
M.collect = export0("collect")
M.totable = M.collect
M.to_table = M.collect
M.count = export0("count")
M.length = M.count
M.shape = export0("shape")
M.plan = export1("plan")
M.compile = export1("compile")
M.head = export0("head")
M.first = M.head
M.nth = export1("nth")
M.any = export1("any")
M.some = M.any
M.all = export1("all")
M.every = M.all
M.sum = export0("sum")
M.min = export0("min")
M.max = export0("max")

return M
