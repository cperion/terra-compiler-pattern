local Boot = require("asdl2.asdl2_boot")
local Schema = require("asdl2.asdl2_schema")

local T = Schema.ctx
local L = Boot.List

local M = {
    T = T,
    L = L,
}

local KEEP = {}

local function KS(s)
    KEEP[#KEEP + 1] = s
    return s
end
M.KS = KS

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end
M.C = C

local function source_cardinality_for(i)
    return (i % 5 == 0) and C(T.Asdl2Source.Optional)
        or (i % 7 == 0) and C(T.Asdl2Source.Many)
        or C(T.Asdl2Source.ExactlyOne)
end

local function type_ref_for(i)
    if i % 11 == 0 then
        return T.Asdl2Source.QualifiedTypeRef(KS("Extern.Type" .. tostring(i % 4)))
    elseif i % 6 == 0 then
        return T.Asdl2Source.UnqualifiedTypeRef(KS("Product1"))
    elseif i % 5 == 0 then
        return T.Asdl2Source.UnqualifiedTypeRef(KS("Sum"))
    elseif i % 3 == 0 then
        return T.Asdl2Source.BuiltinTypeRef(KS("number"))
    elseif i % 2 == 0 then
        return T.Asdl2Source.BuiltinTypeRef(KS("boolean"))
    end
    return T.Asdl2Source.BuiltinTypeRef(KS("string"))
end

local function field(i)
    return T.Asdl2Source.Field(type_ref_for(i), source_cardinality_for(i), KS("field_" .. tostring(i)))
end

local function product_def(i, field_count)
    local fields = {}
    for j = 1, field_count do fields[j] = field(i * 11 + j) end
    return T.Asdl2Source.TypeDef(
        KS("Product" .. tostring(i)),
        T.Asdl2Source.Product(L(fields), (i % 3) == 0)
    )
end

local function ctor(tag, field_count)
    local fields = {}
    for j = 1, field_count do fields[j] = field(tag * 13 + j + 1000) end
    return T.Asdl2Source.Constructor(
        KS("V" .. tostring(tag)),
        L(fields),
        (tag % 2) == 0
    )
end

local function sum_def(variant_count, field_count)
    local ctors = {}
    local attrs = {}
    for i = 1, variant_count do ctors[i] = ctor(i, field_count) end
    for i = 1, math.max(1, math.floor(field_count / 2)) do attrs[i] = field(5000 + i) end
    return T.Asdl2Source.TypeDef(KS("Sum"), T.Asdl2Source.Sum(L(ctors), L(attrs)))
end

function M.build_source(seed, type_count, field_count, variant_count)
    local defs = {}
    for i = 1, type_count do defs[#defs + 1] = product_def(i, field_count) end
    defs[#defs + 1] = sum_def(variant_count, field_count)
    return T.Asdl2Source.Spec(L{
        T.Asdl2Source.ModuleDef(KS("Bench" .. tostring(seed)), L(defs))
    })
end

return M
