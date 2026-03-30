#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "/home/cedric/.luarocks/share/lua/5.1/?.lua",
    "/home/cedric/.luarocks/share/lua/5.1/?/init.lua",
    package.path,
}, ";")
package.cpath = table.concat({
    "/home/cedric/.luarocks/lib64/lua/5.1/?.so",
    package.cpath,
}, ";")

local ffi = require("ffi")
local cjson = require("cjson")
local lpeg = require("lpeg")
local dkjson = require("dkjson")
local lunajson = require("lunajson")

local spec = require("examples.parser.parser_schema")
local grammars = require("examples.parser.parsers")
local T = spec.ctx

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } bench_timespec_t;
    int clock_gettime(int, bench_timespec_t*);
]]
local ts = ffi.new("bench_timespec_t")

local function now()
    ffi.C.clock_gettime(1, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function bench(iters, fn)
    for i = 1, math.min(iters, 1000) do fn() end
    collectgarbage("collect")
    collectgarbage("collect")

    local t0 = now()
    for i = 1, iters do fn() end
    local t1 = now()
    return t1 - t0
end

local results = {}

local function report(group, name, elapsed, iters, bytes)
    local per_iter_us = elapsed / iters * 1e6
    local mb_per_sec = bytes and (bytes * iters / elapsed / 1e6) or 0
    results[#results + 1] = {
        group = group,
        name = name,
        per_iter_us = per_iter_us,
        mb_per_sec = mb_per_sec,
    }
end

local small_json = '{"name": "Alice", "age": 30, "active": true}'

local function make_medium_json()
    local parts = { '{"items": [' }
    for i = 1, 20 do
        if i > 1 then parts[#parts + 1] = "," end
        parts[#parts + 1] = string.format(
            '{"id": %d, "name": "item_%d", "value": %d.%d, "active": %s}',
            i, i, i * 10, i, i % 2 == 0 and "true" or "false"
        )
    end
    parts[#parts + 1] = '], "total": 20}'
    return table.concat(parts)
end
local medium_json = make_medium_json()

local function make_large_json()
    local parts = { '{"records": [' }
    for i = 1, 500 do
        if i > 1 then parts[#parts + 1] = "," end
        parts[#parts + 1] = string.format(
            '{"id": %d, "first": "name_%d", "last": "surname_%d", "email": "user%d@example.com", "score": %d.%d, "verified": %s}',
            i, i, i, i, i * 7, i % 100, i % 3 == 0 and "true" or "false"
        )
    end
    parts[#parts + 1] = '], "count": 500}'
    return table.concat(parts)
end
local large_json = make_large_json()

local csv_line = 'Alice,30,NYC,"Software Engineer",95.5,true'
local http_request = "GET /api/users?page=1&limit=20 HTTP/1.1\r\nHost: example.com\r\nAccept: application/json\r\nAuthorization: Bearer tok123\r\n\r\n"

local json_parser = grammars.json(T):compile()
local csv_parser = grammars.csv(T):compile()
local http_parser = grammars.http(T):compile()

assert(json_parser(small_json), "our parser failed on small_json")
assert(json_parser(medium_json), "our parser failed on medium_json")
assert(json_parser(large_json), "our parser failed on large_json")
assert(csv_parser(csv_line), "our csv parser failed")
assert(http_parser(http_request), "our http parser failed")

local lpeg_json
 do
    local P_l, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V
    local ws = S(" \t\n\r")^0
    local str = P_l('"') * (P_l('\\') * P_l(1) + (1 - P_l('"')))^0 * P_l('"')
    local num = P_l('-')^-1 * (P_l('0') + R('19') * R('09')^0) *
                (P_l('.') * R('09')^1)^-1 *
                (S('eE') * S('+-')^-1 * R('09')^1)^-1

    lpeg_json = P_l{
        "json",
        json = ws * V("value") * ws * P_l(-1),
        value = str + num + V("object") + V("array") +
                P_l("true") + P_l("false") + P_l("null"),
        object = P_l("{") * ws *
                 (V("pair") * (ws * P_l(",") * ws * V("pair"))^0)^-1 *
                 ws * P_l("}"),
        pair = str * ws * P_l(":") * ws * V("value"),
        array = P_l("[") * ws *
                (V("value") * (ws * P_l(",") * ws * V("value"))^0)^-1 *
                ws * P_l("]"),
    }
end

local lpeg_csv
 do
    local P_l, S, C, Ct = lpeg.P, lpeg.S, lpeg.C, lpeg.Ct
    local quoted = P_l('"') * (P_l('""') + (1 - P_l('"')))^0 * P_l('"')
    local field = quoted + (1 - S(',\n"'))^0
    lpeg_csv = Ct(C(field) * (P_l(',') * C(field))^0) * P_l(-1)
end

local lpeg_http
 do
    local P_l, R, C, Ct = lpeg.P, lpeg.R, lpeg.C, lpeg.Ct
    local crlf = P_l("\r\n")
    local method = C(R("AZ")^1)
    local path = C((1 - P_l(" "))^1)
    local version = C(P_l("HTTP/") * (R("09") + P_l("."))^1)
    local hname = C((1 - P_l(":"))^1)
    local hvalue = C((1 - P_l("\r\n"))^1)
    local header = Ct(hname * P_l(": ") * hvalue) * crlf
    lpeg_http = Ct(method * P_l(" ") * path * P_l(" ") * version * crlf * Ct(header^0) * crlf)
end

local function lua_csv_parse(line)
    local fields = {}
    for f in (line .. ","):gmatch("([^,]*),") do
        fields[#fields + 1] = f
    end
    return fields
end

local function lua_http_parse(req)
    local method, path, version = req:match("^(%u+) (%S+) (HTTP/%S+)\r\n")
    return method, path, version
end

print("═══════════════════════════════════════════════════════════════════════")
print("Parser benchmark — canonical compiled grammar vs LuaJIT alternatives")
print("═══════════════════════════════════════════════════════════════════════")
print(string.format("  LuaJIT %s", jit.version))
print(string.format("  lpeg %s  |  cjson (C)  |  lunajson (pure LuaJIT)  |  dkjson (pure Lua)", lpeg.version))
print()

local N_SMALL = 100000
print(string.format("── JSON small (%d bytes, %dk iters) ──", #small_json, N_SMALL / 1000))
report("json_small", "cjson (C)", bench(N_SMALL, function() cjson.decode(small_json) end), N_SMALL, #small_json)
report("json_small", "lunajson", bench(N_SMALL, function() lunajson.decode(small_json) end), N_SMALL, #small_json)
report("json_small", "dkjson", bench(N_SMALL, function() dkjson.decode(small_json) end), N_SMALL, #small_json)
report("json_small", "lpeg (C)", bench(N_SMALL, function() lpeg_json:match(small_json) end), N_SMALL, #small_json)
report("json_small", "OURS", bench(N_SMALL, function() json_parser(small_json) end), N_SMALL, #small_json)

local N_MED = 50000
print(string.format("── JSON medium (%d bytes, %dk iters) ──", #medium_json, N_MED / 1000))
report("json_medium", "cjson (C)", bench(N_MED, function() cjson.decode(medium_json) end), N_MED, #medium_json)
report("json_medium", "lunajson", bench(N_MED, function() lunajson.decode(medium_json) end), N_MED, #medium_json)
report("json_medium", "dkjson", bench(N_MED, function() dkjson.decode(medium_json) end), N_MED, #medium_json)
report("json_medium", "lpeg (C)", bench(N_MED, function() lpeg_json:match(medium_json) end), N_MED, #medium_json)
report("json_medium", "OURS", bench(N_MED, function() json_parser(medium_json) end), N_MED, #medium_json)

local N_LARGE = 1000
print(string.format("── JSON large (%d bytes, %d iters) ──", #large_json, N_LARGE))
report("json_large", "cjson (C)", bench(N_LARGE, function() cjson.decode(large_json) end), N_LARGE, #large_json)
report("json_large", "lunajson", bench(N_LARGE, function() lunajson.decode(large_json) end), N_LARGE, #large_json)
report("json_large", "dkjson", bench(N_LARGE, function() dkjson.decode(large_json) end), N_LARGE, #large_json)
report("json_large", "lpeg (C)", bench(N_LARGE, function() lpeg_json:match(large_json) end), N_LARGE, #large_json)
report("json_large", "OURS", bench(N_LARGE, function() json_parser(large_json) end), N_LARGE, #large_json)

local N_CSV = 200000
print(string.format("── CSV line (%d bytes, %dk iters) ──", #csv_line, N_CSV / 1000))
report("csv", "lua gmatch", bench(N_CSV, function() lua_csv_parse(csv_line) end), N_CSV, #csv_line)
report("csv", "lpeg (C)", bench(N_CSV, function() lpeg_csv:match(csv_line) end), N_CSV, #csv_line)
report("csv", "OURS", bench(N_CSV, function() csv_parser(csv_line) end), N_CSV, #csv_line)

local N_HTTP = 200000
print(string.format("── HTTP request (%d bytes, %dk iters) ──", #http_request, N_HTTP / 1000))
report("http", "lua pattern", bench(N_HTTP, function() lua_http_parse(http_request) end), N_HTTP, #http_request)
report("http", "lpeg (C)", bench(N_HTTP, function() lpeg_http:match(http_request) end), N_HTTP, #http_request)
report("http", "OURS", bench(N_HTTP, function() http_parser(http_request) end), N_HTTP, #http_request)

print()
print("═══════════════════════════════════════════════════════════════════════")
print(string.format("  %-14s  %-20s  %10s  %10s  %8s", "workload", "parser", "µs/parse", "MB/s", "vs best"))
print(string.rep("─", 75))

local groups = {}
local group_order = {}
for _, r in ipairs(results) do
    if not groups[r.group] then
        groups[r.group] = {}
        group_order[#group_order + 1] = r.group
    end
    groups[r.group][#groups[r.group] + 1] = r
end

for _, gname in ipairs(group_order) do
    local g = groups[gname]
    local best_us = math.huge
    for _, r in ipairs(g) do
        if r.per_iter_us < best_us then best_us = r.per_iter_us end
    end
    for _, r in ipairs(g) do
        local ratio = r.per_iter_us / best_us
        local marker = r.name == "OURS" and " ◀" or ""
        print(string.format("  %-14s  %-20s  %10.1f  %10.1f  %7.1fx%s",
            r.group, r.name, r.per_iter_us, r.mb_per_sec, ratio, marker))
    end
    print(string.rep("─", 75))
end

print()
print("Legend:")
print("  cjson    = C library, hand-optimized, parses to Lua tables")
print("  lpeg     = C PEG engine by Roberto Ierusalimschy (compiled C)")
print("  lunajson = pure LuaJIT JSON decoder, optimized for traces")
print("  dkjson   = pure Lua JSON decoder, portable")
print("  OURS     = canonical grammar ASDL → compiled closure tree, pure LuaJIT")
print()
print("Note:")
print("  cjson/lunajson/dkjson produce Lua tables (full decode).")
print("  lpeg/OURS only validate + capture spans (recognition).")
print("  JSON/CSV/HTTP grammars come from examples/parser/parsers/.")
