# js — JavaScript-to-LuaJIT Compiler

A JS-subset compiler that demonstrates the Terra Compiler Pattern applied
to language implementation. JS source text compiles to a closure tree that
LuaJIT traces through — no interpreter loop, no V8, ~2500 lines.

## Architecture

Same five primitives. Same pattern. Different source language.

```
JS source text
  -> lex (text -> JsLex.TokenStream)
JsLex.TokenStream
  -> parse (tokens -> JsSurface.Program)
JsSurface.Program
  -> lower (surface syntax -> JsSource.Program)
JsSource.Program
  -> resolve (names -> slots)
JsResolved.Program
  -> compile (terminal: ASDL -> closure tree)
JsMachine (closure tree that LuaJIT traces)
  -> run
```

## File structure

| File | Role |
|------|------|
| `js_asdl.lua` | Core/lowered ASDL: JsCore, JsSurface, JsSource, JsResolved, JsMachine |
| `js_lex_asdl.lua` | Typed token ASDL for the new frontend split |
| `js_schema.lua` | Pipeline contract + boundary wiring |
| `js_lex.lua` | Fast lexer: text → JsLex.TokenStream |
| `js_parse.lua` | Token parser: JsLex → JsSurface, plus compatibility `JsSource.parse()` |
| `js_lower.lua` | Lowering boundary: JsSurface → JsSource |
| `js_resolve.lua` | Transition: JsSource → JsResolved (scope resolution) |
| `js_compile.lua` | Terminal: JsResolved → closure tree (the leaf compiler) |
| `js_runtime.lua` | JS semantics: null, typeof, loose equality, arrays |
| `js_demo.lua` | End-to-end test suite |

## Supported JS subset

- Arithmetic, comparison, logical, bitwise operators
- `let`, `var`, `const` declarations
- authored `const` declarations require an initializer (except `for...in/of` headers)
- `const` reassignment errors in the compiled execution path
- `function` declarations and expressions
- Arrow functions (expression and block body)
- Closures and lexical scoping
- Receiver-call `this` binding for `obj.method()` and receiver-aware host methods
- `for (let/const ...)` closure capture with per-iteration bindings
- `for...in/of` preserve authored binding kind (`let`/`const` lexical per-iteration, `var` shared)
- Lexical TDZ for block/function/module-frame `let`/`const` bindings
- Per-iteration lexical environments for classic `for (let/const ...)`
- `if`/`else`, `while`, `for`, `for...in`, `for...of`
- `break`, `continue`, `return`
- `try`/`catch`/`finally`, `throw`
- `switch`, `do...while`, `for...in`, `for...of`
- `switch` lexical scope with one shared case-block environment and TDZ
- control-flow bodies lowered as explicit single statements; `{ ... }` remains an explicit `Block`
- Labeled statements with labeled `break` / `continue`
- Objects and arrays (literal syntax)
- Member access (`.` and `[]`), optional chaining (`?.`)
- Template literals (`` `hello ${name}` ``)
- `typeof`, `instanceof`, `void`, `delete`
- Ternary operator, nullish coalescing (`??`)
- Classes: constructors, instance methods, accessors, static fields, inheritance
- Class declarations are lexical/TDZ-bound; named classes have internal self-binding during class initialization
- ES module surface syntax lowered into CommonJS globals:
  - `import`
  - `export`
  - `export default`
  - `export *`
- `console.log`, `Math.*`, `parseInt`, etc.
- Recursive functions, higher-order functions

## Current module semantics

The current frontend accepts broad ES-module surface syntax, but the runtime
semantics are intentionally **not native ESM**.

There is now also a **native-module scaffold** with an initial executable subset:
- `JsSurface.Program:lower_module()`
- `JsModuleSource.Module:resolve_locals()`
- `JsModuleResolved.ModuleGraph:link()` for a strict initial subset
- `JsModuleLinked.ModuleGraph:compile_modules()`
- `compiled_graph:instantiate()`
- `runtime:execute()` for the local-export/live-import subset

