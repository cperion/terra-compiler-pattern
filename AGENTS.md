# AGENTS.md

This repository uses the **compiler pattern** for interactive software. Any coding agent working here must treat this file as the operational guide for how to design, revise, and implement features.

If you follow this file, design and implementation stay aligned. If you violate it, you will create accidental interpreters, hidden state, phase leaks, and brittle code.

---

## 0. What this repository is

This codebase treats interactive software as a **compiler**:

- **Source ASDL** is the user-facing language.
- **Events** are the input language.
- **Apply** is the pure reducer from `(state, event) → state`.
- **Transitions** narrow unresolved decisions across phases.
- **Terminals** compile phase-local ASDL into `Unit { fn, state_t }`.
- **Execution** runs compiled artifacts until the source changes.

The live loop is:

```
poll → apply → compile → execute
```

The central rule:

> **The ASDL is the architecture.**

Everything else is derived from it.

---

## 1. Authority and source of truth

When you work in this repository, use these files in this order:

1. **`modeling-programs-as-compilers.md`** — Source of truth for **how to model the domain** and **the overall architecture**. Use this for nouns, identity, sum types, containment, coupling points, phases, quality tests, design revision, the six concepts, the live loop, the compilation/execution split, Unit semantics, Machine IR, headers/facets, backend framing, performance model, and what the pattern eliminates.

2. **`docs/unit-api.md`** — Source of truth for the **documented `unit` API surface**. Read this first when the question is about signatures, module roles, project conventions, CLI behavior, cross-backend contracts, or current normalization status.

3. **`unit.lua` / `unit_core.lua` / `unit_luajit.lua` / `unit_schema.lua` / `unit_inspect_core.lua` / `unit.t`** — Source of truth for the **actual runtime implementation vocabulary**. Use these to confirm exact behavior and implementation details for `U.new`, `U.leaf`, `U.leaf_quote`, `U.compose`, `U.compose_linear`, `U.chain`, `U.transition`, `U.terminal`, `U.memoize`, `U.with_fallback`, `U.with_errors`, `U.errors`, `U.match`, `U.with`, `U.state_ffi`, `U.state_table`, `U.state_compose`, `U.inspect`, `U.inspect_from`, `U.load_project`, `U.normalize_project`, `U.project_type_artifact_path`, `U.project_type_path`, `U.project_type_test_path`, `U.project_type_bench_path`, `U.project_type_profile_path`, `U.install_project_boundaries`, `U.project_inspect_spec`, `U.load_inspect_spec`, `U.scaffold_type_artifact`, `U.scaffold_project`, `U.hot_slot`, `U.app`, `U.memo_report`, `U.memo_quality`, `U.memo_diagnose`, `U.memo_measure_edit`.

4. **This file (`AGENTS.md`)** — Source of truth for the **operational workflow**, implementation sequence, smell detection, profiling-driven ASDL revision, and hard constraints.

If a design idea conflicts with these files, change the design idea. Do not work around the pattern.

---

## 2. The non-negotiable rules

These rules are mandatory. Every one of them.

### 2.1 Start from ASDL, not runtime machinery

Do not begin with handlers, services, managers, stores, registries, plugin APIs, or runtime object graphs.

Start with: the domain nouns, the source ASDL, the phase boundaries, the desired leaf compilers.

### 2.2 Model the domain, not the implementation

The source phase must describe what the **user works with**, not how the program happens to run.

Good source nouns: track, clip, device, parameter, graph, node, document, block, span, cursor, sheet, cell, formula, chart.

Bad source nouns: callback, buffer pool, thread handle, mutex, renderer state, service locator.

### 2.3 The source ASDL is the specification

The source ASDL must capture all independent user choices and all user-visible persisted state.

If save/load would lose something the user expects to persist, it belongs in the source ASDL. If undo requires custom repair logic, the source ASDL is wrong.

### 2.4 Identity nouns must be explicit and stable

Every persistent, independently editable thing gets its own ASDL node, a stable ID, and `unique` if it is a concrete ASDL type. IDs identify the thing, not its position. Reordering must not change identity.

### 2.5 Every domain "or" is a sum type

If the domain says "clip is audio OR MIDI" or "selection is cursor OR range," the ASDL must say the same thing as an enum / tagged union. Do not encode domain variants with strings when the set is fixed.

### 2.6 Cross-references are IDs, never Lua object pointers

If one node references another outside containment, use a numeric `target_id`, resolve it in a later phase, and validate it globally. Never store live Lua references in source ASDL.

### 2.7 Phases must consume knowledge

Each phase boundary must resolve a real decision. Typical verbs: `lower`, `resolve`, `classify`, `schedule`, `compile`, `project`. If you cannot name the verb, the phase is probably not real.

### 2.8 Later phases should narrow, not widen

As you move through phases, sum types should decrease, decisions should be consumed, shapes should become more concrete. The terminal input should be as flat and monomorphic as possible. A scheduled phase should usually contain zero large domain sum types.

### 2.9 Every pure-layer function must be a structural transform

Transitions, reducers, projections, and helpers in the pure layer must use the boundary vocabulary: `U.match`, `U.with`, `errs:each`, `errs:call`, ASDL constructors.

