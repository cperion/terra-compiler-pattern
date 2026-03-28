#!/usr/bin/env luajit

-- Run from the repository root:
--   luajit examples/luajit/luajit_app_demo.lua
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

local OscState_t = U.state_ffi("OscState")
local TAU = 2.0 * math.pi

local function Node(id, kind, props)
    props.id = id
    props.kind = kind
    return props
end

local function clone_node(node, overrides)
    local out = {}
    for k, v in pairs(node) do out[k] = v end
    for k, v in pairs(overrides) do out[k] = v end
    return out
end

local function update_node(nodes, node_id, updater)
    return fun.iter(nodes)
        :map(function(node)
            if node.id == node_id then
                return updater(node)
            end
            return node
        end)
        :totable()
end

local compile_sine = U.terminal(function(node, sr)
    local inc = TAU * node.freq / sr
    local amp = node.amp or 1.0

    return U.leaf(OscState_t, function(state, buf, n)
        local phase = state.phase
        for i = 0, n - 1 do
            buf[i] = buf[i] + amp * math.sin(phase)
            phase = phase + inc
            if phase >= TAU then phase = phase - TAU end
        end
        state.phase = phase
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

local driver = {
    callback = nil,
    snapshots = {},
}

local function capture(label)
    if not driver.callback then return end
    local n = 8
    local buf = ffi.new("float[?]", n)
    driver.callback(buf, n)

    local samples = {}
    for i = 0, n - 1 do
        samples[#samples + 1] = tonumber(buf[i])
    end

    driver.snapshots[#driver.snapshots + 1] = {
        label = label,
        samples = samples,
    }
end

local events = {
    { kind = "SetFreq", node_id = "osc", freq = 440.0 },
    { kind = "SetGainDb", node_id = "amp", db = -12.0 },
    { kind = "Stop" },
}

local event_i = 0

local function initial_state()
    return {
        running = true,
        sample_rate = 48000,
        nodes = {
            Node("osc", "sine", { freq = 220.0, amp = 0.25 }),
            Node("amp", "gain", { db = -3.0 }),
        },
    }
end

local apply = U.transition(function(state, event)
    return U.match(event, {
        SetFreq = function(e)
            return {
                running = state.running,
                sample_rate = state.sample_rate,
                nodes = update_node(state.nodes, e.node_id, function(node)
                    return clone_node(node, { freq = e.freq })
                end),
            }
        end,

        SetGainDb = function(e)
            return {
                running = state.running,
                sample_rate = state.sample_rate,
                nodes = update_node(state.nodes, e.node_id, function(node)
                    return clone_node(node, { db = e.db })
                end),
            }
        end,

        Stop = function(_)
            return {
                running = false,
                sample_rate = state.sample_rate,
                nodes = state.nodes,
            }
        end,
    })
end)

local compile_audio = U.terminal(function(state)
    return compile_chain(state.nodes, state.sample_rate)
end)

local final_state = U.app {
    initial = initial_state,
    outputs = { audio = true },
    compile = {
        audio = compile_audio,
    },
    start = {
        audio = function(callback)
            driver.callback = callback
        end,
    },
    stop = {
        audio = function()
            driver.callback = nil
        end,
    },
    poll = function()
        if event_i == 0 then
            capture("initial")
        elseif event_i <= #events then
            capture("after event " .. tostring(event_i))
        end

        event_i = event_i + 1
        return events[event_i]
    end,
    apply = apply,
}

print("final running:", tostring(final_state.running))
print("snapshots:")
for _, snap in ipairs(driver.snapshots) do
    io.write(snap.label .. ":")
    for i = 1, #snap.samples do
        io.write(string.format(" %0.5f", snap.samples[i]))
    end
    io.write("\n")
end
