#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit_core").new()
local A = require("asdl")

local function L(xs)
    return U.fold(xs, function(acc, x)
        acc[#acc + 1] = x
        return acc
    end, {})
end

local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = assert(f:read("*a"))
    f:close()
    return s
end

local function find_layout(spec, fqname)
    local found = nil
    U.each(spec.types, function(layout)
        local name = U.match(layout, {
            ProductLayout = function(v) return v.fqname end,
            SumLayout = function(v) return v.fqname end,
        })
        if name == fqname then found = layout end
    end)
    return found
end

local function test_parse_resolve_lower_small_schema()
    local source = A.parse([[
        module Demo {
            Expr = Add(number lhs, number rhs)
                 | Zero

            Node = (Expr? expr, string* labels) unique
        }
    ]])

    assert(#source.definitions == 1)
    assert(source.definitions[1].kind == "SourceModuleDef")

    local resolved = A.resolve(source)
    assert(#resolved.definitions == 1)

    local lowered = A.lower_luajit(resolved, { prefix = "demo_lj" })
    local expr = find_layout(lowered, "Demo.Expr")
    local node = find_layout(lowered, "Demo.Node")

    assert(expr ~= nil)
    assert(node ~= nil)

    U.match(expr, {
        ProductLayout = function()
            error("expected sum layout")
        end,
        SumLayout = function(v)
            assert(v.tag_ctype == "uint8_t")
            assert(#v.variants == 2)
            assert(v.variants[1].kind_name == "Add")
            assert(v.variants[1].tag_value == 1)
            assert(v.variants[2].kind_name == "Zero")
            assert(v.variants[2].tag_value == 2)
        end,
    })

    U.match(node, {
        ProductLayout = function(v)
            assert(v.unique_flag == true)
            assert(#v.slots == 2)
            assert(v.slots[1].name == "expr")
            assert(v.slots[1].optional_flag == true)
            assert(v.slots[1].slot_type.kind == "RefSlotType")
            assert(v.slots[2].name == "labels")
            assert(v.slots[2].optional_flag == false)
            assert(v.slots[2].slot_type.kind == "ListRefSlotType")
        end,
        SumLayout = function()
            error("expected product layout")
        end,
    })
end

local function test_compile_luajit_context()
    local C = A.NewContext()

    C:Define([[module Math {
        Point = (number x, string label) unique
        Expr = Add(number lhs, number rhs)
             | Zero
    }]])

    local p1 = C.Math.Point(3, "hi")
    local p2 = C.Math.Point(3, "hi")
    local p3 = U.with(p1, { label = "bye" })
    local add = C.Math.Add(2, 5)

    assert(type(p1) == "cdata")
    assert(p1 == p2)
    assert(p3.label == "bye")
    assert(U.match(add, {
        Add = function(v) return v.lhs + v.rhs end,
        Zero = function() return 0 end,
    }) == 7)
    assert(U.match(C.Math.Zero, {
        Add = function(v) return v.lhs + v.rhs end,
        Zero = function() return 0 end,
    }) == 0)
end

local function test_compile_refs_lists_and_optional_fields()
    local source = A.parse([[module Demo {
        Expr = Add(number lhs, number rhs)
             | Zero

        Node = (Expr? current, Expr* history, number? weight) unique
    }]])
    local resolved = A.resolve(source)
    local layout = A.lower_luajit(resolved, { prefix = "demo_handles" })
    local lowered = A.emit_luajit(layout)
    local cdefs = table.concat(lowered.cdefs, "\n")

    assert(cdefs:match("uint32_t current__h;"))
    assert(cdefs:match("uint32_t history__h;"))
    assert(cdefs:match("uint32_t weight__h;"))

    local C = A.NewContext()
    C:Define([[module Demo {
        Expr = Add(number lhs, number rhs)
             | Zero

        Node = (Expr? current, Expr* history, number? weight) unique
        Bag = (Expr* history)
    }]])

    local add = C.Demo.Add(1, 2)
    local zero = C.Demo.Zero
    local history_a = L({ add, zero })
    local history_b = L({ add, zero })

    local n1 = C.Demo.Node(add, history_a, nil)
    local n2 = C.Demo.Node(add, history_b, nil)
    local n3 = U.with(n1, { weight = 4.5, current = zero })
    local b1 = C.Demo.Bag(history_a)
    local b2 = C.Demo.Bag(history_b)

    assert(type(n1) == "cdata")
    assert(C.Demo.Node.__arenas.current.kind == "ref")
    assert(C.Demo.Node.__arenas.history.kind == "list")
    assert(C.Demo.Node.__arenas.weight.kind == "optional_scalar")
    assert(n1 == n2)
    assert(n1.current == add)
    assert(#n1.history == 2)
    assert(n1.history[1] == add)
    assert(n1.history[2] == zero)
    assert(n1.weight == nil)
    assert(n3.current == zero)
    assert(n3.weight == 4.5)
    assert(#n3.history == 2)
    assert(b1 ~= b2)
    assert(b1.history == b2.history)

    local ok, err = pcall(function()
        return C.Demo.Node(42, history_a, nil)
    end)
    assert(not ok)
    assert(tostring(err):match("expected 'Demo.Expr%?'"))
end

local function test_self_schema_pipeline()
    local source = A.parse(slurp("asdl_language.asdl"))
    local resolved = A.resolve(source)
    local lowered = A.lower_luajit(resolved, { prefix = "self_lj" })

    assert(#source.definitions == 1)
    assert(#resolved.definitions == 1)
    assert(#lowered.types > 0)
    assert(find_layout(lowered, "Asdl.Source.Spec") ~= nil)
    assert(find_layout(lowered, "Asdl.Resolved.Spec") ~= nil)
    assert(find_layout(lowered, "Asdl.LuaJit.Spec") ~= nil)
end

test_parse_resolve_lower_small_schema()
test_compile_luajit_context()
test_compile_refs_lists_and_optional_fields()
test_self_schema_pipeline()

print("ok")
