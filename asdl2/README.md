# asdl2

`asdl2` is the compiler-shaped rewrite of `asdl.lua`.

It is structured as a standard unit project.

---

## Project structure

```text
asdl2/
  schema/
    app.asdl                              # canonical ASDL source
  pipeline.lua                            # phase order
  unit_project.lua                        # project config
  boundaries/
    asdl2_text_spec.lua                   # Asdl2Text.Spec:tokenize()
    asdl2_token_spec.lua                  # Asdl2Token.Spec:parse()
    asdl2_source_spec.lua                 # Asdl2Source.Spec:catalog()
    asdl2_catalog_spec.lua                # Asdl2Catalog.Spec:classify_lower()
    asdl2_lowered_schema.lua              # Asdl2Lowered.Schema:define_machine()
    asdl2_machine_schema_luajit.lua       # Asdl2Machine.Schema:lower_luajit()
    asdl2_luajit_schema_luajit.lua        # Asdl2LuaJIT.Schema:install()
  asdl2_boot.lua                          # bootstrap runtime
  asdl2_schema_boot.lua                   # generated bootstrap (from schema/app.asdl)
  asdl2_schema.lua                        # runtime entry point
  asdl2_native_leaf_luajit.lua            # LuaJIT native leaf library
  asdl2_bench_fixture.lua                 # bench fixture
  asdl2_source_fixture.lua                # source fixture
  generate_schema_boot.lua                # regenerates asdl2_schema_boot.lua
```

---

## Main path

```text
Asdl2Text -> Asdl2Token -> Asdl2Source -> Asdl2Catalog -> Asdl2Lowered -> Asdl2Machine -> Asdl2LuaJIT -> install
```

1. `Asdl2Text.Spec:tokenize()` → `Asdl2Token.Spec`
2. `Asdl2Token.Spec:parse()` → `Asdl2Source.Spec`
3. `Asdl2Source.Spec:catalog()` → `Asdl2Catalog.Spec`
4. `Asdl2Catalog.Spec:classify_lower()` → `Asdl2Lowered.Schema`
5. `Asdl2Lowered.Schema:define_machine()` → `Asdl2Machine.Schema`
6. `Asdl2Machine.Schema:lower_luajit()` → `Asdl2LuaJIT.Schema`
7. `Asdl2LuaJIT.Schema:install(ctx)` → Context

---

## CLI inspection

```bash
luajit unit.lua status asdl2
luajit unit.lua pipeline asdl2
luajit unit.lua boundaries asdl2
luajit unit.lua backends asdl2
luajit unit.lua path asdl2 Asdl2Text.Spec
luajit unit.lua backend-path asdl2 Asdl2Machine.Schema luajit
luajit unit.lua scaffold-file asdl2 Asdl2Text.Spec
```

---

## What each phase owns

### `Asdl2Text`
Owns raw authored text.

### `Asdl2Token`
Owns the token language:
- typed token stream
- punctuation/keyword/identifier distinction
- token byte spans

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

### `Asdl2LuaJIT`
This is the backend-facing lowering phase.
It owns backend-static truth the leaf should not rediscover:
- ctype names
- backend field plans
- access plans
- ctor plans
- export plans
- sum install shape

### Native install leaf
The LuaJIT leaf in `asdl2_native_leaf_luajit.lua` consumes `Asdl2LuaJIT.Schema` directly.

Mutable backend runtime state still stays in the leaf/runtime, not in the schema.

---

## Bootstrap

`asdl2` self-bootstraps its own type system:

1. `schema/app.asdl` is the canonical ASDL source
2. `generate_schema_boot.lua` parses it and generates `asdl2_schema_boot.lua`
3. `asdl2_boot.lua` provides the bootstrap runtime (`Boot.build()`, `Boot.List()`)
4. `asdl2_schema.lua` loads the boot context and installs boundaries from `boundaries/`

For unit CLI inspection, the standard `asdl.lua` parser loads `schema/app.asdl` directly.
For runtime, `asdl2_schema.lua` uses the asdl2 boot context.

To regenerate the bootstrap after schema changes:

```bash
luajit asdl2/generate_schema_boot.lua
```

---

## Bench/profile surface

Current bench/profile files remain at the project root level:

- `asdl2_parse_bench.lua` / `asdl2_parse_profile.lua`
- `asdl2_catalog_bench.lua` / `asdl2_catalog_profile.lua`
- `asdl2_classify_lower_bench.lua` / `asdl2_classify_lower_profile.lua`
- `asdl2_define_machine_bench.lua` / `asdl2_define_machine_profile.lua`
- `asdl2_lower_luajit_bench.lua` / `asdl2_lower_luajit_profile.lua`
- `asdl2_install_bench.lua` / `asdl2_install_profile.lua`
- `asdl2_full_bench.lua` / `asdl2_full_profile.lua`
- `asdl2_native_leaf_bench.lua` / `asdl2_native_leaf_profile.lua`
- `asdl2_vs_terra_asdl_bench.lua`

These will be migrated to boundary sidecars in a future pass.

---

## Current trusted checkpoint

Recent stable checkpoint on the live path:

- install/setup:
  - `build_luajit_avg_ms: ~1.2`
  - `build_plus_install_avg_ms: ~1.3`
- full path:
  - `full_distinct_avg_ms: ~1.6`
  - `build_plus_full_avg_ms: ~1.6`
- hot native leaf paths remain excellent:
  - plain ctor/read/check paths stay around `~0.7 ns`
  - handle ctor+read stays around `~1.7 ns`
  - unique product ctor stays around `~180-190 ns`

The important judgment is not the exact last decimal place, but that:

- the main compiler path is now architecturally honest
- the backend-facing phase exists and owns backend-static truth
- the native leaf no longer needs to rediscover backend-static structure
- remaining profile noise is increasingly ordinary construction work rather than a major missing phase

## Optimization policy

At this point, `asdl2` should be treated as **fast enough unless a concrete workload disproves it**.

That means:

- do not keep tuning just because a helper appears in a synthetic profile
- trust stopwatch regressions over prettier traces or cleaner-looking code
- resume performance work only when:
  - a real workload says startup/install/full-path time is still too high, or
  - a new feature introduces a fresh hotspot, or
  - a benchmark target against a concrete baseline still matters

## Current design judgment

The current architecture says:

- lookup belongs in `catalog()`
- machine-facing truth belongs in `Asdl2Lowered`
- backend rendering belongs in the native leaf
- `Asdl2Machine` remains as the honest `gen / param / state` frame

If future profiler pressure appears, the next question is not "which helper should be tuned?"
The next question is:

> which distinction is still hidden, duplicated, or over-modeled in the ASDL?
