#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit_luajit")
local Runtime = require("frontendc2.structural_validate_runtime")
local Fixture = require("frontendc2.structural_validate_fixture")

local spec = U.load_inspect_spec("frontendc2")
local T = spec.ctx

local function test_low_level_scanners()
    do
        local next_pos = assert(Runtime.scan_number("12345", 5, 1, T.FrontendSource.NumberFormat(false, false, false, true)))
        assert(next_pos == 6)
    end

    do
        local next_pos = assert(Runtime.scan_number("-12.5e+7", 8, 1, T.FrontendSource.NumberFormat(true, true, true, false)))
        assert(next_pos == 9)
    end

    do
        local ok, err = Runtime.scan_number("01", 2, 1, T.FrontendSource.NumberFormat(false, false, false, false))
        assert(ok == nil)
        assert(tostring(err):match("leading zero"))
    end

    do
        local next_pos = assert(Runtime.scan_quoted_string([["hi\nthere"]], 11, 1, T.FrontendSource.StringFormat("\"", true, false)))
        assert(next_pos == 12)
    end

    do
        local ok, err = Runtime.scan_quoted_string([["bad]], 4, 1, T.FrontendSource.StringFormat("\"", true, false))
        assert(ok == nil)
        assert(tostring(err):match("unterminated string"))
    end
end

local function test_simple_structural_validate_machine()
    local machine_spec = Fixture.new_simple_machine(T)
    local parse_machine = machine_spec.products[1].parse
    local runtime_machine = Runtime.compile_validate_machine(U, parse_machine)

    assert(U.machine_run(runtime_machine, nil, "[]") == true)
    assert(U.machine_run(runtime_machine, nil, "[1, 2, 3]") == true)

    local ok1, err1 = U.machine_run(runtime_machine, nil, "[,]")
    assert(ok1 == false)
    assert(type(err1) == "string")

    local ok2 = U.machine_run(runtime_machine, nil, { text = "[10,20]" })
    assert(ok2 == true)
end

local function test_json_validate_machine()
    local machine_spec = Fixture.new_json_validate_machine(T)
    local parse_machine = machine_spec.products[1].parse
    local runtime_machine = Runtime.compile_validate_machine(U, parse_machine)

    local text = [[
        {
          "name": "terra",
          "ok": true,
          "count": 12,
          "items": [1, 2, 3, null, false, {"nested": []}]
        }
    ]]
    local ok = U.machine_run(runtime_machine, nil, text)
    assert(ok == true)

    local ok2, err2 = U.machine_run(runtime_machine, nil, [[{"x": [1, 2, }]])
    assert(ok2 == false)
    assert(type(err2) == "string")
end

test_low_level_scanners()
test_simple_structural_validate_machine()
test_json_validate_machine()

print("frontendc2_structural_validate_runtime_test.lua: ok")
