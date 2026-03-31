local U = require("unit")

return function(T, U, P)
    local tests = {}

    local function checked_text_catalog(host)
        return T.CrochetRealizeChecked.Catalog({
            T.CrochetRealizeChecked.TextProto(
                T.CrochetRealizeChecked.ProtoHeader("entry", 1),
                {
                    T.CrochetRealizeChecked.Param("x", 1),
                },
                {
                    T.CrochetRealizeChecked.Capture("inc", 1, T.CrochetRealizeRuntime.ValueRef("inc", 3)),
                },
                T.CrochetRealizeChecked.TextBlock({
                    T.CrochetRealizeChecked.LineNode({
                        T.CrochetRealizeChecked.TextPart("return "),
                        T.CrochetRealizeChecked.ParamRef(1),
                        T.CrochetRealizeChecked.TextPart(" + "),
                        T.CrochetRealizeChecked.CaptureRef(1),
                    }),
                })
            ),
        }, 1, host)
    end

    local function checked_closure_catalog(host)
        return T.CrochetRealizeChecked.Catalog({
            T.CrochetRealizeChecked.ClosureProto(
                T.CrochetRealizeChecked.ProtoHeader("entry", 1),
                {
                    T.CrochetRealizeChecked.Param("n", 1),
                },
                {
                    T.CrochetRealizeChecked.Capture("inc", 1, T.CrochetRealizeRuntime.ValueRef("inc", 4)),
                },
                T.CrochetRealizeChecked.ClosureBlock({
                    T.CrochetRealizeChecked.LetStmt(
                        T.CrochetRealizeChecked.LocalHeader("acc", 1),
                        T.CrochetRealizeChecked.LiteralExpr(T.CrochetRealizeRuntime.ValueRef("zero", 0))
                    ),
                    T.CrochetRealizeChecked.ForRangeStmt(
                        T.CrochetRealizeChecked.LocalHeader("i", 2),
                        T.CrochetRealizeChecked.LiteralExpr(T.CrochetRealizeRuntime.ValueRef("one", 1)),
                        T.CrochetRealizeChecked.ParamExpr(1),
                        T.CrochetRealizeChecked.LiteralExpr(T.CrochetRealizeRuntime.ValueRef("one", 1)),
                        T.CrochetRealizeChecked.ClosureBlock({
                            T.CrochetRealizeChecked.SetStmt(
                                1,
                                T.CrochetRealizeChecked.BinaryExpr(
                                    T.CrochetRealizeChecked.AddOp,
                                    T.CrochetRealizeChecked.LocalExpr(1),
                                    T.CrochetRealizeChecked.LocalExpr(2)
                                )
                            ),
                        })
                    ),
                    T.CrochetRealizeChecked.ReturnStmt(
                        T.CrochetRealizeChecked.BinaryExpr(
                            T.CrochetRealizeChecked.AddOp,
                            T.CrochetRealizeChecked.LocalExpr(1),
                            T.CrochetRealizeChecked.CaptureExpr(1)
                        )
                    ),
                })
            ),
        }, 1, host)
    end

    function tests.test_lower_realize_renders_text_proto_and_keys()
        local out = checked_text_catalog(T.CrochetRealizeChecked.LuaBytecodeHost):lower_realize()

        assert(#out.protos == 1)
        assert(out.entry_proto_id == 1)
        assert(out.host.kind == "LuaBytecodeHost")
        assert(out.protos[1].kind == "TextProtoPlan")
        assert(out.protos[1].name == "entry")
        assert(out.protos[1].chunk_name == "@crochet-realize:entry")
        assert(out.protos[1].shape_key:match("text|entry|"))
        assert(out.protos[1].artifact_key:match("captures=1:inc"))
        assert(out.protos[1].source:match("return function%(x%)"))
        assert(out.protos[1].source:match("return x %+ inc"))
    end

    function tests.test_lower_realize_builds_closure_plan_and_keys()
        local out = checked_closure_catalog(
            T.CrochetRealizeChecked.LuaClosureHost(T.CrochetRealizeChecked.DirectClosureMode)
        ):lower_realize()

        assert(#out.protos == 1)
        assert(out.entry_proto_id == 1)
        assert(out.host.kind == "LuaClosureHost")
        assert(out.protos[1].kind == "ClosureProtoPlan")
        assert(out.protos[1].shape_key:match("closure|entry|"))
        assert(out.protos[1].artifact_key:match("captures=1:inc"))
        assert(#out.protos[1].params == 1)
        assert(out.protos[1].params[1].param_id == 1)
        assert(out.protos[1].body.stmts[1].kind == "LetPlan")
        assert(out.protos[1].body.stmts[2].kind == "ForRangePlan")
        assert(out.protos[1].body.stmts[3].kind == "ReturnPlan")
    end

    return tests
end
