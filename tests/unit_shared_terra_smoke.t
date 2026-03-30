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

local terra incr(x : int32)
    return x + 1
end

struct TerraSmokeState { total : int32 }
local terra accum(x : int32, state : &TerraSmokeState)
    state.total = state.total + x
    return state.total
end

local stateless = U.leaf(nil, incr)
assert(stateless.fn(4) == 5)

local stateful = U.leaf(TerraSmokeState, accum)
local state = terralib.new(TerraSmokeState)
assert(stateful.fn(3, state) == 3)
assert(stateful.fn(5, state) == 8)

local x = symbol(int32, "x")
local quoted = U.leaf_quote(nil, terralib.newlist({ x }), function(_, params)
    return quote
        return [params[1]] * 2
    end
end)
assert(quoted.fn(6) == 12)

struct IntBox { value : int32 }

local terra inc_ptr(p : &IntBox)
    p.value = p.value + 1
end
local terra dbl_ptr(p : &IntBox)
    p.value = p.value * 2
end
local inc_unit = U.leaf(nil, inc_ptr)
local dbl_unit = U.leaf(nil, dbl_ptr)

local terra composed_direct(p : &IntBox)
    inc_ptr(p)
    dbl_ptr(p)
end
local packaged = U.compose({ inc_unit, dbl_unit }, composed_direct)
local packed_value = terralib.new(IntBox)
packed_value.value = 7
packaged.fn(packed_value)
assert(packed_value.value == 16)

local qp = symbol(&IntBox, "p")
local quoted_compose = U.compose_quote({ inc_unit, dbl_unit }, terralib.newlist({ qp }), function(_, kids, params)
    return quote
        [kids[1].call(params[1])]
        [kids[2].call(params[1])]
    end
end)
local quoted_value = terralib.new(IntBox)
quoted_value.value = 7
quoted_compose.fn(quoted_value)
assert(quoted_value.value == 16)

local I = U.inspect_from("examples/inspect/demo_project")
assert(I.progress().type_total == 4)
assert(I.progress().boundary_total == 2)
assert(I.find_boundary("Demo.Expr:lower") ~= nil)

print("unit_shared_terra_smoke.t: ok")
