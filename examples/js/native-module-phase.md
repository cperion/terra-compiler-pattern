# Native module phase plan

This file captures the concrete next-phase design for **native module semantics**
in `examples/js/`.

It does **not** change the current execution path yet.

Current reality remains:
- authored ES-module surface syntax exists
- current executable path lowers that syntax into CommonJS globals
- native module linking / live bindings are not implemented yet

This document defines the honest next architecture.

---

## 1. Domain summary

### Nouns
- module file
- module specifier
- import
- export
- default export
- namespace import
- re-export
- module namespace
- module graph
- live binding cell

### Identity nouns
- `Module`
- `ModuleId`

### Sum types
- import:
  - side-effect import
  - default import
  - namespace import
  - named import
- export:
  - local export
  - default expr export
  - default decl export
  - export-from
  - export-all
  - export-all-as

### Containment
- a module contains:
  - import declarations
  - export declarations
  - evaluation body
- a module graph contains:
  - modules
  - an optional entry module id

### Coupling points
These require a graph phase rather than statement-local lowering:
- module specifier resolution
- import/export linking across files
- `export *` propagation
- namespace object shape
- live binding identity
- cycle-safe instantiation/evaluation order

---

## 2. ASDL inventory now scaffolded

`examples/js/js_module_asdl.lua` defines:

- `JsModuleSource.Module`
- `JsModuleSource.ModuleGraph`
- `JsModuleSource.ImportDecl`
- `JsModuleSource.ExportDecl`
- `JsModuleLinked.ModuleGraph`
- `JsModuleLinked.LinkedModule`
- `JsModuleLinked.LinkedImport`
- `JsModuleLinked.LinkedExport`
- `JsModuleLinked.ExportBinding`

These are scaffold types only right now.

---

## 3. Phase plan

### Current executable path
- `text`
- `-> JsLex.TokenStream`
- `-> JsSurface.Program`
- `-> JsSource.Program`
- `-> JsResolved.Program`
- `-> JsMachine`

### Native module path
1. `parse`
   - `JsLex.TokenStream -> JsSurface.Program`
2. `lower_module`
   - `JsSurface.Program -> JsModuleSource.Module`
   - separates imports/exports from eval body
3. `resolve_locals`
   - per-module lexical resolution for local executable body
4. `link`
   - `JsModuleSource.ModuleGraph -> JsModuleLinked.ModuleGraph`
   - resolves specifiers and binding identity
5. `compile_modules`
   - linked graph -> compiled module machines / Units
6. `instantiate/evaluate`
   - runtime export-cell allocation and evaluation

---

## 4. Boundary inventory

### Implemented now
- `JsSurface.Program:lower_module()`
- `JsModuleSource.Module:resolve_locals()`
- `JsModuleSource.ModuleGraph:resolve_locals()`
- `JsModuleResolved.ModuleGraph:link()`
- `JsModuleLinked.ModuleGraph:compile_modules()`
- `compiled_graph:instantiate()` runtime scaffold
- `runtime:execute()` for the local-export/live-import subset
- ordered authored `export default expr` via lowering to a synthetic local export
- explicit per-module instantiation/evaluation split in native execution

### Still to add
- support for manually constructed raw `ExprExport` linked nodes outside the authored lowering path
- fuller spec-accurate ESM instantiation/hoisting semantics beyond the current module-frame/export-cell TDZ model

---

## 5. Leaf-driven constraints

A native-module leaf should not see:
- string module specifiers
- unresolved `export *`
- authored import/export syntax
- local-vs-reexport ambiguity

A native-module leaf should receive:
- concrete `ModuleId`s
- explicit import-cell references
- explicit export-cell indices
- resolved local slots
- explicit dependency graph edges
- explicit instantiation body
- explicit evaluation body

---

## 6. Current scaffold status

`JsSurface.Program:lower_module()` currently does the following:
- collects imports into `JsModuleSource.ImportDecl`
- collects exports into `JsModuleSource.ExportDecl`
- lowers non-module executable statements into `JsSource.Stmt`
- lowers exported declarations into `eval_body` plus export declarations

`JsModuleSource.Module:resolve_locals()` currently does the following:
- allocates top-level lexical slots for imported local bindings
- resolves the per-module executable body through the existing `JsSource -> JsResolved` path
- resolves local exports to `JsResolved.Slot`
- resolves `export default expr` to `JsResolved.Expr`

This is an honest per-module local-resolution boundary, but it is still **not executable as native modules** yet.

`JsModuleResolved.ModuleGraph:link()` now builds the first linked graph subset.
`JsModuleLinked.ModuleGraph:compile_modules()` now compiles linked modules into
per-module machine metadata, `instantiate()` allocates export-cell and
namespace runtime state, and `execute()` now runs the local-export/live-import
subset. Authored `export default expr` is now handled by lowering it into an
ordered synthetic local export before linking/execution. Execution now uses an
explicit instantiation/evaluation split, SCC ordering for cyclic module
graphs, preallocated export cells, top-level module-frame lexical TDZ, and
TDZ errors for cyclic early reads.

---

## 7. Honest next implementation slice

Current first linked native-module slice now supports:
- module graph loader by explicit graph construction
- `resolve_locals` for one module
- `link` for:
  - side-effect imports
  - named imports
  - default imports
  - namespace imports
  - local exports
  - default exports
  - named/default `export ... from`
  - `export * as ns from`
  - `export *` propagation excluding `default`
- duplicate `export *` name conflicts still error explicitly
- `compile_modules()` to compiled per-module metadata
- `instantiate()` to allocate export-cell arrays and namespace objects
- `execute()` for modules whose exports are driven by local slots / re-export cells / namespaces
- live imported bindings during execution via import-slot remapping
- authored `export default expr` execution through ordered lowering to a synthetic local export
- explicit module instantiation before evaluation, including top-level function hoisting and top-level `var` initialization
- top-level lexical TDZ in module frames for `let`/`const`/lowered class bindings
- SCC-based cycle execution with export cells allocated before evaluation
- TDZ errors for cyclic early reads via uninitialized export-cell sentinels and uninitialized module-frame lexical slots
- no support yet for manually constructed raw `ExprExport` linked nodes

Then add, in order:
1. namespace imports
2. `export *`
3. cycles
4. top-level await if desired

---

## 8. Relationship to current CommonJS-lowered path

Current runtime path is still the one used by:
- `js_demo.lua`
- `js_node.lua`
- `run_file`
- `run_string`

So today there are **two truths** and they are intentionally separated:

1. **Executable truth**
   - ES-module syntax lowers into CommonJS globals
2. **Architectural truth for future native modules**
   - native module semantics require a graph-linking phase

The scaffold exists so the second truth now has explicit types and boundary names.
