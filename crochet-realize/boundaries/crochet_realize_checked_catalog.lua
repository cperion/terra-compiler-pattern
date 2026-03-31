local ffi = require("ffi")
local C = require("crochet")
local U = require("unit")

local _table_concat = table.concat

local function S(v)
    if type(v) == "cdata" then
        return ffi.string(v)
    end
    return tostring(v)
end

return function(T, U, P)
    local closure_mode_for

    local function host_for(host)
        return U.match(host, {
            LuaSourceHost = function()
                return T.CrochetRealizePlan.LuaSourceHost
            end,
            LuaClosureHost = function(v)
                return T.CrochetRealizePlan.LuaClosureHost(closure_mode_for(v.mode))
            end,
            LuaBytecodeHost = function()
                return T.CrochetRealizePlan.LuaBytecodeHost
            end,
        })
    end

    closure_mode_for = function(mode)
        return U.match(mode, {
            DirectClosureMode = function()
                return T.CrochetRealizePlan.DirectClosureMode
            end,
            ClosureBundleMode = function()
                return T.CrochetRealizePlan.ClosureBundleMode
            end,
        })
    end

    local function by_id(items, id_field)
        return U.fold(items, function(acc, item)
            acc[item[id_field]] = item
            return acc
        end, {})
    end

    local render_text_block_for
    local render_text_line_for

    local function render_text_part_for(part, params_by_id, captures_by_id)
        return U.match(part, {
            TextPart = function(v)
                return S(v.text)
            end,
            ParamRef = function(v)
                return S(params_by_id[v.param_id].name)
            end,
            CaptureRef = function(v)
                return S(captures_by_id[v.capture_id].name)
            end,
        })
    end

    render_text_line_for = function(line, params_by_id, captures_by_id)
        return C.line(C.join(U.map(line.parts, function(part)
            return C.text(render_text_part_for(part, params_by_id, captures_by_id))
        end), ""))
    end

    local function render_text_node_for(node, params_by_id, captures_by_id)
        return U.match(node, {
            LineNode = function(v)
                return C.line(C.join(U.map(v.parts, function(part)
                    return C.text(render_text_part_for(part, params_by_id, captures_by_id))
                end), ""))
            end,
            BlankNode = function()
                return C.blank()
            end,
            NestNode = function(v)
                return C.block({
                    render_text_line_for(v.opener, params_by_id, captures_by_id),
                    C.indent(render_text_block_for(v.body, params_by_id, captures_by_id)),
                    render_text_line_for(v.closer, params_by_id, captures_by_id),
                })
            end,
        })
    end

    render_text_block_for = function(block, params_by_id, captures_by_id)
        return C.block(U.map(block.nodes, function(node)
            return render_text_node_for(node, params_by_id, captures_by_id)
        end))
    end

    local function capture_plans_for(captures)
        return U.fold(captures, function(acc, capture)
            local bind_index = #acc + 1
            acc[bind_index] = T.CrochetRealizePlan.CapturePlan(
                S(capture.name),
                capture.capture_id,
                capture.value,
                bind_index
            )
            return acc
        end, {})
    end

    local function param_plans_for(params)
        return U.map(params, function(param)
            return T.CrochetRealizePlan.ParamPlan(S(param.name), param.param_id)
        end)
    end

    local function capture_bind_signature(captures)
        return _table_concat(U.map(captures, function(capture)
            return tostring(capture.capture_id) .. ":" .. S(capture.name)
        end), ",")
    end

    local function text_source_for(proto)
        local params_by_id = by_id(proto.params, "param_id")
        local captures_by_id = by_id(proto.captures, "capture_id")
        local chunk = C.block({
            C.line("return function(", C.csv(U.map(proto.params, function(param)
                return S(param.name)
            end)), ")"),
            C.indent(render_text_block_for(proto.body, params_by_id, captures_by_id)),
            C.line("end"),
        })
        return C.render(chunk)
    end

    local function plan_unary_for(op)
        return U.match(op, {
            NotOp = function() return T.CrochetRealizePlan.NotOp end,
            NegOp = function() return T.CrochetRealizePlan.NegOp end,
            LenOp = function() return T.CrochetRealizePlan.LenOp end,
        })
    end

    local function plan_binary_for(op)
        return U.match(op, {
            AddOp = function() return T.CrochetRealizePlan.AddOp end,
            SubOp = function() return T.CrochetRealizePlan.SubOp end,
            MulOp = function() return T.CrochetRealizePlan.MulOp end,
            DivOp = function() return T.CrochetRealizePlan.DivOp end,
            ModOp = function() return T.CrochetRealizePlan.ModOp end,
            EqOp = function() return T.CrochetRealizePlan.EqOp end,
            NeOp = function() return T.CrochetRealizePlan.NeOp end,
            LtOp = function() return T.CrochetRealizePlan.LtOp end,
            LeOp = function() return T.CrochetRealizePlan.LeOp end,
            GtOp = function() return T.CrochetRealizePlan.GtOp end,
            GeOp = function() return T.CrochetRealizePlan.GeOp end,
            AndOp = function() return T.CrochetRealizePlan.AndOp end,
            OrOp = function() return T.CrochetRealizePlan.OrOp end,
        })
    end

    local closure_plan_expr_for
    local closure_plan_block_for

    closure_plan_expr_for = function(expr)
        return U.match(expr, {
            ParamExpr = function(v)
                return T.CrochetRealizePlan.ParamExpr(v.param_id)
            end,
            CaptureExpr = function(v)
                return T.CrochetRealizePlan.CaptureExpr(v.capture_id)
            end,
            LocalExpr = function(v)
                return T.CrochetRealizePlan.LocalExpr(v.local_id)
            end,
            LiteralExpr = function(v)
                return T.CrochetRealizePlan.LiteralExpr(v.value)
            end,
            CallExpr = function(v)
                return T.CrochetRealizePlan.CallExpr(
                    closure_plan_expr_for(v.fn),
                    U.map(v.args, closure_plan_expr_for)
                )
            end,
            IndexExpr = function(v)
                return T.CrochetRealizePlan.IndexExpr(
                    closure_plan_expr_for(v.base),
                    closure_plan_expr_for(v.key)
                )
            end,
            UnaryExpr = function(v)
                return T.CrochetRealizePlan.UnaryExpr(plan_unary_for(v.op), closure_plan_expr_for(v.value))
            end,
            BinaryExpr = function(v)
                return T.CrochetRealizePlan.BinaryExpr(
                    plan_binary_for(v.op),
                    closure_plan_expr_for(v.lhs),
                    closure_plan_expr_for(v.rhs)
                )
            end,
        })
    end

    local function closure_plan_stmt_for(stmt)
        return U.match(stmt, {
            LetStmt = function(v)
                return T.CrochetRealizePlan.LetPlan(
                    T.CrochetRealizePlan.LocalPlan(S(v.local_header.name), v.local_header.local_id),
                    closure_plan_expr_for(v.value)
                )
            end,
            SetStmt = function(v)
                return T.CrochetRealizePlan.SetPlan(v.local_id, closure_plan_expr_for(v.value))
            end,
            EffectStmt = function(v)
                return T.CrochetRealizePlan.EffectPlan(closure_plan_expr_for(v.expr))
            end,
            ReturnStmt = function(v)
                return T.CrochetRealizePlan.ReturnPlan(closure_plan_expr_for(v.value))
            end,
            IfStmt = function(v)
                return T.CrochetRealizePlan.IfPlan(
                    closure_plan_expr_for(v.cond),
                    closure_plan_block_for(v.then_body),
                    closure_plan_block_for(v.else_body)
                )
            end,
            ForRangeStmt = function(v)
                return T.CrochetRealizePlan.ForRangePlan(
                    T.CrochetRealizePlan.LocalPlan(S(v.local_header.name), v.local_header.local_id),
                    closure_plan_expr_for(v.start),
                    closure_plan_expr_for(v.stop),
                    closure_plan_expr_for(v.step),
                    closure_plan_block_for(v.body)
                )
            end,
            WhileStmt = function(v)
                return T.CrochetRealizePlan.WhilePlan(
                    closure_plan_expr_for(v.cond),
                    closure_plan_block_for(v.body)
                )
            end,
        })
    end

    closure_plan_block_for = function(block)
        return T.CrochetRealizePlan.ClosurePlanBlock(U.map(block.stmts, closure_plan_stmt_for))
    end

    local unary_name = function(op)
        return U.match(op, {
            NotOp = function() return "not" end,
            NegOp = function() return "neg" end,
            LenOp = function() return "len" end,
        })
    end

    local binary_name = function(op)
        return U.match(op, {
            AddOp = function() return "add" end,
            SubOp = function() return "sub" end,
            MulOp = function() return "mul" end,
            DivOp = function() return "div" end,
            ModOp = function() return "mod" end,
            EqOp = function() return "eq" end,
            NeOp = function() return "ne" end,
            LtOp = function() return "lt" end,
            LeOp = function() return "le" end,
            GtOp = function() return "gt" end,
            GeOp = function() return "ge" end,
            AndOp = function() return "and" end,
            OrOp = function() return "or" end,
        })
    end

    local closure_sig_expr
    local closure_sig_block

    closure_sig_expr = function(expr)
        return U.match(expr, {
            ParamExpr = function(v) return "p" .. tostring(v.param_id) end,
            CaptureExpr = function(v) return "c" .. tostring(v.capture_id) end,
            LocalExpr = function(v) return "l" .. tostring(v.local_id) end,
            LiteralExpr = function(v) return "lit(" .. S(v.value.debug_name) .. ")" end,
            CallExpr = function(v)
                return "call(" .. closure_sig_expr(v.fn) .. "," .. _table_concat(U.map(v.args, closure_sig_expr), ",") .. ")"
            end,
            IndexExpr = function(v)
                return "idx(" .. closure_sig_expr(v.base) .. "," .. closure_sig_expr(v.key) .. ")"
            end,
            UnaryExpr = function(v)
                return "un(" .. unary_name(v.op) .. "," .. closure_sig_expr(v.value) .. ")"
            end,
            BinaryExpr = function(v)
                return "bin(" .. binary_name(v.op) .. "," .. closure_sig_expr(v.lhs) .. "," .. closure_sig_expr(v.rhs) .. ")"
            end,
        })
    end

    local function closure_sig_stmt(stmt)
        return U.match(stmt, {
            LetStmt = function(v)
                return "let(" .. tostring(v.local_header.local_id) .. "," .. closure_sig_expr(v.value) .. ")"
            end,
            SetStmt = function(v)
                return "set(" .. tostring(v.local_id) .. "," .. closure_sig_expr(v.value) .. ")"
            end,
            EffectStmt = function(v)
                return "effect(" .. closure_sig_expr(v.expr) .. ")"
            end,
            ReturnStmt = function(v)
                return "return(" .. closure_sig_expr(v.value) .. ")"
            end,
            IfStmt = function(v)
                return "if(" .. closure_sig_expr(v.cond) .. "," .. closure_sig_block(v.then_body) .. "," .. closure_sig_block(v.else_body) .. ")"
            end,
            ForRangeStmt = function(v)
                return "for(" .. tostring(v.local_header.local_id) .. "," .. closure_sig_expr(v.start) .. "," .. closure_sig_expr(v.stop) .. "," .. closure_sig_expr(v.step) .. "," .. closure_sig_block(v.body) .. ")"
            end,
            WhileStmt = function(v)
                return "while(" .. closure_sig_expr(v.cond) .. "," .. closure_sig_block(v.body) .. ")"
            end,
        })
    end

    closure_sig_block = function(block)
        return "{" .. _table_concat(U.map(block.stmts, closure_sig_stmt), ";") .. "}"
    end

    local function text_proto_plan_for(proto)
        local source = text_source_for(proto)
        local name = S(proto.header.name)
        local shape_key = "text|" .. name .. "|" .. source
        local artifact_key = shape_key .. "|captures=" .. capture_bind_signature(proto.captures)
        return T.CrochetRealizePlan.TextProtoPlan(
            name,
            proto.header.proto_id,
            "@crochet-realize:" .. name,
            shape_key,
            artifact_key,
            source,
            capture_plans_for(proto.captures)
        )
    end

    local function closure_proto_plan_for(proto)
        local name = S(proto.header.name)
        local shape_key = "closure|" .. name .. "|" .. closure_sig_block(proto.body)
        local artifact_key = shape_key .. "|captures=" .. capture_bind_signature(proto.captures)
        return T.CrochetRealizePlan.ClosureProtoPlan(
            name,
            proto.header.proto_id,
            shape_key,
            artifact_key,
            param_plans_for(proto.params),
            capture_plans_for(proto.captures),
            closure_plan_block_for(proto.body)
        )
    end

    local function proto_plan_for(proto)
        return U.match(proto, {
            TextProto = function(v)
                return text_proto_plan_for(v)
            end,
            ClosureProto = function(v)
                return closure_proto_plan_for(v)
            end,
        })
    end

    local lower_impl = U.transition("CrochetRealizeChecked.Catalog:lower_realize", function(catalog)
        return T.CrochetRealizePlan.Catalog(
            U.map(catalog.protos, proto_plan_for),
            catalog.entry_proto_id,
            host_for(catalog.host)
        )
    end)

    function T.CrochetRealizeChecked.Catalog:lower_realize()
        return lower_impl(self)
    end
end
