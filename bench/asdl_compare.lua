#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./terra/src/?.lua",
    package.path,
}, ";")

local function load_old_asdl()
    local saved = package.loaded["asdl"]
    package.loaded["asdl"] = nil
    dofile("terra/src/asdl.lua")
    local old = package.loaded["asdl"]
    package.loaded["asdl"] = saved
    return old
end

local new_asdl = require("asdl")
local old_asdl = load_old_asdl()

local schema = [[
module Bench {
    Point = (number x, number y) unique
    Expr = Add(number lhs, number rhs)
         | Zero
    Path = (Point* points, string label, Expr? focus) unique
}
]]

local function now()
    collectgarbage("collect")
    collectgarbage("collect")
    return os.clock()
end

local function measure(fn)
    local t0 = now()
    local result = fn()
    return os.clock() - t0, result
end

local function best_of(n, fn)
    local best_t, best_r = nil, nil
    for _ = 1, n do
        local t, r = measure(fn)
        if not best_t or t < best_t then
            best_t, best_r = t, r
        end
    end
    return best_t, best_r
end

local function make_ctx(mod)
    local C = mod.NewContext()
    C:Define(schema)
    return C
end

local function bench_define(mod, reps)
    return best_of(5, function()
        local last
        for _ = 1, reps do
            last = mod.NewContext()
            last:Define(schema)
        end
        return last
    end)
end

local function bench_point_hit(mod, reps)
    local C = make_ctx(mod)
    return best_of(5, function()
        local last, acc = nil, 0
        for i = 1, reps do
            last = (i % 2 == 0) and C.Bench.Point(1, 2) or C.Bench.Point(1, 3)
            acc = acc + last.y
        end
        return { last = last, acc = acc }
    end)
end

local function bench_point_miss(mod, reps)
    local C = make_ctx(mod)
    return best_of(5, function()
        local last, acc = nil, 0
        for i = 1, reps do
            last = C.Bench.Point(i, i + 1)
            acc = acc + last.y
        end
        return { last = last, acc = acc }
    end)
end

local function bench_add_ctor(mod, reps)
    local C = make_ctx(mod)
    return best_of(5, function()
        local last, acc = nil, 0
        for i = 1, reps do
            last = C.Bench.Add(i, i + 1)
            acc = acc + last.lhs
        end
        return { last = last, acc = acc }
    end)
end

local function bench_path_hit(mod, reps)
    local C = make_ctx(mod)
    local List = mod.List
    local p1 = C.Bench.Point(1, 2)
    local p2 = C.Bench.Point(3, 4)
    local add = C.Bench.Add(10, 20)
    local zero = C.Bench.Zero
    return best_of(5, function()
        local last, acc = nil, 0
        for i = 1, reps do
            last = (i % 2 == 0)
                and C.Bench.Path(List({ p1, p2 }), "hello", add)
                or C.Bench.Path(List({ p1, p2 }), "hello", zero)
            acc = acc + #last.points
        end
        return { last = last, acc = acc }
    end)
end

local function ratio(old_t, new_t)
    if new_t == 0 then return "inf" end
    return string.format("%.2fx", old_t / new_t)
end

local function line(name, old_t, new_t)
    print(string.format("%-18s old=%8.4f  new=%8.4f  speedup=%s", name, old_t, new_t, ratio(old_t, new_t)))
end

local DEFINE_REPS = 150
local POINT_HIT_REPS = 300000
local POINT_MISS_REPS = 120000
local ADD_REPS = 250000
local PATH_HIT_REPS = 80000

local old_define = bench_define(old_asdl, DEFINE_REPS)
local new_define = bench_define(new_asdl, DEFINE_REPS)
local old_hit, old_p = bench_point_hit(old_asdl, POINT_HIT_REPS)
local new_hit, new_p = bench_point_hit(new_asdl, POINT_HIT_REPS)
local old_miss, old_m = bench_point_miss(old_asdl, POINT_MISS_REPS)
local new_miss, new_m = bench_point_miss(new_asdl, POINT_MISS_REPS)
local old_add, old_addv = bench_add_ctor(old_asdl, ADD_REPS)
local new_add, new_addv = bench_add_ctor(new_asdl, ADD_REPS)
local old_path, old_pathv = bench_path_hit(old_asdl, PATH_HIT_REPS)
local new_path, new_pathv = bench_path_hit(new_asdl, PATH_HIT_REPS)

assert(old_p.last.x == 1 and (old_p.last.y == 2 or old_p.last.y == 3) and old_p.acc > 0)
assert(new_p.last.x == 1 and (new_p.last.y == 2 or new_p.last.y == 3) and new_p.acc > 0)
assert(old_m.last.x > 0 and old_m.acc > 0)
assert(new_m.last.x > 0 and new_m.acc > 0)
assert(old_addv.last.kind == "Add" and old_addv.acc > 0)
assert(new_addv.last.kind == "Add" and new_addv.acc > 0)
assert(old_pathv.last.label == "hello" and old_pathv.acc > 0)
assert(new_pathv.last.label == "hello" and new_pathv.acc > 0)

print("ASDL benchmark: terra/src/asdl.lua vs current asdl.lua")
print(string.format("reps: define=%d point_hit=%d point_miss=%d add=%d path_hit=%d", DEFINE_REPS, POINT_HIT_REPS, POINT_MISS_REPS, ADD_REPS, PATH_HIT_REPS))
print("")
line("define", old_define, new_define)
line("point_hit", old_hit, new_hit)
line("point_miss", old_miss, new_miss)
line("add_ctor", old_add, new_add)
line("path_hit", old_path, new_path)
