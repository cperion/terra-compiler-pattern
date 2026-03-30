-- js_compile.lua
--
-- Terminal: JsResolved -> closure tree
-- ----------------------------------------------------------------------------
-- This is the leaf compiler. It takes scope-resolved JS AST and produces
-- a closure tree that LuaJIT traces through.
--
-- Architecture:
--   gen   = closure shape (monomorphic code path per AST node)
--   param = compile-time constants captured as upvalues
--   state = frame E (array of local variable slots)
--
-- The key insight: each AST node compiles to one closure at compile time.
-- At runtime, the closure tree is called with a frame array E. No AST
-- interpretation happens at runtime.

local U = require("unit")

local rt_mod = require("examples.js.js_runtime")
local JS_NULL = rt_mod.JS_NULL
local JS_TDZ = rt_mod.JS_TDZ
local js_typeof = rt_mod.js_typeof
local js_loose_equal = rt_mod.js_loose_equal
local js_truthy = rt_mod.js_truthy
local js_add = rt_mod.js_add
local js_array = rt_mod.js_array
local js_object = rt_mod.js_object
local js_instanceof = rt_mod.js_instanceof
local js_globals = rt_mod.js_globals
local js_call = rt_mod.js_call
local js_register_callable = rt_mod.js_register_callable
local JS_CALL_SENTINEL = rt_mod.JS_CALL_SENTINEL
local js_return = rt_mod.js_return
local is_return = rt_mod.is_return
local BREAK = rt_mod.BREAK
local CONTINUE = rt_mod.CONTINUE
local js_break = rt_mod.js_break
local js_continue = rt_mod.js_continue
local is_break = rt_mod.is_break
local is_continue = rt_mod.is_continue
local bit = rt_mod.bit

local unpack = table.unpack or unpack

-- String coercion helper: ASDL cdata strings -> Lua strings
local ffi = require("ffi")
local function S(v)
    if v == nil then return nil end
    if type(v) == "cdata" then return ffi.string(v) end
    return tostring(v)
end

-- ═══════════════════════════════════════════════════════════════
-- Frame helpers
-- ═══════════════════════════════════════════════════════════════
-- A frame E is a flat array: E[1..N] = local slots.
-- Nested scopes create new frames that chain via E[0] = parent.

local function new_frame(parent, size)
    local E = {}
    E[0] = parent
    E.__this = parent and parent.__this or nil
    return E
end

local function clone_frame(E, size)
    local out = new_frame(E[0], size)
    for i = 1, size do out[i] = E[i] end
    return out
end

local function frame_read(E, depth, index)
    local f = E
    for _ = 1, depth do f = f[0] end
    return f[index]
end

local function frame_write(E, depth, index, value)
    local f = E
    for _ = 1, depth do f = f[0] end
    f[index] = value
end

local function stmt_kind(stmt)
    return stmt and S(stmt.kind) or nil
end

local function varkind_name(var_kind)
    if not var_kind then return nil end
    return S(var_kind.kind or var_kind)
end

-- ═══════════════════════════════════════════════════════════════
-- Globals object
-- ═══════════════════════════════════════════════════════════════
-- Global variables live in a shared table.

local function make_globals()
    local g = {}
    for k, v in pairs(js_globals) do g[k] = v end
    return g
end

-- ═══════════════════════════════════════════════════════════════
-- Expression compiler
-- ═══════════════════════════════════════════════════════════════
-- compile_expr: JsResolved.Expr -> (E -> value)
-- Each call returns a CLOSURE. At runtime, that closure takes the
-- current frame E and returns a JS value.

local compile_expr
local compile_stmt
local compile_stmts

-- Numeric coercion for ASDL cdata fields
local function N(v) return tonumber(v) end

local function matches_continue_target(signal, targets)
    if type(signal) ~= "table" or signal.__js_continue ~= true then return false end
    local target = signal.target
    for i = 1, #targets do
        if (tonumber(targets[i]) or targets[i]) == target then return true end
    end
    return false
end

local ACTIVE_SLOT_HOOKS = nil

local function compile_plain_slot_read(slot, globals, current_depth)
    current_depth = current_depth or 0
    return U.match(slot, {
        LocalSlot = function(s)
            local d, idx = current_depth - N(s.depth), N(s.index)
            local function guard(v)
                if rawequal(v, JS_TDZ) then
                    error("Cannot access lexical binding before initialization")
                end
                return v
            end
            if d == 0 then
                return function(E) return guard(E[idx]) end
            elseif d == 1 then
                return function(E) return guard(E[0][idx]) end
            else
                return function(E) return guard(frame_read(E, d, idx)) end
            end
        end,
        GlobalSlot = function(s)
            local name = S(s.name)
            return function(E) return globals[name] end
        end,
    })
end

