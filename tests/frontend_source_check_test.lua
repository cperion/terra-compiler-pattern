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

local function test_source_check_builds_checked_grammar()
    local source = Fixture.new_source_spec_and_target_ctx(T)
    local checked = source:check()

    assert(checked ~= nil)
    assert(checked.parser.entry_rule ~= nil)
    assert(#checked.lexer.tokens == 4)
    assert(checked.lexer.tokens[4].header.payload_shape.kind == "StringTokenPayload")
    assert(#checked.parser.rules == 1)
    assert(checked.parser.rules[1].expr.kind == "Seq")
    assert(checked.parser.rules[1].result.kind == "ReturnCtor")
    assert(checked.parser.rules[1].first_set.token_ids[1] == 1)
    assert(checked.parser.rules[1].nullable == false or checked.parser.rules[1].nullable == 0)
end

test_source_check_builds_checked_grammar()

print("frontend_source_check_test.lua: ok")
