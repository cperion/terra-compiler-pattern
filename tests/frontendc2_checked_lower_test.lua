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

local function test_lower_direct_validate_structural_slice()
    local lowered = new_source():check():lower()
    assert(lowered.kind == "StructuralFrontier")

    assert(lowered.scan.byte_classes ~= nil)
    assert(lowered.scan.string_plans[1] == nil)
    assert(lowered.scan.number_plans[1].number_id == 1)

    assert(lowered.rules[1].kind.kind == "TerminalRuleKind")
    assert(lowered.rules[2].kind.kind == "SeqRuleKind")

    assert(lowered.lookahead_facets[1].first_set_id >= 1)
    assert(lowered.lookahead_facets[2].first_set_id >= 1)

    assert(lowered.exec_facets[1].kind == "StructuralTerminalExecFacet")
    assert(lowered.exec_facets[1].terminal.kind == "ExpectNumber")
    assert(lowered.exec_facets[1].terminal.number_id == 1)

    assert(lowered.exec_facets[2].kind == "StructuralSeqExecFacet")
    local steps = lowered.exec_facets[2].steps
    assert(#steps == 1)
    assert(steps[1].kind == "StructuralDelimitedGroup")
    assert(steps[1].open_byte == string.byte("["))
    assert(steps[1].close_byte == string.byte("]"))
    assert(#steps[1].inner_steps == 1)
    assert(steps[1].inner_steps[1].kind == "StructuralSeparatedListGroup")
    assert(steps[1].inner_steps[1].separator_byte == string.byte(","))
    assert(steps[1].inner_steps[1].item_set_id >= 1)
    assert(#steps[1].inner_steps[1].item_steps == 1)
    assert(steps[1].inner_steps[1].item_steps[1].kind == "StructuralCallRule")
    assert(S(steps[1].inner_steps[1].item_steps[1].header.name) == "item")

    assert(lowered.result_facets[1].result.kind == "ReturnEmpty")
    assert(lowered.result_facets[2].result.kind == "ReturnEmpty")

    assert(lowered.product_facets[1].builder.kind == "ValidateBuilderFacet")
    assert(lowered.package_facet.bindings[1].kind == "DirectBindingFacet")
    assert(S(lowered.package_facet.bindings[1].parse.receiver_fqname) == "TargetJsonText.Spec")
    assert(S(lowered.package_facet.bindings[1].output.output_ctor_fqname) == "TargetJsonValidate.Spec")
end

test_lower_direct_validate_structural_slice()

print("frontendc2_checked_lower_test.lua: ok")
