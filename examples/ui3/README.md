# ui3

`ui3` is the fresh architecture line for the red-teamed UI compiler rewrite.

## Status

This directory is currently a scaffold with the first Layer-0 Terra leaf work started:

- `schema/app.asdl`, `pipeline.lua`, `unit_project.lua`, and lower-snake receiver files under `boundaries/` are now the primary project surface
- benchmark entrypoints now load the project directly with `U.load_inspect_spec("examples/ui3")`
- former installer modules are now routed through receiver-owned boundary files; `_old` modules remain only as parked migration references
- `ui3_asdl_old.lua` remains in the tree as the old generated-string source and migration reference
- `ui3_redesign_asdl_sketch.lua` preserves the current exploratory sketch
- `backends/terra_layer0_unit.t` is the raw backend-facing Unit benchmark leaf
- `ui3_layer0_bench.t` benchmarks Layer 0 directly
- `ui3_layer1_bench.t` benchmarks the canonical `gen / param / state` layer
- `ui3_layer2_bench.t` benchmarks `UiRenderScene -> schedule_render_machine_ir`
- `ui3_layer3_bench.t` benchmarks `UiGeometry + UiRenderFacts -> project_render_scene`
- `ui3_bind_bench.t` benchmarks `UiDecl -> bind -> UiBound`
- `ui3_flatten_bench.t` benchmarks `UiBound -> flatten -> UiFlat`
- `ui3_layer4_render_bench.t` benchmarks `UiFlat -> lower_render_facts`
- `ui3_query_bench.t` benchmarks the query branch:
  - `UiFlat -> lower_query_facts`
  - `UiGeometry + UiQueryFacts -> project_query_scene`
  - `UiQueryScene -> organize_query_machine_ir`
- `ui3_apply_bench.t` benchmarks the query-machine consumer:
  - `UiSession.State:apply_with_intents(query_ir, event)`

Current schema boundary coverage is now `16/16`.

## Workflow rule

`ui3` should be built bottom-up:

1. trust Layer 0: raw backend-facing `Unit { fn, state_t }`
2. benchmark it until it is fast enough to trust
3. only then move to Layer 1: canonical `gen / param / state`
4. if the next trusted boundary is slow, audit the ASDL above it

## Current target architecture

```text
UiDecl
  -> bind
UiBound
  -> flatten
UiFlat

UiFlat
  -> lower_geometry
UiGeometryInput
  -> solve
UiGeometry

UiFlat
  -> lower_render_facts
UiRenderFacts

UiFlat
  -> lower_query_facts
UiQueryFacts

UiGeometry + UiRenderFacts
  -> project_render_scene
UiRenderScene
  -> schedule_render_machine_ir
UiRenderMachineIR
  -> define_machine
UiMachine.Render
  -> Unit

UiGeometry + UiQueryFacts
  -> project_query_scene
UiQueryScene
  -> organize_query_machine_ir
UiQueryMachineIR
  -> reducer/query execution
```

## Design notes

The strongest design discoveries carried into `ui3` are:

- shared flat headers (`UiFlatShape.RegionHeader`, `UiFlatShape.NodeHeader`)
- `UiFlat` as aligned facet planes rather than a giant mixed lowered node
- `UiGeometryInput` as a true solver-facing language
- `UiGeometry` as the shared solved coupling point
- explicit render/query occurrence scenes before machine organization

## Caution

The custom-family story is still the least-settled part of the design and
should remain easy to revise during implementation.

## Schema tooling

### Terra

```bash
terra unit.t status examples/ui3
terra unit.t path examples/ui3 UiDecl.Document
terra unit.t scaffold-file examples/ui3 UiDecl.Document
```

### LuaJIT

```bash
luajit unit.lua status examples/ui3
```
