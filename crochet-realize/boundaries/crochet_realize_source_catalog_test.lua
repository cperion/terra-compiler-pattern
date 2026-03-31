local U = require("unit")

return function(T, U, P)
    local tests = {}

    local function text_catalog(host)
        return T.CrochetRealizeSource.Catalog({
            T.CrochetRealizeSource.TextProto(
                "add_capture",
                { "x" },
                {
                    T.CrochetRealizeSource.Capture(
                        "inc",
                        T.CrochetRealizeRuntime.ValueRef("inc", 2)
                    ),
                },
                T.CrochetRealizeSource.TextBlock({
                    T.CrochetRealizeSource.LineNode({
                        T.CrochetRealizeSource.TextPart("return "),
                        T.CrochetRealizeSource.ParamRef("x"),
                        T.CrochetRealizeSource.TextPart(" + "),
                        T.CrochetRealizeSource.CaptureRef("inc"),
                    }),
                })
            ),
            T.CrochetRealizeSource.TextProto(
                "sum_to_n",
                { "n" },
                {},
                T.CrochetRealizeSource.TextBlock({
                    T.CrochetRealizeSource.LineNode({
                        T.CrochetRealizeSource.TextPart("local acc = 0"),
                    }),
                    T.CrochetRealizeSource.NestNode(
                        T.CrochetRealizeSource.TextLine({
                            T.CrochetRealizeSource.TextPart("for i = 1, "),
                            T.CrochetRealizeSource.ParamRef("n"),
                            T.CrochetRealizeSource.TextPart(" do"),
                        }),
                        T.CrochetRealizeSource.TextBlock({
                            T.CrochetRealizeSource.LineNode({
                                T.CrochetRealizeSource.TextPart("acc = acc + i"),
                            }),
                        }),
                        T.CrochetRealizeSource.TextLine({
                            T.CrochetRealizeSource.TextPart("end"),
                        })
                    ),
                    T.CrochetRealizeSource.LineNode({
                        T.CrochetRealizeSource.TextPart("return acc"),
                    }),
                })
            ),
        }, "add_capture", host)
    end

    local function closure_catalog(host)
        return T.CrochetRealizeSource.Catalog({
            T.CrochetRealizeSource.ClosureProto(
                "sum_plus_inc",
                { "n" },
                {
                    T.CrochetRealizeSource.Capture(
                        "inc",
                        T.CrochetRealizeRuntime.ValueRef("inc", 2)
                    ),
                },
                T.CrochetRealizeSource.ClosureBlock({
                    T.CrochetRealizeSource.LetStmt(
                        "acc",
                        T.CrochetRealizeSource.LiteralExpr(
                            T.CrochetRealizeRuntime.ValueRef("zero", 0)
                        )
                    ),
                    T.CrochetRealizeSource.ForRangeStmt(
                        "i",
                        T.CrochetRealizeSource.LiteralExpr(T.CrochetRealizeRuntime.ValueRef("one", 1)),
                        T.CrochetRealizeSource.ParamExpr("n"),
                        T.CrochetRealizeSource.LiteralExpr(T.CrochetRealizeRuntime.ValueRef("one", 1)),
                        T.CrochetRealizeSource.ClosureBlock({
                            T.CrochetRealizeSource.SetStmt(
                                "acc",
                                T.CrochetRealizeSource.BinaryExpr(
                                    T.CrochetRealizeSource.AddOp,
                                    T.CrochetRealizeSource.LocalExpr("acc"),
                                    T.CrochetRealizeSource.LocalExpr("i")
                                )
                            ),
                        })
                    ),
                    T.CrochetRealizeSource.ReturnStmt(
                        T.CrochetRealizeSource.BinaryExpr(
                            T.CrochetRealizeSource.AddOp,
                            T.CrochetRealizeSource.LocalExpr("acc"),
                            T.CrochetRealizeSource.CaptureExpr("inc")
                        )
                    ),
                })
            ),
        }, "sum_plus_inc", host)
    end

    function tests.test_check_realize_resolves_text_names_to_ids()
        local out = text_catalog(T.CrochetRealizeSource.LuaBytecodeHost):check_realize()

        assert(#out.protos == 2)
        assert(out.entry_proto_id == 1)
        assert(out.host.kind == "LuaBytecodeHost")
        assert(out.protos[1].kind == "TextProto")
        assert(out.protos[1].header.name == "add_capture")
        assert(out.protos[1].params[1].param_id == 1)
        assert(out.protos[1].captures[1].capture_id == 1)
        assert(out.protos[1].body.nodes[1].parts[2].kind == "ParamRef")
        assert(out.protos[1].body.nodes[1].parts[2].param_id == 1)
        assert(out.protos[1].body.nodes[1].parts[4].kind == "CaptureRef")
        assert(out.protos[1].body.nodes[1].parts[4].capture_id == 1)
    end

    function tests.test_check_realize_resolves_closure_names_to_ids()
        local out = closure_catalog(
            T.CrochetRealizeSource.LuaClosureHost(T.CrochetRealizeSource.DirectClosureMode)
        ):check_realize()

        assert(#out.protos == 1)
        assert(out.entry_proto_id == 1)
        assert(out.host.kind == "LuaClosureHost")
        assert(out.protos[1].kind == "ClosureProto")
        assert(out.protos[1].body.stmts[1].kind == "LetStmt")
        assert(out.protos[1].body.stmts[1].local_header.local_id == 1)
        assert(out.protos[1].body.stmts[2].kind == "ForRangeStmt")
        assert(out.protos[1].body.stmts[2].local_header.local_id == 2)
        assert(out.protos[1].body.stmts[3].value.kind == "BinaryExpr")
        assert(out.protos[1].body.stmts[3].value.lhs.kind == "LocalExpr")
        assert(out.protos[1].body.stmts[3].value.lhs.local_id == 1)
        assert(out.protos[1].body.stmts[3].value.rhs.kind == "CaptureExpr")
        assert(out.protos[1].body.stmts[3].value.rhs.capture_id == 1)
    end

    function tests.test_end_to_end_text_bytecode_host()
        local checked = text_catalog(T.CrochetRealizeSource.LuaBytecodeHost):check_realize()
        local plan = checked:lower_realize()
        local lua = plan:prepare_install()
        local unit = lua:install()
        local artifact = unit.fn(nil)

        assert(artifact.mode == "bytecode")
        assert(artifact.entry(5) == 7)
        assert(artifact:realize("sum_to_n")(5) == 15)
        assert(artifact.protos.add_capture.bytecode ~= nil)
        assert(artifact.protos.sum_to_n.bytecode ~= nil)
    end

    function tests.test_end_to_end_closure_host()
        local checked = closure_catalog(
            T.CrochetRealizeSource.LuaClosureHost(T.CrochetRealizeSource.DirectClosureMode)
        ):check_realize()
        local plan = checked:lower_realize()
        local lua = plan:prepare_install()
        local unit = lua:install()
        local artifact = unit.fn(nil)

        assert(artifact.mode == "closure")
        assert(artifact.entry(5) == 17)
        assert(artifact.protos.sum_plus_inc.bytecode == nil)
        assert(artifact.protos.sum_plus_inc.source == nil)
    end

    return tests
end
