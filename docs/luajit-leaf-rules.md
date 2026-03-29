# LuaJIT Leaf Rules

This repository treats LuaJIT leaves as a strict backend target, not as a permissive dynamic runtime escape hatch.

The right mental model is not:

- "write arbitrary Lua and hope the JIT optimizes it"

The right mental model is:

- lower the typed program into a tiny canonical execution machine
- make the machine monomorphic
- make the machine run over typed FFI/cdata layouts
- keep all semantic richness above the leaf, in typed ASDL phases

A useful reference point is `fun.lua`.

`fun.lua` is not fast because it is "dynamic Lua done cleverly." It is fast because it normalizes diverse iterable forms into one canonical execution protocol:

- `(gen, param, state)`

That is exactly the kind of backend discipline LuaJIT rewards.

---

## 1. The core rule

A LuaJIT leaf must have the same architectural honesty as a Terra leaf.

That means:

- the leaf input must already be fully lowered
- the execution function must be monomorphic
- the live state must be typed
- the payload consumed by the leaf must be typed
- no hidden interpreter may remain in the callback

In this repository's vocabulary:

- pure phases operate on ASDL-defined types
- terminal leaves produce `Unit { fn, state_t }`
- on LuaJIT, `state_t` must be realized as FFI/cdata layout

---

## 2. The `Unit` contract on LuaJIT

The LuaJIT backend keeps the same Unit shape as Terra:

- `Unit.fn`
- `Unit.state_t`

But the realization differs:

### Terra

- `fn` = Terra function
- `state_t` = Terra type

### LuaJIT

- `fn` = specialized monomorphic Lua function
- `state_t` = FFI/cdata-backed typed layout descriptor

So the architectural contract is shared, even though the backend mechanism differs.

---

## 3. No opaque tables

Opaque runtime tables are not part of the intended backend contract.

### Not allowed in production leaves

- table-backed kernel state
- shape-varying payload tables consumed by hot callbacks
- string-tag dispatch in hot loops
- nested runtime object graphs
- recursive interpretation of authored trees during execution
- ad hoc dictionaries in the hot path

### Allowed above the leaf

- ASDL-defined typed values
- ASDL typed lists
- pure LuaFun/FP transforms over typed phase data

The system is fully typed:

- the types are the program
- the types are the state shape used by compiled functions

That is not optional decoration. It is part of the architecture.

---

## 4. Required backend form

A production LuaJIT leaf should usually have all of these properties:

- monomorphic control flow
- fixed field reads/writes
- direct indexed loops
- FFI `cdef` structs for state
- FFI `cdef` structs/arrays for live payload
- compile-time-known helper family selection where possible
- stable closure upvalues capturing baked facts

Good examples of backend form:

- packed item arrays with fixed fields
- one runner over typed cdata arrays
- one custom-family dispatch table baked from the compiled spec
- one explicit state struct containing counts and pointers

---

## 5. `fun.lua` as a design lesson

`fun.lua` is instructive because it applies the same normalization discipline.

It takes many iterable forms and lowers them into one canonical protocol:

- `(gen, param, state)`

That gives it:

- uniform composition
- stable call shapes
- low runtime semantic overhead
- good LuaJIT traceability

The lesson for backend leaves is:

> do not execute rich semantic structure directly.
> lower rich structure into one tiny regular machine.

For leaves in this repository, the analogous canonical machine is usually:

- `Unit { fn, state_t }`
- packed typed payload arrays
- direct indexed loops over those arrays

---

## 6. What implementation resistance means on LuaJIT

If a LuaJIT leaf wants any of the following:

- general Lua tables as payload/state
- runtime field-existence checks
- string-based variant dispatch
- many tiny closure layers in the hot path
- recursive tree walking during execution
- environment/context lookups everywhere

then the lowering is incomplete.

The correct response is not:

- "LuaJIT is dynamic, so this is fine"

The correct response is:

- add or revise phases
- narrow the leaf input further
- pack the payload into typed FFI form
- simplify the runner until it is monomorphic

---

## 7. Relationship to Terra

Strict LuaJIT can impose nearly the same architectural pressure as Terra.

The pressure comes from:

- typed source ASDL
- explicit phase narrowing
- strict `Unit { fn, state_t }` ownership
- fully lowered monomorphic leaves

Terra still provides stronger mechanical enforcement when you need:

- explicit staging syntax
- exact native layout synthesis
- ABI control
- SIMD
- LLVM optimization

So the repository policy is:

- LuaJIT by default
- Terra by opt-in
- same pure spine
- backend-specific leaves
- same typed Unit contract on both backends

---

## 8. Practical checklist

Before accepting a LuaJIT leaf, check:

- [ ] Is the leaf input already fully lowered?
- [ ] Is `fn` monomorphic?
- [ ] Is `state_t` FFI/cdata-backed?
- [ ] Is live payload FFI/cdata-backed?
- [ ] Are hot loops direct indexed loops?
- [ ] Is variant dispatch removed or baked where possible?
- [ ] Are there any opaque Lua tables left in the execution path?
- [ ] Would the same leaf shape make sense if rewritten in Terra?

If several answers are "no", the leaf is still too high-level.

---

## 9. Short version

LuaJIT leaves should be treated as:

- typed
- lowered
- monomorphic
- FFI-backed
- compiler-generated in structure, even if expressed in Lua

The goal is not dynamic flexibility.

The goal is:

> a tiny canonical machine that LuaJIT can trace aggressively.
