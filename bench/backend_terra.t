package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local ffi = require("ffi")
local fun = require("fun")
local U = require("unit")
local B = require("bench.backend_bench_common")

local BLOCK = B.getenv_number("BENCH_BLOCK", 16384)
local SMALL_BLOCK = B.getenv_number("BENCH_SMALL_BLOCK", 16)
local WARMUP = B.getenv_number("BENCH_WARMUP", 64)
local ITERS = B.getenv_number("BENCH_ITERS", 256)
local COMPILE_ITERS = B.getenv_number("BENCH_COMPILE_ITERS", 64)
local SAMPLE_RATE = B.getenv_number("BENCH_SR", 48000)
local CHAIN_LEN = B.getenv_number("BENCH_CHAIN_LEN", 8)

struct BenchBiquadState { x1 : float; x2 : float; y1 : float; y2 : float }

local terra copy_buf(dst : &float, src : &float, n : int32)
    for i = 0, n do
        dst[i] = src[i]
    end
end
copy_buf:compile()

local function audio_params()
    local buf = symbol(&float, "buf")
    local n = symbol(int32, "n")
    return terralib.newlist({ buf, n })
end

local function make_gain(db)
    return { kind = "gain", db = db }
end

local function make_biquad(freq, q)
    return { kind = "biquad", freq = freq, q = q }
end

local compile_gain = U.terminal(function(node)
    local g = 10 ^ (node.db / 20)
    local params = audio_params()
    local buf, n = params[1], params[2]

    return U.leaf_quote(nil, params, function(_, _)
        return quote
            for i = 0, [n] do
                buf[i] = buf[i] * [float](g)
            end
        end
    end)
end)

local compile_biquad = U.terminal(function(node, sr)
    local b0, b1, b2, a1, a2 = B.compute_lowpass_coeffs(node.freq, node.q, sr)
    local params = audio_params()
    local buf, n = params[1], params[2]

    local unit = U.leaf_quote(BenchBiquadState, params, function(state, _)
        return quote
            var x1 = state.x1
            var x2 = state.x2
            var y1 = state.y1
            var y2 = state.y2

            for i = 0, [n] do
                var x = buf[i]
                var y = [float](b0)*x + [float](b1)*x1 + [float](b2)*x2
                    - [float](a1)*y1 - [float](a2)*y2
                x2 = x1; x1 = x
                y2 = y1; y1 = y
                buf[i] = y
            end

            state.x1 = x1
            state.x2 = x2
            state.y1 = y1
            state.y2 = y2
        end
    end)

    unit.init = function(state)
        state.x1 = 0; state.x2 = 0; state.y1 = 0; state.y2 = 0
    end

    return unit
end)

local compile_node = U.terminal(function(node, sr)
    return U.match(node, {
        gain = function(n) return compile_gain(n, sr) end,
        biquad = function(n) return compile_biquad(n, sr) end,
    })
end)

local compile_chain = U.terminal(function(nodes, sr)
    local units = fun.iter(nodes)
        :map(function(node) return compile_node(node, sr) end)
        :totable()

    local params = audio_params()
    local buf, n = params[1], params[2]

    return U.compose_quote(units, params, function(_, kids, _)
        local stmts = terralib.newlist()
        for _, kid in ipairs(kids) do
            stmts:insert(kid.call(buf, n))
        end
        return quote [stmts] end
    end)
end)

local function make_chain(seed)
    local nodes = {}
    for i = 1, CHAIN_LEN do
        if i % 2 == 1 then
            nodes[i] = make_biquad(300 + seed * 7 + i * 31, 0.707)
        else
            nodes[i] = make_gain(-1.0 - ((seed + i) % 6))
        end
    end
    return nodes
end

local function make_gain_chain(seed)
    local nodes = {}
    for i = 1, CHAIN_LEN do
        nodes[i] = make_gain(-0.25 - (((seed + i) % 9) * 0.5))
    end
    return nodes
end

