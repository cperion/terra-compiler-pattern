# unit API

This document is the concrete API reference for the `unit` framework.

Use it together with:

- `modeling-programs-as-compilers.md` for the architecture and modeling method
- this document for the actual framework surface, signatures, contracts, and conventions

The goal is that these two documents together are sufficient to understand and use the framework without reading scattered source comments first.

---

## 1. What `unit` is

`unit` is the reusable framework layer for the compiler pattern described in `modeling-programs-as-compilers.md`.

It provides:

- backend-independent pure helpers
- memoized boundaries
- structural error helpers
- ASDL helpers
- schema inspection and project loading
- backend-specific `Unit { fn, state_t }` realization for:
  - LuaJIT
  - Terra

The core architectural split is:

- **Layer 1: domain**
  - your source ASDL, Event ASDL, reducer, phases, projections, machine IR
- **Layer 2: pattern**
  - `Unit`, `transition`, `terminal`, `match`, `with`, errors, inspection, project conventions
- **Layer 3: backend**
  - how a leaf becomes executable on LuaJIT vs Terra

`unit` mostly spans Layers 2 and 3.

---

## 2. Module map

### `unit.lua`
Backend-selecting entrypoint.

Behavior:

- chooses backend by `UNIT_BACKEND=terra|luajit` if set
- otherwise selects:
  - Terra when `terralib` is present
  - LuaJIT otherwise
- exposes the selected backend as `require("unit")`
- when run as a script, dispatches to `U.cli(...)`

### `unit_core.lua`
Backend-independent pure layer.

Owns:

- iteration helpers
- memoization wrappers
- memo diagnostics
- error collection helpers
- ASDL helpers like `U.match` and `U.with`

### `unit_inspect_core.lua`
Backend-independent schema inspection / reflection layer.

Owns:

- boundary discovery
- status reports
- markdown generation
- type graph generation
- prompt generation
- scaffold generation

### `unit_schema.lua`
Convention-first project loading and CLI support.

Owns:

- project loading from directories or direct `.asdl`
- file path conventions
- boundary installation from `boundaries/`
- project-wide inspection entrypoints
- scaffold-file / scaffold-project / CLI commands

### `unit_luajit.lua`
LuaJIT backend realization.

Owns:

- `Unit { fn, state_t }` realization with closures
- FFI-backed state layouts
- state composition
- hot slots
- application loop

### `unit.t`
Terra backend realization.

Owns:

- `Unit { fn, state_t }` realization with Terra functions and Terra types
- ABI validation
- Terra leaf/build helpers
- Terra composition helpers
- Terra hot-slot pointer swapping
- Terra application loop

---

## 3. Entry and loading model

### 3.1 Normal application import

#### LuaJIT
```lua
local U = require("unit")
```

#### Terra
```lua
local U = require("unit")
```

Both forms are intended to work.

### 3.2 Running the CLI

#### LuaJIT
```bash
luajit unit.lua status examples/ui3
```

#### Terra
```bash
terra unit.t status examples/ui3
```

Both use the same `unit_schema.lua` project/inspection layer.

---

## 4. The core architectural contract

The important framework contract is:

```text
Unit { fn, state_t }
```

Where:

- `fn` is executable behavior
- `state_t` is the owned runtime state layout

The backend changes the representation of those two things, but not their meaning.

### 4.1 Canonical machine

Terminals should be designed around:

- **gen** — execution rule / code-shaping part
- **param** — stable machine input
- **state** — mutable runtime-owned state

`Unit { fn, state_t }` is the packaged backend artifact, not the conceptual starting point.

### 4.2 Public normalization status

Currently normalized across backends:

- `U.new(fn, state_t)`
- `U.leaf(state_t, fn)`
- `U.silent()`
- `U.memoize`, `U.transition`, `U.terminal`
- `U.hot_slot(...)`
- `U.app(...)`

Still backend-specific in surface details:

