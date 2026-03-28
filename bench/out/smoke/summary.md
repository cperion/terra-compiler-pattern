# Backend benchmark matrix

Metrics directory: `bench/out/smoke`

## Scenario summary

| Scenario | Block | Chain | Warmup | Iters | Compile iters | Trials |
|---|---:|---:|---:|---:|---:|---:|
| block16k_chain32 | 16384 | 32 | 32 | 256 | 16 | 1 |
| block16k_chain8 | 16384 | 8 | 32 | 256 | 16 | 1 |
| block4k_chain8 | 4096 | 8 | 32 | 128 | 16 | 1 |

## Scenario: `block16k_chain32`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 4066.016 | 4066.016 | 3.322 | 3.322 | 1224.01x |
| biquad | 5965.969 | 5965.969 | 4.383 | 4.383 | 1361.08x |
| chain | 162337.074 | 162337.074 | 152.515 | 152.515 | 1064.40x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.040 | 0.040 | 0.317 | 0.317 | 7.83x |
| biquad | 1.925 | 1.925 | 1.965 | 1.965 | 1.02x |
| chain | 35.416 | 35.416 | 37.955 | 37.955 | 1.07x |

## Scenario: `block16k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 5583.457 | 5583.457 | 2.430 | 2.430 | 2297.54x |
| biquad | 5754.163 | 5754.163 | 4.278 | 4.278 | 1345.06x |
| chain | 39920.635 | 39920.635 | 55.767 | 55.767 | 715.84x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.036 | 0.036 | 0.260 | 0.260 | 7.19x |
| biquad | 1.926 | 1.926 | 2.149 | 2.149 | 1.12x |
| chain | 8.350 | 8.350 | 11.399 | 11.399 | 1.37x |

## Scenario: `block4k_chain8`

### Compile cost (cold average, us)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | Terra/LJ |
|---|---:|---:|---:|---:|---:|
| gain | 5032.324 | 5032.324 | 1.713 | 1.713 | 2937.30x |
| biquad | 5435.141 | 5435.141 | 3.684 | 3.684 | 1475.16x |
| chain | 40767.121 | 40767.121 | 51.560 | 51.560 | 790.67x |

### Execution cost (steady-state net, ns/sample)

| Kernel | Terra median | Terra p95 | LuaJIT median | LuaJIT p95 | LJ/Terra |
|---|---:|---:|---:|---:|---:|
| gain | 0.073 | 0.073 | 0.256 | 0.256 | 3.50x |
| biquad | 1.929 | 1.929 | 1.975 | 1.975 | 1.02x |
| chain | 8.655 | 8.655 | 9.093 | 9.093 | 1.05x |

## Interpretation

- Compile ratios are `Terra / LuaJIT`: larger means Terra pays more cold-compile cost.
- Execution ratios are `LuaJIT / Terra`: larger means pure LuaJIT is slower in steady-state execution.
- Tiny kernels like bare gain can be noisy; biquad and longer chains are usually the more meaningful indicators.
