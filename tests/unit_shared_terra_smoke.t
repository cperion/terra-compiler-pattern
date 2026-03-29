package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit")

assert(type(U.with_fallback) == "function")
assert(type(U.with_errors) == "function")
assert(type(U.errors) == "function")
assert(type(U.match) == "function")
assert(type(U.with) == "function")
assert(type(U.memo_inspector) == "function")
assert(type(U.memo) == "function")
assert(type(U.memo_stats) == "function")
assert(type(U.memo_report) == "function")
assert(type(U.memo_quality) == "function")
assert(type(U.memo_diagnose) == "function")
assert(type(U.memo_measure_edit) == "function")
assert(type(U.memo_reset) == "function")

local memo = U.memoize("terra-smoke-memo", function(x)
    return x + 1
end)
U.memo_reset()
assert(memo(1) == 2)
assert(memo(1) == 2)
local stats = U.memo_stats(memo)
assert(stats.hits == 1)
assert(stats.misses == 1)
assert(U.memo_report():match("MEMOIZE REPORT"))
assert(U.memo_quality():match("DESIGN QUALITY"))

local I = U.inspect_from("examples/inspect/spec_demo.t")
assert(I.progress().type_total == 4)
assert(I.progress().boundary_total == 2)
assert(I.find_boundary("Demo.Expr:lower") ~= nil)

print("unit_shared_terra_smoke.t: ok")
