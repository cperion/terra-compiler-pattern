local ffi = require("ffi")
local U = require("unit")
local asdl = require("asdl")
local L = asdl.List

local function STR(v)
    if type(v) == "cdata" then return ffi.string(v) end
    return v
end

local function map_list(xs, fn)
    local out = L{}
    for i = 1, #xs do out[#out + 1] = fn(xs[i]) end
    return out
end

return function(T)
    local S = T.JsSurface
    local J = T.JsSource

    local lower_expr, lower_stmt, lower_arrow_body, lower_prop, lower_template_part
    local next_gensym = 0

    local function emit_string(s)
        return J.StrLit(s)
    end

    local function emit_bool(b)
        return J.BoolLit(b and true or false)
    end

    local function gensym(prefix)
        next_gensym = next_gensym + 1
        return prefix .. tostring(next_gensym)
    end

    local function member(obj, name)
        return J.Member(obj, emit_string(name), false)
    end

    local function assign_member_stmt(obj, name, value)
        return J.ExprStmt(J.Assign(member(obj, name), value))
    end

    local function assign_computed_stmt(obj, key, value)
        return J.ExprStmt(J.Assign(J.Member(obj, key, true), value))
    end

    local function require_call(from)
        from = STR(from)
        if not from then error("module statement missing 'from' string", 2) end
        return J.Call(J.Ident("require"), L{ emit_string(from) })
    end

    local function one_or_block(stmts)
        if #stmts == 1 then return stmts[1] end
        return J.Block(stmts)
    end

    local function lower_expr_with_this(expr, this_name)
        return lower_expr(expr, this_name)
    end

    local function lower_stmt_with_this(stmt, this_name)
        return lower_stmt(stmt, this_name)
    end

    local function lower_stmts_with_this(body, this_name)
        return map_list(body, function(s) return lower_stmt_with_this(s, this_name) end)
    end

    local function make_this_function(params, body, this_name)
        local full = L{ this_name }
        for i = 1, #params do full[#full + 1] = STR(params[i]) end
        return J.FuncExpr(nil, full, lower_stmts_with_this(body, this_name))
    end

    local function lower_class_expr(expr, explicit_name)
        local specs = L{}
        local ctor = J.UndefinedLit
        local this_name = "__this"
        local class_name = explicit_name or (expr.name and STR(expr.name) or nil)

        for i = 1, #expr.items do
            local m = expr.items[i]
            U.match(m, {
                Method = function(mm)
                    local mk = STR(mm.method_kind.kind)
                    if STR(mm.name) == "constructor" and not mm.is_static and mk == "MethodNormal" then
                        ctor = make_this_function(mm.params, mm.body, this_name)
                        return
                    end
                    local kind_name = ({ MethodNormal = "method", MethodGet = "get", MethodSet = "set" })[mk] or "method"
                    specs[#specs + 1] = J.ObjectExpr(L{
                        J.PropInit(emit_string("name"), emit_string(STR(mm.name)), false),
                        J.PropInit(emit_string("static"), emit_bool(mm.is_static), false),
                        J.PropInit(emit_string("kind"), emit_string(kind_name), false),
                        J.PropInit(emit_string("fn"), make_this_function(mm.params, mm.body, this_name), false),
                    })
                end,
                Field = function(mm)
                    local spec_props = L{
                        J.PropInit(emit_string("name"), emit_string(STR(mm.name)), false),
                        J.PropInit(emit_string("static"), emit_bool(mm.is_static), false),
                        J.PropInit(emit_string("kind"), emit_string("field"), false),
                    }
                    if mm.init then
                        spec_props[#spec_props + 1] = J.PropInit(
                            emit_string("init"),
                            J.FuncExpr(nil, L{ this_name }, L{ J.Return(lower_expr_with_this(mm.init, this_name)) }),
                            false
                        )
                    end
                    specs[#specs + 1] = J.ObjectExpr(spec_props)
                end,
            })
        end

        local function make_class_call(super_expr, bind_self)
            local args = L{
                super_expr or J.UndefinedLit,
                ctor,
                J.ArrayExpr(specs),
            }
            if bind_self then args[#args + 1] = bind_self end
            return J.Call(J.Ident("__js_make_class"), args)
        end

        if class_name then
            local super_name = expr.super_class and gensym("__js_class_super_") or nil
            local bind_name = gensym("__js_bind_class_")
            local body = L{}
            if super_name then
                body[#body + 1] = J.VarDecl(T.JsCore.Const, L{
                    J.Declarator(super_name, lower_expr(expr.super_class))
                })
            end
            body[#body + 1] = J.VarDecl(T.JsCore.Let, L{
                J.Declarator(class_name, nil)
            })
            body[#body + 1] = J.VarDecl(T.JsCore.Const, L{
                J.Declarator(bind_name, J.FuncExpr(nil, L{ "v" }, L{
                    J.ExprStmt(J.Assign(J.Ident(class_name), J.Ident("v")))
                }))
            })
            body[#body + 1] = J.ExprStmt(J.Assign(
                J.Ident(class_name),
                make_class_call(super_name and J.Ident(super_name) or nil, J.Ident(bind_name))
            ))
            body[#body + 1] = J.Return(J.Ident(class_name))
            return J.Call(J.FuncExpr(nil, L{}, body), L{})
        end

        return make_class_call(expr.super_class and lower_expr(expr.super_class) or nil, nil)
    end

    local function unsupported(what)
        error("JsSurface -> JsSource lowering not implemented for " .. what, 2)
    end

    local function map_string_list(xs)
        local out = L{}
        for i = 1, #xs do out[#out + 1] = STR(xs[i]) end
        return out
    end

    local function declared_name(stmt)
        local kind = STR(stmt.kind)
        if kind == "FuncDecl" then
            return STR(stmt.name)
        elseif kind == "ClassDecl" then
            return STR(stmt.name)
        elseif kind == "VarDecl" then
            if #stmt.decls ~= 1 then
                return unsupported("multi-declarator export declaration")
            end
            return STR(stmt.decls[1].name)
        elseif kind == "Block" then
            if #stmt.body ~= 1 then
                return unsupported("block export declaration")
            end
            return declared_name(stmt.body[1])
        end
        return unsupported("export declaration " .. tostring(kind))
    end

    local function lower_export_decl_stmt(decl, export_name, this_name)
        local local_name = declared_name(decl)
        return one_or_block(L{
            lower_stmt(decl, this_name),
            assign_member_stmt(J.Ident("exports"), export_name, J.Ident(local_name)),
        })
    end

    lower_template_part = function(part, this_name)
        return U.match(part, {
            TemplateStr = function(p) return J.TemplateStr(STR(p.value)) end,
            TemplateExpr = function(p) return J.TemplateExpr(lower_expr(p.expr, this_name)) end,
        })
    end

    lower_prop = function(prop, this_name)
        return U.match(prop, {
            PropInit = function(p)
                return J.PropInit(lower_expr(p.key, this_name), lower_expr(p.value, this_name), p.computed)
            end,
            PropSpread = function(p)
                return J.PropSpread(lower_expr(p.argument, this_name))
            end,
        })
    end

    lower_arrow_body = function(body, this_name)
        return U.match(body, {
            ArrowExpr = function(b) return J.ArrowExpr(lower_expr(b.expr, this_name)) end,
            ArrowBlock = function(b) return J.ArrowBlock(map_list(b.body, function(s) return lower_stmt(s, this_name) end)) end,
        })
    end

    lower_expr = function(expr, this_name)
        return U.match(expr, {
            NumLit = function(e) return J.NumLit(e.value) end,
            StrLit = function(e) return J.StrLit(STR(e.value)) end,
            BoolLit = function(e) return J.BoolLit(e.value) end,
            NullLit = function() return J.NullLit end,
            UndefinedLit = function() return J.UndefinedLit end,
            ArrayExpr = function(e) return J.ArrayExpr(map_list(e.elements, function(x) return lower_expr(x, this_name) end)) end,
            ObjectExpr = function(e) return J.ObjectExpr(map_list(e.properties, function(x) return lower_prop(x, this_name) end)) end,
            Ident = function(e) return J.Ident(STR(e.name)) end,
            BinOp = function(e) return J.BinOp(e.op, lower_expr(e.left, this_name), lower_expr(e.right, this_name)) end,
            LogicalOp = function(e) return J.LogicalOp(e.op, lower_expr(e.left, this_name), lower_expr(e.right, this_name)) end,
            UnaryOp = function(e) return J.UnaryOp(e.op, lower_expr(e.argument, this_name)) end,
            UpdateOp = function(e) return J.UpdateOp(e.op, lower_expr(e.argument, this_name), e.prefix) end,
            Assign = function(e) return J.Assign(lower_expr(e.left, this_name), lower_expr(e.right, this_name)) end,
            CompoundAssign = function(e) return J.CompoundAssign(e.op, lower_expr(e.left, this_name), lower_expr(e.right, this_name)) end,
            Member = function(e) return J.Member(lower_expr(e.object, this_name), lower_expr(e.property, this_name), e.computed) end,
            Optional = function(e) return J.Optional(lower_expr(e.object, this_name), lower_expr(e.property, this_name), e.computed) end,
            Call = function(e) return J.Call(lower_expr(e.callee, this_name), map_list(e.arguments, function(x) return lower_expr(x, this_name) end)) end,
            New = function(e) return J.New(lower_expr(e.callee, this_name), map_list(e.arguments, function(x) return lower_expr(x, this_name) end)) end,
            Cond = function(e) return J.Cond(lower_expr(e.test, this_name), lower_expr(e.consequent, this_name), lower_expr(e.alternate, this_name)) end,
            Arrow = function(e) return J.Arrow(map_string_list(e.params), lower_arrow_body(e.body, this_name)) end,
            FuncExpr = function(e) return J.FuncExpr(e.name and STR(e.name) or nil, map_string_list(e.params), map_list(e.body, function(s) return lower_stmt(s, nil) end)) end,
            ClassExpr = function(e) return lower_class_expr(e) end,
            Spread = function(e) return J.Spread(lower_expr(e.argument, this_name)) end,
            Template = function(e) return J.Template(map_list(e.parts, function(x) return lower_template_part(x, this_name) end)) end,
            Typeof = function(e) return J.Typeof(lower_expr(e.argument, this_name)) end,
            Instanceof = function(e) return J.Instanceof(lower_expr(e.left, this_name), lower_expr(e.right, this_name)) end,
            Void = function(e) return J.Void(lower_expr(e.argument, this_name)) end,
            Delete = function(e) return J.Delete(lower_expr(e.object, this_name), lower_expr(e.property, this_name), e.computed) end,
            This = function() return this_name and J.Ident(this_name) or J.This end,
            Sequence = function(e) return J.Sequence(map_list(e.exprs, function(x) return lower_expr(x, this_name) end)) end,
            NullishCoalesce = function(e) return J.NullishCoalesce(lower_expr(e.left, this_name), lower_expr(e.right, this_name)) end,
        })
    end

    local function lower_var_decl(stmt, this_name)
        local var_kind = STR(stmt.var_kind.kind or stmt.var_kind)
        if var_kind == "Const" then
            for i = 1, #stmt.decls do
                local d = stmt.decls[i]
                if d.init == nil then
                    unsupported("const declaration requires initializer")
                end
            end
        end
        return J.VarDecl(stmt.var_kind, map_list(stmt.decls, function(d)
            return J.Declarator(STR(d.name), d.init and lower_expr(d.init, this_name) or nil)
        end))
    end

    local lower_catch = function(c, this_name)
        if not c then return nil end
        return J.CatchClause(c.param and STR(c.param) or nil, lower_stmt(c.body, this_name))
    end

    lower_stmt = function(stmt, this_name)
        return U.match(stmt, {
            ExprStmt = function(s) return J.ExprStmt(lower_expr(s.expr, this_name)) end,
            VarDecl = function(s) return lower_var_decl(s, this_name) end,
            FuncDecl = function(s) return J.FuncDecl(STR(s.name), map_string_list(s.params), map_list(s.body, function(x) return lower_stmt(x, nil) end)) end,
            Return = function(s) return J.Return(s.value and lower_expr(s.value, this_name) or nil) end,
            If = function(s) return J.If(lower_expr(s.test, this_name), lower_stmt(s.consequent, this_name), s.alternate and lower_stmt(s.alternate, this_name) or nil) end,
            While = function(s) return J.While(lower_expr(s.test, this_name), lower_stmt(s.body, this_name)) end,
            DoWhile = function(s) return J.DoWhile(lower_stmt(s.body, this_name), lower_expr(s.test, this_name)) end,
            For = function(s)
                return J.For(
                    s.init and lower_stmt(s.init, this_name) or nil,
                    s.test and lower_expr(s.test, this_name) or nil,
                    s.update and lower_expr(s.update, this_name) or nil,
                    lower_stmt(s.body, this_name)
                )
            end,
            ForIn = function(s) return J.ForIn(s.var_kind, STR(s.name), lower_expr(s.right, this_name), lower_stmt(s.body, this_name)) end,
            ForOf = function(s) return J.ForOf(s.var_kind, STR(s.name), lower_expr(s.right, this_name), lower_stmt(s.body, this_name)) end,
            Switch = function(s)
                local cases = L{}
                for i = 1, #s.cases do
                    local c = s.cases[i]
                    cases[#cases + 1] = J.SwitchCase(c.test and lower_expr(c.test, this_name) or nil, map_list(c.body, function(x) return lower_stmt(x, this_name) end))
                end
                return J.Switch(lower_expr(s.discriminant, this_name), cases)
            end,
            Label = function(s) return J.Label(STR(s.name), lower_stmt(s.body, this_name)) end,
            With = function() return unsupported("JsSurface.Stmt.With (intentionally unsupported: dynamic name resolution conflicts with JsSource -> JsResolved lexical slot resolution)") end,
            Import = function(s)
                local has_bindings = s.default_name ~= nil or s.namespace_name ~= nil or #s.named > 0
                local req = require_call(s.from)
                if not has_bindings then
                    return J.ExprStmt(req)
                end
                local temp_name = gensym("__js_import_")
                local decls = L{ J.Declarator(temp_name, req) }
                if s.default_name then
                    decls[#decls + 1] = J.Declarator(
                        STR(s.default_name),
                        J.NullishCoalesce(member(J.Ident(temp_name), "default"), J.Ident(temp_name))
                    )
                end
                if s.namespace_name then
                    decls[#decls + 1] = J.Declarator(STR(s.namespace_name), J.Ident(temp_name))
                end
                for i = 1, #s.named do
                    local b = s.named[i]
                    decls[#decls + 1] = J.Declarator(
                        STR(b.local_name),
                        member(J.Ident(temp_name), STR(b.imported_name))
                    )
                end
                return J.VarDecl(T.JsCore.Const, decls)
            end,
            ExportNamed = function(s)
                local stmts = L{}
                local source_name = nil
                if s.from then
                    source_name = gensym("__js_export_")
                    stmts[#stmts + 1] = J.VarDecl(T.JsCore.Const, L{
                        J.Declarator(source_name, require_call(s.from))
                    })
                end
                for i = 1, #s.bindings do
                    local b = s.bindings[i]
                    local value = s.from
                        and member(J.Ident(source_name), STR(b.local_name))
                        or J.Ident(STR(b.local_name))
                    stmts[#stmts + 1] = assign_member_stmt(J.Ident("exports"), STR(b.exported_name), value)
                end
                return one_or_block(stmts)
            end,
            ExportAll = function(s)
                if s.alias then
                    return assign_member_stmt(J.Ident("exports"), STR(s.alias), require_call(s.from))
                end
                local source_name = gensym("__js_export_all_")
                local key_name = gensym("__js_export_key_")
                return J.Block(L{
                    J.VarDecl(T.JsCore.Const, L{ J.Declarator(source_name, require_call(s.from)) }),
                    J.ForIn(T.JsCore.Let, key_name, J.Ident(source_name), J.Block(L{
                        J.If(
                            J.BinOp(T.JsCore.NotEqEq, J.Ident(key_name), emit_string("default")),
                            assign_computed_stmt(
                                J.Ident("exports"),
                                J.Ident(key_name),
                                J.Member(J.Ident(source_name), J.Ident(key_name), true)
                            ),
                            nil
                        )
                    }))
                })
            end,
            ExportDefaultExpr = function(s)
                return assign_member_stmt(J.Ident("exports"), "default", lower_expr(s.expr, this_name))
            end,
            ExportDefaultDecl = function(s)
                return lower_export_decl_stmt(s.decl, "default", this_name)
            end,
            ExportDecl = function(s)
                return lower_export_decl_stmt(s.decl, declared_name(s.decl), this_name)
            end,
            ClassDecl = function(s)
                return J.VarDecl(T.JsCore.Let, L{ J.Declarator(STR(s.name), lower_class_expr(s, STR(s.name))) })
            end,
            Block = function(s) return J.Block(map_list(s.body, function(x) return lower_stmt(x, this_name) end)) end,
            Break = function(s) return J.Break(s.label and STR(s.label) or nil) end,
            Continue = function(s) return J.Continue(s.label and STR(s.label) or nil) end,
            Throw = function(s) return J.Throw(lower_expr(s.argument, this_name)) end,
            Try = function(s)
                return J.Try(lower_stmt(s.block, this_name), lower_catch(s.handler, this_name), s.finalizer and lower_stmt(s.finalizer, this_name) or nil)
            end,
            Empty = function() return J.Empty end,
        })
    end

    S.Program.lower = U.transition("JsSurface.Program:lower", function(program)
        return J.Program(map_list(program.body, lower_stmt))
    end)
end
