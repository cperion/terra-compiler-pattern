local U = require("unit")

return function(T, U, P)
    local tests = {}

    local function run_source(spec)
        local lowered = spec:lower()
        local machine = lowered:define_machine()
        local plan = machine:lower_luajit()
        local unit = plan:install()
        return unit.fn(nil), lowered, machine, plan
    end

    function tests.test_lower_filter_to_guard_and_any_predicate()
        local input = T.MoreFunSource.Spec(
            T.MoreFunSource.ArraySource(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunSource.MapPipe(
                T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end),
                T.MoreFunSource.FilterPipe(
                    T.MoreFunSource.ModEqNumberPred(2, 0),
                    T.MoreFunSource.DropPipe(1, T.MoreFunSource.EndPipe)
                )
            ),
            T.MoreFunSource.AnyTerminal(T.MoreFunSource.GtNumberPred(5))
        )

        local out = input:lower()
        assert(out.source.kind == "ArraySource")
        assert(out.pipe.kind == "MapPipe")
        assert(out.pipe.next.kind == "GuardPipe")
        assert(out.pipe.next.pred.kind == "ModEqNumberPred")
        assert(out.pipe.next.next.kind == "DropPipe")
        assert(out.terminal.kind == "AnyTerminal")
        assert(out.terminal.pred.kind == "GtNumberPred")
    end

    function tests.test_lower_chain_source()
        local input = T.MoreFunSource.Spec(
            T.MoreFunSource.ChainSource({
                T.MoreFunSource.ArraySource(T.MoreFunRuntime.ArrayInput("xs", { 1, 2 })),
                T.MoreFunSource.RangeSource(1, 3, 1),
            }),
            T.MoreFunSource.EndPipe,
            T.MoreFunSource.SumTerminal
        )

        local out = input:lower()
        assert(out.source.kind == "ChainSource")
        assert(#out.source.parts == 2)
        assert(out.source.parts[1].kind == "ArraySource")
        assert(out.source.parts[2].kind == "RangeSource")
        assert(out.pipe.kind == "EndPipe")
        assert(out.terminal.kind == "SumTerminal")
    end

    function tests.test_lower_byte_string_source()
        local input = T.MoreFunSource.Spec(
            T.MoreFunSource.ByteStringSource(T.MoreFunRuntime.StringInput("s", "abcd")),
            T.MoreFunSource.EndPipe,
            T.MoreFunSource.SumTerminal
        )

        local out = input:lower()
        assert(out.source.kind == "ByteStringSource")
    end

    function tests.test_end_to_end_array_fast_sum()
        local result, lowered, machine, plan = run_source(T.MoreFunSource.Spec(
            T.MoreFunSource.ArraySource(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })),
            T.MoreFunSource.MapPipe(
                T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end),
                T.MoreFunSource.FilterPipe(
                    T.MoreFunSource.ModEqNumberPred(2, 0),
                    T.MoreFunSource.DropPipe(1, T.MoreFunSource.TakePipe(2, T.MoreFunSource.EndPipe))
                )
            ),
            T.MoreFunSource.SumTerminal
        ))

        assert(result == 10)
        assert(lowered.pipe.kind == "MapPipe")
        assert(machine.body.kind == "FastBody")
        assert(plan.kind == "ArraySum")
    end

    function tests.test_end_to_end_byte_string_fast_sum()
        local result, lowered, machine, plan = run_source(T.MoreFunSource.Spec(
            T.MoreFunSource.ByteStringSource(T.MoreFunRuntime.StringInput("s", "ABCD")),
            T.MoreFunSource.EndPipe,
            T.MoreFunSource.SumTerminal
        ))

        assert(result == (65 + 66 + 67 + 68))
        assert(lowered.source.kind == "ByteStringSource")
        assert(machine.loop.kind == "ByteStringLoop")
        assert(plan.kind == "ByteStringSum")
    end

    function tests.test_end_to_end_string_char_semantics()
        local result, _, machine, plan = run_source(T.MoreFunSource.Spec(
            T.MoreFunSource.StringSource(T.MoreFunRuntime.StringInput("s", "abcd")),
            T.MoreFunSource.DropPipe(1, T.MoreFunSource.TakePipe(2, T.MoreFunSource.EndPipe)),
            T.MoreFunSource.ToTableTerminal
        ))

        assert(#result == 2)
        assert(result[1] == "b")
        assert(result[2] == "c")
        assert(machine.loop.kind == "StringLoop")
        assert(plan.kind == "StringToTable")
    end

    function tests.test_end_to_end_generic_order_fallback()
        local result, _, machine, plan = run_source(T.MoreFunSource.Spec(
            T.MoreFunSource.ArraySource(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4 })),
            T.MoreFunSource.TakePipe(
                2,
                T.MoreFunSource.MapPipe(
                    T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end),
                    T.MoreFunSource.EndPipe
                )
            ),
            T.MoreFunSource.SumTerminal
        ))

        assert(result == 5)
        assert(machine.body.kind == "GenericBody")
        assert(plan.kind == "GenericInstall")
    end

    function tests.test_end_to_end_raw_source_generic_fallback()
        local result, _, machine, plan = run_source(T.MoreFunSource.Spec(
            T.MoreFunSource.RawIterSource(
                T.MoreFunRuntime.CallRef("gen", function(param, state)
                    state = state + 1
                    if state > #param then return nil end
                    return state, param[state] * 3
                end),
                T.MoreFunRuntime.ValueRef("param", { 1, 2, 3, 4 }),
                T.MoreFunRuntime.ValueRef("state0", 0)
            ),
            T.MoreFunSource.EndPipe,
            T.MoreFunSource.ToTableTerminal
        ))

        assert(#result == 4)
        assert(result[1] == 3)
        assert(result[4] == 12)
        assert(machine.loop.kind == "RawWhileLoop")
        assert(plan.kind == "GenericInstall")
    end

    function tests.test_end_to_end_chain_source_generic_fallback()
        local result, _, machine, plan = run_source(T.MoreFunSource.Spec(
            T.MoreFunSource.ChainSource({
                T.MoreFunSource.ArraySource(T.MoreFunRuntime.ArrayInput("a", { 1, 2, 3 })),
                T.MoreFunSource.ArraySource(T.MoreFunRuntime.ArrayInput("b", { 4, 5, 6 })),
                T.MoreFunSource.RangeSource(7, 9, 1),
            }),
            T.MoreFunSource.TakePipe(5, T.MoreFunSource.EndPipe),
            T.MoreFunSource.ToTableTerminal
        ))

        assert(#result == 5)
        assert(result[1] == 1)
        assert(result[5] == 5)
        assert(machine.loop.kind == "ChainLoop")
        assert(plan.kind == "GenericInstall")
    end

    return tests
end