This rule is **strict**.

It is **not enough** that a function is merely pure, deterministic, memoized, or architecturally well-placed.

A pure-layer function written as ad hoc imperative traversal is still a design failure by repository standards.

In particular, do **not** treat these as acceptable substitutes for the required style:

- manual `for` loops that build result tables in pure boundaries
- mutable accumulator tables used to drive phase lowering
- `table.insert` into result tables
- repeated `v.kind` / `K(v)` branching where `U.match` or a real sum-consuming phase should exist
- hand-rolled structural updates instead of `U.with`
- "it is still pure" as justification for imperative boundary code

If a function resists the required style, do **not** fight the code into shape. Fix the ASDL or insert the missing phase.

Signs the ASDL is wrong: you need mutable accumulators, you need global context objects, you need sibling lookups everywhere, you need imperative branching over string tags, you need a hidden environment to make tests pass.

This rule also applies to **compiler-side backend boundaries**. A function of the form ASDL → ASDL or ASDL → Unit is still part of the **pure layer**, even if the generated code will later talk to SDL, OpenGL, fonts, or OS APIs. Keep mutable stacks, GL state changes, and other imperative mechanics inside the **emitted code** or inside `Unit.state_t`, not in the Lua-side boundary construction.

If you catch yourself saying "the code is still pure, just written with loops," stop and redesign before continuing.

### 2.10 Every boundary is memoized

All pure stage boundaries must go through `U.transition(name, fn)` for ASDL → ASDL or `U.terminal(name, fn)` for ASDL → Unit. Do not invent parallel caching systems, dirty flags, or invalidation frameworks.

### 2.11 Every compiled artifact is a Unit

Compiled outputs must be `Unit { fn, state_t }`. Use `U.leaf` for leaf codegen, `U.compose` for structural composition, `U.compose_linear` / `U.chain` for sequential composition, `U.new` for validated construction. Do not separate code generation from state ABI ownership.

### 2.12 Event input must be an Event ASDL

Interactive inputs are not ad hoc callbacks. They are an input language. Represent them as a sum type. Handle them with a pure reducer: `(state, event) → state`, exhaustively matched via `U.match`.

### 2.13 The view is a separate ASDL projection

Do not force UI shape into the source ASDL. Source ASDL models the domain, view ASDL models presentation, projection maps source → view. Carry semantic refs through projection so errors and selections can map back to source nodes.

### 2.14 Tests are constructor + assertion

Pure-layer tests should look like: construct ASDL input, call function, assert output. Avoid mocks, fixtures, setup frameworks, or hidden context. If a function needs those, it has a design problem.

### 2.15 Production leaves use typed FFI state

`U.state_table()` is for debug/scaffolding only. Production leaves use `U.state_ffi()` with typed cdata layouts. No opaque Lua tables anywhere in the designed execution model.

### 2.16 The unit authoring surface is a project directory

The normal `unit` surface is convention-first project loading.

Preferred project shape:

- `schema/*.asdl`
- optional `pipeline.lua`
- `boundaries/`
- optional `unit_project.lua`

Use project directories as the primary source for inspection, path lookup, and scaffolding.

### 2.17 Flat boundary layout is the default

Use flat receiver-owned files unless there is a strong reason to opt into tree layout.

Default flat mapping uses lower-snake filenames:

- `Demo.Expr` → `boundaries/demo_expr.lua`
- `Demo.Expr` test → `boundaries/demo_expr_test.lua`
- `Demo.Expr` bench → `boundaries/demo_expr_bench.lua`
- `Demo.Expr` profile → `boundaries/demo_expr_profile.lua`

Tree layout is optional via project config.

### 2.18 One receiver type owns its boundary artifacts

A receiver type owns its boundary implementation file and its sidecars.

Do not create one file per boundary verb by default.

Canonical artifact kinds are:

- `impl`
- `test`
- `bench`
- `profile`

---

## 3. Modeling ASDL from scratch

When starting a new domain, follow these steps in order. Do not skip steps. Do not start coding until step 7 is done.

### Step 1: List the nouns

Ask: "What are all the things the user sees and interacts with?" Write down every noun — visible elements, interactive controls, structural containers, configuration.

### Step 2: Classify identity vs property

For each noun: "Can the user point to this and say 'that one'?"
- YES → identity noun → gets its own ASDL record with a stable ID, marked `unique`
- NO → property → becomes a field on an identity noun

### Step 3: Find the sum types

For every "or" in the domain, create an enum. Every fixed-set choice MUST be an enum. Never use strings for fixed choices. Never use nil-filled bags of optional fields where a sum type belongs.

### Step 4: Draw the containment tree

What owns what? Parents own children (no shared ownership). Cross-references are IDs, not Lua references. Lists use ASDL `*`.

### Step 5: Find the coupling points

Where do two independent subtrees need each other's information? Coupling points determine phase ordering. If A depends on B and B depends on A, they must be resolved in the same phase.

### Step 6: Define the phases

