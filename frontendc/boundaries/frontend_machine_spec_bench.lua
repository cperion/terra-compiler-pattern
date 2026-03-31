local ffi = require("ffi")
local Fixture = require("frontendc.frontend_machine_fixture")

ffi.cdef[[
    typedef struct { long tv_sec; long tv_nsec; } frontendc_bench_timespec_t;
    int clock_gettime(int clk_id, frontendc_bench_timespec_t *tp);
]]

local ts = ffi.new("frontendc_bench_timespec_t")
local CLOCK_MONOTONIC = 1

local function now_s()
    ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
end

local function bench_avg_ms(iters, fn)
    local warm = math.min(iters, 50)
    local sink = 0
    for i = 1, warm do sink = sink + fn(i) end
    collectgarbage("collect")
    collectgarbage("collect")
    local t0 = now_s()
    for i = 1, iters do sink = sink + fn(i) end
    local t1 = now_s()
    return ((t1 - t0) * 1000) / iters, sink
end

return function(T, U, P)
    local benches = {}

    function benches.bench_emit_lua()
        local machine = select(1, Fixture.new_tokenize_machine_and_target_ctx(T))
        local iters = 500
        local avg_ms = bench_avg_ms(iters, function()
            local out = machine:emit_lua()
            return #out.files
        end)
        print(string.format("frontendc emit_lua bench iters=%d avg_ms=%.6f", iters, avg_ms))
    end

    function benches.bench_install_generated()
        local machine, target_ctx = Fixture.new_tokenize_machine_and_target_ctx(T)
        local iters = 200
        local avg_ms = bench_avg_ms(iters, function()
            local fresh_ctx = {
                TargetText = { Spec = {} },
                TargetToken = target_ctx.TargetToken,
                TargetSource = target_ctx.TargetSource,
            }
            machine:install_generated(fresh_ctx)
            return (type(fresh_ctx.TargetText.Spec.tokenize) == "function") and 1 or 0
        end)
        print(string.format("frontendc install_generated bench iters=%d avg_ms=%.6f", iters, avg_ms))
    end

    function benches.bench_tokenize_runtime()
        local machine, target_ctx = Fixture.new_tokenize_machine_and_target_ctx(T)
        machine:install_generated(target_ctx)
        local lines = { "# comment" }
        for i = 1, 200 do
            lines[#lines + 1] = "module Demo" .. tostring(i) .. " {"
            lines[#lines + 1] = "  Inner" .. tostring(i)
            lines[#lines + 1] = "}"
        end
        local text = table.concat(lines, "\n")
        local iters = 1000
        local input_pool = {}
        for i = 1, iters + 64 do
            input_pool[i] = { text = text }
        end
        local next_idx = 0
        local avg_ms = bench_avg_ms(iters, function()
            next_idx = next_idx + 1
            return #target_ctx.TargetText.Spec.tokenize(input_pool[next_idx]).items
        end)
        local mb_per_s = (#text / (1024 * 1024)) / (avg_ms / 1000)
        print(string.format(
            "frontendc tokenize runtime bench iters=%d bytes=%d avg_ms=%.6f throughput_mb_s=%.3f",
            iters,
            #text,
            avg_ms,
            mb_per_s
        ))
    end

    function benches.bench_parse_runtime()
        local machine, target_ctx = Fixture.new_tokenize_machine_and_target_ctx(T)
        machine:install_generated(target_ctx)
        local token_input = target_ctx.TargetText.Spec.tokenize({ text = "module Demo { Inner }" })
        local iters = 5000
        local input_pool = {}
        for i = 1, iters + 64 do
            input_pool[i] = token_input
        end
        local next_idx = 0
        local avg_ms = bench_avg_ms(iters, function()
            next_idx = next_idx + 1
            return (target_ctx.TargetToken.Spec.parse(input_pool[next_idx]).root.name == "Demo") and 1 or 0
        end)
        print(string.format("frontendc parse runtime bench iters=%d avg_ms=%.6f", iters, avg_ms))
    end

    function benches.bench_full_runtime()
        local machine, target_ctx = Fixture.new_tokenize_machine_and_target_ctx(T)
        machine:install_generated(target_ctx)
        local text = "module Demo { Inner }"
        local iters = 3000
        local input_pool = {}
        for i = 1, iters + 64 do
            input_pool[i] = { text = text }
        end
        local next_idx = 0
        local avg_ms = bench_avg_ms(iters, function()
            next_idx = next_idx + 1
            local token_spec = target_ctx.TargetText.Spec.tokenize(input_pool[next_idx])
            return (target_ctx.TargetToken.Spec.parse(token_spec).root.inner == "Inner") and 1 or 0
        end)
        print(string.format("frontendc full runtime bench iters=%d avg_ms=%.6f", iters, avg_ms))
    end

    return benches
end
