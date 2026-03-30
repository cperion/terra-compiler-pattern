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

local function test_install_generated_attaches_runtime_closures()
    local machine, target_ctx = Fixture.new_tokenize_machine_and_target_ctx(T)

    local installed = machine:install_generated(target_ctx)
    assert(installed == target_ctx)
    assert(type(target_ctx.TargetText.Spec.tokenize) == "function")
    assert(type(target_ctx.TargetToken.Spec.parse) == "function")

    local token_spec = target_ctx.TargetText.Spec.tokenize({ text = "# c\nmodule Demo { Inner }" })
    assert(token_spec.kind == "TokenSpec")
    assert(#token_spec.items == 6)
    assert(token_spec.items[1].token_id == 1)
    assert(token_spec.items[1].span.start_byte == 5)
    assert(token_spec.items[2].token_id == 4)
    assert(token_spec.items[2].text == "Demo")
    assert(token_spec.items[3].token_id == 2)
    assert(token_spec.items[4].token_id == 4)
    assert(token_spec.items[4].text == "Inner")
    assert(token_spec.items[5].token_id == 3)
    assert(token_spec.items[6].token_id == 5)

    local token_spec2 = target_ctx.TargetText.Spec.tokenize({ text = "modulex" })
    assert(#token_spec2.items == 2)
    assert(token_spec2.items[1].token_id == 4)
    assert(token_spec2.items[1].text == "modulex")

    local ok1, err1 = pcall(function()
        return target_ctx.TargetText.Spec.tokenize({ text = "@" })
    end)
    assert(not ok1)
    assert(tostring(err1):match("generated tokenize machine invalid token"))

    local source_spec = target_ctx.TargetToken.Spec.parse(token_spec)
    assert(source_spec.kind == "SourceSpec")
    assert(source_spec.root.kind == "Document")
    assert(source_spec.root.name == "Demo")
    assert(source_spec.root.inner == "Inner")

    local ok2, err2 = pcall(function()
        return target_ctx.TargetToken.Spec.parse({ tokens = {} })
    end)
    assert(not ok2)
    assert(tostring(err2):match("missing entry rule") or tostring(err2):match("expected token") or tostring(err2):match("unexpected eof") or tostring(err2):match("expected eof"))
end

test_install_generated_attaches_runtime_closures()

print("frontend_machine_install_generated_test.lua: ok")
