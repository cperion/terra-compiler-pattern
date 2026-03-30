#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local Schema = require("asdl2.asdl2_schema")
local T = Schema.ctx

local function parse(text)
    return T.Asdl2Text.Spec(text):tokenize():parse()
end

local function test_parse_product_sum_and_attributes()
    local spec = parse([[
module Demo {
    Expr = Add(number lhs, Foo.Bar* rhs) unique | Zero attributes (string label, number? weight)
    Node = (Expr? current, string* labels) unique
}
]])

    assert(#spec.definitions == 1)

    local mod = spec.definitions[1]
    assert(mod.kind == "ModuleDef")
    assert(mod.name == "Demo")
    assert(#mod.definitions == 2)

    local expr = mod.definitions[1]
    local node = mod.definitions[2]

    assert(expr.kind == "TypeDef")
    assert(expr.name == "Expr")
    assert(expr.type_expr.kind == "Sum")
    assert(#expr.type_expr.constructors == 2)
    assert(#expr.type_expr.attribute_fields == 2)

    local add = expr.type_expr.constructors[1]
    local zero = expr.type_expr.constructors[2]
    assert(add.name == "Add")
    assert(add.unique_flag == true)
    assert(#add.fields == 2)
    assert(zero.name == "Zero")
    assert(zero.unique_flag == false)
    assert(#zero.fields == 0)

    local lhs = add.fields[1]
    local rhs = add.fields[2]
    assert(lhs.type_ref.kind == "BuiltinTypeRef")
    assert(lhs.type_ref.name == "number")
    assert(lhs.cardinality.kind == "ExactlyOne")
    assert(lhs.name == "lhs")

    assert(rhs.type_ref.kind == "QualifiedTypeRef")
    assert(rhs.type_ref.fqname == "Foo.Bar")
    assert(rhs.cardinality.kind == "Many")
    assert(rhs.name == "rhs")

    local label = expr.type_expr.attribute_fields[1]
    local weight = expr.type_expr.attribute_fields[2]
    assert(label.type_ref.kind == "BuiltinTypeRef")
    assert(label.type_ref.name == "string")
    assert(label.cardinality.kind == "ExactlyOne")
    assert(weight.cardinality.kind == "Optional")

    assert(node.kind == "TypeDef")
    assert(node.name == "Node")
    assert(node.type_expr.kind == "Product")
    assert(node.type_expr.unique_flag == true)
    assert(#node.type_expr.fields == 2)
    assert(node.type_expr.fields[1].type_ref.kind == "UnqualifiedTypeRef")
    assert(node.type_expr.fields[1].type_ref.name == "Expr")
    assert(node.type_expr.fields[1].cardinality.kind == "Optional")
    assert(node.type_expr.fields[2].type_ref.kind == "BuiltinTypeRef")
    assert(node.type_expr.fields[2].type_ref.name == "string")
    assert(node.type_expr.fields[2].cardinality.kind == "Many")
end

local function test_parse_comments_nested_modules_and_empty_shapes()
    local spec = parse([[
# leading comment
module Outer {
    # inner comment
    module Inner {
        Unit = () unique
        Choice = A | B(number n) unique
    }
}
]])

    local outer = spec.definitions[1]
    assert(outer.kind == "ModuleDef")
    assert(outer.name == "Outer")
    assert(#outer.definitions == 1)

    local inner = outer.definitions[1]
    assert(inner.kind == "ModuleDef")
    assert(inner.name == "Inner")
    assert(#inner.definitions == 2)

    local unit = inner.definitions[1]
    assert(unit.name == "Unit")
    assert(unit.type_expr.kind == "Product")
    assert(unit.type_expr.unique_flag == true)
    assert(#unit.type_expr.fields == 0)

    local choice = inner.definitions[2]
    assert(choice.name == "Choice")
    assert(choice.type_expr.kind == "Sum")
    assert(#choice.type_expr.constructors == 2)
    assert(choice.type_expr.constructors[1].name == "A")
    assert(#choice.type_expr.constructors[1].fields == 0)
    assert(choice.type_expr.constructors[2].name == "B")
    assert(choice.type_expr.constructors[2].unique_flag == true)
    assert(choice.type_expr.constructors[2].fields[1].type_ref.name == "number")
    assert(choice.type_expr.constructors[2].fields[1].name == "n")
end

local function test_parse_reuses_stable_type_refs_for_repeated_names()
    local spec = parse([[
module Demo {
    Pair = (string left, string right, Ref item, Ref other, Ext.Type x, Ext.Type y)
}
]])

    local fields = spec.definitions[1].definitions[1].type_expr.fields
    assert(fields[1].type_ref == fields[2].type_ref)
    assert(fields[3].type_ref == fields[4].type_ref)
    assert(fields[5].type_ref == fields[6].type_ref)
end

test_parse_product_sum_and_attributes()
test_parse_comments_nested_modules_and_empty_shapes()
test_parse_reuses_stable_type_refs_for_repeated_names()

print("asdl2_text_spec_test.lua: ok")
