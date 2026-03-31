#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")

local U = require("unit_core").new()
require("unit_schema").install(U)

local spec = U.load_inspect_spec("frontendc")
local T = spec.ctx
local Fixture = require("frontendc.frontend_machine_fixture")

local function install_emitted(out, target_ctx)
    for i = 1, #out.files do
        local chunk = assert(loadstring(ffi.string(out.files[i].lua_source), "@" .. ffi.string(out.files[i].path)))
        chunk()(target_ctx, U, nil)
    end
end

local function build_repeated_pairs_source(base_source)
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
                        T.FrontendSource.Capture(
                            "pairs",
                            T.FrontendSource.Many(
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
                            )
                        ),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.DocumentPairs",
                        {
                            T.FrontendSource.FieldResult("name", T.FrontendSource.CaptureSource("name")),
                            T.FrontendSource.FieldResult("pairs", T.FrontendSource.CaptureSource("pairs")),
                        }
                    )
                ),
            }
        )
    )
end

local function new_target_ctx()
    local _, target_ctx = Fixture.new_source_spec_and_target_ctx(T)
    target_ctx.TargetSource.Pair = function(left, right)
        return { kind = "Pair", left = left, right = right }
    end
    target_ctx.TargetSource.DocumentPairs = function(name, pairs)
        return { kind = "DocumentPairs", name = name, pairs = pairs }
    end
    return target_ctx
end

local function assert_document_pairs(root)
    assert(root.kind == "DocumentPairs")
    assert(root.name == "Root")
    assert(#root.pairs == 2)
    assert(root.pairs[1].kind == "Pair")
    assert(root.pairs[1].left == "Alpha")
    assert(root.pairs[1].right == "Beta")
    assert(root.pairs[2].left == "Gamma")
    assert(root.pairs[2].right == "Delta")
end

local function test_install_generated_supports_repeated_build_nodes()
    local base_source = select(1, Fixture.new_source_spec_and_target_ctx(T))
    local target_ctx = new_target_ctx()

    build_repeated_pairs_source(base_source):check():lower():define_machine():install_generated(target_ctx)

    local source_spec = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = "module Root Alpha { Beta } Gamma { Delta }" })
    )
    assert_document_pairs(source_spec.root)
end

local function test_emit_lua_supports_repeated_build_nodes()
    local base_source = select(1, Fixture.new_source_spec_and_target_ctx(T))
    local target_ctx = new_target_ctx()

    local out = build_repeated_pairs_source(base_source):check():lower():define_machine():emit_lua()
    install_emitted(out, target_ctx)

    local source_spec = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = "module Root Alpha { Beta } Gamma { Delta }" })
    )
    assert_document_pairs(source_spec.root)
end

test_install_generated_supports_repeated_build_nodes()
test_emit_lua_supports_repeated_build_nodes()

print("frontend_repeated_build_nodes_test.lua: ok")
