#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local spec = require("examples.parser.parser_schema")
local grammars = require("examples.parser.parsers")
local T = spec.ctx
local P = T._parser_builder

local pass, fail = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass = pass + 1
        print(string.format("OK    %s", name))
    else
        fail = fail + 1
        print(string.format("FAIL  %s\n      %s", name, tostring(err)))
    end
end

local function parse_ok(parser, input)
    local caps, pos = parser(input)
    assert(caps, "expected match on: " .. input)
    return caps, pos
end

local function parse_fail(parser, input)
    local caps = parser(input)
    assert(not caps, "expected no match on: " .. input)
end

local function extract(input, cap)
    return input:sub(cap.start + 1, cap.start + cap.len)
end

print("═══════════════════════════════════════════════════════════")
print("Parser compiler demo — grammar ASDL → closure tree")
print("═══════════════════════════════════════════════════════════")
print()

-- ══════════════════════════════════════
-- Layer 0: individual patterns
-- ══════════════════════════════════════

test("literal match", function()
    local g = P.grammar({ P.rule("start", P.lit("hello")) }, "start")
    local parser = g:compile()
    parse_ok(parser, "hello")
    parse_fail(parser, "world")
    parse_fail(parser, "hell")
end)

test("sequence + eof", function()
    local g = P.grammar({
        P.rule("start", P.seq(P.lit("ab"), P.lit("cd"), P.eof))
    }, "start")
    local parser = g:compile()
    parse_ok(parser, "abcd")
    parse_fail(parser, "abce")
end)

test("choice", function()
    local g = P.grammar({
        P.rule("start", P.alt(P.lit("yes"), P.lit("no")))
    }, "start")
    local parser = g:compile()
    parse_ok(parser, "yes")
    parse_ok(parser, "no")
    parse_fail(parser, "maybe")
end)

test("repeat + optional", function()
    local g = P.grammar({
        P.rule("start", P.seq(P.opt(P.lit("-")), P.plus(P.digit), P.eof))
    }, "start")
    local parser = g:compile()
    parse_ok(parser, "42")
    parse_ok(parser, "-7")
    parse_fail(parser, "-")
end)

test("lookahead", function()
    local g = P.grammar({
        P.rule("start", P.seq(P.not_look(P.lit("/")), P.any, P.eof))
    }, "start")
    local parser = g:compile()
    parse_ok(parser, "x")
    parse_fail(parser, "/")
end)

