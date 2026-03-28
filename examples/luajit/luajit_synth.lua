#!/usr/bin/env luajit

-- Run from the repository root:
--   luajit examples/luajit/luajit_synth.lua
package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")
local fun = require("fun")
local U = require("unit_luajit")

ffi.cdef [[
    typedef struct { float phase; } OscState;
]]

local TAU = math.pi * 2.0
local OscState_t = U.state_ffi("OscState")

local function Node(kind, props)
    props.kind = kind
    return props
end

local compile_sine = U.terminal(function(node, sr)
    local inc = TAU * node.freq / sr

    return U.leaf(OscState_t, function(state, buf, n)
        local phase = state.phase
        local amp = node.amp or 1.0

        for i = 0, n - 1 do
            buf[i] = buf[i] + amp * math.sin(phase)
            phase = phase + inc
            if phase >= TAU then phase = phase - TAU end
        end

        state.phase = phase
    end)
end)

local compile_gain = U.terminal(function(node)
    local g = 10 ^ (node.db / 20)

    return U.leaf(nil, function(_, buf, n)
        for i = 0, n - 1 do
            buf[i] = buf[i] * g
        end
    end)
end)

local compile_node = U.terminal(function(node, sr)
    return U.match(node, {
        sine = function(n) return compile_sine(n, sr) end,
        gain = function(n) return compile_gain(n, sr) end,
    })
end)

local compile_chain = U.terminal(function(nodes, sr)
    local units = fun.iter(nodes)
        :map(function(node) return compile_node(node, sr) end)
        :totable()

    return U.compose_linear(units)
end)

local patch = {
    sample_rate = 48000,
    nodes = {
        Node("sine", { freq = 220.0, amp = 0.25 }),
        Node("gain", { db = -3.0 }),
    },
}

local unit = compile_chain(patch.nodes, patch.sample_rate)
local slot = U.hot_slot()
slot.swap(unit)

local n = 64
local buf = ffi.new("float[?]", n)
slot.callback(buf, n)

print("first 8 samples:")
for i = 0, 7 do
    io.write(string.format("%0.6f\n", tonumber(buf[i])))
end

slot.collect()
slot.close()
