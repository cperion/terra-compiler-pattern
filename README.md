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
- `docs/unit-api.md`
- `terra-compiler-pattern.md`
- `unit.t`
- `AGENTS.md`

Additional backend notes:

- `docs/luajit-backend.md`
- `docs/luajit-leaf-rules.md`
- `docs/gen-param-state-machine.md`
- `docs/unit-shared-core-refactor-plan.md`
- `docs/backend-benchmarks.md`

## Runtime split

The runtime vocabulary is now split into small layers.

### Shared pure layer

- `unit_core.lua`

Backend-independent helpers:

- canonical `gen / param / state` traversal helpers
- explicit `Machine` descriptors via:
  - `U.machine_step(...)`
  - `U.machine_iter(...)`
  - `U.machine_run(...)`
  - `U.machine_iterate(...)`
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
- Terra `Machine -> Unit` realization (`U.machine_to_unit`)
- terminal auto-realization when a Terra terminal returns a `Machine`
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
- explicit `Machine -> Unit` realization (`U.machine_to_unit`)
- terminal auto-realization when a LuaJIT terminal returns a `Machine`
- direct realization of callable step and iter machines
- FFI/cdata state layouts for production leaves
- LuaJIT hot-slot swapping
- Lua callback application loop
- shared project/schema/inspect support through `unit.lua`

## Project conventions

`unit` now supports convention-first project loading.

Preferred project shape:

```text
myproj/
  schema/
    app.asdl
  pipeline.lua
  unit_project.lua   # optional, also used for deps/imports
  boundaries/
    ui_bound_document.lua
    ui_bound_document_test.lua
    ui_bound_document_bench.lua
    ui_bound_document_profile.lua
```

Default layout is **flat**. Optional tree layout is enabled with `unit_project.lua`:

```lua
return {
    layout = "tree",
}
```

Flat type paths use a single underscore separator and lower-snake casing:

- `UiBound.Document` -> `boundaries/ui_bound_document.lua`
- `UiBound.Document` test -> `boundaries/ui_bound_document_test.lua`

Canonical semantic artifact kinds per receiver type:

- `impl`
- `test`
- `bench`
- `profile`

Canonical backend artifact examples:

- `ui_machine_render_gen_luajit.lua`
- `ui_machine_render_gen_terra.t`
- `ui_machine_render_gen_luajit_bench.lua`
- `ui_machine_render_gen_terra_bench.t`

Useful CLI commands:

```bash
terra unit.t init myproj --layout flat
terra unit.t status myproj
terra unit.t path myproj UiBound.Document
terra unit.t backends myproj
terra unit.t backend-path myproj UiMachine.RenderGen terra bench
terra unit.t scaffold-file myproj UiBound.Document
terra unit.t scaffold-project myproj --all-artifacts
```

Legacy `U.spec { ... }` support has been removed. Use project directories or direct `.asdl` schema files.

Projects may also declare dependencies in `unit_project.lua`:

```lua
return {
    deps = {
        "../ui3",
    },
}
```

`unit` loads dependency schemas first and then installs dependency backend artifacts for the active backend automatically.

## Examples

Convention-first inspect example:

- `examples/inspect/demo_project`

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
- Terra inspect/status/scaffold smoke checks for the convention-first project loader
