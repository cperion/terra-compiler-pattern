local U = require("unit")

return function(T, U, P)
    local tests = {}

    local function text_plan_catalog(host)
        return T.CrochetRealizePlan.Catalog({
            T.CrochetRealizePlan.TextProtoPlan(
                "entry",
                1,
                "@crochet-realize:entry",
                "text|entry|shape",
                "text|entry|artifact",
                "return function(x)\n  return x + inc\nend\n",
                {
                    T.CrochetRealizePlan.CapturePlan(
                        "inc",
                        1,
                        T.CrochetRealizeRuntime.ValueRef("inc", 4),
                        1
                    ),
                }
            ),
        }, 1, host)
    end

    local function closure_plan_catalog(host)
        return T.CrochetRealizePlan.Catalog({
            T.CrochetRealizePlan.ClosureProtoPlan(
                "entry",
                1,
                "closure|entry|shape",
                "closure|entry|artifact",
                {
                    T.CrochetRealizePlan.ParamPlan("x", 1),
                },
                {
                    T.CrochetRealizePlan.CapturePlan(
                        "inc",
                        1,
                        T.CrochetRealizeRuntime.ValueRef("inc", 4),
                        1
                    ),
                },
                T.CrochetRealizePlan.ClosurePlanBlock({
                    T.CrochetRealizePlan.ReturnPlan(
                        T.CrochetRealizePlan.BinaryExpr(
                            T.CrochetRealizePlan.AddOp,
                            T.CrochetRealizePlan.ParamExpr(1),
                            T.CrochetRealizePlan.CaptureExpr(1)
                        )
                    ),
                })
            ),
        }, 1, host)
    end

    function tests.test_prepare_install_maps_text_host_to_source_variant()
        local out = text_plan_catalog(T.CrochetRealizePlan.LuaSourceHost):prepare_install()

        assert(out.entry_proto_id == 1)
        assert(out.artifact_mode.kind == "SourceArtifact")
        assert(#out.protos == 1)
        assert(out.protos[1].kind == "SourceInstall")
        assert(out.protos[1].artifact_key == "text|entry|artifact")
    end

    function tests.test_prepare_install_maps_text_host_to_bytecode_variant()
        local out = text_plan_catalog(T.CrochetRealizePlan.LuaBytecodeHost):prepare_install()

        assert(out.artifact_mode.kind == "BytecodeArtifact")
        assert(out.protos[1].kind == "BytecodeInstall")
        assert(#out.protos[1].captures == 1)
        assert(out.protos[1].captures[1].bind_index == 1)
    end

    function tests.test_prepare_install_maps_closure_host_to_closure_variant()
        local out = closure_plan_catalog(
            T.CrochetRealizePlan.LuaClosureHost(T.CrochetRealizePlan.DirectClosureMode)
        ):prepare_install()

        assert(out.artifact_mode.kind == "ClosureArtifact")
        assert(out.protos[1].kind == "ClosureInstall")
        assert(#out.protos[1].params == 1)
        assert(out.protos[1].params[1].param_id == 1)
        assert(#out.protos[1].captures == 1)
        assert(out.protos[1].body.stmts[1].kind == "ReturnInstall")
    end

    return tests
end
