#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local Schema = require("asdl2.asdl2_schema")
local T = Schema.ctx

local function tokenize(text)
    return T.Asdl2Text.Spec(text):tokenize()
end

local function test_tokenize_builds_typed_tokens_with_spans()
    local spec = tokenize([[
# comment
module Demo {
    Node = (Foo.Bar* xs, number? n) unique
}
]])

    local toks = spec.tokens
    assert(#toks == 19)

    assert(toks[1].kind == "ModuleKw")
    assert(toks[2].kind == "Ident" and toks[2].text == "Demo")
    assert(toks[3].kind == "LBrace")
    assert(toks[4].kind == "Ident" and toks[4].text == "Node")
    assert(toks[5].kind == "Eq")
    assert(toks[6].kind == "LParen")
    assert(toks[7].kind == "Ident" and toks[7].text == "Foo")
    assert(toks[8].kind == "Dot")
    assert(toks[9].kind == "Ident" and toks[9].text == "Bar")
    assert(toks[10].kind == "ManyMark")
    assert(toks[11].kind == "Ident" and toks[11].text == "xs")
    assert(toks[12].kind == "Comma")
    assert(toks[13].kind == "Ident" and toks[13].text == "number")
    assert(toks[14].kind == "OptionalMark")
    assert(toks[15].kind == "Ident" and toks[15].text == "n")
    assert(toks[16].kind == "RParen")
    assert(toks[17].kind == "UniqueKw")
    assert(toks[18].kind == "RBrace")
    assert(toks[19].kind == "Eof")

    for i = 1, #toks do
        local span = toks[i].span
        assert(span.start_byte <= span.end_byte)
    end

    local eof = tokenize("module X { }").tokens
    assert(eof[#eof].kind == "Eof")
end

local function test_tokenize_reports_invalid_token()
    local ok, err = pcall(function()
        tokenize("module Demo { X = @ }")
    end)

    assert(not ok)
    assert(tostring(err):match("expected valid token"))
    assert(tostring(err):match("@"))
end

test_tokenize_builds_typed_tokens_with_spans()
test_tokenize_reports_invalid_token()

print("asdl2_token_spec_test.lua: ok")
