# AGENTS.md

This repository uses the **Terra Compiler Pattern**. Any coding agent working here must treat this file as the operational guide for how to design, revise, and implement features.

This is not a generic “be careful” document. It is a concrete workflow and a set of hard constraints.

If you follow this file, design and implementation stay aligned. If you violate it, you will create accidental interpreters, hidden state, phase leaks, and brittle code.

---

## 0. What this repository is

This codebase treats interactive software as a **compiler**:

- **Source ASDL** is the user-facing language.
- **Events** are the input language.
- **Apply** is the pure reducer from `(state, event) -> state`.
- **Transitions** narrow unresolved decisions across phases.
- **Terminals** compile phase-local ASDL into `Unit { fn, state_t }`.
- **Execution** runs compiled native code until the source changes.

The central idea is simple:

> **The ASDL is the architecture.**

Everything else is derived from it.

---

## 1. Authority and source of truth

When you work in this repository, use these files in this order:

1. **`modeling-programs-as-compilers.md`**
   - Source of truth for **how to model the domain**.
   - Use this for nouns, identity, sum types, containment, coupling points, phases, quality tests, and design revision.

2. **`terra-compiler-pattern.md`**
   - Source of truth for the **overall architecture**.
   - Use this for the six primitives, event loop, incremental compilation, hot swap, Unit semantics, elimination of infrastructure, and backend framing.

3. **`unit.t`**
   - Source of truth for the **actual runtime API and implementation vocabulary**.
   - Use this for `U.new`, `U.leaf`, `U.compose`, `U.transition`, `U.terminal`, `U.with_fallback`, `U.with_errors`, `U.errors`, `U.match`, `U.with`, `U.inspect`, `U.hot_slot`, and `U.app`.

If a design idea conflicts with these files, change the design idea. Do not work around the pattern.

---

## 2. The non-negotiable rules

These rules are mandatory.

### 2.1 Start from ASDL, not runtime machinery

Do not begin with handlers, services, managers, stores, registries, plugin APIs, or runtime object graphs.

Start with:

- the domain nouns
- the source ASDL
- the phase boundaries
- the desired leaf compilers

### 2.2 Model the domain, not the implementation

The source phase must describe what the **user works with**, not how the program happens to run.

Good source nouns:

- track, clip, device, parameter, graph, node
- document, block, span, cursor
- sheet, cell, formula, chart

Bad source nouns:

- callback, buffer pool, thread handle, mutex, renderer state, service locator

### 2.3 The source ASDL is the specification

The source ASDL must capture all independent user choices and all user-visible persisted state.

If save/load would lose something the user expects to persist, it belongs in the source ASDL.

If undo requires custom repair logic, the source ASDL is wrong.

### 2.4 Identity nouns must be explicit and stable

Every persistent, independently editable thing gets:

- its own ASDL node
- a stable ID
- `unique` if it is a concrete ASDL type

IDs identify the thing, not its position.

Reordering must not change identity.

### 2.5 Every domain “or” is a sum type

If the domain says:

- clip is audio **or** MIDI
- track is audio **or** group **or** master
- selection is cursor **or** range

then the ASDL must say the same thing as an enum / tagged union.

Do not encode domain variants with strings when the set is fixed.

### 2.6 Cross-references are IDs, never Lua object pointers

If one node references another outside containment:

- use `target_id`
- resolve it in a later phase
- validate it globally

Never store live Lua references in source ASDL.

### 2.7 Phases must consume knowledge

Each phase boundary must resolve a real decision.

Typical verbs:

- `lower`
- `resolve`
- `classify`
- `schedule`
- `compile`
- `project`

If you cannot name the verb, the phase is probably not real.

### 2.8 Later phases should narrow, not widen

As you move through phases:

- sum types should decrease
- decisions should be consumed
- shapes should become more concrete

The terminal input should be as flat and monomorphic as possible.

A scheduled phase should usually contain **zero large domain sum types**.

### 2.9 Every pure-layer function must be expressible as a LuaFun-style transform

Transitions, reducers, projections, and helpers in the pure layer should read like:

- map
- filter
- reduce / fold
- flatmap
- structural construction
- `U.match`
- `U.with`

