# Terra Compiler Pattern

This repository models interactive software as a compiler:

- source ASDL is the user-facing program
- events are the input language
- `apply` is the pure reducer
- transitions narrow unresolved knowledge across phases
- terminals compile phase-local ASDL into `Unit`
- execution runs compiled artifacts until the source changes again

The key discovery in this repository is that the pattern is **not actually Terra-specific**. Terra is one backend — a very strong one — for realizing specialized `Unit`s through LLVM. But the architecture itself is backend-neutral. In a JIT-native runtime like LuaJIT, much of the backend compiler is already present; the main task is to produce terminal code that is ultra-monomorphic and specialization-friendly.

Current backend policy:

- **LuaJIT by default** on JIT-native platforms
- **Terra by opt-in** when explicit staging, static native layout, ABI control, or LLVM-native optimization are worth the extra compile/build cost

The detailed design docs remain the source of truth:

- `modeling-programs-as-compilers.md`
- `terra-compiler-pattern.md`
- `unit.t`
- `AGENTS.md`

Additional backend notes:

- `docs/luajit-backend.md`
- `docs/luajit-leaf-rules.md`
- `docs/unit-shared-core-refactor-plan.md`
- `docs/backend-benchmarks.md`

## Runtime split

The runtime vocabulary is now split into small layers.

### Shared pure layer

- `unit_core.lua`

Backend-independent helpers:

- LuaFun traversal helpers
- pure memoize wrapper shape
- `with_fallback`
- `with_errors`
- `errors`
- `match`
- `with`

### Shared inspection layer

- `unit_inspect_core.lua`

Backend-independent schema/reflection helpers used by inspection and scaffolding.

### Terra backend

- `unit.t`

Owns Terra-specific behavior as the opt-in explicit-native backend:

- Terra `Unit` construction
- ABI validation
- Terra quote composition
- Terra state struct synthesis
- Terra hot-swap pointers
- Terra application loop

### Shared application architecture

Both backends can host the same application architecture:

- same source ASDL
- same Event ASDL
- same reducer
- same transitions
- same terminal structure
- same view projection

The backend only changes how `Unit`s are realized, installed, and executed.

### LuaJIT backend

- `unit_luajit.lua`
- `unit.lua`
- `unit_schema.lua`

Owns LuaJIT-specific behavior:

- closure-based leaf compilation
- FFI/cdata state layouts for production leaves
- LuaJIT hot-slot swapping
- Lua callback application loop
- shared schema/spec/inspect support through `unit.lua`

## Examples

LuaJIT examples live in:

- `examples/luajit/luajit_synth.lua`
- `examples/luajit/luajit_biquad.lua`
- `examples/luajit/luajit_app_demo.lua`
- `examples/ui2/ui2_demo_luajit.lua`

Run from the repository root, e.g.:

```bash
luajit examples/luajit/luajit_synth.lua
luajit examples/luajit/luajit_biquad.lua
luajit examples/luajit/luajit_app_demo.lua
```

## Tests

Shared pure/backend smoke tests:

```bash
make test-shared
```

Example smoke tests:

```bash
make test-examples
```

Everything together:

```bash
make test-all
```

Backend benchmark:

```bash
make bench-backends
make bench-backends-heavy
```

Direct scripts:

```bash
./tests/run_shared_tests.sh
./tests/run_example_smokes.sh
./tests/unit_backend_bench_smoke.sh
```

`test-shared` runs:

- shared pure helper tests
- shared inspection helper tests
- LuaJIT backend smoke tests
- Terra shared-layer smoke tests

`test-examples` runs:

- LuaJIT synth example
- LuaJIT biquad example
- LuaJIT app loop example
- Terra inspect/status/scaffold smoke checks