local function compile_plain_slot_init(slot, globals, current_depth)
    current_depth = current_depth or 0
    return U.match(slot, {
        LocalSlot = function(s)
            local d, idx = current_depth - N(s.depth), N(s.index)
            if d == 0 then
                return function(E, v) E[idx] = v end
            elseif d == 1 then
                return function(E, v) E[0][idx] = v end
            else
                return function(E, v) frame_write(E, d, idx, v) end
            end
        end,
        GlobalSlot = function(s)
            local name = S(s.name)
            return function(E, v) globals[name] = v end
        end,
    })
end

local function compile_plain_slot_write(slot, globals, current_depth)
    current_depth = current_depth or 0
    return U.match(slot, {
        LocalSlot = function(s)
            local d, idx = current_depth - N(s.depth), N(s.index)
            local binding_kind = varkind_name(s.binding_kind)
            local function assign(E, v)
                if d == 0 then
                    E[idx] = v
                elseif d == 1 then
                    E[0][idx] = v
                else
                    frame_write(E, d, idx, v)
                end
            end
            if binding_kind == "Const" then
                return function(E, v)
                    error("assignment to const binding")
                end
            end
            return assign
        end,
        GlobalSlot = function(s)
            local name = S(s.name)
            return function(E, v) globals[name] = v end
        end,
    })
end

local function compile_slot_read(slot, globals, current_depth)
    local hooks = ACTIVE_SLOT_HOOKS
    if hooks and hooks.read_slot then
        local custom = hooks.read_slot(slot, globals, current_depth, function()
            return compile_plain_slot_read(slot, globals, current_depth)
        end)
        if custom then return custom end
    end
    return compile_plain_slot_read(slot, globals, current_depth)
end

local function compile_slot_init(slot, globals, current_depth)
    local hooks = ACTIVE_SLOT_HOOKS
    if hooks and hooks.init_slot then
        local custom = hooks.init_slot(slot, globals, current_depth, function()
            return compile_plain_slot_init(slot, globals, current_depth)
        end)
        if custom then return custom end
    end
    return compile_plain_slot_init(slot, globals, current_depth)
end

local function compile_slot_write(slot, globals, current_depth)
    local hooks = ACTIVE_SLOT_HOOKS
    if hooks and hooks.write_slot then
        local custom = hooks.write_slot(slot, globals, current_depth, function()
            return compile_plain_slot_write(slot, globals, current_depth)
        end)
        if custom then return custom end
    end
    return compile_plain_slot_write(slot, globals, current_depth)
end

