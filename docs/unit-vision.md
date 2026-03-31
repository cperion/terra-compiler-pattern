# The New Unit Vision

This document describes a new direction for `unit`.

It is a design document, not a claim that every detail here is already implemented.
Its purpose is to state a simpler, more elegant, more honest model for the framework as it evolves.

The central change is small to say but large in consequence:

> `unit` is no longer best understood as a framework around one ASDL tree.
> It is better understood as a framework that usually hosts **two first-class languages**:
> **domain** and **proto**.

Those two languages are not the same thing.
They should not be collapsed.
They should not be confused.
And they should be given a simple, canonical place in the project model.

The canonical minimal form is:

```text
myproj/
  domain.lua
  proto.lua
  boundaries/
    my_domain_source_spec.lua
    my_domain_checked_spec.lua
    my_proto_source_catalog.lua
    my_proto_plan_catalog.lua
  pipeline.lua          -- optional
  unit_project.lua      -- optional
  app.lua               -- optional
```

That is the new vision in one picture.

Just as important: `unit` should keep an **opinionated flat layout by default**.
The new two-language model is meant to clarify architecture, not to introduce folder tax.
So the preferred default is:

- flat top-level schema entrypoints: `domain.lua`, `proto.lua`
- flat `boundaries/`
- lower-snake receiver-owned artifact filenames

Tree layout can still exist when a project truly needs it, but it should remain the exception rather than the story the framework teaches first.

---

## 1. Why this document exists

The older `unit` framing was good at several things:

- ASDL-centered design
- memoized boundaries
- transitions and terminals
- `Unit { fn, state_t }`
- convention-first project loading
- backend separation

But over time, a real architectural fact became clearer:

- the user-facing **domain language** is one language
- the install / realization / artifact-facing **proto language** is another language

That second language is not a backend afterthought.
It has its own nouns, its own tree, its own transitions, and its own correctness conditions.

Once that becomes true, the framework should say so honestly.

At the same time, the framework should **not** overreact by creating a heavy workspace ontology, a forest of folder categories, or a tax on every project.

So the goal of this vision is:

- make the language split explicit
- keep the file structure cheap
- keep convention stronger than configuration
- preserve the compiler pattern
- make CLI and integration feel elegant instead of accidental

---

## 2. The core claim

The best default model for `unit` is now:

```text
authored domain language
  -> semantic compilation
  -> canonical machine meaning
  -> project_proto
  -> proto language
  -> realization / install
  -> Unit / installed artifact
```

The important change is the named boundary:

```text
project_proto
```

That boundary is where semantic machine meaning is handed to the proto language.

The proto language is then responsible for questions like:

- what artifact family should exist?
- what host contract applies?
- what binding shape applies?
- what install identity applies?
- what restore / swap / install strategy applies?

The domain language is responsible for different questions:

- what did the user author?
- what is saved and loaded?
- what does undo restore?
- what are the real domain nouns?
- what semantic machine should exist?

These are different jobs.
They deserve different trees.

---

## 3. What stays the same

This vision does **not** abandon the compiler pattern.
It sharpens it.

The following remain true:

- the ASDL is the architecture
- events are still an input language
- apply is still pure
- transitions still consume knowledge
- terminals still end compilation
- execution still runs installed artifacts
- structural sharing and memoization still matter
- backend leaves still own typed runtime state
- domain modeling still begins from user nouns, not runtime machinery

The new vision does not replace those rules.
It gives a clearer place to the proto layer that the architecture already wanted.

---

## 4. The two first-class languages

## 4.1 Domain

`domain.lua` defines the user-facing language.

This is the language of authored truth.
It contains what the user works with and what the application means.

Examples of domain nouns:

- document
- block
- rule
- token
- node
- graph
- clip
- track
- parameter
- schema
- frontend
- app state

Domain is where these questions live:

- what is authored?
- what has stable identity?
- what variants are real domain variants?
- what survives save/load?
- what does undo restore?
- what semantic compilation should happen?

Domain should **not** contain install-policy or backend-packaging concerns unless those are truly authored in that domain.

## 4.2 Proto

`proto.lua` defines the realization-facing language.

This is the language of hosting, packaging, installation, artifact planning, and backend-facing structure.

Examples of proto nouns:

- proto catalog
- host contract
- artifact key
- shape key
- closure family
- bytecode bundle
- capture plan
- install contract
- emitted source block
- binding order
- hot-swap slot plan

Proto is where these questions live:

