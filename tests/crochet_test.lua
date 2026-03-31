#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local C = require("crochet")

local function test_fn_keeps_symbols_structural_until_render()
    local syms = C.symbols()
    local fn_name = syms:fixed("my_fn")
    local a = syms:keyed("arg", 1)
    local b = syms:keyed("arg", 2)

    local node = C.fn(fn_name, { a, b }, C.block({
        C.line("return ", a, " + ", b),
    }))

    local rendered = C.render(node, {
        symbol_renderer = function(sym)
            return "<" .. sym.name .. ">"
        end,
    })

    assert(rendered == table.concat({
        "function <my_fn>(<arg_1>, <arg_2>)\n",
        "  return <arg_1> + <arg_2>\n",
        "end\n",
    }))
end

local function test_join_accepts_node_separator()
    local rendered = C.render(C.join({
        C.text("a"),
        C.text("b"),
        C.text("c"),
    }, C.line(",")))

    assert(rendered == "a,\nb,\nc")
end

local function test_nil_nodes_are_ignored_in_join()
    local rendered = C.render(C.join({
        C.text("x"),
        nil,
        C.text("y"),
    }, ""))
    assert(rendered == "xy")
end

test_fn_keeps_symbols_structural_until_render()
test_join_accepts_node_separator()
test_nil_nodes_are_ignored_in_join()

print("crochet_test.lua: ok")
