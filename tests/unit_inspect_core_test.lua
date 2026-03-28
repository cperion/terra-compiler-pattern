#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit_core").new()
local H = require("unit_inspect_core").new(U)

local function class(name)
    return {
        __name = name,
        isclassof = function() end,
    }
end

local function test_discover_phases()
    local phases = H.discover_phases({
        namespaces = {
            Zed = { Thing = class("Thing") },
            Empty = {},
            Alpha = { Node = class("Node"), helper = true },
        },
    })

    assert(#phases == 2)
    assert(phases[1] == "Alpha")
    assert(phases[2] == "Zed")
end

local function test_sorted_class_names()
    local names = H.sorted_class_names({
        c = class("C"),
        a = class("A"),
        helper = function() end,
        b = class("B"),
    })

    assert(#names == 3)
    assert(names[1] == "a")
    assert(names[2] == "b")
    assert(names[3] == "c")
end

local function test_field_type_string()
    assert(H.field_type_string({ type = "number" }) == "number")
    assert(H.field_type_string({ type = "Expr", optional = true }) == "Expr?")
    assert(H.field_type_string({ type = "Track", list = true }) == "Track*")
end

local function test_phase_buckets()
    local by_phase = {}
    local a = H.ensure_phase_bucket(by_phase, "Editor")
    local b = H.ensure_phase_bucket(by_phase, "Editor")

    assert(a == b)
    assert(a.boundary_total == 0)
    assert(a.type_total == 0)
end

local function test_sort_boundaries()
    local xs = {
        { receiver = "B.Node", name = "compile" },
        { receiver = "A.Node", name = "resolve" },
        { receiver = "A.Node", name = "lower" },
    }

    H.sort_boundaries(xs)

    assert(xs[1].receiver == "A.Node" and xs[1].name == "lower")
    assert(xs[2].receiver == "A.Node" and xs[2].name == "resolve")
    assert(xs[3].receiver == "B.Node" and xs[3].name == "compile")
end

local function test_append_unique_item()
    local xs, seen = {}, {}
    H.append_unique_item(xs, seen, "A")
    H.append_unique_item(xs, seen, "A")
    H.append_unique_item(xs, seen, "B")

    assert(#xs == 2)
    assert(xs[1] == "A")
    assert(xs[2] == "B")
end

local function test_is_public_method_and_stub()
    assert(H.is_public_method("lower", function() end) == true)
    assert(H.is_public_method("__index", function() end) == false)
    assert(H.is_public_method("init", function() end) == false)

    assert(H.is_stub({ fn = function() error("not implemented") end }) == true)
    assert(H.is_stub({ fn = function() return 1 end }) == false)
end

local function test_find_boundary()
    local boundaries = {
        { receiver = "A.Node", name = "lower" },
        { receiver = "B.Node", name = "compile" },
    }

    local b = H.find_boundary(boundaries, "B.Node:compile")
    assert(b == boundaries[2])
    assert(H.find_boundary(boundaries, "C.Node:lower") == nil)
end

local function test_resolve_type_name_and_direct_refs()
    local FooExpr = { fqname = "Foo.Expr" }
    local FooNode = {
        fqname = "Foo.Node",
        phase = "Foo",
        kind = "record",
        fields = {
            { name = "expr", type = "Expr" },
            { name = "child", type = "Foo.Child" },
        },
    }
    local FooChild = { fqname = "Foo.Child", phase = "Foo", kind = "record", fields = {} }
    local BarExpr = { fqname = "Bar.Expr", phase = "Bar", kind = "record", fields = {} }

    local type_map = {
        ["Foo.Expr"] = FooExpr,
        ["Foo.Node"] = FooNode,
        ["Foo.Child"] = FooChild,
        ["Bar.Expr"] = BarExpr,
    }

    assert(H.resolve_type_name(type_map, "Foo.Child", "Foo") == "Foo.Child")
    assert(H.resolve_type_name(type_map, "Child", "Foo") == "Foo.Child")
    assert(H.resolve_type_name(type_map, "Expr", nil) == nil)

    local refs = H.direct_refs(type_map, function(type_name, phase_name)
        return H.resolve_type_name(type_map, type_name, phase_name)
    end, FooNode)

    assert(#refs == 2)
    assert(refs[1].fqname == "Foo.Child")
    assert(refs[2].fqname == "Foo.Expr")
end

local function test_render_helpers()
    local lines = { "# Schema Documentation", "" }
    local DemoExpr = {
        fqname = "Demo.Expr",
        phase = "Demo",
        kind = "enum",
        variants = { "Add", "Mul" },
        variant_types = {},
        fields = {},
        class = { lower = function() end },
    }
    local DemoAdd = {
        fqname = "Demo.Add",
        phase = "Demo",
        kind = "record",
        variants = {},
        variant_types = {},
        fields = { { name = "x", type = "number" } },
        class = { lower = function() end },
    }
    local DemoNode = {
        fqname = "Demo.Node",
        phase = "Demo",
        kind = "record",
        variants = {},
        variant_types = {},
        fields = {
            { name = "expr", type = "Demo.Expr" },
        },
        class = {},
    }
    DemoExpr.variant_types = { DemoAdd }

    local types = { DemoExpr, DemoAdd, DemoNode }
    local boundaries = {
        { phase = "Demo", receiver = "Demo.Expr", name = "lower", type = DemoExpr },
    }

    H.append_phase_markdown(lines, "Demo", types, boundaries)
    local md = table.concat(lines, "\n")
    assert(md:match("## Phase: Demo"))
    assert(md:match("### Demo%.Expr %(enum%)"))
    assert(md:match("### Boundaries"))

    local scaffold_lines = {
        "function Expr:lower()",
    }
    H.append_enum_scaffold(scaffold_lines, { "Add", "Mul" })
    local scaffold = table.concat(scaffold_lines, "\n")
    assert(scaffold:match("Add = function"))
    assert(scaffold:match("Mul = function"))

    local status = H.render_status({
        type_total = 2,
        record_total = 1,
        enum_total = 1,
        variant_total = 2,
        boundary_total = 1,
        boundary_real = 1,
        boundary_coverage = 1.0,
        by_phase = {
            Demo = {
                type_total = 2,
                record_total = 1,
                enum_total = 1,
                variant_total = 2,
                boundary_total = 1,
                boundary_real = 1,
                boundary_stub = 0,
                boundary_coverage = 1.0,
            },
        },
    }, { "Demo" })

    assert(status:match("Schema inventory:"))
    assert(status:match("Boundary coverage:"))
    assert(status:match("100%.0%%"))

    local type_map = {
        ["Demo.Expr"] = DemoExpr,
        ["Demo.Add"] = DemoAdd,
        ["Demo.Node"] = DemoNode,
    }
    local graph = H.render_type_graph(type_map, function(type_name, phase_name)
        return H.resolve_type_name(type_map, type_name, phase_name)
    end, "Demo.Node", 3)
    assert(graph:match("### Demo%.Node"))
    assert(graph:match("### Demo%.Expr %([0-9]+ variants%)"))

    local prompt_items = H.collect_prompt_child_items(
        boundaries,
        function() return { DemoAdd } end,
        boundaries[1])
    assert(#prompt_items == 1)
    assert(prompt_items[1] == "Demo.Add:lower()")

    local sections = {}
    H.append_prompt_sections(sections, boundaries[1], "TYPEGRAPH", prompt_items)
    local prompt = table.concat(sections, "\n\n")
    assert(prompt:match("## Phase: Demo"))
    assert(prompt:match("Demo.Add:lower%(%)"))

    local record_lines = { "function Node:lower()" }
    local record_calls = H.collect_record_scaffold_calls(type_map, function(type_name, phase_name)
        return H.resolve_type_name(type_map, type_name, phase_name)
    end, DemoNode, "lower")
    H.append_record_scaffold(record_lines, "lower", record_calls)
    local record_scaffold = table.concat(record_lines, "\n")
    assert(record_scaffold:find("local errs = U.errors()", 1, true))
end

test_discover_phases()
test_sorted_class_names()
test_field_type_string()
test_phase_buckets()
test_sort_boundaries()
test_append_unique_item()
test_is_public_method_and_stub()
test_find_boundary()
test_resolve_type_name_and_direct_refs()
test_render_helpers()

print("unit_inspect_core_test.lua: ok")
