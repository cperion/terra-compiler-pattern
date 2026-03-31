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

local function test_check_direct_validate_structural_slice()
    local source = T.FrontendSource.Spec(
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

    local checked = source:check()
    assert(checked.frontend.grammar.tokens[4].header.payload_shape.kind == "NumberPayload")
    assert(S(checked.frontend.products[1].entry_rule.name) == "entry")
    assert(S(checked.package.bindings[1].product.name) == "validate")

    local entry = checked.frontend.grammar.rules[2]
    assert(S(entry.header.name) == "entry")
    assert(entry.expr.kind == "Delimited")
    assert(entry.expr.inner.kind == "SeparatedList")
    assert(entry.first_set.token_ids[1] == 1)
    assert((tonumber(entry.nullable) or 0) == 0)
    assert(entry.value_shape.kind == "UnitValue")
end

test_check_direct_validate_structural_slice()

print("frontendc2_source_check_test.lua: ok")
