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

local function test_emit_lua_materializes_boundary_files()
    local machine, target_ctx = Fixture.new_tokenize_machine_and_target_ctx(T)
    local out = machine:emit_lua()

    assert(out ~= nil)
    assert(#out.files == 2)

    assert(out.files[1].path == "boundaries/target_text_spec.lua")
    assert(out.files[1].receiver_fqname == "TargetText.Spec")
    assert(out.files[1].verb == "tokenize")
    assert(not ffi.string(out.files[1].lua_source):match("lua_boundary_runtime"))
    assert(ffi.string(out.files[1].lua_source):match("local impl = U%.transition"))
    assert(ffi.string(out.files[1].lua_source):match("scan_number"))

    assert(out.files[2].path == "boundaries/target_token_spec.lua")
    assert(out.files[2].receiver_fqname == "TargetToken.Spec")
    assert(out.files[2].verb == "parse")
    assert(not ffi.string(out.files[2].lua_source):match("lua_boundary_runtime"))
    assert(ffi.string(out.files[2].lua_source):match("local rule_"))
    assert(ffi.string(out.files[2].lua_source):match("join_capture"))

    for i = 1, #out.files do
        local chunk = assert(loadstring(ffi.string(out.files[i].lua_source), "@" .. ffi.string(out.files[i].path)))
        local install = chunk()
        install(target_ctx, U, nil)
    end

    local token_spec = target_ctx.TargetText.Spec.tokenize({ text = "module Demo { Inner }" })
    local source_spec = target_ctx.TargetToken.Spec.parse(token_spec)
    assert(source_spec.root.kind == "Document")
    assert(source_spec.root.name == "Demo")
    assert(source_spec.root.inner == "Inner")
end

test_emit_lua_materializes_boundary_files()

print("frontend_machine_emit_lua_test.lua: ok")
