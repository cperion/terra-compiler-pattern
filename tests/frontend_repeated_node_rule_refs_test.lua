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

local function build_repeated_names_source(base_source)
    return T.FrontendSource.Spec(
        base_source.target,
        base_source.lexer,
        T.FrontendSource.Parser(
            "entry",
            {
                T.FrontendSource.Rule(
                    "item",
                    T.FrontendSource.Capture("text", T.FrontendSource.TokenRef("Ident")),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.NameNode",
                        {
                            T.FrontendSource.FieldResult("text", T.FrontendSource.CaptureSource("text")),
                        }
                    )
                ),
                T.FrontendSource.Rule(
                    "entry",
                    T.FrontendSource.Seq({
                        T.FrontendSource.TokenRef("ModuleKw"),
                        T.FrontendSource.Capture("name", T.FrontendSource.TokenRef("Ident")),
                        T.FrontendSource.Capture("items", T.FrontendSource.Many(T.FrontendSource.RuleRef("item"))),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.DocumentNames",
                        {
                            T.FrontendSource.FieldResult("name", T.FrontendSource.CaptureSource("name")),
                            T.FrontendSource.FieldResult("items", T.FrontendSource.CaptureSource("items")),
                        }
                    )
                ),
            }
        )
    )
end

local function new_target_ctx()
    local _, target_ctx = Fixture.new_source_spec_and_target_ctx(T)
    target_ctx.TargetSource.NameNode = function(text)
        return { kind = "NameNode", text = text }
    end
    target_ctx.TargetSource.DocumentNames = function(name, items)
        return { kind = "DocumentNames", name = name, items = items }
    end
    return target_ctx
end

local function assert_document_names(root)
    assert(root.kind == "DocumentNames")
    assert(root.name == "Root")
    assert(#root.items == 3)
    assert(root.items[1].kind == "NameNode")
    assert(root.items[1].text == "Alpha")
    assert(root.items[2].text == "Beta")
    assert(root.items[3].text == "Gamma")
end

local function test_install_generated_supports_repeated_node_rule_refs()
    local base_source = select(1, Fixture.new_source_spec_and_target_ctx(T))
    local target_ctx = new_target_ctx()

    build_repeated_names_source(base_source):check():lower():define_machine():install_generated(target_ctx)

    local source_spec = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = "module Root Alpha Beta Gamma" })
    )
    assert_document_names(source_spec.root)
end

local function test_emit_lua_supports_repeated_node_rule_refs()
    local base_source = select(1, Fixture.new_source_spec_and_target_ctx(T))
    local target_ctx = new_target_ctx()

    local out = build_repeated_names_source(base_source):check():lower():define_machine():emit_lua()
    install_emitted(out, target_ctx)

    local source_spec = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = "module Root Alpha Beta Gamma" })
    )
    assert_document_names(source_spec.root)
end

test_install_generated_supports_repeated_node_rule_refs()
test_emit_lua_supports_repeated_node_rule_refs()

print("frontend_repeated_node_rule_refs_test.lua: ok")