Each phase consumes decisions. Name the verb. Rules: each phase has fewer sum types than the previous one, terminal phase has ZERO sum types, if you can't name the verb the phase shouldn't exist, if a boundary does two unrelated things you're missing a phase.

### Step 7: Quality-check the source ASDL

Before writing any code, verify:

```
□ Save/load: serializing and deserializing preserves all user intent
□ Undo: restoring the previous ASDL tree restores all behavior (no repair logic)
□ Completeness: every variant is reachable, every state is representable
□ Minimality: every field is independently editable by the user
□ Orthogonality: independent fields don't constrain each other
□ Testing: every function is testable with one constructor + one assertion
```

If any check fails, fix the ASDL before proceeding.

---

## 4. The leaf-first implementation workflow

This is the most important workflow in the entire system. Follow it exactly.

### 4.1 The principle

**Do not implement top-down.** Implement bottom-up, starting at the leaves.

The leaf terminal is the function closest to the machine — it takes a phase-local node and produces a `Unit { fn, state_t }`. It is the smallest function in the system (often 10-20 lines) and the most honest. It has no room to hide a bad ASDL.

### 4.2 The cycle

```
STEP 1: Pick the lowest unimplemented leaf terminal
STEP 2: Implement it as Unit { fn, state_t }
STEP 3: Profile and trace it (LuaJIT -jv, -jdump, jit.p)
STEP 4: Read the trace output as a design diagnostic
STEP 5: If traces are clean → move up one layer
STEP 6: If traces are dirty → redesign the ASDL of the phase above
STEP 7: Repeat from STEP 1 at the next layer up
```

### 4.3 Implementing the leaf

Write the leaf you WANT to write. Imagine the perfect machine:

- What would `fn` do in the hot path?
- What would `state_t` own as live mutable data?
- What values should be baked (compile-time constants)?
- What values should stay live in state?

Production leaves use `U.state_ffi()` for typed cdata state, not `U.state_table()`.

```lua
-- GOOD: FFI-backed typed state, baked coefficients as upvalues
local state_t = U.state_ffi("struct { double x1; double x2; double y1; double y2; }")

local compile_biquad = U.terminal("compile_biquad", function(node)
    local b0, b1, b2, a1, a2 = compute_coefficients(node)
    return U.leaf(state_t, function(state, input)
        local y = b0 * input + b1 * state.x1 + b2 * state.x2
                             - a1 * state.y1 - a2 * state.y2
        state.x2 = state.x1
        state.x1 = input
        state.y2 = state.y1
        state.y1 = y
        return y
    end)
end)

-- BAD: opaque Lua tables, dynamic lookup, runtime interpretation
local bad_terminal = U.terminal("bad", function(node)
    return U.leaf(U.state_table(), function(state, input)
        local coeffs = state.coeffs  -- table lookup in hot path!
        local kind = state.kind      -- dynamic dispatch!
        if kind == "lowpass" then    -- string comparison in hot path!
            ...
        end
    end)
end)
```

### 4.4 Profile and trace

LuaJIT's tracing JIT is the design probe. Run with these flags:

```bash
# Verbose trace output — shows trace compilation, exits, aborts
luajit -jv your_test.lua

# Detailed dump — shows generated IR and machine code
luajit -jdump your_test.lua

# Profiler — shows where time is spent
luajit -jp your_test.lua

# Profiler with verbose trace info combined
luajit -jp=vl your_test.lua
```

### 4.5 Read traces as design diagnostics

The trace output tells you about the ASDL, not just the code.

**TRACE COMPILED CLEANLY** → The leaf is getting good types. The phase above is doing its job. Move up.

**TRACE EXIT (type instability)** → The leaf is seeing multiple types for the same value. The phase above is feeding a sum type that should have been consumed earlier. Fix: add a phase that eliminates the sum type, or move the match upstream.

**NYI (not yet implemented)** → The leaf is using a LuaJIT operation that can't be traced. Common culprits: `pairs()`/`next()` on tables in the hot path, `tostring()` in the hot path, concatenation in the hot path, untyped table access. Fix: the phase above should have lowered these into trace-friendly forms.

**RETURN TO INTERPRETER** → The trace was abandoned. The code is too polymorphic. Common causes: the leaf dispatches on a sum type that should have been consumed, the leaf does table lookups that should be FFI access, the leaf calls functions through dynamic dispatch. Fix: the ASDL above is too wide. Narrow it.

**TRACE TOO LONG** → The function is too big. Fix: the identity noun is too coarse — split the type, or adjust Unit granularity.

**MANY SHORT TRACES, POOR STITCHING** → Too many tiny closures composing at runtime. Fix: the leaf is over-lowered into micro-Units — fuse children, use parent state, rethink composition boundary.

### 4.6 Redesign upward

When traces are dirty, **do not fix the leaf**. Fix the phase above.

The question is always:

> What must the layer above produce so this leaf traces clean?

Common fixes:

| Trace symptom | ASDL fix |
|---|---|
| Type instability | Consume the sum type in a prior phase |
| Table lookup in hot path | Use FFI cdata layout instead |
| String comparison | Replace string tags with enum variants |
| Dynamic dispatch | Monomorphize: one closure per variant, chosen at compile time |
| Polymorphic call site | Specialize the composition — each child is a known direct call |
| Large recompilation on small edit | Split the ASDL node (finer identity boundaries) |
| Sibling cache miss on local edit | Fix structural sharing (use `U.with`, not deep copy) |

