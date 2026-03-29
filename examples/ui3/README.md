# ui3

`ui3` is the fresh architecture line for the red-teamed UI compiler rewrite.

## Status

This directory is currently a scaffold:

- `ui3_asdl.lua` combines the stable top/source-side UI language with the new
  lower architecture
- `ui3_schema.lua` is stub-only
- `ui3_redesign_asdl_sketch.lua` preserves the current exploratory sketch

No live compiler or backend implementation is installed yet.

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
terra unit.t status examples/ui3/ui3_schema.lua
```

### LuaJIT

```bash
luajit unit.lua status examples/ui3/ui3_schema.lua
```
