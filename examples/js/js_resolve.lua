-- js_resolve.lua
--
-- Transition: JsSource -> JsResolved
-- ----------------------------------------------------------------------------
-- This phase consumes variable name binding:
--   - each Ident(name) -> SlotRef(LocalSlot | GlobalSlot)
--   - each VarDecl/FuncDecl -> allocates slots
--   - scope depth + slot count tracked per scope
--
-- After this phase, no name lookups remain. Every variable reference
-- is a typed slot address.

local U = require("unit")
local asdl = require("asdl")
local L = asdl.List

-- ═══════════════════════════════════════════════════════════════
-- Scope builder
-- ═══════════════════════════════════════════════════════════════

local function new_scope(T, parent_depth)
    local depth = (parent_depth or -1) + 1
    local slots = {}
    local bindings = {}
    local next_slot = 1

    return {
        depth = depth,

        declare = function(self, name, kind)
            local idx = next_slot
            next_slot = next_slot + 1
            slots[name] = { depth = depth, index = idx, kind = kind }
            bindings[#bindings + 1] = T.JsResolved.Binding(name, kind, idx)
            return T.JsResolved.LocalSlot(depth, idx, kind)
        end,

        resolve_local = function(self, name)
            local s = slots[name]
            if s then
                return T.JsResolved.LocalSlot(s.depth, s.index, s.kind)
            end
            return nil
        end,

        resolve = function(self, name, parent_resolve)
            local s = slots[name]
            if s then
                return T.JsResolved.LocalSlot(s.depth, s.index, s.kind)
            end
            if parent_resolve then
                return parent_resolve(name)
            end
            return T.JsResolved.GlobalSlot(name)
        end,

        finalize = function(self)
            return T.JsResolved.Scope(depth, next_slot - 1, L(bindings))
        end,
    }
end

-- String coercion helper: ASDL cdata strings -> Lua strings
local ffi = require("ffi")
local function S(v)
    if v == nil then return nil end
    if type(v) == "cdata" then return ffi.string(v) end
    return tostring(v)
end

-- Safe list map: avoids the asdl.List .insert method in pairs iteration
local function list_map(xs, fn)
    local result = L{}
    for i = 1, #xs do
        result[i] = fn(xs[i])
    end
    return result
end

-- A resolver is a callable table with .__depth
local function make_resolver(scope, parent_resolve)
    return setmetatable({ __depth = scope.depth }, {
        __call = function(_, name)
            return scope:resolve(name, parent_resolve)
        end,
    })
end

-- ═══════════════════════════════════════════════════════════════
-- Resolve expressions
-- ═══════════════════════════════════════════════════════════════

local resolve_expr
local resolve_stmt
local resolve_stmts

local function predeclare_var_decl(T, scope, stmt)
    local var_kind = S(stmt.var_kind.kind or stmt.var_kind)
    if var_kind == "Let" or var_kind == "Const" then
        for j = 1, #stmt.decls do
            local name = S(stmt.decls[j].name)
            if not scope:resolve_local(name) then
                scope:declare(name, stmt.var_kind)
            end
        end
    end
end

local function predeclare_scope_bindings(T, scope, stmts)
    for i = 1, #stmts do
        local s = stmts[i]
        local kind = S(s.kind)
        if kind == "FuncDecl" then
            if not scope:resolve_local(S(s.name)) then
                scope:declare(S(s.name), T.JsCore.Let)
            end
        elseif kind == "VarDecl" then
            predeclare_var_decl(T, scope, s)
        end
    end
end

local function new_jump_root(shared_alloc)
    local next_target = 0
    local alloc = shared_alloc or function()
        next_target = next_target + 1
        return next_target
    end
    return {
        parent = nil,
        name = nil,
        target_id = nil,
        continuable = false,
        alloc = alloc,
    }
end

local function push_jump_label(J, name, target_id, continuable)
    return {
        parent = J,
        name = name,
        target_id = target_id,
        continuable = continuable and true or false,
        alloc = J.alloc,
    }
end

local function resolve_jump_label(J, name, need_continue)
    local cur = J
    while cur do
        if cur.name == name then
            if need_continue and not cur.continuable then
                error("continue target is not an iteration label: " .. tostring(name))
            end
            return cur.target_id
        end
        cur = cur.parent
    end
    error("unknown label: " .. tostring(name))
end

local function source_stmt_is_continuable(stmt)
    local kind = S(stmt.kind)
    if kind == "While" or kind == "DoWhile" or kind == "For" or kind == "ForIn" or kind == "ForOf" then
        return true
    elseif kind == "Label" then
        return source_stmt_is_continuable(stmt.body)
    end
    return false
end

local function append_number_list(xs, value)
    local out = L{}
    for i = 1, #xs do out[#out + 1] = tonumber(xs[i]) or xs[i] end
    out[#out + 1] = value
    return out
end

local attach_continue_target_stmt

attach_continue_target_stmt = function(T, stmt, target_id)
    local kind = S(stmt.kind)
    if kind == "While" then
        return T.JsResolved.While(stmt.test, stmt.body, append_number_list(stmt.continue_targets, target_id))
    elseif kind == "DoWhile" then
        return T.JsResolved.DoWhile(stmt.body, stmt.test, append_number_list(stmt.continue_targets, target_id))
    elseif kind == "For" then
        return T.JsResolved.For(stmt.init, stmt.test, stmt.update, stmt.body, stmt.scope, append_number_list(stmt.continue_targets, target_id))
    elseif kind == "ForIn" then
        return T.JsResolved.ForIn(stmt.var_kind, stmt.target, stmt.right, stmt.body, stmt.scope, append_number_list(stmt.continue_targets, target_id))
    elseif kind == "ForOf" then
        return T.JsResolved.ForOf(stmt.var_kind, stmt.target, stmt.right, stmt.body, stmt.scope, append_number_list(stmt.continue_targets, target_id))
    elseif kind == "Label" then
        return T.JsResolved.Label(tonumber(stmt.target_id), attach_continue_target_stmt(T, stmt.body, target_id))
    end
    error("internal: cannot attach continue target to " .. tostring(kind))
end

resolve_expr = function(T, node, R)
    return U.match(node, {
        NumLit = function(e)
            return T.JsResolved.NumLit(tonumber(e.value))
        end,

        StrLit = function(e)
            return T.JsResolved.StrLit(S(e.value))
        end,

        BoolLit = function(e)
            return T.JsResolved.BoolLit(e.value ~= false and e.value ~= 0)
        end,

        NullLit = function()
            return T.JsResolved.NullLit
        end,

        UndefinedLit = function()
            return T.JsResolved.UndefinedLit
        end,

        Ident = function(e)
            return T.JsResolved.SlotRef(R(S(e.name)))
        end,

        BinOp = function(e)
            return T.JsResolved.BinOp(
                e.op,
                resolve_expr(T, e.left, R),
                resolve_expr(T, e.right, R)
            )
        end,

        LogicalOp = function(e)
            return T.JsResolved.LogicalOp(
                e.op,
                resolve_expr(T, e.left, R),
                resolve_expr(T, e.right, R)
            )
        end,

        UnaryOp = function(e)
            return T.JsResolved.UnaryOp(
                e.op,
                resolve_expr(T, e.argument, R)
            )
        end,

        UpdateOp = function(e)
            return T.JsResolved.UpdateOp(
                e.op,
                resolve_expr(T, e.argument, R),
                e.prefix
            )
        end,

        Assign = function(e)
            return T.JsResolved.Assign(
                resolve_expr(T, e.left, R),
                resolve_expr(T, e.right, R)
            )
        end,

        CompoundAssign = function(e)
            return T.JsResolved.CompoundAssign(
                e.op,
                resolve_expr(T, e.left, R),
                resolve_expr(T, e.right, R)
            )
        end,

        Member = function(e)
            return T.JsResolved.Member(
                resolve_expr(T, e.object, R),
                resolve_expr(T, e.property, R),
                e.computed
            )
        end,

        Optional = function(e)
            return T.JsResolved.Optional(
                resolve_expr(T, e.object, R),
                resolve_expr(T, e.property, R),
                e.computed
            )
        end,

        Call = function(e)
            return T.JsResolved.Call(
                resolve_expr(T, e.callee, R),
                list_map(e.arguments, function(a)
                    return resolve_expr(T, a, R)
                end)
            )
        end,

        New = function(e)
            return T.JsResolved.New(
                resolve_expr(T, e.callee, R),
                list_map(e.arguments, function(a)
                    return resolve_expr(T, a, R)
                end)
            )
        end,

        Cond = function(e)
            return T.JsResolved.Cond(
                resolve_expr(T, e.test, R),
                resolve_expr(T, e.consequent, R),
                resolve_expr(T, e.alternate, R)
            )
        end,

        Arrow = function(e)
            local scope = new_scope(T, R.__depth)
            for _, p in ipairs(e.params) do
                scope:declare(S(p), T.JsCore.Let)
            end
            local CR = make_resolver(scope, R)

            local body = U.match(e.body, {
                ArrowExpr = function(ab)
                    return T.JsResolved.ArrowExpr(
                        resolve_expr(T, ab.expr, CR)
                    )
                end,
                ArrowBlock = function(ab)
                    return T.JsResolved.ArrowBlock(
                        resolve_stmts(T, ab.body, CR, scope, new_jump_root())
                    )
                end,
            })

            local sparams = L{}
            for _, p in ipairs(e.params) do sparams[#sparams+1] = S(p) end
            return T.JsResolved.Arrow(
                sparams,
                body,
                scope:finalize()
            )
        end,

        FuncExpr = function(e)
            local scope = new_scope(T, R.__depth)
            if e.name then
                scope:declare(S(e.name), T.JsCore.Let)
            end
            for _, p in ipairs(e.params) do
                scope:declare(S(p), T.JsCore.Let)
            end
            local CR = make_resolver(scope, R)
            local sparams = L{}
            for _, p in ipairs(e.params) do sparams[#sparams+1] = S(p) end

            return T.JsResolved.FuncExpr(
                e.name and S(e.name) or nil,
                sparams,
                resolve_stmts(T, e.body, CR, scope, new_jump_root()),
                scope:finalize()
            )
        end,

        ArrayExpr = function(e)
            return T.JsResolved.ArrayExpr(
                list_map(e.elements, function(el)
                    return resolve_expr(T, el, R)
                end)
            )
        end,

        ObjectExpr = function(e)
            return T.JsResolved.ObjectExpr(
                list_map(e.properties, function(p)
                    return U.match(p, {
                        PropInit = function(pi)
                            return T.JsResolved.PropInit(
                                resolve_expr(T, pi.key, R),
                                resolve_expr(T, pi.value, R),
                                pi.computed
                            )
                        end,
                        PropSpread = function(ps)
                            return T.JsResolved.PropSpread(
                                resolve_expr(T, ps.argument, R)
                            )
                        end,
                    })
                end)
            )
        end,

        Spread = function(e)
            return T.JsResolved.Spread(
                resolve_expr(T, e.argument, R)
            )
        end,

        Template = function(e)
            return T.JsResolved.Template(
                list_map(e.parts, function(p)
                    return U.match(p, {
                        TemplateStr = function(ts)
                            return T.JsResolved.TemplateStr(S(ts.value))
                        end,
                        TemplateExpr = function(te)
                            return T.JsResolved.TemplateExpr(
                                resolve_expr(T, te.expr, R)
                            )
                        end,
                    })
                end)
            )
        end,

        Typeof = function(e)
            return T.JsResolved.Typeof(
                resolve_expr(T, e.argument, R)
            )
        end,

        Instanceof = function(e)
            return T.JsResolved.Instanceof(
                resolve_expr(T, e.left, R),
                resolve_expr(T, e.right, R)
            )
        end,

        Void = function(e)
            return T.JsResolved.Void(
                resolve_expr(T, e.argument, R)
            )
        end,

        Delete = function(e)
            return T.JsResolved.Delete(
                resolve_expr(T, e.object, R),
                resolve_expr(T, e.property, R),
                e.computed
            )
        end,

        This = function()
            return T.JsResolved.This
        end,

        Sequence = function(e)
            return T.JsResolved.Sequence(
                list_map(e.exprs, function(ex)
                    return resolve_expr(T, ex, R)
                end)
            )
        end,

        NullishCoalesce = function(e)
            return T.JsResolved.NullishCoalesce(
                resolve_expr(T, e.left, R),
                resolve_expr(T, e.right, R)
            )
        end,
    })
end

-- ═══════════════════════════════════════════════════════════════
-- Resolve statements
-- ═══════════════════════════════════════════════════════════════

resolve_stmt = function(T, node, scope, R, J)
    return U.match(node, {
        ExprStmt = function(s)
            return T.JsResolved.ExprStmt(
                resolve_expr(T, s.expr, R)
            )
        end,

        VarDecl = function(s)
            local decls = L{}
            for _, d in ipairs(s.decls) do
                -- Reuse a predeclared slot when an earlier phase intentionally
                -- hoisted the lexical binding into scope shape.
                local target = scope:resolve_local(S(d.name)) or scope:declare(S(d.name), s.var_kind)
                local init = d.init and resolve_expr(T, d.init, R) or nil
                decls[#decls + 1] = T.JsResolved.RDeclarator(target, init)
            end
            return T.JsResolved.VarDecl(s.var_kind, decls)
        end,

        FuncDecl = function(s)
            local target = scope:resolve_local(S(s.name)) or scope:declare(S(s.name), T.JsCore.Let)
            local child_scope = new_scope(T, scope.depth)
            for _, p in ipairs(s.params) do
                child_scope:declare(S(p), T.JsCore.Let)
            end
            local CR = make_resolver(child_scope, R)
            local sparams = L{}
            for _, p in ipairs(s.params) do sparams[#sparams+1] = S(p) end

            return T.JsResolved.FuncDecl(
                S(s.name),
                target,
                sparams,
                resolve_stmts(T, s.body, CR, child_scope, new_jump_root()),
                child_scope:finalize()
            )
        end,

        Return = function(s)
            if s.value then
                return T.JsResolved.Return(resolve_expr(T, s.value, R))
            end
            return T.JsResolved.Return(nil)
        end,

        If = function(s)
            return T.JsResolved.If(
                resolve_expr(T, s.test, R),
                resolve_stmt(T, s.consequent, scope, R, J),
                s.alternate and resolve_stmt(T, s.alternate, scope, R, J) or nil
            )
        end,

        While = function(s)
            return T.JsResolved.While(
                resolve_expr(T, s.test, R),
                resolve_stmt(T, s.body, scope, R, J),
                L{}
            )
        end,

        DoWhile = function(s)
            return T.JsResolved.DoWhile(
                resolve_stmt(T, s.body, scope, R, J),
                resolve_expr(T, s.test, R),
                L{}
            )
        end,

        For = function(s)
            local init_kind = s.init and S(s.init.kind) or nil
            local init_var_kind = (init_kind == "VarDecl" and S(s.init.var_kind.kind or s.init.var_kind)) or nil
            if init_kind == "VarDecl" and (init_var_kind == "Let" or init_var_kind == "Const") then
                local loop_scope = new_scope(T, scope.depth)
                predeclare_var_decl(T, loop_scope, s.init)
                local LR = make_resolver(loop_scope, R)
                local init = resolve_stmt(T, s.init, loop_scope, LR, J)
                local test = s.test and resolve_expr(T, s.test, LR) or nil
                local update = s.update and resolve_expr(T, s.update, LR) or nil
                return T.JsResolved.For(
                    init, test, update,
                    resolve_stmt(T, s.body, loop_scope, LR, J),
                    loop_scope:finalize(),
                    L{}
                )
            end

            local init = s.init and resolve_stmt(T, s.init, scope, R, J) or nil
            local test = s.test and resolve_expr(T, s.test, R) or nil
            local update = s.update and resolve_expr(T, s.update, R) or nil
            return T.JsResolved.For(
                init, test, update,
                resolve_stmt(T, s.body, scope, R, J),
                nil,
                L{}
            )
        end,

        ForIn = function(s)
            local var_kind = S(s.var_kind.kind or s.var_kind)
            if var_kind == "Var" then
                local target = scope:resolve_local(S(s.name)) or scope:declare(S(s.name), s.var_kind)
                return T.JsResolved.ForIn(
                    s.var_kind,
                    target,
                    resolve_expr(T, s.right, R),
                    resolve_stmt(T, s.body, scope, R, J),
                    nil,
                    L{}
                )
            end

            local child_scope = new_scope(T, scope.depth)
            local target = child_scope:declare(S(s.name), s.var_kind)
            local CR = make_resolver(child_scope, R)
            return T.JsResolved.ForIn(
                s.var_kind,
                target,
                resolve_expr(T, s.right, R),
                resolve_stmt(T, s.body, child_scope, CR, J),
                child_scope:finalize(),
                L{}
            )
        end,

        ForOf = function(s)
            local var_kind = S(s.var_kind.kind or s.var_kind)
            if var_kind == "Var" then
                local target = scope:resolve_local(S(s.name)) or scope:declare(S(s.name), s.var_kind)
                return T.JsResolved.ForOf(
                    s.var_kind,
                    target,
                    resolve_expr(T, s.right, R),
                    resolve_stmt(T, s.body, scope, R, J),
                    nil,
                    L{}
                )
            end

            local child_scope = new_scope(T, scope.depth)
            local target = child_scope:declare(S(s.name), s.var_kind)
            local CR = make_resolver(child_scope, R)
            return T.JsResolved.ForOf(
                s.var_kind,
                target,
                resolve_expr(T, s.right, R),
                resolve_stmt(T, s.body, child_scope, CR, J),
                child_scope:finalize(),
                L{}
            )
        end,

        Switch = function(s)
            local switch_scope = new_scope(T, scope.depth)
            for i = 1, #s.cases do
                predeclare_scope_bindings(T, switch_scope, s.cases[i].body)
            end
            local SR = make_resolver(switch_scope, R)
            local cases = L{}
            for i = 1, #s.cases do
                local c = s.cases[i]
                cases[#cases + 1] = T.JsResolved.RSwitchCase(
                    c.test and resolve_expr(T, c.test, SR) or nil,
                    resolve_stmts(T, c.body, SR, switch_scope, J)
                )
            end
            return T.JsResolved.Switch(
                resolve_expr(T, s.discriminant, R),
                cases,
                switch_scope:finalize()
            )
        end,

        Label = function(s)
            local target_id = J.alloc()
            local continuable = source_stmt_is_continuable(s.body)
            local LJ = push_jump_label(J, S(s.name), target_id, continuable)
            local body = resolve_stmt(T, s.body, scope, R, LJ)
            if continuable then
                body = attach_continue_target_stmt(T, body, target_id)
            end
            return T.JsResolved.Label(target_id, body)
        end,

        Block = function(s)
            local block_scope = new_scope(T, R.__depth)
            local BR = make_resolver(block_scope, R)
            return T.JsResolved.Block(
                resolve_stmts(T, s.body, BR, block_scope, J),
                block_scope:finalize()
            )
        end,

        Break = function(s)
            local target_id = s.label and resolve_jump_label(J, S(s.label), false) or nil
            return T.JsResolved.Break(target_id)
        end,

        Continue = function(s)
            local target_id = s.label and resolve_jump_label(J, S(s.label), true) or nil
            return T.JsResolved.Continue(target_id)
        end,

        Throw = function(s)
            return T.JsResolved.Throw(
                resolve_expr(T, s.argument, R)
            )
        end,

        Try = function(s)
            local handler = nil
            if s.handler then
                local catch_scope = new_scope(T, scope.depth)
                local param_slot = nil
                if s.handler.param then
                    param_slot = catch_scope:declare(S(s.handler.param), T.JsCore.Let)
                end
                local CR = make_resolver(catch_scope, R)
                handler = T.JsResolved.CatchClause(
                    param_slot,
                    resolve_stmt(T, s.handler.body, catch_scope, CR, J),
                    catch_scope:finalize()
                )
            end
            return T.JsResolved.Try(
                resolve_stmt(T, s.block, scope, R, J),
                handler,
                s.finalizer and resolve_stmt(T, s.finalizer, scope, R, J) or nil
            )
        end,

        Empty = function()
            return T.JsResolved.Empty
        end,
    })
end

resolve_stmts = function(T, stmts, R, scope, J)
    J = J or new_jump_root()

    -- If no scope provided, create a block scope for var declarations
    if not scope then
        scope = new_scope(T, R.__depth)
        R = make_resolver(scope, R)
    end

    predeclare_scope_bindings(T, scope, stmts)

    local result = L{}
    for i = 1, #stmts do
        result[#result + 1] = resolve_stmt(T, stmts[i], scope, R, J)
    end
    return result
end

-- ═══════════════════════════════════════════════════════════════
-- Top-level resolve
-- ═══════════════════════════════════════════════════════════════

local function resolve_program(T, program)
    local scope = new_scope(T, -1)

    predeclare_scope_bindings(T, scope, program.body)

    local R = make_resolver(scope, nil)
    local J = new_jump_root()

    -- Resolve body
    local resolved_body = L{}
    for _, s in ipairs(program.body) do
        resolved_body[#resolved_body + 1] = resolve_stmt(T, s, scope, R, J)
    end

    return T.JsResolved.Program(resolved_body, scope:finalize())
end

-- ═══════════════════════════════════════════════════════════════
-- Install on T
-- ═══════════════════════════════════════════════════════════════
return function(T)
    T.JsSource.Program.resolve = U.transition("JsSource.Program:resolve",
        function(program)
            return resolve_program(T, program)
        end
    )
end