After each ASDL fix: update the ASDL definition, update the transition that feeds this leaf, re-run the leaf, re-trace, verify the trace is now clean.

### 4.7 Move up one layer

Once the leaf traces clean, implement the transition ONE layer above it. Profile and trace THIS transition. Same diagnostic: if it's slow, the phase above IT has the wrong types.

Continue recursing upward until you reach the source ASDL. At each layer: implement, profile, if dirty redesign the ASDL above, if clean move up.

### 4.8 The ASDL is fluid

The ASDL is NEVER frozen during this process. It is a living design document refined by what the profiler tells you. Every trace exit, every NYI, every return-to-interpreter is intelligence about the type system.

The ASDL stabilizes when leaves stop demanding changes.

---

## 5. The boundary vocabulary

Every boundary function uses exactly these primitives. No others.

### 5.1 The primitives

**`U.match(value, arms)`** — Exhaustive dispatch on a sum type. Every variant MUST have a handler.

**`U.errors()`** — Creates an error collector.

**`errs:each(items, fn, ref_field)`** — Maps a list of children through a function, collects errors, substitutes neutrals for failures.

**`errs:call(target, fn)`** — Transforms a single child, collects errors.

**`U.with(node, overrides)`** — Structural copy with field changes. Preserves structural sharing.

**ASDL constructor** — `Phase.TypeName(field1, field2, ...)` — Builds the output node.

**`U.transition(name, fn)`** — Memoized phase transition (ASDL → ASDL).

**`U.terminal(name, fn)`** — Memoized terminal compilation (ASDL → Unit).

**`U.with_fallback(fn, neutral)`** — Wraps fn to return neutral on error.

**`U.with_errors(fn)`** — Wraps fn to return (result, errors).

### 5.2 Shape 1: Record boundary

The node is a record with children. Call each child's boundary, collect errors, construct the next-phase node.

```lua
function Track:lower()
    local errs = U.errors()

    local devices = errs:each(self.devices, function(d)
        return d:lower()
    end, "id")

    local clips = errs:each(self.clips, function(c)
        return c:lower()
    end, "id")

    return Authored.Track(self.id, self.name, devices, clips), errs:get()
end
```

### 5.3 Shape 2: Enum boundary

The node is a sum type. Dispatch on the variant.

```lua
function Device:lower()
    return U.match(self, {
        NativeDevice = function(self)
            local errs = U.errors()
            local params = errs:each(self.params, function(p)
                return p:lower()
            end, "id")
            return Authored.Node(self.id, self.kind, params), errs:get()
        end,
        LayerDevice = function(self)
            local errs = U.errors()
            local children = errs:each(self.devices, function(d)
                return d:lower()
            end, "id")
            return Authored.Graph(self.id, children, {}), errs:get()
        end,
    })
end
```

### 5.4 The rule

If a boundary function doesn't fit one of these two shapes, one of these is true: the ASDL is missing a field, the ASDL is missing a phase, the containment hierarchy is wrong, or a sum type is missing. **Never force the code. Fix the ASDL.**

---

## 6. The Apply reducer

Apply is the pure function that evolves the source program:

```lua
function apply(state, event)
    return U.match(event, {
        SetVolume = function(e)
            local track = find_track(state.tracks, e.track_id)
            local new_track = U.with(track, { volume_db = e.value })
            return replace_track(state, new_track)
        end,
        AddDevice = function(e)
            ...
        end,
    })
end
```

Rules:
- Apply MUST be pure. No side effects, no I/O, no mutation.
- Apply MUST use `U.with()` for structural sharing. Never deep-copy.
- Apply MUST use `U.match()` for event dispatch. Every event variant handled.
- Apply returns a new ASDL tree. The old tree is untouched.
- Unchanged subtrees are the SAME Lua objects (not copies). This is what makes memoize work.

---

## 7. ASDL smells — detection and fixes

When reviewing code or ASDL, watch for these smells. Each one has a specific fix.

### Smell 1: String tags where enums belong

```lua
-- SMELL: kind = "biquad" — no exhaustiveness, no variant-specific fields, typos are silent
Node = (number id, string kind, ...)

-- FIX
NodeKind = Biquad(number freq, number q) | Gain(number db) | Sine(number freq)
Node = (number id, NodeKind kind, ...)
```

**Detection:** `if x.kind == "..."` or `x.type == "..."` anywhere in boundary code.

### Smell 2: Derived values in source

```lua
-- SMELL
Track = (number id, string name, number volume_db,
         float* compiled_coefficients, number buffer_slot)

-- FIX: source contains only authored choices
Editor.Track = (number id, string name, number volume_db) unique
```

**Detection:** fields that change whenever another field changes. Fields the user never directly edits.

### Smell 3: Context arguments

```lua
-- SMELL
function Node:lower(ctx, global_state, parent_ref)
    local target = ctx.lookup(self.target_id)
    ...
end

-- FIX: a prior phase already linked the reference onto self
function Node:lower()
    return Authored.Node(self.id, self.resolved_target, ...), nil
end
```