test("capture", function()
    local g = P.grammar({
        P.rule("start", P.seq(
            P.cap("greeting", P.plus(P.alpha)),
            P.lit(" "),
            P.cap("name", P.plus(P.alpha)),
            P.eof
        ))
    }, "start")
    local parser = g:compile()
    local caps = parse_ok(parser, "hello world")
    assert(#caps == 2)
    assert(extract("hello world", caps[1]) == "hello")
    assert(caps[1].name == "greeting")
    assert(extract("hello world", caps[2]) == "world")
    assert(caps[2].name == "name")
end)

test("rule reference + recursion", function()
    local g = P.grammar({
        P.rule("start", P.seq(P.ref("s"), P.eof)),
        P.rule("s", P.alt(
            P.seq(P.lit("("), P.ref("s"), P.lit(")"), P.ref("s")),
            P.lit("")
        )),
    }, "start")
    local parser = g:compile()
    parse_ok(parser, "")
    parse_ok(parser, "((())())")
    parse_fail(parser, "())")
end)

-- ══════════════════════════════════════
-- Layer 1: canonical parser set
-- ══════════════════════════════════════

test("canonical parser set", function()
    assert(#grammars.names >= 10)
    assert(grammars.names[1] == "json")
end)

test("json parser", function()
    local parser = grammars.json(T):compile()
    parse_ok(parser, '"hello"')
    parse_ok(parser, '{"users": [{"name": "Bob"}, {"name": "Eve"}]}')
    parse_ok(parser, '[1, [2, [3, [4]]]]')
    parse_fail(parser, '{missing: "quotes"}')
end)

test("csv parser", function()
    local parser = grammars.csv(T):compile()
    local input = 'name,age,city\nAlice,30,NYC\nBob,25,"San Francisco"'
    local caps = parse_ok(parser, input)
    assert(#caps == 9, "expected 9 fields, got " .. #caps)
    assert(extract(input, caps[1]) == "name")
    assert(extract(input, caps[9]) == '"San Francisco"')
end)

test("http parser", function()
    local parser = grammars.http(T):compile()
    local req = "GET /api/users?page=1&limit=20 HTTP/1.1\r\nHost: example.com\r\nAccept: application/json\r\n\r\n"
    local caps = parse_ok(parser, req)
    assert(caps[1].name == "method")
    assert(extract(req, caps[1]) == "GET")
end)

test("asdl parser", function()
    local parser = grammars.asdl(T):compile()
    local input = [[
-- small ASDL sample
module Demo {
    Expr = Literal(string text) | Add(Expr left, Expr right)
    Root = (Expr expr) unique
}
]]
    parse_ok(parser, input)
    parse_fail(parser, "module Broken { Expr = | Add() }")
end)

test("sql parser", function()
    local parser = grammars.sql(T):compile()
    parse_ok(parser, "SELECT id, name FROM users WHERE active = TRUE")
    parse_fail(parser, "SELECT FROM users")
    parse_fail(parser, "DELETE FROM users")
end)


test("ini parser", function()
    local parser = grammars.ini(T):compile()
    local input = [[
; comment
[server]
host = localhost
port = 8080

[paths]
root = /srv/www
]]
    parse_ok(parser, input)
    parse_fail(parser, "[broken\nkey=value")
end)


test("s-expression parser", function()
    local parser = grammars.s_expr(T):compile()
    parse_ok(parser, "(define (square x) (* x x))")
    parse_ok(parser, "(list 1 2 \"three\")")
    parse_fail(parser, "(unclosed")
end)


test("uri parser", function()
    local parser = grammars.uri(T):compile()
    parse_ok(parser, "https://example.com/a/b?x=1#frag")
    parse_ok(parser, "mailto:user@example.com")
    parse_fail(parser, "://broken")
end)


test("http response parser", function()
    local parser = grammars.http_response(T):compile()
    local input = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
    parse_ok(parser, input)
    parse_fail(parser, "HTTP/1.1 OK\r\n\r\n")
end)


test("ecmascript parser", function()
    local parser = grammars.ecmascript(T):compile()
    parse_ok(parser, [[
        import http, { createServer as create } from "http";
        export default class Server extends Base {
            static count = 0;
            #secret = 1;
            constructor(x) { this.x = x; }
            async run(a, ...rest) {
                for (let item of rest) { if (item ?? false) continue; }
                return `${a + this.x}`;
            }
        }
    ]])

    local f = assert(io.open("examples/js/demo_server.js", "rb"))
    local src = f:read("*a")
    f:close()
    parse_ok(parser, src)
    parse_fail(parser, "export default class { if ( }")
end)

-- ══════════════════════════════════════
-- Layer 2: benchmark
-- ══════════════════════════════════════

test("JSON parse speed", function()
    local parser = grammars.json(T):compile()

    local parts = { '{"items": [' }
    for i = 1, 20 do
        if i > 1 then parts[#parts + 1] = "," end
        parts[#parts + 1] = string.format(
            '{"id": %d, "name": "item_%d", "value": %d.%d, "active": %s}',
            i, i, i * 10, i, i % 2 == 0 and "true" or "false"
        )
    end
    parts[#parts + 1] = '], "total": 20}'
    local doc = table.concat(parts)

    for i = 1, 100 do parser(doc) end

    local ffi = require("ffi")
    ffi.cdef("typedef struct { long tv_sec; long tv_nsec; } timespec_t;")
    ffi.cdef("int clock_gettime(int, timespec_t*);")
    local ts = ffi.new("timespec_t")

    local iters = 10000
    ffi.C.clock_gettime(1, ts)
    local t0 = tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
    for i = 1, iters do parser(doc) end
    ffi.C.clock_gettime(1, ts)
    local t1 = tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9

    local elapsed = t1 - t0
    local per_iter_us = elapsed / iters * 1e6
    local mb_per_sec = (#doc * iters) / elapsed / 1e6

    print(string.format("        %d bytes × %d iters in %.3fs", #doc, iters, elapsed))
    print(string.format("        %.1f µs/parse  %.1f MB/s", per_iter_us, mb_per_sec))
    assert(per_iter_us < 5000, "too slow: " .. per_iter_us .. " µs/parse")
end)

print()
print("═══════════════════════════════════════════════════════════")
print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
