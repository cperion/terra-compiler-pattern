local U = require("unit")

local function project_ctx()
    local I = U.inspect_from("more-fun")
    return I.ctx
end

local function even_pred(T)
    return T.MoreFunLuaJIT.ModEqNumberPred(2, 0)
end

local function test_install_array_sum_plain()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.ArraySum(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 10)
end

local function test_install_array_sum_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArraySum(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 10)
end

local function test_install_array_foldl_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("double", function(x) return x * 2 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(T.MoreFunLuaJIT.GtNumberPred(4)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArrayFoldl(
        loop,
        body,
        T.MoreFunRuntime.CallRef("append", function(acc, x) return acc .. ":" .. tostring(x) end),
        T.MoreFunRuntime.ValueRef("init", "start")
    )

    local unit = plan:install()
    assert(unit.fn(nil) == "start:8:10")
end

local function test_install_array_head_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArrayHead(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 4)
end

local function test_install_array_head_take_zero()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, true))
    local plan = T.MoreFunLuaJIT.ArrayHead(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == nil)
end

local function test_install_array_to_table_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArrayToTable(loop, body)

    local unit = plan:install()
    local out = unit.fn(nil)
    assert(#out == 2)
    assert(out[1] == 4)
    assert(out[2] == 6)
end

local function test_install_array_to_table_take_zero()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, true))
    local plan = T.MoreFunLuaJIT.ArrayToTable(loop, body)

    local unit = plan:install()
    local out = unit.fn(nil)
    assert(#out == 0)
end

local function test_install_array_nth_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArrayNth(loop, body, 2)

    local unit = plan:install()
    assert(unit.fn(nil) == 6)
end

local function test_install_array_nth_out_of_bounds()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.ArrayNth(loop, body, 10)

    local unit = plan:install()
    assert(unit.fn(nil) == nil)
end

local function test_install_array_any_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArrayAny(loop, body, T.MoreFunLuaJIT.GtNumberPred(5))

    local unit = plan:install()
    assert(unit.fn(nil) == true)
end

local function test_install_array_any_false()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.ArrayAny(loop, body, T.MoreFunLuaJIT.GtNumberPred(10))

    local unit = plan:install()
    assert(unit.fn(nil) == false)
end

local function test_install_array_all_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArrayAll(loop, body, T.MoreFunLuaJIT.GtNumberPred(3))

    local unit = plan:install()
    assert(unit.fn(nil) == true)
end

local function test_install_array_all_false()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.ArrayAll(loop, body, T.MoreFunLuaJIT.GtNumberPred(1))

    local unit = plan:install()
    assert(unit.fn(nil) == false)
end

local function test_install_array_all_take_zero()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, true))
    local plan = T.MoreFunLuaJIT.ArrayAll(loop, body, T.MoreFunLuaJIT.GtNumberPred(100))

    local unit = plan:install()
    assert(unit.fn(nil) == true)
end

local function test_install_array_min_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArrayMin(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 4)
end

local function test_install_array_max_maps_guards_control()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.ArrayMax(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 6)
end

local function test_install_array_min_empty_after_take_zero()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, true))
    local plan = T.MoreFunLuaJIT.ArrayMin(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == nil)
end

local function test_install_array_max_empty_when_no_values_pass()
    local T = project_ctx()

    local input = T.MoreFunRuntime.ArrayInput("xs", { 1, 3, 5 })
    local loop = T.MoreFunLuaJIT.ArrayLoop(input)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {},
        {
            T.MoreFunLuaJIT.GuardStep(T.MoreFunLuaJIT.LtNumberPred(0)),
        },
        T.MoreFunLuaJIT.Control(0, 0, false)
    )
    local plan = T.MoreFunLuaJIT.ArrayMax(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == nil)
end

local function test_install_range_sum_plain()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(1, 4, 1)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.RangeSum(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 10)
end

local function test_install_range_head_maps_guards_control()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(1, 5, 1)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.RangeHead(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 4)
end

local function test_install_range_nth_maps_guards_control()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(1, 5, 1)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.RangeNth(loop, body, 2)

    local unit = plan:install()
    assert(unit.fn(nil) == 6)
end

local function test_install_range_nth_descending()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(5, 1, -1)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.RangeNth(loop, body, 3)

    local unit = plan:install()
    assert(unit.fn(nil) == 3)
end

local function test_install_range_foldl_plain()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(1, 4, 1)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.RangeFoldl(
        loop,
        body,
        T.MoreFunRuntime.CallRef("add", function(acc, x) return acc + x end),
        T.MoreFunRuntime.ValueRef("init", 0)
    )

    local unit = plan:install()
    assert(unit.fn(nil) == 10)
end

