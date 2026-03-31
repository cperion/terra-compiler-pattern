#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")

local U = require("unit_core").new()
require("unit_schema").install(U)

local T = U.load_inspect_spec("frontendc").ctx
local JsonExample = require("frontendc.examples.json_frontend")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } frontendc_json_bench_timespec_t;
    int clock_gettime(int clk_id, frontendc_json_bench_timespec_t *tp);
]]

local ts = ffi.new("frontendc_json_bench_timespec_t")
local CLOCK_MONOTONIC = 1

local function now_s()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function bench(iters, fn)
    local warm = math.min(iters, 50)
    local sink = 0
    for i = 1, warm do sink = sink + fn(i) end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do sink = sink + fn(i) end
    local t1 = now_s()
    return ((t1 - t0) * 1000) / iters, sink
end

local function report(label, name, avg_ms, bytes)
    local throughput = (#bytes > 0) and ((#bytes / (1024 * 1024)) / (avg_ms / 1000)) or 0
    print(string.format("%-18s avg_ms=%9.6f throughput_mb_s=%8.3f", label .. " " .. name, avg_ms, throughput))
end

local function optional_require(name)
    local ok, mod = pcall(require, name)
    if ok then return mod end
    return nil
end

local function make_medium_json()
    local parts = { '{"items":[' }
    for i = 1, 100 do
        if i > 1 then parts[#parts + 1] = "," end
        parts[#parts + 1] = string.format('{"id":%d,"name":"Item%d","ok":%s,"score":%0.3f}', i, i, (i % 2 == 0) and "true" or "false", i * 1.25)
    end
    parts[#parts + 1] = '],"meta":{"count":100,"kind":"medium"}}'
    return table.concat(parts)
end

local function make_large_json()
    local parts = { '{"rows":[' }
    for i = 1, 300 do
        if i > 1 then parts[#parts + 1] = "," end
        parts[#parts + 1] = string.format('{"id":%d,"name":"User%d","tags":["a","b","c"],"active":%s,"score":%0.3f,"note":null}', i, i, (i % 3 == 0) and "true" or "false", i / 3)
    end
    parts[#parts + 1] = '],"meta":{"count":300,"kind":"large"}}'
    return table.concat(parts)
end

local small_json = '{"name":"Alice","age":30,"active":true,"tags":["x","y"],"meta":{"ok":false},"none":null}'
local medium_json = make_medium_json()
local large_json = make_large_json()

local source, target_ctx = JsonExample.new_source_spec_and_target_ctx(T)
source:check():lower():define_machine():install_generated(target_ctx)

local function frontendc_decode(text)
    local token_spec = target_ctx.TargetText.Spec.tokenize({ text = text })
    return target_ctx.TargetToken.Spec.parse(token_spec).root
end

assert(frontendc_decode(small_json) ~= nil)
assert(frontendc_decode(medium_json) ~= nil)
assert(frontendc_decode(large_json) ~= nil)

local decoders = {
    { name = "frontendc", decode = frontendc_decode },
}

local cjson = optional_require("cjson") or optional_require("cjson.safe")
if cjson and cjson.decode then
    decoders[#decoders + 1] = { name = "cjson", decode = cjson.decode }
end

local lunajson = optional_require("lunajson")
if lunajson and lunajson.decode then
    decoders[#decoders + 1] = { name = "lunajson", decode = lunajson.decode }
end

local dkjson = optional_require("dkjson")
if dkjson and dkjson.decode then
    decoders[#decoders + 1] = { name = "dkjson", decode = dkjson.decode }
end

local vendored_dkjson = optional_require("examples.js.jsrun-app.deps.json")
if vendored_dkjson and vendored_dkjson.decode then
    decoders[#decoders + 1] = { name = "vendored_dkjson", decode = vendored_dkjson.decode }
end

local cases = {
    { name = "small", text = small_json, iters = 5000 },
    { name = "medium", text = medium_json, iters = 500 },
    { name = "large", text = large_json, iters = 50 },
}

print("frontendc JSON benchmark")
print("note: frontendc currently produces JSON AST nodes, while common JSON libs decode to Lua tables/values")
print("")

for _, case in ipairs(cases) do
    print(string.format("-- %s (%d bytes, %d iters)", case.name, #case.text, case.iters))
    for _, decoder in ipairs(decoders) do
        local avg_ms = bench(case.iters, function()
            return decoder.decode(case.text) and 1 or 0
        end)
        report(case.name, decoder.name, avg_ms, case.text)
    end
    print("")
end
