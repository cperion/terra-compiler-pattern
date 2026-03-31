# FrontendC

`frontendc` is a meta-frontend compiler project.

It takes an authored frontend specification and compiles it into two generated boundaries:

- text -> token spec
- token spec -> source spec

The project is deliberately machine-first.

## Phase stack

```text
FrontendSource
  -check-> FrontendChecked
  -lower-> FrontendLowered
  -define_machine-> FrontendMachine
  -emit_lua-> FrontendLua
```

There is also an install leaf:

```text
FrontendMachine -install_generated-> loadstring-installed generated boundaries
```

`install_generated()` and `emit_lua()` now share the same backend strategy:
materialize tiny generated Lua boundaries and install them through `loadstring`/`load`.
There is no separate direct runtime-closure path anymore.

## Current phase meanings

### `FrontendSource`
Authored frontend language:
- target attachment fqnames
- lexer rules
- parser grammar
- semantic result construction

Current lexer families:
- `KeywordToken`
- `PunctToken`
- `IdentToken`
- `QuotedStringToken`
- `NumberToken`

Important source expression forms:
- `Capture(name, inner)`
- `Build(inner, result)`

`Build` is the explicit local semantic grouping form.
It parses `inner`, uses captures made inside that `inner`, and assembles one semantic value from them.
Its captures are local to the build expression and do not leak into the surrounding rule scope.
This is the honest way to express multi-value sequence capture.

### `FrontendChecked`
Resolved / validated spec:
- stable token ids
- stable rule ids
- stable capture slot ids
- canonical `CheckedCharSet`
- explicit token payload shape
- explicit capture slot shape
- explicit semantic value shape
- first sets and nullability

Important checked vocab:
- `TokenPayloadShape`
  - `NoTokenPayload`
  - `StringTokenPayload`
- `CaptureSlotShape`
  - `SingleSlot`
  - `ListSlot`
  - `PresenceSlot`
- `SemanticValueShape`
  - `NodeValue`
  - `ListValue`
  - `StringValue`
  - `BoolValue`

### `FrontendLowered`
Backend-neutral machine-feeding plans:
- fixed-token dispatch buckets
- identifier dispatch bitsets
- parse `RulePlan`
- parse `Step`
- normalized `ResultPlan`

Important lowered parser vocab:
- `RulePlan`
- `RuleKind`
  - `TokenRuleKind`
  - `SeqRuleKind`
  - `ChoiceRuleKind`
- `ChoiceArm`
- `Step`
  - `ExpectToken`
  - `CallRule`
  - `OptionalGroup`
  - `RepeatGroup`

### `FrontendMachine`
Install-ready machine attachment:
- structured paths instead of fqname strings
- install headers for tokenize / parse boundaries
- constructor refs for parse result assembly

### `FrontendLua`
Materialized Lua boundary files.

Each `BoundaryFile` contains:
- output path
- receiver fqname
- boundary verb
- generated Lua source

## Current runtime leaves

### `FrontendMachine.Spec:install_generated()`
Installs generated Lua boundaries directly via `loadstring`/`load`.

### `FrontendMachine.Spec:emit_lua()`
Emits direct Lua boundary source files.

Those generated files now contain the tokenizer and parser kernels themselves:
- direct tokenize loop shape
- direct rule functions
- direct step lowering
- direct result assembly

The current backend doctrine is:
- inline structure
- bind target constructors
- keep generated code tiny and regular
- avoid a separate generic runtime helper in the hot path

## Current supported grammar surface

Supported:
- token refs
- rule refs
- seq / choice / optional / many / one-or-more
- captures
- nested helper rules
- string-valued rule refs
- repeated node-valued helper-rule captures
- local semantic grouping via `Build`
- repeated node-valued `Build` groups
- result construction via:
  - `CaptureSource`
  - `PresentSource`
  - `JoinedListSource`
  - `ConstBoolSource`

Intended modeling rule:
- if one parse fragment needs several captured semantic children to become one value, use `Build`
- do not ask lowering to guess an implicit tuple/object meaning

## Example frontend

A machine-first JSON example frontend now lives at:

- `frontendc/examples/json_frontend.lua`
- `frontendc/examples/json_frontend_bench.lua`

It currently parses JSON into frontend-owned AST nodes (`JsonObject`, `JsonArray`, `JsonString`, `JsonNumber`, `JsonBool`, `JsonNull`) rather than directly into ordinary Lua tables.

## Bench hooks

Implemented benches:
- `FrontendSource.Spec:check()`
- `FrontendChecked.Spec:lower()`
- `FrontendLowered.Spec:define_machine()`
- `FrontendMachine.Spec:emit_lua()`
- `FrontendMachine.Spec:install_generated()`
- tokenize runtime
- parse runtime
- full runtime
