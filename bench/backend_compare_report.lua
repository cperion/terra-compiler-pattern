#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local B = require("bench.backend_bench_common")

local terra_metrics = assert(arg[1], "usage: luajit bench/backend_compare_report.lua terra_metrics.txt luajit_metrics.txt")
local lj_metrics = assert(arg[2], "usage: luajit bench/backend_compare_report.lua terra_metrics.txt luajit_metrics.txt")

local terra = B.parse_metrics(terra_metrics)
local lj = B.parse_metrics(lj_metrics)

local function ratio(a, b)
    if not a or not b or b == 0 then return 0 end
    return a / b
end

local function line(label, terra_v, lj_v, fmt, ratio_label, ratio_value)
    io.write(string.format("%-24s terra=%-18s luajit=%-18s %s=%.2fx\n",
        label,
        fmt(terra_v),
        fmt(lj_v),
        ratio_label,
        ratio_value))
end

io.write("Backend benchmark\n")
io.write(string.format("block=%d warmup=%d iterations=%d chain_len=%d compile_iters=%d\n\n",
    terra.block or lj.block,
    terra.warmup or lj.warmup,
    terra.iterations or lj.iterations,
    terra.chain_len or lj.chain_len,
    terra.compile_iterations or lj.compile_iterations))

io.write("Compile cost (cold average)\n")
line("gain compile", terra.compile_gain_avg_ns, lj.compile_gain_avg_ns, B.fmt_us, "terra/lj", ratio(terra.compile_gain_avg_ns, lj.compile_gain_avg_ns))
line("biquad compile", terra.compile_biquad_avg_ns, lj.compile_biquad_avg_ns, B.fmt_us, "terra/lj", ratio(terra.compile_biquad_avg_ns, lj.compile_biquad_avg_ns))
line("chain compile", terra.compile_chain_avg_ns, lj.compile_chain_avg_ns, B.fmt_us, "terra/lj", ratio(terra.compile_chain_avg_ns, lj.compile_chain_avg_ns))
if terra.compile_gain_chain_avg_ns and lj.compile_gain_chain_avg_ns then
    line("gain-chain compile", terra.compile_gain_chain_avg_ns, lj.compile_gain_chain_avg_ns, B.fmt_us, "terra/lj", ratio(terra.compile_gain_chain_avg_ns, lj.compile_gain_chain_avg_ns))
end

if terra.compile_chain_hit_avg_ns and lj.compile_chain_hit_avg_ns then
    io.write("\nCompile reuse / incremental cost\n")
    line("chain memo hit", terra.compile_chain_hit_avg_ns, lj.compile_chain_hit_avg_ns, B.fmt_us, "terra/lj", ratio(terra.compile_chain_hit_avg_ns, lj.compile_chain_hit_avg_ns))
    line("chain one-edit", terra.compile_chain_edit_avg_ns, lj.compile_chain_edit_avg_ns, B.fmt_us, "terra/lj", ratio(terra.compile_chain_edit_avg_ns, lj.compile_chain_edit_avg_ns))
end

io.write("\nExecution cost (steady-state net)\n")
line("gain exec", terra.exec_gain_ns_per_sample, lj.exec_gain_ns_per_sample, B.fmt_ns_per_sample, "lj/terra", ratio(lj.exec_gain_ns_per_sample, terra.exec_gain_ns_per_sample))
line("biquad exec", terra.exec_biquad_ns_per_sample, lj.exec_biquad_ns_per_sample, B.fmt_ns_per_sample, "lj/terra", ratio(lj.exec_biquad_ns_per_sample, terra.exec_biquad_ns_per_sample))
line("chain exec", terra.exec_chain_ns_per_sample, lj.exec_chain_ns_per_sample, B.fmt_ns_per_sample, "lj/terra", ratio(lj.exec_chain_ns_per_sample, terra.exec_chain_ns_per_sample))
if terra.exec_gain_chain_ns_per_sample and lj.exec_gain_chain_ns_per_sample then
    line("gain-chain exec", terra.exec_gain_chain_ns_per_sample, lj.exec_gain_chain_ns_per_sample, B.fmt_ns_per_sample, "lj/terra", ratio(lj.exec_gain_chain_ns_per_sample, terra.exec_gain_chain_ns_per_sample))
end
if terra.exec_chain_small_ns_per_sample and lj.exec_chain_small_ns_per_sample then
    io.write(string.format("\nSmall-block execution (steady-state net, block=%d)\n", terra.small_block or lj.small_block or 0))
    line("chain small", terra.exec_chain_small_ns_per_sample, lj.exec_chain_small_ns_per_sample, B.fmt_ns_per_sample, "lj/terra", ratio(lj.exec_chain_small_ns_per_sample, terra.exec_chain_small_ns_per_sample))
    line("gain-chain small", terra.exec_gain_chain_small_ns_per_sample, lj.exec_gain_chain_small_ns_per_sample, B.fmt_ns_per_sample, "lj/terra", ratio(lj.exec_gain_chain_small_ns_per_sample, terra.exec_gain_chain_small_ns_per_sample))
end

io.write("\nInterpretation\n")
io.write("- compile ratios > 1 mean Terra compilation is more expensive than LuaJIT closure construction.\n")
io.write("- chain memo hit measures the cost of asking for the same compiled subtree again after memoization is warm.\n")
io.write("- chain one-edit measures one incremental rebuild where only the middle node changes and siblings are structurally reused.\n")
io.write("- execution ratios > 1 mean LuaJIT is slower than Terra for steady-state sample processing.\n")
io.write("- gain-chain isolates composition/call overhead more than arithmetic-heavy alternating chains do.\n")
io.write("- small-block execution surfaces dispatch/composition overhead that large blocks can hide.\n")
