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

local function test_captured_seq_and_choice_lowering()
    local base_source, target_ctx = Fixture.new_source_spec_and_target_ctx(T)

    local source = T.FrontendSource.Spec(
        base_source.target,
        base_source.lexer,
        T.FrontendSource.Parser(
            "entry",
            {
                T.FrontendSource.Rule(
                    "name",
                    T.FrontendSource.Capture("text", T.FrontendSource.TokenRef("Ident")),
                    T.FrontendSource.ReturnCapture("text")
                ),
                T.FrontendSource.Rule(
                    "entry",
                    T.FrontendSource.Seq({
                        T.FrontendSource.TokenRef("ModuleKw"),
                        T.FrontendSource.Capture(
                            "name",
                            T.FrontendSource.Seq({
                                T.FrontendSource.Choice({
                                    T.FrontendSource.RuleRef("name"),
                                    T.FrontendSource.TokenRef("Ident"),
                                }),
                            })
                        ),
                        T.FrontendSource.TokenRef("LBrace"),
                        T.FrontendSource.Capture("inner", T.FrontendSource.RuleRef("name")),
                        T.FrontendSource.TokenRef("RBrace"),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.Document",
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

    local token_spec = target_ctx.TargetText.Spec.tokenize({ text = "module Demo { Inner }" })
    local source_spec = target_ctx.TargetToken.Spec.parse(token_spec)
    assert(source_spec.root.name == "Demo")
    assert(source_spec.root.inner == "Inner")
end

test_captured_seq_and_choice_lowering()

print("frontend_captured_seq_choice_test.lua: ok")