local function lexical_tdz_slots(scope, initialized_slots)
    local init = initialized_slots or {}
    local out = {}
    if not scope then return out end
    for i = 1, #scope.bindings do
        local b = scope.bindings[i]
        local idx = N(b.slot)
        if varkind_name(b.kind) ~= "Var" and not init[idx] then
            out[#out + 1] = idx
        end
    end
    return out
end

local function init_tdz_slots(E, slots)
    for i = 1, #slots do E[slots[i]] = JS_TDZ end
end

local function compile_var_hoist(stmt, globals, depth)
    local writes = {}
    for i = 1, #stmt.decls do
        writes[i] = compile_slot_init(stmt.decls[i].target, globals, depth)
    end
    local n = #writes
    return function(E)
        for i = 1, n do writes[i](E, nil) end
        return nil
    end
end

local function scope_init_plan(scope, body, initialized_slots)
    local init = {}
    if initialized_slots then
        for k, v in pairs(initialized_slots) do init[k] = v and true or false end
    end

    local instantiate_stmts = {}
    local eval_stmts = {}
    for i = 1, #body do
        local stmt = body[i]
        local kind = stmt_kind(stmt)
        if kind == "FuncDecl" then
            instantiate_stmts[#instantiate_stmts + 1] = stmt
            init[N(stmt.target.index)] = true
        elseif kind == "VarDecl" and varkind_name(stmt.var_kind) == "Var" then
            instantiate_stmts[#instantiate_stmts + 1] = stmt
            eval_stmts[#eval_stmts + 1] = stmt
        else
            eval_stmts[#eval_stmts + 1] = stmt
        end
    end

    local tdz_slots = lexical_tdz_slots(scope, init)

    return instantiate_stmts, eval_stmts, tdz_slots
end

local function compile_scope_runner(scope, body, globals, depth, initialized_slots)
    local instantiate_stmts, eval_stmts, tdz_slots = scope_init_plan(scope, body, initialized_slots)
    local instantiate_fns = {}
    for i = 1, #instantiate_stmts do
        local stmt = instantiate_stmts[i]
        if stmt_kind(stmt) == "FuncDecl" then
            instantiate_fns[#instantiate_fns + 1] = compile_stmt(stmt, globals, depth)
        else
            instantiate_fns[#instantiate_fns + 1] = compile_var_hoist(stmt, globals, depth)
        end
    end
    local eval_fns = {}
    for i = 1, #eval_stmts do
        eval_fns[i] = compile_stmt(eval_stmts[i], globals, depth)
    end

    return function(E, preinit)
        init_tdz_slots(E, tdz_slots)
        if preinit then preinit(E) end
        for i = 1, #instantiate_fns do
            local signal = instantiate_fns[i](E)
            if signal ~= nil then return signal end
        end
        for i = 1, #eval_fns do
            local signal = eval_fns[i](E)
            if signal ~= nil then return signal end
        end
        return nil
    end
end

compile_expr = function(node, globals, depth)
    depth = depth or 0
    return U.match(node, {
        NumLit = function(e)
            local v = tonumber(e.value)
            return function(E) return v end
        end,

        StrLit = function(e)
            local v = S(e.value)
            return function(E) return v end
        end,

        BoolLit = function(e)
            local v = (e.value ~= false and e.value ~= 0)
            return function(E) return v end
        end,

        NullLit = function(e)
            return function(E) return JS_NULL end
        end,

        UndefinedLit = function(e)
            return function(E) return nil end
        end,

        SlotRef = function(e)
            return compile_slot_read(e.slot, globals, depth)
        end,

        BinOp = function(e)
            local left = compile_expr(e.left, globals, depth)
            local right = compile_expr(e.right, globals, depth)
            local op = S(e.op.kind)

            if op == "Add" then
                return function(E) return js_add(left(E), right(E)) end
            elseif op == "Sub" then
                return function(E) return left(E) - right(E) end
            elseif op == "Mul" then
                return function(E) return left(E) * right(E) end
            elseif op == "Div" then
                return function(E) return left(E) / right(E) end
            elseif op == "Mod" then
                return function(E) return left(E) % right(E) end
            elseif op == "Exp" then
                return function(E) return left(E) ^ right(E) end
            elseif op == "EqEqEq" then
                return function(E) return left(E) == right(E) end
            elseif op == "NotEqEq" then
                return function(E) return left(E) ~= right(E) end
            elseif op == "EqEq" then
                return function(E) return js_loose_equal(left(E), right(E)) end
            elseif op == "NotEq" then
                return function(E) return not js_loose_equal(left(E), right(E)) end
            elseif op == "Lt" then
                return function(E) return left(E) < right(E) end
            elseif op == "Le" then
                return function(E) return left(E) <= right(E) end
            elseif op == "Gt" then
                return function(E) return left(E) > right(E) end
            elseif op == "Ge" then
                return function(E) return left(E) >= right(E) end
            elseif op == "BitAnd" then
                return function(E) return bit.band(left(E), right(E)) end
            elseif op == "BitOr" then
                return function(E) return bit.bor(left(E), right(E)) end
            elseif op == "BitXor" then
                return function(E) return bit.bxor(left(E), right(E)) end
            elseif op == "Shl" then
                return function(E) return bit.lshift(left(E), right(E)) end
            elseif op == "Shr" then
                return function(E) return bit.arshift(left(E), right(E)) end
            elseif op == "UShr" then
                return function(E) return bit.rshift(left(E), right(E)) end
            else
                error("compile_expr: unknown BinOp " .. tostring(op))
            end
        end,

        LogicalOp = function(e)
            local left = compile_expr(e.left, globals, depth)
            local right = compile_expr(e.right, globals, depth)
            local op = S(e.op.kind)

            if op == "LogAnd" then
                return function(E)
                    local l = left(E)
                    if not js_truthy(l) then return l end
                    return right(E)
                end
            elseif op == "LogOr" then
                return function(E)
                    local l = left(E)
                    if js_truthy(l) then return l end
                    return right(E)
                end
            else
                error("compile_expr: unknown LogicalOp " .. tostring(op))
            end
        end,

        UnaryOp = function(e)
            local arg = compile_expr(e.argument, globals, depth)
            local op = S(e.op.kind)

            if op == "UNeg" then
                return function(E) return -(arg(E)) end
            elseif op == "UPos" then
                return function(E) return tonumber(arg(E)) or 0/0 end
            elseif op == "UBitNot" then
                return function(E) return bit.bnot(arg(E)) end
            elseif op == "ULogNot" then
                return function(E) return not js_truthy(arg(E)) end
            else
                error("compile_expr: unknown UnaryOp " .. tostring(op))
            end
        end,

        UpdateOp = function(e)
            -- ++x or x++ on a SlotRef
            local arg_expr = e.argument
            if S(arg_expr.kind) ~= "SlotRef" then
                error("compile_expr: UpdateOp requires SlotRef target")
            end
            local read = compile_slot_read(arg_expr.slot, globals, depth)
            local write = compile_slot_write(arg_expr.slot, globals, depth)
            local is_inc = S(e.op.kind) == "Inc"

            if e.prefix then
                return function(E)
                    local v = (tonumber(read(E)) or 0) + (is_inc and 1 or -1)
                    write(E, v)
                    return v
                end
            else
                return function(E)
                    local old = tonumber(read(E)) or 0
                    write(E, old + (is_inc and 1 or -1))
                    return old
                end
            end
        end,

        Assign = function(e)
            local val = compile_expr(e.right, globals, depth)

            if S(e.left.kind) == "SlotRef" then
                local write = compile_slot_write(e.left.slot, globals, depth)
                return function(E)
                    local v = val(E)
                    write(E, v)
                    return v
                end
            elseif S(e.left.kind) == "Member" then
                local obj = compile_expr(e.left.object, globals, depth)
                if e.left.computed then
                    local prop = compile_expr(e.left.property, globals, depth)
                    return function(E)
                        local v = val(E)
                        obj(E)[prop(E)] = v
                        return v
                    end
                else
                    local field = S(e.left.property.value)  -- StrLit
                    return function(E)
                        local v = val(E)
                        obj(E)[field] = v
                        return v
                    end
                end
            else
                error("compile_expr: unsupported Assign target " .. tostring(S(e.left.kind)))
            end
        end,

        CompoundAssign = function(e)
            -- a += b  etc
            local right = compile_expr(e.right, globals, depth)
            local op = S(e.op.kind)

            if S(e.left.kind) == "SlotRef" then
                local read = compile_slot_read(e.left.slot, globals, depth)
                local write = compile_slot_write(e.left.slot, globals, depth)

                local apply_op
                if op == "Add" then apply_op = js_add
                elseif op == "Sub" then apply_op = function(a, b) return a - b end
                elseif op == "Mul" then apply_op = function(a, b) return a * b end
                elseif op == "Div" then apply_op = function(a, b) return a / b end
                elseif op == "Mod" then apply_op = function(a, b) return a % b end
                else error("compile_expr: unsupported CompoundAssign op " .. tostring(op))
                end

                return function(E)
                    local v = apply_op(read(E), right(E))
                    write(E, v)
                    return v
                end
            else
                error("compile_expr: unsupported CompoundAssign target")
            end
        end,

        Member = function(e)
            local obj = compile_expr(e.object, globals, depth)
            if e.computed then
                local prop = compile_expr(e.property, globals, depth)
                return function(E) return obj(E)[prop(E)] end
            else
                local field = S(e.property.value)  -- StrLit from parser
                return function(E) return obj(E)[field] end
            end
        end,

        Optional = function(e)
            local obj = compile_expr(e.object, globals, depth)
            if e.computed then
                local prop = compile_expr(e.property, globals, depth)
                return function(E)
                    local o = obj(E)
                    if o == nil or o == JS_NULL then return nil end
                    return o[prop(E)]
                end
            else
                local field = S(e.property.value)
                return function(E)
                    local o = obj(E)
                    if o == nil or o == JS_NULL then return nil end
                    return o[field]
                end
            end
        end,

        Call = function(e)
            local n = #e.arguments
            local args = {}
            for i = 1, n do args[i] = compile_expr(e.arguments[i], globals, depth) end

            local invoke_vals = function(fn, recv, E)
                if n == 0 then
                    return js_call(fn, recv)
                elseif n == 1 then
                    return js_call(fn, recv, args[1](E))
                elseif n == 2 then
                    return js_call(fn, recv, args[1](E), args[2](E))
                elseif n == 3 then
                    return js_call(fn, recv, args[1](E), args[2](E), args[3](E))
                else
                    local vals = {}
                    for i = 1, n do vals[i] = args[i](E) end
                    return js_call(fn, recv, unpack(vals, 1, n))
                end
            end

            if S(e.callee.kind) == "Member" then
                local m = e.callee
                local obj = compile_expr(m.object, globals, depth)
                if m.computed then
                    local prop = compile_expr(m.property, globals, depth)
                    return function(E)
                        local recv = obj(E)
                        local fn = recv[prop(E)]
                        return invoke_vals(fn, recv, E)
                    end
                else
                    local field = S(m.property.value)
                    return function(E)
                        local recv = obj(E)
                        local fn = recv[field]
                        return invoke_vals(fn, recv, E)
                    end
                end
            end

            local callee = compile_expr(e.callee, globals, depth)
            return function(E)
                return invoke_vals(callee(E), nil, E)
            end
        end,

        New = function(e)
            local ctor = compile_expr(e.callee, globals, depth)
            local args = {}
            for i = 1, #e.arguments do
                args[i] = compile_expr(e.arguments[i], globals, depth)
            end
            local n = #args
            return function(E)
                local cls = ctor(E)
                local instance = setmetatable({}, cls.__proto__ or {})
                local vals = {}
                for i = 1, n do vals[i] = args[i](E) end
                local result = cls(instance, unpack(vals, 1, n))
                if type(result) == "table" then return result end
                return instance
            end
        end,

        Cond = function(e)
            local test = compile_expr(e.test, globals, depth)
            local cons = compile_expr(e.consequent, globals, depth)
            local alt = compile_expr(e.alternate, globals, depth)
            return function(E)
                if js_truthy(test(E)) then return cons(E) end
                return alt(E)
            end
        end,

        Arrow = function(e)
            local params = e.params
            local np = #params
            local frame_size = e.scope and N(e.scope.slot_count) or np
            local initialized_slots = {}
            for i = 1, np do initialized_slots[i] = true end

            return U.match(e.body, {
                ArrowExpr = function(ab)
                    local body = compile_expr(ab.expr, globals, depth + 1)
                    return function(E)
                        return js_register_callable(function(a, b, ...)
                            local inner = new_frame(E, frame_size)
                            local argv
                            if a == JS_CALL_SENTINEL then
                                argv = { ... }
                            else
                                argv = { a, b, ... }
                            end
                            for i = 1, np do inner[i] = argv[i] end
                            return body(inner)
                        end, "compiled")
                    end
                end,
                ArrowBlock = function(ab)
                    local body = compile_scope_runner(e.scope, ab.body, globals, depth + 1, initialized_slots)
                    return function(E)
                        return js_register_callable(function(a, b, ...)
                            local inner = new_frame(E, frame_size)
                            local argv
                            if a == JS_CALL_SENTINEL then
                                argv = { ... }
                            else
                                argv = { a, b, ... }
                            end
                            local function init(inner_frame)
                                for i = 1, np do inner_frame[i] = argv[i] end
                            end
                            local signal = body(inner, init)
                            if is_return(signal) then return signal.value end
                            return nil
                        end, "compiled")
                    end
                end,
            })
        end,

        FuncExpr = function(e)
            local params = e.params
            local np = #params
            local frame_size = e.scope and N(e.scope.slot_count) or np
            local name_offset = e.name and 1 or 0
            local initialized_slots = {}
            if name_offset == 1 then initialized_slots[1] = true end
            for i = 1, np do initialized_slots[i + name_offset] = true end
            local body = compile_scope_runner(e.scope, e.body, globals, depth + 1, initialized_slots)
            return function(E)
                local fn
                fn = js_register_callable(function(a, b, ...)
                    local call_this, argv
                    if a == JS_CALL_SENTINEL then
                        call_this = b
                        argv = { ... }
                    else
                        call_this = nil
                        argv = { a, b, ... }
                    end
                    local inner = new_frame(E, frame_size)
                    inner.__this = call_this
                    local function init(inner_frame)
                        if name_offset == 1 then inner_frame[1] = fn end
                        for i = 1, np do inner_frame[i + name_offset] = argv[i] end
                    end
                    local signal = body(inner, init)
                    if is_return(signal) then return signal.value end
                    return nil
                end, "compiled")
                return fn
            end
        end,

        ArrayExpr = function(e)
            local elems = {}
            for i = 1, #e.elements do
                elems[i] = compile_expr(e.elements[i], globals, depth)
            end
            local n = #elems
            return function(E)
                local arr = {}
                for i = 1, n do arr[i] = elems[i](E) end
                return js_array(arr)
            end
        end,

        ObjectExpr = function(e)
            local props = {}
            for i = 1, #e.properties do
                local p = e.properties[i]
                props[i] = U.match(p, {
                    PropInit = function(pi)
                        local key
                        if pi.computed then
                            key = compile_expr(pi.key, globals, depth)
                        else
                            -- key is a StrLit or NumLit
                            local k = S(pi.key.value) or S(pi.key.name)
                            key = function(E) return k end
                        end
                        local val = compile_expr(pi.value, globals, depth)
                        return { key = key, val = val }
                    end,
                    PropSpread = function(ps)
                        local src = compile_expr(ps.argument, globals, depth)
                        return { spread = src }
                    end,
                })
            end
            local n = #props
            return function(E)
                local obj = js_object({})
                for i = 1, n do
                    local p = props[i]
                    if p.spread then
                        local src = p.spread(E)
                        if type(src) == "table" then
                            for k, v in pairs(src) do obj[k] = v end
                        end
                    else
                        obj[p.key(E)] = p.val(E)
                    end
                end
                return obj
            end
        end,

        Spread = function(e)
            return compile_expr(e.argument, globals, depth)
        end,

        Template = function(e)
            local parts = {}
            for i = 1, #e.parts do
                parts[i] = U.match(e.parts[i], {
                    TemplateStr = function(p)
                        local s = S(p.value)
                        return function(E) return s end
                    end,
                    TemplateExpr = function(p)
                        local expr = compile_expr(p.expr, globals, depth)
                        return function(E) return tostring(expr(E)) end
                    end,
                })
            end
            local n = #parts
            return function(E)
                local result = {}
                for i = 1, n do result[i] = parts[i](E) end
                return table.concat(result)
            end
        end,

        Typeof = function(e)
            local arg = compile_expr(e.argument, globals, depth)
            return function(E) return js_typeof(arg(E)) end
        end,

        Instanceof = function(e)
            local left = compile_expr(e.left, globals, depth)
            local right = compile_expr(e.right, globals, depth)
            return function(E) return js_instanceof(left(E), right(E)) end
        end,

        Void = function(e)
            local arg = compile_expr(e.argument, globals, depth)
            return function(E) arg(E); return nil end
        end,

        Delete = function(e)
            local obj = compile_expr(e.object, globals, depth)
            if e.computed then
                local prop = compile_expr(e.property, globals, depth)
                return function(E)
                    local o = obj(E)
                    local k = prop(E)
                    if type(o) == "table" then o[k] = nil end
                    return true
                end
            else
                local field = S(e.property.value)
                return function(E)
                    local o = obj(E)
                    if type(o) == "table" then o[field] = nil end
                    return true
                end
            end
        end,

        This = function(e)
            return function(E) return E.__this end
        end,

        Sequence = function(e)
            local exprs = {}
            for i = 1, #e.exprs do
                exprs[i] = compile_expr(e.exprs[i], globals, depth)
            end
            local n = #exprs
            return function(E)
                local v
                for i = 1, n do v = exprs[i](E) end
                return v
            end
        end,

        NullishCoalesce = function(e)
            local left = compile_expr(e.left, globals, depth)
            local right = compile_expr(e.right, globals, depth)
            return function(E)
                local l = left(E)
                if l == nil or l == JS_NULL then return right(E) end
                return l
            end
        end,
    })
end

-- ═══════════════════════════════════════════════════════════════
-- Statement compiler
-- ═══════════════════════════════════════════════════════════════
-- compile_stmt: JsResolved.Stmt -> (E -> signal?)
-- Returns nil for normal completion, or a signal for
-- break/continue/return.

compile_stmt = function(node, globals, depth)
    depth = depth or 0
    return U.match(node, {
        ExprStmt = function(s)
            local expr = compile_expr(s.expr, globals, depth)
            return function(E) expr(E); return nil end
        end,

        VarDecl = function(s)
            local decls = {}
            for i = 1, #s.decls do
                local d = s.decls[i]
                local write = compile_slot_init(d.target, globals, depth)
                local init = d.init and compile_expr(d.init, globals, depth) or nil
                decls[i] = { write = write, init = init }
            end
            local n = #decls
            return function(E)
                for i = 1, n do
                    local d = decls[i]
                    if d.init then
                        d.write(E, d.init(E))
                    else
                        d.write(E, nil)
                    end
                end
                return nil
            end
        end,

        FuncDecl = function(s)
            local write = compile_slot_init(s.target, globals, depth)
            local params = s.params
            local np = #params
            local frame_size = s.scope and N(s.scope.slot_count) or np
            local initialized_slots = {}
            for i = 1, np do initialized_slots[i] = true end
            local body = compile_scope_runner(s.scope, s.body, globals, depth + 1, initialized_slots)
            return function(E)
                local fn = js_register_callable(function(a, b, ...)
                    local call_this, argv
                    if a == JS_CALL_SENTINEL then
                        call_this = b
                        argv = { ... }
                    else
                        call_this = nil
                        argv = { a, b, ... }
                    end
                    local inner = new_frame(E, frame_size)
                    inner.__this = call_this
                    local function init(inner_frame)
                        for i = 1, np do inner_frame[i] = argv[i] end
                    end
                    local signal = body(inner, init)
                    if is_return(signal) then return signal.value end
                    return nil
                end, "compiled")
                write(E, fn)
                return nil
            end
        end,

        Return = function(s)
            if s.value then
                local val = compile_expr(s.value, globals, depth)
                return function(E) return js_return(val(E)) end
            else
                return function(E) return js_return(nil) end
            end
        end,

        If = function(s)
            local test = compile_expr(s.test, globals, depth)
            local cons = compile_stmt(s.consequent, globals, depth)
            local alt = s.alternate and compile_stmt(s.alternate, globals, depth) or nil
            return function(E)
                if js_truthy(test(E)) then
                    return cons(E)
                elseif alt then
                    return alt(E)
                end
                return nil
            end
        end,

        While = function(s)
            local test = compile_expr(s.test, globals, depth)
            local body = compile_stmt(s.body, globals, depth)
            local continue_targets = s.continue_targets
            return function(E)
                while js_truthy(test(E)) do
                    local signal = body(E)
                    if signal == BREAK then break end
                    if signal == CONTINUE or matches_continue_target(signal, continue_targets) then
                        -- continue current loop
                    elseif signal ~= nil then
                        return signal -- propagate return / labeled break
                    end
                end
                return nil
            end
        end,

        DoWhile = function(s)
            local body = compile_stmt(s.body, globals, depth)
            local test = compile_expr(s.test, globals, depth)
            local continue_targets = s.continue_targets
            return function(E)
                while true do
                    local signal = body(E)
                    if signal == BREAK then break end
                    if signal == CONTINUE or matches_continue_target(signal, continue_targets) then
                        -- continue current loop
                    elseif signal ~= nil then
                        return signal
                    end
                    if not js_truthy(test(E)) then break end
                end
                return nil
            end
        end,

        For = function(s)
            local continue_targets = s.continue_targets
            if s.scope then
                local frame_size = N(s.scope.slot_count)
                local tdz_slots = lexical_tdz_slots(s.scope, nil)
                local init = s.init and compile_stmt(s.init, globals, depth + 1) or nil
                local test = s.test and compile_expr(s.test, globals, depth + 1) or nil
                local update = s.update and compile_expr(s.update, globals, depth + 1) or nil
                local body = compile_stmt(s.body, globals, depth + 1)
                return function(E)
                    local current = new_frame(E, frame_size)
                    init_tdz_slots(current, tdz_slots)
                    if init then init(current) end
                    while true do
                        if test and not js_truthy(test(current)) then break end
                        local signal = body(current)
                        if signal == BREAK then break end
                        if signal == CONTINUE or matches_continue_target(signal, continue_targets) then
                            -- continue current loop
                        elseif signal ~= nil then
                            return signal
                        end
                        local next = clone_frame(current, frame_size)
                        if update then update(next) end
                        current = next
                    end
                    return nil
                end
            end

            local init = s.init and compile_stmt(s.init, globals, depth) or nil
            local test = s.test and compile_expr(s.test, globals, depth) or nil
            local update = s.update and compile_expr(s.update, globals, depth) or nil
            local body = compile_stmt(s.body, globals, depth)
            return function(E)
                if init then init(E) end
                while true do
                    if test and not js_truthy(test(E)) then break end
                    local signal = body(E)
                    if signal == BREAK then break end
                    if signal == CONTINUE or matches_continue_target(signal, continue_targets) then
                        -- continue current loop
                    elseif signal ~= nil then
                        return signal
                    end
                    if update then update(E) end
                end
                return nil
            end
        end,

        ForIn = function(s)
            local continue_targets = s.continue_targets
            local right = compile_expr(s.right, globals, depth)
            if s.scope then
                local frame_size = N(s.scope.slot_count)
                local write = compile_slot_init(s.target, globals, depth + 1)
                local body = compile_stmt(s.body, globals, depth + 1)
                return function(E)
                    local obj = right(E)
                    if type(obj) == "table" then
                        for k, _ in pairs(obj) do
                            local inner = new_frame(E, frame_size)
                            init_tdz_slots(inner, lexical_tdz_slots(s.scope, nil))
                            write(inner, k)
                            local signal = body(inner)
                            if signal == BREAK then break end
                            if signal == CONTINUE or matches_continue_target(signal, continue_targets) then
                                -- continue current loop
                            elseif signal ~= nil then
                                return signal
                            end
                        end
                    end
                    return nil
                end
            end

            local write = compile_slot_init(s.target, globals, depth)
            local body = compile_stmt(s.body, globals, depth)
            return function(E)
                local obj = right(E)
                if type(obj) == "table" then
                    for k, _ in pairs(obj) do
                        write(E, k)
                        local signal = body(E)
                        if signal == BREAK then break end
                        if signal == CONTINUE or matches_continue_target(signal, continue_targets) then
                            -- continue current loop
                        elseif signal ~= nil then
                            return signal
                        end
                    end
                end
                return nil
            end
        end,

        ForOf = function(s)
            local continue_targets = s.continue_targets
            local right = compile_expr(s.right, globals, depth)
            if s.scope then
                local frame_size = N(s.scope.slot_count)
                local write = compile_slot_init(s.target, globals, depth + 1)
                local body = compile_stmt(s.body, globals, depth + 1)
                return function(E)
                    local arr = right(E)
                    if type(arr) == "table" then
                        for _, v in ipairs(arr) do
                            local inner = new_frame(E, frame_size)
                            init_tdz_slots(inner, lexical_tdz_slots(s.scope, nil))
                            write(inner, v)
                            local signal = body(inner)
                            if signal == BREAK then break end
                            if signal == CONTINUE or matches_continue_target(signal, continue_targets) then
                                -- continue current loop
                            elseif signal ~= nil then
                                return signal
                            end
                        end
                    end
                    return nil
                end
            end

            local write = compile_slot_init(s.target, globals, depth)
            local body = compile_stmt(s.body, globals, depth)
            return function(E)
                local arr = right(E)
                if type(arr) == "table" then
                    for _, v in ipairs(arr) do
                        write(E, v)
                        local signal = body(E)
                        if signal == BREAK then break end
                        if signal == CONTINUE or matches_continue_target(signal, continue_targets) then
                            -- continue current loop
                        elseif signal ~= nil then
                            return signal
                        end
                    end
                end
                return nil
            end
        end,

        Switch = function(s)
            local discriminant = compile_expr(s.discriminant, globals, depth)
            local frame_size = s.scope and N(s.scope.slot_count) or 0
            local tdz_slots = lexical_tdz_slots(s.scope, nil)
            local compiled_cases = {}
            for i = 1, #s.cases do
                local c = s.cases[i]
                compiled_cases[i] = {
                    test = c.test and compile_expr(c.test, globals, depth + 1) or nil,
                    body = compile_stmts(c.body, globals, depth + 1),
                }
            end
            return function(E)
                local inner = new_frame(E, frame_size)
                init_tdz_slots(inner, tdz_slots)
                local disc = discriminant(E)
                local matched = false
                for i = 1, #compiled_cases do
                    local c = compiled_cases[i]
                    if matched or c.test == nil or js_loose_equal(disc, c.test(inner)) then
                        matched = true
                        local signal = c.body(inner)
                        if signal == BREAK then return nil end
                        if signal ~= nil then return signal end
                    end
                end
                return nil
            end
        end,

        Label = function(s)
            local body = compile_stmt(s.body, globals, depth)
            local target_id = N(s.target_id)
            return function(E)
                local signal = body(E)
                if type(signal) == "table" and signal.__js_break == true and signal.target == target_id then
                    return nil
                end
                return signal
            end
        end,

        Block = function(s)
            local frame_size = s.scope and N(s.scope.slot_count) or 0
            local body = compile_scope_runner(s.scope, s.body, globals, depth + 1, nil)
            return function(E)
                local inner = new_frame(E, frame_size)
                return body(inner)
            end
        end,

        Break = function(s)
            local target_id = s.target_id ~= nil and N(s.target_id) or nil
            return function(E) return js_break(target_id) end
        end,

        Continue = function(s)
            local target_id = s.target_id ~= nil and N(s.target_id) or nil
            return function(E) return js_continue(target_id) end
        end,

        Throw = function(s)
            local arg = compile_expr(s.argument, globals, depth)
            return function(E) error(arg(E), 0) end
        end,

        Try = function(s)
            local block = compile_stmt(s.block, globals, depth)
            local handler = s.handler
            local finalizer = s.finalizer and compile_stmt(s.finalizer, globals, depth) or nil
            local catch_fn = nil

            if handler then
                local catch_frame_size = handler.scope and N(handler.scope.slot_count) or 0
                local initialized_slots = {}
                if handler.param then initialized_slots[N(handler.param.index)] = true end
                local catch_body = compile_scope_runner(handler.scope, { handler.body }, globals, depth + 1, initialized_slots)
                if handler.param then
                    local write = compile_slot_init(handler.param, globals, depth + 1)
                    catch_fn = function(E, err)
                        local inner = new_frame(E, catch_frame_size)
                        return catch_body(inner, function(inner_frame)
                            write(inner_frame, err)
                        end)
                    end
                else
                    catch_fn = function(E, err)
                        local inner = new_frame(E, catch_frame_size)
                        return catch_body(inner)
                    end
                end
            end

            return function(E)
                local ok, result = pcall(block, E)
                local signal = nil
                if ok then
                    signal = result
                elseif catch_fn then
                    signal = catch_fn(E, result)
                else
                    if finalizer then finalizer(E) end
                    error(result)
                end
                if finalizer then finalizer(E) end
                return signal
            end
        end,

        Empty = function(s)
            return function(E) return nil end
        end,
    })
end

-- ═══════════════════════════════════════════════════════════════
-- Statement list compiler
-- ═══════════════════════════════════════════════════════════════
compile_stmts = function(stmts, globals, depth)
    depth = depth or 0
    local fns = {}
    for i = 1, #stmts do
        fns[i] = compile_stmt(stmts[i], globals, depth)
    end
    local n = #fns
    if n == 0 then
        return function(E) return nil end
    elseif n == 1 then
        local f = fns[1]
        return function(E) return f(E) end
    else
        return function(E)
            for i = 1, n do
                local signal = fns[i](E)
                if signal ~= nil then return signal end
            end
            return nil
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Top-level program compiler
-- ═══════════════════════════════════════════════════════════════

local function compile_program(program, extra_globals, slot_hooks, options)
    local globals = make_globals()
    if extra_globals then
        for k, v in pairs(extra_globals) do globals[k] = v end
    end

    options = options or {}

    local prev_hooks = ACTIVE_SLOT_HOOKS
    ACTIVE_SLOT_HOOKS = slot_hooks
    local body = options.raw_body
        and compile_stmts(program.body, globals, 0)
        or compile_scope_runner(program.scope, program.body, globals, 0, nil)
    ACTIVE_SLOT_HOOKS = prev_hooks

    local frame_size = program.scope and N(program.scope.slot_count) or 0

    local function run_with_frame(E)
        local signal = body(E)
        if is_return(signal) then return signal.value end
        return nil
    end

    return {
        run = function()
            local E = new_frame(nil, frame_size)
            return run_with_frame(E)
        end,
        run_with_frame = run_with_frame,
        body = body,
        globals = globals,
        frame_size = frame_size,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- Install on T
-- ═══════════════════════════════════════════════════════════════
return function(T)
    T._js_compile_program = function(program, extra_globals, slot_hooks)
        return compile_program(program, extra_globals, slot_hooks, { raw_body = true })
    end
    T.JsResolved.Program.compile = U.terminal("JsResolved.Program:compile",
        function(program, extra_globals)
            return compile_program(program, extra_globals)
        end
    )
end
