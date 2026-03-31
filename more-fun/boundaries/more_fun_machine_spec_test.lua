local U = require("unit")

return function(T, U, P)
    local tests = {}

    function tests.test_lower_luajit_array_sum()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.SumPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArraySum")
    end

    function tests.test_lower_luajit_array_foldl()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.FoldlPlan(
                T.MoreFunRuntime.CallRef("add", function(acc, x) return acc + x end),
                T.MoreFunRuntime.ValueRef("init", 0)
            )
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArrayFoldl")
    end

    function tests.test_lower_luajit_array_head()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.HeadPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArrayHead")
    end

    function tests.test_lower_luajit_array_to_table()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.ToTablePlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArrayToTable")
    end

    function tests.test_lower_luajit_array_nth()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.NthPlan(2)
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArrayNth")
    end

    function tests.test_lower_luajit_array_any()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.AnyPlan(T.MoreFunMachine.GtNumberPred(1))
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArrayAny")
    end

    function tests.test_lower_luajit_array_all()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.AllPlan(T.MoreFunMachine.GtNumberPred(0))
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArrayAll")
    end

    function tests.test_lower_luajit_array_min()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.MinPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArrayMin")
    end

    function tests.test_lower_luajit_array_max()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.MaxPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "ArrayMax")
    end

    function tests.test_lower_luajit_range_sum()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 3, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.SumPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeSum")
    end

    function tests.test_lower_luajit_range_head()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 3, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.HeadPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeHead")
    end

    function tests.test_lower_luajit_range_nth()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 5, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.NthPlan(2)
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeNth")
    end

    function tests.test_lower_luajit_range_foldl()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 3, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.FoldlPlan(
                T.MoreFunRuntime.CallRef("add", function(acc, x) return acc + x end),
                T.MoreFunRuntime.ValueRef("init", 0)
            )
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeFoldl")
    end

    function tests.test_lower_luajit_range_to_table()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 3, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.ToTablePlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeToTable")
    end

    function tests.test_lower_luajit_range_any()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 3, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.AnyPlan(T.MoreFunMachine.GtNumberPred(2))
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeAny")
    end

    function tests.test_lower_luajit_range_all()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 3, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.AllPlan(T.MoreFunMachine.GtNumberPred(0))
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeAll")
    end

    function tests.test_lower_luajit_range_min()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 3, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.MinPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeMin")
    end

    function tests.test_lower_luajit_range_max()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 3, 1),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.MaxPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "RangeMax")
    end

    function tests.test_lower_luajit_string_to_table()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.StringLoop(T.MoreFunRuntime.StringInput("s", "abcd")),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.ToTablePlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "StringToTable")
    end

    function tests.test_lower_luajit_string_head()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.StringLoop(T.MoreFunRuntime.StringInput("s", "abcd")),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.HeadPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "StringHead")
    end

    function tests.test_lower_luajit_string_any()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.StringLoop(T.MoreFunRuntime.StringInput("s", "abcd")),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.AnyPlan(T.MoreFunMachine.CallPred(T.MoreFunRuntime.CallRef("isb", function(x) return x == "b" end)))
        )

        local out = input:lower_luajit()
        assert(out.kind == "StringAny")
    end

    function tests.test_lower_luajit_byte_string_sum()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ByteStringLoop(T.MoreFunRuntime.StringInput("s", "abcd")),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.SumPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "ByteStringSum")
    end

    function tests.test_lower_luajit_byte_string_head()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.ByteStringLoop(T.MoreFunRuntime.StringInput("s", "abcd")),
            T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
            T.MoreFunMachine.HeadPlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "ByteStringHead")
    end

    function tests.test_lower_luajit_generic_fallback()
        local input = T.MoreFunMachine.Spec(
            T.MoreFunMachine.RangeLoop(1, 10, 1),
            T.MoreFunMachine.GenericBody(T.MoreFunMachine.EndPipe),
            T.MoreFunMachine.ToTablePlan
        )

        local out = input:lower_luajit()
        assert(out.kind == "GenericInstall")
    end

    return tests
end
