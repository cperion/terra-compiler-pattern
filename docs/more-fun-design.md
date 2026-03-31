# more-fun design

`more-fun.lua` is a new optimization project derived from `fun.lua`.

The intent is not to dismiss `fun.lua`. `fun.lua` is already a very strong piece of code, and it teaches an important lesson used elsewhere in this repository:

> normalize rich iteration forms into one tiny regular machine.

For `fun.lua`, that machine is:

- `gen`
- `param`
- `state`

That normalization is a major reason the library performs well and traces well on LuaJIT.

But `fun.lua` is still a broad, compatibility-oriented functional iterator library. It keeps a large dynamic surface:

- many iterable source kinds
- many combinators
- multi-value iteration
- layered generator adapters
- runtime source detection at public boundaries
- recursive helper shapes in a few places
- param/state tuples represented as generic Lua tables

`more-fun.lua` starts from a different question:

> what is the narrowest, cleanest iterator source language we can compile into a faster runner for the cases this repository actually cares about?

## Curated public API

The public surface should be small, explicit, and expressive.

Canonical source constructors:

- `F.from(x)` — normalize an existing source
- `F.of(...)` — literal finite sequence
- `F.empty()` — explicit empty source
- `F.range(start, stop[, step])`
- `F.chars(text)` — character semantics
- `F.bytes(text)` — byte semantics
- `F.generate(gen, param, state)` — raw generator source
- `F.chain(...)` / `F.concat(...)` — concatenate sources

Canonical pipeline methods:

- transforms:
  - `:map(fn)`
  - `:filter(fn)`
  - `:take(n)`
  - `:drop(n)` / `:skip(n)`
- terminals:
  - `:each(fn)`
  - `:fold(fn, init)`
  - `:collect()`
  - `:count()`
  - `:head()` / `:first()`
  - `:nth(n)`
  - `:any(fn)`
  - `:all(fn)`
  - `:sum()`
  - `:min()`
  - `:max()`
- explicit compiler boundary:
  - `:plan(kind)`
  - `:compile(kind)`
- introspection:
  - `:shape()`

Compatibility aliases may remain where useful (`iter`, `wrap`, `foldl`, `totable`, `length`, etc.), but they should not define the taste of the library. The canonical surface should read like a small curated language.

## Core idea

Treat an iterator pipeline as a tiny program:

```text
source + op chain -> compiled runner
```

That gives a simple phase story:

1. **source normalization**
   - array
   - range
   - string (character semantics)
   - byte-string (numeric byte semantics)
   - raw generator triple
   - chain

2. **structural pipeline building**
   - `map`
   - `filter`
   - `take`
   - `drop`

3. **runner compilation**
   - compile the source family into one source-specialized loop
   - compile the op chain into one sink adapter

4. **terminal execution**
   - `each`
   - `foldl`
   - `totable`
   - `length`
   - `head`
   - `nth`
   - `any`
   - `all`
   - `sum`
   - `min`
   - `max`

This is more in the spirit of the repository's compiler pattern than the classic stack-of-adapters model.

## Narrowing policy

The first version of `more-fun.lua` is intentionally narrower than `fun.lua`:

- optimized for **single-value streams**
- optimized for **dense arrays** as the main source kind
- keeps ranges, strings, raw generators, and chains as supported families
- does **not** try to preserve the whole broad `fun.lua` compatibility surface yet

This is deliberate.

The design goal is to build the smallest honest machine first, then widen only when real use requires it.

## Machine shape

A `more-fun` pipeline is an immutable structural chain:

- root source node
- zero or more op nodes

The compiled machine is:

- one **source runner** specialized by source family
- one **sink adapter builder** specialized by the op chain
- one **terminal sink** provided by the reducer/collector

Execution shape:

```text
source_runner(build_sink(terminal_sink))
```

This keeps the main decisions out of the per-item hot path:

- source-kind dispatch happens once
- op-kind dispatch happens once, at compile time
- the inner loops become regular

## Why this is better aligned than a larger generic API

In repository terms:

- the **source family** is the phase-local source language
- the **op chain** is the transformation language
- the **compiled runner** is the terminal machine
- the **terminal sink** is the installed consumer

This is a small compiler.

## What `fun.lua` gets right

Reading `fun.lua` more closely suggests an important correction to the public `more-fun.lua` model.

`fun.lua` first normalizes many inputs into one execution machine:

- `gen`
- `param`
- `state`

That part is excellent.

But the more important detail is this:

> terminals in `fun.lua` run directly against that machine.

Examples:

- `foldl` is a direct `while` loop over `gen(param, state)`
- `any` / `all` are direct terminal loops
- `sum` is a direct terminal loop
- `min` / `max` seed once and then run a direct compare loop
- `nth` has source-family special cases for arrays and strings

So the hot machine in `fun.lua` is not:

```text
runner(sink)
```

It is closer to:

```text
compile(source, body, terminal) -> terminal-specific loop
```

The generator normalization is the machine IR, but the terminal is still compiled into the final loop shape.

## Current public `more-fun.lua` modeling bug