- how does this machine become installable here?
- what artifact family exists?
- what is cached and keyed?
- what bindings are attached and in what order?
- what source / closure / bytecode choice applies?
- what installation metadata exists?

Proto should **not** rediscover domain semantics.
If proto needs to reinterpret the broad authored domain tree, the semantic lowering is incomplete.

## 4.3 Lua protos, Terra protos, and realization modes

The proto side becomes clean only if `unit` keeps several lower-level distinctions separate.

These are related, but they are **not the same question**:

### Host / backend world

Examples:

- LuaJIT
- Terra

This is the host-contract axis.
It answers:

- what runtime world hosts the machine?
- what calling and ownership rules apply?
- what lower realization families are even legal here?

### Proto family

Examples:

- textual Lua proto
- closure Lua proto
- thin native Terra proto
- quoted Terra proto
- generated Terra proto

This is the proto-family axis.
It answers:

- what lower language shape represents installation structure?
- is the proto body text, closure structure, quote structure, or something else?

### Artifact / install mode

Examples:

- `load` / `loadstring` source chunk
- direct closure artifact
- bytecode blob
- native Terra function
- generated Terra module

This is the install-mode axis.
It answers:

- what final installed artifact form is produced?
- how is it loaded, restored, swapped, or cached?

These three axes must not be collapsed into one blurry notion of "backend".

### The clean rule

The clean architectural rule is:

> `domain` decides semantic meaning.
> `proto` binds that meaning to a host world.

Within proto:

- **Lua vs Terra** is a host distinction
- **text proto vs closure proto vs quote/native proto** is a proto-family distinction
- **`loadstring` vs direct closure vs bytecode vs native function** is an install/artifact distinction

### Lua-side realization

On the Lua side, a proto family may honestly distinguish between:

- text-oriented proto bodies
- closure-oriented proto bodies

And realization may honestly distinguish between:

- loading source text
- installing a direct closure
- loading or restoring bytecode

This is clean **if those choices remain proto-side**.
They should not leak upward into the authored domain language.

### Terra-side realization

On the Terra side, proto may be thinner or richer depending on what the backend truly needs.

A Terra path may eventually distinguish between things like:

- direct native realization
- quoted realization
- generated-module realization

But Terra does **not** need to mirror Lua exactly.
The architecture should not force a fake universal proto just to make both backends look cosmetically similar.

The honest rule is:

> one `proto.lua`, potentially several backend-shaped proto families inside it.

So `proto.lua` does **not** mean one generic lowest-common-denominator language.
It means one canonical home for realization-facing languages.

### What this prevents

Keeping these axes separate prevents several common mistakes:

- polluting domain ASDL with `loadstring`, bytecode, or closure policy
- forcing Lua and Terra into one bag of optional fields
- making install code rediscover semantic meaning
- hiding real host-contract differences behind the vague word "backend"

### Short form

If this distinction needs to be stated briefly, it is:

> **Lua vs Terra** is a host distinction.
> **Text vs closure vs quote/native proto** is a proto-language distinction.
> **`loadstring` vs closure vs bytecode vs native function** is an install-mode distinction.

That is the clean lower architecture.

---

## 5. Why only two canonical files

The framework should prefer the smallest honest convention.

That convention is:

- `domain.lua`
- `proto.lua`

This is enough because it names the two genuinely different language roles that most `unit` systems now have.

It is also intentionally restrained.

The framework should **not** force extra top-level categories for every projection pattern:

- not `views/`
- not `checked/`
- not `lowered/`
- not `machine/`
- not `apps/`
- not `domains/`
- not `protos/`

Those may exist internally as modules, phases, or extracted projects when they are justified.
But they should not be the default filesystem doctrine.

The cheap default should be enough for most work.

---

## 6. Canonical minimal project shape

The canonical minimal project is:

```text
myproj/
  domain.lua
  proto.lua
  boundaries/
    my_domain_source_spec.lua
    my_domain_checked_spec.lua
    my_domain_machine_spec.lua
    my_proto_source_catalog.lua
    my_proto_checked_catalog.lua
    my_proto_plan_catalog.lua
  pipeline.lua          -- optional
  unit_project.lua      -- optional
  app.lua               -- optional
```

This project form is intentionally **flat and opinionated**.
That is a feature, not a compromise.

A flat layout is preferred because it is:

- cheap to adopt
- easy to scan
- grep-friendly
- convention-first
- well matched to receiver-owned artifacts
- consistent with the goal of making architecture explicit without making the filesystem ceremonial

