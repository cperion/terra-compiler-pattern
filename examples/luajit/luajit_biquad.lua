#!/usr/bin/env luajit

-- Run from the repository root:
--   luajit examples/luajit/luajit_biquad.lua
package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")
local fun = require("fun")
local U = require("unit_luajit")

ffi.cdef [[
    typedef struct { int emitted; } ImpulseState;
    typedef struct { float x1, x2, y1, y2; } BiquadState;
]]

local ImpulseState_t = U.state_ffi("ImpulseState")
local BiquadState_t = U.state_ffi("BiquadState")

local function Node(kind, props)
    props.kind = kind
    return props
end

local function compute_lowpass_coeffs(freq, q, sr)
    local omega = 2.0 * math.pi * freq / sr
    local cosw = math.cos(omega)
    local alpha = math.sin(omega) / (2.0 * q)

    local b0 = (1.0 - cosw) * 0.5
    local b1 = 1.0 - cosw
    local b2 = (1.0 - cosw) * 0.5
    local a0 = 1.0 + alpha
    local a1 = -2.0 * cosw
    local a2 = 1.0 - alpha

    return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
end

local compile_impulse = U.terminal(function(node)
    local amp = node.amp or 1.0

    return U.leaf(ImpulseState_t, function(state, buf, n)
        if state.emitted == 0 and n > 0 then
            buf[0] = buf[0] + amp
            state.emitted = 1
        end
    end)
end)

local compile_biquad = U.terminal(function(node, sr)
    local b0, b1, b2, a1, a2 = compute_lowpass_coeffs(node.freq, node.q, sr)

    return U.leaf(BiquadState_t, function(state, buf, n)
        local x1, x2 = state.x1, state.x2
        local y1, y2 = state.y1, state.y2

        for i = 0, n - 1 do
            local x = buf[i]
            local y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            buf[i] = y
        end

        state.x1, state.x2 = x1, x2
        state.y1, state.y2 = y1, y2
    end)
end)

local compile_gain = U.terminal(function(node)
    local g = 10 ^ ((node.db or 0.0) / 20.0)
    return U.leaf(nil, function(_, buf, n)
        for i = 0, n - 1 do
            buf[i] = buf[i] * g
        end
    end)
end)

local compile_node = U.terminal(function(node, sr)
    return U.match(node, {
        impulse = function(n) return compile_impulse(n, sr) end,
        biquad = function(n) return compile_biquad(n, sr) end,
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
        Node("impulse", { amp = 1.0 }),
        Node("biquad", { freq = 1200.0, q = 0.707 }),
        Node("gain", { db = -3.0 }),
    },
}

local unit = compile_chain(patch.nodes, patch.sample_rate)
local slot = U.hot_slot()
slot.swap(unit)

local n = 32
local buf = ffi.new("float[?]", n)
slot.callback(buf, n)

print("lowpass impulse response (first 16 samples):")
for i = 0, 15 do
    io.write(string.format("%2d  %0.8f\n", i, tonumber(buf[i])))
end

slot.collect()
slot.close()