**Detection:** any boundary function that takes arguments beyond `self`. Any call into a context, registry, or lookup table.

### Smell 4: Mutable accumulator

```lua
-- SMELL
local all_nodes = {}
for _, track in ipairs(project.tracks) do
    for _, device in ipairs(track.devices) do
        table.insert(all_nodes, device)
    end
end

-- FIX
local devices = errs:each(self.devices, function(d)
    return d:lower()
end, "id")
```

**Detection:** `table.insert`, manual `for` loops with accumulator tables, any `local result = {}` followed by mutation.

### Smell 5: Imperative control flow in boundaries

```lua
-- SMELL
function Node:lower()
    if self.kind == "special" then
        return handle_special(self)
    elseif self.kind == "other" then
        return handle_other(self)
    else
        error("unknown kind")
    end
end

-- FIX
function Node:lower()
    return U.match(self, {
        Special = function(self) ... end,
        Other = function(self) ... end,
    })
end
```

**Detection:** `if/elseif` chains that select behavior based on type/kind. `break` or early `return` inside loops.

### Smell 6: Lua tables as state in production leaves

```lua
-- SMELL
local state_t = U.state_table(function(s) s.x1 = 0; s.x2 = 0 end)

-- FIX
local state_t = U.state_ffi("struct { double x1; double x2; }")
```

**Detection:** `U.state_table()` in production code. Any untyped table access in a leaf's hot path.

### Smell 7: Deep copy instead of structural sharing

```lua
-- SMELL
local new_project = deep_copy(old_project)
new_project.tracks[2].volume_db = -3

-- FIX
local new_track = U.with(old_track, { volume_db = -3 })
```

**Detection:** any function named `deep_copy`, `clone`, or `copy` applied to ASDL nodes.

### Smell 8: Cross-references as Lua pointers

```lua
-- SMELL
Send = (Track target, number gain_db)  -- live Lua reference

-- FIX
Send = (number target_track_id, number gain_db) unique
```

**Detection:** ASDL fields that hold Lua tables or objects rather than numbers/strings/ASDL nodes.

### Smell 9: Missing phase (boundary does two things)

```lua
-- SMELL
function Track:compile()
    local target = find_track(self.send_target_id)  -- resolution
    local slot = allocate_buffer()                   -- scheduling
    local unit = emit_code(self, target, slot)       -- compilation
    return unit
end

-- FIX: three separate phases
```

**Detection:** boundary functions longer than ~30 lines. Functions that mix lookups, allocation, and code generation.

### Smell 10: Sum type reaching the hot path

```lua
-- SMELL: runtime dispatch on authored variant
function process(state, node)
    if node.kind == "biquad" then return biquad_process(state, node)
    elseif node.kind == "gain" then return gain_process(state, node)
    end
end

-- FIX: terminal emits a specialized closure per variant
local compile_node = U.terminal("compile_node", function(node)
    return U.match(node, {
        Biquad = function(self)
            local b0, b1, b2, a1, a2 = compute_coefficients(self)
            return U.leaf(biquad_state_t, function(state, input)
                -- no dispatch here — this closure IS the biquad
                ...
            end)
        end,
        Gain = function(self)
            local linear = 10 ^ (self.db / 20)
            return U.leaf(U.EMPTY, function(state, input)
                return input * linear
            end)
        end,
    })
end)
```

**Detection:** `if`/`match` on variant kind inside a `Unit.fn`. Any type dispatch in code that runs per-sample, per-frame, or per-tick.

### Smell 11: Unstable IDs

**Detection:** memoize cache miss ratios above 50% on simple reordering edits. IDs that are array indices.

**Fix:** IDs identify the THING, not its POSITION. Assign once at creation.

### Smell 12: Opaque table in ASDL

```lua
-- SMELL
Settings = (table config) unique

-- FIX
Setting = (string key, string value) unique
Settings = (Setting* entries) unique
```

**Detection:** ASDL fields of type `table`. Any field that breaks save/load because it has no schema.

---

## 8. Revising existing ASDL

When the profiler, a leaf, or a user requirement tells you the ASDL needs to change:

### 8.1 The revision checklist

```
1. □ Identify what's wrong (smell, trace diagnostic, missing feature)
2. □ Draft the ASDL change
3. □ Check: does this change break save/load? If so, migration plan needed
4. □ Check: does this change break undo? (It shouldn't if done right)
5. □ Check: do existing boundaries still fit the canonical shapes?
6. □ Update the ASDL definition
7. □ Update affected transitions (layer above and below the change)
8. □ Run U.inspect() to verify boundary coverage
9. □ Re-run leaf traces to verify the fix worked
10. □ Run memoize hit-ratio test to verify incrementality
```

### 8.2 Common revisions

**Adding a field to source:** Add to the ASDL record, update constructors in Apply, update `U.with` calls, update transitions.

**Adding a variant to a sum type:** Add to the ASDL enum, update EVERY `U.match` on that enum (the runtime will error on missing arms), update terminals. This is why exhaustive matching matters.