Tree layout remains optional, but flat should stay the clean default that `unit` recommends first.

### `domain.lua`
Defines the domain ASDL family or families.
This is the authored side.

### `proto.lua`
Defines the proto ASDL family or families.
This is the realization side.

### `boundaries/`
Owns semantic boundaries, proto boundaries, and backend artifacts under one conventional root.
Receiver-owned artifact naming remains the preferred style.
The preferred boundary layout is **flat**.

### `pipeline.lua`
Optional.
Used when phase ordering should be declared explicitly rather than inferred.

### `unit_project.lua`
Optional.
Used only for truthful metadata:

- layout
- deps
- stubs
- install hooks
- other minimal project facts

It must not become a second schema language.

### `app.lua`
Optional runtime entrypoint for the host application loop or integration surface.
This is useful when the project is not only a library of boundaries but a runnable app.

---

## 7. What `domain.lua` and `proto.lua` should contain

The new vision does **not** require that each file contain only one ASDL module.

A file is a canonical schema entrypoint, not a forced one-module container.

So these are both acceptable:

### single-family style

```lua
-- domain.lua
module MyDomainSource { ... }
module MyDomainChecked { ... }
module MyDomainMachine { ... }
```

```lua
-- proto.lua
module MyProtoSource { ... }
module MyProtoChecked { ... }
module MyProtoPlan { ... }
module MyProtoLua { ... }
```

### multi-family style inside one side

```lua
-- domain.lua
module AppSource { ... }
module AppChecked { ... }
module AppView { ... }
module AppMachine { ... }
```

```lua
-- proto.lua
module LuaProtoSource { ... }
module LuaProtoPlan { ... }
module LuaProtoInstall { ... }
```

The point is not one file = one module.
The point is:

- domain-side language families live in `domain.lua`
- proto-side language families live in `proto.lua`

That is enough convention to keep projects readable.

---

## 8. The semantic split

The right split between domain and proto is this:

## 8.1 Domain decides meaning

Domain-side phases answer questions like:

- what references resolve to what?
- what defaults apply?
- what semantic variant is this really?
- what machine should exist?
- what lower domain-local structure is honest?

## 8.2 Proto decides hosting

Proto-side phases answer questions like:

- what install family applies?
- what artifact representation should exist?
- what host contract is required?
- what binding schema is used?
- what artifact identity and shape identity apply?
- how is the result restored, installed, or swapped?

## 8.3 The bridge is explicit

The bridge between them must be a named, typed boundary.

For example:

```text
MyDomainMachine.Spec
  -> project_proto
  -> MyProtoSource.Catalog
```

That bridge may live in:

- a domain-side receiver
- an app-side receiver
- a small host-local bridge boundary

The important rule is not where it lives.
The important rule is that it is explicit and typed.

---

## 9. View is a pattern, not a doctrine

This new vision intentionally does **not** elevate view to a top-level filesystem category.

A view projection is an important pattern in the compiler model:

- it illustrates side projections
- it illustrates connecting ASDL domains
- it illustrates how one language can target another language

But it is still a **pattern**, not a required repo ontology.

Sometimes a project will have a real view ASDL family.
Sometimes it will not.
Sometimes that view family belongs naturally inside `domain.lua`.
Sometimes it belongs in a reusable dependency.
Sometimes it is just one typed projection boundary among many.

So the rule is:

> keep the pattern available, but do not force a filesystem religion around it.

---

## 10. Phase plan under the new vision

A typical project now looks like this:

```text
apply events
  -> DomainSource
  -> check / resolve / classify / lower / define_machine
  -> DomainMachine
  -> project_proto
  -> ProtoSource
  -> check_realize / lower_realize / prepare_install / emit
  -> ProtoInstall
  -> install
  -> Unit / installed artifact
```

Not every project needs all of those phases.
But the separation of responsibilities should remain.

### Domain-side phase verbs
Common verbs:

- check
- resolve
- classify
- lower
- define_machine
- project_view
- normalize

### Proto-side phase verbs
Common verbs:

- check_realize
- lower_realize
- prepare_install
- package
- emit
- install
- restore

These should remain honest verbs that consume knowledge.

---

## 11. Boundary inventory

A typical project under this vision will contain three kinds of boundaries.

## 11.1 Domain boundaries

Examples:

- `MyDomainSource.Spec:check()`
- `MyDomainChecked.Spec:lower()`
- `MyDomainLowered.Spec:define_machine()`

These are semantic compiler boundaries.

