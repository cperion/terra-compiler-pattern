local U = require("unit")
local C = require("crochet")

return function(T, U, P)
    local benches = {}

    local function bench_seconds(rounds, warmup, fn)
        collectgarbage(); collectgarbage()
        for _ = 1, warmup do fn() end
        local t0 = os.clock()
        local out
        for _ = 1, rounds do out = fn() end
        return os.clock() - t0, out
    end

    function benches.bench_string_vs_byte_to_table()
        local text = string.rep("abcd", 2500)

        local string_unit = T.MoreFunLuaJIT.StringToTable(
            T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", text)),
            T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(1, 5000, true))
        ):install()

        local byte_unit = T.MoreFunLuaJIT.ByteStringToTable(
            T.MoreFunLuaJIT.ByteStringLoop(T.MoreFunRuntime.StringInput("s", text)),
            T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(1, 5000, true))
        ):install()

        local rounds = 300
        local warmup = 20
        local string_dt, string_out = bench_seconds(rounds, warmup, function()
            return string_unit.fn(nil)
        end)
        local byte_dt, byte_out = bench_seconds(rounds, warmup, function()
            return byte_unit.fn(nil)
        end)

        print(string.format("string_to_table  %.4f s  n=%d", string_dt, #string_out))
        print(string.format("byte_to_table    %.4f s  n=%d", byte_dt, #byte_out))

        return {
            string_seconds = string_dt,
            byte_seconds = byte_dt,
            string_count = #string_out,
            byte_count = #byte_out,
        }
    end

    function benches.bench_string_vs_byte_any()
        local text = string.rep("abcd", 2500)

        local string_unit = T.MoreFunLuaJIT.StringAny(
            T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", text)),
            T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false)),
            T.MoreFunLuaJIT.CallPred(T.MoreFunRuntime.CallRef("isd", function(x) return x == "d" end))
        ):install()

        local byte_unit = T.MoreFunLuaJIT.ByteStringAny(
            T.MoreFunLuaJIT.ByteStringLoop(T.MoreFunRuntime.StringInput("s", text)),
            T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false)),
            T.MoreFunLuaJIT.EqNumberPred(string.byte("d"))
        ):install()

        local rounds = 5000
        local warmup = 50
        local string_dt, string_out = bench_seconds(rounds, warmup, function()
            return string_unit.fn(nil)
        end)
        local byte_dt, byte_out = bench_seconds(rounds, warmup, function()
            return byte_unit.fn(nil)
        end)

        print(string.format("string_any       %.4f s  result=%s", string_dt, tostring(string_out)))
        print(string.format("byte_any         %.4f s  result=%s", byte_dt, tostring(byte_out)))

        return {
            string_seconds = string_dt,
            byte_seconds = byte_dt,
            string_result = string_out,
            byte_result = byte_out,
        }
    end

    function benches.bench_array_min_max()
        local xs = {}
        for i = 1, 100000 do
            xs[i] = i
        end
        local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
        local min_unit = T.MoreFunLuaJIT.ArrayMin(
            T.MoreFunLuaJIT.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", xs)),
            body
        ):install()
        local max_unit = T.MoreFunLuaJIT.ArrayMax(
            T.MoreFunLuaJIT.ArrayLoop(T.MoreFunRuntime.ArrayInput("xs", xs)),
            body
        ):install()

        local function hand_min()
            local acc = xs[1]
            for i = 2, #xs do
                local v = xs[i]
                if v < acc then acc = v end
            end
            return acc
        end

        local function hand_max()
            local acc = xs[1]
            for i = 2, #xs do
                local v = xs[i]
                if v > acc then acc = v end
            end
            return acc
        end

        local rounds = 200
        local warmup = 20
        local leaf_min_dt, leaf_min_out = bench_seconds(rounds, warmup, function() return min_unit.fn(nil) end)
        local hand_min_dt, hand_min_out = bench_seconds(rounds, warmup, hand_min)
        local leaf_max_dt, leaf_max_out = bench_seconds(rounds, warmup, function() return max_unit.fn(nil) end)
        local hand_max_dt, hand_max_out = bench_seconds(rounds, warmup, hand_max)

        print(string.format("leaf-array-min   %.4f s  result=%s", leaf_min_dt, tostring(leaf_min_out)))
        print(string.format("hand-array-min   %.4f s  result=%s", hand_min_dt, tostring(hand_min_out)))
        print(string.format("leaf-array-max   %.4f s  result=%s", leaf_max_dt, tostring(leaf_max_out)))
        print(string.format("hand-array-max   %.4f s  result=%s", hand_max_dt, tostring(hand_max_out)))

        return {
            leaf_min_seconds = leaf_min_dt,
            hand_min_seconds = hand_min_dt,
            leaf_max_seconds = leaf_max_dt,
            hand_max_seconds = hand_max_dt,
            min_result = leaf_min_out,
            max_result = leaf_max_out,
        }
    end

    function benches.bench_range_min_max()
        local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
        local min_unit = T.MoreFunLuaJIT.RangeMin(T.MoreFunLuaJIT.RangeLoop(1, 100000, 1), body):install()
        local max_unit = T.MoreFunLuaJIT.RangeMax(T.MoreFunLuaJIT.RangeLoop(1, 100000, 1), body):install()

        local function hand_min()
            local acc = 1
            for i = 2, 100000 do
                if i < acc then acc = i end
            end
            return acc
        end

        local function hand_max()
            local acc = 1
            for i = 2, 100000 do
                if i > acc then acc = i end
            end
            return acc
        end

        local rounds = 200
        local warmup = 20
        local leaf_min_dt, leaf_min_out = bench_seconds(rounds, warmup, function() return min_unit.fn(nil) end)
        local hand_min_dt, hand_min_out = bench_seconds(rounds, warmup, hand_min)
        local leaf_max_dt, leaf_max_out = bench_seconds(rounds, warmup, function() return max_unit.fn(nil) end)
        local hand_max_dt, hand_max_out = bench_seconds(rounds, warmup, hand_max)

        print(string.format("leaf-range-min   %.4f s  result=%s", leaf_min_dt, tostring(leaf_min_out)))
        print(string.format("hand-range-min   %.4f s  result=%s", hand_min_dt, tostring(hand_min_out)))
        print(string.format("leaf-range-max   %.4f s  result=%s", leaf_max_dt, tostring(leaf_max_out)))
        print(string.format("hand-range-max   %.4f s  result=%s", hand_max_dt, tostring(hand_max_out)))

        return {
            leaf_min_seconds = leaf_min_dt,
            hand_min_seconds = hand_min_dt,
            leaf_max_seconds = leaf_max_dt,
            hand_max_seconds = hand_max_dt,
            min_result = leaf_min_out,
            max_result = leaf_max_out,
        }
    end

    function benches.bench_string_vs_byte_min_max()
        local text = string.rep("dbca", 2500)
        local body = T.MoreFunLuaJIT.BodyPlan({}, {}, T.MoreFunLuaJIT.Control(0, 0, false))
        local string_min = T.MoreFunLuaJIT.StringMin(
            T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", text)),
            body
        ):install()
        local string_max = T.MoreFunLuaJIT.StringMax(
            T.MoreFunLuaJIT.StringLoop(T.MoreFunRuntime.StringInput("s", text)),
            body
        ):install()
        local byte_min = T.MoreFunLuaJIT.ByteStringMin(
            T.MoreFunLuaJIT.ByteStringLoop(T.MoreFunRuntime.StringInput("s", text)),
            body
        ):install()
        local byte_max = T.MoreFunLuaJIT.ByteStringMax(
            T.MoreFunLuaJIT.ByteStringLoop(T.MoreFunRuntime.StringInput("s", text)),
            body
        ):install()

        local rounds = 1000
        local warmup = 50
        local string_min_dt, string_min_out = bench_seconds(rounds, warmup, function() return string_min.fn(nil) end)
        local string_max_dt, string_max_out = bench_seconds(rounds, warmup, function() return string_max.fn(nil) end)
        local byte_min_dt, byte_min_out = bench_seconds(rounds, warmup, function() return byte_min.fn(nil) end)
        local byte_max_dt, byte_max_out = bench_seconds(rounds, warmup, function() return byte_max.fn(nil) end)

        print(string.format("string_min       %.4f s  result=%s", string_min_dt, tostring(string_min_out)))
        print(string.format("string_max       %.4f s  result=%s", string_max_dt, tostring(string_max_out)))
        print(string.format("byte_min         %.4f s  result=%s", byte_min_dt, tostring(byte_min_out)))
        print(string.format("byte_max         %.4f s  result=%s", byte_max_dt, tostring(byte_max_out)))

        return {
            string_min_seconds = string_min_dt,
            string_max_seconds = string_max_dt,
            byte_min_seconds = byte_min_dt,
            byte_max_seconds = byte_max_dt,
            string_min_result = string_min_out,
            string_max_result = string_max_out,
            byte_min_result = byte_min_out,
            byte_max_result = byte_max_out,
        }
    end

    function benches.bench_template_closure_vs_bytecode_array_sum()
        local xs = {}
        for i = 1, 100000 do
            xs[i] = i
        end

        local closure_artifact = C.compile(C.catalog({
            C.proto("array_sum_closure_artifact", { "_state" }, {
                C.capture("values", xs),
            }, C.body({
                C.stmt("local xs = values"),
                C.stmt("local acc = 0"),
                C.nest(C.clause("for i = 1, #xs do"), C.body({
                    C.stmt("acc = acc + xs[i]"),
                }), C.clause("end")),
                C.stmt("return acc"),
            })),
        }, "array_sum_closure_artifact", "closure"))

        local bytecode_artifact = C.compile(C.catalog({
            C.proto("array_sum_bytecode_artifact", { "_state" }, {
                C.capture("values", xs),
            }, C.body({
                C.stmt("local xs = values"),
                C.stmt("local acc = 0"),
                C.nest(C.clause("for i = 1, #xs do"), C.body({
                    C.stmt("acc = acc + xs[i]"),
                }), C.clause("end")),
                C.stmt("return acc"),
            })),
        }, "array_sum_bytecode_artifact", C.host_bytecode()))

        local rounds = 200
        local warmup = 20
        local closure_dt, closure_out = bench_seconds(rounds, warmup, function()
            return closure_artifact.entry(nil)
        end)
        local bytecode_dt, bytecode_out = bench_seconds(rounds, warmup, function()
            return bytecode_artifact.entry(nil)
        end)

        print(string.format("tmpl-closure-sum %.4f s  result=%s", closure_dt, tostring(closure_out)))
        print(string.format("tmpl-bytecode-sum %.4f s  result=%s", bytecode_dt, tostring(bytecode_out)))

        return {
            closure_seconds = closure_dt,
            bytecode_seconds = bytecode_dt,
            closure_result = closure_out,
            bytecode_result = bytecode_out,
        }
    end

    function benches.bench_template_closure_vs_bytecode_range_sum()
        local closure_artifact = C.compile(C.catalog({
            C.proto("range_sum_closure_artifact", { "_state" }, {
                C.capture("start", 1),
                C.capture("stop", 100000),
                C.capture("step", 1),
            }, C.body({
                C.stmt("if step == 0 then return 0 end"),
                C.stmt("local acc = 0"),
                C.nest(C.clause("for i = start, stop, step do"), C.body({
                    C.stmt("acc = acc + i"),
                }), C.clause("end")),
                C.stmt("return acc"),
            })),
        }, "range_sum_closure_artifact", "closure"))

        local bytecode_artifact = C.compile(C.catalog({
            C.proto("range_sum_bytecode_artifact", { "_state" }, {
                C.capture("start", 1),
                C.capture("stop", 100000),
                C.capture("step", 1),
            }, C.body({
                C.stmt("if step == 0 then return 0 end"),
                C.stmt("local acc = 0"),
                C.nest(C.clause("for i = start, stop, step do"), C.body({
                    C.stmt("acc = acc + i"),
                }), C.clause("end")),
                C.stmt("return acc"),
            })),
        }, "range_sum_bytecode_artifact", C.host_bytecode()))

        local rounds = 200
        local warmup = 20
        local closure_dt, closure_out = bench_seconds(rounds, warmup, function()
            return closure_artifact.entry(nil)
        end)
        local bytecode_dt, bytecode_out = bench_seconds(rounds, warmup, function()
            return bytecode_artifact.entry(nil)
        end)

        print(string.format("tmpl-closure-rsum %.4f s  result=%s", closure_dt, tostring(closure_out)))
        print(string.format("tmpl-bytecode-rsum %.4f s  result=%s", bytecode_dt, tostring(bytecode_out)))

        return {
            closure_seconds = closure_dt,
            bytecode_seconds = bytecode_dt,
            closure_result = closure_out,
            bytecode_result = bytecode_out,
        }
    end

    return benches
end
