local M = {}

local function new_simple_source(T)
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

local function new_json_validate_source(T)
    return T.FrontendSource.Spec(
        T.FrontendSource.Frontend(
            T.FrontendSource.Grammar(
                T.FrontendSource.Utf8TextInput,
                T.FrontendSource.DropTrivia,
                {
                    T.FrontendSource.WhitespaceSkip,
                },
                {
                    T.FrontendSource.Token(1, "LBrace", T.FrontendSource.FixedToken("{", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(2, "RBrace", T.FrontendSource.FixedToken("}", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(3, "LBracket", T.FrontendSource.FixedToken("[", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(4, "RBracket", T.FrontendSource.FixedToken("]", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(5, "Colon", T.FrontendSource.FixedToken(":", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(6, "Comma", T.FrontendSource.FixedToken(",", T.FrontendSource.NoWordBoundary)),
                    T.FrontendSource.Token(7, "TrueKw", T.FrontendSource.FixedToken("true", T.FrontendSource.RequiresWordBoundary)),
                    T.FrontendSource.Token(8, "FalseKw", T.FrontendSource.FixedToken("false", T.FrontendSource.RequiresWordBoundary)),
                    T.FrontendSource.Token(9, "NullKw", T.FrontendSource.FixedToken("null", T.FrontendSource.RequiresWordBoundary)),
                    T.FrontendSource.Token(10, "String", T.FrontendSource.QuotedStringToken(
                        T.FrontendSource.StringFormat("\"", true, false)
                    )),
                    T.FrontendSource.Token(11, "Number", T.FrontendSource.NumberToken(
                        T.FrontendSource.NumberFormat(true, true, true, false)
                    )),
                },
                {
                    T.FrontendSource.Rule(
                        1,
                        "value",
                        T.FrontendSource.NormalRule,
                        T.FrontendSource.Choice({
                            T.FrontendSource.RuleRef("object"),
                            T.FrontendSource.RuleRef("array"),
                            T.FrontendSource.TokenRef("String"),
                            T.FrontendSource.TokenRef("Number"),
                            T.FrontendSource.TokenRef("TrueKw"),
                            T.FrontendSource.TokenRef("FalseKw"),
                            T.FrontendSource.TokenRef("NullKw"),
                        }),
                        T.FrontendSource.ReturnEmpty
                    ),
                    T.FrontendSource.Rule(
                        2,
                        "object",
                        T.FrontendSource.NormalRule,
                        T.FrontendSource.Delimited(
                            "LBrace",
                            T.FrontendSource.SeparatedList(
                                T.FrontendSource.RuleRef("pair"),
                                "Comma",
                                T.FrontendSource.ZeroOrMore,
                                T.FrontendSource.NoTrailingSeparator
                            ),
                            "RBrace"
                        ),
                        T.FrontendSource.ReturnEmpty
                    ),
                    T.FrontendSource.Rule(
                        3,
                        "pair",
                        T.FrontendSource.NormalRule,
                        T.FrontendSource.Seq({
                            T.FrontendSource.TokenRef("String"),
                            T.FrontendSource.TokenRef("Colon"),
                            T.FrontendSource.RuleRef("value"),
                        }),
                        T.FrontendSource.ReturnEmpty
                    ),
                    T.FrontendSource.Rule(
                        4,
                        "array",
                        T.FrontendSource.NormalRule,
                        T.FrontendSource.Delimited(
                            "LBracket",
                            T.FrontendSource.SeparatedList(
                                T.FrontendSource.RuleRef("value"),
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
                    "json_validate",
                    "value",
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

function M.new_simple_machine(T)
    return new_simple_source(T):check():lower():define_machine()
end

function M.new_json_validate_machine(T)
    return new_json_validate_source(T):check():lower():define_machine()
end

return M