- state layout construction APIs
- backend-specific realization helpers such as `U.leaf_quote(...)` and `U.compose_quote(...)`

This is intentional current truth, not hidden behavior.

---

## 5. Shared pure API (`unit_core.lua`)

These functions exist across both backends because both backends build on `unit_core.lua`.

---

## 5.1 Iteration and traversal helpers

These are specialized traversal helpers used heavily throughout the framework.
They are preferred over LuaFun in framework internals.

### `U.rawiter(obj, param?, state?)`
Returns the raw `gen, param, state` triple for an iterable object.

Supports:

- plain arrays
- plain maps
- custom iterables carrying `gen / param / state`
- tables with `__ipairs` / `__pairs`
- generator functions

Use when you need direct canonical iteration machinery.

### `U.iter(obj, param?, state?)`
Wraps something iterable into a `gen / param / state` iterator object.

### `U.wrap(gen, param, state)`
Builds an iterator wrapper directly from a `gen, param, state` triple.

### `U.each(xs, fn)`
Iterate through `xs`, calling `fn` on each item.

Behavior:

- arrays: `fn(value)`
- maps: `fn(key, value)`
- generic iterables: forwards yielded values

### `U.fold(xs, fn, init)`
Fold / reduce over `xs`.

### `U.map(xs, fn)`
Map `xs` into a new array.

### `U.copy(xs)`
Shallow copy into a new array using `U.map` semantics.

### `U.map_into(dst, xs, fn)`
Map `xs` into existing destination array `dst`.

Useful when avoiding temporary arrays.

### `U.filter_map_into(dst, xs, fn)`
Map `xs` into `dst`, skipping `nil` results.

### `U.find(xs, pred)`
Return the first item satisfying `pred`, or `nil`.

### `U.any(xs, pred?)`
True if any item satisfies `pred`.
If `pred` is omitted, checks truthiness.

### `U.all(xs, pred?)`
True if all items satisfy `pred`.
If `pred` is omitted, checks truthiness.

### `U.reverse_each(xs, fn)`
Reverse iterate over an array.

### `U.each_name(tables, fn?)`
Collect the unique keys from one or more tables, sort them, and return them.
If `fn` is given, also iterates those names.

Used heavily in inspection/schema code.

---

## 5.2 Memoized boundary wrappers

These are the fundamental pure boundary wrappers.

### `U.memoize(name_or_fn, maybe_fn?)`
Memoize a pure function.

Accepted forms:

```lua
local f = U.memoize(function(x) ... end)
local f = U.memoize("name", function(x) ... end)
```

### `U.transition(name_or_fn, maybe_fn?)`
Memoized ASDL → ASDL boundary.

Use for:

- `bind`
- `resolve`
- `classify`
- `flatten`
- `schedule`
- `project`

### `U.terminal(name_or_fn, maybe_fn?)`
Memoized ASDL → `Unit` boundary.

Use for terminal compilation.

### Naming behavior
If no explicit name is supplied, `unit_core` infers one from debug info where possible.

---

## 5.3 Memo diagnostics

### `U.memo_stats(memoized_fn)`
Return the tracked stats table for a memoized function.

Fields include:

- `name`
- `kind`
- `calls`
- `hits`
- `misses`
- `unique_keys`
- `last_miss_reason`

### `U.memo_inspector()`
Returns an inspector object.

Important methods:

- `track(memoized_fn)`
- `stats()`
- `reset()`
- `report()`
- `measure_edit(description, fn)`
- `quality()`
- `diagnose()`

### `U.memo()`
Convenience alias returning `U.memo_inspector()`.

### `U.memo_report()`
Render the global memo report as text.

### `U.memo_quality()`
Render a memo-quality assessment string.

### `U.memo_diagnose()`
Render memo diagnostic advice.

### `U.memo_measure_edit(description, fn)`
Measure boundary misses/reuse for a representative edit.

### `U.memo_reset()`
Reset tracked memo stats.

---

## 5.4 Error helpers

