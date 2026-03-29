# Backend benchmark matrix

Metrics directory: `bench/out/20260328-174036`

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
| gain | 3685.671 | 4459.342 | 1.988 | 2.533 | 1854.43x |
| biquad | 5056.728 | 5499.123 | 4.158 | 6.944 | 1216.02x |
| chain | 147445.846 | 156075.900 | 122.979 | 138.096 | 1198.95x |
| gain-chain | 124399.686 | 130611.257 | 81.826 | 107.851 | 1520.29x |

### Compile reuse / incremental cost (us)

| Metric | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| chain memo hit | 0.750 | 2.103 | 1.508 | 1.560 | 0.50x |
| chain one-edit | 9110.762 | 9494.735 | 28.800 | 31.217 | 316.34x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.031 | 0.038 | 0.254 | 0.680 | 8.14x |
| biquad | 1.928 | 1.943 | 1.998 | 2.010 | 1.04x |
| chain | 31.142 | 31.481 | 35.105 | 38.905 | 1.13x |
| gain-chain | 0.982 | 0.984 | 8.598 | 14.408 | 8.75x |

### Small-block execution (ns/sample, block=16)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| chain small | 30.663 | 36.404 | 64.714 | 67.104 | 2.11x |
| gain-chain small | 14.086 | 17.406 | 36.700 | 37.771 | 2.61x |

## Scenario: `block16k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 4103.330 | 4220.801 | 2.011 | 3.614 | 2040.19x |
| biquad | 4971.969 | 5113.580 | 3.389 | 9.018 | 1467.14x |
| chain | 36056.409 | 37157.800 | 49.346 | 54.013 | 730.69x |
| gain-chain | 31946.458 | 33686.158 | 31.457 | 38.170 | 1015.57x |

### Compile reuse / incremental cost (us)

| Metric | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| chain memo hit | 1.004 | 1.607 | 1.323 | 3.961 | 0.76x |
| chain one-edit | 6201.204 | 6342.106 | 16.976 | 24.291 | 365.29x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.032 | 0.033 | 0.263 | 0.581 | 8.27x |
| biquad | 1.928 | 1.964 | 1.919 | 1.935 | 1.00x |
| chain | 7.777 | 7.888 | 9.087 | 9.563 | 1.17x |
| gain-chain | 0.249 | 0.252 | 2.045 | 3.485 | 8.21x |

### Small-block execution (ns/sample, block=16)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| chain small | 7.734 | 11.733 | 19.827 | 20.979 | 2.56x |
| gain-chain small | 1.778 | 3.156 | 10.995 | 11.482 | 6.18x |

## Scenario: `block4k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 4067.884 | 4127.537 | 1.893 | 2.455 | 2148.98x |
| biquad | 5091.696 | 5206.017 | 3.821 | 5.410 | 1332.60x |
| chain | 36458.405 | 37556.132 | 47.869 | 53.417 | 761.62x |
| gain-chain | 31434.401 | 32397.267 | 30.492 | 34.086 | 1030.90x |

### Compile reuse / incremental cost (us)

| Metric | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| chain memo hit | 0.498 | 0.967 | 1.393 | 1.829 | 0.36x |
| chain one-edit | 6035.066 | 6727.303 | 15.125 | 18.023 | 399.00x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.033 | 0.058 | 0.421 | 0.422 | 12.57x |
| biquad | 1.922 | 1.957 | 1.939 | 1.960 | 1.01x |
| chain | 7.811 | 10.878 | 9.437 | 10.429 | 1.21x |
| gain-chain | 0.339 | 0.358 | 3.467 | 3.633 | 10.21x |

### Small-block execution (ns/sample, block=16)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| chain small | 1.864 | 141.535 | 27.630 | 28.873 | 14.82x |
| gain-chain small | 3.796 | 6.198 | 13.385 | 16.667 | 3.53x |

## Interpretation

- Compile ratios are `Terra / LuaJIT`: larger means Terra pays more cold-compile cost.
- Execution ratios are `LuaJIT / Terra`: larger means pure LuaJIT is slower in steady-state execution.
- Tiny kernels like bare gain can be noisy; biquad and longer chains are usually the more meaningful indicators.
