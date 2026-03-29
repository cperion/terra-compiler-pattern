# Backend Benchmarks

This repository now includes a direct Terra vs LuaJIT backend benchmark.

## Goal

Measure several different costs separately:

1. **cold compile cost**
   - Terra: quote construction + LLVM compilation
   - LuaJIT: closure construction / memoized terminal creation

2. **warm memo-hit compile cost**
   - asking for the same compiled subtree again after memoization is already warm

3. **incremental one-edit rebuild cost**
   - compile an old chain
   - edit one middle node while structurally reusing siblings
   - measure the cost of recompiling the edited chain

4. **steady-state execution cost**
   - sample processing throughput after warmup
   - reported as `ns/sample`

5. **small-block steady-state execution cost**
   - same idea as steady-state throughput, but with a tiny block size to surface dispatch/composition overhead that large blocks can hide

This gives practical intelligence on the tradeoff:

- Terra usually pays more to compile
- LuaJIT usually pays more to execute

Current repository-level conclusion:

- **LuaJIT should usually be the default backend** on JIT-native platforms because compile/build cost is dramatically cheaper
- **Terra remains the opt-in strong backend** where explicit staging, exact native layout, ABI control, or stronger LLVM-native optimization justify the extra compile tax

## Files

- `bench/backend_bench_common.lua`
- `bench/backend_terra.t`
- `bench/backend_luajit.lua`
- `bench/backend_compare_report.lua`
- `bench/run_backend_compare.sh`

## What is benchmarked

The benchmark now exercises several kernel shapes on both backends:

- `gain`
- `biquad`
- `chain` — alternating biquads and gains through the backend's real `U.compose` path
- `gain-chain` — a stateless composition-heavy chain used to expose compose/call overhead more directly

In addition to cold compile and large-block execution, the benchmark also reports:

- `chain memo hit`
- `chain one-edit`
- small-block execution metrics

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
- `BENCH_SMALL_BLOCK` default `16`
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

### Cold compile section

Reported as average time per cold compile.

- ratios are shown as `terra/lj`
- values greater than `1x` mean Terra compilation costs more than LuaJIT closure construction

### Compile reuse / incremental section

Reported as average time per warm memo hit or one-edit incremental rebuild.

- `chain memo hit` asks for the exact same compiled chain again after the cache is warm
- `chain one-edit` recompiles a new chain where only the middle node changed and all siblings were structurally reused
- ratios are shown as `terra/lj`

### Execution section

Reported as net `ns/sample` after subtracting buffer reset baseline.

- ratios are shown as `lj/terra`
- values greater than `1x` mean LuaJIT is slower than Terra in steady-state sample processing
- `gain-chain` is especially useful for exposing composition/call overhead with little arithmetic hiding it
- small-block execution is especially useful for surfacing dispatch/composition overhead that large blocks can hide

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

- how expensive is Terra cold compile here?
- how cheap are warm memo hits on each backend?
- how much does a one-node incremental edit really cost?
- how expensive is LuaJIT execution here?
- how much overhead is hidden by large block sizes?
- where is the crossover for your workload?

That is the useful intelligence.

In other words, the benchmark is most useful for deciding where the architecture should stay on LuaJIT by default and where a terminal family should deliberately opt into Terra.
