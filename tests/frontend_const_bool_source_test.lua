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

local function build_flags_source(base_source)
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
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.Flags",
                        {
                            T.FrontendSource.FieldResult("name", T.FrontendSource.CaptureSource("name")),
                            T.FrontendSource.FieldResult("enabled", T.FrontendSource.ConstBoolSource(true)),
                            T.FrontendSource.FieldResult("disabled", T.FrontendSource.ConstBoolSource(false)),
                        }
                    )
                ),
            }
        )
    )
end

local function new_target_ctx()
    local _, target_ctx = Fixture.new_source_spec_and_target_ctx(T)
    target_ctx.TargetSource.Flags = function(name, enabled, disabled)
        return {
            kind = "Flags",
            name = name,
            enabled = enabled,
            disabled = disabled,
        }
    end
    return target_ctx
end

local function test_install_generated_supports_const_bool_source()
    local base_source = select(1, Fixture.new_source_spec_and_target_ctx(T))
    local target_ctx = new_target_ctx()

    build_flags_source(base_source):check():lower():define_machine():install_generated(target_ctx)

    local source_spec = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = "module Demo" })
    )
    assert(source_spec.root.kind == "Flags")
    assert(source_spec.root.name == "Demo")
    assert(source_spec.root.enabled == true)
    assert(source_spec.root.disabled == false)
end

local function test_emit_lua_supports_const_bool_source()
    local base_source = select(1, Fixture.new_source_spec_and_target_ctx(T))
    local target_ctx = new_target_ctx()

    local out = build_flags_source(base_source):check():lower():define_machine():emit_lua()
    install_emitted(out, target_ctx)

    local source_spec = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = "module Demo" })
    )
    assert(source_spec.root.kind == "Flags")
    assert(source_spec.root.name == "Demo")
    assert(source_spec.root.enabled == true)
    assert(source_spec.root.disabled == false)
end

test_install_generated_supports_const_bool_source()
test_emit_lua_supports_const_bool_source()

print("frontend_const_bool_source_test.lua: ok")