## 11.2 Bridge boundaries

Examples:

- `MyDomainMachine.Spec:project_proto()`
- `MyApp.State:project_proto()`

These connect domain meaning to proto structure.

## 11.3 Proto boundaries

Examples:

- `MyProtoSource.Catalog:check_realize()`
- `MyProtoChecked.Catalog:prepare_install()`
- `MyProtoPlan.Catalog:install()`

These are realization-facing boundaries.

The file layout remains receiver-owned and convention-first.
The new vision changes what the project means, not the usefulness of receiver ownership.

---

## 12. Leaf-driven constraints

The new vision is justified only if it makes leaves clearer.

That means the two-language split must satisfy the following constraints.

## 12.1 Domain leaves must not see proto concerns too early

A domain leaf or domain terminal should not be distorted by:

- bytecode packaging policy
- install slot order
- artifact cache key design
- source-vs-closure-vs-bytecode choice
- backend host metadata

If those concerns shape the domain too early, the source language is polluted.

## 12.2 Proto leaves must not rediscover source semantics

A proto leaf should not be trying to determine:

- what the user meant
- what authored variant this is
- what references resolve to
- what semantic machine should exist

If proto is doing that, the bridge from domain to proto is too weak.

## 12.3 Execution leaves must remain narrow

Execution still wants:

- monomorphic hot paths
- typed runtime state
- no wide authored branching
- no accidental interpretation in the hot path

The new vision should improve this by giving install-facing structure a proper home before execution.

---

## 13. CLI principles

The CLI should be reworked around the new project model, but kept simple.

The CLI should primarily target the **project**, not a heavy workspace ontology.

If a project has `domain.lua` and `proto.lua`, the CLI should understand that automatically.

The goal is:

- zero or near-zero configuration
- one obvious place to stand in the repo
- one obvious set of commands
- explicit output about domain and proto coverage

### Core commands should still feel like this

```text
unit status .
unit pipeline .
unit boundaries .
unit markdown .
unit scaffold . MyDomainSource.Spec:check
unit scaffold . MyProtoSource.Catalog:check_realize
unit test-all .
```

### The new CLI should understand two-language status

For example, `unit status .` should be able to show:

- domain-side types and boundaries
- proto-side types and boundaries
- bridge boundaries between them
- backend artifact coverage where relevant

### The CLI should not require new folder tax

The CLI should not require users to adopt categories like:

- `domains/`
- `protos/`
- `views/`
- `apps/`

unless they consciously choose a larger extracted structure.

---

## 14. Convention over configuration

This new vision strongly prefers convention.
It also strongly prefers a **flat default layout** over an elaborate tree-shaped taxonomy.

## 14.1 Default discovery

If the loader sees:

```text
domain.lua
proto.lua
```

it should understand the project shape immediately.

## 14.2 Optional configuration only

`unit_project.lua` remains optional.
When present, it should refine truth, not invent ontology.

Good uses:

- dependencies
- layout choice
- stubs
- install hooks
- explicit pipeline declaration

Bad uses:

- manually reconstructing what file means domain
- duplicating schema structure in config
- turning project config into a second DSL

## 14.3 Cheap defaults beat abstract purity

The framework should choose the smallest convention that works for most projects.
That is why `domain.lua` and `proto.lua` are enough.

---

## 15. Crochet as a builtin library

Crochet should be a builtin provided library of the framework.

This follows directly from the new vision:

- proto is first-class
- Crochet helps with proto structure and realization work
- therefore Crochet belongs in the standard toolkit of `unit`

But builtin should not mean magical or hidden.

It should mean:

- ships with `unit`
- available without vendoring
- inspectable like normal `unit` code
- follows the same boundary/project conventions internally
- usable from proto-side projects without ceremony

Crochet should be treated as a standard library for proto work.

It should not be a special invisible subsystem that bypasses the rest of the framework model.

---

## 16. Dependencies and extraction

The new vision does **not** require every language family to become its own project.

That would be expensive and awkward.

The correct default is:

- keep `domain.lua` and `proto.lua` together in one project
- extract only when reuse or ownership genuinely demands it

A proto family becomes a dependency only when it is truly:

- reusable across projects
- independently maintained
- independently tested or versioned
- conceptually its own product

Until then, one project is enough.

This preserves elegance and keeps the cost low.

---

## 17. Canonical examples

## 17.1 Small app with explicit proto

```text
notes/
  domain.lua
  proto.lua
  boundaries/
  app.lua
```