### `U.with_fallback(fn, neutral)`
Wrap a function and return `neutral` if it errors.

### `U.with_errors(fn)`
Wrap a function that expects an `errs` collector as its first argument.
Returns:

```lua
result, errs_or_nil
```

### `U.errors()`
Create a structural error collector.

Returned object methods:

#### `errs:each(items, fn, ref_field?, neutral_fn?)`
Map a list of children through `fn`, collecting failures into the local error list.

If a child fails:

- error is recorded
- fallback value comes from:
  - `neutral_fn(item)` if supplied
  - otherwise `U.silent()` if available
  - otherwise `nil`

#### `errs:call(target, fn, neutral_fn?)`
Call `fn(target)` with structural error capture.

#### `errs:merge(child_errs)`
Append an existing error list.

#### `errs:get()`
Return accumulated errors, or `nil` if empty.

---

## 5.5 ASDL helpers

### `U.match(value, arms)`
Exhaustive sum-type dispatch.

Rules:

- `value.kind` must exist
- if ASDL metadata exposes variants, all variants must be present in `arms`
- errors if a variant is missing

Use this for all sum-type dispatch in pure code.

### `U.with(node, overrides)`
Rebuild an ASDL node of the same type with selected fields overridden.

This preserves structural style and avoids in-place mutation.

### `U.register_asdl_resolver(fn)`
Register an ASDL metatable resolver for cases where ordinary metatable lookup is insufficient.

Mostly framework-level support.

---

## 6. LuaJIT backend API (`unit_luajit.lua`)

This is the current default execution backend on JIT-native platforms.

---

## 6.1 State layouts

LuaJIT state layouts are explicit runtime layout descriptors, not plain types.

### `U.EMPTY`
Empty state layout.

Fields:

- `kind = "empty"`
- `alloc()`
- `release()`

### `U.state(alloc, release?, kind?)`
Create a custom state layout descriptor.

Arguments:

- `alloc`: required function
- `release`: optional function
- `kind`: optional descriptive tag

Returns a layout descriptor with:

- `kind`
- `alloc`
- `release`

### `U.state_table(init?, release?)`
Debug/scaffolding helper.

Allocates ordinary Lua table state.

Not intended for production hot leaves.

### `U.state_ffi(ctype, opts?)`
Production state helper for typed FFI-backed state.

Arguments:

- `ctype`: FFI ctype or ctype string
- `opts.init(state)?`
- `opts.release(state)?`

### `U.state_compose(children)`
Compose child `state_t` layouts structurally.

Behavior:

- returns `U.EMPTY` if all children are stateless
- otherwise allocates an array-like parent state table containing each child's allocated state in child order
- release walks children in reverse order

---

## 6.2 Unit construction

### `U.new(fn, state_t?)`
Validate and package a LuaJIT Unit.

Rules:

- `fn` must be callable
- `state_t` must be `U.EMPTY` or a layout descriptor with `alloc/release`

Returns:

```lua
{ fn = fn, state_t = state_t }
```

### `U.silent()`
Return a no-op stateless Unit.

### `U.leaf(state_t, fn)`
Normalized leaf packaging.

This is the normal leaf form on LuaJIT.

Example:

```lua
local State_t = U.state_ffi("struct { float phase; }")

local osc = U.leaf(State_t, function(state, buf, n)
    -- mutate state, write to buf
end)
```

---

## 6.3 Composition

### `U.compose(children, fn)`
Normalized composed Unit packaging.

Arguments:

- `children`: array of child Units
- `fn`: realized Lua function expecting `(state, ...)`

Behavior:

- parent `state_t` is `U.state_compose(children)`
- packages the realized function as one composed Unit

### `U.compose_closure(children, body)`
LuaJIT-specific composition realization helper.

Arguments:

- `children`: array of child Units
- `body(state, kids, ...)`

`kids[i]` contains:

- `fn`
- `state_t`
- `has_state`
- `state(parent_state)`
- `call(parent_state, ...)`

This helper builds the closure first, then packages it through normalized `U.compose(children, fn)`.

### `U.compose_linear(children)`
Build a sequential composition that simply runs child functions in order.

Useful when the parent adds no extra control logic beyond a straight sequence.

### `U.chain(children)`
Alias for `U.compose_linear(children)`.

---

## 6.4 Hot swap and app loop

### `U.hot_slot()`
Create a hot-swappable slot.

Returned object methods / fields:

- `callback(...)`
- `swap(unit)`
- `peek()`
- `collect()`
- `close()`

Behavior:

- allocates state for newly installed Units
- retires old `(unit, state)` pairs
- `collect()` releases retired states
- `close()` releases everything and installs a silent Unit

### `U.app(config)`
Run the standard application loop.

Required config fields:

- `initial()`
- `apply(state, event)`

Optional fields:

- `outputs`
- `compile`
- `start`
- `stop`
- `poll`

Behavior:

1. create output slots
2. build initial state
3. compile each output
4. start each output driver
5. poll/apply/recompile until `state.running == false` or polling ends
6. stop drivers and release slots

The loop shape is:

```text
poll -> apply -> compile -> execute
```

---

## 7. Terra backend API (`unit.t`)

Terra is the opt-in explicit-native backend.

---

## 7.1 State representation

In Terra, `state_t` is directly a Terra type.

### `U.EMPTY`
A stateless empty Terra tuple type.

### Stateful leaves
Use a Terra struct type directly:

```lua
struct FilterState { x1 : float; x2 : float; y1 : float; y2 : float }
```

That type becomes the Unit's `state_t`.

---

## 7.2 Unit construction

### `U.new(fn, state_t?)`
Validate and package a Terra Unit.

Rules enforced:

1. `fn` must be a Terra function
2. if state is non-empty, `fn` must take `&state_t`
3. `fn:compile()` is forced immediately

Returns:

```lua
{ fn = terra_fn, state_t = terra_type }
```

### `U.silent()`
No-op stateless Terra Unit.

### `U.leaf(state_t, fn)`
Normalized backend-agnostic leaf packaging.

This no longer builds Terra code. It packages an already-built Terra function as a Unit.

Example:

```lua
struct CounterState { total : int32 }

local terra accum(x : int32, state : &CounterState)
    state.total = state.total + x
    return state.total
end

local unit = U.leaf(CounterState, accum)
```

### `U.leaf_quote(state_t, params, body)`
Terra-specific leaf realization helper.

Use this when you want `unit` to build the Terra function from symbols + quote body.

Arguments:

- `state_t`: Terra type or `nil`
- `params`: `terralib.newlist(...)` of symbols
- `body(state_sym, params)` returning a Terra quote

Example:

```lua
local x = symbol(int32, "x")
local unit = U.leaf_quote(nil, terralib.newlist({ x }), function(_, params)
    return quote
        return [params[1]] * 2
    end
end)
```

---

## 7.3 Composition

### `U.state_compose(children)`
Return the composed Terra state type for a set of children.

Behavior:

- synthesizes a Terra struct type with one field per non-empty child state
- returns `U.EMPTY` if all children are stateless

### `U.compose(children, fn)`
Normalized composed Unit packaging.

Arguments:

- `children`: child Units
- `fn`: realized Terra function

Behavior:

- derives composed `state_t` from children
- packages the realized function as a Unit
- attaches composed child lifecycle when children define `init` / `release`

### `U.compose_quote(children, params, body)`
Terra-specific composition realization helper.

Arguments:

- `children`: child Units
- `params`: Terra symbol list
- `body(state_sym, kids, params)` returning a Terra quote

Annotated children include:

- `fn`
- `state_t`
- `has_state`
- `state_expr`
- `call(...)`

This helper builds the Terra function first, then packages it through normalized `U.compose(children, fn)`.

---

## 7.4 Memoization and terminals