If a function resists that style, do **not** fight the code into shape. Fix the ASDL or insert the missing phase.

Signs the ASDL is wrong:

- you need mutable accumulators
- you need global context objects
- you need sibling lookups everywhere
- you need imperative branching over string tags
- you need a hidden environment to make tests pass

This rule also applies to **compiler-side backend boundaries**.

A function of the form:

- ASDL -> ASDL
- ASDL -> Unit

is still part of the **pure layer**, even if the generated Terra code will later talk to SDL, OpenGL, fonts, or OS APIs.

So:

- the **boundary implementation** should stay functional and structural
- use `U.match`, `U.with`, `map`, `filter`, `reduce`, `flatmap`, and small pure helpers where needed
- use `U.terminal` for ASDL -> Unit boundaries
- keep mutable stacks, GL state changes, and other imperative mechanics inside the **emitted Terra/native code** or inside `Unit.state_t`, not in the Lua-side boundary construction

### 2.10 Every boundary is memoized

All pure stage boundaries must go through:

- `U.transition(fn)` for ASDL → ASDL
- `U.terminal(fn)` for ASDL → Unit

Do not invent parallel caching systems, dirty flags, or invalidation frameworks unless the pattern truly cannot express the problem.

### 2.11 Every compiled artifact is a `Unit`

Compiled outputs must be represented as:

- `Unit { fn, state_t }`

Use:

- `U.leaf` for leaf codegen
- `U.compose` for structural composition
- `U.new` for validated construction

Do not separate code generation from state ABI ownership.

### 2.12 Event input must be an Event ASDL

Interactive inputs are not ad hoc callbacks. They are an input language.

Represent them as a sum type.

Handle them with a pure reducer:

- `(state, event) -> state`
- typically memoized via `U.transition`
- exhaustively matched via `U.match`

### 2.13 The view is a separate ASDL projection

Do not force UI shape into the source ASDL.

Instead:

- source ASDL models the domain
- view ASDL models presentation
- projection maps source → view
- view has its own phases if needed

Carry semantic refs through projection so errors and selections can map back to source nodes.

### 2.14 Tests are constructor + assertion

Pure-layer tests should usually look like:

1. construct ASDL input
2. call function
3. assert output

Avoid mocks, fixtures, setup frameworks, or hidden context.

If a function needs those, it likely has a design problem.

---

## 3. How an agent must work on any task

For every non-trivial task, follow this order.

### Step 1: Reconstruct the domain slice

Before coding, identify:

- the user-visible nouns involved
- which are identity nouns vs properties
- which choices are sum types
- where the feature sits in containment
- whether it introduces new coupling points

Always reason in domain language first.

### Step 2: Locate or revise the source ASDL

Ask:

- Is the feature already representable?
- If not, which source types are missing?
- Is the new data independent user choice, derived data, or runtime state?

Rules:

- **independent user choice** → source phase
- **derived semantic data** → later phase
- **compiled/native execution state** → `Unit.state_t`

### Step 3: Define or update the phase path

Determine the exact path from user vocabulary to compiled output.

At minimum, identify:

- source phase name
- subsequent phases
- what each phase consumes
- which boundaries must be added or changed

If a function is currently doing multiple unrelated jobs, split the phase.

### Step 4: Write the leaf you want to write

Design the terminal leaf first.

Ask:

- What does the generated code actually need?
- What fields must be present on the terminal input node?
- What should already be resolved by then?

Then propagate those needs upward.

This is the key implementation-discovery loop:

- leaf demands data
- lower phase must provide it
- if not possible, revise earlier phase
- recurse until the source ASDL is correct

### Step 5: Only then implement the pure boundaries

Implement transitions and terminals only after the phase and ASDL story is coherent.

Use:

- `U.match` for sum types
- `U.with` for structural updates
- `U.errors` / `U.with_errors` for structural error collection
- `U.with_fallback` only where a neutral substitution is meaningful
- `U.transition` and `U.terminal` for boundary memoization

### Step 6: Wire interactive behavior through Event ASDL + Apply

If the feature changes interaction:

