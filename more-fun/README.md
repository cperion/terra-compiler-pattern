# more-fun

`more-fun` is a new optimization project for iterator pipelines.

The goal is not merely to reproduce `fun.lua`.
The goal is to design a **faster compiler-pattern version** of the same core idea:

> normalize iterable intent, shave out genericity in explicit phases, and end in one tiny fast closure.

## Domain summary

### Nouns

- source
- pipe
- predicate
- terminal
- loop
- body plan
- control plan
- runtime input
- call ref
- value ref
- LuaJIT fast plan

### Identity nouns

This project is intentionally small. The main receiver nouns are:

- `MoreFunSource.Spec`
- `MoreFunLowered.Spec`
- `MoreFunMachine.Spec`
- `MoreFunLuaJIT.Plan`

The important correction is that the LuaJIT leaf receiver is `Plan`, not a wrapper `Spec` record. The leaf should compile the real machine-near noun directly.

The helper records are phase-local structure, not long-lived user-authored identity nouns.

### Sum types

At source level:

- `Source`
- `Transform`
- `Terminal`

At machine level:

- `Loop`
- `TerminalPlan`

At LuaJIT lowering level:

- `MoreFunLuaJIT.Plan` is the specialized sum over fast-plan variants.

### Containment

The main authored shape is:

```text
Spec
├── Source
├── Pipe
│   ├── EndPipe
│   ├── MapPipe
│   ├── Filter/GuardPipe
│   ├── TakePipe
│   └── DropPipe
└── Terminal
```

The main lowered and machine-adjacent shapes are:

```text
Lowered.Spec
├── Source
├── Pipe          -- preserves order honestly
└── Terminal

Machine.Spec
├── Loop
├── BodyPlan
│   ├── FastBody(Map*, Guard*, Control)
│   └── GenericBody(Pipe)
└── TerminalPlan
```

### Coupling points

- source family ↔ loop family
- transform order ↔ which fast bodies are semantically valid
- predicate shape ↔ whether the leaf can inline comparisons or must call a fallback function
- transform chain ↔ body fusion
- terminal kind ↔ final closure template
- loop family ↔ LuaJIT fast-path choice

## String vs byte-string

`more-fun` now treats these as different source families on purpose.

### `StringSource`

Use this when the semantic item is a **1-character string**.

Examples:
- case mapping
- character classification with string predicates
- lexeme-style character pipelines

Hot-path value shape:
- `"a"`, `"b"`, `"c"`

### `ByteStringSource`

Use this when the semantic item is a **numeric byte**.

Examples:
- byte-class predicates
- ASCII-oriented scans
- numeric reductions over bytes
- max-speed string iteration where byte semantics are acceptable

Hot-path value shape:
- `97`, `98`, `99`

### Why the split exists

If the leaf receives characters as 1-char strings, the hot path must materialize character values.
If the leaf receives bytes as numbers, LuaJIT gets a much cleaner numeric loop.

So the split is not an optimization hack; it is a semantic distinction that also improves code generation.

Rule of thumb:
- want characters → `StringSource`
- want bytes → `ByteStringSource`

These coupling points determine the phase structure.

## Phase plan

```text
MoreFunSource
  - authored pipeline language
  - verb: lower

MoreFunLowered
  - normalized source family + order-preserving pipe
  - verb: define_machine

MoreFunMachine
  - explicit loop/body/terminal machine IR
  - body is either `FastBody` or `GenericBody`
  - verb: lower_luajit

MoreFunLuaJIT
  - LuaJIT-specific fast-plan variants with genericity shaved out
  - receiver: `Plan`
  - verb: install
```

## Leaf-driven constraints

The final installed closure should:

- know its loop family already
- know its terminal family already
- know whether predicates are inline numeric comparisons or fallback calls
- avoid per-item source-kind dispatch
- avoid per-item op-kind dispatch
- avoid sink callback indirection in the hot path
- avoid opaque predicate calls when a predicate algebra can express the intent directly
- keep counters and accumulators in simple locals or fixed state
- treat fallback generic execution as a separate plan, not as a tax on fast plans

## Current project status

The project directory has been initialized as a proper `unit` project with:

- `schema/app.asdl`
- `pipeline.lua`
- `unit_project.lua`
- scaffolded boundaries in `boundaries/`

The boundaries are currently scaffolds and are intended to be filled in leaf-first.

## Bench notes

There is now a small comparison harness in:

- `more-fun/boundaries/more_fun_lua_jit_plan_bench.lua`

Useful comparisons:
- `bench_string_vs_byte_to_table()`
- `bench_string_vs_byte_any()`

These are meant to make the semantic/performance split visible, not to serve as a full benchmark suite.

## Immediate implementation direction

1. Start at the true leaf: `MoreFunLuaJIT.Plan:install()`.
2. Make each plan variant compile directly to one final LuaJIT `Unit`.
3. Profile those leaves with `luajit -jv` and treat every trace complaint as an ASDL diagnostic on `MoreFunMachine`.
4. Only after the leaves are honest and tracing clean should `MoreFunMachine.Spec:lower_luajit()` be implemented to feed them.
5. `MoreFunLowered.Spec:define_machine()` must preserve source order honestly and only classify to `FastBody` when the ordered pipe really matches a valid fast pattern.
6. Only then should `MoreFunSource.Spec:lower()` be implemented.
