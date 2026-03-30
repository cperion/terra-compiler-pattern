#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local Lexer = require("asdl2.text_lexer")

local function lex_all(text)
    local lex = Lexer.new(text)
    local out = {}
    lex.next_token()
    while true do
        out[#out + 1] = { lex.cur, lex.value }
        if lex.cur == "EOF" then break end
        lex.next_token()
    end
    return out
end

local function test_tokenizes_keywords_punctuation_and_identifiers()
    local toks = lex_all([[
# comment
module Demo {
    Node = (Foo.Bar* xs, number? n) unique
    Expr = Add | Zero attributes (string label)
}
]])

    local want = {
        { "module", "module" },
        { "Ident", "Demo" },
        { "{", "{" },
        { "Ident", "Node" },
        { "=", "=" },
        { "(", "(" },
        { "Ident", "Foo" },
        { ".", "." },
        { "Ident", "Bar" },
        { "*", "*" },
        { "Ident", "xs" },
        { ",", "," },
        { "Ident", "number" },
        { "?", "?" },
        { "Ident", "n" },
        { ")", ")" },
        { "unique", "unique" },
        { "Ident", "Expr" },
        { "=", "=" },
        { "Ident", "Add" },
        { "|", "|" },
        { "Ident", "Zero" },
        { "attributes", "attributes" },
        { "(", "(" },
        { "Ident", "string" },
        { "Ident", "label" },
        { ")", ")" },
        { "}", "}" },
        { "EOF", "EOF" },
    }

    assert(#toks == #want)
    for i = 1, #want do
        assert(toks[i][1] == want[i][1], string.format("token %d kind: got %s want %s", i, toks[i][1], want[i][1]))
        assert(toks[i][2] == want[i][2], string.format("token %d value: got %s want %s", i, toks[i][2], want[i][2]))
    end
end

local function test_reports_invalid_token()
    local ok, err = pcall(function()
        local lex = Lexer.new("module Demo { X = @ }")
        while true do
            lex.next_token()
            if lex.cur == "EOF" then break end
        end
    end)

    assert(not ok)
    assert(tostring(err):match("expected valid token"))
    assert(tostring(err):match("@"))
end

test_tokenizes_keywords_punctuation_and_identifiers()
test_reports_invalid_token()

print("asdl2_text_lexer_test.lua: ok")
