#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit_core").new()
require("unit_schema").install(U)

local spec = U.load_inspect_spec("data-realize")
local T = spec.ctx

local function test_source_check_builds_checked_bindings()
    local source = T.DataRealizeSource.Spec({
        T.DataRealizeSource.Binding(
            1,
            "settings",
            T.DataRealizeSource.InlineText('{"volume": 0.8}'),
            T.DataRealizeSource.JsonLanguage,
            T.DataRealizeSource.ReturnValueContract
        ),
        T.DataRealizeSource.Binding(
            2,
            "theme",
            T.DataRealizeSource.FileText("theme.json"),
            T.DataRealizeSource.JsonLanguage,
            T.DataRealizeSource.AssignGlobalContract("THEME")
        ),
    }, T.DataRealizeSource.BytecodeMode)

    local checked = source:check()

    assert(checked ~= nil)
    assert(#checked.bindings == 2)
    assert(checked.package.kind == "BytecodeMode")

    assert(checked.bindings[1].header.id == 1)
    assert(checked.bindings[1].header.name == "settings")
    assert(checked.bindings[1].input.kind == "InlineText")
    assert(checked.bindings[1].language.kind == "JsonLanguage")
    assert(checked.bindings[1].contract.kind == "ReturnValueContract")

    assert(checked.bindings[2].header.id == 2)
    assert(checked.bindings[2].header.name == "theme")
    assert(checked.bindings[2].input.kind == "FileText")
    assert(checked.bindings[2].input.path == "theme.json")
    assert(checked.bindings[2].contract.kind == "AssignGlobalContract")
    assert(checked.bindings[2].contract.variable_name == "THEME")
end

local function test_source_check_rejects_duplicate_binding_names()
    local source = T.DataRealizeSource.Spec({
        T.DataRealizeSource.Binding(
            1,
            "settings",
            T.DataRealizeSource.InlineText("{}"),
            T.DataRealizeSource.JsonLanguage,
            T.DataRealizeSource.ReturnValueContract
        ),
        T.DataRealizeSource.Binding(
            2,
            "settings",
            T.DataRealizeSource.InlineText("{}"),
            T.DataRealizeSource.JsonLanguage,
            T.DataRealizeSource.ReturnValueContract
        ),
    }, T.DataRealizeSource.SourceMode)

    local ok, err = pcall(function()
        source:check()
    end)

    assert(ok == false)
    assert(tostring(err):match("duplicate binding name"))
end

test_source_check_builds_checked_bindings()
test_source_check_rejects_duplicate_binding_names()

print("data_realize_source_check_test.lua: ok")
