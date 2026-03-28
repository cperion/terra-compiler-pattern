# Shared `unit_core` Refactor Plan

## 1. Domain change

None.

This is a backend factoring task, not a source-language change. The user-visible nouns, event language, transitions, projections, and leaves stay the same.

## 2. ASDL change

None.

The ASDL remains the architectural source of truth. This plan only reorganizes the runtime vocabulary so that Terra and LuaJIT backends share one pure helper layer.

## 3. Phase impact

Unchanged phase path:

- source ASDL
- transitions (`lower`, `resolve`, `classify`, `schedule`, `project`)
- terminals (`compile`)
- `Unit`
- hot swap / app loop

What changes is only the implementation location of backend-independent helpers.

## 4. Boundary inventory

## Shared in `unit_core.lua`

These are pure helper/boundary concepts and should be backend-independent:

- `memoize`
- `transition`
- `terminal`
- `with_fallback`
- `with_errors`
- `errors`
- `match`
- `with`
- small LuaFun combinators:
  - `each`
  - `fold`
  - `map`
  - `reverse_each`
  - `each_name`
  - `append_errors`
  - `map_errors`

## Remain backend-specific in `unit.t`

These depend on Terra semantics and should stay in the Terra backend:

- `U.new(fn, state_t)` Terra ABI validation
- `U.leaf(state_t, params, body)` Terra quote construction
- `U.compose(children, params, body)` Terra struct synthesis
- `U.hot_slot(fn_type)` Terra globals + pointer swap
- `U.app(config)` if it continues to depend on Terra callback pointers

## Remain backend-specific in `unit_luajit.lua`

These depend on LuaJIT runtime semantics:

- `U.state`
- `U.state_table`
- `U.state_ffi`
- `U.state_compose`
- `U.new(fn, state_t)` callable/layout validation
- `U.leaf(state_t, fn)` closure leaf construction
- `U.compose(children, body)` closure/state-table composition
- `U.hot_slot()` runtime callback swap
- `U.app(config)` Lua callback hookup

## 5. Leaf-driven constraints

The factoring must preserve the different leaf requirements.

### Terra leaves need

- quoted code fragments
- explicit Terra parameter symbols
- explicit `state_t`
- LLVM compilation at construction time
- typed aggregate state layout

### LuaJIT leaves need

- captured constants as closure upvalues
- `fn(state, ...)`
- FFI/table state layouts
- monomorphic hot loops
- JIT-friendly imperative inner loops

This is why `Unit` construction cannot move fully into the shared layer.

## 6. Implementation plan

### Step 1: Keep `unit_core.lua` pure

Do not let backend details leak into `unit_core.lua`.

No:

- Terra quotes
- FFI allocation
- callback pointers
- state blob policies
- driver hooks

Only pure helpers and functional traversal.

### Step 2: Port pure helpers out of `unit.t`

Move these from `unit.t` into `unit_core.lua` in behavior-preserving form:

- `with_fallback`
- `with_errors`
- `errors`
- `match`
- `with`

Then have `unit.t` require/compose `unit_core` concepts instead of redefining them.

### Step 3: Keep Terra constructor semantics intact

`unit.t` must continue to enforce:

- Terra function validation
- `&state_t` ABI ownership
- eager `fn:compile()`

The shared layer must not weaken those invariants.

### Step 4: Decide whether `U.app` should split

There are two options:

1. keep one backend-specific `U.app` per backend
2. extract a smaller shared orchestration helper, and let backends provide:
   - slot creation
   - start/stop hookup
   - swap/install semantics

Short term, option 1 is simpler and safer.

### Step 5: Treat `inspect` separately

`U.inspect`, CLI scaffolding, and schema bootstrap are pure, but they are also much larger and tied to the existing Terra-centric file layout.

So they should be moved only after:

- shared helper extraction is stable
- Terra behavior is covered by tests
- the backend split vocabulary is settled

## 7. Validation notes

Before refactoring `unit.t`, verify:

- `U.match` behavior stays exhaustive where metadata exists
- `U.with` still reconstructs ASDL nodes exactly
- `U.errors` preserves semantic refs and neutral substitution
- `transition` / `terminal` memoization semantics do not change
- Terra leaves still compile eagerly
- hot-swap behavior is unchanged

## 8. Quality gates

- **Save/load:** unchanged
- **Undo:** unchanged
- **Completeness:** unchanged
- **Minimality:** unchanged
- **Testability:** improved, because pure helpers can be tested without Terra codegen
- **Incrementality:** unchanged if memoize semantics remain identity-based
- **Phase clarity:** improved, because backend-independent and backend-specific concerns are separated

## 9. Recommended next steps

1. add focused tests for `unit_core.lua`
2. migrate `unit.t` pure helpers to consume `unit_core.lua`
3. keep Terra-specific Unit construction untouched until tests pass
4. only then consider moving inspection/scaffolding helpers into a shared inspection module
