# Insight: `gen, param, state` is the canonical machine layer above `Unit`

This note reframes the bottom of the compiler pattern more clearly.

The repository's runtime contract remains:

- `Unit.fn`
- `Unit.state_t`

But `Unit` is not the first machine concept.

`unit` now exposes that machine layer explicitly in the shared API:

- `U.machine_step(...)`
- `U.machine_iter(...)`
- `U.machine_run(...)`
- `U.machine_iterate(...)`
- `U.is_machine(...)`

And in LuaJIT:

- `U.machine_to_unit(...)`
- `U.terminal(...)` can auto-realize returned `Machine`s

The better articulation is:

> a terminal first defines a `gen, param, state` machine,
> then backend realization lowers that machine to `Unit { fn, state_t }`.

So the bottom of the pattern is best understood as:

1. **Machine IR**
2. **`gen, param, state` machine**
3. **`Unit { fn, state_t }` realization**

---

## 1. The core claim

`gen, param, state` is the canonical machine layer immediately above `Unit`.

Where:

- `gen` = the execution rule
- `param` = the stable machine environment
- `state` = the mutable machine state

Then backend realization lowers that to:

- `fn` = realized `gen`
- `state_t` = backend-owned layout carrying realized `param` and `state`

So the relationship is:

- `gen, param, state` = the first real machine model
- `Unit { fn, state_t }` = the packaged runtime artifact

This is a better explanation of terminals than thinking only in terms of `fn` and `state_t` from the start.

---

## 2. Why this is useful

`Unit { fn, state_t }` is a good terminal contract, but it compresses too much.

It hides that terminals usually have to solve three different design problems:

1. what must be baked into code shape?
2. what should remain as stable machine input?
3. what must remain mutable execution state?

`gen, param, state` makes those roles explicit.

That helps with:

- bake/live splits
- leaf-first design
- backend-neutral terminal reasoning
- LuaJIT vs Terra comparison
- deciding what the immediate feeder layer above the terminal should contain

---

## 3. The inspiration from `fun.lua`

A useful reference point is `fun.lua`, which normalizes rich iteration forms into:

- `(gen, param, state)`

That protocol is interesting here not because all leaves should become iterators, but because it reveals a general machine pattern.

In `unit`, that distinction is now explicit:

- **step machines** for one-call kernels / callbacks / parsers
- **iter machines** for traversal-shaped leaves that should plug directly into `U.each`, `U.fold`, `U.map`, `U.find`, and friends

So iterator benefits are available as a first-class machine family without forcing every terminal into iterator semantics.

That protocol is interesting here because it reveals a general machine pattern:

> efficient execution often wants a tiny regular machine with explicit code, environment, and evolving state.

That is exactly the kind of clarity terminal design needs.

---

## 4. The layer above `Unit`

If `Unit` is the backend packaging layer, then the layer immediately above it should be the explicit machine layer:

- `gen`
- `param`
- `state`

That gives us a clean terminal story:

### Terminal design
A terminal should first answer:

- what is the machine's `gen`?
- what is the machine's `param`?
- what is the machine's `state`?

### Terminal realization
Only then should backend realization answer:

- how does `gen` become `fn`?
- how do `param` and `state` become `state_t`?

This is the right separation.

---

## 5. The layer above `gen, param, state`

If `gen, param, state` is the canonical layer above `Unit`, then the layer above *that* should be a **Machine IR**.

Good names for it are:

- Machine IR
- terminal machine input
- specialized machine input

Its job is:

> make `gen, param, state` obvious.

A good Machine IR should already have consumed the kinds of knowledge that would otherwise force the leaf to keep thinking.
It should also make the machine's compiled wiring explicit: what execution can read, how it reaches those values, what it emits or updates, and what runtime-owned state shape it requires.

So by the time data reaches Machine IR, earlier phases should usually have consumed:

- tree shape that the leaf should not walk directly
- cross-reference resolution
- global lookups the leaf should not repeat
- large unresolved domain sum types where possible
- ambiguity about order, spans, routing, ownership, or family selection

And Machine IR should usually be:

- explicit about order, spans, refs, and access paths

- flat or nearly flat
- explicit about order and spans
- narrow in variants
- closed-world for the leaf's needs
- small enough to lower directly into a concrete machine

---

## 6. How to design Machine IR leaf-first

Do not begin by asking:

- is this a planning layer?
- is this a flattening layer?
- is this a classification layer?

Begin by asking:

> what typed input would make `gen, param, state` trivial to write?

That gives a much better design procedure.

### Step 1: write the leaf you want
Ask:

- what loop or execution rule do I want?
- what branches must already be gone?
- what stable data should it read?
- what mutable state should it own?

That gives you:

- `gen`
- `param`
- `state`

### Step 2: define Machine IR
Now define the smallest typed layer that feeds those three roles cleanly.

### Step 3: derive the layer above it
Once Machine IR is clear, ask what knowledge had to be consumed to produce it.

That usually reveals the correct verb for the layer above it:

- **flatten**
- **resolve**
- **classify**
- **plan**
- **schedule**
- **specialize**
- **project**

So the machine tells you what the previous phase must do.

---

## 7. What good Machine IR usually looks like

Machine IR should make these three splits obvious:

### `gen`-shaping facts
These are facts that alter code shape.

Examples:

- active families
- fixed operation sets
- helper selection
- ABI-relevant machine shape
- closed render/query family choices

### `param` data
These are stable machine inputs.
They should already be arranged so the machine reads typed access paths rather than performing semantic lookup.

Examples:

- packed item arrays
- region spans
- routing tables
- prepared coefficients
- batch payloads
- solved but non-mutable execution data

### `state` requirements
These are mutable execution-owned needs.

Examples:

- counters
- cursors
- live backend handles
- persistent kernel-owned runtime state
- per-child runtime slots

This does **not** mean every subsystem must literally define `Spec`, `Param`, and `State` records.
It means the Machine IR should make those roles easy to identify.
It also does **not** mean introducing a generic interpreted wiring DSL with runtime `Accessor`, `Processor`, or `Emitter` nodes. The whole point is that querying/wiring should already have been compiled into ordinary typed shapes such as spans, headers, refs, instances, resource specs, and runtime state schemas.

---

## 8. The ui2 example

`ui2` already discovered this shape.

At the bottom of the render path:

- `UiKernel` is the Machine IR
- `UiKernel.Spec` is close to `gen`-shaping input
- `UiKernel.Payload` is close to `param`
- installed runtime-owned storage is `state`

Then backend realization lowers that machine into:

- `fn`
- `state_t`

So `ui2`'s honest bottom-of-stack story is:

1. Machine IR (`UiKernel` in the current design)
2. canonical `gen, param, state`
3. `Unit { fn, state_t }`

That is why `UiKernel` was necessary: it is the layer that makes the machine explicit.

---

## 9. What this does **not** mean

This insight should not be overextended.

It does **not** mean:

- every public API must literally expose `gen, param, state`
- `Unit { fn, state_t }` should be replaced
- terminals should become iterator libraries
- pure phases should start storing backend runtime protocols directly

Instead, it means:

- `gen, param, state` is the canonical machine model above `Unit`
- Machine IR should feed that model cleanly
- backend realization should package that model as a `Unit`

So this is a clarification of the pattern, not a new runtime contract.

---

## 10. Canonical wording

A good way to phrase the pattern near the terminal is:

> `gen, param, state` is the canonical machine layer immediately above `Unit`.
> A terminal first defines that machine.
> A Machine IR layer above it exists to make those three roles explicit and easy to derive, including the machine's compiled wiring.
> Backend realization then lowers that machine to `Unit { fn, state_t }`, where `fn` embodies `gen` and `state_t` stores the realized `param/state` layout.

---

## 11. Short version

The canonical bottom of the pattern is:

1. **Machine IR**
2. **`gen, param, state`**
3. **`Unit { fn, state_t }`**

That is the cleanest way to explain:

- what a terminal is discovering
- what the feeder layer above it must provide
- and what `Unit` is actually packaging.