local function test_install_range_to_table_maps_guards_control()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(1, 5, 1)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.RangeToTable(loop, body)

    local unit = plan:install()
    local out = unit.fn(nil)
    assert(#out == 2)
    assert(out[1] == 4)
    assert(out[2] == 6)
end

local function test_install_range_any_true()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(1, 5, 1)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.RangeAny(loop, body, T.MoreFunLuaJIT.GtNumberPred(5))

    local unit = plan:install()
    assert(unit.fn(nil) == true)
end

local function test_install_range_all_true()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(1, 5, 1)
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(even_pred(T)),
        },
        T.MoreFunLuaJIT.Control(1, 2, true)
    )
    local plan = T.MoreFunLuaJIT.RangeAll(loop, body, T.MoreFunLuaJIT.GtNumberPred(3))

    local unit = plan:install()
    assert(unit.fn(nil) == true)
end

local function test_install_range_min_plain()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(5, 1, -1)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.RangeMin(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 1)
end

local function test_install_range_max_plain()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.RangeLoop(1, 5, 1)
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.RangeMax(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == 5)
end

local function test_install_string_to_table_drop_take()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", "abcd"))
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(1, 2, true))
    local plan = T.MoreFunLuaJIT.StringToTable(loop, body)

    local unit = plan:install()
    local out = unit.fn(nil)
    assert(#out == 2)
    assert(out[1] == "b")
    assert(out[2] == "c")
end

local function test_install_string_head_map_guard()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", "abcd"))
    local body = T.MoreFunLuaJIT.BodyPlan(
        {
            T.MoreFunLuaJIT.MapStep(T.MoreFunRuntime.CallRef("upper", function(x) return string.upper(x) end)),
        },
        {
            T.MoreFunLuaJIT.GuardStep(T.MoreFunLuaJIT.CallPred(T.MoreFunRuntime.CallRef("not_a", function(x) return x ~= "A" end))),
        },
        T.MoreFunLuaJIT.Control(0, 0, false)
    )
    local plan = T.MoreFunLuaJIT.StringHead(loop, body)

    local unit = plan:install()
    assert(unit.fn(nil) == "B")
end

local function test_install_string_nth()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", "abcd"))
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local plan = T.MoreFunLuaJIT.StringNth(loop, body, 3)

    local unit = plan:install()
    assert(unit.fn(nil) == "c")
end

local function test_install_string_any_and_all()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", "abcd"))
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local any_plan = T.MoreFunLuaJIT.StringAny(loop, body, T.MoreFunLuaJIT.CallPred(T.MoreFunRuntime.CallRef("isc", function(x) return x == "c" end)))
    local all_plan = T.MoreFunLuaJIT.StringAll(loop, body, T.MoreFunLuaJIT.CallPred(T.MoreFunRuntime.CallRef("islower", function(x) return x == string.lower(x) end)))

    assert(any_plan:install().fn(nil) == true)
    assert(all_plan:install().fn(nil) == true)
end

local function test_install_string_foldl_min_max()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", "dbca"))
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    local foldl = T.MoreFunLuaJIT.StringFoldl(
        loop,
        body,
        T.MoreFunRuntime.CallRef("append", function(acc, x) return acc .. x end),
        T.MoreFunRuntime.ValueRef("init", "")
    )

    assert(foldl:install().fn(nil) == "dbca")
    assert(T.MoreFunLuaJIT.StringMin(loop, body):install().fn(nil) == "a")
    assert(T.MoreFunLuaJIT.StringMax(loop, body):install().fn(nil) == "d")
end

local function test_install_byte_string_sum_head_nth()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.ByteStringLoop(T.MoreFunRuntime.StringInput("s", "ABCD"))
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))

    assert(T.MoreFunLuaJIT.ByteStringSum(loop, body):install().fn(nil) == (65 + 66 + 67 + 68))
    assert(T.MoreFunLuaJIT.ByteStringHead(loop, body):install().fn(nil) == 65)
    assert(T.MoreFunLuaJIT.ByteStringNth(loop, body, 3):install().fn(nil) == 67)
end

