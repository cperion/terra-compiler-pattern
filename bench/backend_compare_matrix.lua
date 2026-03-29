#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local B = require("bench.backend_bench_common")

local out_dir = assert(arg[1], "usage: luajit bench/backend_compare_matrix.lua <metrics_dir>")

local function list_metric_files(dir)
    local cmd = string.format("find %q -type f -name '*.metrics' | sort", dir)
    local p = assert(io.popen(cmd, "r"))
    local files = {}
    for line in p:lines() do
        files[#files + 1] = line
    end
    p:close()
    return files
end

local function median(xs)
    if #xs == 0 then return 0 end
    local copy = {}
    for i = 1, #xs do copy[i] = xs[i] end
    table.sort(copy)
    local n = #copy
    if n % 2 == 1 then return copy[math.floor((n + 1) / 2)] end
    local mid = math.floor(n / 2)
    return 0.5 * (copy[mid] + copy[mid + 1])
end

local function percentile(xs, p)
    if #xs == 0 then return 0 end
    local copy = {}
    for i = 1, #xs do copy[i] = xs[i] end
    table.sort(copy)
    local idx = math.max(1, math.min(#copy, math.floor((#copy - 1) * p + 1.5)))
    return copy[idx]
end

local function ratio(a, b)
    if not a or not b or b == 0 then return 0 end
    return a / b
end

local files = list_metric_files(out_dir)
assert(#files > 0, "no .metrics files found in " .. out_dir)

local data = {}

for _, path in ipairs(files) do
    local base = path:match("([^/]+)$") or path
    local scenario, backend, trial = base:match("^(.-)%.([^.]+)%.(%d+)%.metrics$")
    if scenario and (backend == "terra" or backend == "luajit") and trial then
        data[scenario] = data[scenario] or {}
        data[scenario][backend] = data[scenario][backend] or {}
        data[scenario][backend][tonumber(trial)] = B.parse_metrics(path)
    end
end

local scenarios = {}
for name, _ in pairs(data) do scenarios[#scenarios + 1] = name end
table.sort(scenarios)

local compile_metrics = {
    { key = "compile_gain_avg_ns", label = "gain" },
    { key = "compile_biquad_avg_ns", label = "biquad" },
    { key = "compile_chain_avg_ns", label = "chain" },
    { key = "compile_gain_chain_avg_ns", label = "gain-chain" },
}

local incremental_compile_metrics = {
    { key = "compile_chain_hit_avg_ns", label = "chain memo hit" },
    { key = "compile_chain_edit_avg_ns", label = "chain one-edit" },
}

local exec_metrics = {
    { key = "exec_gain_ns_per_sample", label = "gain" },
    { key = "exec_biquad_ns_per_sample", label = "biquad" },
    { key = "exec_chain_ns_per_sample", label = "chain" },
    { key = "exec_gain_chain_ns_per_sample", label = "gain-chain" },
}

local exec_small_metrics = {
    { key = "exec_chain_small_ns_per_sample", label = "chain small" },
    { key = "exec_gain_chain_small_ns_per_sample", label = "gain-chain small" },
}

local function gather_values(trials, key)
    local xs = {}
    for _, metrics in pairs(trials or {}) do
        if metrics[key] then xs[#xs + 1] = metrics[key] end
    end
    table.sort(xs)
    return xs
end

local function scenario_config(trials)
    for _, metrics in pairs(trials or {}) do
        return metrics
    end
    return {}
end

local function metric_present(scenario, key)
    local terra_trials = data[scenario].terra or {}
    local lj_trials = data[scenario].luajit or {}
    for _, metrics in pairs(terra_trials) do
        if metrics[key] ~= nil then return true end
    end
    for _, metrics in pairs(lj_trials) do
        if metrics[key] ~= nil then return true end
    end
    return false
end

io.write("# Backend benchmark matrix\n\n")
io.write("Metrics directory: `" .. out_dir .. "`\n\n")
io.write("## Scenario summary\n\n")
io.write("| Scenario | Block | Chain | Warmup | Iters | Compile iters | Trials |\n")
io.write("|---|---:|---:|---:|---:|---:|---:|\n")
for _, scenario in ipairs(scenarios) do
    local terra_trials = data[scenario].terra or {}
    local cfg = scenario_config(terra_trials)
    local ntrials = 0
    for _, _ in pairs(terra_trials) do ntrials = ntrials + 1 end
    io.write(string.format("| %s | %d | %d | %d | %d | %d | %d |\n",
        scenario,
        cfg.block or 0,
        cfg.chain_len or 0,
        cfg.warmup or 0,
        cfg.iterations or 0,
        cfg.compile_iterations or 0,
        ntrials))
end
io.write("\n")

for _, scenario in ipairs(scenarios) do
    io.write("## Scenario: `" .. scenario .. "`\n\n")

    io.write("### Compile cost (cold average, us)\n\n")
    io.write("| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |\n")
    io.write("|---|---:|---:|---:|---:|---:|\n")
    for _, metric in ipairs(compile_metrics) do
        if metric_present(scenario, metric.key) then
            local terra_xs = gather_values(data[scenario].terra, metric.key)
            local lj_xs = gather_values(data[scenario].luajit, metric.key)
            local terra_med = median(terra_xs) / 1000.0
            local terra_p95 = percentile(terra_xs, 0.95) / 1000.0
            local lj_med = median(lj_xs) / 1000.0
            local lj_p95 = percentile(lj_xs, 0.95) / 1000.0
            io.write(string.format("| %s | %.3f | %.3f | %.3f | %.3f | %.2fx |\n",
                metric.label,
                terra_med,
                terra_p95,
                lj_med,
                lj_p95,
                ratio(terra_med, lj_med)))
        end
    end
    io.write("\n")

    if metric_present(scenario, "compile_chain_hit_avg_ns") then
        io.write("### Compile reuse / incremental cost (us)\n\n")
        io.write("| Metric | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |\n")
        io.write("|---|---:|---:|---:|---:|---:|\n")
        for _, metric in ipairs(incremental_compile_metrics) do
            if metric_present(scenario, metric.key) then
                local terra_xs = gather_values(data[scenario].terra, metric.key)
                local lj_xs = gather_values(data[scenario].luajit, metric.key)
                local terra_med = median(terra_xs) / 1000.0
                local terra_p95 = percentile(terra_xs, 0.95) / 1000.0
                local lj_med = median(lj_xs) / 1000.0
                local lj_p95 = percentile(lj_xs, 0.95) / 1000.0
                io.write(string.format("| %s | %.3f | %.3f | %.3f | %.3f | %.2fx |\n",
                    metric.label,
                    terra_med,
                    terra_p95,
                    lj_med,
                    lj_p95,
                    ratio(terra_med, lj_med)))
            end
        end
        io.write("\n")
    end

    io.write("### Execution cost (steady-state net, ns/sample)\n\n")
    io.write("| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |\n")
    io.write("|---|---:|---:|---:|---:|---:|\n")
    for _, metric in ipairs(exec_metrics) do
        if metric_present(scenario, metric.key) then
            local terra_xs = gather_values(data[scenario].terra, metric.key)
            local lj_xs = gather_values(data[scenario].luajit, metric.key)
            local terra_med = median(terra_xs)
            local terra_p95 = percentile(terra_xs, 0.95)
            local lj_med = median(lj_xs)
            local lj_p95 = percentile(lj_xs, 0.95)
            io.write(string.format("| %s | %.3f | %.3f | %.3f | %.3f | %.2fx |\n",
                metric.label,
                terra_med,
                terra_p95,
                lj_med,
                lj_p95,
                ratio(lj_med, terra_med)))
        end
    end
    io.write("\n")

    if metric_present(scenario, "exec_chain_small_ns_per_sample") then
        local cfg = scenario_config(data[scenario].terra or {})
        io.write(string.format("### Small-block execution (ns/sample, block=%d)\n\n", cfg.small_block or 0))
        io.write("| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |\n")
        io.write("|---|---:|---:|---:|---:|---:|\n")
        for _, metric in ipairs(exec_small_metrics) do
            if metric_present(scenario, metric.key) then
                local terra_xs = gather_values(data[scenario].terra, metric.key)
                local lj_xs = gather_values(data[scenario].luajit, metric.key)
                local terra_med = median(terra_xs)
                local terra_p95 = percentile(terra_xs, 0.95)
                local lj_med = median(lj_xs)
                local lj_p95 = percentile(lj_xs, 0.95)
                io.write(string.format("| %s | %.3f | %.3f | %.3f | %.3f | %.2fx |\n",
                    metric.label,
                    terra_med,
                    terra_p95,
                    lj_med,
                    lj_p95,
                    ratio(lj_med, terra_med)))
            end
        end
        io.write("\n")
    end
end

io.write("## Interpretation\n\n")
io.write("- Compile ratios are `Terra / LuaJIT`: larger means Terra pays more cold-compile cost.\n")
io.write("- Execution ratios are `LuaJIT / Terra`: larger means pure LuaJIT is slower in steady-state execution.\n")
io.write("- Tiny kernels like bare gain can be noisy; biquad and longer chains are usually the more meaningful indicators.\n")
