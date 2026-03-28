# Backend benchmark matrix

Metrics directory: `bench/out/20260328-163813`

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
| gain | 4172.635 | 4973.435 | 1.987 | 2.303 | 2100.10x |
| biquad | 5041.123 | 5523.133 | 3.399 | 3.792 | 1483.17x |
| chain | 143661.451 | 145434.563 | 132.619 | 170.942 | 1083.27x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.035 | 0.041 | 0.256 | 0.484 | 7.25x |
| biquad | 2.090 | 2.304 | 1.951 | 2.243 | 0.93x |
| chain | 31.701 | 34.135 | 35.727 | 41.691 | 1.13x |

## Scenario: `block16k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 4387.655 | 4434.402 | 1.782 | 2.869 | 2462.90x |
| biquad | 4817.679 | 5171.724 | 2.963 | 4.666 | 1625.91x |
| chain | 35174.932 | 36749.292 | 50.194 | 83.140 | 700.78x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.041 | 0.043 | 0.256 | 0.431 | 6.28x |
| biquad | 1.951 | 2.254 | 2.020 | 2.285 | 1.04x |
| chain | 7.923 | 8.239 | 9.225 | 9.779 | 1.16x |

## Scenario: `block4k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 4566.829 | 4752.213 | 1.880 | 2.647 | 2428.68x |
| biquad | 4821.447 | 5514.505 | 4.081 | 6.218 | 1181.49x |
| chain | 36093.029 | 38008.827 | 50.424 | 57.742 | 715.79x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.053 | 0.102 | 0.249 | 0.444 | 4.71x |
| biquad | 1.975 | 1.998 | 1.960 | 2.349 | 0.99x |
| chain | 7.896 | 8.179 | 8.971 | 9.773 | 1.14x |

## Interpretation

- Compile ratios are `Terra / LuaJIT`: larger means Terra pays more cold-compile cost.
- Execution ratios are `LuaJIT / Terra`: larger means pure LuaJIT is slower in steady-state execution.
- Tiny kernels like bare gain can be noisy; biquad and longer chains are usually the more meaningful indicators.