**Adding a phase:** Define new ASDL types, split the boundary that was doing two things, update the phase list, run `U.inspect()`.

**Splitting a type:** When too coarse (leaf too big, edits cause too much recompilation). Create finer-grained types, update containment, check memoize hit ratios.

**Merging types:** When too fine (leaf is trivial, too many micro-Units). Combine, simplify transitions, may improve composition performance.

### 8.3 Treat ASDL revision as normal, not as failure

You will not get the ASDL perfect on the first pass. Revision is expected. When implementation reveals resistance, revise the ASDL first.

---

## 9. Implementation resistance — what it means

When code feels wrong, interpret it diagnostically.

| Symptom | Meaning | Fix |
|---|---|---|
| Missing field at a leaf | Upstream ASDL doesn't provide required knowledge | Add or move the field in the correct phase |
| Repeated lookups by ID | Resolution phase is missing or incomplete | Add a resolved phase that attaches info structurally |
| Mutable accumulation required | Node boundaries or phase are wrong | Restructure data so transforms are local and compositional |
| One boundary function is enormous | Too much unresolved knowledge arrives at once | Split the phase or split the type |
| Function is trivial and meaningless | Type too fine-grained or phase distinction not real | Merge nodes or phases |
| Need `context`, `env`, or service access | Function is impure or phase underspecified | Move required data into the ASDL of the proper phase |
| Tests need mocks or elaborate setup | Hidden dependencies in pure layer | Fix the design, not the test harness |
| Trace exit on type check | Sum type in hot path | Consume variant in prior phase |
| NYI in hot path | Untyped operation | Use FFI cdata, pre-compute strings |
| Return to interpreter | Polymorphic code | Monomorphize leaf, specialize per variant |
| Trace too long | Leaf too big | Split the type, adjust Unit granularity |
| Many short traces | Over-lowered micro-Units | Fuse children, use parent state |
| Memoize hit ratio < 50% | Coarse identity or broken sharing | Split ASDL nodes, use U.with |
| Memoize miss on unrelated sibling | Broken structural sharing | Use U.with, not deep copy |
| Can't test without setup | Hidden dependency | Trace to ASDL — field is missing or function is impure |

---

## 10. Composition patterns

### 10.1 Linear composition

When children should run in sequence:

```lua
local chain = U.compose_linear(children)
-- or equivalently
local chain = U.chain(children)
```

### 10.2 Structural composition

When the parent needs to orchestrate children:

```lua
local unit = U.compose(children, function(state, kids, ...)
    local result = kids[1].call(state, ...)
    result = kids[2].call(state, result)
    return result
end)
```

### 10.3 Hot swap

When the compiled Unit needs to be replaced at runtime:

```lua
local slot = U.hot_slot()
slot:swap(new_unit)       -- install new Unit
slot.callback(...)        -- call current Unit
slot:collect()            -- clean up retired Units
slot:close()              -- shut down
```

### 10.4 The app loop

The universal application loop:

```lua
U.app({
    initial = function() return initial_state end,
    apply = function(state, event) return new_state end,
    poll = function() return next_event_or_nil end,
    compile = {
        audio = function(state) return compile_audio(state) end,
        view = function(state) return compile_view(state) end,
    },
    start = {
        audio = function(callback) install_audio_callback(callback) end,
    },
    stop = {
        audio = function() stop_audio() end,
    },
})
```

---

## 11. Using U.inspect() and U.memo()

These are your diagnostic tools. Use them constantly.

### 11.1 Schema inspection

Preferred project-oriented flow:

```lua
local I = U.inspect_from("examples/myproj")

print(I.status())                            -- types and boundary coverage
print(I.markdown())                          -- full schema docs
print(I.type_graph("Editor.Track", 3))      -- type graph from root
print(I.prompt_for("Editor.Track:lower"))   -- implementation prompt
print(I.scaffold("Editor.Track:lower"))     -- scaffold code

for _, edge in ipairs(I.pipeline()) do
    print(edge.from, "→", edge.verb, "→", edge.to)
end

local results = I.test_all()
print(results.passed .. "/" .. results.total)
```

Lower-level flow is still available when you already have `(ctx, phases)` in hand:

```lua
local I = U.inspect(ctx, phases)
```

### 11.2 Memoize diagnostics

```lua
print(U.memo_report())       -- full boundary-by-boundary report
print(U.memo_quality())      -- design quality assessment
print(U.memo_diagnose())     -- detect specific problems

print(U.memo_measure_edit("change biquad freq", function()
    -- perform the edit and recompile here
end))
```

### 11.3 Interpreting memoize reports

- **90%+ hit ratio** → ASDL decomposition is excellent
- **70-90% hit ratio** → healthy, but inspect the worst boundary
- **below 50%** → ASDL or phase boundaries are too coarse, or structural sharing is broken

The **misses-per-edit** is the architectural cost of one user action.

---

## 12. How to handle common task types

### 12.1 New feature

1. Identify domain nouns
2. Extend source ASDL
3. Identify phase impacts
4. Define desired leaves
5. Implement leaves-up with profiling cycle (section 4)
6. Add events/reducer changes if interactive
7. Update view projection if visible
8. Test with constructor + assertion
9. Check memoize hit ratios

