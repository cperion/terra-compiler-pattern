#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit_core").new()

local function record_class(name, field_names)
    local fields = {}
    for i, field_name in ipairs(field_names) do
        fields[i] = { name = field_name }
    end

    local class = {
        __name = name,
        __fields = fields,
    }

    setmetatable(class, {
        __call = function(self, ...)
            local values = { ... }
            local node = {}
            for i, field in ipairs(self.__fields) do
                node[field.name or field[1]] = values[i]
            end
            return setmetatable(node, self)
        end,
    })

    return class
end

local function test_each_name()
    local names = U.each_name({
        { beta = true, alpha = true },
        { gamma = true, alpha = true },
    })

    assert(#names == 3)
    assert(names[1] == "alpha")
    assert(names[2] == "beta")
    assert(names[3] == "gamma")
end

local function test_memoize_identity()
    local calls = 0
    local f = U.memoize(function(x, y)
        calls = calls + 1
        return { x = x, y = y }
    end)

    local key = {}
    local a = f(key, 1)
    local b = f(key, 1)
    local c = f({}, 1)

    assert(a == b)
    assert(a ~= c)
    assert(calls == 2)
end

local function test_with_fallback_and_with_errors()
    local fallback = U.with_fallback(function()
        error("boom")
    end, 42)

    assert(fallback() == 42)

    local wrapped = U.with_errors(function(errs, xs)
        local ys = errs:each(xs, function(x)
            if x.bad then error("bad item") end
            return x.value * 2
        end, "id", function() return -1 end)
        return ys
    end)

    local ys, errs = wrapped({
        { id = "a", value = 2 },
        { id = "b", bad = true },
    })

    assert(ys[1] == 4)
    assert(ys[2] == -1)
    assert(errs and #errs == 1)
    assert(errs[1].ref == "b")
end

local function test_match_exhaustive()
    local Expr = { __name = "Expr", __variants = { "Add", "Mul" } }
    local Add = { __name = "Add", __sum_parent = Expr }
    local Mul = { __name = "Mul", __sum_parent = Expr }

    local add = setmetatable({ kind = "Add", x = 3 }, Add)
    local mul = setmetatable({ kind = "Mul", y = 4 }, Mul)

    assert(U.match(add, {
        Add = function(v) return v.x end,
        Mul = function(v) return v.y end,
    }) == 3)

    assert(U.match(mul, {
        Add = function(v) return v.x end,
        Mul = function(v) return v.y end,
    }) == 4)

    local ok, err = pcall(function()
        return U.match(add, {
            Add = function(v) return v.x end,
        })
    end)

    assert(not ok)
    assert(tostring(err):match("missing variant 'Mul'"))
end

local function test_with_reconstructs()
    local Point = record_class("Point", { "x", "y" })
    local p1 = Point(1, 2)
    local p2 = U.with(p1, { y = 9 })

    assert(p1 ~= p2)
    assert(p1.x == 1 and p1.y == 2)
    assert(p2.x == 1 and p2.y == 9)
    assert(getmetatable(p2) == Point)
end

local function test_memo_inspector()
    local f = U.memoize("double", function(x)
        return x * 2
    end)

    local I = U.memo()
    I.reset()

    assert(f(3) == 6)
    assert(f(3) == 6)
    assert(f(4) == 8)

    local stats = U.memo_stats(f)
    assert(stats ~= nil)
    assert(stats.name == "double")
    assert(stats.calls == 3)
    assert(stats.hits == 1)
    assert(stats.misses == 2)
    assert(stats.unique_keys == 2)

    local report = U.memo_report()
    assert(report:match("MEMOIZE REPORT"))
    assert(report:match("double"))

    local quality = U.memo_quality()
    assert(quality:match("DESIGN QUALITY"))

    local edit = U.memo_measure_edit("repeat cached call", function()
        assert(f(3) == 6)
    end)
    assert(edit:match("EDIT: repeat cached call"))
    assert(edit:match("Reuse:"))

    local diag = U.memo_diagnose()
    assert(type(diag) == "string")
end

local function test_errors_merge_and_call()
    local errs = U.errors()

    local value = errs:call({ id = "node-1" }, function(target)
        return target.id .. "!", {
            { ref = "child", err = "minor" },
        }
    end)

    assert(value == "node-1!")

    errs:merge({
        { ref = "other", err = "warn" },
    })

    local list = errs:get()
    assert(list and #list == 2)
    assert(list[1].ref == "child")
    assert(list[2].ref == "other")
end

test_each_name()
test_memoize_identity()
test_with_fallback_and_with_errors()
test_match_exhaustive()
test_with_reconstructs()
test_memo_inspector()
test_errors_merge_and_call()

print("unit_core_test.lua: ok")