- add or revise Event variants
- update the reducer
- keep reducer pure
- preserve structural sharing on edits

### Step 7: Add or revise the view projection if the feature is visible

If the source model changed, decide whether the view projection must change too.

Never cram presentation-only concerns into the source model unless the user expects them to persist as part of authored state.

### Step 8: Validate against the pattern checklists

Before declaring the task done, explicitly check:

- save/load
- undo
- completeness
- minimality
- orthogonality
- testability
- incremental compilation impact
- view projection impact

---

## 4. Required deliverables for agent work

When doing serious design or implementation, an agent should usually produce these artifacts in order.

### 4.1 Domain summary

A concise restatement of:

- nouns
- identity nouns
- sum types
- containment
- coupling points

### 4.2 ASDL proposal or ASDL diff

Prefer explicit proposed type changes over vague prose.

Show:

- new/changed records
- new/changed enums
- moved fields
- removed derived fields

### 4.3 Phase plan

List phases in order and name the verb for each boundary.

### 4.4 Boundary inventory

List which functions must exist or change.

Examples:

- `Editor.Device:lower()`
- `Authored.Graph:resolve()`
- `Resolved.Project:classify()`
- `Scheduled.Job:compile()`
- `Editor.Project:project_view()`

### 4.5 Leaf-driven constraints

State what each important leaf requires from its input.

This is how the ASDL stays honest.

### 4.6 Implementation

Only after the above is coherent.

### 4.7 Validation notes

Explicitly say what was checked and what remains uncertain.

---

## 5. Rules for creating or revising ASDL

Use this method every time.

### 5.1 List the nouns

Write down everything the user sees, names, edits, saves, loads, or references.

### 5.2 Separate identity from property

Identity nouns:

- persist
- can be pointed at as “that one”
- can usually be edited independently

Properties:

- belong on identity nouns
- do not need separate identity

### 5.3 Find all sum types

Look for every domain “or”.

Each must become a sum type unless it is truly open-ended text.

### 5.4 Draw containment

Parents own children.

Containment should make incremental compilation natural.

If edits to one subtree should not disturb siblings, they should not be flattened together too early.

### 5.5 Find coupling points

A coupling point is where two otherwise separate parts need each other’s information.

Use coupling points to decide:

- phase order
- when to merge a phase
- when to insert a new phase

### 5.6 Keep source ASDL minimal and complete

Include:

- independent user choices
- persisted authored state
- stable IDs

Exclude:

- derived coefficients
- scheduled buffer slots
- compiled opcodes
- runtime history state owned by Units

### 5.7 Prefer typed records and enums over bags and strings

Do not model fixed domain structure with:

- anonymous Lua tables
- free-form string tags
- ad hoc maps

Use explicit types.

### 5.8 Treat ASDL revision as normal, not as failure

You will not get the ASDL perfect on the first pass.

Revision is expected.

When implementation reveals resistance, revise the ASDL first.

---

## 6. What implementation resistance means

When code feels wrong, interpret it diagnostically.

### Symptom: missing field at a leaf
Meaning:
- the upstream ASDL does not provide required knowledge

Fix:
- add or move the field in the correct phase
- propagate it through transitions

### Symptom: repeated lookups by ID in many places
Meaning:
- a resolution phase is missing or incomplete

Fix:
- add a resolved phase that attaches or validates the needed information structurally

### Symptom: mutable accumulation is required
Meaning:
- the node boundaries or phase are wrong

Fix:
- restructure data so transforms are local and compositional

### Symptom: one boundary function is enormous
Meaning:
- too much unresolved knowledge is arriving at once
- identity noun may be too coarse
- a phase may be missing

Fix:
- split the phase or split the type

### Symptom: the function is trivial and meaningless
Meaning:
- the type may be too fine-grained
- the phase distinction may not be real

Fix:
- merge nodes or phases

### Symptom: you need `context`, `env`, or service access everywhere
Meaning:
- the function is impure or the phase is underspecified

Fix:
- move required data into the ASDL of the proper phase

### Symptom: tests need mocks or elaborate setup
Meaning:
- hidden dependencies are leaking into the pure layer

Fix:
- fix the design, not the test harness

