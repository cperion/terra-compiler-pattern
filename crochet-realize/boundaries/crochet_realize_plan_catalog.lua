local ffi = require("ffi")
local U = require("unit")

local function S(v)
    if type(v) == "cdata" then
        return ffi.string(v)
    end
    return tostring(v)
end

return function(T, U, P)
    local function install_mode_for(host)
        return U.match(host, {
            LuaSourceHost = function()
                return T.CrochetRealizeLua.SourceArtifact
            end,
            LuaClosureHost = function()
                return T.CrochetRealizeLua.ClosureArtifact
            end,
            LuaBytecodeHost = function()
                return T.CrochetRealizeLua.BytecodeArtifact
            end,
        })
    end

    local function param_install_for(param)
        return T.CrochetRealizeLua.ParamInstall(S(param.name), param.param_id)
    end

    local function capture_install_for(capture)
        return T.CrochetRealizeLua.CaptureInstall(
            S(capture.name),
            capture.capture_id,
            capture.bind_index,
            capture.value
        )
    end

    local function install_unary_for(op)
        return U.match(op, {
            NotOp = function() return T.CrochetRealizeLua.NotOp end,
            NegOp = function() return T.CrochetRealizeLua.NegOp end,
            LenOp = function() return T.CrochetRealizeLua.LenOp end,
        })
    end

    local function install_binary_for(op)
        return U.match(op, {
            AddOp = function() return T.CrochetRealizeLua.AddOp end,
            SubOp = function() return T.CrochetRealizeLua.SubOp end,
            MulOp = function() return T.CrochetRealizeLua.MulOp end,
            DivOp = function() return T.CrochetRealizeLua.DivOp end,
            ModOp = function() return T.CrochetRealizeLua.ModOp end,
            EqOp = function() return T.CrochetRealizeLua.EqOp end,
            NeOp = function() return T.CrochetRealizeLua.NeOp end,
            LtOp = function() return T.CrochetRealizeLua.LtOp end,
            LeOp = function() return T.CrochetRealizeLua.LeOp end,
            GtOp = function() return T.CrochetRealizeLua.GtOp end,
            GeOp = function() return T.CrochetRealizeLua.GeOp end,
            AndOp = function() return T.CrochetRealizeLua.AndOp end,
            OrOp = function() return T.CrochetRealizeLua.OrOp end,
        })
    end

    local install_expr_for
    local install_block_for

    install_expr_for = function(expr)
        return U.match(expr, {
            ParamExpr = function(v)
                return T.CrochetRealizeLua.ParamExpr(v.param_id)
            end,
            CaptureExpr = function(v)
                return T.CrochetRealizeLua.CaptureExpr(v.capture_id)
            end,
            LocalExpr = function(v)
                return T.CrochetRealizeLua.LocalExpr(v.local_id)
            end,
            LiteralExpr = function(v)
                return T.CrochetRealizeLua.LiteralExpr(v.value)
            end,
            CallExpr = function(v)
                return T.CrochetRealizeLua.CallExpr(
                    install_expr_for(v.fn),
                    U.map(v.args, install_expr_for)
                )
            end,
            IndexExpr = function(v)
                return T.CrochetRealizeLua.IndexExpr(
                    install_expr_for(v.base),
                    install_expr_for(v.key)
                )
            end,
            UnaryExpr = function(v)
                return T.CrochetRealizeLua.UnaryExpr(install_unary_for(v.op), install_expr_for(v.value))
            end,
            BinaryExpr = function(v)
                return T.CrochetRealizeLua.BinaryExpr(
                    install_binary_for(v.op),
                    install_expr_for(v.lhs),
                    install_expr_for(v.rhs)
                )
            end,
        })
    end

    local function install_stmt_for(stmt)
        return U.match(stmt, {
            LetPlan = function(v)
                return T.CrochetRealizeLua.LetInstall(
                    T.CrochetRealizeLua.LocalInstall(S(v.local_info.name), v.local_info.local_id),
                    install_expr_for(v.value)
                )
            end,
            SetPlan = function(v)
                return T.CrochetRealizeLua.SetInstall(v.local_id, install_expr_for(v.value))
            end,
            EffectPlan = function(v)
                return T.CrochetRealizeLua.EffectInstall(install_expr_for(v.expr))
            end,
            ReturnPlan = function(v)
                return T.CrochetRealizeLua.ReturnInstall(install_expr_for(v.value))
            end,
            IfPlan = function(v)
                return T.CrochetRealizeLua.IfInstall(
                    install_expr_for(v.cond),
                    install_block_for(v.then_body),
                    install_block_for(v.else_body)
                )
            end,
            ForRangePlan = function(v)
                return T.CrochetRealizeLua.ForRangeInstall(
                    T.CrochetRealizeLua.LocalInstall(S(v.local_info.name), v.local_info.local_id),
                    install_expr_for(v.start),
                    install_expr_for(v.stop),
                    install_expr_for(v.step),
                    install_block_for(v.body)
                )
            end,
            WhilePlan = function(v)
                return T.CrochetRealizeLua.WhileInstall(
                    install_expr_for(v.cond),
                    install_block_for(v.body)
                )
            end,
        })
    end

    install_block_for = function(block)
        return T.CrochetRealizeLua.ClosureInstallBlock(U.map(block.stmts, install_stmt_for))
    end

    local function proto_install_for(host, proto)
        return U.match(host, {
            LuaSourceHost = function()
                return U.match(proto, {
                    TextProtoPlan = function(v)
                        return T.CrochetRealizeLua.SourceInstall(
                            S(v.name),
                            v.proto_id,
                            S(v.chunk_name),
                            S(v.artifact_key),
                            S(v.source)
                        )
                    end,
                    ClosureProtoPlan = function()
                        error("LuaSourceHost cannot prepare ClosureProtoPlan", 2)
                    end,
                })
            end,
            LuaClosureHost = function()
                return U.match(proto, {
                    TextProtoPlan = function()
                        error("LuaClosureHost cannot prepare TextProtoPlan", 2)
                    end,
                    ClosureProtoPlan = function(v)
                        return T.CrochetRealizeLua.ClosureInstall(
                            S(v.name),
                            v.proto_id,
                            S(v.artifact_key),
                            U.map(v.params, param_install_for),
                            U.map(v.captures, capture_install_for),
                            install_block_for(v.body)
                        )
                    end,
                })
            end,
            LuaBytecodeHost = function()
                return U.match(proto, {
                    TextProtoPlan = function(v)
                        return T.CrochetRealizeLua.BytecodeInstall(
                            S(v.name),
                            v.proto_id,
                            S(v.chunk_name),
                            S(v.artifact_key),
                            S(v.source),
                            U.map(v.captures, capture_install_for)
                        )
                    end,
                    ClosureProtoPlan = function()
                        error("LuaBytecodeHost cannot prepare ClosureProtoPlan", 2)
                    end,
                })
            end,
        })
    end

    local prepare_impl = U.transition("CrochetRealizePlan.Catalog:prepare_install", function(catalog)
        return T.CrochetRealizeLua.Catalog(
            U.map(catalog.protos, function(proto)
                return proto_install_for(catalog.host, proto)
            end),
            catalog.entry_proto_id,
            install_mode_for(catalog.host)
        )
    end)

    function T.CrochetRealizePlan.Catalog:prepare_install()
        return prepare_impl(self)
    end
end
