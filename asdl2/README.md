# asdl2

`asdl2` is the compiler-shaped rewrite of `asdl.lua`.

It is no longer modeled as a long semantic chain with intermediate compatibility phases.
The current converged story is:

```text
Asdl2Text -> Asdl2Source -> Asdl2Catalog -> Asdl2Lowered -> Asdl2Machine -> native install leaf
```

The important architectural rule is still:

> lower machine first, then recurse upward only after the leaf is honest, benchmarked, and stable.

---

## Main path

The real main path is:

1. `Asdl2Text.Spec:parse() -> Asdl2Source.Spec`
2. `Asdl2Source.Spec:catalog() -> Asdl2Catalog.Spec`
3. `Asdl2Catalog.Spec:classify_lower() -> Asdl2Lowered.Schema`
4. `Asdl2Lowered.Schema:define_machine() -> Asdl2Machine.Schema`
5. `Asdl2Machine.Schema:install(ctx) -> Context`

There are no compatibility phases in the modeled path.

Retired phases removed from the architecture:

- `Asdl2Resolved`
- `Asdl2Runtime`
- `Asdl2MachineIR`
- `Asdl2Install`

Those phases were useful during expansion, but they stopped consuming unique knowledge and were collapsed out.

---

## What each phase owns

### `Asdl2Text`
Owns raw authored text.

### `Asdl2Source`
Owns only the authored language:
- modules
- type definitions
- products
- sums
- constructors
- fields
- authored type refs
- authored cardinality

### `Asdl2Catalog`
Consumes lookup and scope ambiguity.
It owns:
- visible scopes
- typed lookup targets
- product headers
- sum headers
- variant headers
- typed refs ready for lowering

### `Asdl2Lowered`
Owns machine-facing schema truth.
It owns:
- lowered records
- lowered sums
- field representation choice
- check payloads
- arena slots
- cache slots
- cache refs
- ctor family
- class ids / family ids / variant tags

This is the key semantic lowering phase.

### `Asdl2Machine`
Owns canonical machine framing:
- `gen`
- `param`
- `state`

`param` forwards lowered schema truth.
`state` owns arena/cache runtime state declarations.
`gen` carries only the remaining code-shaping families actually used by the leaf.

### Native install leaf
The LuaJIT leaf in `asdl2/asdl2_native_leaf_luajit.lua` consumes `Asdl2Machine.Schema` directly.

Backend naming such as generated ctype names is now leaf-local, not carried as a separate public ASDL phase.

---

## Domain summary

### Source nouns
- spec
- module
- type definition
- type expression
- constructor
- field
- type ref
- cardinality

### Catalog nouns
- scope
- lookup entry
- lookup target
- product header
- sum header
- variant header

### Lowered nouns
- record
- sum
- field
- check spec
- arena slot
- cache slot
- cache ref
- ctor family

### Machine nouns
- `gen`
- `param`
- `state`

### Backend nouns
These are now mostly leaf-local:
- ctype names
- cdefs
- metatype installation
- namespace installation
- per-context runtime state hookup

---

## Why the collapse happened

`asdl2` went through the normal convergence cycle:

```text
DRAFT -> EXPANSION -> COLLAPSE
```

The removed phases were real during exploration, but once lookup was consumed in `catalog()` and lower truth was owned explicitly in `Asdl2Lowered`, the following became redundant:

- `resolve()` as a separate knowledge-consuming phase
- `lower_runtime()`
- `organize_machine_ir()`
- `emit_install()`
- a public `Asdl2Install` ASDL

The remaining path is the smallest one that still makes the leaf honest.

---

## Boundary inventory

Current boundaries:

- `Asdl2Text.Spec:parse()`
- `Asdl2Source.Spec:catalog()`
- `Asdl2Catalog.Spec:classify_lower()`
- `Asdl2Lowered.Schema:define_machine()`
- `Asdl2Machine.Schema:install(ctx)`

If a new feature cannot fit this shape, first suspect the ASDL.

---

## Bench/profile surface

Current main bench/profile modules are:

- `asdl2/asdl2_parse_bench.lua`
- `asdl2/asdl2_parse_profile.lua`
- `asdl2/asdl2_catalog_bench.lua`
- `asdl2/asdl2_catalog_profile.lua`
- `asdl2/asdl2_classify_lower_bench.lua`
- `asdl2/asdl2_classify_lower_profile.lua`
- `asdl2/asdl2_define_machine_bench.lua`
- `asdl2/asdl2_define_machine_profile.lua`
- `asdl2/asdl2_install_bench.lua`
- `asdl2/asdl2_install_profile.lua`
- `asdl2/asdl2_full_bench.lua`
- `asdl2/asdl2_full_profile.lua`
- `asdl2/asdl2_native_leaf_bench.lua`
- `asdl2/asdl2_native_leaf_profile.lua`
- `asdl2/asdl2_vs_terra_asdl_bench.lua`

Retired compatibility bench/profile files were removed along with the retired phases.

---

## Environment variable naming

Bench/profile env vars now follow explicit boundary names.
Examples:

- `ASDL2_PARSE_*`
- `ASDL2_CATALOG_*`
- `ASDL2_CLASSIFY_LOWER_*`
- `ASDL2_DEFINE_MACHINE_*`
- `ASDL2_INSTALL_*`
- `ASDL2_FULL_*`
- `ASDL2_NATIVE_*`

Old `ASDL2_L1..L5_*` compatibility names are gone from the active main-path harnesses.

---

## Current design judgment

The current architecture says:

- lookup belongs in `catalog()`
- machine-facing truth belongs in `Asdl2Lowered`
- backend rendering belongs in the native leaf
- `Asdl2Machine` remains as the honest `gen / param / state` frame

If future profiler pressure appears, the next question is not “which helper should be tuned?”
The next question is:

> which distinction is still hidden, duplicated, or over-modeled in the ASDL?
