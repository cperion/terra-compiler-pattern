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

local function test_define_machine_builds_runtime_shape()
    local lowered, target_ctx = Fixture.new_lowered_spec_and_target_ctx(T)
    local machine = lowered:define_machine()

    assert(machine.tokenize.header.receiver_path.parts[1] == "TargetText")
    assert(machine.tokenize.header.receiver_path.parts[2] == "Spec")
    assert(machine.tokenize.header.verb == "tokenize")
    assert(machine.parse.header.receiver_path.parts[1] == "TargetToken")
    assert(machine.parse.header.verb == "parse")
    assert(#machine.tokenize.machine.fixed_dispatches == 3)
    assert(#machine.tokenize.machine.ident_dispatches == 1)
    assert(machine.tokenize.machine.eof_header.token_id == 5)
    assert(#machine.parse.result_ctors == 1)
    assert(#machine.parse.machine.rules == 1)
    assert(machine.parse.machine.rules[1].kind.kind == "SeqRuleKind")
    assert(machine.parse.machine.rules[1].result.kind == "ReturnCtor")

    machine:install_generated(target_ctx)
    local token_spec = target_ctx.TargetText.Spec.tokenize({ text = "module Demo { Inner }" })
    local source_spec = target_ctx.TargetToken.Spec.parse(token_spec)
    assert(source_spec.root.kind == "Document")
    assert(source_spec.root.name == "Demo")
    assert(source_spec.root.inner == "Inner")
end

test_define_machine_builds_runtime_shape()

print("frontend_lowered_define_machine_test.lua: ok")
