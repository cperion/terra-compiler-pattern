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

local function test_checked_lower_builds_machine_feeding_phase()
    local source, target_ctx = Fixture.new_source_spec_and_target_ctx(T)
    local lowered = source:check():lower()

    assert(lowered ~= nil)
    assert(lowered.tokenize.eof_header.token_id == 5)
    assert(#lowered.tokenize.fixed_dispatches == 3)
    assert(#lowered.tokenize.ident_dispatches == 1)
    assert(#lowered.parse.result_ctors == 1)
    assert(#lowered.parse.rules == 1)
    assert(lowered.parse.rules[1].kind.kind == "SeqRuleKind")

    local machine = lowered:define_machine()
    machine:install_generated(target_ctx)
    local token_spec = target_ctx.TargetText.Spec.tokenize({ text = "module Demo { Inner }" })
    local source_spec = target_ctx.TargetToken.Spec.parse(token_spec)
    assert(source_spec.root.name == "Demo")
    assert(source_spec.root.inner == "Inner")
end

test_checked_lower_builds_machine_feeding_phase()

print("frontend_checked_lower_test.lua: ok")
