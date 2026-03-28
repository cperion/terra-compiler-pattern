# LuaJIT Backend

This repository's architecture is not Terra-only.

The deeper point is stronger: the so-called Terra Compiler Pattern is not fundamentally about Terra. It is about:

- source ASDL
- pure transitions
- memoized boundaries
- terminal compilation to `Unit`
- hot swap / execution

Terra is one backend that realizes these Units explicitly through quotes and LLVM. LuaJIT is another backend that realizes them through closures, FFI state, and trace compilation. In a JIT-native runtime, much of the backend compiler is already available; our job is to emit terminal code that is ultra-monomorphic and specialization-friendly.

LuaJIT is now a real backend in its own right in this repository, and should usually be the default backend on JIT-native platforms. Terra remains the opt-in strong backend when explicit staging, static native layout, ABI control, or LLVM-native optimization are worth the extra cost.

## Files

- `unit_core.lua` — shared pure helper layer
- `unit_inspect_core.lua` — shared inspection helper layer
- `unit_luajit.lua` — LuaJIT backend
- `examples/luajit/luajit_synth.lua`
- `examples/luajit/luajit_biquad.lua`
- `examples/luajit/luajit_app_demo.lua`

## Unit meaning on LuaJIT

On Terra:

- `Unit.fn` is a Terra function
- `Unit.state_t` is a Terra type

On LuaJIT:

- `Unit.fn` is a specialized Lua function of shape `fn(state, ...)`
- `Unit.state_t` is a layout descriptor with `alloc()` and `release()`

This preserves the same architectural split:

- compiled artifact
- state ownership
- structural composition
- installation via hot swap

So the same application can keep one source ASDL, one reducer, one transition pipeline, and one view projection, while selecting either a Terra backend or a LuaJIT backend for realization.

## What is shared with Terra

The following concepts are shared across backends:

- `U.transition`
- `U.terminal`
- `U.with_fallback`
- `U.with_errors`
- `U.errors`
- `U.match`
- `U.with`
- LuaFun-style traversal helpers
- inspection/reflection helpers

## What differs from Terra

LuaJIT uses:

- closure capture instead of Terra quotes
- FFI/table state instead of Terra struct types
- callback/table swapping instead of Terra pointer globals
- JIT tracing instead of LLVM codegen

## Tradeoffs

### LuaJIT strengths

- much smaller runtime footprint
- fast startup
- no LLVM dependency
- practical for prototyping and many non-SIMD workloads
- same compiler-pattern architecture
- in scalar DSP-style kernels, often surprisingly close to Terra when the code shape is monomorphic enough

### Terra strengths

- explicit staging
- explicit native ABI
- Terra struct synthesis in `Unit.compose`
- LLVM optimization and vectorization
- stronger design pressure through explicit types and staging
- strongest backend when you need predictable native code generation rather than host-JIT specialization

## Running the backend examples

From the repository root:

```bash
luajit examples/luajit/luajit_synth.lua
luajit examples/luajit/luajit_biquad.lua
luajit examples/luajit/luajit_app_demo.lua
```

## Tests

Shared tests:

```bash
make test-shared
```

Examples + smoke tests:

```bash
make test-examples
make test-all
```
