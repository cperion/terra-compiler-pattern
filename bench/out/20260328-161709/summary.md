# Backend benchmark matrix

Metrics directory: `bench/out/20260328-161709`

## Scenario summary

| Scenario | Block | Chain | Warmup | Iters | Compile iters | Trials |
|---|---:|---:|---:|---:|---:|---:|
| block16k_chain32 | 16384 | 32 | 32 | 256 | 16 | 3 |
| block16k_chain8 | 16384 | 8 | 32 | 256 | 16 | 3 |
| block4k_chain8 | 4096 | 8 | 32 | 128 | 16 | 3 |

## Scenario: `block16k_chain32`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 5246.178 | 5683.058 | 2.476 | 4.951 | 2118.92x |
| biquad | 5306.056 | 5530.857 | 4.773 | 8.126 | 1111.74x |
| chain | 156728.578 | 157833.980 | 168.895 | 416.081 | 927.97x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.039 | 0.039 | 0.562 | 1.193 | 14.61x |
| biquad | 2.082 | 2.159 | 2.652 | 4.819 | 1.27x |
| chain | 32.047 | 32.615 | 42.066 | 71.633 | 1.31x |

## Scenario: `block16k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 5121.626 | 5281.597 | 1.915 | 1.957 | 2673.78x |
| biquad | 5408.111 | 5432.256 | 3.224 | 3.720 | 1677.36x |
| chain | 40039.239 | 40096.455 | 53.696 | 55.881 | 745.67x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.036 | 0.051 | 0.293 | 0.367 | 8.10x |
| biquad | 2.114 | 2.215 | 2.311 | 2.365 | 1.09x |
| chain | 7.992 | 8.996 | 10.532 | 10.555 | 1.32x |

## Scenario: `block4k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 5197.176 | 5585.451 | 1.926 | 2.172 | 2698.25x |
| biquad | 5237.852 | 6770.541 | 3.440 | 3.487 | 1522.55x |
| chain | 40135.523 | 40417.112 | 52.506 | 56.140 | 764.40x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.027 | 0.077 | 0.284 | 0.420 | 10.37x |
| biquad | 2.090 | 2.188 | 2.208 | 2.809 | 1.06x |
| chain | 7.755 | 10.075 | 10.887 | 11.347 | 1.40x |

## Interpretation

- Compile ratios are `Terra / LuaJIT`: larger means Terra pays more cold-compile cost.
- Execution ratios are `LuaJIT / Terra`: larger means pure LuaJIT is slower in steady-state execution.
- Tiny kernels like bare gain can be noisy; biquad and longer chains are usually the more meaningful indicators.