Terra owns backend-specific versions of:

- `U.memoize(...)`
- `U.transition(...)`
- `U.terminal(...)`

These route through `terralib.memoize`.

The architectural meaning is the same as in `unit_core`, but Terra uses Terra's identity caching for implementation.

---

## 7.5 Hot slots

### `U.hot_slot(fn_type)`
Create a Terra hot-swap render slot.

Arguments:

- `fn_type`: Terra function type

Returned table fields:

- `callback`
- `swap(unit)`
- `render_ptr`
- `state_ptr`

Intended use:

- a long-lived Terra callback is registered with the driver
- edit-time recompilation swaps the function pointer and state pointer behind it

---

## 7.6 Application loop

### `U.app(config)`
Terra version of the universal app loop.

Requires:

- `outputs = { name = fn_type, ... }`
- `compile = { name = compiler_fn, ... }`
- `start = { name = start_fn, ... }`
- `initial()`
- `poll()`
- `apply(state, event)`

The Terra backend uses hot slots with explicit callback pointers.

---

## 8. Schema / project API (`unit_schema.lua`)

This is the convention-first project loader and CLI layer.

---

## 8.1 File helpers

### `U.read_file(path)`
Read file bytes as text.

### `U.normalize_asdl_text(text)`
Normalize ASDL text for the current ASDL loader.

Current behavior includes converting `--` comments into `#`-style ASDL comments at line starts.

### `U.read_asdl_file(path)`
Read file and normalize as ASDL text.

### `U.is_asdl_class(value)`
True if `value` looks like an installed ASDL class.

---

## 8.2 Stub installation

### `U.stub(boundary_name?)`
Return a not-implemented function.

### `U.install_stubs(ctx, plan)`
Install stub methods into an ASDL context.

`plan` supports:

```lua
{
    ["Phase"] = "lower",
    ["Phase.Type"] = { "bind", "flatten" },
}
```

Use this when the boundary inventory is known but implementation is not ready.

---

## 8.3 Project model

### `U.normalize_project(project)`
Normalize a project config.

Normalized fields include:

- `kind = "UnitProject"`
- `root`
- `source_kind`
- `layout = "flat" | "tree"`
- `schema_root`
- `boundary_root`
- `schema_paths`
- `pipeline`
- `phases`
- `stubs`
- `install`
- `deps`

### `U.load_project(source)`
Load a project from:

- a project directory
- a direct `.asdl` file

Legacy `.lua/.t` spec sources are removed.

### Project dependencies

A project may declare:

```lua
return {
    deps = {
        "../ui3",
        { source = "../tasks" },
    },
}
```

Dependency behavior:

- dependency schemas are loaded into the same context first
- dependency semantic boundaries are installed before host-local boundaries
- backend-specific dependency artifacts are selected automatically for the active backend
  - Terra consumer -> `_terra`
  - LuaJIT consumer -> `_luajit`

### `U.install_project_boundaries(project, ctx)`
Load and install implementation files from `boundaries/`.

For a project with dependencies, installation is recursive in dependency order.

Installation order:

1. dependency semantic boundaries
2. dependency backend artifacts for active backend
3. host semantic boundaries
4. host backend artifacts for active backend

Boundary module contract:

- returns `function(T, U, P) ... end`
- or `{ install = function(T, U, P) ... end }`

---

## 8.4 Path conventions

### `U.project_type_artifact_path(project, fqname, kind?)`
Return canonical file path for a receiver type artifact.

Kinds:

- `impl`
- `test`
- `bench`
- `profile`

Default convention:

- flat layout
- lower-snake filenames

Examples:

- `UiDecl.Document` -> `boundaries/ui_decl_document.lua`
- `UiDecl.Document`, `test` -> `boundaries/ui_decl_document_test.lua`

Tree layout uses lower-snake path parts:

- `UiDecl.Document` -> `boundaries/ui_decl/document.lua`

### Convenience wrappers

