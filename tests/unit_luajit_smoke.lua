#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")
local U = require("unit_luajit")

ffi.cdef [[
    typedef struct { float value; } CounterState;
]]

local CounterState_t = U.state_ffi("CounterState")

local function test_leaf_compose_hot_slot()
    local add = U.leaf(CounterState_t, function(state, x)
        state.value = state.value + x
        return state.value
    end)

    local mul = U.leaf(nil, function(_, x)
        return x * 3
    end)

    local direct = U.compose({ add, mul }, function(state, x)
        local a = add.fn(state[1], x)
        local b = mul.fn(nil, x)
        return a, b
    end)

    local unit = U.compose_closure({ add, mul }, function(state, kids, x)
        local a = kids[1].call(state, x)
        local b = kids[2].call(state, x)
        return a, b
    end)

    local slot = U.hot_slot()
    local direct_state = direct.state_t.alloc()
    local da, db = direct.fn(direct_state, 4)
    assert(da == 4)
    assert(db == 12)
    direct.state_t.release(direct_state)

    slot.swap(unit)

    local a1, b1 = slot.callback(2)
    local a2, b2 = slot.callback(5)

    assert(a1 == 2)
    assert(b1 == 6)
    assert(math.abs(a2 - 7) < 1e-6)
    assert(b2 == 15)

    slot.collect()
    slot.close()
end

local function test_compose_linear()
    local unit = U.compose_linear({
        U.leaf(nil, function(_, x, acc)
            acc[1] = x + 1
        end),
        U.leaf(nil, function(_, x, acc)
            acc[2] = x * 2
        end),
    })

    local acc = {}
    unit.fn(nil, 3, acc)
    assert(acc[1] == 4)
    assert(acc[2] == 6)
end

local function test_app_loop()
    local seen = {}

    local compile_value = U.terminal(function(state)
        local k = state.value
        return U.leaf(nil, function(_, x)
            return x + k
        end)
    end)

    local events = {
        { kind = "Inc", amount = 2 },
        { kind = "Inc", amount = 5 },
        { kind = "Stop" },
    }
    local i = 0
    local driver = { callback = nil }

    local final = U.app {
        initial = function()
            return { running = true, value = 1 }
        end,
        outputs = { value = true },
        compile = {
            value = compile_value,
        },
        start = {
            value = function(callback)
                driver.callback = callback
                seen[#seen + 1] = callback(10)
            end,
        },
        stop = {
            value = function()
                driver.callback = nil
            end,
        },
        poll = function()
            i = i + 1
            local ev = events[i]
            if driver.callback and ev and ev.kind ~= "Stop" then
                seen[#seen + 1] = driver.callback(10)
            end
            return ev
        end,
        apply = U.transition(function(state, event)
            return U.match(event, {
                Inc = function(e)
                    return { running = true, value = state.value + e.amount }
                end,
                Stop = function(_)
                    return { running = false, value = state.value }
                end,
            })
        end),
    }

    assert(final.running == false)
    assert(final.value == 8)
    assert(#seen == 3)
    assert(seen[1] == 11)
    assert(seen[2] == 11)
    assert(seen[3] == 13)
end

test_leaf_compose_hot_slot()
test_compose_linear()
test_app_loop()

print("unit_luajit_smoke.lua: ok")
