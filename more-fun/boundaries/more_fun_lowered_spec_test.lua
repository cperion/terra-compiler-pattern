local U = require("unit")

return function(T, U, P)
    local tests = {}

    function tests.test_define_machine_fast_body()
        local input = T.MoreFunLowered.Spec(
            T.MoreFunLowered.ArraySource(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunLowered.MapPipe(
                T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end),
                T.MoreFunLowered.GuardPipe(
                    T.MoreFunLowered.ModEqNumberPred(2, 0),
                    T.MoreFunLowered.DropPipe(
                        1,
                        T.MoreFunLowered.TakePipe(2, T.MoreFunLowered.EndPipe)
                    )
                )
            ),
            T.MoreFunLowered.SumTerminal
        )

        local out = input:define_machine()
        assert(out.loop.kind == "ArrayLoop")
        assert(out.terminal.kind == "SumPlan")
        assert(out.body.kind == "FastBody")
        assert(#out.body.maps == 1)
        assert(#out.body.guards == 1)
        assert(out.body.control.drop_count == 1)
        assert(out.body.control.take_count == 2)
    end

    function tests.test_define_machine_foldl_fast_body()
        local input = T.MoreFunLowered.Spec(
            T.MoreFunLowered.ArraySource(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunLowered.EndPipe,
            T.MoreFunLowered.FoldlTerminal(
                T.MoreFunRuntime.CallRef("add", function(acc, x) return acc + x end),
                T.MoreFunRuntime.ValueRef("init", 0)
            )
        )

        local out = input:define_machine()
        assert(out.terminal.kind == "FoldlPlan")
        assert(out.terminal.reducer.debug_name == "add")
        assert(out.body.kind == "FastBody")
    end

    function tests.test_define_machine_generic_when_order_is_not_fast()
        local input = T.MoreFunLowered.Spec(
            T.MoreFunLowered.ArraySource(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunLowered.TakePipe(
                2,
                T.MoreFunLowered.MapPipe(
                    T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end),
                    T.MoreFunLowered.EndPipe
                )
            ),
            T.MoreFunLowered.SumTerminal
        )

        local out = input:define_machine()
        assert(out.body.kind == "GenericBody")
        assert(out.body.pipe.kind == "TakePipe")
    end

    return tests
end