That scaffold is for architectural honesty and graph-shape validation. It now
allocates compiled module metadata, export-cell arrays, namespace objects, and
can evaluate linked modules with live imported bindings for the supported
subset. The current production/demo executable path still also uses the
CommonJS-lowered runtime described below.

Today, module syntax lowers into the CommonJS-style globals injected by
`examples/js/js_node.lua`:

- `import ... from "m"` lowers to `require("m")` plus property reads
- `export ...` lowers to writes on `exports`
- `export default ...` lowers to `exports.default = ...`
- `export * from "m"` copies enumerable properties except `default`
- `import foo from "m"` currently uses **default-or-module fallback**:
  `require("m").default ?? require("m")`

What this means in practice for the executable path:

- there is **no native ESM linker / instantiation phase**
- there are **no live bindings** between importer and exporter
- `export *` is a runtime property copy, not a spec-accurate module namespace
- interop is intentionally biased toward the current Node/Luvit-style runtime

What the new scaffold already does:
- lowers a module into explicit import/export inventory plus eval body
- resolves local lexical slots inside one module
- preserves authored order for `export default expr` by lowering it to a
  synthetic local export in the module body
- performs an explicit native-module instantiation step before evaluation:
  - top-level function declarations are hoisted into module frames/export cells
  - top-level `var` bindings are initialized to `undefined` before eval
  - top-level lexical bindings (`let`/`const`/lowered class bindings) start in a
    TDZ state inside the module frame until their declaration runs
- links an explicit module graph for the first strict subset:
  - side-effect imports
  - default imports
  - named imports
  - namespace imports
  - local exports
  - default exports
  - named/default `export ... from`
  - `export * as ns from`
  - `export *` propagation (excluding `default`)

What the scaffold still rejects explicitly:
- `export *` name conflicts
- manually constructed raw `ExprExport` linked nodes outside the authored lowering
  path

Cycle status for the native scaffold:
- cycles now execute in SCC order with export cells allocated up front
- each reachable SCC is instantiated before any module in that SCC is evaluated
- this supports a useful live-binding subset, including hoisted function
  exports across cycles
- cyclic early reads now use TDZ sentinels and error instead of silently
  observing `nil`
- the same TDZ behavior now applies to top-level lexical bindings inside one
  module frame, including reads reached through hoisted exported functions
- this is still not full spec-accurate ESM instantiation/hoisting semantics;
  it is an honest module-frame/export-cell model for the current subset

This is honest for the current backend and tests, but it should not be read as
full ECMAScript module semantics.

## Intentional non-support

- `with` is parsed at the `JsSurface` layer but intentionally not lowered.
- Reason: `with` introduces dynamic name resolution, which conflicts with the
  explicit `JsSource -> JsResolved` lexical slot-resolution phase.
- Current policy: keep `with` as surface-only syntax and fail explicitly during
  lowering rather than pretending it fits the resolved execution model.

## Run

```bash
luajit examples/js/js_demo.lua
```

## Design notes

Built ASDL-first, leaf-first per AGENTS.md:

1. **ASDL first**: defined the complete type language (JsSource, JsResolved,
   JsMachine) before writing any implementation
2. **Leaf first**: designed the closure-tree terminal (js_compile.lua) before
   the resolver or parser — what does the compiled machine actually need?
3. **Phase boundaries**: each boundary consumes real knowledge:
   - `lex`: text → tokens (consumes character-level structure)
   - `parse`: tokens → `JsSurface` (consumes syntax)
   - `lower`: `JsSurface` → `JsSource` (consumes surface-only syntax distinctions and normalizes control-flow bodies to explicit single statements / `Block`s)
   - `resolve`: names → slot addresses (consumes scoping and label names)
   - `compile`: AST → closure tree (consumes all remaining structure)
4. **No interpretation at runtime**: the closure tree IS the executable.
   LuaJIT traces through monomorphic closure chains.
5. **Explicit scope ownership**: explicit `Block` / function / catch / loop
   scopes carry the scope information the leaf uses. The compiler should not
   rely on accidental Lua table growth or anonymous implicit scopes.

## Schema status

```bash
luajit unit.lua status examples/js/js_schema.lua
```
