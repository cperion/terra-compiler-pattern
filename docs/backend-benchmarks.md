# Backend Benchmarks

This repository now includes a direct Terra vs LuaJIT backend benchmark.

## Goal

Measure two different costs separately:

1. **cold compile cost**
   - Terra: quote construction + LLVM compilation
   - LuaJIT: closure construction / memoized terminal creation

2. **steady-state execution cost**
   - sample processing throughput after warmup
   - reported as `ns/sample`

This gives practical intelligence on the tradeoff:

- Terra usually pays more to compile
- LuaJIT usually pays more to execute

## Files

- `bench/backend_bench_common.lua`
- `bench/backend_terra.t`
- `bench/backend_luajit.lua`
- `bench/backend_compare_report.lua`
- `bench/run_backend_compare.sh`

## What is benchmarked

Three kernels are measured on both backends:

- `gain`
- `biquad`
- `chain`

The chain is an alternating sequence of biquads and gains built through the backend's real `U.compose` path.

So the benchmark exercises:

- `U.terminal`
- backend leaf compilation
- backend state ownership
- backend composition
- hot numeric execution loops

## Running

Quick single-run comparison:

```bash
make bench-backends
```

Heavier multi-scenario matrix with repeated trials and markdown tables:

```bash
make bench-backends-heavy
```

or directly:

```bash
./bench/run_backend_compare.sh
./bench/run_backend_compare_heavy.sh
```

## Environment variables

You can tune the benchmark size:

- `BENCH_BLOCK` default `16384`
- `BENCH_WARMUP` default `64`
- `BENCH_ITERS` default `256`
- `BENCH_COMPILE_ITERS` default `64`
- `BENCH_SR` default `48000`
- `BENCH_CHAIN_LEN` default `8`

Example:

```bash
BENCH_BLOCK=65536 BENCH_ITERS=512 make bench-backends
```

The heavy runner writes raw metrics plus a markdown summary to:

- `bench/out/<timestamp>/summary.md`

## Reading the report

### Compile section

Reported as average time per cold compile.

- ratios are shown as `terra/lj`
- values greater than `1x` mean Terra compilation costs more than LuaJIT closure construction

### Execution section

Reported as net `ns/sample` after subtracting buffer reset baseline.

- ratios are shown as `lj/terra`
- values greater than `1x` mean LuaJIT is slower than Terra in steady-state sample processing

The heavy matrix report prints one table per scenario with:

- Terra median and p95
- LuaJIT median and p95
- direct slowdown / speedup ratios

## Important interpretation note

This benchmark is meant to compare backend behavior, not to prove a universal absolute truth.

It measures this repository's current backend implementations with:

- current composition strategy
- current state layout strategy
- current warmup policy
- current compiler heuristics

So the benchmark should be used as an architectural instrument:

- how expensive is Terra compile time here?
- how expensive is LuaJIT execution here?
- where is the crossover for your workload?

That is the useful intelligence.
