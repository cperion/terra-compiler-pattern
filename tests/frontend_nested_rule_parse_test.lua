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

local function test_nested_rule_results_flow_through_rule_refs()
    local base_source, target_ctx = Fixture.new_source_spec_and_target_ctx(T)

    target_ctx.TargetSource.NameLeaf = function(text)
        return { kind = "NameLeaf", text = text }
    end
    target_ctx.TargetSource.DocumentWithNodes = function(name, inner)
        return { kind = "DocumentWithNodes", name = name, inner = inner }
    end

    local source = T.FrontendSource.Spec(
        base_source.target,
        base_source.lexer,
        T.FrontendSource.Parser(
            "entry",
            {
                T.FrontendSource.Rule(
                    "name",
                    T.FrontendSource.Capture("text", T.FrontendSource.TokenRef("Ident")),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.NameLeaf",
                        {
                            T.FrontendSource.FieldResult("text", T.FrontendSource.CaptureSource("text")),
                        }
                    )
                ),
                T.FrontendSource.Rule(
                    "entry",
                    T.FrontendSource.Seq({
                        T.FrontendSource.TokenRef("ModuleKw"),
                        T.FrontendSource.Capture("name", T.FrontendSource.RuleRef("name")),
                        T.FrontendSource.TokenRef("LBrace"),
                        T.FrontendSource.Capture("inner", T.FrontendSource.RuleRef("name")),
                        T.FrontendSource.TokenRef("RBrace"),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.DocumentWithNodes",
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

    assert(source_spec.root.kind == "DocumentWithNodes")
    assert(source_spec.root.name.kind == "NameLeaf")
    assert(source_spec.root.name.text == "Demo")
    assert(source_spec.root.inner.kind == "NameLeaf")
    assert(source_spec.root.inner.text == "Inner")
end

test_nested_rule_results_flow_through_rule_refs()

print("frontend_nested_rule_parse_test.lua: ok")
