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

local function build_summary_source(T, base_source)
    return T.FrontendSource.Spec(
        base_source.target,
        base_source.lexer,
        T.FrontendSource.Parser(
            "entry",
            {
                T.FrontendSource.Rule(
                    "entry",
                    T.FrontendSource.Seq({
                        T.FrontendSource.TokenRef("ModuleKw"),
                        T.FrontendSource.Capture("name", T.FrontendSource.TokenRef("Ident")),
                        T.FrontendSource.Capture("maybe_inner", T.FrontendSource.Optional(T.FrontendSource.TokenRef("Ident"))),
                        T.FrontendSource.Capture("more", T.FrontendSource.Many(T.FrontendSource.TokenRef("Ident"))),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.Summary",
                        {
                            T.FrontendSource.FieldResult("name", T.FrontendSource.CaptureSource("name")),
                            T.FrontendSource.FieldResult("has_inner", T.FrontendSource.PresentSource("maybe_inner")),
                            T.FrontendSource.FieldResult("more_csv", T.FrontendSource.JoinedListSource("more", ",")),
                        }
                    )
                ),
            }
        )
    )
end

local function test_install_generated_supports_present_and_joined_result_sources()
    local base_source, target_ctx = Fixture.new_source_spec_and_target_ctx(T)

    target_ctx.TargetSource.Summary = function(name, has_inner, more_csv)
        return {
            kind = "Summary",
            name = name,
            has_inner = has_inner,
            more_csv = more_csv,
        }
    end

    local machine = build_summary_source(T, base_source):check():lower():define_machine()
    machine:install_generated(target_ctx)

    local source_spec1 = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = "module Demo" })
    )
    assert(source_spec1.root.kind == "Summary")
    assert(source_spec1.root.name == "Demo")
    assert(source_spec1.root.has_inner == false)
    assert(source_spec1.root.more_csv == "")

    local source_spec2 = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = "module Demo Inner Tail More" })
    )
    assert(source_spec2.root.kind == "Summary")
    assert(source_spec2.root.name == "Demo")
    assert(source_spec2.root.has_inner == true)
    assert(source_spec2.root.more_csv == "Tail,More")
end

test_install_generated_supports_present_and_joined_result_sources()

print("frontend_result_sources_test.lua: ok")
