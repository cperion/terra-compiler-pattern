#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local fun = require("fun")
local more = require("more-fun")

local function bench(name, rounds, fn)
    collectgarbage()
    collectgarbage()
    local t0 = os.clock()
    local result
    for _ = 1, rounds do
        result = fn()
    end
    local dt = os.clock() - t0
    io.write(string.format("%-28s %8.4f s  result=%s\n", name, dt, tostring(result)))
end

local xs = {}
for i = 1, 100000 do
    xs[i] = i
end

local rounds = 100

print("== array map/filter/sum (construct + run) ==")
bench("fun", rounds, function()
    return fun.iter(xs)
        :map(function(x) return x + 1 end)
        :filter(function(x) return x % 2 == 0 end)
        :sum()
end)
bench("more-fun", rounds, function()
    return more.iter(xs)
        :map(function(x) return x + 1 end)
        :filter(function(x) return x % 2 == 0 end)
        :sum()
end)

print("\n== array map/filter/sum (reuse pipeline) ==")
local fun_array = fun.iter(xs)
    :map(function(x) return x + 1 end)
    :filter(function(x) return x % 2 == 0 end)
local more_array = more.iter(xs)
    :map(function(x) return x + 1 end)
    :filter(function(x) return x % 2 == 0 end)
bench("fun", rounds, function()
    return fun_array:sum()
end)
bench("more-fun", rounds, function()
    return more_array:sum()
end)

print("\n== range map/filter/totable (construct + run) ==")
bench("fun", rounds, function()
    return #fun.range(1, 100000)
        :map(function(x) return x * 2 end)
        :filter(function(x) return x % 3 == 0 end)
        :totable()
end)
bench("more-fun", rounds, function()
    return #more.range(1, 100000)
        :map(function(x) return x * 2 end)
        :filter(function(x) return x % 3 == 0 end)
        :totable()
end)

print("\n== range map/filter/totable (reuse pipeline) ==")
local fun_range = fun.range(1, 100000)
    :map(function(x) return x * 2 end)
    :filter(function(x) return x % 3 == 0 end)
local more_range = more.range(1, 100000)
    :map(function(x) return x * 2 end)
    :filter(function(x) return x % 3 == 0 end)
bench("fun", rounds, function()
    return #fun_range:totable()
end)
bench("more-fun", rounds, function()
    return #more_range:totable()
end)

print("\n== array plain any/all/max (reuse pipeline) ==")
local fun_array_plain = fun.iter(xs)
local more_array_plain = more.iter(xs)
bench("fun any", rounds, function()
    return fun_array_plain:any(function(x) return x > 99999 end)
end)
bench("more any", rounds, function()
    return more_array_plain:any(function(x) return x > 99999 end)
end)
bench("fun all", rounds, function()
    return fun_array_plain:all(function(x) return x > 0 end)
end)
bench("more all", rounds, function()
    return more_array_plain:all(function(x) return x > 0 end)
end)
bench("fun max", rounds, function()
    return fun_array_plain:max()
end)
bench("more max", rounds, function()
    return more_array_plain:max()
end)

print("\n== range plain sum/max (reuse pipeline) ==")
local fun_plain_range = fun.range(1, 100000)
local more_plain_range = more.range(1, 100000)
bench("fun sum", rounds, function()
    return fun_plain_range:sum()
end)
bench("more sum", rounds, function()
    return more_plain_range:sum()
end)
bench("fun max", rounds, function()
    return fun_plain_range:max()
end)
bench("more max", rounds, function()
    return more_plain_range:max()
end)

print("\n== string plain foldl/any (reuse pipeline) ==")
local text = string.rep("abcd", 2500)
local fun_string = fun.iter(text)
local more_string = more.iter(text)
local count_d = function(acc, x)
    return acc + ((x == "d") and 1 or 0)
end
local is_d = function(x)
    return x == "d"
end
bench("fun foldl", rounds, function()
    return fun_string:foldl(count_d, 0)
end)
bench("more foldl", rounds, function()
    return more_string:foldl(count_d, 0)
end)
bench("fun any", rounds, function()
    return fun_string:any(is_d)
end)
bench("more any", rounds, function()
    return more_string:any(is_d)
end)

print("\n== string plain head/nth/min/max (reuse pipeline) ==")
bench("fun head", rounds, function()
    return fun_string:head()
end)
bench("more head", rounds, function()
    return more_string:head()
end)
bench("fun nth", rounds, function()
    return fun_string:nth(9999)
end)
bench("more nth", rounds, function()
    return more_string:nth(9999)
end)
bench("fun min", rounds, function()
    return fun_string:min()
end)
bench("more min", rounds, function()
    return more_string:min()
end)
bench("fun max", rounds, function()
    return fun_string:max()
end)
bench("more max", rounds, function()
    return more_string:max()
end)

print("\n== chain sum/any (reuse pipeline) ==")
local fun_chain = fun.chain(
    fun.iter({ 1, 2, 3 }):map(function(x) return x * 2 end),
    fun.range(4, 6),
    fun.iter({ 7, 8 })
):filter(function(x) return x % 2 == 0 end)
local more_chain = more.chain(
    more.iter({ 1, 2, 3 }):map(function(x) return x * 2 end),
    more.range(4, 6),
    more.iter({ 7, 8 })
):filter(function(x) return x % 2 == 0 end)
local is_eight = function(x)
    return x == 8
end
bench("fun sum", rounds, function()
    return fun_chain:sum()
end)
bench("more sum", rounds, function()
    return more_chain:sum()
end)
bench("fun any", rounds, function()
    return fun_chain:any(is_eight)
end)
bench("more any", rounds, function()
    return more_chain:any(is_eight)
end)