- `U.project_type_path(project, fqname)`
- `U.project_type_test_path(project, fqname)`
- `U.project_type_bench_path(project, fqname)`
- `U.project_type_profile_path(project, fqname)`

### Backend artifact paths

### `U.project_type_backend_artifact_path(project, fqname, backend, kind?)`
Return canonical path for a backend-specific receiver artifact.

Backends:

- `luajit`
- `terra`

Kinds:

- `impl`
- `test`
- `bench`
- `profile`

Examples:

- `UiMachine.RenderGen`, `luajit` -> `boundaries/ui_machine_render_gen_luajit.lua`
- `UiMachine.RenderGen`, `terra` -> `boundaries/ui_machine_render_gen_terra.t`
- `UiMachine.RenderGen`, `terra`, `bench` -> `boundaries/ui_machine_render_gen_terra_bench.t`

### Convenience wrappers

- `U.project_type_backend_path(project, fqname, backend)`
- `U.project_type_backend_test_path(project, fqname, backend)`
- `U.project_type_backend_bench_path(project, fqname, backend)`
- `U.project_type_backend_profile_path(project, fqname, backend)`

---

## 8.5 Inspection/project entrypoints

### `U.project_inspect_spec(project)`
Load schema, install stubs/installers/boundaries, and return:

```lua
{
    project = project,
    ctx = ctx,
    phases = phases,
    pipeline = pipeline,
}
```

### `U.load_inspect_spec(source)`
Load project from source and return the inspect spec above.

### `U.inspect_from(source)`
Convenience wrapper that returns the final inspection object.

Also attaches project/backend artifact inventory derived from project conventions.

Equivalent conceptual flow:

```lua
local spec = U.load_inspect_spec(source)
local I = U.inspect(spec.ctx, spec.phases, spec.pipeline)
```

---

## 8.6 Scaffolding

### `U.scaffold_type_artifact(project, I, selector, kind?)`
Scaffold one receiver artifact.

`selector` may be:

- fully-qualified type name
- boundary name like `UiDecl.Document:bind`

Returns:

```lua
text, receiver
```

### `U.scaffold_project(project, I, opts?)`
Write scaffold files for all receivers that currently expose boundaries.

Options:

- `with_test = true`
- `with_bench = true`
- `with_profile = true`
- `all_artifacts = true`
- `force = true`

Returns a list of written file records.

---

## 8.7 CLI

### `U.cli_usage()`
Return CLI usage text.

### `U.cli(argv?)`
Run the CLI dispatcher.

Supported commands:

- `init <dir> [--layout flat|tree]`
- `status <source>`
- `markdown <source>`
- `pipeline <source>`
- `boundaries <source>`
- `backends <source>`
- `path <source> <type-or-boundary> [impl|test|bench|profile]`
- `backend-path <source> <type-or-boundary> <luajit|terra> [impl|test|bench|profile]`
- `type-graph <source> <root> [max_depth]`
- `prompt <source> <boundary> [max_depth]`
- `scaffold <source> <boundary>`
- `scaffold-all <source>`
- `scaffold-file <source> <type-or-boundary> [impl|test|bench|profile]`
- `scaffold-project <source> [--with-test] [--with-bench] [--with-profile] [--all-artifacts] [--force]`
- `test-all <source>`

---

## 9. Inspection API (`unit_inspect_core.lua`)

This is the reflection object returned by `U.inspect(...)` or `U.inspect_from(...)`.

---

## 9.1 Top-level entry

### `U.inspect(ctx, phases?, pipeline_phases?)`
Return an inspection object `I`.

Typical use:

```lua
local I = U.inspect_from("examples/ui3")
print(I.status())
```

---

## 9.2 Inspection object fields

Common fields include:

