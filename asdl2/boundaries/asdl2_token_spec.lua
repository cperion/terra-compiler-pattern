local Boot = require("asdl2.asdl2_boot")

local L = Boot.List
local concat = table.concat
local format = string.format

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

return function(T, U, P)
    local Source = T.Asdl2Source
    local Spec = Source.Spec
    local ModuleDef = Source.ModuleDef
    local TypeDef = Source.TypeDef
    local Product = Source.Product
    local Sum = Source.Sum
    local Constructor = Source.Constructor
    local Field = Source.Field
    local BuiltinTypeRef = Source.BuiltinTypeRef
    local UnqualifiedTypeRef = Source.UnqualifiedTypeRef
    local QualifiedTypeRef = Source.QualifiedTypeRef

    local CARD_EXACTLY_ONE = C(Source.ExactlyOne)
    local CARD_OPTIONAL = C(Source.Optional)
    local CARD_MANY = C(Source.Many)
    local EMPTY = L {}

    local builtin_ref_cache = {}
    for name, _ in pairs(BUILTIN) do
        builtin_ref_cache[name] = BuiltinTypeRef(name)
    end

    local unqualified_ref_cache = {}
    local qualified_ref_cache = {}

    local function unqualified_ref(name)
        local ref = unqualified_ref_cache[name]
        if ref ~= nil then return ref end
        ref = UnqualifiedTypeRef(name)
        unqualified_ref_cache[name] = ref
        return ref
    end

    local function qualified_ref(fqname)
        local ref = qualified_ref_cache[fqname]
        if ref ~= nil then return ref end
        ref = QualifiedTypeRef(fqname)
        qualified_ref_cache[fqname] = ref
        return ref
    end

    local function token_desc(tok)
        if tok.kind == "Ident" then
            return format("Ident(%s)", tok.text)
        end
        return tok.kind
    end

    local function token_span_desc(tok)
        local span = tok.span
        return format("bytes %d..%d", span.start_byte, span.end_byte)
    end

    T.Asdl2Token.Spec.parse = U.transition(function(token_spec)
        local tokens = token_spec.tokens
        local pos = 1
        local cur = tokens[pos]

        local function err(what)
            error(format(
                "asdl2_token.parse: expected %s but found %s at %s",
                what,
                token_desc(cur),
                token_span_desc(cur)
            ), 2)
        end

        local function next_token()
            pos = pos + 1
            cur = tokens[pos] or tokens[#tokens]
        end

        local function expect(kind)
            if cur.kind ~= kind then err(kind) end
            local tok = cur
            next_token()
            return tok
        end

        local function expect_ident()
            return expect("Ident").text
        end

        local function parse_cardinality()
            if cur.kind == "OptionalMark" then
                next_token()
                return CARD_OPTIONAL
            end
            if cur.kind == "ManyMark" then
                next_token()
                return CARD_MANY
            end
            return CARD_EXACTLY_ONE
        end

        local function parse_field()
            local first = expect_ident()
            local type_ref

            if cur.kind == "Dot" then
                local parts = { first }
                repeat
                    next_token()
                    parts[#parts + 1] = expect_ident()
                until cur.kind ~= "Dot"
                type_ref = qualified_ref(concat(parts, "."))
            else
                type_ref = builtin_ref_cache[first] or unqualified_ref(first)
            end

            local card = parse_cardinality()
            local name = expect_ident()
            return Field(type_ref, card, name)
        end

        local function parse_fields()
            expect("LParen")
            if cur.kind == "RParen" then
                next_token()
                return EMPTY
            end

            local fields = {}
            local n = 0
            repeat
                n = n + 1
                fields[n] = parse_field()
                if cur.kind ~= "Comma" then break end
                next_token()
            until false
            expect("RParen")
            return L(fields)
        end

        local function parse_product()
            local fields = parse_fields()
            local unique_flag = false
            if cur.kind == "UniqueKw" then
                unique_flag = true
                next_token()
            end
            return Product(fields, unique_flag)
        end

        local function parse_constructor()
            local name = expect_ident()
            local fields = EMPTY
            if cur.kind == "LParen" then
                fields = parse_fields()
            end
            local unique_flag = false
            if cur.kind == "UniqueKw" then
                unique_flag = true
                next_token()
            end
            return Constructor(name, fields, unique_flag)
        end

        local function parse_sum()
            local ctors = { parse_constructor() }
            local n = 1
            while cur.kind == "Bar" do
                next_token()
                n = n + 1
                ctors[n] = parse_constructor()
            end
            local attribute_fields = EMPTY
            if cur.kind == "AttributesKw" then
                next_token()
                attribute_fields = parse_fields()
            end
            return Sum(L(ctors), attribute_fields)
        end

        local function parse_type_expr()
            if cur.kind == "LParen" then return parse_product() end
            return parse_sum()
        end

        local parse_definitions

        local function parse_module_def()
            expect("ModuleKw")
            local name = expect_ident()
            expect("LBrace")
            local definitions = parse_definitions()
            expect("RBrace")
            return ModuleDef(name, definitions)
        end

        local function parse_type_def()
            local name = expect_ident()
            expect("Eq")
            return TypeDef(name, parse_type_expr())
        end

        function parse_definitions()
            local defs = {}
            local n = 0
            while cur.kind ~= "Eof" and cur.kind ~= "RBrace" do
                n = n + 1
                defs[n] = (cur.kind == "ModuleKw") and parse_module_def() or parse_type_def()
            end
            return L(defs)
        end

        local out = Spec(parse_definitions())
        expect("Eof")
        return out
    end)
end
