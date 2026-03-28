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

local I = U.inspect_from("examples/inspect/spec_demo.t")
assert(I.progress().type_total == 4)
assert(I.progress().boundary_total == 2)
assert(I.find_boundary("Demo.Expr:lower") ~= nil)

print("unit_shared_terra_smoke.t: ok")
