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

local direct_machine = U.machine_step(accum, nil, TerraSmokeState, "terra-direct")
local direct_unit = U.machine_to_unit(direct_machine)
local direct_state = terralib.new(TerraSmokeState)
direct_state.total = 0
assert(direct_unit.fn(4, direct_state) == 4)
assert(direct_unit.fn(6, direct_state) == 10)

local builder_machine = U.machine_step(function(param)
    local input = symbol(int32, "input")
    return terra([input])
        return [param.delta] + input
    end
end, { delta = 9 }, nil, "terra-builder")
local builder_unit = U.machine_to_unit(builder_machine)
assert(builder_unit.fn(3) == 12)

local hooked_iter_machine = U.machine_iter(function()
    error("hooked Terra iter machine should realize via hook before execution")
end, 0, nil, nil, {
    family = "terra-iter-hook",
    realize_terra = function(_, U_backend)
        local value = symbol(int32, "value")
        return U_backend.leaf_quote(nil, terralib.newlist({ value }), function(_, params)
            return quote
                return [params[1]] + 2
            end
        end)
    end,
})
local hooked_iter_unit = U.machine_to_unit(hooked_iter_machine)
assert(hooked_iter_unit.fn(5) == 7)

local machine_terminal = U.terminal(function(spec)
    return U.machine_step(function(param)
        local input = symbol(int32, "input")
        return terra([input])
            return input * [param.scale]
        end
    end, { scale = spec.scale }, nil, "terra-terminal-machine")
end)
local terminal_unit = machine_terminal({ scale = 3 })
assert(terminal_unit.fn(7) == 21)

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
