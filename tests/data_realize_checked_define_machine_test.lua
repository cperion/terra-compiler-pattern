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

local function test_define_machine_maps_languages_inputs_and_contracts()
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
            T.DataRealizeSource.FileText("theme.toml"),
            T.DataRealizeSource.TomlLanguage,
            T.DataRealizeSource.AssignGlobalContract("THEME")
        ),
        T.DataRealizeSource.Binding(
            3,
            "events",
            T.DataRealizeSource.FileText("events.jsonl"),
            T.DataRealizeSource.JsonLinesLanguage,
            T.DataRealizeSource.PatchGlobalContract("EVENTS")
        ),
    }, T.DataRealizeSource.ClosureMode)

    local machine = source:check():define_machine()

    assert(machine ~= nil)
    assert(machine.package.kind == "ClosureMode")
    assert(#machine.bindings == 3)

    assert(machine.bindings[1].header.id == 1)
    assert(machine.bindings[1].header.name == "settings")
    assert(machine.bindings[1].input.kind == "InlineText")
    assert(machine.bindings[1].machine.kind == "JsonToTableMachine")
    assert(machine.bindings[1].contract.kind == "ReturnValueContract")

    assert(machine.bindings[2].header.id == 2)
    assert(machine.bindings[2].input.kind == "FileText")
    assert(machine.bindings[2].input.path == "theme.toml")
    assert(machine.bindings[2].machine.kind == "TomlToTableMachine")
    assert(machine.bindings[2].contract.kind == "AssignGlobalContract")
    assert(machine.bindings[2].contract.variable_name == "THEME")

    assert(machine.bindings[3].header.id == 3)
    assert(machine.bindings[3].machine.kind == "JsonLinesToTableMachine")
    assert(machine.bindings[3].contract.kind == "PatchGlobalContract")
    assert(machine.bindings[3].contract.variable_name == "EVENTS")
end

test_define_machine_maps_languages_inputs_and_contracts()

print("data_realize_checked_define_machine_test.lua: ok")
