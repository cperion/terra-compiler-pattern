#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit_core").new()
local asdl = require("asdl")

local function lowered_spec(prefix)
    prefix = prefix or "leaf_test"

    local add = {
        kind = "record",
        fqname = "Math.Add",
        ctype_name = prefix .. "_Math_Add",
        fields = {
            { name = "lhs", type = "number", inline = true, storage_kind = "inline_scalar", c_name = "double" },
            { name = "rhs", type = "number", inline = true, storage_kind = "inline_scalar", c_name = "double" },
        },
        unique = false,
        kind_name = "Add",
        sum_parent = "Math.Expr",
    }

    local zero = {
        kind = "record",
        fqname = "Math.Zero",
        ctype_name = prefix .. "_Math_Zero",
        fields = {},
        unique = false,
        kind_name = "Zero",
        sum_parent = "Math.Expr",
    }

    local point = {
        kind = "record",
        fqname = "Math.Point",
        ctype_name = prefix .. "_Math_Point",
        fields = {
            { name = "x", type = "number", inline = true, storage_kind = "inline_scalar", c_name = "double" },
            { name = "label", type = "string", inline = true, storage_kind = "inline_scalar", c_name = "const char *" },
        },
        unique = true,
    }

    local node = {
        kind = "record",
        fqname = "Math.Node",
        ctype_name = prefix .. "_Math_Node",
        fields = {
            { name = "current", type = "Math.Expr", optional = true, inline = false, storage_kind = "ref", handle_field = "current__h" },
            { name = "history", type = "Math.Expr", list = true, inline = false, storage_kind = "list", handle_field = "history__h" },
            { name = "weight", type = "number", optional = true, inline = false, storage_kind = "optional_scalar", handle_field = "weight__h" },
        },
        unique = true,
    }

    return {
        records = { point, add, zero, node },
        definitions = {
            ["Math.Point"] = point,
            ["Math.Add"] = add,
            ["Math.Zero"] = zero,
            ["Math.Node"] = node,
            ["Math.Expr"] = {
                kind = "sum",
                fqname = "Math.Expr",
                variants = { add, zero },
            },
        },
        cdefs = {
            string.format([[typedef struct %s_Math_Point {
  double x;
  const char * label;
} %s_Math_Point;]], prefix, prefix),
            string.format([[typedef struct %s_Math_Add {
  double lhs;
  double rhs;
} %s_Math_Add;]], prefix, prefix),
            string.format([[typedef struct %s_Math_Zero {
  uint8_t __unit;
} %s_Math_Zero;]], prefix, prefix),
            string.format([[typedef struct %s_Math_Node {
  uint32_t current__h;
  uint32_t history__h;
  uint32_t weight__h;
} %s_Math_Node;]], prefix, prefix),
        },
    }
end

local function test_leaf_compile_into()
    local C = asdl.new_leaf_context()
    asdl.compile_into(C, lowered_spec("leaf_test_a"))

    local p1 = C.Math.Point(3, "hi")
    local p2 = C.Math.Point(3, "hi")
    local add = C.Math.Add(10, 20)
    local zero = C.Math.Zero
    local n1 = C.Math.Node(add, { add, zero }, nil)
    local n2 = C.Math.Node(add, { add, zero }, nil)
    local n3 = U.with(n1, { current = zero, weight = 4.5 })

    assert(type(p1) == "cdata")
    assert(p1 == p2)
    assert(p1.x == 3)
    assert(p1.label == "hi")

    assert(U.match(add, {
        Add = function(v) return v.lhs + v.rhs end,
        Zero = function() return 0 end,
    }) == 30)

    assert(U.match(zero, {
        Add = function(v) return v.lhs + v.rhs end,
        Zero = function() return 0 end,
    }) == 0)

    assert(n1 == n2)
    assert(n1.current == add)
    assert(#n1.history == 2)
    assert(n3.current == zero)
    assert(n3.weight == 4.5)
    assert(C.Math.Node.__arenas.history.kind == "list")
end

local function test_leaf_validation()
    local C = asdl.new_leaf_context()
    asdl.compile_into(C, lowered_spec("leaf_test_b"))
    local add = C.Math.Add(1, 2)

    local ok1, err1 = pcall(function()
        return C.Math.Node(42, { add }, nil)
    end)
    assert(not ok1)
    assert(tostring(err1):match("Math%.Expr%?"))

    local ok2, err2 = pcall(function()
        return C.Math.Node(add, { 42 }, nil)
    end)
    assert(not ok2)
    assert(tostring(err2):match("Math%.Expr%*"))
end

test_leaf_compile_into()
test_leaf_validation()

print("ok")
