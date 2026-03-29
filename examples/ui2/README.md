# ui2

`ui2` is the backend-neutral UI compiler spine.

## Architecture

Pure/compiler-side modules are shared across backends and now live as ordinary Lua modules:

- `ui2_asdl.lua`
- `ui2_schema.lua`
- `ui2_decl_document.lua`
- `ui2_bound_document.lua`
- `ui2_flat_scene.lua`
- `ui2_demand_scene.lua`
- `ui2_solved_scene.lua`
- `ui2_plan_scene.lua`
- `ui2_session_state.lua`

These implement the typed compiler/reducer spine:

- `UiDecl -> bind -> UiBound`
- `UiBound -> flatten -> UiFlat`
- `UiFlat -> prepare_demands -> UiDemand`
- `UiDemand -> solve -> UiSolved`
- `UiSolved -> plan -> UiPlan`
- `UiPlan -> specialize_kernel -> UiKernel.Render`
- `UiKernel.Spec -> compile -> Unit`
- `UiKernel.Payload -> materialize -> state load`

## Backend leaves

Only the render/backend leaves differ by runtime.

### ui2 backend namespace

- `examples.ui2.backends.terra_kernel_render`
- `examples.ui2.backends.luajit_kernel_render`

### shared UI backend namespace

- `examples.ui.backends.terra_sdl_gl`
- `examples.ui.backends.luajit_sdl_gl`
- `examples.ui.backends.text_sdl_ttf`

The schema selects the render leaf by runtime:

- under Terra: install the Terra render leaf
- under LuaJIT: install the LuaJIT render leaf

Both leaves keep the same Unit contract:

- `Unit { fn, state_t }`
- typed source/phase data above the leaf
- typed backend state below the leaf

On LuaJIT specifically, production leaves are expected to lower to monomorphic code over FFI/cdata-backed state and payload layouts. Opaque runtime tables are not part of the intended backend contract.

So the ASDL, reducer, transitions, planning, and app/view structure stay the same.

## Demo entrypoints

### Terra

```bash
terra examples/ui2/ui2_demo.t
```

### LuaJIT

```bash
luajit examples/ui2/ui2_demo_luajit.lua
```

## Schema tooling

The backend-neutral `unit.lua` front door now works for both runtimes.

### Terra

```bash
terra unit.t status examples/ui2/ui2_schema.lua
```

### LuaJIT

```bash
luajit unit.lua status examples/ui2/ui2_schema.lua
```

## Naming policy

- shared pure compiler code: `.lua`
- Terra-only leaves: `.t`
- LuaJIT-only leaves: `.lua`
- backend selection should happen at the leaf boundary, not in the pure phases

That keeps the repository aligned with the updated compiler-pattern framing:

> LuaJIT by default, Terra by opt-in, shared pure spine, backend-specific leaves.