---

## 7. Implementation rules inside this framework

### 7.1 Use `U.match` for sum-type dispatch

Do not hand-roll string dispatch when working over ASDL variants.

### 7.2 Use `U.with` for structural updates

Do not mutate ASDL nodes in place.

Edits must create new nodes and preserve structural sharing for unchanged subtrees.

### 7.3 Use `U.errors` and semantic refs for recoverable structure-local failures

If a subtree fails to compile or lower:

- collect an error with a semantic ref
- substitute a neutral if appropriate
- let unaffected siblings continue

### 7.4 Use `U.leaf` for leaf code generation

Leaf terminals should own exactly the state they need.

Bake compile-time-known values into Terra code whenever possible.

But keep the distinction explicit:

- **building the Unit** is compiler work and should stay pure / structural
- **running the emitted Terra code** may be imperative if the backend requires it

Do not smuggle imperative compiler logic into the Lua side just because the generated code will be imperative.

### 7.5 Use `U.compose` for structural aggregation

Parent Units own child state structurally.

Do not invent independent runtime state lifecycles when structural composition suffices.

### 7.6 Use `U.hot_slot` or equivalent pattern for live swap

Do not build extra runtime machinery for hot reload if the compiled output already fits the `Unit`/pointer-swap model.

### 7.7 Use `U.app` for the basic loop unless there is a real reason not to

The default loop is:

- poll
- apply
- compile
- execute

Do not create extra orchestration layers unless absolutely necessary.

### 7.8 Use `U.inspect` to derive scaffolding and progress where useful

Do not build separate metadata registries if the ASDL and methods already carry the information.

---

## 8. Forbidden shortcuts and anti-patterns

Do **not** introduce these casually.

### 8.1 Modeling implementation details in source ASDL

Examples:

- thread handles
- mutexes
- callbacks
- renderer caches
- buffer slots
- LLVM-specific compiled artifacts

### 8.2 Mixing phases in one type

Do not store authored choices together with:

- derived semantic data
- scheduled layout/buffer allocations
- compiled/native state

### 8.3 Strings instead of enums for closed domains

If the set is known, type it.

### 8.4 Lua object references across the authored tree

Use IDs and resolution.

### 8.5 Raw table maps in source ASDL

Use typed lists of records unless you are clearly outside the authored model.

### 8.6 Deep-copy edits

Deep-copying destroys structural identity and defeats memoization.

### 8.7 Hidden mutable state in pure-layer functions

No global registries, mutable closures, or implicit context dependencies.

This includes compiler-side terminal construction for backend leaves. Do not build ASDL -> Unit boundaries around ad hoc mutable Lua-side stacks, caches, or orchestration state unless that state is explicitly modeled as phase data or `Unit.state_t`.

### 8.8 Runtime dispatch for compile-time-known decisions

If the compiler knows the device kind, chart type, block variant, or operation, bake it into the output.

### 8.9 Hand-built infrastructure that the pattern already eliminates

Be suspicious of adding:

- state managers
- dependency injection containers
- observer buses
- invalidation graphs
- custom build caches
- plugin ABI layers
- heavy test harnesses

The first question should always be:

> “What information is missing from the ASDL or phase structure that made this seem necessary?”

---

## 9. How to handle common task types

### 9.1 New feature

1. identify domain nouns
2. extend source ASDL
3. identify phase impacts
4. define desired leaves
5. update transitions/terminals
6. add events/reducer changes if interactive
7. update view projection if visible
8. test with constructor + assertion

### 9.2 Bug fix

First classify the bug:

- bad ASDL
- missing phase
- incorrect transition
- incorrect terminal/leaf
- reducer bug
- projection bug

Do not patch symptoms in runtime code if the actual problem is in modeling.

### 9.3 Refactor

The goal is usually one of:

- better ASDL minimality
- better phase separation
- better leaf locality
- better structural sharing
- removal of accidental runtime interpretation

A refactor that preserves behavior but clarifies the phase model is good.

### 9.4 Performance work

First ask whether performance should come from:

- fixing memoization boundaries
- improving structural sharing
- narrowing sum types earlier
- baking more constants into leaves
- splitting a coarse identity noun