- `domain.lua` defines notes, documents, selections, commands, checked forms, machine forms
- `proto.lua` defines host contracts, render/install plans, artifact keys, emitted closures
- `boundaries/` contains both semantic and proto boundaries
- `app.lua` starts the live loop

## 17.2 Library project

```text
frontendc2/
  domain.lua
  proto.lua
  boundaries/
```

- no runtime app entrypoint required
- project is primarily a compiler/pipeline library

## 17.3 Domain-only project

```text
simple-domain/
  domain.lua
  boundaries/
```

If a project truly does not need an explicit proto language yet, `proto.lua` may be absent.
In that case the older thin path remains valid.

But as soon as install-facing structure becomes real, `proto.lua` is the honest place for it.

---

## 18. What this vision rejects

This document rejects several directions.

## 18.1 Reject: one giant blended tree

Do not hide proto concerns inside domain just because there used to be only one obvious tree.

## 18.2 Reject: overbuilt workspace tax

Do not require every project to adopt many top-level folder categories just to be considered canonical.

## 18.3 Reject: view as hard filesystem ontology

View is a valuable pattern, not a mandatory top-level category.

## 18.4 Reject: hidden builtin magic

If Crochet is builtin, it should still be an honest `unit` library, not a hidden exception to the rules.

## 18.5 Reject: configuration as substitute for convention

Do not make users describe in config what the framework can infer from a small canonical layout.

---

## 19. Migration from the current model

Projects that currently look like this:

```text
myproj/
  schema/
    app.asdl
  pipeline.lua
  boundaries/
  unit_project.lua
```

can be reinterpreted gradually.

A plausible migration path is:

1. identify which existing modules are truly domain-side
2. identify which existing modules are truly proto-side
3. move domain-side schema entry into `domain.lua`
4. move proto-side schema entry into `proto.lua`
5. keep existing boundaries under `boundaries/`
6. introduce or rename the explicit bridge to `project_proto`
7. teach CLI and loader to understand the new convention

This can happen incrementally.
The vision is about clarity of model first.

---

## 20. Implementation direction for the framework

If `unit` adopts this vision, the implementation work should happen in this order.

## 20.1 Loader and project model

Teach project loading to understand the minimal canonical form:

```text
domain.lua
proto.lua
```

without requiring a schema directory.

## 20.2 Inspection

Teach inspection to report:

- domain families
- proto families
- bridge boundaries
- backend artifact coverage

## 20.3 CLI

Rework CLI output and scaffolding around the two-language project model.

## 20.4 Builtin libraries

Promote Crochet into the builtin provided library layer in a way that stays inspectable and conventional.

## 20.5 Documentation

Update the rest of the docs to describe `unit` first through:

- domain
- proto
- bridge
- install
- execution

rather than through a one-tree simplification that is no longer the honest default.

---

## 21. Quality gates for this vision

This vision is only good if it satisfies the same quality demands as the rest of the compiler pattern.

### Save/load honesty
Domain still owns authored truth.
Proto owns install truth.
Neither should impersonate the other.

### Undo honesty
Undo should restore domain truth cleanly without repair logic.

### Phase clarity
The bridge to proto must consume a real decision.
Proto phases must consume install knowledge, not rediscover semantics.

### Testability
Domain transitions, bridge boundaries, and proto transitions should still be testable as constructor + assertion.

### Incrementality
The split should improve memo boundaries rather than make them more accidental.

### Leaf clarity
Leaves should become easier to write because they see the right kind of input.

### Elegance
The framework should become simpler to explain and easier to adopt.
If the new structure feels heavier than the old confusion, the design is wrong.

---

## 22. A short statement of the new vision

If this document had to collapse into a few lines, it would be this:

> `unit` should model two first-class languages: **domain** and **proto**.
> The canonical project should stay minimal: **`domain.lua` and `proto.lua` are enough**.
> Everything else should remain optional, conventional, and cheap.
> View remains an important projection pattern, not a mandatory filesystem doctrine.
> Crochet should become a builtin proto library of the framework.
> The CLI and loader should reflect this architecture directly.

---

## 23. Final summary

The old simplification was:

```text
one project, one ASDL tree
```

The new honest simplification is:

```text
one project, two first-class languages
  - domain
  - proto
```

And the canonical filesystem expression of that is simply:

```text
myproj/
  domain.lua
  proto.lua
  boundaries/
```

That is small enough to remember, strong enough to guide design, and honest enough to match where `unit` is going.
