# Backend benchmark matrix

Metrics directory: `bench/out/20260328-174313`

## Scenario summary

| Scenario | Block | Chain | Warmup | Iters | Compile iters | Trials |
|---|---:|---:|---:|---:|---:|---:|
| block16k_chain32 | 16384 | 32 | 32 | 256 | 16 | 5 |
| block16k_chain8 | 16384 | 8 | 32 | 256 | 16 | 5 |
| block4k_chain8 | 4096 | 8 | 32 | 128 | 16 | 5 |

## Scenario: `block16k_chain32`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 4374.271 | 4675.659 | 1.731 | 1.802 | 2527.38x |
| biquad | 5106.395 | 6762.372 | 2.700 | 6.427 | 1891.21x |
| chain | 152141.999 | 163803.349 | 147.329 | 151.058 | 1032.67x |
| gain-chain | 126488.888 | 145194.799 | 87.479 | 101.191 | 1445.93x |

### Compile reuse / incremental cost (us)

| Metric | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| chain memo hit | 0.381 | 0.436 | 1.507 | 1.570 | 0.25x |
| chain one-edit | 9167.068 | 9592.938 | 32.038 | 33.032 | 286.13x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.032 | 0.039 | 0.281 | 0.436 | 8.74x |
| biquad | 1.942 | 1.963 | 1.953 | 2.165 | 1.01x |
| chain | 31.480 | 31.894 | 35.453 | 39.672 | 1.13x |
| gain-chain | 0.991 | 1.026 | 8.414 | 14.892 | 8.49x |

### Small-block execution (ns/sample, block=16)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| chain small | 20.099 | 33.011 | 66.098 | 67.009 | 3.29x |
| gain-chain small | 16.100 | 116.557 | 37.639 | 38.559 | 2.34x |

## Scenario: `block16k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 4759.950 | 5705.436 | 1.604 | 1.785 | 2967.09x |
| biquad | 5739.197 | 5949.144 | 2.953 | 3.486 | 1943.47x |
| chain | 42332.070 | 43032.469 | 50.812 | 64.966 | 833.11x |
| gain-chain | 36641.314 | 39458.599 | 30.979 | 58.046 | 1182.79x |

### Compile reuse / incremental cost (us)

| Metric | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| chain memo hit | 0.548 | 0.671 | 1.354 | 1.952 | 0.40x |
| chain one-edit | 6718.157 | 7421.827 | 17.808 | 26.403 | 377.26x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.034 | 0.070 | 0.286 | 0.444 | 8.50x |
| biquad | 1.955 | 2.290 | 2.089 | 2.120 | 1.07x |
| chain | 8.019 | 8.682 | 9.672 | 9.940 | 1.21x |
| gain-chain | 0.257 | 0.278 | 2.332 | 3.544 | 9.09x |

### Small-block execution (ns/sample, block=16)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| chain small | 9.948 | 104.689 | 22.398 | 23.538 | 2.25x |
| gain-chain small | 3.060 | 5.521 | 11.743 | 12.594 | 3.84x |

## Scenario: `block4k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 4413.717 | 5244.465 | 1.592 | 1.813 | 2771.78x |
| biquad | 5460.439 | 5808.718 | 2.758 | 5.944 | 1979.63x |
| chain | 39643.861 | 43178.751 | 51.915 | 56.831 | 763.63x |
| gain-chain | 36164.919 | 37525.862 | 30.340 | 33.088 | 1191.99x |

### Compile reuse / incremental cost (us)

| Metric | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| chain memo hit | 0.482 | 1.197 | 1.487 | 1.859 | 0.32x |
| chain one-edit | 6297.669 | 6826.606 | 18.719 | 37.110 | 336.43x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.043 | 0.058 | 0.255 | 0.378 | 5.91x |
| biquad | 1.964 | 2.017 | 1.977 | 2.234 | 1.01x |
| chain | 7.892 | 7.927 | 9.127 | 9.660 | 1.16x |
| gain-chain | 0.328 | 0.356 | 2.115 | 2.170 | 6.46x |

### Small-block execution (ns/sample, block=16)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| chain small | 8.840 | 11.339 | 24.837 | 34.748 | 2.81x |
| gain-chain small | 5.474 | 9.163 | 13.507 | 14.437 | 2.47x |

## Interpretation

- Compile ratios are `Terra / LuaJIT`: larger means Terra pays more cold-compile cost.
- Execution ratios are `LuaJIT / Terra`: larger means pure LuaJIT is slower in steady-state execution.
- Tiny kernels like bare gain can be noisy; biquad and longer chains are usually the more meaningful indicators.