Do not start with ad hoc micro-optimization if the architecture is forcing unnecessary recompilation or dispatch.

### 9.5 Porting to another backend

Only the backend-specific leaf compilation and runtime hookup should change.

The pure layer should stay structurally the same.

---

## 10. The quality gates every agent must use

Before finalizing changes, check these.

### 10.1 Save/load gate

Would a round-trip preserve all user-expected authored state?

### 10.2 Undo gate

Would reverting to the prior ASDL node restore the old behavior without custom repair logic?

### 10.3 Completeness gate

Can every user-reachable state be represented by the types?

### 10.4 Minimality gate

Is every source field an independent authored choice rather than derived data?

### 10.5 Orthogonality gate

Do supposedly independent fields actually vary independently?

If not, the type likely needs a sum-type split.

### 10.6 Testability gate

Can the changed pure-layer functions be tested with simple constructors and assertions?

### 10.7 Incrementality gate

Did the change preserve or improve structural sharing and memoize locality?

### 10.8 Phase clarity gate

Can each changed boundary be described with a single verb?

### 10.9 View consistency gate

If the source changed, is the source-to-view projection still correct?

---

## 11. What an agent should say when proposing design changes

When presenting a design or code change, use this structure:

1. **Domain change**
   - what user concept is being added or corrected

2. **ASDL change**
   - exact type additions/removals/moves

3. **Phase impact**
   - which phases and boundaries change

4. **Leaf requirement**
   - what the terminal code needs and why

5. **Implementation plan**
   - transitions, terminals, reducer, projection, tests

6. **Validation**
   - which quality gates were checked

This keeps design and implementation coupled.

---

## 12. Repository-specific expectations

When working in this repository specifically:

- Use the terminology and patterns from:
  - `modeling-programs-as-compilers.md`
  - `terra-compiler-pattern.md`
  - `unit.t`
- Prefer the existing `U.*` vocabulary over inventing parallel helpers.
- Treat compiler-side boundary code as pure code. Backend terminals are not an exception just because their emitted code talks to SDL/GL/TTF.
- Treat the current docs as a coherent pattern, not as optional inspiration.
- When adding examples or helpers, reinforce the pattern rather than diluting it.
- If you must extend the framework, do it in the same spirit: small, compositional, reflective, no new DSL unless absolutely forced.

---

## 13. The core mental model to keep at all times

Keep these truths in mind:

- The user edits a program.
- The source ASDL is that program.
- Events edit that program.
- Transitions narrow that program.
- Terminals compile that program.
- Units are the compiled artifacts.
- Execution runs compiled artifacts until the program changes again.

And the deepest rule:

> **When implementation gets hard, the first suspect is the ASDL.**

Not because the code is unimportant, but because in this pattern the code is downstream of the model.

Fix the model, and the code becomes simple.

---

## 14. Minimal working checklist for agents

Before finishing any task, verify:

- [ ] I modeled the domain, not the implementation.
- [ ] I identified identity nouns, properties, and sum types.
- [ ] I updated the source ASDL before patching runtime code.
- [ ] I named the affected phase boundaries with real verbs.
- [ ] I wrote or at least mentally specified the leaf I want.
- [ ] I propagated leaf requirements upward through phases.
- [ ] I used `U.transition` / `U.terminal` for boundaries.
- [ ] I kept compiler-side boundary code pure and structural.
- [ ] I used `U.match` / `U.with` instead of ad hoc structural logic.
- [ ] I preserved structural sharing on edits.
- [ ] I kept compiled state inside `Unit.state_t`.
- [ ] I updated Event ASDL / reducer if interaction changed.
- [ ] I updated view projection if presentation changed.
- [ ] I checked save/load, undo, minimality, completeness, and testability.

If several boxes are unchecked, stop coding and fix the design.

---

## 15. Final instruction to any agent

Do not ask, “How do I implement this feature in the existing runtime architecture?”

Ask:

1. What is the correct source language for this feature?
2. What phases does it need?
3. What should the leaf compiler look like?
4. What ASDL makes that leaf trivial?

Then implement the answer.
