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
local JsonExample = require("frontendc.examples.json_frontend")

local function install_emitted(out, target_ctx)
    for i = 1, #out.files do
        local chunk = assert(loadstring(ffi.string(out.files[i].lua_source), "@" .. ffi.string(out.files[i].path)))
        chunk()(target_ctx, U, nil)
    end
end

local function pair_value(obj, key)
    for i = 1, #obj.entries do
        local pair = obj.entries[i]
        if pair.key == key then return pair.value end
    end
    error("missing key " .. tostring(key), 2)
end

local function assert_json_tree(root)
    assert(root.kind == "JsonObject")
    assert(pair_value(root, "name").kind == "JsonString")
    assert(pair_value(root, "name").value == "Alice")
    assert(pair_value(root, "age").kind == "JsonNumber")
    assert(pair_value(root, "age").text == "-12.5e2")
    assert(pair_value(root, "age").value == -1250)
    assert(pair_value(root, "active").kind == "JsonBool")
    assert(pair_value(root, "active").value == true)
    assert(pair_value(root, "none").kind == "JsonNull")

    local items = pair_value(root, "items")
    assert(items.kind == "JsonArray")
    assert(#items.items == 3)
    assert(items.items[1].value == 1)
    assert(items.items[2].value == 2)
    assert(items.items[3].value == 3)

    local meta = pair_value(root, "meta")
    assert(meta.kind == "JsonObject")
    assert(pair_value(meta, "note").value == "hi\nthere")

    local empty_obj = pair_value(root, "emptyObj")
    assert(empty_obj.kind == "JsonObject")
    assert(#empty_obj.entries == 0)

    local empty_arr = pair_value(root, "emptyArr")
    assert(empty_arr.kind == "JsonArray")
    assert(#empty_arr.items == 0)
end

local SAMPLE = '{"name":"Alice","age":-12.5e2,"active":true,"items":[1,2,3],"meta":{"note":"hi\\nthere"},"none":null,"emptyObj":{},"emptyArr":[]}'

local function test_json_frontend_install_generated()
    local source, target_ctx = JsonExample.new_source_spec_and_target_ctx(T)
    source:check():lower():define_machine():install_generated(target_ctx)

    local source_spec = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = SAMPLE })
    )
    assert_json_tree(source_spec.root)
end

local function test_json_frontend_emit_lua()
    local source, target_ctx = JsonExample.new_source_spec_and_target_ctx(T)
    local out = source:check():lower():define_machine():emit_lua()
    install_emitted(out, target_ctx)

    local source_spec = target_ctx.TargetToken.Spec.parse(
        target_ctx.TargetText.Spec.tokenize({ text = SAMPLE })
    )
    assert_json_tree(source_spec.root)
end

test_json_frontend_install_generated()
test_json_frontend_emit_lua()

print("frontend_json_frontend_test.lua: ok")