The current public `more-fun.lua` models the machine as:

```text
source_runner(build_sink(terminal_sink))
```

That is better than a stack of runtime adapters, but it is still the wrong final machine for the max-speed cases.

Why it loses:

- the terminal stays late
- every terminal call allocates a sink closure
- every item still pays sink-callback style control flow
- terminal-specific structure is not consumed before execution
- source-special terminal opportunities are hidden behind the sink ABI

That is why the `unit` project leaves are now fast while the public `more-fun.lua` API still loses badly to `fun.lua` on reused array/range workloads.

The issue is no longer just code quality. It is a modeling issue:

> the public machine is missing a terminal compilation phase.

## Corrected model for public `more-fun`

The public pipeline object should still author:

```text
Source + Pipe
```

But terminal calls should not execute through a generic sink ABI.

They should perform:

```text
Source + Pipe + Terminal -> TerminalPlan -> installed loop
```

That means the real public phases should be thought of as:

1. **normalize source**
2. **normalize pipe**
3. **classify machine shape**
4. **compile terminal-specific runner**
5. **cache that runner per pipeline + terminal shape**

The terminal is not an afterthought. The terminal is part of the compilation boundary.

## Public-runtime consequence

`more-fun.lua` should move toward caching terminal-specific installed runners rather than caching only a generic `runner(sink)` function.

In practical terms, that means:

- cache source/body classification once per pipeline node
- compile `sum`, `min`, `max`, `head`, `nth`, `any`, `all`, `foldl`, `totable`, `length` as separate runner families
- use direct terminal loops for hot public cases, just as `fun.lua` does
- keep the generic sink-builder path only as a fallback or transitional machine

That change would align the public API with the successful `more-fun/` `unit` project model.

The public implementation now also uses Crochet's proto realization model for terminal executors. In other words, the public hot path is no longer just "render a Lua chunk for a runner"; it is now more explicitly:

```text
shape + terminal -> plan -> proto body -> realized closure
```

The public pipeline exposes that compiler boundary with `:plan(kind)` and `:compile(kind)`.

A public plan currently records:

- source family and source proto
- pipe family and pipe proto
- exec family and exec proto
- terminal family and terminal proto
- install family and install proto
- `shape_key`
- `artifact_key`

So a user or benchmark can now inspect the public compiler's decision directly instead of inferring it from performance.

That is a better fit for the compiler pattern because the executor is now a small named realization unit with explicit captures, rather than an anonymous rendered fragment.

## Immediate goals

1. Make dense-array pipelines cheap and obvious.
2. Keep the pipeline immutable and structurally shareable.
3. Compile op chains once per pipeline node.
4. Support early stop cleanly for `head`, `nth`, `any`, and `all`.
5. Stay small enough that profiling can directly guide the next revision.

## String-family split

The project now distinguishes two string-adjacent source families:

- `StringSource` — yields 1-character strings
- `ByteStringSource` — yields numeric bytes

This is an ASDL correction, not a micro-optimization detail.

If the user means characters, the source language should say characters.
If the user means bytes, the source language should say bytes.

That distinction also matters to LuaJIT:

- character iteration tends to carry substring materialization semantics
- byte iteration gives the leaf a narrow numeric hot path

So the byte-string family is the honest fast-path family for ASCII / byte-oriented work.

## Likely next revisions

- specialized fast paths for all-map / all-filter / map+filter array pipelines
- direct terminal compilation for `foldl`, `sum`, `length`, `min`, `max`
- optional FFI-backed numeric array sources for stricter LuaJIT hot loops
- explicit multi-value stream family if real use demands it
- benchmark suite comparing `fun.lua` and `more-fun.lua` on repository workloads

## Proto universe direction

With the stronger `crochet.lua` proto model, the iterator/compiler work can now be understood more cleanly as a proto universe rather than only as ad hoc loop emission.

Useful proto families for `more-fun` are:

- **source protos**
  - array traversal
  - range traversal
  - string traversal
  - byte-string traversal
  - raw generator traversal
  - chain traversal

- **transform protos**
  - map application
  - predicate/guard application
  - control application (`drop`, `take`)

- **terminal protos**
  - `sum`
  - `foldl`
  - `head`
  - `nth`
  - `any`
  - `all`
  - `min`
  - `max`
  - `totable`
  - `length`

- **loop-shape protos**
  - plain direct loop
  - guarded linear loop
  - seeded extrema loop
  - chain process loop

That is a better ontology for the functional library than thinking only in terms of emitted loop strings. It keeps composition explicit longer, gives cleaner realization-unit boundaries, and makes closure/bytecode installation policy a backend decision rather than a modeling decision.

The recent Crochet refactor in `more-fun/boundaries/more_fun_lua_jit_plan.lua` moves in this direction: leaves are now authored as proto-shaped realization units instead of low-level rendered chunks.

## Current status

The initial implementation exists in `more-fun.lua`.

It should be treated as:

- a new optimized core
- a smaller and more intentional surface
- a design probe for what the real terminal iterator machine should be

not yet as a full replacement for `fun.lua`.
