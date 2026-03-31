#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit_core").new()
require("unit_schema").install(U)

local spec = U.load_inspect_spec("frontendc")
local T = spec.ctx
local Fixture = require("frontendc.frontend_machine_fixture")

local function test_build_expr_constructs_value_from_multi_value_seq()
    local base_source, target_ctx = Fixture.new_source_spec_and_target_ctx(T)

    target_ctx.TargetSource.Pair = function(left, right)
        return { kind = "Pair", left = left, right = right }
    end
    target_ctx.TargetSource.DocumentPair = function(name, inner)
        return { kind = "DocumentPair", name = name, inner = inner }
    end

    local source = T.FrontendSource.Spec(
        base_source.target,
        base_source.lexer,
        T.FrontendSource.Parser(
            "entry",
            {
                T.FrontendSource.Rule(
                    "pair",
                    T.FrontendSource.Capture(
                        "pair_value",
                        T.FrontendSource.Build(
                            T.FrontendSource.Seq({
                                T.FrontendSource.Capture("left", T.FrontendSource.TokenRef("Ident")),
                                T.FrontendSource.TokenRef("LBrace"),
                                T.FrontendSource.Capture("right", T.FrontendSource.TokenRef("Ident")),
                                T.FrontendSource.TokenRef("RBrace"),
                            }),
                            T.FrontendSource.ReturnCtor(
                                "TargetSource.Pair",
                                {
                                    T.FrontendSource.FieldResult("left", T.FrontendSource.CaptureSource("left")),
                                    T.FrontendSource.FieldResult("right", T.FrontendSource.CaptureSource("right")),
                                }
                            )
                        )
                    ),
                    T.FrontendSource.ReturnCapture("pair_value")
                ),
                T.FrontendSource.Rule(
                    "entry",
                    T.FrontendSource.Seq({
                        T.FrontendSource.TokenRef("ModuleKw"),
                        T.FrontendSource.Capture("name", T.FrontendSource.TokenRef("Ident")),
                        T.FrontendSource.Capture("inner", T.FrontendSource.RuleRef("pair")),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.DocumentPair",
                        {
                            T.FrontendSource.FieldResult("name", T.FrontendSource.CaptureSource("name")),
                            T.FrontendSource.FieldResult("inner", T.FrontendSource.CaptureSource("inner")),
                        }
                    )
                ),
            }
        )
    )

    local machine = source:check():lower():define_machine()
    machine:install_generated(target_ctx)

    local token_spec = target_ctx.TargetText.Spec.tokenize({ text = "module Demo Left { Right }" })
    local source_spec = target_ctx.TargetToken.Spec.parse(token_spec)
    assert(source_spec.root.kind == "DocumentPair")
    assert(source_spec.root.name == "Demo")
    assert(source_spec.root.inner.kind == "Pair")
    assert(source_spec.root.inner.left == "Left")
    assert(source_spec.root.inner.right == "Right")
end

test_build_expr_constructs_value_from_multi_value_seq()

print("frontend_build_expr_test.lua: ok")