local function edit_middle(nodes, seed)
    local out = {}
    local idx = math.floor((#nodes + 1) / 2)
    for i = 1, #nodes do
        if i == idx then
            local old = nodes[i]
            if old.kind == "biquad" then
                out[i] = make_biquad(old.freq + 17 + seed, old.q)
            else
                out[i] = make_gain(old.db - 0.125)
            end
        else
            out[i] = nodes[i]
        end
    end
    return out
end

local function bench_compile(factory)
    local t0 = B.now_ns()
    local last
    for i = 1, COMPILE_ITERS do
        last = factory(i)
    end
    local dt = B.now_ns() - t0
    return dt / COMPILE_ITERS, last
end

local function bench_compile_hit(factory, input)
    local last = factory(input)
    local t0 = B.now_ns()
    for _ = 1, COMPILE_ITERS do
        last = factory(input)
    end
    local dt = B.now_ns() - t0
    return dt / COMPILE_ITERS, last
end

local function bench_compile_edit()
    local total = 0
    local last
    for i = 1, COMPILE_ITERS do
        local old_nodes = make_chain(i)
        compile_chain(old_nodes, SAMPLE_RATE)
        local new_nodes = edit_middle(old_nodes, i)
        local t0 = B.now_ns()
        last = compile_chain(new_nodes, SAMPLE_RATE)
        total = total + (B.now_ns() - t0)
    end
    return total / COMPILE_ITERS, last
end

local function bench_exec(unit, block)
    block = block or BLOCK
    local src_t = float[block]
    local work_t = float[block]
    local src = terralib.new(src_t)
    local work = terralib.new(work_t)
    local state = unit.state_t ~= U.EMPTY and terralib.new(unit.state_t) or nil

    B.fill_source(src, block)

    for _ = 1, WARMUP do
        copy_buf(work, src, block)
        if state and unit.init then unit.init(state) end
        if state then
            unit.fn(work, block, state)
        else
            unit.fn(work, block)
        end
    end

    local t0 = B.now_ns()
    for _ = 1, ITERS do
        copy_buf(work, src, block)
        if state and unit.init then unit.init(state) end
    end
    local baseline = B.now_ns() - t0

    t0 = B.now_ns()
    for _ = 1, ITERS do
        copy_buf(work, src, block)
        if state and unit.init then unit.init(state) end
        if state then
            unit.fn(work, block, state)
        else
            unit.fn(work, block)
        end
    end
    local total = B.now_ns() - t0

    local net = math.max(0, total - baseline)
    return net / (ITERS * block)
end

local compile_gain_ns = bench_compile(function(i)
    return compile_gain(make_gain(-0.5 - i * 0.01), SAMPLE_RATE)
end)

local compile_biquad_ns = bench_compile(function(i)
    return compile_biquad(make_biquad(200 + i * 13, 0.707), SAMPLE_RATE)
end)

local compile_chain_ns = bench_compile(function(i)
    return compile_chain(make_chain(i), SAMPLE_RATE)
end)

local compile_gain_chain_ns = bench_compile(function(i)
    return compile_chain(make_gain_chain(i), SAMPLE_RATE)
end)

local chain_hit_nodes = make_chain(777)
local compile_chain_hit_ns = bench_compile_hit(function(nodes)
    return compile_chain(nodes, SAMPLE_RATE)
end, chain_hit_nodes)

local compile_chain_edit_ns = bench_compile_edit()

local exec_gain_ns = bench_exec(compile_gain(make_gain(-3.0), SAMPLE_RATE), BLOCK)
local exec_biquad_ns = bench_exec(compile_biquad(make_biquad(1200.0, 0.707), SAMPLE_RATE), BLOCK)
local exec_chain_ns = bench_exec(compile_chain(make_chain(1), SAMPLE_RATE), BLOCK)
local exec_gain_chain_ns = bench_exec(compile_chain(make_gain_chain(1), SAMPLE_RATE), BLOCK)
local exec_chain_small_ns = bench_exec(compile_chain(make_chain(1), SAMPLE_RATE), SMALL_BLOCK)
local exec_gain_chain_small_ns = bench_exec(compile_chain(make_gain_chain(1), SAMPLE_RATE), SMALL_BLOCK)

B.print_metrics({
    backend = "terra",
    block = BLOCK,
    small_block = SMALL_BLOCK,
    warmup = WARMUP,
    iterations = ITERS,
    compile_iterations = COMPILE_ITERS,
    chain_len = CHAIN_LEN,
    compile_gain_avg_ns = compile_gain_ns,
    compile_biquad_avg_ns = compile_biquad_ns,
    compile_chain_avg_ns = compile_chain_ns,
    compile_gain_chain_avg_ns = compile_gain_chain_ns,
    compile_chain_hit_avg_ns = compile_chain_hit_ns,
    compile_chain_edit_avg_ns = compile_chain_edit_ns,
    exec_gain_ns_per_sample = exec_gain_ns,
    exec_biquad_ns_per_sample = exec_biquad_ns,
    exec_chain_ns_per_sample = exec_chain_ns,
    exec_gain_chain_ns_per_sample = exec_gain_chain_ns,
    exec_chain_small_ns_per_sample = exec_chain_small_ns,
    exec_gain_chain_small_ns_per_sample = exec_gain_chain_small_ns,
})
