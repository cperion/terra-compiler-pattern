local Boot = require("asdl2.asdl2_boot")

local L = Boot.List

local BUILTIN = {
    number = true,
    boolean = true,
    string = true,
    any = true,
    userdata = true,
    cdata = true,
    ["function"] = true,
}

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function S(v)
    return v
end

local BYTE_EQ = string.byte("=")
local BYTE_BAR = string.byte("|")
local BYTE_Q = string.byte("?")
local BYTE_STAR = string.byte("*")
local BYTE_COMMA = string.byte(",")
local BYTE_LPAREN = string.byte("(")
local BYTE_RPAREN = string.byte(")")
local BYTE_LBRACE = string.byte("{")
local BYTE_RBRACE = string.byte("}")
local BYTE_DOT = string.byte(".")
local BYTE_HASH = string.byte("#")
local BYTE_NL = string.byte("\n")

local function is_ident_start(c)
    return c == 95
        or (c >= 65 and c <= 90)
        or (c >= 97 and c <= 122)
end

local function is_ident_continue(c)
    return c == 95
        or (c >= 48 and c <= 57)
        or (c >= 65 and c <= 90)
        or (c >= 97 and c <= 122)
end

local function is_space(c)
    return c == 32 or c == 9 or c == 10 or c == 13
end

return function(T, U, P)
    T.Asdl2Text.Spec.parse = U.transition(function(spec)
        local text = S(spec.text)
        local len = #text
        local pos = 1
        local cur = nil
        local value = nil

        local function err(what)
            error(string.format(
                "asdl2_text.parse: expected %s but found '%s' here:\n%s",
                what,
                tostring(value),
                text:sub(1, pos) .. "<--##    " .. text:sub(pos + 1, -1)
            ), 2)
        end

        local function next_token()
            while true do
                while pos <= len do
                    local c = text:byte(pos)
                    if not is_space(c) then break end
                    pos = pos + 1
                end

                if pos > len then
                    cur, value = "EOF", "EOF"
                    return
                end

                if text:byte(pos) ~= BYTE_HASH then break end
                pos = pos + 1
                while pos <= len and text:byte(pos) ~= BYTE_NL do
                    pos = pos + 1
                end
                if pos <= len then pos = pos + 1 end
            end

            local c = text:byte(pos)
            if c == BYTE_EQ or c == BYTE_BAR or c == BYTE_Q or c == BYTE_STAR
                or c == BYTE_COMMA or c == BYTE_LPAREN or c == BYTE_RPAREN
                or c == BYTE_LBRACE or c == BYTE_RBRACE or c == BYTE_DOT then
                cur = text:sub(pos, pos)
                value = cur
                pos = pos + 1
                return
            end

            if not is_ident_start(c) then
                value = text:sub(pos, pos)
                err("valid token")
            end

            local start = pos
            pos = pos + 1
            while pos <= len and is_ident_continue(text:byte(pos)) do
                pos = pos + 1
            end

            local ident = text:sub(start, pos - 1)
            if ident == "attributes" or ident == "unique" or ident == "module" then
                cur = ident
            else
                cur = "Ident"
            end
            value = ident
        end

        local function nextif(kind)
            if cur ~= kind then return false end
            next_token()
            return true
        end

        local function expect(kind)
            if cur ~= kind then err(kind) end
            local v = value
            next_token()
            return v
        end

        local function parse_cardinality()
            if nextif("?") then return C(T.Asdl2Source.Optional) end
            if nextif("*") then return C(T.Asdl2Source.Many) end
            return C(T.Asdl2Source.ExactlyOne)
        end

        local function parse_field()
            local first = expect("Ident")
            local type_ref

            if nextif(".") then
                local fqname = first .. "." .. expect("Ident")
                while nextif(".") do
                    fqname = fqname .. "." .. expect("Ident")
                end
                type_ref = T.Asdl2Source.QualifiedTypeRef(fqname)
            elseif BUILTIN[first] then
                type_ref = T.Asdl2Source.BuiltinTypeRef(first)
            else
                type_ref = T.Asdl2Source.UnqualifiedTypeRef(first)
            end

            local card = parse_cardinality()
            local name = expect("Ident")
            return T.Asdl2Source.Field(type_ref, card, name)
        end

        local function parse_fields()
            expect("(")
            local fields = {}
            if cur ~= ")" then
                repeat
                    fields[#fields + 1] = parse_field()
                until not nextif(",")
            end
            expect(")")
            return L(fields)
        end

        local function parse_product()
            local fields = parse_fields()
            local unique_flag = nextif("unique") and true or false
            return T.Asdl2Source.Product(fields, unique_flag)
        end

        local function parse_constructor()
            local name = expect("Ident")
            local fields = cur == "(" and parse_fields() or L {}
            local unique_flag = nextif("unique") and true or false
            return T.Asdl2Source.Constructor(name, fields, unique_flag)
        end

        local function parse_sum()
            local ctors = { parse_constructor() }
            while nextif("|") do
                ctors[#ctors + 1] = parse_constructor()
            end
            local attribute_fields = nextif("attributes") and parse_fields() or L {}
            return T.Asdl2Source.Sum(L(ctors), attribute_fields)
        end

        local function parse_type_expr()
            if cur == "(" then return parse_product() end
            return parse_sum()
        end

        local parse_definitions

        local function parse_module_def()
            expect("module")
            local name = expect("Ident")
            expect("{")
            local definitions = parse_definitions()
            expect("}")
            return T.Asdl2Source.ModuleDef(name, definitions)
        end

        local function parse_type_def()
            local name = expect("Ident")
            expect("=")
            return T.Asdl2Source.TypeDef(name, parse_type_expr())
        end

        function parse_definitions()
            local defs = {}
            while cur ~= "EOF" and cur ~= "}" do
                defs[#defs + 1] = (cur == "module") and parse_module_def() or parse_type_def()
            end
            return L(defs)
        end

        next_token()
        local out = T.Asdl2Source.Spec(parse_definitions())
        expect("EOF")
        return out
    end)
end