- `I.ctx`
- `I.phases`
- `I.pipeline_phases`
- `I.types`
- `I.types_by_phase`
- `I.type_map`
- `I.basename_map`
- `I.boundaries`
- `I.boundaries_by_phase`
- `I.boundary_counts_by_phase`
- `I.phase_primary_verbs`
- `I.project` when created via `inspect_from`
- `I.backend_inventory` when created via `inspect_from`

---

## 9.3 Inspection methods

### `I.find_boundary(boundary_name)`
Return one boundary record, or `nil`.

### `I.resolve_type_name(type_name, phase_name?)`
Resolve a possibly-short type name into a fully-qualified type name.

### `I.is_stub(boundary)`
True if boundary appears to be a not-implemented stub.

### `I.progress()`
Return inventory / coverage info.

Includes totals like:

- `type_total`
- `record_total`
- `enum_total`
- `variant_total`
- `boundary_total`
- `boundary_real`
- `boundary_stub`
- `boundary_coverage`
- `by_phase`

### `I.pipeline()`
Return the phase-edge summary list.

Each edge includes:

- `from`
- `to`
- `verb`
- `count`

### `I.type_graph(root_type, max_depth?)`
Render a markdown-ish type graph from a root type.

### `I.prompt_for(boundary_name, max_depth?)`
Render an implementation prompt for a boundary.

### `I.markdown()`
Render full schema/boundary markdown.

### `I.test_all()`
Return a simple coverage summary over discovered boundaries.

### `I.scaffold(boundary_name)`
Return a boundary scaffold snippet for a specific boundary.

### `I.status()`
Render the human-readable inventory / boundary coverage report.

### `I.backends()`
Return backend artifact inventory for receiver types discovered from boundary coverage.

Current inventory includes:

- `receivers`
- `items`
- `totals.by_backend.luajit`
- `totals.by_backend.terra`

### `I.backend_status()`
Render a compact backend artifact coverage summary.

---

## 10. Composing multiple ASDL families in one host project

There is not yet a first-class project dependency/import system in `unit`.

The current honest way to compose one unit module family with another is:

1. create a **host project**
2. load multiple ASDL families into the **same context**
3. install both boundary families into that same context
4. connect them with an explicit typed boundary

This is the correct compiler-pattern way to "plug trees into each other".

### 10.1 The rule

Do **not** usually merge authored source trees together.

Instead:

- keep authored domain trees honest
- treat the connection as an explicit boundary
- have one family lower/project into another family's target ASDL

Example shape:

```text
Tasks.Document
  -> project_ui
UiDecl.Document
  -> bind
UiBound.Document
  -> flatten
UiFlat.Scene
  -> ...
```

This means:

- `Tasks` remains the authored domain
- `UiDecl` is the target UI language
- ui3 takes over from `UiDecl` downward

### 10.2 Host project layout

Typical host project:

```text
examples/tasks_ui3/
  schema/
    00_all.lua
  pipeline.lua
  unit_project.lua
  boundaries/
    ... optional host-local boundaries ...
```

The host project's schema file can contribute one combined ASDL text in a known order when one family references types from another.

Example:

```lua
return function(U)
    return table.concat({
        U.read_asdl_file("examples/ui3/schema/app.asdl"),
        require("examples.tasks.tasks_asdl"),
    }, "\n\n")
end
```

### 10.3 Installing both families

A host project's `unit_project.lua` can install boundary modules from multiple families:

```lua
return {
    install = {
        "examples.tasks.task_app_state",
        "examples.tasks.task_view",
        "examples.tasks.task_view_screen",

        "examples.ui3.boundaries.ui_bound_document",
        "examples.ui3.boundaries.ui_flat_scene",
        "examples.ui3.boundaries.ui_geometry_input_scene",
        "examples.ui3.boundaries.ui_geometry_scene",
        "examples.ui3.boundaries.ui_render_scene",
        "examples.ui3.boundaries.ui_query_scene",
        "examples.ui3.boundaries.ui_render_machine_ir_render",
        "examples.ui3.boundaries.ui_session_state",
        "examples.ui3.boundaries.ui_machine_render",
        "examples.ui3.boundaries.ui_machine_render_gen",
    },
}
```