### 12.2 Bug fix

First classify the bug:
- Bad ASDL → fix the ASDL
- Missing phase → add the phase
- Incorrect transition → fix the transition
- Incorrect terminal/leaf → fix the leaf
- Reducer bug → fix the reducer
- Projection bug → fix the projection

Do not patch symptoms in runtime code if the actual problem is in modeling.

### 12.3 Refactor

The goal is usually: better ASDL minimality, better phase separation, better leaf locality, better structural sharing, removal of accidental runtime interpretation.

A refactor that preserves behavior but clarifies the phase model is good.

### 12.4 Performance work

First ask whether performance should come from:
- Fixing memoization boundaries
- Improving structural sharing
- Narrowing sum types earlier
- Baking more constants into leaves
- Splitting a coarse identity noun

Then run the profiling cycle (section 4). Trace exits and NYI are design diagnostics. Do not start with micro-optimization if the architecture is forcing unnecessary recompilation or dispatch.

### 12.5 Porting to another backend

Only the backend-specific leaf compilation and runtime hookup should change. The pure layer should stay structurally the same.

---

## 13. Required deliverables for agent work

When doing serious design or implementation, produce these artifacts in order.

### 13.1 Domain summary

A concise restatement of: nouns, identity nouns, sum types, containment, coupling points.

### 13.2 ASDL proposal or ASDL diff

Prefer explicit proposed type changes over vague prose. Show: new/changed records, new/changed enums, moved fields, removed derived fields.

### 13.3 Phase plan

List phases in order and name the verb for each boundary.

### 13.4 Boundary inventory

List which functions must exist or change. Examples:
- `Editor.Device:lower()`
- `Authored.Graph:resolve()`
- `Resolved.Project:classify()`
- `Scheduled.Job:compile()`
- `Editor.Project:project_view()`

### 13.5 Leaf-driven constraints

State what each important leaf requires from its input. This is how the ASDL stays honest.

### 13.6 Implementation

Only after the above is coherent.

### 13.7 Validation notes

Explicitly say what was checked and what remains uncertain.

---

## 14. What to say when proposing design changes

When presenting a design or code change, use this structure:

1. **Domain change** — what user concept is being added or corrected
2. **ASDL change** — exact type additions/removals/moves
3. **Phase impact** — which phases and boundaries change
4. **Leaf requirement** — what the terminal code needs and why
5. **Implementation plan** — transitions, terminals, reducer, projection, tests
6. **Validation** — which quality gates were checked

This keeps design and implementation coupled.

---

## 15. LuaJIT backend rules

The LuaJIT backend is NOT the permissive dynamic-tables backend. These rules are strict.

### 15.1 Production leaf contract

Every production leaf MUST be:

```lua
Unit {
    fn = function(state, ...)  -- state is FFI cdata, not a Lua table
        -- monomorphic hot path
        -- no table lookups, no string comparisons
        -- no dynamic dispatch, no sum type interpretation
        -- direct arithmetic over typed fields
    end,
    state_t = U.state_ffi("struct { ... }")  -- typed FFI layout
}
```

### 15.2 What makes a trace-friendly leaf

**DO:** Capture compile-time-known values as upvalues. Use FFI cdata for state access. Keep loops simple and monomorphic. Use direct function calls in hot paths. Compose children as direct calls.

**DON'T:** Use `pairs()` or `next()` in hot paths. Use string keys for field access. Use `type()` checks. Use `tostring()` or concatenation. Use `table.insert()`. Leave sum types unresolved.

### 15.3 The bake/live split

| Classification | Where it goes | When to use |
|---|---|---|
| **Bake as upvalue** | captured in closure | compile-time-known, rarely changes |
| **Bake as constant** | literal in code | never changes for this leaf |
| **Live in state_t** | FFI cdata field | changes per-call, execution-time mutable |
| **Live in param** | function argument | changes per-call, comes from caller |

### 15.4 The strict rule

> No opaque tables anywhere in the designed system.

Pure phases may work over ASDL-defined typed values and typed lists. Backend leaves must work over backend-native typed FFI/cdata layouts. If a LuaJIT leaf wants general table bags, missing-field checks, tag strings, or interpreter-style tree walking, the lowering is incomplete. Fix the ASDL or insert the missing phase.

---

## 16. Forbidden shortcuts and anti-patterns

Do **not** introduce these casually.

- Modeling implementation details in source ASDL (thread handles, mutexes, callbacks, renderer caches, buffer slots)
- Mixing phases in one type (authored choices with derived data or scheduled allocations)
- Strings instead of enums for closed domains
- Lua object references across the authored tree
- Raw table maps in source ASDL
- Deep-copy edits (destroys structural identity and defeats memoization)
- Hidden mutable state in pure-layer functions (global registries, mutable closures, implicit context — including compiler-side terminal construction)
- Runtime dispatch for compile-time-known decisions
- Hand-built infrastructure that the pattern already eliminates