local function test_install_byte_string_to_table_any_min_max()
    local T = project_ctx()

    local loop = T.MoreFunLuaJIT.ByteStringLoop(T.MoreFunRuntime.StringInput("s", "abcd"))
    local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(1, 2, true))
    local out = T.MoreFunLuaJIT.ByteStringToTable(loop, body):install().fn(nil)
    assert(#out == 2)
    assert(out[1] == string.byte("b"))
    assert(out[2] == string.byte("c"))

    local full_body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
    assert(T.MoreFunLuaJIT.ByteStringAny(loop, full_body, T.MoreFunLuaJIT.GtNumberPred(100)):install().fn(nil) == false)
    assert(T.MoreFunLuaJIT.ByteStringAny(loop, full_body, T.MoreFunLuaJIT.GtNumberPred(98)):install().fn(nil) == true)
    assert(T.MoreFunLuaJIT.ByteStringMin(loop, full_body):install().fn(nil) == string.byte("a"))
    assert(T.MoreFunLuaJIT.ByteStringMax(loop, full_body):install().fn(nil) == string.byte("d"))
end

local function test_install_generic_array_generic_body_sum()
    local T = project_ctx()

    local machine = T.MoreFunMachine.Spec(
        T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", { 1, 2, 3, 4 })),
        T.MoreFunMachine.GenericBody(
            T.MoreFunMachine.TakePipe(
                2,
                T.MoreFunMachine.MapPipe(
                    T.MoreFunRuntime.CallRef("inc", function(x) return x + 1 end),
                    T.MoreFunMachine.EndPipe
                )
            )
        ),
        T.MoreFunMachine.SumPlan
    )

    local plan = machine:lower_luajit()
    assert(plan.kind == "GenericInstall")
    local unit = plan:install()
    assert(unit.fn(nil) == 5)
end

local function test_install_generic_raw_loop_to_table()
    local T = project_ctx()

    local machine = T.MoreFunMachine.Spec(
        T.MoreFunMachine.RawWhileLoop(
            T.MoreFunRuntime.CallRef("gen", function(param, state)
                state = state + 1
                if state > #param then return nil end
                return state, param[state] * 3
            end),
            T.MoreFunRuntime.ValueRef("param", { 1, 2, 3, 4 }),
            T.MoreFunRuntime.ValueRef("state0", 0)
        ),
        T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 0, false)),
        T.MoreFunMachine.ToTablePlan
    )

    local plan = machine:lower_luajit()
    assert(plan.kind == "GenericInstall")
    local out = plan:install().fn(nil)
    assert(#out == 4)
    assert(out[1] == 3)
    assert(out[4] == 12)
end

local function test_install_generic_chain_loop_global_take()
    local T = project_ctx()

    local machine = T.MoreFunMachine.Spec(
        T.MoreFunMachine.ChainLoop({
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("a", { 1, 2, 3 })),
            T.MoreFunMachine.ArrayLoop(T.MoreFunRuntime.ArrayInput("b", { 4, 5, 6 })),
            T.MoreFunMachine.RangeLoop(7, 9, 1),
        }),
        T.MoreFunMachine.FastBody({}, {}, T.MoreFunMachine.Control(0, 5, true)),
        T.MoreFunMachine.ToTablePlan
    )

    local plan = machine:lower_luajit()
    assert(plan.kind == "GenericInstall")
    local out = plan:install().fn(nil)
    assert(#out == 5)
    assert(out[1] == 1)
    assert(out[5] == 5)
end

return {
    test_install_array_sum_plain = test_install_array_sum_plain,
    test_install_array_sum_maps_guards_control = test_install_array_sum_maps_guards_control,
    test_install_array_foldl_maps_guards_control = test_install_array_foldl_maps_guards_control,
    test_install_array_head_maps_guards_control = test_install_array_head_maps_guards_control,
    test_install_array_head_take_zero = test_install_array_head_take_zero,
    test_install_array_to_table_maps_guards_control = test_install_array_to_table_maps_guards_control,
    test_install_array_to_table_take_zero = test_install_array_to_table_take_zero,
    test_install_array_nth_maps_guards_control = test_install_array_nth_maps_guards_control,
    test_install_array_nth_out_of_bounds = test_install_array_nth_out_of_bounds,
    test_install_array_any_maps_guards_control = test_install_array_any_maps_guards_control,
    test_install_array_any_false = test_install_array_any_false,
    test_install_array_all_maps_guards_control = test_install_array_all_maps_guards_control,
    test_install_array_all_false = test_install_array_all_false,
    test_install_array_all_take_zero = test_install_array_all_take_zero,
    test_install_array_min_maps_guards_control = test_install_array_min_maps_guards_control,
    test_install_array_max_maps_guards_control = test_install_array_max_maps_guards_control,
    test_install_array_min_empty_after_take_zero = test_install_array_min_empty_after_take_zero,
    test_install_array_max_empty_when_no_values_pass = test_install_array_max_empty_when_no_values_pass,
    test_install_range_sum_plain = test_install_range_sum_plain,
    test_install_range_head_maps_guards_control = test_install_range_head_maps_guards_control,
    test_install_range_nth_maps_guards_control = test_install_range_nth_maps_guards_control,
    test_install_range_nth_descending = test_install_range_nth_descending,
    test_install_range_foldl_plain = test_install_range_foldl_plain,
    test_install_range_to_table_maps_guards_control = test_install_range_to_table_maps_guards_control,
    test_install_range_any_true = test_install_range_any_true,
    test_install_range_all_true = test_install_range_all_true,
    test_install_range_min_plain = test_install_range_min_plain,
    test_install_range_max_plain = test_install_range_max_plain,
    test_install_string_to_table_drop_take = test_install_string_to_table_drop_take,
    test_install_string_head_map_guard = test_install_string_head_map_guard,
    test_install_string_nth = test_install_string_nth,
    test_install_string_any_and_all = test_install_string_any_and_all,
    test_install_string_foldl_min_max = test_install_string_foldl_min_max,
    test_install_byte_string_sum_head_nth = test_install_byte_string_sum_head_nth,
    test_install_byte_string_to_table_any_min_max = test_install_byte_string_to_table_any_min_max,
    test_install_generic_array_generic_body_sum = test_install_generic_array_generic_body_sum,
    test_install_generic_raw_loop_to_table = test_install_generic_raw_loop_to_table,
    test_install_generic_chain_loop_global_take = test_install_generic_chain_loop_global_take,
}