### 10.4 What the plug looks like

Two ASDL families are effectively plugged together when a boundary in one family returns nodes of the other family inside the same installed context.

For example:

```text
TaskApp.State
  -> project_view
TaskView.Screen
  -> lower
UiDecl.Document
```

That handoff is the plug.

### 10.5 Current example

See:

- `examples/tasks_ui3`

This is the current in-repo example of multi-family composition through a host project.

It now uses a project dependency:

- `examples/tasks_ui3` declares `deps = { "../ui3" }`

So ui3 schemas and active-backend artifacts are selected transparently by `unit`.

## 11. Current project conventions

The preferred project form is:

```text
myproj/
  schema/
    app.asdl
  pipeline.lua
  boundaries/
    ui_decl_document.lua
    ui_decl_document_test.lua
    ui_decl_document_bench.lua
    ui_decl_document_profile.lua
```

### 11.1 Defaults

- default layout: `flat`
- filenames: lower-snake
- receiver owns all its artifacts
- semantic sidecars:
  - `_test`
  - `_bench`
  - `_profile`
- backend suffixes:
  - `_luajit`
  - `_terra`

### 11.2 Optional `unit_project.lua`

Use it only for truthful project metadata such as:

- `layout`
- `schema_root`
- `boundary_root`
- `pipeline`
- `phases`
- `stubs`
- `install`

Do not turn it into a second schema language.

---

## 12. Cross-backend examples

## 12.1 Pure boundary

```lua
local lower = U.transition("lower", function(node)
    return U.match(node, {
        Add = function(v) return v end,
        Mul = function(v) return v end,
    })
end)
```

## 12.2 LuaJIT leaf

```lua
local State_t = U.state_ffi("struct { float total; }")

local unit = U.leaf(State_t, function(state, x)
    state.total = state.total + x
    return state.total
end)
```

## 12.3 Terra packaged leaf

```lua
struct CounterState { total : int32 }

local terra accum(x : int32, state : &CounterState)
    state.total = state.total + x
    return state.total
end

local unit = U.leaf(CounterState, accum)
```

## 12.4 Terra quoted leaf

```lua
local x = symbol(int32, "x")

local unit = U.leaf_quote(nil, terralib.newlist({ x }), function(_, params)
    return quote
        return [params[1]] * 2
    end
end)
```

---

## 13. Design rules for using the API

1. Use `U.transition` for ASDL → ASDL boundaries.
2. Use `U.terminal` for ASDL → Unit boundaries.
3. Use `U.match` for sum types.
4. Use `U.with` for structural updates.
5. Keep execution state inside `state_t`, not in source ASDL.
6. Prefer project directories, not ad hoc schema modules.
7. Prefer lower-snake receiver filenames.
8. On LuaJIT, use `U.state_ffi` for production leaves.
9. On Terra, use `U.leaf` for packaging and `U.leaf_quote` when you actually want Terra quote construction.
10. Treat differences in backend realization as Layer 3 details, not application architecture.

---

## 14. Known current asymmetries

The framework is converging toward a cleaner backend-agnostic public surface.

Current normalization status:

- `U.leaf(state_t, fn)` is normalized across backends
- `U.compose(children, fn)` is normalized as the packaging API across backends
- backend-specific realization helpers remain different:
  - LuaJIT: `U.compose_closure(children, body)`
  - Terra: `U.compose_quote(children, params, body)`

This document describes current truth, not aspirational behavior.

---

## 15. Recommended reading order

For a new contributor, read in this order:

1. `modeling-programs-as-compilers.md`
2. `docs/unit-api.md` (this file)
3. `README.md`
4. backend-specific notes only as needed:
   - `docs/luajit-backend.md`
   - `docs/luajit-leaf-rules.md`
   - `docs/gen-param-state-machine.md`

That set should be enough to understand both the architecture and the concrete framework surface.
