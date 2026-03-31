local ffi = require("ffi")
local U = require("unit")

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
                return T.CrochetRealizeChecked.LuaSourceHost
            end,
            LuaClosureHost = function(v)
                return T.CrochetRealizeChecked.LuaClosureHost(closure_mode_for(v.mode))
            end,
            LuaBytecodeHost = function()
                return T.CrochetRealizeChecked.LuaBytecodeHost
            end,
        })
    end

    closure_mode_for = function(mode)
        return U.match(mode, {
            DirectClosureMode = function()
                return T.CrochetRealizeChecked.DirectClosureMode
            end,
            ClosureBundleMode = function()
                return T.CrochetRealizeChecked.ClosureBundleMode
            end,
        })
    end

    local function unique_name_map(items, name_of, label)
        return U.fold(items, function(acc, item)
            local name = name_of(item)
            assert(acc[name] == nil, label .. " name must be unique: " .. name)
            acc[name] = item
            return acc
        end, {})
    end

    local function param_name_map(params)
        return unique_name_map(params, function(param)
            return S(param.name)
        end, "param")
    end

    local function capture_name_map(captures)
        return unique_name_map(captures, function(capture)
            return S(capture.name)
        end, "capture")
    end

    local function assoc(tbl, key, value)
        local out = {}
        for k, v in pairs(tbl) do
            out[k] = v
        end
        out[key] = value
        return out
    end

    local function next_local_env(env, name)
        local local_id = env.next_local_id
        return T.CrochetRealizeChecked.LocalHeader(name, local_id), {
            params_by_name = env.params_by_name,
            captures_by_name = env.captures_by_name,
            locals_by_name = assoc(env.locals_by_name, name, local_id),
            next_local_id = local_id + 1,
        }
    end

    local checked_text_block_for
    local checked_text_line_for
    local checked_closure_block_for
    local checked_closure_expr_for

    local function checked_text_part_for(proto, part, params_by_name, captures_by_name)
        return U.match(part, {
            TextPart = function(v)
                return T.CrochetRealizeChecked.TextPart(S(v.text))
            end,
            ParamRef = function(v)
                local param = params_by_name[S(v.name)]
                assert(param ~= nil, "unknown param ref: " .. S(v.name) .. " in proto " .. S(proto.name))
                return T.CrochetRealizeChecked.ParamRef(param.param_id)
            end,
            CaptureRef = function(v)
                local capture = captures_by_name[S(v.name)]
                assert(capture ~= nil, "unknown capture ref: " .. S(v.name) .. " in proto " .. S(proto.name))
                return T.CrochetRealizeChecked.CaptureRef(capture.capture_id)
            end,
        })
    end

    checked_text_line_for = function(proto, line, params_by_name, captures_by_name)
        return T.CrochetRealizeChecked.TextLine(U.map(line.parts, function(part)
            return checked_text_part_for(proto, part, params_by_name, captures_by_name)
        end))
    end

    local function checked_text_node_for(proto, node, params_by_name, captures_by_name)
        return U.match(node, {
            LineNode = function(v)
                return T.CrochetRealizeChecked.LineNode(U.map(v.parts, function(part)
                    return checked_text_part_for(proto, part, params_by_name, captures_by_name)
                end))
            end,
            BlankNode = function()
                return T.CrochetRealizeChecked.BlankNode
            end,
            NestNode = function(v)
                return T.CrochetRealizeChecked.NestNode(
                    checked_text_line_for(proto, v.opener, params_by_name, captures_by_name),
                    checked_text_block_for(proto, v.body, params_by_name, captures_by_name),
                    checked_text_line_for(proto, v.closer, params_by_name, captures_by_name)
                )
            end,
        })
    end

    checked_text_block_for = function(proto, block, params_by_name, captures_by_name)
        return T.CrochetRealizeChecked.TextBlock(U.map(block.nodes, function(node)
            return checked_text_node_for(proto, node, params_by_name, captures_by_name)
        end))
    end

    local function checked_unary_for(op)
        return U.match(op, {
            NotOp = function() return T.CrochetRealizeChecked.NotOp end,
            NegOp = function() return T.CrochetRealizeChecked.NegOp end,
            LenOp = function() return T.CrochetRealizeChecked.LenOp end,
        })
    end

    local function checked_binary_for(op)
        return U.match(op, {
            AddOp = function() return T.CrochetRealizeChecked.AddOp end,
            SubOp = function() return T.CrochetRealizeChecked.SubOp end,
            MulOp = function() return T.CrochetRealizeChecked.MulOp end,
            DivOp = function() return T.CrochetRealizeChecked.DivOp end,
            ModOp = function() return T.CrochetRealizeChecked.ModOp end,
            EqOp = function() return T.CrochetRealizeChecked.EqOp end,
            NeOp = function() return T.CrochetRealizeChecked.NeOp end,
            LtOp = function() return T.CrochetRealizeChecked.LtOp end,
            LeOp = function() return T.CrochetRealizeChecked.LeOp end,
            GtOp = function() return T.CrochetRealizeChecked.GtOp end,
            GeOp = function() return T.CrochetRealizeChecked.GeOp end,
            AndOp = function() return T.CrochetRealizeChecked.AndOp end,
            OrOp = function() return T.CrochetRealizeChecked.OrOp end,
        })
    end

    checked_closure_expr_for = function(proto, expr, env)
        return U.match(expr, {
            ParamExpr = function(v)
                local param = env.params_by_name[S(v.name)]
                assert(param ~= nil, "unknown param expr: " .. S(v.name) .. " in proto " .. S(proto.name))
                return T.CrochetRealizeChecked.ParamExpr(param.param_id)
            end,
            CaptureExpr = function(v)
                local capture = env.captures_by_name[S(v.name)]
                assert(capture ~= nil, "unknown capture expr: " .. S(v.name) .. " in proto " .. S(proto.name))
                return T.CrochetRealizeChecked.CaptureExpr(capture.capture_id)
            end,
            LocalExpr = function(v)
                local local_id = env.locals_by_name[S(v.name)]
                assert(local_id ~= nil, "unknown local expr: " .. S(v.name) .. " in proto " .. S(proto.name))
                return T.CrochetRealizeChecked.LocalExpr(local_id)
            end,
            LiteralExpr = function(v)
                return T.CrochetRealizeChecked.LiteralExpr(v.value)
            end,
            CallExpr = function(v)
                return T.CrochetRealizeChecked.CallExpr(
                    checked_closure_expr_for(proto, v.fn, env),
                    U.map(v.args, function(arg)
                        return checked_closure_expr_for(proto, arg, env)
                    end)
                )
            end,
            IndexExpr = function(v)
                return T.CrochetRealizeChecked.IndexExpr(
                    checked_closure_expr_for(proto, v.base, env),
                    checked_closure_expr_for(proto, v.key, env)
                )
            end,
            UnaryExpr = function(v)
                return T.CrochetRealizeChecked.UnaryExpr(
                    checked_unary_for(v.op),
                    checked_closure_expr_for(proto, v.value, env)
                )
            end,
            BinaryExpr = function(v)
                return T.CrochetRealizeChecked.BinaryExpr(
                    checked_binary_for(v.op),
                    checked_closure_expr_for(proto, v.lhs, env),
                    checked_closure_expr_for(proto, v.rhs, env)
                )
            end,
        })
    end

    local function checked_closure_stmt_for(proto, stmt, env)
        return U.match(stmt, {
            LetStmt = function(v)
                local local_header, next_env = next_local_env(env, S(v.name))
                return T.CrochetRealizeChecked.LetStmt(
                    local_header,
                    checked_closure_expr_for(proto, v.value, env)
                ), next_env
            end,
            SetStmt = function(v)
                local local_id = env.locals_by_name[S(v.name)]
                assert(local_id ~= nil, "unknown local set: " .. S(v.name) .. " in proto " .. S(proto.name))
                return T.CrochetRealizeChecked.SetStmt(
                    local_id,
                    checked_closure_expr_for(proto, v.value, env)
                ), env
            end,
            EffectStmt = function(v)
                return T.CrochetRealizeChecked.EffectStmt(
                    checked_closure_expr_for(proto, v.expr, env)
                ), env
            end,
            ReturnStmt = function(v)
                return T.CrochetRealizeChecked.ReturnStmt(
                    checked_closure_expr_for(proto, v.value, env)
                ), env
            end,
            IfStmt = function(v)
                return T.CrochetRealizeChecked.IfStmt(
                    checked_closure_expr_for(proto, v.cond, env),
                    checked_closure_block_for(proto, v.then_body, env),
                    checked_closure_block_for(proto, v.else_body, env)
                ), env
            end,
            ForRangeStmt = function(v)
                local local_header, body_env = next_local_env(env, S(v.name))
                return T.CrochetRealizeChecked.ForRangeStmt(
                    local_header,
                    checked_closure_expr_for(proto, v.start, env),
                    checked_closure_expr_for(proto, v.stop, env),
                    checked_closure_expr_for(proto, v.step, env),
                    checked_closure_block_for(proto, v.body, body_env)
                ), env
            end,
            WhileStmt = function(v)
                return T.CrochetRealizeChecked.WhileStmt(
                    checked_closure_expr_for(proto, v.cond, env),
                    checked_closure_block_for(proto, v.body, env)
                ), env
            end,
        })
    end

    checked_closure_block_for = function(proto, block, env)
        local acc = U.fold(block.stmts, function(state, stmt)
            local checked_stmt, next_env = checked_closure_stmt_for(proto, stmt, state.env)
            state.stmts[#state.stmts + 1] = checked_stmt
            return {
                stmts = state.stmts,
                env = next_env,
            }
        end, {
            stmts = {},
            env = env,
        })
        return T.CrochetRealizeChecked.ClosureBlock(acc.stmts)
    end

    local function checked_params_for(params)
        return U.fold(params, function(acc, name)
            local param_id = #acc + 1
            acc[param_id] = T.CrochetRealizeChecked.Param(S(name), param_id)
            return acc
        end, {})
    end

    local function checked_captures_for(captures)
        return U.fold(captures, function(acc, capture)
            local capture_id = #acc + 1
            acc[capture_id] = T.CrochetRealizeChecked.Capture(S(capture.name), capture_id, capture.value)
            return acc
        end, {})
    end

    local function checked_text_proto_for(proto, proto_id)
        local header = T.CrochetRealizeChecked.ProtoHeader(S(proto.name), proto_id)
        local params = checked_params_for(proto.params)
        local captures = checked_captures_for(proto.captures)
        local params_by_name = param_name_map(params)
        local captures_by_name = capture_name_map(captures)

        return T.CrochetRealizeChecked.TextProto(
            header,
            params,
            captures,
            checked_text_block_for(proto, proto.body, params_by_name, captures_by_name)
        )
    end

    local function checked_closure_proto_for(proto, proto_id)
        local header = T.CrochetRealizeChecked.ProtoHeader(S(proto.name), proto_id)
        local params = checked_params_for(proto.params)
        local captures = checked_captures_for(proto.captures)
        local env = {
            params_by_name = param_name_map(params),
            captures_by_name = capture_name_map(captures),
            locals_by_name = {},
            next_local_id = 1,
        }

        return T.CrochetRealizeChecked.ClosureProto(
            header,
            params,
            captures,
            checked_closure_block_for(proto, proto.body, env)
        )
    end

    local function checked_proto_for(proto, proto_id)
        return U.match(proto, {
            TextProto = function(v)
                return checked_text_proto_for(v, proto_id)
            end,
            ClosureProto = function(v)
                return checked_closure_proto_for(v, proto_id)
            end,
        })
    end

    local function entry_proto_id_for(protos, entry_name)
        local proto = U.find(protos, function(item)
            return S(item.header.name) == entry_name
        end)
        assert(proto ~= nil, "entry proto not found: " .. entry_name)
        return proto.header.proto_id
    end

    local function validate_proto_host(proto, host)
        return U.match(host, {
            LuaSourceHost = function()
                assert(proto.kind == "TextProto", "LuaSourceHost requires TextProto bodies")
            end,
            LuaBytecodeHost = function()
                assert(proto.kind == "TextProto", "LuaBytecodeHost requires TextProto bodies")
            end,
            LuaClosureHost = function()
                assert(proto.kind == "ClosureProto", "LuaClosureHost requires ClosureProto bodies")
            end,
        })
    end

    local check_impl = U.transition("CrochetRealizeSource.Catalog:check_realize", function(catalog)
        U.each(catalog.protos, function(proto)
            validate_proto_host(proto, catalog.host)
        end)

        local protos = U.fold(catalog.protos, function(acc, proto)
            local proto_id = #acc + 1
            acc[proto_id] = checked_proto_for(proto, proto_id)
            return acc
        end, {})

        unique_name_map(protos, function(proto)
            return S(proto.header.name)
        end, "proto")

        return T.CrochetRealizeChecked.Catalog(
            protos,
            entry_proto_id_for(protos, S(catalog.entry_name)),
            host_for(catalog.host)
        )
    end)

    function T.CrochetRealizeSource.Catalog:check_realize()
        return check_impl(self)
    end
end
