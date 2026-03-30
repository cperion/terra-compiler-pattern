local Boot = require("asdl2.asdl2_boot")
local Lexer = require("asdl2.text_lexer")

local L = Boot.List

return function(T, U, P)
    local Token = T.Asdl2Token
    local Span = Token.Span
    local Spec = Token.Spec
    local Ident = Token.Ident
    local ModuleKw = Token.ModuleKw
    local AttributesKw = Token.AttributesKw
    local UniqueKw = Token.UniqueKw
    local Eq = Token.Eq
    local Bar = Token.Bar
    local OptionalMark = Token.OptionalMark
    local ManyMark = Token.ManyMark
    local Comma = Token.Comma
    local LParen = Token.LParen
    local RParen = Token.RParen
    local LBrace = Token.LBrace
    local RBrace = Token.RBrace
    local Dot = Token.Dot
    local Eof = Token.Eof

    local function token_from_lex(lex)
        local span = Span(lex.start_byte, lex.end_byte)
        local kind = lex.cur

        if kind == "Ident" then return Ident(lex.value, span) end
        if kind == "module" then return ModuleKw(span) end
        if kind == "attributes" then return AttributesKw(span) end
        if kind == "unique" then return UniqueKw(span) end
        if kind == "=" then return Eq(span) end
        if kind == "|" then return Bar(span) end
        if kind == "?" then return OptionalMark(span) end
        if kind == "*" then return ManyMark(span) end
        if kind == "," then return Comma(span) end
        if kind == "(" then return LParen(span) end
        if kind == ")" then return RParen(span) end
        if kind == "{" then return LBrace(span) end
        if kind == "}" then return RBrace(span) end
        if kind == "." then return Dot(span) end
        if kind == "EOF" then return Eof(span) end

        error("asdl2_text.tokenize: unknown token kind '" .. tostring(kind) .. "'", 2)
    end

    T.Asdl2Text.Spec.tokenize = U.transition(function(spec)
        local lex = Lexer.new(spec.text)
        local tokens = {}
        local n = 0

        repeat
            lex.next_token()
            n = n + 1
            tokens[n] = token_from_lex(lex)
        until lex.cur == "EOF"

        return Spec(L(tokens))
    end)
end