Be suspicious of adding: state managers, dependency injection containers, observer buses, invalidation graphs, custom build caches, plugin ABI layers, heavy test harnesses.

The first question should always be:

> "What information is missing from the ASDL or phase structure that made this seem necessary?"

---

## 17. Repository-specific expectations

- Use the terminology and patterns from `modeling-programs-as-compilers.md` and the `unit_*.lua` files.
- Prefer the existing `U.*` vocabulary over inventing parallel helpers.
- Treat compiler-side boundary code as pure code. Backend terminals are not an exception just because their emitted code talks to SDL/GL/TTF.
- Treat the current docs as a coherent pattern, not as optional inspiration.
- When adding examples or helpers, reinforce the pattern rather than diluting it.
- If you must extend the framework, do it in the same spirit: small, compositional, reflective, no new DSL unless absolutely forced.
- Use project directories or direct `.asdl` schema files; `U.spec(...)` is removed.
- Prefer flat boundary layout by default. Use tree layout only when it materially improves organization.
- Use canonical sidecar names: `_test`, `_bench`, `_profile`.
- For backend-owned receiver artifacts, use canonical backend suffixes such as `_luajit` and `_terra` before the sidecar suffix.
- Use `unit_project.lua` only for truthful project metadata such as layout, roots, phases, stubs, installation hooks, or project dependencies; do not turn it into a second schema language.

---

## 18. The complete implementation sequence

When implementing a full feature, follow this exact sequence:

```
1. REVIEW the current ASDL
2. DRAFT source ASDL changes (if needed)
3. DRAFT phase structure (if new phases needed)
4. START AT THE LEAF — the terminal closest to the backend
5. IMPLEMENT the leaf as Unit { fn, state_t }
6. WRITE a minimal test: construct input node, call terminal, verify Unit
7. PROFILE the leaf: luajit -jv, check traces
8. If traces are dirty → REDESIGN the phase above → go to step 5
9. If traces are clean → MOVE UP one layer
10. IMPLEMENT the transition one layer above
11. PROFILE that transition
12. If dirty → REDESIGN above → go to step 10
13. If clean → MOVE UP
14. REPEAT until you reach Apply and the source ASDL
15. RUN U.memo_measure_edit() for representative edits
16. If hit ratio < 90% → check structural sharing and identity boundaries
17. UPDATE ASDL definitions to reflect all changes made during implementation
```

The ASDL you end with may be significantly different from the ASDL you started with. That is expected and correct.

---

## 19. The quality gates

Before finalizing changes, check every one:

```
□ Save/load: round-trip preserves all user-expected authored state
□ Undo: reverting to prior ASDL node restores old behavior without repair logic
□ Completeness: every user-reachable state representable by the types
□ Minimality: every source field is an independent authored choice, not derived data
□ Orthogonality: supposedly independent fields actually vary independently
□ Testability: changed pure-layer functions testable with constructors and assertions
□ Incrementality: structural sharing and memoize locality preserved or improved
□ Phase clarity: each changed boundary describable with a single verb
□ View consistency: if source changed, source-to-view projection still correct
□ Trace cleanliness: leaf traces compile cleanly, no NYI/exit/return-to-interpreter from design issues
```

---

## 20. Minimal working checklist for agents

Before finishing any task, verify:

- [ ] I modeled the domain, not the implementation.
- [ ] I identified identity nouns, properties, and sum types.
- [ ] I updated the source ASDL before patching runtime code.
- [ ] I named the affected phase boundaries with real verbs.
- [ ] I wrote or at least mentally specified the leaf I want.
- [ ] I propagated leaf requirements upward through phases.
- [ ] I used `U.transition` / `U.terminal` for boundaries.
- [ ] I kept compiler-side boundary code pure and structural.
- [ ] I used `U.match` / `U.with` / `errs:each` instead of ad hoc structural logic.
- [ ] I did **not** excuse imperative pure-layer code on the grounds that it was "still pure" or "still deterministic."
- [ ] I stopped and revised the ASDL/phase whenever a pure boundary wanted manual loops, mutable accumulators, or repeated `kind` branching.
- [ ] I preserved structural sharing on edits.
- [ ] I kept compiled state inside `Unit.state_t`.
- [ ] I used `U.state_ffi` for production leaves, not `U.state_table`.
- [ ] I profiled leaves with `luajit -jv` and treated trace issues as ASDL diagnostics.
- [ ] I updated Event ASDL / reducer if interaction changed.
- [ ] I updated view projection if presentation changed.
- [ ] I checked save/load, undo, minimality, completeness, and testability.
- [ ] I ran `U.memo_measure_edit()` for representative edits.

If several boxes are unchecked, stop coding and fix the design.

---

## 21. Final instruction

Do not ask:

> "How do I implement this feature in the existing runtime architecture?"

Ask:

1. What is the correct source language for this feature?
2. What phases does it need?
3. What should the leaf compiler look like?
4. What ASDL makes that leaf trivial?
5. Does the leaf trace clean?

Then implement the answer, from the leaf up.

> **When implementation gets hard, the first suspect is the ASDL.** Not because the code is unimportant, but because in this pattern the code is downstream of the model. Fix the model, and the code becomes simple.
