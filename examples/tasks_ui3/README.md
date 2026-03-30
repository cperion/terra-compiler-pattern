# tasks_ui3

`tasks_ui3` is a host project showing how one unit module family can target another module family's ASDL inside one combined context.

## What is being plugged together

- `examples/tasks/tasks_asdl.lua`
  - task-domain authored/app/view phases
- `examples/ui3/schema/app.asdl`
  - ui3 UI target language and downstream compiler phases

The important connection is not runtime integration.
It is an explicit typed boundary chain inside one installed ASDL context:

```text
TaskApp.State
  -> project_view
TaskView.Screen
  -> lower
UiDecl.Document
  -> bind
UiBound.Document
  -> flatten
UiFlat.Scene
  -> ... ui3 downstream ...
```

So the "plug" is:

- task-domain phases produce `TaskView.Screen`
- `TaskView.Screen:lower()` produces `UiDecl.Document`
- ui3 takes over from `UiDecl` downward

## Why this exists

This example demonstrates the current composition mechanism:

- declare project dependencies with `deps`
- load dependency schema families into the same context first
- install dependency semantic boundaries plus active-backend artifacts automatically
- install host-local boundaries after that
- connect the families with explicit typed boundaries

## Files

- `schema/10_tasks.lua`
  - contributes the task ASDL text
- `pipeline.lua`
  - combined phase order
- `unit_project.lua`
  - declares `deps = { "../ui3" }` and installs the task-side boundaries locally

Because `ui3` is imported as a dependency, Terra consumers transparently load ui3 Terra backend artifacts and LuaJIT consumers transparently load ui3 LuaJIT backend artifacts.

## Try it

```bash
terra unit.t status examples/tasks_ui3
terra unit.t boundaries examples/tasks_ui3
luajit unit.lua status examples/tasks_ui3
```
