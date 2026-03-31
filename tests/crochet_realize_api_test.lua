#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local C = require("crochet")

local function test_realize_compile_bytecode_catalog()
    local catalog = C.catalog({
        C.proto("entry", { "x" }, {
            C.capture("inc", 10),
        }, C.body({
            C.stmt(
                C.literal("return "),
                C.param("x"),
                C.literal(" + "),
                C.capture_ref("inc")
            ),
        })),
        C.proto("triple", { "x" }, {}, C.body({
            C.stmt("return x * 3"),
        })),
    }, "entry", C.host_bytecode())

    local artifact = C.compile(catalog)

    assert(artifact.mode == "bytecode")
    assert(artifact.entry(5) == 15)
    assert(artifact:realize("triple")(7) == 21)
    assert(artifact.protos.entry.bytecode ~= nil)
    assert(artifact.protos.triple.bytecode ~= nil)
end

local function test_realize_structural_nest()
    local catalog = C.catalog({
        C.proto("sum_to_n", { "n" }, {}, C.body({
            C.stmt("local acc = 0"),
            C.nest(
                C.clause("for i = 1, ", C.param("n"), " do"),
                C.body({
                    C.stmt("acc = acc + i"),
                }),
                C.clause("end")
            ),
            C.stmt("return acc"),
        })),
    }, "sum_to_n", C.host_source())

    local artifact = C.compile(catalog)
    assert(artifact.mode == "source")
    assert(artifact.entry(5) == 15)
end

local function test_host_selectors_have_distinct_contracts()
    assert(C.host_source().kind == "LuaSourceHost")
    assert(C.host_bytecode().kind == "LuaBytecodeHost")
    assert(C.host_closure().kind == "LuaClosureHost")
    assert(C.host_closure().mode.kind == "DirectClosureMode")
    assert(C.host_closure("bundle").mode.kind == "ClosureBundleMode")
end

local function test_realize_direct_closure_host()
    local catalog = C.catalog({
        C.closure_proto("sum_plus_inc", { "n" }, {
            C.capture("inc", 2),
        }, C.closure_body({
            C.let("acc", C.const("zero", 0)),
            C.for_range("i", C.const("one", 1), C.param_expr("n"), C.const("one", 1), C.closure_body({
                C.set("acc", C.binary("+", C.local_expr("acc"), C.local_expr("i"))),
            })),
            C.ret(C.binary("+", C.local_expr("acc"), C.capture_expr("inc"))),
        })),
    }, "sum_plus_inc", C.host_closure())

    local plan = C.lower(C.check(catalog))
    assert(plan.protos[1].kind == "ClosureProtoPlan")
    assert(plan.protos[1].shape_key:match("closure|sum_plus_inc|"))

    local artifact = C.install(C.prepare(plan))
    assert(artifact.mode == "closure")
    assert(artifact.entry(5) == 17)
end

test_host_selectors_have_distinct_contracts()
test_realize_compile_bytecode_catalog()
test_realize_structural_nest()
test_realize_direct_closure_host()

print("crochet_realize_api_test.lua: ok")
