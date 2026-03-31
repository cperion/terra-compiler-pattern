#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")

local U = require("unit_core").new()
require("unit_schema").install(U)

local spec = U.load_inspect_spec("frontendc2")
local T = spec.ctx

local function S(v)
    if type(v) == "cdata" then return ffi.string(v) end
    return tostring(v)
end

local function N(v)
    return tonumber(v) or 0
end

local function new_source()
    return T.FrontendSource.Spec(
        T.FrontendSource.Frontend(
            T.FrontendSource.Grammar(
                T.FrontendSource.Utf8TextInput,
                T.FrontendSource.DropTrivia,
                {
                    T.FrontendSource.WhitespaceSkip,
                },
                {
                    T.FrontendSource.Token(1, "LBracket", T.FrontendSource.FixedToken("[", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(2, "RBracket", T.FrontendSource.FixedToken("]", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(3, "Comma", T.FrontendSource.FixedToken(",", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(4, "Number", T.FrontendSource.NumberToken(
                        T.FrontendSource.NumberFormat(false, true, true, true)
                    )),
                },
                {
                    T.FrontendSource.Rule(
                        1,
                        "item",
                        T.FrontendSource.NormalRule,
                        T.FrontendSource.TokenRef("Number"),
                        T.FrontendSource.ReturnEmpty
                    ),
                    T.FrontendSource.Rule(
                        2,
                        "entry",
                        T.FrontendSource.NormalRule,
                        T.FrontendSource.Delimited(
                            "LBracket",
                            T.FrontendSource.SeparatedList(
                                T.FrontendSource.RuleRef("item"),
                                "Comma",
                                T.FrontendSource.ZeroOrMore,
                                T.FrontendSource.NoTrailingSeparator
                            ),
                            "RBracket"
                        ),
                        T.FrontendSource.ReturnEmpty
                    ),
                }
            ),
            {},
            {
                T.FrontendSource.Product(
                    1,
                    "validate",
                    "entry",
                    T.FrontendSource.ValidateProduct,
                    T.FrontendSource.DropSourceRefs
                ),
            }
        ),
        T.FrontendSource.Package({
            T.FrontendSource.Binding(
                1,
                1,
                T.FrontendSource.DirectBinding(
                    T.FrontendSource.BoundaryBinding("TargetJsonText.Spec", "parse"),
                    T.FrontendSource.OutputBinding("TargetJsonValidate.Spec")
                )
            ),
        }),
        T.FrontendSource.FailFast
    )
end

local function test_define_machine_structural_validate_slice()
    local machine = new_source():check():lower():define_machine()

    assert(#machine.products == 1)
    local pm = machine.products[1]
    assert(pm.kind == "StructuralValidateMachine")
    assert(S(pm.product.name) == "validate")

    local parse = pm.parse
    assert(N(parse.param.entry_rule_id) == 2)
    assert(N(parse.gen.parses_numbers) == 1)
    assert(N(parse.gen.parses_strings) == 0)
    assert(N(parse.gen.parses_keywords) == 0)
    assert(N(parse.gen.parses_containers) == 1)
    assert(#parse.param.rules == 2)
    assert(#parse.param.terminals >= 1)
    assert(#parse.param.ops >= 1)
    assert(N(parse.param.rules[1].entry_pc) >= 1)
    assert(N(parse.param.rules[2].entry_pc) >= 1)
    assert(parse.param.ops[N(parse.param.rules[1].entry_pc)].kind == "ExpectTerminal")
    assert(parse.param.ops[N(parse.param.rules[2].entry_pc)].kind == "DelimitedGroup")
    assert(N(parse.state.control.max_depth) >= 2)

    assert(#machine.package_plan.bindings == 1)
    local binding = machine.package_plan.bindings[1]
    assert(binding.kind == "DirectBindingPlan")
    assert(S(binding.product.name) == "validate")
    assert(S(binding.parse.receiver_fqname) == "TargetJsonText.Spec")
    assert(S(binding.parse.verb) == "parse")
    assert(S(binding.output.output_ctor_fqname) == "TargetJsonValidate.Spec")
end

test_define_machine_structural_validate_slice()

print("frontendc2_lowered_define_machine_test.lua: ok")
