# Modeling Programs as Compilers

## Part 1: The Core Insight

### 1.1 The ASDL is a language

The ASDL is not a data format. It is not just a schema. It is not merely a description of what the program stores.

The ASDL is a LANGUAGE.

The source ASDL is the input language of a compiler. The user is the programmer. The UI is the IDE. Every user gesture is a program edit. Every edit produces a new program — a new ASDL tree. The compiler compiles it. The output runs.

Getting the ASDL right means getting the LANGUAGE right. A good language has:
- clear nouns
- clear verbs
- orthogonal features
- completeness
- minimality
- composability

These are the same properties that make a programming language good, because that is what the source ASDL is: a domain-specific programming language whose programs are domain artifacts — songs, documents, spreadsheets, scenes, grammars, tools — and whose compiler produces executable machinery that realizes those artifacts.

The ASDL is the architecture. Everything else is downstream.

### 1.2 Interactive software is a compiler

Every interactive program takes human gestures — clicks, keystrokes, drags, edits, messages, file updates — and turns them into machine behavior — pixels, samples, queries, responses, network bytes, driver calls.

Between intent and execution there is a gap. The user thinks in domain concepts:
- “make this louder”
- “insert a paragraph here”
- “parse this grammar”
- “connect these nodes”
- “install this realization”

The machine does not think in those terms. It works in registers, memory layouts, loops, buffers, closures, function pointers, and driver callbacks.

Traditional systems bridge that gap at runtime by repeatedly interpreting broad authored structure. Every frame, every callback, every update, they re-answer some version of:

> what does this node mean, really?

The compiler pattern bridges the gap earlier. It treats the program as authored source, compiles that source into narrower lower forms, produces a machine, realizes that machine on a backend, and runs the installed artifact until the source changes again.

That is the core claim:

> interactive software is best understood as a live compiler from authored intent to executable machinery.

### 1.3 The semantic product is a machine

The most important output of the compiler is not “a function.” It is a MACHINE.

More precisely, the lower stack of the pattern is:

- **transitions**
- **Machine IR**
- **canonical Machine** (`gen`, `param`, `state`)
- **proto language**
- **Unit / installed artifact**

Or as a flow:

```text
transitions
→ Machine IR
→ canonical Machine
→ proto language
→ Unit / installed artifact
```

This distinction matters.

A `Unit` is not the first machine concept. A `Unit` is the packaged installed result. The semantic executable abstraction above it is the canonical Machine:
- `gen` — the execution rule
- `param` — the stable machine input
- `state` — the mutable runtime-owned state

If you compress those layers too early, terminal design gets muddy. If you keep them distinct, the architecture becomes much clearer.

### 1.4 The second compiler compiles into proto language

Once a canonical machine exists, there is still another job to do:

> how should this machine become an installable runtime artifact on this backend?

That job is realization.

Every canonical machine still has to cross one more boundary:

> what is the smallest installable thing that hosts this machine on this backend?

That boundary is realization, and its language is the **proto language**.

Sometimes the proto language is thin:
- Terra may lower to something close to a native proto with native code and native state layout
- LuaJIT may lower to something close to a direct-closure proto for the smallest direct cases

Sometimes the proto language is rich:
- real Lua template functions that define execution shape
- bytecode blobs produced from those templates via `string.dump`
- explicit upvalue-binding plans installed via `debug.setupvalue`
- source-kernel families loaded via `load` / `loadstring`
- artifact identity and cache keys
- hot-swapable named executable fragments

So the compiler pattern often contains not one compiler but two linked compilers:

1. **domain compilation** — from authored source to machine meaning
2. **proto compilation / realization** — from machine meaning to installable runtime form

This is not architectural drift. It is a normal lower-layer design choice.

The proto language is not the source language of the domain. It is the structural language of installation. In simple cases it is almost empty; in richer cases it expands into explicit artifact families, binding schemas, and install catalogs.

In `unit`'s current preferred project form, this split should be cheap and visible. The canonical minimal expression is often simply:

```text
myproj/
  domain.lua
  proto.lua
  boundaries/
```

`domain.lua` is the conventional home of domain-facing ASDL families. `proto.lua` is the conventional home of realization-facing ASDL families. This does **not** mean each file must contain only one module, and it does **not** mean every projection or internal phase deserves its own top-level file. It means the two most important language roles get an explicit, low-cost place in the project model.

### 1.5 The gap has layers, and those layers are your phases

The gap between “what the user said” and “what the runtime executes” is never one step. There are always intermediate levels of knowledge.

```text
User intent:      “I want a low-pass filter at 2kHz on this synth”
    ↓
UI vocabulary:    Track → DeviceChain → Device(Biquad, freq=2000, q=0.7)
    ↓
Semantic model:   Graph → Node(biquad_kind, params=[2000, 0.7])
    ↓
Execution plan:   Job(biquad, bus=3, coeffs=[b0, b1, b2, a1, a2])
    ↓
Machine:          gen/filter-step, param/coeffs, state/history
    ↓
Proto language:   Terra native proto OR LuaJIT closure proto OR Lua template/blob/bind proto
    ↓
Installed unit:   Unit { fn, state_t }
```

Each layer consumes knowledge. Each phase boundary exists because some real decision is being resolved.

The question “how many phases should I have?” is answered by:

> how many distinct levels of knowledge resolution does this domain actually have?

Not more. Not fewer.

### 1.6 The source phase is still the most important

The source phase — the first phase, the one the user edits — determines everything.

It is the input language of the compiler. Every later phase is derived from it. Every transition consumes knowledge from it. Every machine is downstream of it. Every installed artifact is downstream of that machine.

If the source phase is wrong — wrong nouns, wrong granularity, wrong containment, wrong variants, wrong identity boundaries — every lower phase inherits the mistake. The entire pipeline compiles the wrong thing correctly.

Getting the source phase right requires answering:

> what are the domain nouns?

Not implementation nouns:
- buffer
- callback
- registry
- renderer state
- service container

But user nouns:
- track
- clip
- parameter
- rule
- token
- widget
- cell
- scene
- proto if and only if proto is truly authored in that domain

### 1.7 The hard part

The framework primitives — ASDL, Event ASDL, Apply, memoized transitions, Machines, realization, Unit — are tools. They do not tell you what to model. They do not tell you what the source language should be. They do not tell you where knowledge is consumed, what lower forms are honest, or when realization deserves its own structural layer.

That is the hard part.

And it must be done correctly, because the ASDL is the architecture. A wrong type at the source phase propagates through transitions, machine design, realization strategy, installed artifacts, and runtime behavior. The cost compounds.

This document is about making those design decisions explicitly and correctly.

---

## Part 2: The Seven Concepts and the Live Loop

The pattern is built from seven concepts. They are small enough to state simply and strong enough to organize an entire interactive system.

### 2.1 Source ASDL

This is what the program IS: the user-authored, user-visible, persistent model of the domain.

In a music tool: tracks, clips, devices, routings, parameters.
In a text editor: document, blocks, spans, cursors, selections.
In a parser tool: grammar, token, rule, product.
In a UI system: widgets, layout declarations, style declarations, bindings.

The source ASDL is not runtime scaffolding. It is not a cache of derived facts. It is not a bag of backend conveniences. It is the authored program.

It must answer:
- what did the user author?
- what survives save/load?
- what does undo restore?
- what exists as a user-visible thing?
- which choices are independent authored choices rather than derived consequences?

### 2.2 Event ASDL

This is what can HAPPEN to the program.

Instead of treating interaction as arbitrary callbacks, the pattern models input as a language too. Examples:
- pointer moved
- key pressed
- node inserted
- selection changed
- parameter edited
- file opened
- transport started
- network message received

Events are architectural because they define how the source program evolves.

### 2.3 Apply

The pure reducer:

```text
Apply : (state, event) → state
```

Apply does not mutate the world in place. It takes the current source program and an event and returns the next source program.

That purity is what makes:
- undo simple
- structural sharing possible
- memoization coherent
- tests trivial
- the live loop understandable

### 2.4 Transitions

A transition is a pure, memoized boundary from one phase to another.

Examples:
- source → checked
- checked → resolved
- resolved → classified
- classified → scheduled
- lowered → machine-ir

A transition consumes unresolved knowledge. A real transition answers a real question:
- what name does this reference resolve to?
- which variant is this really?
- which defaults apply?
- what order exists?
- what concrete lower shape should this subtree have?

A transition is not just “another pass.” It is a reduction of ambiguity.

### 2.5 Terminals

A terminal is the boundary where the compiler stops producing progressively lower ASDL and defines executable meaning.

A terminal takes a phase-local node and produces either:
- a canonical Machine
- or a thin proto/install form when that is an honest one-step lowering

The terminal should be understood as the place where machine design becomes explicit:
- what is `gen`?
- what is `param`?
- what is `state`?
- what should be baked?
- what should stay live?

A terminal is still part of the compilation side. It decides the machine. It does not run it.

### 2.6 Proto language

The seventh concept has always been the **proto language**.

Once a machine exists, there is still one more language to cross:

> what is the installable realizable unit for this machine on this backend?

That question is answered by the proto language.

Realization is what the proto language is for. Realization is the lower compilation and installation movement:

```text
machine → proto → installed artifact
```

The proto language always exists, because every machine must become an installable thing on some host. What varies is whether the proto language is thin or rich.

Examples:
- thin Terra native proto lowering
- thin LuaJIT direct-closure proto lowering
- Lua bytecode template → blob → bind proto lowering
- source-kernel proto lowering via `load` / `loadstring`
- install catalogs with explicit artifact identity and caching

The proto language is where backend policy becomes explicit without contaminating the source language.

Its nouns may include:
- named realizable unit
- template
- binding plan
- artifact key
- install mode
- shape key
- bytecode blob
- source-kernel family

Those are not usually source-domain nouns. They are proto nouns.

### 2.7 Unit

A `Unit` is the packaged runtime artifact for a machine after it has crossed the proto boundary.

```text
Unit { fn, state_t }
```

`Unit` is about installation, composition, ownership, hot swap, and runtime calling convention.

A Unit is not the whole semantic story. It is the installed package of the machine after proto lowering and installation.

### 2.8 The live loop

Put together, those seven concepts yield the live loop:

```text
poll → apply → compile → execute
```

**poll** — read an input from the outside world

**apply** — use the pure reducer to derive the next source program

**compile** — re-run memoized transitions, terminals, and realization for affected subtrees only

**execute** — run the currently installed artifacts

This is incremental compilation as a direct consequence of architecture, not a bolt-on invalidation subsystem.

### 2.9 Hot swap is the natural execution story

The loop makes hot swap natural rather than exotic:
- old source compiled to installed artifacts
- a new event changes the source
- affected subtrees recompile
- affected machines re-realize
- affected Units re-install or swap
- execution continues using the new installed artifacts

There is no need for a second shadow architecture called “live objects” that must somehow be reconciled with compilation output. The installed artifact is the live thing.

### 2.10 The loop is continuous, not one-shot

This is not an ahead-of-time compiler that runs once and disappears. The program stays alive. The user keeps editing. The system keeps repeating:
- receive event
- derive next source
- recompile affected parts
- re-realize affected machines
- keep running the result

That is why the pattern fits interactive software so well.

### 2.11 Multiple compilation targets from one source

The same source program may feed multiple memoized products:
- execution artifacts
- view projections
- inspection structures
- error reports
- hit-test structures
- realization catalogs

These are not special cases. They are ordinary outputs of the same compiler architecture.

### 2.12 Why this is stronger than “just use immutable data”

Many systems use immutable data and still remain interpreter-shaped. They still:
- walk broad generic trees every frame
- branch on wide variants in hot paths
- bolt on caches later
- mix code generation with runtime object graphs
- hide backend policy in ad hoc runtime mechanisms

The compiler pattern is stronger. Its real claim is:

> the program should be modeled as source, compiled into a machine, realized explicitly, and then run.

That is much stronger than “use immutable data.”

---

## Part 3: The Three Levels — Compilation, Realization, and Execution

The pattern stays coherent because it distinguishes three different kinds of work:

1. work that decides what the machine should mean
2. work that decides how that machine should be installed on a backend
3. work that runs the installed result

A lot of architecture becomes muddy because these levels are collapsed together.

### 3.1 The compilation level

The compilation level is where the system reasons about the authored program.

It includes:
- Source ASDL
- Event ASDL
- Apply
- transitions
- projections
- structural error collection
- Machine IR
- terminal input design
- canonical machine design

Its characteristic properties are:
- pure
- structural
- memoized at stage boundaries
- testable by constructor + assertion
- driven by modeled data rather than ambient context

This is where questions are answered:
- which variant is this really?
- what does this reference resolve to?
- which defaults apply?
- what lower shape is honest?
- what machine should exist for this subtree?

### 3.2 The proto / realization level

The proto / realization level is where machine meaning becomes installable artifact form.

It includes things like:
- backend realization policy
- artifact planning
- source vs closure vs bytecode choice
- emitted-kernel assembly
- install catalogs
- artifact identity and cache keys
- backend-specific packaging decisions

Its characteristic properties are different from both pure semantic compilation and hot execution:
- still downstream of machine meaning
- often structural and memoizable
- explicitly backend-facing
- concerned with installation and artifact identity
- not the place where source-domain semantics should be rediscovered

This is where the proto language lives.

Sometimes the proto language is so thin that machine → proto → Unit feels almost compressed into one move. Sometimes it is rich enough to deserve explicit ASDL and helper machinery. In both cases, the architectural boundary is the same.

That is why the seventh concept should be named here as proto language rather than only as realization in the abstract. Realization is the process; proto language is the lower language it passes through.

### 3.3 The execution level

The execution level is where the installed artifact actually runs.

It includes:
- a Terra function over native state
- a LuaJIT specialized closure over FFI-backed state
- a loaded bytecode template with bound upvalues and installed state ownership
- a draw routine
- a parser callback
- an audio callback
- a simulation step

Its characteristic properties are:
- imperative internally if needed
- mutates only owned runtime state
- should not rediscover source semantics
- should be narrow, monomorphic, and operational

The execution level is not where the app decides what exists. It is where the installed artifact does the work it was specialized to do.

### 3.4 Why this split matters

If compilation work leaks downward into realization or execution, you get bad symptoms:
- runtime branching on wide source variants
- repeated name or ID lookup in hot paths
- artifact assembly doing semantic work that should already be resolved
- dependence on global context at the wrong level
- difficulty testing without standing up large parts of the runtime

If backend/install concerns leak upward into source modeling, you get different bad symptoms:
- source ASDL polluted with artifact modes or runtime handles
- domain types shaped by installer or bytecode concerns
- user vocabulary replaced by backend vocabulary
- save/load truth corrupted by implementation details

The split exists to prevent those failures.

### 3.5 Compilation-level code

Compilation-level code should read like pure structural compiler passes:
- `U.match`
- `U.with`
- `errs:each`
- `errs:call`
- ASDL constructors
- small pure helpers
- explicit error attachment

The goal is not aesthetic purity. The goal is to keep phase boundaries honest.

The framework's functional helpers belong here. They are the authoring surface of the pure layer. They are not the deepest runtime ontology.

### 3.6 Realization-level code

Realization-level code should read like backend-facing structural packaging, not like a second hidden semantic compiler and not like arbitrary runtime glue.

Good realization-level concerns:
- choose or derive a template family from already-lowered structure
- attach binding payload in a defined order
- choose artifact family
- compute shape keys and artifact keys
- install or restore installed artifacts

Bad realization-level concerns:
- deciding source-domain meaning
- discovering references that should have been resolved earlier
- interpreting a wide authored tree at install time
- replacing honest lower ASDL with raw string concatenation too early

### 3.7 Execution-level code

Imperative code is allowed at the execution level. It is expected there.

Good execution-level behavior:
- update filter history in state
- increment counters
- traverse already-lowered arrays
- issue GL/SDL/native calls
- run a parser step over already-decided control structure

Bad execution-level behavior:
- deciding which source variant something is
- validating authored references every call
- recomputing semantic facts every frame
- rebuilding install-time structure while running

### 3.8 Terminals end compilation; realization begins

Terminals still belong to the compilation side, even when they immediately produce an installed artifact.

The important conceptual order is:

```text
compilation decides the machine
realization installs the machine
execution runs the installed result
```

Some APIs may compress those steps. The architecture should not.

### 3.9 Error handling differs by level

At the compilation level, errors are structural:
- invalid authored combination
- missing reference
- unknown asset
- impossible lower form

At the proto / realization level, errors are install-oriented:
- backend does not support this realization mode yet
- bytecode artifact failed to load
- artifact restore failed
- binding installation failed

At the execution level, errors are operational:
- driver failure
- device failure
- hard runtime fault

Mixing these error families leads to bad design.

### 3.10 Testing differs by level

Compilation-level tests should look like:
- construct ASDL input
- call reducer / transition / terminal
- assert output

Realization-level tests should look like:
- construct lowered or machine input
- realize it
- assert artifact identity, source, install mode, or callable result

Execution-level tests may involve:
- smoke tests
- benchmarks
- backend integration checks
- profiling and latency measurement

All three matter, but they are not the same kind of test.

### 3.11 Backend neutrality depends on this split

Most of the application's meaning should live above realization:
- source language
- event language
- apply
- phase design
- Machine IR
- terminal intent

Most backend variation should live at realization and below:
- exact code shape
- artifact family
- installation path
- state representation
- calling convention

That is what keeps the architecture portable.

---

## Part 4: Machine, Proto Language, and Unit

### 4.1 What the lower stack is

The lower stack of the pattern is not just “terminal returns Unit.” It is:

```text
Machine IR
→ canonical Machine (`gen`, `param`, `state`)
→ proto language
→ Unit / installed artifact
```

That is the correct explanatory order.

- **Machine IR** makes lower execution structure explicit
- **Machine** is the semantic executable abstraction
- **proto language** is the language of installable realizable units for that machine on this backend
- **Unit** is the packaged installed runtime artifact

### 4.2 Why Machine is better than “just a function”

A plain function hides too much.

It does not tell you clearly:
- what should be baked into code shape
- what stable payload should remain available as param
- what mutable state must persist across calls
- what lower typed feeder layer should exist above it

`gen, param, state` makes those roles explicit.

That helps with:
- leaf-first design
- bake/live splits
- terminal input design
- backend comparison
- deciding what realization policy is actually appropriate

### 4.3 Why proto is not a backend footnote

Proto is not merely “the last bit of backend work.”

The proto language may be thin. It may be rich. But it is always there, and when it becomes non-trivial it deserves explicit design.

A good proto layer may need to represent:
- artifact family
- template family
- binding schema
- bytecode blob
- installation metadata
- shape identity
- artifact identity
- upvalue slot order
- hot-swap and cache behavior

Those are real architectural concerns. They should not be hand-waved away as incidental implementation detail when they materially shape the backend/install story.

See also §6.10 on proto footguns: proto richness invented too early, proto genericity kept too long, hidden binding contracts, and proto doing semantic work are all signs that the lower design is still wrong.

### 4.3.1 Realization as host contract

A canonical machine is not yet a running system.

That sentence is the key to the whole proto / realization layer.

By the time semantic compilation finishes, the compiler may already know exactly what should execute:
- what `gen` is
- what stable payload belongs in `param`
- what mutable payload belongs in `state`
- what loops, dispatch records, refs, slots, and resources the machine needs

But the machine is still not yet **hosted**.

It does not yet know:
- who installs it
- who calls it
- what timing model governs it
- what state ownership means in this host
- how hot swap works here
- what resource lifecycle rules apply
- what error boundary surrounds it
- what artifact forms this host accepts

That missing step is realization.

This is why realization should not be thought of merely as “emit some code” or “choose Lua vs Terra.” The deeper truth is:

> realization binds machine meaning to a host contract.

It also helps to separate three lower-level questions that are often confused:

1. **host/backend world** — LuaJIT, Terra, or some other host world
2. **proto family** — text proto, closure proto, quoted/native proto, generated proto, etc.
3. **artifact/install mode** — `load` / `loadstring`, direct closure, bytecode blob, native function, generated module, and so on

These are related, but they are not the same axis.

- **Lua vs Terra** is primarily a host distinction
- **text vs closure vs quote/native proto** is a proto-language distinction
- **`loadstring` vs closure vs bytecode vs native function** is an install-mode distinction

Keeping those axes separate prevents several design failures:

- leaking install policy into the domain language
- forcing different backends into one fake lowest-common-denominator proto
- hiding real host-contract differences behind the vague word “backend”
- making install code rediscover semantics that should already have been lowered

So when the lower architecture is clean, `proto` is one first-class realization side, but it may still contain several backend-shaped proto families inside it. A single `proto.lua` does not imply one generic universal proto language.

A host contract is the structured account of what a runtime world expects and provides. It may include:
- installation API
- uninstallation API
- swap policy
- callback or frame shape
- state ownership model
- timing model
- resource lifetime rules
- permitted artifact forms
- serialization or transport rules
- operational error boundary

In that sense, a backend is often not merely a target language. It is a **host world**.

A useful canonical pattern is:

```text
installed_artifact = realize(host_contract, machine)
```

That is the simple form of realization.

The machine says what should execute. The host contract says under what runtime terms that machine becomes alive. The installed artifact is the result.

This matters especially in multi-output systems, where one source program may compile into several different machines that must live under different host contracts.

For example, in a DAW-like system, one source program may yield:

- an **audio machine**
- a **view machine**
- a **network machine**
- perhaps a **control / MIDI machine**

These are all valid semantic products of the same source. But they are not hosted under the same contract.

An **audio host contract** may define:
- callback shape
- sample/block timing model
- real-time safety rules
- buffer ownership
- swap policy
- audio-device error boundary

A **view host contract** may define:
- frame/tick boundary
- input event boundary
- surface lifecycle
- redraw policy
- GPU resource ownership
- render-loop swap policy

A **network host contract** may define:
- send/receive boundaries
- connection ownership
- serialization rules
- retry / reconnection policy
- transport-level error handling

So a more complete picture is:

```text
source
→ semantic phases
→ canonical machine(s)
→ realize(audio_contract,   audio_machine)
→ realize(view_contract,    view_machine)
→ realize(network_contract, network_machine)
→ installed artifacts
```

That is why whole “backends” can become parameters. More precisely, whole **host contracts** can become parameters of realization.

This is stronger than ordinary backend abstraction. It is also stronger than dependency injection.

Dependency injection usually means passing services into arbitrary runtime code. Realization is cleaner than that. The host contract is not ambient context for arbitrary behavior. It is the explicit parameter to a controlled lower transformation:

```text
machine × host_contract → installed_artifact
```

That discipline prevents a common architectural collapse.

Without it, source-domain meaning leaks downward and host details leak upward:
- source ASDL grows fields that only matter because something will later be installed
- terminals quietly absorb installer logic
- realization code rediscovers semantic distinctions that should have been consumed earlier
- runtime integration accumulates ad hoc caches and hidden glue

With an explicit host-contract view of realization, the layers stay honest:
- the **source language** says what the user means
- the **machine** says what should execute
- the **proto layer** says where and under what contract that machine lives

This also clarifies what makes the proto language thin versus rich.

Sometimes the proto is thin:
- a small machine becomes a specialized Lua closure proto
- a Terra machine becomes a thin native install proto

Sometimes the proto language develops real nouns of its own:
- artifact family
- template family
- install mode
- shape key
- artifact key
- binding plan
- bytecode blob
- install catalog
- bundle or package

When those nouns are real, realization deserves explicit structure. That is not architectural drift. It is architectural honesty.

This is also the right place to understand proto-like vocabularies. `Proto`, `catalog`, `binding plan`, `install mode`, `artifact key` — these are usually not source-domain nouns. They are proto nouns. They become correct when the question is no longer “what does the user mean?” but rather:

> what is the installable realizable unit of this machine family under this host contract?

That is the deeper rule:

> a machine is semantically complete before realization, but it is not operationally alive until realization binds it to a host.

So realization exists because semantic correctness is not yet hosted existence.

That is why the layer matters. That is why audio, view, network, export, and control can each have different realization contracts. And that is why the right parameter of realization is often not merely a target compiler, but a whole host contract.

### 4.3.2 Three canonical Lua realization patterns: direct closure, template → blob → bind, and source kernel

Lua has three especially useful realization patterns, and all three should be treated as legitimate.

The first is **direct closure realization**:

```text
machine
→ specialized closure
→ installed function / Unit
```

This is often the best answer when installation is simple and closure capture already expresses the machine honestly. Direct closures are not a fallback. They are the best direct Lua realization form.

The second is the default **explicit structural** realization pattern:

```text
template function
→ string.dump(template_fn)
→ bytecode blob
→ load(blob)
→ debug.setupvalue(binding plan)
→ installed function / Unit
```

This pattern is unusually clean because it keeps each lower role explicit.

- The **template** is real Lua. You can read it, test it, profile it, and reason about it as ordinary code.
- The **bytecode blob** is the artifact form. It captures execution shape without pretending to be source truth.
- The **binding plan** is the realization form of machine `param`. The semantic compiler decides what values must be injected; realization decides where those values are bound.
- The **installed function** is the loaded and bound result. No source concatenation is required at install time, and no parser step is paid on the hot installation path.

In this design, `string.dump` captures shape, while `debug.setupvalue` injects compiled meaning. That is a very good fit for the canonical Machine split:

- `gen` chooses the execution family
- `param` becomes the stable binding payload
- `state` remains runtime-owned mutable data

The third is **source-kernel realization**:

```text
kernel source
→ load / loadstring
→ installed function / Unit
```

This is the right choice when the source kernel itself is the honest artifact: for example, when a human or a lower compiler intentionally shapes LuaJIT traces, performs unrolling, or authors exact low-level execution structure for a known machine family. In this mode, source is not a fallback for unfinished lowering; source is the realization artifact.

So the practical rule is:

- use **direct closures** when direct realization is honest
- use **template → blob → bind** when realization needs explicit artifact structure
- use **source kernels via `load` / `loadstring`** when exact LuaJIT code shape is itself the point

Terra still makes sense when explicit native ABI, native layout, or LLVM-level optimization is required. The real distinction is not “closures versus bytecode.” It is **direct realization versus explicit realization**.

It is also the right place to be strict.

- No ad hoc `loadstring` as the default installation path.
- No source concatenation that rediscovers semantics which should already have been lowered.
- No relying on informal upvalue ordering in bytecode-binding paths.

If bytecode installation depends on upvalues, the proto layer should model the binding schema explicitly: slot index, expected meaning, and compiled payload source. The template family should identify a class of machines that share one execution shape under one host contract; differing compiled payload should change binding values, not force a brand-new semantic architecture.

If source-kernel realization is used, the generated or handwritten source should likewise correspond to a known realization family rather than serving as a generic escape hatch for unresolved semantics.

In practical terms, a template family or source-kernel family corresponds roughly to a **terminal realization family**: one host-side execution skeleton for a machine shape, an artifact mode, and a host contract. That is why explicit Lua realization is not just serialization. It is a host-contract design.

### 4.4 What belongs in param, state, and artifact

A useful discipline is:

**belongs in `param`:**
- stable machine input
- resolved refs
- coefficients
- slot indices
- already-decided control structure
- machine-local static payload

**belongs in `state`:**
- mutable runtime-owned data
- counters
- histories
- accumulators
- persistent execution-time state

**belongs in realization artifact form:**
- template identity or shape key
- binding schema / binding payload
- bytecode blob
- artifact key
- install metadata
- backend-specific packaging details

**does not belong in any of these lower layers:**
- user-authored choices that should stay in source ASDL
- unresolved references
- wide source-domain sums that should have been consumed earlier

### 4.5 Structural installation and composition

Units compose structurally, and realization artifacts often should too.

If child A and child B are separate compiled or realized child machines, parent composition should reflect that structure rather than rebuilding a shadow runtime architecture around them.

That gives the system a natural locality story:
- source tree composes structurally
- lower machine-feeding forms compose structurally
- realization artifacts may compose structurally
- Units compose structurally
- runtime state layout composes structurally

All of those layers line up when the model is honest.

### 4.6 The canonical machine: gen, param, state

The canonical machine layer immediately above runtime packaging is:

- **gen** — the execution rule / code-shaping part
- **param** — the stable machine input it reads
- **state** — the mutable runtime-owned state it preserves

So the bottom of the architecture is best understood as a canonical chain, not a single handoff:

1. **transitions** — pure boundaries that consume knowledge and produce the right lower typed forms
2. **Machine IR** — the typed machine-feeding layer that makes order, access, use-sites, resource identity, and runtime ownership explicit
3. **canonical Machine** — `gen`, `param`, `state`
4. **proto language** — target-specific installable form of that machine
5. **Unit / installed artifact** — installed runtime packaging as `Unit { fn, state_t }`

On LuaJIT specifically, the proto language may produce:
- a direct closure for tiny or cold paths
- a specialized closure for the smallest common hot paths
- a bytecode template artifact installed by `load(blob)` plus explicit `debug.setupvalue` binding
- an install-oriented artifact catalog when that is the honest backend surface

These are realization policies for the same machine, not new semantic layers.

This is not an optional explanatory trick. It is the right way to think about terminal design. The compiler's semantic product is the machine. The installed runtime artifact is how that machine is hosted on a backend.

### 4.7 Machine IR

A good Machine IR above the canonical machine is the **typed machine-feeding layer** that makes the machine's compiled wiring explicit. The machine is the real semantic executable abstraction; Machine IR exists to make that machine trivial to derive; realization and Unit then package it for installation and runtime.

Machine IR should answer five things directly:

1. **Order** — what loops exist? What spans or ranges are executed? What headers determine one execution slice?
2. **Addressability** — how does execution reach what it needs? What refs, slots, indices, or handles are already resolved?
3. **Use-sites** — what concrete occurrences are executed? What instances of drawing, querying, routing, or processing exist?
4. **Resource identity** — what realizable resources may need runtime ownership? What stable resource specifications identify them?
5. **Runtime ownership requirements** — what mutable runtime state must persist? What state schema does the machine require?

That is a more useful way to think about Machine IR than calling it merely a planning layer. Its job is to make `gen`, `param`, and `state` obvious.

This does **not** mean introducing a generic interpreted wiring DSL. The pattern should not devolve into runtime nodes like `Accessor(kind, ...)` or `Processor(kind, ...)` that execution must interpret dynamically. That would just recreate the accidental interpreter lower down.

Instead, the wiring should already have been compiled into typed shapes the machine can consume directly: spans and ranges, headers and closed dispatch records, slot refs, instance records, resource specifications, runtime state schemas.

The practical test is:

> does the machine receive explicit order, addressability, use-sites, resource identity, and persistent state needs — or does it still have to invent them while running?

If it still has to invent them, the phase structure above it is still too high-level.

### 4.8 The header pattern

When several later branches must remain aligned after a shared flattening phase, it is often a mistake to keep widening one giant node record so every later branch can still find the same thing.

A better design is often:

1. define a **shared structural header vocabulary**
2. let later branches carry only their own orthogonal fact planes
3. rejoin those branches structurally through the shared header/index space rather than through semantic lookup

A header is not just metadata. It is a typed structural carrier for truths such as: stable identity, parent/child topology, subtree spans, region-local index space — whatever minimal structural alignment later branches must share.

The discipline is:

> keep shared structure in the header spine; keep branch-specific meaning in separate fact planes.

Without a header spine, there is constant pressure to build oversized lower nodes that carry unrelated concerns together merely so later phases can still line them up.

### 4.9 The facet pattern

If the header spine carries the shared structural truth, the next question is: what different aspects of meaning are attached to that shared structure, and which later consumers actually need which aspects?

A **facet** is one orthogonal semantic plane aligned to the shared header/index space.

Typical examples:
- layout facts
- paint facts
- content facts
- behavior facts
- accessibility facts
- routing facts
- realization facts when several install-oriented branches share one structural spine

Instead of widening one lower node record until it carries everything, a better design is:

1. one shared header spine
2. several aligned facet planes
3. branch-specific lowerings that consume only the facets they actually need

Together, headers and facets give a powerful lower design shape:

> **spine + facets**

The spine carries shared structural truth. The facets carry orthogonal semantic truth.

### 4.10 Errors and fallback at the realization / Unit boundary

Suppose a subtree cannot be compiled or realized cleanly because:
- an asset is missing
- a reference is invalid
- a backend does not support a requested realization form yet
- an emitted artifact fails to install

A good architecture can:
- attach an error to that subtree
- produce a neutral fallback artifact or Unit if appropriate
- continue compiling unaffected siblings

A missing image may compile to a placeholder visual Unit. An unsupported effect may compile to a no-op Unit plus an attached error. A realization mode not yet supported may fall back from bytecode to source or closure when that is architecturally honest. This is much cleaner than turning one subtree problem into a global runtime failure.

---

## Part 5: Designing the ASDL

Before the step-by-step method, it helps to make the architectural vocabulary explicit.

There are really **three different distinctions** in play:

1. the minimal set of **formal type constructors**
2. the minimal set of **architectural roles**
3. the difference between **domain modeling** and **realization modeling**

Confusing these levels creates a lot of design fog.

- The **formal** level tells you what shapes the type algebra has.
- The **architectural** level tells you how those shapes are used in a compiler-pattern design.
- The **domain vs realization** distinction tells you which language you are designing at a given moment.

This last distinction is now essential.

A compiler-pattern system always contains both:

1. a **domain source language**
2. a **proto language** for installable artifacts

Those are not the same thing.

The first is the language of meaning. The second is the language of installation.

A parser frontend may have source nouns like:
- grammar
- token
- rule
- product

and proto nouns like:
- proto
- template family
- binding schema
- artifact key
- install mode
- bytecode blob

The first language describes what the user means in the domain.
The second language describes how already-lowered machine meaning becomes installable on a backend.

The crucial refinement is that the proto language is always present architecturally, even when it is thin, degenerate, or almost identity-shaped. The design question is not whether the second language exists. The design question is whether it is thin or rich.

This is why the seventh concept has always really been proto language. “Realization” names the lower compilation/install movement through that language; proto language names the language itself.

If you confuse them, you get one of two bad outcomes:
- realization concerns leak upward and pollute the source ASDL
- source-domain meaning gets rediscovered too late inside the backend/install layer

So Part 5 now has two jobs:

1. explain how to model the **domain source ASDL** correctly
2. explain how to model the **proto ASDL** honestly, whether it is thin or rich

#### How the two languages think differently

This distinction is not only about vocabulary. It is about mindset.

In the **domain ASDL**, we think in **meaning**.

The questions are:
- what does the user work with?
- what does the user see and edit?
- what must save/load preserve?
- what must undo restore?
- what has stable domain identity?
- what are the real domain variants?
- what owns what in the user's world?

So domain ASDL thinks in nouns such as:
- entity
- property
- variant
- containment
- reference
- authored choice
- persistent truth

In the **proto ASDL**, we think in **hosting**.

The questions are:
- what is the smallest installable thing?
- what proto family does this machine belong to?
- what host contract installs it?
- what binding surface does it expose?
- what artifact identity matters?
- what gets cached, restored, swapped, or loaded?
- what install structure is real here?

So proto ASDL thinks in nouns such as:
- proto
- template family
- source-kernel family
- binding plan
- artifact family
- install mode
- shape key
- artifact key
- install catalog

The difference is fundamental:

> domain ASDL is modeled from the user's ontology;
> proto ASDL is modeled from the host's ontology.

Or more briefly:

> in the domain ASDL, we think in meaning;
> in the proto ASDL, we think in hosting.

If you think proto thoughts while modeling the domain ASDL, source truth gets polluted by install concerns. If you think domain thoughts while modeling the proto ASDL, installation stays vague and generic when it should have specialized structure.

So one of the core design skills in this pattern is learning to switch mental mode deliberately:
- **domain mode** for source truth
- **proto mode** for installation truth

### 5.0 The minimal architectural vocabulary

#### 5.0.1 The formal minimum

At the deepest level, most useful ASDL is built from a very small algebra:

- **product** — a record with fields
- **sum** — a tagged choice / enum / variant
- **sequence** — zero or more children
- **reference** — a stable cross-link by ID
- **identity** — stable naming of independently editable things

This is the mathematical minimum.

But this level is too low-level to guide architecture by itself. It does not tell you:

- what deserves stable identity
- which choices belong in the source ASDL
- when a lower phase should become a projection
- when several downstream branches need one shared alignment space
- when one wide lower node should split into orthogonal semantic planes

For that, we need a second vocabulary.

A note on **reference** specifically: reference belongs in the formal minimum, but it should be treated with caution in architectural design.

A reference is not automatically wrong, but it is never free. It introduces non-local dependency, validation burden, phase-ordering pressure, possible cycles, and lookup needs. Containment is the calm default. Reference is a controlled escape from the tree.

So the right stance is:

- containment first
- references only for real authored cross-links
- references represented as stable IDs, never live object pointers
- references resolved in explicit phases as early as possible

A useful practical slogan is:

> a reference is not necessarily a smell, but it is always a coupling signal.

If references proliferate, ask whether the design is missing containment, normalization, a projection, a spine, or a dedicated resolve phase.

#### 5.0.2 The architectural minimum

A more useful working vocabulary for this repository is:

- **entity**
- **variant**
- **projection**
- **spine**
- **facet**

These are not new formal type constructors. They are recurring architectural roles built from products, sums, sequences, references, and stable identity.

This is close to the minimal practical vocabulary for designing ASDL well. Once this vocabulary is clear, design becomes much more compositional: instead of inventing large custom shapes from scratch, you compose a small number of known roles correctly.

#### 5.0.3 Entity

An **entity** is a persistent user-visible thing with stable identity.

Examples:

- track
- clip
- device
- block
- span
- cell
- chart
- node
- layer

An entity answers:

> what is the thing the user can point to and say "that one"?

An entity is usually:

- a product type
- given a stable numeric ID
- marked `unique` when it is a concrete ASDL type
- owned by exactly one parent in the containment tree

Example:

```asdl
Editor.Document = (Block* blocks, Selection selection) unique
Editor.Block = (number id, BlockKind kind, Span* spans) unique
Editor.Span = (number id, SpanKind kind, string text) unique
```

Here `Document`, `Block`, and `Span` are entities because the user can independently reason about them, edit them, and expect them to persist across save/load and undo.

A useful non-example is:

```asdl
Editor.Block = (number id, string text, number line_count) unique
```

If `line_count` is derived from `text`, it is not a user-authored entity and should not even be a source property. It belongs in a later projection if some consumer needs it.

#### 5.0.4 Variant

A **variant** is a real domain “or”.

Examples:

- a clip is audio **or** MIDI
- a selection is cursor **or** range
- a chart is bar **or** line **or** pie
- a node is gain **or** filter **or** oscillator

A variant answers:

> what closed set of kinds can this thing be?

A variant is usually a sum type.

Example:

```asdl
Editor.Selection = Cursor(number span_id, number offset)
                 | Range(number start_span_id, number start_offset,
                         number end_span_id, number end_offset)

Editor.BlockKind = Paragraph
                 | Quote
                 | CodeBlock(string language)
```

This is better than string tags because it gives:

- exhaustiveness
- variant-specific payloads
- explicit domain closure
- cleaner downstream lowering

The smell to watch for is:

```asdl
Editor.Block = (number id, string kind, string text, string language) unique
```

If `kind` is a closed set, it wants to be a sum type. Otherwise every later boundary is forced to re-interpret the string.

#### 5.0.5 Projection

A **projection** is a derived ASDL view of another ASDL.

Examples:

- source → view
- source → resolved
- resolved → scheduled
- document → outline
- graph → render tree
- source → machine IR

A projection answers:

> what derived shape do later consumers need that should not distort the source ASDL?

Projection matters because the source ASDL models the user’s world, not every consumer’s world.

Example:

```asdl
Editor.Track = (number id, string name, Device* devices) unique
```

A view might need:

- a track header row
- a mixer strip
- a device panel
- selected styling
- hit targets

Those do not belong in `Editor.Track`. A better design is a projection:

```asdl
View.TrackHeader = (number track_id, string label, bool selected)
View.MixerStrip = (number track_id, string label, number meter_db)
View.DevicePanel = (number track_id, DeviceCard* cards)
```

Likewise, a resolve phase is also a projection:

```asdl
Editor.Send = (number id, number target_track_id, number gain_db) unique
Resolved.Send = (number id, number target_track_id, number gain_db,
                 number target_bus_ix) unique
```

`Resolved.Send` has consumed a routing decision without polluting the source ASDL with derived scheduling facts.

#### 5.0.6 Spine, header, and shared alignment

A **spine** is a shared structural alignment space used by several downstream branches.

A spine answers:

> what shared structure must later branches remain aligned on?

Typical spine facts include:

- stable identity
- flattened order
- parent/child topology
- subtree spans
- region-local indices
- addressability
- execution order

A spine is usually carried by a header-like product type. That is why this document often uses the phrase **header spine**.

The clean way to think about it is:

- **spine** = the architectural role
- **header** = the common concrete record that carries that role

So `header` is usually not a separate primitive alongside `spine`. It is the usual carrier of the spine.

Example:

```asdl
View.Header = (
    number id,
    number parent_ix,
    number start_ix,
    number end_ix,
    NodeRole role
) unique
```

This is not “mere metadata.” It is shared structural truth that several later branches can align on.

Another example from a scheduled audio phase:

```asdl
Scheduled.Header = (
    number node_id,
    number order_ix,
    number input_bus_ix,
    number output_bus_ix,
    number channel_count
) unique
```

This one header can align coefficient computation, meter routing, execution order, and bus allocation without forcing those concerns into one giant lower node.

#### 5.0.7 Facet

A **facet** is one orthogonal semantic plane aligned to a shared spine.

A facet answers:

> given the shared structure, what aspect of this thing are we talking about?

Typical facets include:

- layout facet
- paint facet
- content facet
- behavior facet
- accessibility facet
- routing facet
- query facet
- animation facet

A facet is not the structure itself. It is semantic meaning attached to a shared structural alignment space.

Example:

```asdl
View.Header = (
    number id,
    number parent_ix,
    number start_ix,
    number end_ix,
    NodeRole role
) unique

View.ContentFacet = (
    number id,
    string text
) unique

View.LayoutFacet = (
    number id,
    number x,
    number y,
    number w,
    number h
) unique

View.PaintFacet = (
    number id,
    Color fg,
    Color bg,
    PaintKind paint
) unique

View.HitFacet = (
    number id,
    HitKind hit,
    number action_id
) unique

View.A11yFacet = (
    number id,
    A11yRole role,
    string label
) unique
```

Now different downstream consumers can take only the semantic planes they need:

- layout lowering uses `Header + ContentFacet`
- painting uses `Header + LayoutFacet + PaintFacet`
- hit testing uses `Header + LayoutFacet + HitFacet`
- accessibility uses `Header + A11yFacet`

That is better than one giant lower node because unrelated edits stay more local and the joins stay structural rather than semantic.

#### 5.0.8 Source roles, lower roles, and realization roles

The same vocabulary does not dominate every phase.

At the **source** level, the dominant roles are:

- entity
- property
- variant
- containment
- reference

Questions at this layer are:

- what are the user-visible nouns?
- which nouns have stable identity?
- what fixed choices are true domain variants?
- what owns what?
- what cross-links are real authored references?

At **lower semantic** phases, the dominant roles become:

- projection
- spine
- facet
- schedule/order/index/address records
- closed terminal payloads

Questions at this layer are:

- what derived shape does the machine need?
- what structural alignment must later branches share?
- which meanings should be separated into orthogonal facets?
- what decisions must be consumed before the terminal?

At the **realization** layer, the dominant roles may become:

- proto / realizable unit
- template family
- binding schema
- artifact family
- shape key
- artifact key
- install catalog
- bytecode / source-kernel / native policy record

Questions at this layer are:

- what is the realizable unit of installation or caching?
- what values are bound as binding payload rather than re-emitted structurally?
- what identity belongs to machine shape versus concrete installed artifact?
- what backend policy choices are explicit here?
- what artifact form should be produced?

Leaf-first design sharpens these questions. Once you begin at the leaf, you usually discover two different smallest truthful things:

1. the smallest truthful **machine**
2. the smallest truthful **installable realization unit**

The first belongs to semantic compilation. The second belongs to realization. When that second unit needs stable identity, packaging, binding, install metadata, or cacheability, it becomes a realization noun — often a **proto**.

So `Proto` should not be pulled upward as a fashionable generic term into the domain source phase. But it should be treated as architecturally universal on the realization side. Every machine crosses a proto boundary, even if the proto is almost empty. It becomes rich when leaf-first design reveals that the backend really does need one named realizable member of a machine family with a specific install story.

Proto also forces specialization. A machine forces semantic specialization; a proto forces realization specialization. Once something is a proto, the backend/install layer must commit to a concrete realizable family, a concrete binding surface, and a concrete artifact identity instead of hiding behind generic installer glue.

This is why `spine + facets` is a canonical semantic lowering shape but usually not the first move in source modeling, and why proto/artifact vocabularies usually belong at realization rather than at the domain source phase.

A practical rule is:

> if the noun only exists because something must be emitted, loaded, cached, restored, or installed, it is probably a realization noun, not a source-domain noun.

#### 5.0.9 Worked example: source entities become a view spine plus facets

Suppose a small document editor has paragraphs, code blocks, links, and selections.

A good source ASDL might be:

```asdl
Editor.Document = (Block* blocks, Selection selection) unique

Editor.Block = (number id, BlockKind kind, Span* spans) unique
Editor.BlockKind = Paragraph
                 | Quote
                 | CodeBlock(string language)

Editor.Span = (number id, SpanKind kind, string text) unique
Editor.SpanKind = Text
                | Emphasis
                | Link(number target_block_id)

Editor.Selection = Cursor(number span_id, number offset)
                 | Range(number start_span_id, number start_offset,
                         number end_span_id, number end_offset)
```

This is source-authored truth:

- entities: `Document`, `Block`, `Span`
- variants: `BlockKind`, `SpanKind`, `Selection`
- reference: `target_block_id`
- containment: document owns blocks, blocks own spans

Now suppose a later view pipeline flattens the document for layout, paint, hit testing, and accessibility.

A bad lower design is one giant node:

```asdl
BadView.Node = (
    number id,
    number parent_ix,
    number start_ix,
    number end_ix,
    Rect rect,
    string text,
    PaintKind paint,
    HitKind hit,
    A11yRole a11y_role,
    string a11y_label,
    bool selected
) unique
```

A better design is:

```asdl
View.Header = (
    number id,
    number parent_ix,
    number start_ix,
    number end_ix,
    NodeRole role
) unique

View.ContentFacet = (number id, string text) unique
View.LayoutFacet = (number id, number x, number y, number w, number h) unique
View.PaintFacet = (number id, PaintKind paint, bool selected) unique
View.HitFacet = (number id, HitKind hit, number action_id) unique
View.A11yFacet = (number id, A11yRole role, string label) unique
```

Now:

- the source ASDL stayed honest to the domain
- the lower ASDL introduced a projection
- the projection split into one spine plus several facets
- downstream consumers remain aligned structurally without carrying unrelated facts together

#### 5.0.10 Worked example: scheduled audio as projection + spine + specialized payloads

Consider a source audio graph:

```asdl
Editor.Project = (Track* tracks) unique
Editor.Track = (number id, string name, Device* devices, Send* sends) unique
Editor.Send = (number id, number target_track_id, number gain_db) unique

Editor.Device = Osc(number id, number hz)
              | Gain(number id, number db)
              | Filter(number id, number hz, number q)
```

Here the source phase contains:

- entities: project, track, send, device instances
- variants: `Device`
- references: `target_track_id`

A resolve phase may attach validated bus routing:

```asdl
Resolved.Send = (
    number id,
    number target_track_id,
    number gain_db,
    number target_bus_ix
) unique
```

A later schedule phase may establish a shared execution spine:

```asdl
Scheduled.Header = (
    number node_id,
    number order_ix,
    number input_bus_ix,
    number output_bus_ix,
    number channel_count
) unique

Scheduled.OscPayload = (number node_id, number hz) unique
Scheduled.GainPayload = (number node_id, number linear_gain) unique
Scheduled.FilterPayload = (
    number node_id,
    number hz,
    number q,
    double* coeffs
) unique
```

At this stage the important move is not to drag the entire authored variant shape into the hot path. The terminal should receive a narrow, phase-local, monomorphic payload. If the leaf is still switching on authored strings or wide source variants, the lowering is incomplete.

#### 5.0.11 The design game is mostly composition

Once the vocabulary is explicit, many good designs reduce to a few recurring compositions:

- **entity + variant** — a persistent thing with meaningful kinds
- **entity + reference** — a persistent thing that points outside containment
- **projection + spine** — a derived phase that several later consumers must align on
- **spine + facets** — shared structure with orthogonal semantic planes
- **projection → closed payload** — the narrowing move just before the terminal

That is why good ASDL design is less about inventing many special-purpose shapes and more about composing a small number of roles correctly.

The operational steps below are how to discover those roles in a real domain.

### 5.1 Step 1: List the nouns

Start by asking a precise question:

> whose language am I modeling right now?

There are two common answers:

1. **the domain user's language**
2. **the realization author's language**

Most of the time, Part 5 starts with the first one. You are modeling the domain source ASDL. In that case, open the program you're modeling (or imagine it if it doesn't exist), look at every element the user can see and interact with, and write down every noun.

For a DAW:
```
project, track, clip, audio clip, MIDI clip, note, device,
effect, instrument, parameter, knob, fader, slider, automation curve,
breakpoint, modulator, LFO, envelope, send, bus, group track,
master track, tempo, time signature, marker, scene, launcher slot,
arranger, mixer, device chain, patch cable, module, port, grid,
transport, playhead, loop region, selection, solo, mute, arm,
monitor, pan, volume, waveform, spectrogram, meter, plugin
```

For a text editor:
```
document, paragraph, line, character, word, sentence,
selection, cursor, mark, font, size, weight, slant,
color, style, span, heading, list, list item, link,
image, table, cell, row, column, page, margin,
indent, tab stop, ruler, bookmark, fold, comment
```

For a spreadsheet:
```
workbook, sheet, cell, row, column, range, formula,
reference, function call, value, number, string, boolean,
format, border, fill, font, alignment, conditional format,
chart, axis, series, data point, filter, sort, pivot table,
named range, validation rule, comment, hyperlink
```

If instead you are modeling a **realization framework**, the “user” at that layer is usually a compiler/backend author, not the app end-user. Then the honest nouns may be things like:

```
proto, catalog, template, binding plan, install mode,
artifact, shape key, artifact key, bytecode blob,
chunk name, install entry, host contract
```

That is fine — if and only if that really is the language being authored.

The critical rule is:

> do not pull proto nouns upward into the domain source language just because you know they will matter later.

A JSON parser source language should usually start from:
- grammar
- token
- rule
- product

not from:
- proto
- chunk
- bytecode blob

Those may become the right nouns later at realization time, but they are not automatically the right nouns at the domain source phase.

So Step 1 is really:

1. identify the layer you are modeling
2. list the nouns that are truthful at that layer
3. refuse nouns from lower layers unless they are genuinely authored there

### 5.2 Step 2: Find the identity nouns (entities)

Not all nouns are equal. Some are THINGS with identity — they persist, they can be referenced, they can be edited independently. Others are PROPERTIES of things — they change when the thing changes, they don't have independent identity.

Identity test: "Can the user point to this and say 'that one'?"

```
DAW:
    IDENTITY (user can point to it):
        project, track, clip, device, parameter, send,
        automation curve, modulator, scene, launcher slot,
        graph, node, wire, port, module

    PROPERTY (attribute of an identity noun):
        volume, pan, mute, solo, arm, frequency, Q,
        waveform shape, tempo value, time signature,
        breakpoint position, clip start/end
```

Identity nouns become ASDL records or enum variants. Property nouns become fields ON those records.

### 5.3 Step 3: Find the sum types (variants)

Sum types represent CHOICES — places where the domain has more than one possibility. They are the most important types in the source phase because they represent UNRESOLVED DECISIONS.

Look for the word "or" in your domain:

```
DAW:
    A clip is an audio clip OR a MIDI clip.
    A device is a native device OR a layer device OR a selector OR a split OR a grid.
    A parameter source is static OR automated OR modulated.
    An automation curve segment is linear OR curved OR step.
    A track is an audio track OR an instrument track OR a group OR a master.

Text editor:
    A block is a paragraph OR a heading OR a list OR a code block OR an image.
    A span is plain OR bold OR italic OR link OR code.
    A selection is a cursor (collapsed) OR a range.
    An edit operation is insert OR delete OR replace OR format.

Spreadsheet:
    A cell value is number OR string OR boolean OR formula OR empty.
    A formula term is literal OR cell ref OR range ref OR function call.
    A format condition is value-based OR formula-based.
    A chart type is bar OR line OR scatter OR pie.
```

Each "or" becomes an ASDL enum. Each option becomes a variant. This is where domain expertise matters most — missing a variant means the system can't represent something the user needs. Adding a variant later means every `U.match` in the pipeline needs a new arm.

### 5.4 Step 4: Find the containment hierarchy

Domain objects contain other domain objects. The containment forms a tree (or DAG). This tree IS the ASDL structure.

Containment is the default structural relation because it is local, memo-friendly, and easy to reason about. References are the exception. If a relationship is really ownership, model ownership. If a relationship is truly a non-owning cross-link, represent it as a stable ID and plan an explicit resolve phase for it later.

```
DAW:
    Project
    └── Track*
        ├── DeviceChain
        │   └── Device*
        │       ├── Parameter*
        │       ├── ModSlot*
        │       │   └── Modulator
        │       │       └── Parameter*
        │       └── ChildGraph*
        │           └── Graph
        │               ├── Node*
        │               ├── Wire*
        │               └── Port*
        ├── Clip*
        │   ├── AudioClip → AssetRef
        │   └── MIDIClip → MIDIEvent*
        ├── Send*
        ├── LauncherSlot*
        └── AutomationLane*
            └── AutomationCurve
                └── Breakpoint*

Text editor:
    Document
    └── Block*
        ├── Paragraph → Span*
        ├── Heading → Span*, level
        ├── List → ListItem*
        │         └── Block* (recursive!)
        ├── CodeBlock → string, language
        └── Image → AssetRef, caption

Spreadsheet:
    Workbook
    └── Sheet*
        ├── Cell[row][col]
        │   ├── value: CellValue
        │   ├── format: CellFormat
        │   └── validation: ValidationRule?
        ├── Chart*
        │   ├── Series*
        │   └── Axis*
        └── ConditionalFormat*
```

Read this tree as the ASDL:
```
Project = (string name, Track* tracks, Transport transport, ...) unique
Track = (number id, string name, DeviceChain devices, Clip* clips, ...) unique
DeviceChain = (Device* devices) unique
```

Now apply the reference discipline carefully.

A useful rule is:

> containment is the default; references are controlled escapes from the tree.

That means:

- use references only for real authored cross-links
- represent them as stable IDs, never positions or live pointers
- treat every reference as a coupling signal
- consume references into more local structure in a later resolve phase as early as possible

If references start appearing everywhere, suspect the ASDL before normalizing the complexity away in runtime code.

### 5.5 Step 5: Find the coupling points

Coupling points are places where two independent subtrees of the containment hierarchy need information from each other. These are the HARDEST design decisions because they determine phase boundaries.

```
DAW coupling points:
    Text ←→ Layout
        Text wrapping depends on available width (from layout).
        Layout height depends on text measurement (from shaping).
        → must be resolved in the SAME phase.

    Automation ←→ Parameter
        A parameter's value at time T depends on the automation curve.
        The automation curve's range depends on the parameter's min/max.
        → automation must be resolved AFTER parameters are defined.

    Send ←→ Track
        A send references another track by ID.
        The target track must exist and have compatible channel count.
        → sends must be resolved AFTER all tracks are defined.

    Modulator ←→ Parameter
        A modulator's output maps to a parameter's range.
        The mapping depends on both the modulator's output range
        and the parameter's value range.
        → modulation binding must be classified AFTER both are defined.

Text editor coupling points:
    Style ←→ Font
        A style specifies a font family. The actual font file
        must be resolved (font fallback, system fonts).
        → font resolution is its own phase.

    Paragraph ←→ Page
        Line breaking depends on page width.
        Page breaking depends on paragraph heights.
        → layout and pagination are interleaved.

Spreadsheet coupling points:
    Formula ←→ Cell
        A formula references other cells.
        Those cells might contain formulas that reference this cell.
        → dependency analysis is its own phase (topological sort).

    Conditional format ←→ Value
        A conditional format depends on cell values.
        But cell values depend on formulas which depend on other cells.
        → conditional formatting is AFTER formula evaluation.
```

Each coupling point tells you something about phase ordering. If A depends on B and B depends on A, they must be resolved in the same phase. If A depends on B but B doesn't depend on A, B must be resolved first (earlier phase).

### 5.6 Step 6: Define the phases

Phases are ordered by knowledge. Each phase knows everything the previous phase knew, plus the decisions it resolved. The source phase has the most sum types (most unresolved decisions). The terminal phase has zero sum types (everything resolved to concrete values).

The method:
1. Start with the source phase (the user's vocabulary)
2. List all the decisions that need to be resolved
3. Order them by dependency (coupling points determine order)
4. Group decisions that must happen together (coupling)
5. Each group becomes a phase transition

Another useful framing is:

- source phases are dominated by **entities**, **variants**, containment, and references
- intermediate phases are usually **projections** that consume decisions
- when several later branches need the same structural alignment, introduce a **spine**
- when those branches need different semantic facts, split those facts into **facets**
- terminal-adjacent phases should collapse toward closed monomorphic payloads

```
DAW phases:

    Editor (source):
        All sum types present. User vocabulary.
        Device = NativeDevice | LayerDevice | SelectorDevice | ...
        Clip = AudioClip | MIDIClip
        AutomationSource = Static | Clip | Scene | Global

    Authored (after lowering):
        Containers flattened to graphs.
        Device variants → Node with NodeKind.
        Connections explicit as Wire objects.
        Decisions consumed: device container topology.

    Resolved (after resolving):
        IDs stable. Cross-references validated.
        Sends resolved to target tracks. Assets validated.
        Decisions consumed: identity resolution, reference validation.

    Classified (after classifying):
        Rate classes assigned (sample, block, init, constant).
        Modulation bindings computed.
        Decisions consumed: update rate, modulation depth.

    Scheduled (after scheduling):
        Buffer slots assigned. Linear job list computed.
        Topological sort done.
        Decisions consumed: execution order, buffer allocation.

    Terminal (compilation):
        Each job → Unit. Session → composed Unit.
        Decisions consumed: ALL. The output is monomorphic native code.
```

Each phase transition has a VERB: lower, resolve, classify, schedule, compile. The verb describes what knowledge is consumed. If you can't name the verb, the phase transition isn't meaningful.

#### The universal phase pattern

Across every domain we've examined — DAW, text editor, spreadsheet, game engine, UI toolkit — the same sequence of phases appears, with domain-specific names:

```
Phase 1: VOCABULARY      (what the user said)
Phase 2: SEMANTIC MODEL  (what it means)
Phase 3: RESOLVED MODEL  (validated, references linked)
Phase 4: CLASSIFIED      (rate/type/category assigned)
Phase 5: SCHEDULED       (execution plan, order, resources)
Phase 6: COMPILED        (native code, Unit)
```

Not every domain needs all six. Some merge phases. Some skip phases. But the ORDER is universal. You cannot schedule before resolving. You cannot classify before knowing the semantic model. You cannot compile before scheduling.

**Phase 1: Vocabulary.** This is the user's language. The types mirror the UI. Every button, every panel, every editable field corresponds to a field in this phase.

Design rules:
- Name types the way the user would name them (Track, not AudioChannel)
- Sum types represent user choices (Device = Native | Layer | Selector | ...)
- Fields represent user-editable values (frequency, volume, color, text)
- No derived values (coefficients, layouts, compiled code)
- No implementation details (buffer sizes, thread IDs, memory addresses)
- Must pass the save/load test, the undo test, the completeness test

```
-- DAW vocabulary
Editor.Track = (number id, string name, Device* devices,
                number volume_db, number pan, boolean muted, ...) unique

-- Text editor vocabulary
Editor.Document = (Block* blocks, Cursor cursor, Selection? sel) unique

-- Spreadsheet vocabulary
Editor.Sheet = (Cell* cells, number rows, number cols, ...) unique

-- Game vocabulary
Editor.Scene = (Entity* entities, Camera camera, Lighting lighting) unique
```

**Phase 2: Semantic model.** The vocabulary contains user-facing abstractions that hide complexity. Phase 2 UNFOLDS these abstractions into their semantic meaning.

In a DAW: Device containers (Layer, Selector, Split) become Graphs with Nodes and Wires. The user thinks "layer device." The compiler thinks "parallel graph with mix node."

In a text editor: Rich text spans become resolved font runs. The user thinks "bold." The compiler thinks "font lookup → FiraCode-Bold.otf → glyph IDs."

In a spreadsheet: Formula strings become expression trees. The user thinks `=SUM(A1:A10)`. The compiler thinks `FoldExpr(Range(A1,A10), Add, 0)`.

Design rules:
- Fewer sum types than Phase 1 (container variants resolved)
- All cross-references still as IDs (not yet validated)
- Structure is canonical (one representation, not many)
- No derived values yet (no computed layouts, no coefficients)

```
-- DAW semantic model
Authored.Track = (number id, Graph graph, Param volume, Param pan) unique
Authored.Graph = (Node* nodes, Wire* wires, GraphLayout layout) unique
Authored.Node = (number id, NodeKind kind, Param* params) unique

-- Text editor semantic model
Authored.Document = (Authored.Block* blocks) unique
Authored.Block = Paragraph(TextRun* runs, Alignment align)
               | Heading(TextRun* runs, number level)
               | CodeBlock(string text, string language)

Authored.TextRun = (string text, ResolvedFont font,
                    number size_px, Color color) unique

-- Spreadsheet semantic model
Authored.Sheet = (Authored.Cell* cells) unique
Authored.Cell = (number row, number col, CellExpr expr,
                 CellFormat format) unique
Authored.CellExpr = Literal(CellValue value)
                   | Ref(number row, number col)
                   | RangeRef(number r1, number c1, number r2, number c2)
                   | FuncCall(string name, CellExpr* args)
                   | BinOp(string op, CellExpr lhs, CellExpr rhs)
```

**Phase 3: Resolved.** Cross-references are validated. IDs are stable. Everything that references something else is confirmed to reference a real thing.

This phase exists because validation requires seeing the WHOLE document. Phase 2's transitions are local — they transform one node at a time. Phase 3 is global — it looks at all nodes to validate references.

Design rules:
- All cross-references validated (dangling ref = error with semantic ref)
- IDs assigned/stabilized if not already
- May flatten the tree for random access (all nodes in a list with IDs)
- Fewer sum types (reference resolution might eliminate some)

```
-- DAW resolved
Resolved.Project = (Track* tracks, Node* all_nodes, Wire* all_wires,
                    Param* all_params) unique
-- Flat lists with IDs for random access. Send targets validated.
-- Modulation targets validated. Automation targets validated.

-- Spreadsheet resolved
Resolved.Sheet = (Resolved.Cell* cells,
                  DependencyEdge* edges, number* eval_order) unique
-- Formula references validated. Circular dependencies detected.
-- Topological sort computed for evaluation order.
```

**Phase 4: Classified.** Domain-specific classification. In a DAW: rate classes (sample, block, init, constant). In a layout engine: sizing categories (fixed, flex, intrinsic). In a spreadsheet: cell volatility (static, depends-on-volatile).

This phase exists to assign CATEGORIES that determine how things will be compiled. A constant parameter and a sample-rate parameter produce different code. A fixed-width element and a flex element use different layout algorithms.

Design rules:
- Categories are usually flags or small enums (not large sum types)
- This phase may ADD a classification sum type, but the overall decision surface should still be shrinking
- The classification determines the compilation strategy

```
-- DAW classified
Classified.Param = (number id, number value, RateClass rate,
                    number slot, number state_offset) unique
-- RateClass = Constant | Init | Block | Sample | Event | Voice

-- Layout classified
Classified.Element = (number id, SizeClass width_class,
                      SizeClass height_class, ...) unique
-- SizeClass = Fixed(number px) | Flex(number weight)
--           | Intrinsic(number measured)
-- Note: Intrinsic means text was measured. This is where
-- the text/layout coupling resolves.
```

**Phase 5: Scheduled.** The execution plan. Resources allocated. Order determined. This is the last phase before compilation. Everything is concrete — numbers, indices, offsets.

Design rules:
- ZERO sum types. Everything is a number or a flat record of numbers.
- Buffer slots assigned. State offsets computed.
- Execution order determined (topological sort for graphs).
- This is the input to the terminal boundaries.

```
-- DAW scheduled
Scheduled.Job = (number node_id, number kind_code,
                 number* params, number in_bus, number out_bus,
                 number state_offset, number state_size) unique

-- Layout scheduled
Scheduled.Box = (number id, number x, number y,
                 number w, number h,
                 DrawCmd* commands) unique

-- Spreadsheet scheduled
Scheduled.EvalStep = (number cell_id, number op_code,
                      number* args) unique
```

**Phase 6: Compiled.** Terminal boundaries produce Units. This is not a "phase" in the ASDL sense — there are no ASDL types. The output is `{ fn, state_t }`. The Unit IS the final phase.

#### When to merge phases

Not every domain needs six phases. Merge phases when:
- Two phases would always run together (no independent use of intermediate result)
- The decisions resolved are tightly coupled (splitting them adds complexity)
- The intermediate ASDL would be nearly identical to the input or output

```
Simple app (e.g. calculator):
    Phase 1: Expression tree (source)
    Phase 2: Compiled (terminal)
    Two phases. No intermediate representation needed.

Medium app (e.g. charting library):
    Phase 1: Chart spec (series, axes, labels)
    Phase 2: Laid out (positions computed)
    Phase 3: Compiled (draw calls)
    Three phases. Layout is the only meaningful intermediate.

Complex app (e.g. DAW):
    All six phases. Each resolves distinct knowledge.
```

Rule of thumb: if you can't name the VERB for a phase transition, the phase probably shouldn't exist.

### 5.7 Test the source ASDL

Once the source phase is drafted, test it before writing a single boundary function. These tests catch modeling errors that would compound through every downstream phase.

#### The save/load test

Serialize your source ASDL to JSON (or any format). Load it back. Reconstruct the ASDL. Is every user-visible aspect of the project restored perfectly?

If something is lost — a UI layout preference, a device ordering, a selection state — it means the source ASDL is missing a field. The source phase must capture EVERYTHING the user cares about.

```
FAILS the save/load test:
    The user arranged their mixer channel strips in a custom order.
    The ASDL has no field for strip_order on Track.
    After save/load, the mixer reverts to default order.
    → Add: strip_order: number to Track

    The user collapsed a device panel in the UI.
    The ASDL has no field for collapsed state.
    After save/load, all panels are expanded.
    → Add: collapsed: boolean to Device? Or is this View state,
      not source state? If the user expects it to persist, it's source.
```

Rule: if the user would be surprised or annoyed that something changed after save/load, it belongs in the source ASDL.

#### The undo test

The user performs an edit. Then undoes it. The source ASDL should be identical to the pre-edit state — and because ASDL `unique` gives structural identity, "identical" means the SAME Lua object. Memoize returns the cached compilation instantly. The entire UI and audio state reverts with zero recompilation.

If undo requires special handling — reconstructing state, invalidating caches, re-running computations — the source ASDL is wrong. Undo should be: replace the current ASDL tree with the previous one. That's it. Everything else follows from memoize.

```
FAILS the undo test:
    The user adds an effect. The effect allocates a state buffer.
    Undo removes the effect. But the state buffer must be freed.
    → Wrong: state buffers shouldn't exist outside the compiled Unit.
      The Unit owns its state. Remove the ASDL node, recompile,
      the new Unit has no state for that effect. Old state is GC'd.

    The user changes a parameter. Undo reverts it.
    But the UI shows the old value while the audio plays the new one
    for a moment.
    → Wrong: UI and audio should both derive from the same ASDL.
      Revert the ASDL → recompile both UI and audio → instant.
```

#### The collaboration test

Two users edit the same project simultaneously. They edit different things (different tracks, different parameters). Can their edits be merged?

ASDL trees are VALUES, not mutable objects. Merging two value-trees is a structural operation: for each node, take the newer version. If both users edited the same node, conflict. This works naturally if:

- Each identity noun has a stable ID
- Edits produce new ASDL nodes (structural sharing for unchanged subtrees)
- The merge algorithm walks both trees and picks the non-conflicting updates

If merging requires understanding the semantics of the edit (not just the structure), the source ASDL is too coarse-grained. Each independently editable thing should be its own ASDL node.

#### The completeness test

For each sum type in the source ASDL, ask: "Can the user create an instance of every variant?" If a variant is impossible to reach through the UI, it shouldn't exist. If a user action creates something that doesn't fit any variant, a variant is missing.

```
Device = NativeDevice | LayerDevice | SelectorDevice | SplitDevice | GridDevice

Can the user create each one?
    NativeDevice:   yes, by adding a built-in effect or instrument
    LayerDevice:    yes, by creating a layer container
    SelectorDevice: yes, by creating a selector/switch
    SplitDevice:    yes, by creating a multiband split
    GridDevice:     yes, by creating a modular patch

Is there a user action that creates something else?
    What about an external VST plugin?
    → Need: PluginDevice { id, name, plugin_id, preset, params }
    Or is it a NativeDevice with a special NodeKind?
    → Design decision: is "VST plugin" a device container kind
      or a node processing kind?
```

Every variant must be reachable. Every reachable state must have a variant.

#### The minimality test

For each field on each record, ask: "Is there a user action that changes ONLY this field?" If yes, the field is at the right granularity. If no — if this field always changes together with another field — they might be one field (a record containing both), or one of them might be derived.

```
Track:
    volume_db: number   — user drags fader → changes only this → CORRECT
    pan: number         — user drags pan knob → changes only this → CORRECT
    muted: boolean      — user clicks mute → changes only this → CORRECT

    volume_db AND pan changing together? No, they're independent. CORRECT.

Biquad:
    freq: number        — user turns freq knob → changes only this → CORRECT
    q: number           — user turns Q knob → changes only this → CORRECT

    What about filter coefficients (b0, b1, b2, a1, a2)?
    → These are DERIVED from freq and q. They change whenever
      freq or q changes. They're not source — they're computed
      in the compilation phase. Do NOT put them in the source ASDL.
```

Rule: if a value is derived from other values in the ASDL, it belongs in a later phase, not in the source. The source contains only INDEPENDENT user choices.

#### The orthogonality test

For each pair of fields on a record, ask: "Can these vary independently?" If yes, they're orthogonal — good. If no — if changing one constrains or determines the other — you may have a hidden dependency that should be a sum type or a separate phase.

```
Track:
    volume_db: number and pan: number
    → Can volume be -6dB with pan at center? Yes.
    → Can volume be 0dB with pan hard left? Yes.
    → They vary independently. ORTHOGONAL. Good.

Device:
    kind: NodeKind and params: Param*
    → Can a Biquad have gain params? No — biquad has freq/q.
    → Can a Gain have freq/q params? No — gain has db.
    → They're NOT orthogonal. kind constrains params.
    → This is correct AS LONG AS NodeKind is a sum type where
      each variant declares its own parameter set.
```

When fields are not orthogonal, the constraint should be visible in the types — usually as a sum type where each variant carries only the fields it needs.

#### The testing test

For each function you write, ask: "Can I test this with nothing but an ASDL constructor and an assertion?" If yes, the design is right. If no — if you need mocks, fixtures, setup, teardown, a running server, a database, environment variables, or a specific ordering of prior calls — then the function has hidden dependencies, which means the ASDL is incomplete or the function is impure.

```
The function needs a "context" or "environment" argument:
    resolve_track(track, context)
    → What is "context"? It carries data the track doesn't own.
      That data belongs in a prior phase that put it ON the track.
      After resolution, the track is self-contained.
      The test constructs a track. No context needed.

The function needs to be called in a specific order:
    init_system()
    load_plugins()
    result = process(input)  -- only works after init + load
    → The ordering dependency means hidden state.
      In the pattern, process(input) works on any valid input,
      regardless of what happened before. The ASDL node carries
      everything the function needs.

The function needs a mock:
    process(input, mock_filesystem)
    → The function is reaching outside its arguments.
      The file system data should already be in the ASDL —
      loaded during an earlier phase, stored as values,
      not as live references to external systems.
```

The rule is: **every function is testable with one constructor call and one assertion.** If it needs more, trace the extra dependency back to the ASDL. Either the data is missing (incomplete ASDL), the phases are wrong (unresolved coupling), or the function is impure. The fix is always upstream, never at the test site.

This also means the entire testing infrastructure dissolves:
- **No test framework** — setup/teardown have nothing to set up.
- **No mocks** — pure functions have no external dependencies.
- **No fixtures** — ASDL constructors are self-contained.
- **No regression suite** — memoize is the regression oracle. Same input to changed function: if memoize recomputes, behavior changed.
- **No property testing library** — ASDL types define the space of valid inputs. Random testing is: random ASDL constructor arguments → call function → assert structural properties.
- **No flaky tests** — pure functions produce the same output for the same input. Always.

### 5.8 Design for incrementality

The memoize cache is the incremental compilation system. Its effectiveness depends on how the ASDL is structured.

#### Structural sharing

When the user edits one track, the other tracks are unchanged. If each Track is ASDL `unique`, the unchanged tracks are the SAME Lua objects in the new project as in the old one. The memoize cache hits on them instantly.

This requires that edits produce NEW ASDL nodes with STRUCTURAL SHARING:

```lua
-- User changes Track 2's volume from -6 to -3

-- WRONG (deep copy — destroys memoize):
local new_project = deep_copy(old_project)
new_project.tracks[2].volume_db = -3
-- Every track is a new object. Every memoize lookup misses.
-- The entire pipeline recompiles. No incrementality.

-- RIGHT (structural sharing — preserves memoize):
local new_tracks = {}
for i, track in ipairs(old_project.tracks) do
    if i == 2 then
        -- Construct new Track with changed volume
        new_tracks[i] = T.Editor.Track(
            track.id, track.name, track.devices,
            -3,  -- changed
            track.pan, track.muted
        )
    else
        -- Reuse the same object
        new_tracks[i] = track
    end
end
local new_project = T.Editor.Project(
    old_project.name, new_tracks, old_project.sample_rate
)
-- Track 1 is the SAME object. Memoize hits on it.
-- Track 2 is new. Memoize misses. Only Track 2 recompiles.
```

Or with `U.with`:

```lua
local new_track = U.with(old_track, { volume_db = -3 })
-- Returns a new ASDL node with volume_db changed, all other fields identical.
-- The devices field is the SAME object as old_track.devices.
-- Memoize on devices hits.
```

#### The granularity tradeoff

Finer granularity = more cache hits, but more memoize lookups.
Coarser granularity = fewer lookups, but more cache misses (bigger recompilation units).

```
TOO FINE (per-sample memoize):
    compile_sample = memoize(function(sample_value) ...)
    -- Millions of cache entries. Lookup cost dominates.

TOO COARSE (per-project memoize):
    compile_project = memoize(function(project) ...)
    -- One cache entry. Any edit recompiles everything.

RIGHT (per-node memoize):
    compile_node = memoize(function(node, sr) ...)
    -- One cache entry per node. Edit one node → one recompile.
    -- Typically 50-500 entries. Lookup is O(1) hash.
```

The right granularity is: one memoize boundary per IDENTITY NOUN. Each track, each device, each clip, each parameter is a potential cache boundary. The memoize key is the ASDL `unique` node. An edit to one node misses that node's cache entry. Everything else hits.

#### What makes a good memoize key

The memoize key is the function's argument list. For it to work correctly:

```
GOOD KEYS:
    ASDL unique nodes          → identity comparison, instant
    numbers, strings, booleans → value comparison, instant
    backend-native types       → identity comparison, instant

BAD KEYS:
    Lua tables                 → identity comparison, but tables are mutable!
                                  same table with changed contents → stale cache
    Functions / closures       → identity comparison, but closures close over state
    Anything mutable           → the key can change after caching
```

This is why ASDL `unique` is essential. It guarantees that structurally identical nodes are the SAME object. You don't need deep comparison. You don't need hashing. Identity IS equality. And ASDL nodes are immutable — once constructed, they never change. The cache is always consistent.

### 5.9 Verify parallelism

The ASDL dependency graph IS the execution plan. Multithreading, parallelization, and execution planning are not features you add on top — they are properties you READ from the ASDL structure.

#### The graph encodes the dependencies

An ASDL tree is a DAG of immutable values. Every node knows its children. Every memoized function depends only on its explicit arguments. The dependency structure is fully visible before any compilation happens:

```
        Project
       /       \
    Track1     Track2
    /   \       /   \
  Dev1  Dev2  Dev3  Dev4
  |     |     |     |
 Node1 Node2 Node3 Node4
```

Nodes that don't share ancestors are independent. Track1 and Track2 can compile in parallel. All four leaf nodes can compile in parallel. The graph tells you which work is independent — you don't need to discover it at runtime with a dependency analysis framework.

#### Why this works

The pattern's purity guarantees make parallelism safe by construction:

- **Memoized functions are pure.** They depend only on their explicit arguments. No shared mutable state, no side effects, no ordering requirements.
- **ASDL nodes are immutable.** Once constructed, they never change. Two parallel threads reading the same node see the same value.
- **Memoize handles deduplication.** If two parallel branches reach the same shared subnode, one compiles and caches, the other gets a cache hit.
- **Identity is structural.** ASDL `unique` means the same arguments produce the same object. No race on identity — identity is determined at construction.

Traditional architectures need thread pools, schedulers, synchronization primitives, and dependency graphs as SEPARATE INFRASTRUCTURE because their dependency information is scattered across mutable state, callbacks, and implicit ordering. The pattern concentrates all dependencies in one place — the ASDL tree — and makes them immutable.

#### The modeling consequence

This has a direct consequence for ASDL design: **the granularity of your ASDL nodes determines the granularity of your parallelism.**

```
TOO COARSE:
    Project = (Track* tracks, ...) unique
    compile_project = memoize(function(project) ... end)
    → One node. No parallelism. Everything is sequential.

RIGHT:
    Track = (number id, Device* devices, ...) unique
    compile_track = memoize(function(track, sr) ... end)
    → N tracks. N-way parallelism for independent tracks.
    → Plus M-way parallelism within each track for independent devices.

TOO FINE:
    Sample = (number value) unique
    compile_sample = memoize(function(sample) ... end)
    → Millions of nodes. Parallelism overhead dominates.
```

The same granularity that gives you good incrementality also gives you good parallelism. One memoize boundary per identity noun means one unit of parallelism per identity noun. The design choices compose.

#### What this eliminates

No thread pool. No task queue. No fork-join framework. No dependency graph library. No work-stealing scheduler. No futures or promises for compilation coordination. The ASDL graph is all of these things — it just doesn't know it.

This is the same pattern as every other "eliminated" system: the information already exists in the ASDL structure. Building a separate system to represent it is redundant. Building a separate system to manage it is reconciliation work that shouldn't exist.

### 5.10 Design the view projection

Every program has at least two pipelines from the same source:

```
Source ASDL ──transition──> ... ──terminal──> Execution Unit
             │
             └──projection──> View ASDL ──terminal──> Render Unit
```

The execution pipeline produces the domain output (audio, computed cells, game frame). The view pipeline produces the visual representation (pixels on screen). Both start from the same source ASDL. Both are memoized independently. Editing the source recompiles both — but only the changed subtrees.

View is an important pattern here, but it should not be mistaken for a mandatory top-level filesystem doctrine. Sometimes a project has a substantial explicit View ASDL family. Sometimes the view path is smaller and more local. The architectural point is the projection boundary and the preserved semantic refs, not a required repo taxonomy.

#### The view is NOT the source

The View ASDL is different from the source ASDL. The source represents the user's domain model. The View represents the visual presentation of that model. They are different shapes:

```
Source (DAW):                          View:
    Project                                Shell (title bar, menus)
    ├── Track 1                            ├── Arranger panel
    │   ├── Devices                        │   ├── Track header row
    │   │   ├── Synth                      │   │   ├── Track 1 header
    │   │   └── Filter                     │   │   ├── Track 2 header
    │   └── Clips                          │   │   └── ...
    │       ├── Clip A                     │   └── Clip area
    │       └── Clip B                     │       ├── Clip A rect
    └── Track 2                            │       └── Clip B rect
        └── ...                            ├── Mixer panel
                                           │   ├── Strip 1 (for Track 1)
                                           │   └── Strip 2 (for Track 2)
                                           └── Device panel
                                               ├── Synth UI
                                               └── Filter UI
```

The same Track appears in three places in the View: the track header, the mixer strip, and the device panel. The View is not a mirror of the source — it is a PROJECTION. One source entity can appear multiple times. Some source entities don't appear at all (depending on what's visible). The View adds layout, sizing, colors, labels, and interaction behaviors that don't exist in the source.

#### The view's own phase pipeline

The View has its own phases:

```
View.Decl       the element tree (layout + draw + behavior)
                projection from source ASDL

View.Laid       positions computed (constraints down, sizes up)
                text shaped, measurements known

View.Batched    draw commands sorted for GPU efficiency

View.Compiled   Unit { fn, state_t } — one function, all GL calls
```

The projection boundary (`source → View.Decl`) is a `transition` or `projection` function. The View pipeline from Decl to Compiled is its own sequence of transitions and terminals.

#### The semantic ref connection

Errors from the domain pipeline carry semantic refs (TrackRef, DeviceRef, ClipRef). The View knows which visual elements correspond to which semantic refs (because the projection maintained the mapping). When an error says `DeviceRef(42) failed`, the View finds the visual element for Device 42 and shows the error there.

This works because the source ASDL node identity (the `id` field) flows through both pipelines — through the domain compilation AND through the View projection. The ID is the shared key.

---

## Part 6: Type Design Principles

This section is a reference for ASDL quality. Look things up here when you're unsure about a specific type design decision.

### 6.1 Sum types are domain decisions

Every sum type in the source ASDL represents a decision the user made. "This is an audio clip, not a MIDI clip." "This is a low-pass filter, not a high-pass." "This parameter is automated, not static."

Later phases RESOLVE these decisions. A sum type that exists in phase N and doesn't exist in phase N+1 was consumed by the transition between them. That transition's job was to resolve that specific decision.

```
Editor phase:
    Device = NativeDevice | LayerDevice | SelectorDevice | ...
    (user's decision: what kind of container)

Authored phase:
    Node = (id, kind: NodeKind, params, ...)
    (container decision consumed → everything is a Node in a Graph)
    But NodeKind still has 135 variants — those decisions are consumed LATER

Scheduled phase:
    Job = (node_id, kind_code: number, params: number*)
    (NodeKind decision consumed → just a numeric code + parameter array)
    Zero sum types. Everything is a flat job with numbers.
```

#### Fewer sum types downstream

Each phase should have fewer sum types than the previous phase. This is the NARROWING property. If a phase adds sum types, something is wrong — you're creating decisions instead of consuming them.

The terminal phase has ZERO sum types. Everything is concrete. No branches, no dispatch, no type checks. Just concrete fields and predictable access paths. This is what lets the backend optimize aggressively — whether that is LLVM on Terra or host-JIT specialization and bytecode-template realization on LuaJIT — because there is nothing semantic left to dispatch on.

```
Phase          Sum types          What they represent
──────────     ──────────         ───────────────────
Editor         12 enums           User choices
Authored       8 enums            Container choices resolved
Resolved       5 enums            References resolved
Classified     2 enums            Rates classified
Scheduled      0 enums            Everything is a flat job
Terminal       0 sum types        Everything is native code
```

If a phase has more sum types than the previous one, ask: "What new decision was introduced?" Sometimes it's legitimate — a classification phase might introduce a RateClass enum that didn't exist before. But the total decision surface should still be shrinking.

#### Anti-pattern: strings where enums belong

```
WRONG:
    Node = (number id, string kind, ...)
    -- kind = "biquad" — no exhaustiveness checking,
    -- no variant-specific fields, typos are silent bugs

RIGHT:
    Node = (number id, NodeKind kind, ...)
    NodeKind = Biquad { freq: number, q: number }
             | Gain { db: number }
             | Sine { freq: number }
             | ...
    -- Each variant has its own fields. U.match is exhaustive.
    -- Adding a variant forces all match sites to handle it.
```

Strings are bags. Enums are types. Every string that represents a fixed set of options should be an enum. Every string that represents a fixed set of choices with different fields should be an enum with fields.

### 6.2 Records should be deep modules

Each record should be a "deep module" in the Ousterhout sense — a simple interface hiding significant complexity. The record's fields are the interface. The methods that operate on it are the implementation.

```
SHALLOW (bad — too many fields, too little meaning):
    BiquadNode = (
        number b0, number b1, number b2,
        number a1, number a2,
        number x1, number x2, number y1, number y2,
        number frequency, number q, number gain,
        number sample_rate, number filter_mode
    )

DEEP (good — meaningful fields, complexity hidden):
    BiquadNode = (
        number id,
        FilterMode mode,       -- what the user chose
        number frequency,      -- what the user set
        number q               -- what the user set
    ) unique
    -- Coefficients computed during compilation.
    -- History state owned by the Unit.
    -- Sample rate is an explicit boundary argument.
```

The deep version has 4 fields. The shallow version has 14. The deep version is the source phase — what the user decided. The shallow version mixed source decisions (frequency, q) with derived values (coefficients) and runtime state (x1, y1). These belong in different phases.

#### Anti-pattern: mixing phases

```
WRONG (mixing source and derived):
    Track = (number id, string name, Device* devices,
             number volume_db,
             float* compiled_coefficients,  ← derived! not source!
             BufferSlot output_buffer)      ← scheduled! not source!

RIGHT (source only):
    Editor.Track = (number id, string name, Device* devices,
                    number volume_db) unique
    -- Coefficients are computed in the terminal phase.
    -- Buffer slots are assigned in the Scheduled phase.
```

#### Anti-pattern: modeling the implementation instead of the domain

```
WRONG (implementation model):
    AudioEngine = (BufferPool pool, CallbackFn callback,
                   ThreadHandle thread, MutexHandle lock)

RIGHT (domain model):
    Project = (Track* tracks, Transport transport,
               TempoMap tempo, AssetBank assets)
```

The implementation model describes HOW the program works. The domain model describes WHAT the user works with. The pattern compiles the domain model INTO the implementation. If you put the implementation in the source, you're compiling the compiler.

### 6.3 IDs should be structural, not sequential

Every identity noun needs an ID. The ID should support structural comparison (for ASDL `unique` identity). Two approaches:

**Sequential IDs** (simple but fragile):
```
Track(1, "Lead", ...) unique
Track(2, "Bass", ...) unique
-- What if the user reorders tracks?
-- Track 1 and Track 2 swap positions.
-- The IDs stay the same → the memoize cache is correct.
-- But if IDs were assigned by position, reordering would
-- invalidate the entire cache.
```

**Content-derived IDs** (robust):
```
-- The ID is part of the unique key, but not the position.
-- Moving a track changes its position in the list,
-- but the Track node itself (same ID, same name, same devices)
-- is the same unique object. Memoize hits.
```

Rule: IDs should identify the THING, not its POSITION. Moving things should not change their identity. This maximizes memoize cache hits.

### 6.4 Lists vs. maps

ASDL has `*` for lists. It doesn't have maps/dictionaries. If you need key-value lookup, you have two options:

**List with ID lookup** (standard):
```
Track = (number id, string name, ...) unique
Project = (Track* tracks, ...) unique
-- Look up by: fun.iter(project.tracks):find(function(t) return t.id == id end)
```

**Sorted list** (for ordered data):
```
Breakpoint = (number time, number value) unique
AutomationCurve = (Breakpoint* points, ...) unique
-- Points are sorted by time. Binary search for lookup.
-- Sorted order is an invariant, enforced at construction.
```

Don't use Lua tables as maps in the source ASDL. ASDL nodes are typed records with known fields. A Lua table is an untyped bag. It breaks memoize (table identity is by reference, not by content). It breaks save/load (no schema for the keys). It breaks the type system (no field validation).

If you need associative data, model it as a list of key-value records:

```
Setting = (string key, string value) unique
Settings = (Setting* entries) unique
-- Not: settings: table (which breaks everything)
```

### 6.5 Cross-references are IDs, resolved in a later phase

Sometimes one ASDL node needs to reference another that isn't its child. A Send references a target Track. An automation lane references a Parameter. A wire connects two Ports.

Model these as ID references, not Lua references:

```
WRONG (Lua reference — breaks unique, breaks save/load):
    Send = (Track target, number gain_db)
    -- target is a Lua pointer to another node.
    -- ASDL unique can't hash Lua objects correctly.
    -- Save/load can't serialize Lua pointers.

RIGHT (ID reference — works with unique, save/load, memoize):
    Send = (number target_track_id, number gain_db) unique
    -- target_track_id is a number that references a Track.
    -- ASDL unique hashes it correctly.
    -- Save/load serializes it as a number.
    -- A later phase (Resolved) validates that the ID exists.
```

Cross-references are resolved in a dedicated phase. The source ASDL contains the INTENT ("send to track 5"). The Resolved phase validates it ("track 5 exists and has the right channel count").

### 6.6 Containment anti-patterns

#### Over-flattening

```
WRONG (too flat — loses structure):
    Project = (string* track_names, number* track_volumes,
               string* device_kinds, number* device_params)
    -- How do you know which devices belong to which track?
    -- How do you edit one track without touching others?

RIGHT (structured):
    Project = (Track* tracks) unique
    Track = (number id, string name, Device* devices,
             number volume_db) unique
    -- Each track owns its devices. Editing Track 2 doesn't
    -- touch Track 1's ASDL node. Memoize hits on Track 1.
```

#### Under-flattening

```
WRONG (too nested — redundant wrapping):
    Project = (TrackList tracks)
    TrackList = (TrackListEntry* entries)
    TrackListEntry = (Track track, TrackMetadata metadata)
    TrackMetadata = (number index, boolean visible)
    Track = (number id, ...)

RIGHT (flat enough):
    Project = (Track* tracks) unique
    Track = (number id, string name, boolean visible, ...) unique
    -- If visible is a user decision, it belongs on Track.
    -- If it's a view decision, it belongs in the View ASDL.
```

### 6.7 Missing a phase

Symptom: a boundary function is doing two unrelated things. It resolves cross-references AND assigns buffer slots. It lowers containers AND validates connections.

Fix: split into two phases. Each boundary should do ONE kind of knowledge consumption. If it does two, you're missing a phase between them.

### 6.8 Realization nouns do not belong in the source ASDL

A very common new mistake is to pollute the source language with nouns that only exist because of backend installation.

If the user is authoring a parser grammar, the honest source nouns are things like:
- grammar
- token
- rule
- constructor
- product

Not:
- proto
- chunk name
- bytecode blob
- install mode
- artifact key
- closure cache entry

Those may be excellent **proto nouns** later. They are usually bad **source nouns**.

#### Anti-pattern: source polluted by artifact forms

```asdl
WRONG:
    ParserRule = (
        number id,
        string name,
        Expr expr,
        string emitted_chunk_name,
        string bytecode_blob,
        string install_mode
    ) unique

RIGHT:
    FrontendSource.Rule = (
        number id,
        string name,
        Expr expr,
        Result result
    ) unique
    -- chunk names, bytecode, install mode belong in realization.
```

The test is simple:

> if a field only matters because something will later be emitted, cached, loaded, restored, or installed, it probably does not belong in the source ASDL.

#### Anti-pattern: backend policy encoded as a source-domain sum type

```asdl
WRONG:
    Widget = Button(..., BackendMode mode) | Text(..., BackendMode mode)
    BackendMode = SourceMode | BytecodeMode | ClosureMode

RIGHT:
    Ui.Source.Widget = Button(...) | Text(...)
    -- realization policy is chosen below the machine boundary,
    -- not inside the domain source language.
```

The source language should describe what the user means in the domain. Realization policy should describe how the backend hosts that meaning.

### 6.9 Artifact forms are not source truth

Template definitions, binding payloads, bytecode blobs, loaded artifacts, bundles, and install catalogs are all artifact forms.

They may be:
- important
- explicit
- typed
- cacheable
- worth modeling honestly

But they are still **downstream of source truth**.

#### Anti-pattern: treating bytecode as authored truth

```asdl
WRONG:
    Tool = (
        ScriptSource source,
        string cached_bytecode
    ) unique
    -- which one is the truth when they diverge?

RIGHT:
    ToolSource = (
        ScriptSource source
    ) unique

    ToolRealize.BytecodeArtifact = (
        string key,
        bytes blob
    ) unique
    -- source is source truth; bytecode is installed artifact.
```

If save/load, undo, collaboration, or semantic editing would become ambiguous because an artifact form is mixed into the source record, the design is wrong.

The rule is:

> artifacts may be explicit, but they are never the authored source of truth.

### 6.10 Proto footguns

Proto is powerful because it forces realization specialization. That also means proto has its own failure modes. These should be named explicitly.

#### Footgun 1: inventing a rich proto too early

```asdl
WRONG:
    ProjectProto = (
        TemplateFamily template,
        BindingPlan bindings,
        ArtifactKey key,
        InstallCatalog catalog,
        BytecodeBlob blob,
        SourceKernel src,
        ...
    ) unique
    -- before any leaf has proven these nouns are needed
```

If the honest install story is still just:

```text
machine -> closure -> Unit
```

then a large proto ASDL is premature.

Rule:

> every machine crosses a proto boundary, but not every machine needs a rich proto language.

Start with the thinnest proto that makes installation truthful. Let the leaves force richness upward.

#### Footgun 2: keeping proto generic too long

```lua
WRONG:
install(proto)
    if proto.kind == "closure" then ...
    elseif proto.kind == "template" then ...
    elseif proto.kind == "kernel" then ...
    elseif proto.kind == "catalog" then ...
    ...
```

A proto is supposed to force specialization. If one installer keeps rediscovering what family something “really” is, the proto boundary is still too vague.

Rule:

> proto is where realization stops being generic.

Split unrelated install families. Give them distinct proto variants or distinct phases.

#### Footgun 3: treating proto as source truth

```asdl
WRONG:
    Widget = (number id, string text, Proto proto) unique
```

If save/load, undo, collaboration, or authored editing would become ambiguous when proto changes, then proto has leaked upward.

Rule:

> source says what the user means; proto says how the machine is installed.

Proto belongs below the machine boundary, unless the user is literally authoring install artifacts.

#### Footgun 4: collapsing machine identity, proto identity, and artifact identity

These are often related, but they are not always the same:

- **machine identity** — semantic execution shape
- **proto identity** — realizable/installable family member
- **artifact identity** — concrete installed/restored payload

If these are collapsed casually, caches become confusing and invalidation becomes accidental.

Rule:

> decide explicitly which edits change machine shape, which only change proto binding, and which only change concrete artifact payload.

#### Footgun 5: hidden binding contracts

```lua
WRONG:
local f = load(blob)
debug.setupvalue(f, 1, value_a)
debug.setupvalue(f, 2, value_b)
-- why 1 and 2? what do they mean?
```

If a proto depends on binding order, the binding schema must be explicit.

Rule:

> no magical upvalue slots.

Binding plan means: slot, meaning, source, and expected family.

#### Footgun 6: using source kernels as an escape hatch for unfinished lowering

`load` / `loadstring` are valid proto paths when source kernels are the honest artifact. They are a footgun when they hide unresolved semantics.

Bad sign:
- source generation still branches on broad semantic variants
- the kernel builder rediscovers references that should already be resolved
- huge bespoke strings are assembled because the machine was never narrowed enough

Rule:

> source-kernel proto is valid only when the kernel family is already known.

#### Footgun 7: one proto spanning unrelated host contracts

Audio callback installation, view-frame installation, network handler installation, export artifact packaging — these may all be proto languages, but they are not necessarily one proto family.

If one proto node is trying to describe several unrelated host worlds, the host-contract boundary is too weak.

Rule:

> a proto family should belong to one host contract story.

#### Footgun 8: letting proto do semantic work

Proto should package already-decided structure. It should not:
- rediscover domain meaning
- resolve references that should have been resolved earlier
- interpret wide semantic sums at install time
- act as a second hidden semantic compiler

Rule:

> if proto construction wants to reinterpret the source, the phases above it are wrong.

These are the core proto footguns:
- proto too rich too early
- proto too generic too late
- proto leaked into source truth
- identity layers collapsed carelessly
- binding contracts hidden
- source kernels used as semantic escape hatches
- unrelated host contracts forced into one proto
- proto doing semantic work it should only package

A good proto layer is narrow, explicit, specialized, and downstream of already-decided machine meaning.

---

## Part 7: Implementation

### 7.1 The boundary vocabulary

Every boundary function in the pattern is built from six primitives. That's the complete set.

These primitives belong to the compilation-level authoring language. They are how you WRITE pure structural compiler passes. They should not be mistaken for the final runtime ontology. By the time execution begins, the result of all this structural work should be a machine narrow enough to run without rediscovering semantics.

**`U.match(value, arms)`** — exhaustive dispatch on a sum type. Every variant must have a handler. Missing a variant is a compile-time error (from the ASDL, not the Lua runtime — `U.match` checks exhaustiveness).

**`U.errors()`** — creates an error collector. Returns an object with `:each()`, `:call()`, `:merge()`, and `:get()`.

**`errs:each(items, fn, ref_field)`** — maps a list of children through a function, collects errors from any that fail, substitutes neutral values (silent Units) for failures. This is the workhorse — it does mapping, error handling, and fault isolation in one expression.

**`errs:call(target, fn)`** — transforms a single child through a function, collects errors if it fails. Same as `:each()` but for a single value instead of a list.

**`U.with(node, overrides)`** — creates a new ASDL node with some fields changed, all other fields identical. The unchanged fields are the SAME objects (structural sharing preserved). This is how you build new ASDL nodes in reducers.

**ASDL constructor** — `Phase.TypeName(field1, field2, ...)` — builds the output node for the next phase.

Two memoization wrappers declare the boundary's role in the pipeline:

**`U.transition(name, fn)`** — a memoized phase transition. Takes a node from phase N, returns a node in phase N+1.

**`U.terminal(name, fn)`** — a memoized terminal compilation. Takes a node from the final semantic phase, uses the pure structural authoring vocabulary to define the canonical machine for that node, and returns either:
- that machine,
- a thin proto/install form,
- or a packaged `Unit { fn, state_t }` when the proto boundary is maximally collapsed.

Conceptually, `U.terminal(...)` ends semantic compilation. The returned machine or lowered result then feeds the proto layer rather than forcing installation concerns back upward into the source-domain phases.

That's it. No other primitives are needed. If a boundary function reaches for something outside this set — a `for` loop, a `table.insert`, a mutable accumulator, a context argument, a sibling lookup — the ASDL is wrong.

### 7.2 The two canonical shapes

Every boundary function fits one of two shapes.

#### Shape 1: Record boundary

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

#### Shape 2: Enum boundary

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

Notice that inside each `U.match` arm, the body is just a record boundary again — `errs:each` children, construct output. The two shapes nest: enums dispatch to record-shaped bodies.

If your boundary function doesn't fit either of these shapes, one of these is true:
- The ASDL is missing a field (the leaf needs data that isn't on the node)
- The ASDL is missing a phase (the boundary does two unrelated things)
- The containment hierarchy is wrong (the node needs a sibling's data)
- A sum type is missing (imperative control flow compensates for a missing variant)

### 7.3 The purity test

Every boundary function is a pure structural transform. The quality test:

- **No mutation.** The function never modifies its input. It constructs a new ASDL node.
- **No accumulators.** No `table.insert` into a table defined outside the function. `errs:each` is the accumulator — it's built into the primitive.
- **No context arguments.** The function takes `self` (the ASDL node) and nothing else. If it needs data that isn't on `self`, that data should have been placed there by a prior phase.
- **No sibling lookups.** The function never reaches into a parent or sibling node. If it needs sibling data, a prior phase should have resolved the reference and placed the data on this node.
- **No imperative control flow.** No `break`, no early `return` inside a loop, no `if/else` chains that select behavior based on type — that's what `U.match` is for.

When a boundary resists these constraints, the resistance is diagnostic. It tells you exactly what's wrong with the ASDL and where to fix it:

```
"I need a mutable accumulator"
    → The data isn't self-contained per node. A prior phase should
      make each node independent.

"I need to look up another node by ID"
    → A Resolved phase should have already linked the reference.
      After resolution, the data the node needs is ON the node.

"I need a context argument"
    → The node doesn't carry everything the function needs.
      Either the ASDL is missing a field, or a prior phase should
      have attached the needed data.

"I need if/else to handle different cases"
    → A sum type is missing. The cases should be variants.
      U.match handles them exhaustively.

"I need to break out of a loop"
    → The loop is compensating for heterogeneous data.
      The data should be uniform (same type per list) or
      separated into different lists by a prior phase.
```

### 7.4 Leaves-up discovery: leaf → machine → realization → Unit

The modeling method gives you a first draft of the ASDL. That draft is a hypothesis. Implementation tests it.

The testing direction is bottom-up:

1. imagine the leaf you want
2. make the canonical machine explicit
3. decide whether the proto stays thin or expands into richer structure
4. derive the ASDL above from those constraints

The sequence is not merely:

```text
leaf → Unit
```

The more honest sequence is:

```text
leaf intent → canonical Machine → proto language / realization policy → installed Unit/artifact
```

That sequence should guide implementation.

#### Write the leaf you want to write

Don't start by implementing the full pipeline top-down. Start at the leaf — the smallest function that tells the truth about the machine you wish existed.

After you identify the top-level domain nouns and draft the source ASDL, the next question is not:

> how do I fit this feature into the current runtime architecture?

The next questions are:

> what machine do I wish I could install?
>
> and what is the smallest proto that would install it honestly?

That means imagining the highest-performance stable kernel that would execute this domain well:

- what would the hot path actually do?
- what would `gen` be?
- what stable payload belongs in `param`?
- what mutable payload belongs in `state`?
- what should be baked into code shape?
- what should stay live across calls?
- should the machine walk a tree, a flat plan, an array pack, or a command stream?
- should the proto stay thin as a direct closure/native path, or expand into a structural install artifact like template / bytecode blob / binding plan / source-kernel family?

Only after you can picture that machine should you ask what phase-local data structure would feed it cleanly.

#### The terminal question is really two questions

A healthy terminal design separates two distinct questions:

1. **machine question** — what is the semantic executable abstraction?
2. **proto question** — what is the smallest installable realization unit for that machine on this backend?

Sometimes the proto answer is thin:
- define the machine
- lower to a thin closure/native proto
- install as a Unit

Sometimes the proto answer is rich:
- define the machine
- lower to a proto language or artifact plan
- install that plan as the runtime artifact

Leaf-first work often reveals that the realization side also has its own leaf. After you discover the machine you want, the next bottom-up question is:

> what is the smallest installable thing that would host this machine honestly?

Sometimes the answer is simply a closure. Sometimes it is a template family plus binding schema. Sometimes it is a source-kernel family. Sometimes it is a named installable unit with cache identity and install metadata. When that smallest installable thing has stable structure, it deserves its own realization noun — often a **proto**.

That is why proto-like vocabularies are often discovered from the bottom rather than invented from the top. They are what falls out when a backend/install leaf needs truthful identity and packaging.

If the backend/install story has its own real nouns — artifact family, binding schema, install key, template family, bytecode blob, source-kernel family — then realization probably deserves explicit structure.

When making that move, check the proto footguns in §6.10. In particular: do not inflate proto before the leaf requires it, do not keep proto generic once specialization is honest, and do not let proto construction rediscover semantic meaning.

#### Don’t fix the leaf. Fix the layer above it.

The leaf immediately tells you what its input node must contain.

A sine oscillator leaf needs frequency, waveform shape, gain.
A biquad filter leaf needs pre-computed coefficients.
A text renderer leaf needs resolved font metrics and glyph positions.
A UI kernel leaf may need flat boxes, clip ranges, hit-test regions, and draw commands.
A structural realization leaf may need proto identity, template family, binding schema, shape key, and bytecode blob.

If the terminal input node does not have those fields — if the leaf cannot get what it needs from its single argument — the ASDL is wrong.

Don't fix the leaf. Fix the layer above.

#### Illustration: a UI library designed from the kernel backward

Suppose the source domain for a UI library is something like:

```lua
Ui.Source.Widget
    = Row(number id, Widget* children, Constraint* constraints)
    | Column(number id, Widget* children, Constraint* constraints)
    | Text(number id, string value, StyleRef style, Binding* bindings)
    | Button(number id, Widget label, ActionRef action)
    | Scroll(number id, Widget child, ScrollStateRef scroll)
```

That is the authored tree — the vocabulary the user or library author works with. It is the right source shape because UI is authored hierarchically.

Now stop looking at the source tree and imagine the machine you actually want.

A high-performance UI backend probably does **not** want to traverse that authored tree every frame. It probably wants one stable machine over flat payload:

```lua
terra ui_kernel(plan: &UiPlanState, input: &InputState, out: &GpuBuffer)
    -- walk flat layout boxes
    -- walk clip ranges
    -- walk draw commands
    -- walk hit-test items
    -- no symbolic refs
    -- no tree recursion
    -- no string dispatch
end
```

And its live state probably looks more like this than like the source tree:

```lua
UiPlanState = struct {
    boxes: BoxLayout[N]
    clips: ClipRange[M]
    draws: DrawCmd[K]
    hits: HitRegion[H]
    focus: FocusItem[F]
    scroll_offsets: float[S]
    cached_text_runs: TextRun[T]
}
```

That imagined machine tells you several truths immediately:

1. the kernel does not want symbolic bindings
2. it does not want the authored tree shape
3. it does not want unresolved constraints
4. it wants one stable runner over packed plan data
5. therefore the final semantic phase before terminalization should not be `Widget`; it should be something like `Ui.Plan`

If the backend then emits a tiny Lua kernel rather than going directly to a closure or native function, that is a **realization choice**, not a reason to contaminate the source ASDL with kernel-emission nouns.

So now you can derive the path backward:

```lua
Ui.Source.WidgetTree
    ↓ resolve_bindings
Ui.Resolved.WidgetTree
    ↓ flatten_regions
Ui.Flat.Region*
    ↓ solve_constraints
Ui.Solved.Region*
    ↓ build_plan
Ui.Plan.Scene
    ↓ define_machine
Ui.Machine.Scene
    ↓ realize_luajit | realize_terra
Unit { fn, state_t }
```

If the Lua path needs explicit emitted-artifact structure, it may instead become:

```lua
Ui.Machine.Scene
    ↓ prepare_install
Ui.Realize.Plan
    ↓ install
Unit { fn, state_t }  -- or install catalog wrapping callable artifacts
```

That is still the same architecture. It is just a richer proto layer.

#### What to inspect in the imagined leaf and machine

When you imagine the leaf, inspect these questions explicitly.

**Machine shape**
- Is the hot path one stable loop or many small submachines?
- What is `gen`?
- What belongs in `param`?
- What belongs in `state`?
- Does runtime still dispatch on a sum type that should have been consumed earlier?

**Realization shape**
- Is direct closure/native realization enough?
- Does the backend need explicit artifact families?
- Is there a shape key distinct from artifact key?
- Are binding schemas or install metadata real nouns here?
- Should template families stay fixed while larger payload binds separately?

**Memory shape**
- Does the machine want arrays, trees, command streams, or region-local payload?
- Should the plan be packed by region, z-order, text run, material, or schedule order?

**Boundary shape**
- What is the ideal function or machine signature?
- What is the smallest terminal input node that makes the machine trivial?
- If the proto is rich, what is the smallest proto node that makes installation trivial?

This is what “leaf-first” means in practice:

- not “start with implementation details and retrofit the domain”
- but “after modeling the domain, design the machine you wish you could install, then derive the semantic ASDL and proto layer that make that installation mechanical”

These questions are architectural, not micro-optimization. The goal is not to hand-tune LLVM. The goal is to choose the right machine shape so the phases above it become obvious.

#### Modify the layer above

Once the leaf exists — even as a sketch — move exactly one level up. Ask:

> what must the layer above produce so this leaf is trivial?

If the leaf says, "I need resolved coefficients," then the prior phase must produce a node with resolved coefficients. If the leaf says, "I need a flat constraint region with no symbolic refs," then the prior phase must produce exactly that.

```
leaf:              "I need resolved coefficients"
    ↓
scheduling:        "I need coefficients to schedule — get from classified"
    ↓
classification:    "I need filter type to classify — get from authored"
    ↓
lowering:          "I need filter type in authored — get from source"
    ↓
source ASDL:       add filter_type field to the filter node
```

Or for the UI example:

```
compile_kernel:    "I need packed draw/hit/layout arrays"
    ↓
build_plan:        "I need solved boxes and resolved materials"
    ↓
solve_constraints: "I need flat nodes with explicit edges"
    ↓
flatten_regions:   "I need a resolved tree with validated bindings"
    ↓
resolve_bindings:  "I need explicit IDs/refs in the source tree"
    ↓
source ASDL:       add stable widget IDs, typed bindings, typed constraints
```

This is the recursive process: each layer is shaped by the demands of the layer below it. The source ASDL is the LAST thing that settles, not the first. The modeling method gave you a draft. The leaves correct it.

#### Why this gives the earliest ASDL warnings

The leaf compiler is the smallest function in the system — often 10-20 lines. It is also the most honest function. It has no room to hide a bad ASDL.

```
Missing field           → ASDL is incomplete, add to source and propagate
Purity resistance       → prior phase didn't resolve a coupling
Trivial function        → identity noun is too fine-grained (merge nodes)
Enormous function       → identity noun is too coarse (split the type)
Needs sibling context   → containment hierarchy is wrong
Needs global lookup     → missing resolution phase
Too many tiny calls     → over-lowered fake submachines; use parent state or fusion
Huge flat rebuild       → flattened too early or lost region identity
```

Every one of these is a specific ASDL or phase-design fix, not a code fix. The leaf is the probe. It discovers the model's flaws at the cheapest possible moment — before you've written the transitions, the composition, the event handling.

This is why the kernel sketch matters so much. It exposes whether the bake/live split is wrong:

- if the leaf recompiles for facts that should have stayed live, move them into `state_t`
- if the leaf is shelling out to many tiny children, the terminal shape is wrong
- if the leaf wants flat payload but the prior phase still exposes the authored tree, a flattening phase is missing
- if the leaf still has to resolve names, IDs, bindings, or style inheritance, a resolving phase is missing

The kernel is where optimistic abstraction ends. Either the needed knowledge is there, or it isn't.

### 7.5 The design cycle

Design and implementation are not sequential. They interleave.

```
DESIGN (top-down):
    model the domain
    → draft source ASDL
    → identify coupling points
    → draft phase path

DISCOVERY (bottom-up):
    imagine the installed machine
    → sketch fn + state_t
    → define the terminal input node it wants
    → modify the layer above
    → recurse upward

CONVERGENCE:
    the ASDL stabilizes when leaves stop demanding changes
```

This is why the design method has two directions:

- **top-down** for the user domain
- **bottom-up** for the machine shape

Top-down tells you what the user is editing. Bottom-up tells you what the machine must run. The correct pipeline is the one where these meet cleanly in the middle.

You model a bit (Part 2), sketch a kernel, discover the model is wrong, fix it, sketch the next leaf, discover another missing phase, fix that. The modeling method tells you WHERE to look — which nouns, which phases, which coupling points. The leaves tell you WHAT to put there — which fields, which resolutions, which phase boundaries. Neither works alone. Together, they converge on the correct ASDL: the one where every leaf is a natural pure structural transform, every phase transition has one real verb, and the installed machine is exactly the one you wanted to build.

The convergence criterion is:

**every leaf compiles as a clean structural transform with no reaching, no hidden context, no runtime interpretation of authored structure, and a clear bake/live split between code and `state_t`.**

When that's true, the ASDL is done. When it's not, the resistance tells you exactly what to fix and where.

### 7.6 The memoize-hit-ratio test

Once the pipeline exists, there is an extremely practical design test:

> **What percentage of memoized boundaries hit the cache during realistic edits?**

This is not a backend-speed metric. It is a design-quality metric.

If one small edit causes:

- one or two local misses
- a few expected parent misses
- many sibling hits

then the ASDL decomposition is probably healthy.

If one small edit causes:

- misses across most leaves
- misses across unrelated siblings
- misses at boundaries that should have been unaffected

then the design is telling you something is wrong.

Typical causes include:

- structural sharing is broken (deep copy instead of `U.with`)
- IDs are unstable
- memoize keys include volatile data
- a boundary is too coarse
- a source node is carrying too much unrelated state
- a phase is flattening away locality too early

This is important because it turns architectural quality into an observable quantity.

A high hit ratio means:

- edits are local
- identities are stable
- phases are well scoped
- the ASDL matches the natural incrementality of the domain

A low hit ratio means the opposite.

The especially useful metric is not only the global hit ratio, but **misses per edit**:

- change one biquad frequency → how many boundaries miss?
- mute one track → how many boundaries miss?
- insert one paragraph → how many boundaries miss?

That number is the architectural cost of one user action.

In practice, it helps to give important boundaries explicit names so the inspector report is readable:

- `U.transition("lower_track", fn)`
- `U.terminal("compile_node", fn)`
- `U.memo_measure_edit(...)`
- `U.memo_report()`

So once you have memoize instrumentation, treat the report as a design inspector:

- **90%+ reuse** usually means the decomposition is excellent
- **70–90% reuse** is often healthy but worth inspecting
- **below 50% reuse** usually means the ASDL or phase boundaries are too coarse, structural sharing is broken, or keys are unstable

There is one expected caveat: the root boundary often misses on every edit. That is normal. The real question is whether the leaves and intermediate structural boundaries are reusing their work.

In other words:

> **The cache hit ratio is the design-quality metric for incremental compilation.**

Use it the same way you use the save/load test, the undo test, and the purity test: not as a performance tweak, but as a diagnostic for whether the model and phase boundaries are right.

---

## Part 8: The ASDL Convergence Cycle

The ASDL goes through a predictable lifecycle. It looks alarming in the middle but converges to something surprisingly simple at the end.

### 8.1 The three stages

```
DRAFT        →      EXPANSION        →      COLLAPSE
(too coarse)        (too many types)         (just right)
```

The draft is your first attempt — top-down, based on domain intuition from Part 5. It is always too coarse. The expansion is driven by the profiler — every trace exit, every NYI, every return-to-interpreter demands a new type, a new phase, a new distinction. The collapse is driven by the expanded types themselves — once you can see all the real distinctions, you also see which ones are redundant. The final ASDL is often simpler than the draft.

This is not refactoring. This is convergence. And it is safe at every step because the profiler validates each move.

### 8.2 Stage 1: The draft — too coarse

You model the domain top-down using the method from Part 5. You list the nouns, find the sum types, draw containment, sketch the phases. The draft captures the user's vocabulary faithfully. It passes the save/load test, the undo test, the completeness test.

But it has not yet been tested against the machine. The leaves have not spoken.

A typical draft might have a `Device` with `kind` as a string and `params` as a flat list. This feels clean but hides decisions behind loose bags. The leaves will tell you.

### 8.3 Stage 2: The expansion — driven by the profiler

You implement the leaf terminal (Part 7, leaf-first). You profile it. The profiler speaks:

**"Trace exit on type check."** The leaf branches on `device.kind` — a string. Fix: `kind` should be a sum type. You expand: four variants where there was one string. The type count grows. But now each leaf is monomorphic.

**"NYI: pairs() in hot path."** A leaf iterates over a parameter table. Fix: you need a resolution phase that pre-resolves the references structurally. More types. A whole new phase. But the leaf traces clean.

Each layer you implement adds distinctions. The ASDL grows:

```
Draft:       3 types, 0 enums, 1 phase
Expanded:   14 types, 4 enums, 3 phases
```

This is the scary moment. Don't simplify prematurely. The expansion is not done until every leaf traces clean and every transition compiles without resistance.

### 8.4 Stage 3: The collapse — driven by structural redundancy

Once the expanded ASDL is fully validated — every leaf traces clean, every transition fits the canonical shape, the memoize hit ratio is above 90% — patterns become visible:

**Variants that share structure.** Several device variants all went through the same resolution step: authored parameter → computed coefficient. They collapse into fewer variants with a shared coefficient structure.

**Phases that do the same verb.** Two separate phases both "resolve" — one resolves ID references, the other resolves parameter values. They can be one phase: the verb is the same.

**Fields that belong on a header.** Every scheduled variant carries the same bus/state/channel fields. Those become a shared header. The variant carries only its specific payload.

**Types that were modeling accidents.** Separate `MonoTrack`, `StereoTrack`, `SurroundTrack` types — but the leaves don't care about track type. They care about channel count, which is a number on the header. Three types collapse to one type with a field.

After collapse:

```
Draft:       3 types, 0 enums, 1 phase
Expanded:   14 types, 4 enums, 3 phases
Collapsed:   8 types, 3 enums, 2 phases
```

### 8.5 Why you can't regress

In a conventional codebase, simplification is dangerous. In this workflow, regression is structurally impossible at each step.

**During expansion:** every new type was demanded by a leaf that couldn't trace clean. If you remove the type, the trace breaks again. You can verify this instantly.

**During collapse:** every merge is validated by the profiler. Merge two types. Re-run the leaf. Does it still trace clean? Yes → the merge was correct. No → the distinction was real, undo the merge.

**The memoize cache is the regression oracle.** If the memoize report shows degraded hit ratios after a change, the change broke structural sharing.

**`U.inspect()` catches missing boundaries.** After any ASDL change, the inspect system tells you which boundaries are stubs.

### 8.6 The deeper reason

The domain is simpler than your first model of it. The draft over-models because you don't yet know which distinctions the machine actually cares about. You model what the user sees — shaped by UI conventions and jargon, not by computational structure.

The expansion discovers the real distinctions — the ones the machine needs. The collapse removes the accidents — the ones that existed because you were thinking in UI categories rather than machine categories.

The final ASDL captures exactly the domain's real structure:
- every distinction that makes a leaf trace differently is a type
- every distinction that doesn't is a field value
- every phase consumes exactly one kind of knowledge
- the terminal input is exactly what the machine needs, nothing more

### 8.7 Practical signs

**Signs you're still in expansion:**
- leaves resist the canonical shape — they need data that isn't on their input
- trace exits and NYI in profiled leaves
- transitions doing two unrelated things (missing phase)
- `U.match` arms that are nearly identical (missing shared structure)
- boundary functions longer than 30 lines
- memoize hit ratios below 70%

**Signs you're ready for collapse:**
- all leaves trace clean
- all transitions fit the canonical record/enum shape
- memoize hit ratios above 90%
- structural similarity between types that were added separately
- two phases have the same verb
- the same fields appear on multiple variant types
- some types exist only because of UI naming, not machine need
- terminals that receive identical concrete fields for different source variants reveal redundant distinctions

**Signs the collapse is done:**
- further merges cause trace regressions (the remaining distinctions are real)
- `U.inspect()` shows clean coverage
- the type count is stable across several feature additions
- new features are additive — a new variant and a new terminal, nothing else changes

### 8.8 The convergence criterion

The ASDL has converged when:

> every leaf is a clean structural transform with no reaching, the profiler shows clean traces top to bottom, the memoize report shows 90%+ reuse, and the most recent feature additions were purely additive — one new variant, one new terminal, zero changes to existing phases.

At that point, the ASDL is the architecture, and the architecture is done. New features flow through it. They don't reshape it.

---

## Part 9: The Backend-Neutral Architecture and Realization Policy

### 9.1 The pattern is not Terra

This architecture was historically called the Terra Compiler Pattern because Terra was the environment in which it first became unmistakably visible. Terra made the compiler-like nature hard to miss: you could literally build code as code, synthesize native state layouts, and hand the result to LLVM.

But the deeper discovery is: **the pattern is not fundamentally about Terra.**

The pattern is: the user edits a program in a domain language, that program is represented as source ASDL, input is represented as Event ASDL, state changes are modeled by a pure Apply reducer, unresolved knowledge is consumed across real phases, lower phases become machine-feeding structures, terminals define canonical machines, realization turns those machines into installable artifacts, and execution runs the installed result until the source changes again.

None of that requires Terra specifically. Terra is one realization style — a very strong one — but still just one backend story.

Terra revealed the pattern. It did not define it.

### 9.2 The three-layer architecture, with realization explicit

The architecture still has three layers, but the lower boundary must now be read more precisely.

```
┌─────────────────────────────────────────────────────────────┐
│                         YOUR DOMAIN                        │
│                                                             │
│  source ASDL, Event ASDL, Apply, phase structure,           │
│  projections, Machine IR, terminal intent,                  │
│  domain semantics                                           │
│                                                             │
│  This is your application.                                  │
├─────────────────────────────────────────────────────────────┤
│                         THE PATTERN                         │
│                                                             │
│  transitions, terminal, memoize, match, with, errors,      │
│  Machine IR, canonical Machine (gen/param/state),          │
│  realization-aware terminal reasoning, inspect              │
│                                                             │
│  This is the compiler architecture vocabulary               │
│  used to express the app.                                   │
├─────────────────────────────────────────────────────────────┤
│                    THE REALIZATION / BACKEND                │
│                                                             │
│  direct closure/native realization, structural realization  │
│  frameworks, template/blob/bind paths, artifact families,   │
│  install                                                    │
│  catalogs, state layout, composition, hot swap, drivers,    │
│  host compiler/JIT                                           │
│                                                             │
│  This is target-specific.                                   │
└─────────────────────────────────────────────────────────────┘
```

**Layer 1: Domain** — The application's semantic content. Source ASDL, Event ASDL, Apply, real phases, projections, Machine IRs, terminal inputs. This is where questions like “what is a track?” and “what should save/load preserve?” live. This layer is not backend-specific.

**Layer 2: Pattern** — The reusable compiler vocabulary. Transition, terminal, Machine IR thinking, canonical `gen/param/state` machine thinking, memoize, match, with, errors, inspect. This layer is not the app's semantics, but it gives the app a disciplined way to express them.

**Layer 3: Realization / Backend** — How a machine becomes executable on this target. How runtime state is represented. What the proto language looks like on this backend — thin direct-install forms or richer artifact families. How artifacts are installed and swapped. How external drivers are called. This is where Terra, LuaJIT, source-kernel paths, bytecode-template paths, install catalogs, and other backend stories differ.

A practical way to remember it is:

> the domain says what should exist;
> the pattern says how to compile it;
> the realization/backend layer says how that machine lives on this target.

### 9.3 What should be shared across backends

For a well-factored app, the following should be shared:

- the source ASDL
- the Event ASDL
- the Apply reducer
- phase boundaries and their semantic meaning
- view projection logic
- Machine IR design
- terminal intent and terminal input design
- structural helper logic
- pure-layer tests

In many cases, even the **realization intent** should be shared:
- whether the proto language is thin or rich
- what the realizable unit is
- what shape identity versus artifact identity means
- what should be baked versus bound

If changing backends requires changing large parts of this core, target concerns leaked too far upward.

### 9.4 What should vary across backends

The following may legitimately vary:

- the exact representation of `Unit`
- the exact representation of `state_t`
- the exact representation of installed artifacts
- how thin or rich the proto language is on this backend
- the exact leaf code shape
- the backend realization policy (direct closure, specialized closure, template/blob/bind path, native path, artifact catalog)
- installation and hot-swap mechanics
- driver integration
- the host compiler or JIT relied upon

The key discipline is:

> backend variation should change realization policy, not source truth.

### 9.5 Proto languages are first-class backend design

Every machine goes through a proto boundary before it becomes an installed runtime form.

Sometimes the proto language is thin.

Examples:
- a Terra machine lowered through a thin native proto with native function + native state layout
- a small LuaJIT machine lowered through a thin direct-closure proto

Other backend stories need a richer proto language.

A richer proto language becomes appropriate when the backend has real nouns such as:
- artifact family
- template family
- binding schema
- bytecode blob
- install catalog
- shape key
- artifact key
- upvalue slot order
- install metadata

When those nouns are real, it is a design improvement to model them honestly rather than hiding them inside ad hoc backend helpers.

This is not an extra architecture layered on top of the pattern. It is the explicit lower realization half of the pattern.

A useful formulation is:

> every backend has a proto language; some keep it thin, others expand it into a richer structural artifact language.

Both are normal.

### 9.6 Backend policy: LuaJIT by default, Terra by opt-in

This reframing still leads to a practical policy:

> **LuaJIT by default. Terra by opt-in.**

That is not a demotion of Terra. It is a clarification of roles.

LuaJIT should be the default backend on JIT-native platforms because:

- the host runtime already provides much of the final compiler
- terminal and realization construction are extremely cheap compared to LLVM
- deployment is lighter, iteration is faster
- scalar steady-state performance is highly competitive
- the same architecture applies cleanly

But LuaJIT is **not** the permissive dynamic-tables backend. The backend contract is still strict. Pure phases remain typed ASDL + pure structural transforms. Terminal leaves must lower to monomorphic LuaJIT code over typed FFI/cdata-backed layouts or through realization artifacts whose semantics have already been resolved upstream.

A healthy LuaJIT backend usually has a realization ladder:

1. **direct closure** when installation is simple and closure capture is already the honest binding form
2. **specialized direct closure** for the common hot case when direct specialization is still enough
3. **template → bytecode blob → load + bind** as the default explicit structural realization path when artifact identity, binding schema, or install caching deserve their own layer
4. **source kernel via `load` / `loadstring`** when exact LuaJIT trace shape, unrolling, or authored low-level execution structure is itself the honest realization artifact
5. **explicit install/artifact framework** when the backend really needs named catalogs, install keys, multiple artifact families, or richer realization structure

These are backend realization choices for the same canonical machine. They are not five different architectures.

So the practical rule is: closures are the default **direct** Lua realization path; template → blob → bind is the default **explicit structural** Lua realization path; source kernels via `load` / `loadstring` are the deliberate **manual code-shape** Lua realization path. Author templates as real Lua when structure should be restored and rebound; use source kernels when exact trace-shaped code is the point.

### 9.7 Structural Lua realization policy

When Lua realization is explicit rather than direct, the key rule is simple:

> **lower hard, then choose the honest explicit artifact form: template/blob/bind or source kernel.**

That means:

- author templates as real Lua functions when execution shape should be restored from bytecode
- use source kernels when exact trace-friendly LuaJIT code shape is itself the artifact being installed
- choose either form only from already-lowered machine plans
- use `string.dump` to make bytecode the normal artifact form for template-based realization
- use `load(blob)` to restore template execution shape at installation time
- use an explicit binding schema plus `debug.setupvalue` to inject compiled payload in bytecode-binding paths
- separate template or kernel-family identity from artifact identity when install caching matters
- bind larger data instead of constantly re-emitting shape when the bytecode-template path is used
- cache by machine shape when possible and by concrete artifact identity when necessary

If the Lua installer is still doing semantic work, the phase above it is wrong. A good Lua proto layer should mostly choose among fixed templates or known source-kernel families, restore or load artifacts, apply explicit bindings where needed, and install already-decided control structure.

If bytecode installation depends on fragile unnamed upvalues, the realization model is still too implicit. If source generation is rediscovering semantics instead of expressing a known low-level kernel family, the backend policy is wrong even if the code still runs fast.

### 9.8 What makes Terra special

Terra becomes the opt-in strong backend when you need what only Terra gives clearly and reliably:

**Explicit staging.** In Terra, the separation between compiler-side logic, generated code, realization, and runtime execution is concrete and programmable.

**Static native types.** A Terra machine or Unit can own a native function with a concrete signature and an exact native state layout.

**Struct synthesis in compose.** Because child state layouts are native types, composition can synthesize larger native state layouts structurally.

**ABI control.** When the integration boundary demands a specific calling convention or data layout, Terra provides it directly.

**LLVM optimization.** Constants baked into code, dead code elimination, instruction selection, vectorization potential — LLVM continues simplifying from where the terminal and realization stages leave off.

### 9.9 Terra as design pressure

One subtle but important point: Terra matters for more than raw speed.

Terra also acts as design pressure. Because it forces explicitness in type layout, staging boundaries, realization boundaries, state ownership, machine shape, and compilation granularity, it often reveals missing phases, vague source models, coarse recompilation boundaries, and unclear authored/runtime splits.

A good mental model is:

> design with Terra-level explicitness in mind, even when LuaJIT is the default realization backend.

Once the LuaJIT backend is constrained correctly, a second statement also becomes true:

> strict LuaJIT — whether realized as specialized closures, bytecode-template artifacts, or explicit install catalogs — can impose almost the same architectural pressure, because the machine and proto layers still have to end in a narrow installed runtime form.

The difference is that Terra provides stronger mechanical enforcement through explicit native staging, while LuaJIT provides the same pressure only if the backend rules are kept strict.

### 9.10 When to opt into Terra

Terra is especially worthwhile when:
- explicit staging control matters more than build speed
- exact struct layout and ABI compatibility are required
- LLVM can materially outperform the host JIT for this machine family
- the workload is heavy enough that LLVM compile cost is repaid by runtime throughput
- native interop requires direct low-level expression

### 9.11 A practical policy

1. Design the domain backend-neutrally
2. Design leaves with Terra-level explicitness in mind
3. Make the canonical machine explicit
4. Decide whether the proto stays thin or deserves richer structure
5. Implement the shared pure layer once
6. Target LuaJIT first on JIT-native platforms when iteration cost matters
7. Benchmark important machine and realization families separately
8. Opt into Terra where explicit native power buys enough

A stronger restatement is:

> backend-neutral architecture means source language, phase meaning, and machine design stay stable while realization policy varies below them.

---

## Part 10: Performance Model

### 10.1 Performance has three costs, not one

Because this architecture is built around a live compile loop, performance must be understood across **three** costs:

1. **semantic rebuild cost** — the cost of recomputing source-driven meaning
2. **realization cost** — the cost of turning machine meaning into installed artifacts
3. **runtime cost** — the cost of executing the installed result

That is the modern performance model of the pattern.

The old two-way split of “rebuild cost” and “run cost” was helpful, but too coarse now that realization is explicit. In many systems the dominant question is not just:

- how expensive is recompilation?
- how fast is execution?

but also:

- how expensive is realization and installation for this backend policy?

A backend may have:
- cheap semantic compilation but expensive realization
- cheap realization but expensive runtime
- excellent runtime but too much install cost for interactive edits

You need to see all three.

### 10.2 The first performance question is architectural

In this pattern, the first useful performance question is often not:

> what function is hot?

but rather:

> why did this change require this amount of semantic recomputation, realization work, and installation work?

That question immediately points toward architecture:

- Did Apply fail to preserve structural sharing?
- Are identity boundaries too coarse?
- Is source containment too broad?
- Is a transition doing too much work over too much structure?
- Is a terminal compiling too large a region at once?
- Did a later phase flatten away locality too early?
- Did realization become too bespoke per tiny change?
- Is the install boundary too coarse?

These are architectural issues, not micro-optimization issues. Performance debugging often becomes a question about model boundaries, phase clarity, machine shape, and realization policy rather than about scattered runtime heuristics.

### 10.3 Semantic rebuild cost

Semantic rebuild cost is paid when the source program changes and the compiler must re-derive meaning.

It includes:

- reducer work
- structural allocation of changed nodes
- transition recomputation
- Machine IR recomputation
- terminal / machine recomputation

In interactive systems, this cost is part of the user experience. Every keystroke, parameter tweak, node move, rule edit, or drag may trigger semantic rebuild work. This affects responsiveness, live feel, and confidence that the system is truly incremental.

The right question here is:

> how much semantic work did this edit force, and why?

If a tiny local edit causes broad semantic misses, the source ASDL, phase boundaries, or structural sharing rules are wrong.

### 10.4 Realization cost

Realization cost is the cost of taking already-derived machine meaning and turning it into installable backend artifacts.

It may include:

- machine → direct-closure realization
- template selection
- bytecode generation or restoration
- artifact planning
- installation metadata assembly
- binding schema / binding payload assembly
- `load(blob)` / `debug.setupvalue` / native compile overhead
- artifact cache lookup or population
- hot-swap / install work

This cost is often paid on every meaningful semantic miss, but it is conceptually distinct from semantic rebuilding.

That distinction matters because realization cost is controlled by different design choices:

- whether the proto language is thin or rich
- how large the realizable unit is
- whether shape identity is separated from artifact identity
- whether template families stay small, regular, and reusable
- how much payload is inlined versus bound
- how much install work is repeated unnecessarily

A good proto framework can reduce both latency and conceptual mess by making artifact work explicit and cacheable.

### 10.5 Runtime cost

Runtime cost is the cost of executing the installed machine or artifact:
- callback throughput
- draw loop throughput
- parser throughput
- state access cost
- arithmetic cost
- memory locality in the hot path
- branch predictability / trace friendliness / machine-code quality

If the installed machine is too slow, the architecture still fails. Audio callbacks, 60fps rendering, low-latency simulation, or high-volume parsing all impose real runtime constraints.

### 10.6 Why the three costs trade off

These three costs interact.

Examples:

- A backend that produces brilliant native code may have excellent runtime cost but poor realization cost.
- A tiny direct closure realization may have excellent realization cost but weaker runtime cost for certain machine families.
- A bytecode-artifact framework may improve runtime cost and install reuse while increasing one-time realization complexity.
- Over-specializing template families or binding too much shape into the artifact may improve runtime but hurt realization reuse and inflate install cost.

So performance work is usually not “make one number smaller.” It is:

> choose the right tradeoff between semantic rebuild, realization, and runtime for the actual edit/run profile of the system.

### 10.7 The bake / bind / live split

One of the most useful lower-boundary performance questions is now:

> what should shape `gen`, what should remain stable in `param`, what should remain mutable in `state`, and what should be carried as realization artifact payload rather than repeatedly emitted?

A good lower split is no longer only bake/live. It is:

- **bake into the machine**
- **bind as stable machine/realization payload**
- **keep live in state**

**Bake into the machine when:**
- the fact is compile-time-known for the subtree
- removing the variability simplifies control flow materially
- specialization will help
- it removes repeated branching in the hot path

Examples:
- fixed operator kind
- fixed blend mode
- known channel count
- known parser branch shape
- resolved filter topology

**Bind as stable payload when:**
- the data is stable for this machine/artifact instance
- it is too large or too variable to inline repeatedly
- shape reuse matters more than embedding every constant
- realization artifacts should stay small and regular

Examples:
- larger tables
- constructor refs
- first-set data
- binding payloads
- install metadata
- shared helper references

**Keep live in state when:**
- the value is execution-time mutable
- it changes frequently without requiring semantic recompilation
- the machine genuinely needs runtime ownership of it
- rebuilding for every tiny change would be the wrong tradeoff

Examples:
- filter delay history
- counters
- mutable buffers
- smoothing state
- backend-owned handles
- scrolling offsets
- simulation accumulators

The right bake / bind / live split often determines whether a system feels compiled or still half interpreted.

### 10.8 Narrowing sum types early helps all three costs

A wide sum type reaching too far downward hurts:

- **semantic rebuild cost** because terminals and proto layers become more complex
- **realization cost** because artifact generation must still interpret broad authored structure
- **runtime cost** because the machine keeps branching on semantic alternatives

That is why later semantic phases should narrow rather than widen. A good terminal input should be much more monomorphic than the authored source, and a good proto layer should receive already-decided structure rather than rediscovering meaning.

### 10.9 Locality is performance

If source modeling, phases, machine design, and realization boundaries preserve locality well, then:
- small edits change small subtrees
- semantic rebuild stays local
- realization work stays local
- artifact caches stay useful
- runtime installation work stays smaller

If locality is poor, performance suffers before any low-level arithmetic question even arises.

This is why stable IDs, honest containment, structural sharing, truthful memo boundaries, and sensible realizable-unit boundaries are central to the architecture's performance story.

### 10.10 Semantic reuse and realization reuse are separate metrics

There are at least two reuse questions worth measuring:

1. **semantic memo reuse** — how often transitions and terminals hit the cache
2. **realization reuse** — how often machine shape, artifact shape, or install artifacts are reused

A system can have good semantic reuse but poor realization reuse if:
- shape keys are unstable
- emitted code inlines too much volatile payload
- install keys are too specific
- realization boundaries are too coarse or too fine

Likewise, a system can have decent realization reuse but poor semantic reuse if the source ASDL or phase design is wrong.

So when measuring incrementality, ask both:
- how many semantic boundaries missed?
- how many realization boundaries or artifact constructions missed?

### 10.11 The memoize-hit-ratio test

There is a highly practical metric that sits between modeling and performance:

> **the memoize hit ratio at real semantic stage boundaries**

This metric measures the architecture more directly than raw throughput does. If one small edit causes a few local misses and many sibling hits, the decomposition is healthy. If one small edit causes misses across unrelated leaves and widespread recompilation, the ASDL or phase boundaries are wrong.

Instrumentation through `U.memo_report()`, `U.memo_measure_edit()`, and `U.memo_quality()` makes this observable. The hit ratio is the design-quality metric for incremental semantic compilation.

- **90%+ reuse** — decomposition is excellent
- **70–90% reuse** — healthy but worth inspecting
- **below 50% reuse** — the ASDL or phase boundaries are too coarse, structural sharing is broken, or keys are unstable

But now add a second practical question:

> after the semantic misses, how much realization work was actually repeated?

That is often the difference between a merely correct system and a truly interactive one.

### 10.12 The recursive benchmarking law

Once one lower layer is trusted, the next slow boundary points upward.

- If runtime is slow, inspect machine shape.
- If realization is slow, inspect artifact shape and install policy.
- If semantic rebuild is slow, inspect source modeling and phase design.

The biggest wins often come first from:
- better source modeling
- better identity boundaries
- narrower phases
- cleaner machine inputs
- better realizable-unit boundaries
- better bake / bind / live decisions

Only after those are right do low-level backend optimizations pay their full value.

A poor source model can waste more performance than a clever arithmetic trick can recover. A missing phase can cost more than a backend micro-optimization can save. A bad realization boundary can dominate interactivity even if the final machine runs fast.

### 10.13 Backend-specific performance questions

**Semantic-layer questions:**
- Did this edit preserve structural sharing?
- Are phase boundaries scoped correctly?
- Is Machine IR too broad or too bespoke?
- Are sum types consumed early enough?

**LuaJIT / Lua realization questions:**
- Are specialized closures monomorphic enough to trace well?
- If emitting Lua, is the generated source tiny, regular, and reused by shape?
- Are emit time, load time, and run time measured separately?
- Are important constants bound instead of bloating source?
- Is state access stable and cheap via FFI?
- Are artifact keys and shape keys truthful?
- Is install work repeated unnecessarily?

**Terra questions:**
- Are we staging the right facts into emitted code?
- Is the native state layout as explicit and local as it should be?
- Are we paying LLVM cost at the right granularity?
- Is the compile tax worthwhile with sufficient steady-state benefit?

Different backends, same architectural frame.

### 10.14 The practical rule

A good performance diagnosis in this pattern usually asks, in order:

1. is the source/phase design forcing too much semantic rebuild?
2. is the realization policy forcing too much artifact work?
3. is the installed machine too slow at runtime?

That order matters.

If you reverse it, you may spend a long time optimizing a hot path whose real problem was a bad ASDL, a missing phase, or an over-bespoke realization strategy.

---

## Part 11: What the Pattern Eliminates

The pattern does not eliminate complexity by pretending complex programs are simple. It eliminates infrastructure by removing the architectural conditions that made so much coordinating machinery necessary in the first place.

In many conventional designs, a large amount of system complexity exists because the architecture has multiple overlapping partial truths:
- a runtime object graph
- a store or model layer
- a rendering layer with its own derived structures
- caches remembering what changed
- invalidation rules tracking who depends on whom
- installer logic with its own hidden artifact model
- controller/service logic that reinterprets the same domain repeatedly

When those partial truths drift, the system needs more machinery to reconcile them.

The compiler pattern reduces that need because the source program is explicit, interaction is explicit, phase boundaries are explicit, machine meaning is explicit, realization is explicit where needed, installed artifacts are explicit, state ownership is explicit, and recompilation is driven structurally rather than by ad hoc invalidation protocols.

### 11.1 State management frameworks

Centralized stores that become shadow architectures, action/effect plumbing, observer-heavy propagation systems, elaborate consistency protocols between multiple runtime models.

In the compiler pattern, the source ASDL is the authored program, Apply computes the next source ASDL, later phases derive what should run, and realization installs the resulting artifacts. The state is no longer architecturally mysterious. You do not need meta-infrastructure just to answer:

> what is the application right now?

### 11.2 Invalidation frameworks

Complex machinery to track what changed, what needs recomputation, what caches must be repaired.

In this pattern, structural identity plus memoized boundaries handle it: unchanged nodes hit the cache, changed nodes miss it. Incrementality is not a second architecture bolted onto the first one.

### 11.3 Observer buses and event-dispatch webs

Listeners, subscriptions, bubbling systems, change-notification graphs.

Much of this becomes unnecessary when inputs are modeled as Event ASDL, Apply is the explicit state transition, and later phases rederive consequences structurally. Instead of “notify everyone who might care and let them each mutate their corner,” the story is:
- represent what happened explicitly
- compute the next program
- recompile the consequences
- re-realize only the affected artifacts

### 11.4 Dependency-injection containers and service-locator architecture

Global service access accumulates because key functions cannot get the information they need structurally from their inputs. Service containers, DI graphs, registries passed everywhere, context objects threaded through all operations.

These are often symptoms that the source model, phase structure, or realization boundary is underspecified:
- missing source fields
- missing resolution phases
- hidden cross-references
- hidden install dependencies

The better fix is architectural, not infrastructural.

### 11.5 Hand-built runtime interpretation layers

Perhaps the biggest elimination: the accidental interpreter itself.

Examples:
- dynamic dispatch tables over variants
- generic node walkers asking “what are you?” repeatedly
- runtime graph traversals rediscovering semantic facts
- renderer-style command systems that are really uncompiled authored trees
- callback routers deciding domain behavior on the fly

The compiler pattern consumes that uncertainty earlier. By the time execution runs, those questions should already have been answered.

### 11.6 Accidental realization interpreters

There is now a second version of the same mistake lower down.

Even if source semantics were compiled correctly, the backend can regress by turning realization into another hidden interpreter.

Examples:
- generic installer bags that rediscover artifact meaning dynamically
- emitted-source builders that still branch on broad semantic variants
- install-time string routers deciding what machine shape something “really” is
- bytecode/source/closure logic scattered across ad hoc conditionals instead of one explicit proto layer
- artifact payloads that are opaque bags because no honest proto nouns were modeled

This is the **accidental realization interpreter**.

The fix is the same kind of fix as for accidental runtime interpreters:
- define the missing proto nouns
- make artifact identity explicit
- lower semantics earlier
- keep realization structural and regular

### 11.7 Ad hoc artifact caches and installer glue

Without an explicit realization model, systems often grow:
- hand-rolled code caches
- one-off bytecode registries
- installer maps keyed by mysterious strings
- closure caches with unclear invalidation rules
- hidden load/bind helpers spread across the codebase

These are often symptoms that artifact identity, shape identity, or install boundaries were real architectural concerns but were never modeled honestly.

A proto framework eliminates much of this glue by making those concerns explicit:
- shape key
- artifact key
- install mode
- binding schema / binding payload
- install catalog
- reusable template/blob families

### 11.8 Redundant test scaffolding

Mocks for services, fake runtime environments, setup frameworks, elaborate fixtures standing in for global state.

In the pure layer, tests reduce to: construct ASDL input, call function, assert output.

In the proto layer, tests can often reduce to: construct machine or proto input, lower/install it, assert artifact form or callable behavior.

When such tests become difficult, something hidden is leaking into the supposedly explicit architecture.

### 11.9 Redundant runtime ownership machinery

External state registries, independent lifecycle managers for compiled children, detached runtime objects mirroring compiled structure.

Because Units pair behavior with owned runtime state, and because realization can make installation and artifact ownership explicit, lifecycle concerns are more often represented structurally rather than by a second shadow architecture.

### 11.10 The general principle

> The pattern eliminates glue whose only job was to reconnect truths that should never have been split apart.

If authored truth and semantic truth are explicitly connected by transitions, less glue.
If machine meaning and installation are explicitly connected by realization, less glue.
If compiled behavior and state ownership are one Unit, less glue.
If change propagation is handled by identity plus memoization, less glue.
If interaction is an explicit Event language, less glue.

### 11.11 What does not disappear

The pattern does not eliminate:
- the need for careful domain modeling
- backend engineering
- realization design
- integration with drivers / OS / graphics / audio
- operational error handling
- performance work
- judgment about phase design, realization boundaries, and Unit granularity

It moves complexity to places where it is more explicit, more local, and more meaningful.

### 11.12 A warning against reintroducing the eliminated machinery

Once the pattern starts simplifying a codebase, there is a temptation to reintroduce the old furniture by habit:
- adding a state manager where the source ASDL should suffice
- adding an observer bus where Event ASDL + Apply should suffice
- adding invalidation flags where identity + memoize should suffice
- adding a service container where a resolution phase should suffice
- adding runtime registries where Unit composition should suffice
- adding ad hoc installer caches where proto nouns should suffice
- adding hidden backend glue where an explicit proto layer should exist

Sometimes these tools are genuinely needed at specific backend boundaries. But they should be treated as exceptions that require justification, not as default architecture.

---

## Part 12: Worked Examples

### 12.1 Text editor

**Nouns**: document, paragraph, heading, list, code block, text run, character, cursor, selection, font, style, image, link

**Identity nouns**: document, block (paragraph/heading/etc.), image, link
**Properties**: font, size, weight, color, alignment, indentation

**Sum types**:
```
Block = Paragraph | Heading | CodeBlock | List | Image | HorizontalRule
Span = Plain | Bold | Italic | Code | Link | Strikethrough
Selection = Collapsed(cursor) | Range(anchor, focus)
EditOp = Insert | Delete | Replace | Format | Split | Merge
```

**Phases**:
```
Editor:     Block* with Span* — user vocabulary
Authored:   TextRun* with resolved fonts, resolved links
Laid:       PositionedLine* with x,y,w,h — layout done
Compiled:   Unit that renders to GPU
```

**Coupling point**: text shaping needs available width (from layout). Layout needs text height (from shaping). They happen in the SAME phase (Laid).

**Source ASDL**:
```
module Editor {
    Document = (Block* blocks, Cursor cursor,
                Selection? selection) unique
    Block = Paragraph(Span* spans, Alignment align)
          | Heading(Span* spans, number level)
          | CodeBlock(string text, string language)
          | List(ListKind kind, ListItem* items)
          | Image(number asset_id, string? caption)
          | HorizontalRule()
    Span = Plain(string text)
         | Styled(string text, Style style)
         | Link(string text, string url)
         | Code(string text)
    Style = (boolean bold, boolean italic, boolean strikethrough,
             string? font_override, number? size_override,
             Color? color_override)
    ListKind = Ordered | Unordered
    ListItem = (Block* content) unique
    Cursor = (number block_idx, number offset)
    Selection = Collapsed(Cursor cursor)
              | Range(Cursor anchor, Cursor focus)
    Alignment = Left | Center | Right | Justify
}
```

**Quality tests**:
- Save/load: ✓ every user-visible attribute is in the ASDL
- Undo: ✓ replace the Document node, memoize handles the rest
- Completeness: ✓ every block kind the user can create has a variant
- Minimality: ✓ bold and italic are independent booleans in Style
- Orthogonality: ✓ Span kind and Style are independent

**What falls out of this modeling**:
- Incremental rendering: keystroke changes one Line/Span → memoize caches all others → one line recompiles
- Undo: previous Document node → memoize cache hit → instant, no undo stack
- Modal editing (if vim-style): Mode is a sum type in the reducer, not a state machine
- Syntax highlighting: second terminal from the same Line nodes, memoized per line
- Multiple windows: same Buffer node referenced by two Windows → memoize hits on shared compilation
- Search/replace: new Line nodes for affected lines only → 3 replacements in 10,000 lines recompiles 3 lines
- Parallelism: independent Blocks compile in parallel — the ASDL tree is the execution plan

**Realization note**:
A text editor often uses a thin proto path from laid/batched text plans to installed render Units. But if the backend grows honest install nouns — glyph-atlas artifacts, cached emitted text kernels, exportable formatting packages — then the proto language becomes richer. The source language is still document/block/span; the proto language simply expands when installation itself needs more structure.

### 12.2 Spreadsheet

**Sum types**:
```
CellValue = Number | Text | Boolean | Empty | Error
CellExpr = Literal | CellRef | RangeRef | FuncCall | BinOp | UnaryOp
ChartKind = Bar | Line | Scatter | Pie | Area
FormatCondition = ValueBased | FormulaBased
```

**Phases**:
```
Editor:       Sheet with formula strings, cell formats
Authored:     Formulas parsed to expression trees
Resolved:     References validated, dependency graph built,
              topological sort computed
Classified:   Cells classified: static | volatile | circular
Evaluated:    All values computed (THIS is the "compilation" —
              evaluation IS compilation)
Compiled:     Unit that renders the grid to GPU
```

**Key insight**: In a spreadsheet, EVALUATION is the terminal phase for data. Formula `=A1+B1` compiles to `terra: return cells[0] + cells[1]`. The result is a number, but the compilation process bakes the cell references as array indices and the operations as arithmetic. A compiled spreadsheet doesn't interpret formulas — it runs a native function that produces all cell values.

**Coupling point**: Conditional formatting depends on cell values. Cell values depend on formulas. Formulas depend on other cells. The dependency graph determines evaluation order. This is why the Resolved phase computes the topological sort BEFORE evaluation.

**What falls out of this modeling**:
- Incremental evaluation: change cell A1 → only cells dependent on A1 recompute, the dependency DAG is the ASDL structure
- Compiled formulas: `=SUM(A1:A10)` compiles to a native add chain with baked offsets — no formula interpreter at runtime
- Circular dependency detection: falls out of the topological sort in the Resolved phase — cycles are errors with semantic refs
- Parallel evaluation: independent subgraphs of the dependency DAG evaluate in parallel, no scheduler needed
- Charts as second terminal: same cell data → chart rendering pipeline, memoized independently, change a cell → chart recompiles incrementally

**Realization note**:
Many spreadsheet workloads use a thin proto path: machine meaning becomes an installed evaluator or renderer with very little extra proto structure. But if formulas are packaged for deployment, sandboxing, persistence, remote execution, or cached bytecode-template artifacts, then the proto language becomes richer below the evaluator machine. Again, that does not change the source nouns: sheet, cell, formula remain the domain language.

### 12.3 Drawing / vector graphics app

**Sum types**:
```
Shape = Rect | Ellipse | Path | Text | Image | Group
PathOp = MoveTo | LineTo | CubicTo | QuadTo | ArcTo | Close
Fill = Solid | LinearGradient | RadialGradient | Pattern | None
Stroke = (Paint paint, number width, LineCap cap, LineJoin join)
BlendMode = Normal | Multiply | Screen | Overlay | ...
```

**Phases**:
```
Editor:     Shape tree with transforms, styles, layers
Authored:   Transforms resolved to absolute, groups flattened
Laid:       Bounds computed, text shaped, hit-test tree built
Batched:    Draw calls sorted by texture/shader/blend
Compiled:   Unit that renders to GPU
```

**Key insight**: A vector graphics app and a UI toolkit have ALMOST IDENTICAL compilation pipelines. The difference is the source ASDL: a vector app has shapes with artistic properties (gradients, blends, strokes). A UI toolkit has elements with layout properties (flex, stack, sizing). Both compile to the same thing: GPU draw calls.

**What falls out of this modeling**:
- Incremental rendering: move one shape → memoize caches all others → 10,000 shapes behaves like 10 shapes per edit
- Layer reordering: new list, same child nodes (structural sharing) → memoize hits on every layer's content
- Group transforms: move group → children are same ASDL nodes → children cached, only group shell recompiles
- Export to multiple formats: SVG, PDF, PNG are different terminal boundaries from the same ASDL → target is a memoize key
- Zoom/pan: viewport-independent shape compilation + viewport-dependent projection → zoom is a cache hit on all shapes

**Realization note**:
Vector and drawing systems often split here. On-screen rendering may use a thin proto path to draw Units, while export/build paths may honestly want richer artifact languages: SVG documents, PDF object graphs, cached shader/material packages, or installable export jobs. This is a good example of one source language feeding both thin proto realization and richer structured artifact realization.

### 12.4 Game / simulation

**Sum types**:
```
Entity = Player | NPC | Projectile | Trigger | Light | Camera | ...
Collider = Box | Sphere | Capsule | Mesh
Material = PBR | Unlit | Custom
Light = Point | Directional | Spot | Area
```

**Phases**:
```
Editor:       Scene graph — entities with components
Authored:     Transform hierarchy resolved, references linked
Classified:   Render buckets (opaque, transparent, shadow-casting)
Scheduled:    Draw call order, culling results, LOD selection
Compiled:     Unit that renders frame + Unit that steps physics
```

**Key insight**: A game has TWO terminal compilations — rendering AND physics. Both start from the same scene ASDL. Both are memoized independently. Editing an entity's visual properties recompiles only the render pipeline. Editing its collider recompiles only the physics pipeline. They share the source but have independent cache trees.

**Coupling point**: Physics affects rendering (transforms change per-frame). This means the compiled render Unit takes PHYSICS STATE as a parameter — the transforms are not baked, they're read from state. But the DRAW CALLS are baked (which shader, which texture, which mesh). Only the WHERE changes per-frame (from physics). The WHAT was compiled away.

This is a subtlety: not everything can be baked. Per-frame-changing values (physics positions, animation states) must be state fields, not constants. The Phase 4 classification determines: constant (bake it), per-frame (state field), per-vertex (shader attribute). The classification IS the compilation strategy.

**What falls out of this modeling**:
- Two pipelines from one source: render and physics compile independently — change a mesh, physics cached; change a collider, render cached
- Incremental scene compilation: add/move one entity → memoize caches all others
- Material specialization: PBR with baked roughness/metallic compiles to a specialized shader — no runtime material branching
- Live editing: edit an entity → recompile → hot-swap → see change immediately, no separate editor/play modes
- Prefab instancing: 100 references to the same ASDL subtree → memoize compiles once, change the prefab → one recompilation updates all instances
- Parallelism: independent entities compile in parallel, independent render buckets compile in parallel

**Realization note**:
Games and simulations commonly use both styles at once. Physics stepping may use a thin proto path to installed machines. Rendering may partly stay thin and partly expand through richer artifact layers such as shader packages, cooked material variants, asset bundles, or installable script kernels. The important rule is the same: entity/collider/material are source nouns; package/bundle/kernel/blob are proto nouns.

### 12.5 Parser frontend plus proto compiler

This example shows the full modern story:
- a **domain compiler** for parser meaning
- followed by a **proto compiler** for installable artifacts

#### Domain nouns

At the parser domain level, the honest nouns are:
- grammar
- token
- rule
- constructor
- product

Not:
- proto
- chunk name
- bytecode blob
- install catalog

Those later nouns may become correct at realization time, but they are not the parser author's source language.

#### Source ASDL

```asdl
FrontendSource.Spec = (
    Grammar grammar,
    Constructor* constructors,
    Product* products
) unique

FrontendSource.Grammar = (
    Token* tokens,
    Rule* rules,
    SkipRule* skips
) unique

FrontendSource.Token = (
    number id,
    string name,
    TokenKind kind
) unique

FrontendSource.Rule = (
    number id,
    string name,
    Expr expr,
    Result result
) unique
```

For JSON, the user-facing rule vocabulary might include:
- `value`
- `object`
- `array`
- `string`
- `number`
- `members`
- `elements`

That is the honest domain language.

#### Domain phases

```text
FrontendSource
    ↓ check
FrontendChecked
    ↓ lower
FrontendLowered
    ↓ define_machine
FrontendMachine
```

These phases consume real semantic decisions:
- names become validated IDs
- token and rule refs become resolved headers
- grammar expressions become machine-feeding parser plans
- canonical parse/token machines become explicit

At this point, the semantic compiler has done its job. We know what parser machine should exist.

#### Realization phases

Now the second compiler begins.

For a Lua-oriented backend, the honest proto nouns might be:
- proto
- binding plan
- artifact family
- chunk name
- shape key
- artifact key
- source artifact
- closure artifact
- bytecode artifact

So the backend may continue like this:

```text
FrontendMachine
    ↓ prepare_realization
CrochetRealizeSource / ProtoCatalog
    ↓ check_realize
CrochetRealizeChecked
    ↓ lower_realize
CrochetRealizePlan
    ↓ prepare_install
CrochetRealizeLua
    ↓ install
artifact catalog / Unit / installed parser entry
```

The exact names may vary, but the architecture is the same.

#### Why this split is good

It keeps the two languages honest.

The parser author edits:
- tokens
- rules
- products

The proto layer handles:
- emitted parser kernels
- binding order
- source vs closure vs bytecode policy
- install keys and caches
- backend artifact installation

That means:
- grammar meaning stays out of the install layer
- install concerns stay out of the source grammar ASDL
- bytecode is an artifact, not the source of truth
- artifact identity can be modeled explicitly
- emitted Lua can stay tiny and regular because semantic work already happened upstream

#### What falls out of this modeling

- You can change the JSON grammar and recompile only the affected rules and parser artifacts.
- You can keep one realization policy for cold tools and another for hot ones without redesigning the grammar language.
- You can cache by machine shape separately from bound payload where useful.
- You can compare direct closure realization against emitted-source or bytecode realization as backend policy choices over the same machine.
- You avoid the common trap where the parser source language gets polluted with backend artifact concerns.

This is the clean relationship between a domain compiler and a proto compiler:

> the grammar language says what parser should exist;
> the proto language says how that parser machine should be installed.

---

## Part 13: What You Can Build

The pattern is applicable anywhere the user is editing a structured program in some domain and where repeated specialization is a better architectural fit than repeated interpretation.

The general rule: a good domain for this pattern has structured persistent domain objects with meaningful identity and relationships, interaction that changes the authored program over time, later computation that depends on derived semantic decisions, a final runtime workload that benefits from specialization, and where repeated interpretation of the full domain structure would be wasteful or architecturally messy.

All of those domains cross a proto boundary. In some, the proto stays thin. In others, the proto language becomes richer because installation itself has honest nouns: artifact family, template family, install key, bound payload, package, bundle, bytecode, export job. The source-domain fit and the proto-layer fit are related, but they are not the same question.

In every case, though, the seventh concept is still proto language. Only its richness changes.

### 13.1 Audio tools and synthesizers

Audio is one of the clearest fits. The domain naturally has explicit user-authored structure, graph or chain composition, stable identities for devices/clips/nodes/parameters, derived semantic phases (resolution, scheduling, coefficient computation), and a hot execution path where repeated interpretation is undesirable. Synth graphs, effects chains, modular routing, sequencers, DAWs, live performance tools.

The proto layer is often thin for hot DSP kernels, but may become richer for plugin wrappers, export artifacts, preset/package formats, or cached generated kernels.

### 13.2 Text editors and structured editors

A serious editor contains rich structure: documents, blocks, spans, cursors, selections, marks, style rules, folding state. Events edit that structure: insert, delete, move cursor, change selection, apply formatting. Later phases resolve styles, shape text, compute line layout, derive paint-ready runs, produce hit-test structures. The visual execution layer benefits from receiving something much narrower than the raw authored model. Especially compelling in structured editors where the source is richer than text.

Most editor rendering paths use a thin proto path, but cached text kernels, export documents, or installable editor-extension artifacts may justify a richer proto layer.

### 13.3 UI systems and retained declarative interfaces

A retained UI tree is already very close to a source program. It contains nodes, layout declarations, visual style, content, interaction bindings, view state. Events edit it, phases resolve styles/bindings, compute layout, flatten paint operations, produce draw/hit-test Units. The same architecture that drives an audio compiler drives a UI compiler — different source vocabulary, same compilation story.

UI often uses a thin proto path to render/hit-test Units, but style packages, emitted widget kernels, theme bundles, or installable component artifacts may justify a richer proto language.

### 13.4 Spreadsheets and notebooks

Sheets, cells, formulas, charts, formatting rules. Formulas parse to expression trees, references validate into dependency graphs, evaluation IS compilation. The compiled spreadsheet doesn't interpret formulas — it runs a native function that produces all cell values. Notebooks extend this with richer cell types and execution semantics.

Many spreadsheet engines use a thin proto path, but packaging formulas for persistence, remote execution, sandboxing, or reusable emitted evaluators can introduce a richer proto layer.

### 13.5 Drawing and scene editors

Shapes with transforms, styles, layers. Transforms resolve to absolute, groups flatten, bounds compute, text shapes, draw calls sort by GPU efficiency. The same compilation pipeline as UI — different source vocabulary (artistic properties vs layout properties), same draw-call terminal.

These tools often have both thin and rich proto paths: on-screen rendering may stay thin, while export paths, print paths, and asset-package paths may need richer artifact languages.

### 13.6 Protocol engines and structured communication

If a system processes structured messages through semantic phases — validate, bind, classify, route, respond — it may fit the compiler shape. Source model may be session or protocol state, events are incoming messages, phases resolve and classify, terminals produce specialized handlers.

Realization may stay direct for in-process handlers, or become explicit when handlers must be packaged, deployed, cached, serialized, or installed into another runtime.

### 13.7 Simulations and live-authored systems

Scenario editors, physics setup tools, rule-based world configuration, interactive simulations with authored entities and behaviors. Source model contains entities, relationships, parameters, scenario structure. Later phases validate references, classify behavior families, derive execution schedules, compile step/query/render Units.

A thin proto path is common for hot stepping paths, while richer proto layers become valuable for asset cooking, scenario packages, generated rule kernels, or deployable simulation bundles.

### 13.8 Multi-output tools

Tools where the same source program feeds multiple outputs: execution, editor view, inspector/debugger, export/build artifacts. The architecture already assumes multiple memoized products from the same source. This is much cleaner than inventing several loosely synchronized models that each think they are the real app state.

This is also where richer proto languages most often appear, because export/build/install artifacts become honest outputs in their own right rather than incidental side effects.

### 13.9 The applicability test

The right question is not "is my domain like audio compilation?" The right questions are:

> is my user editing a structured program whose meaning I keep rediscovering at runtime, and would it be better to compile that meaning into narrower machines?
>
> and, below that, how thin or rich should the proto language be for this installation story?

### 13.10 What is a weaker fit

The pattern is a weaker fit when there is little or no persistent authored structure, no meaningful phase boundaries, execution is inherently generic and does not benefit from specialization, the domain is mostly ad hoc dynamic scripting with little stable semantic structure, or the cost of modeling the source language exceeds the value of the resulting clarity.

Likewise, a rich proto language is a weaker fit when installation has little honest structure beyond a thin machine-to-install path. If there are no real artifact nouns, no meaningful install identity, and no policy choices worth modeling, then the proto should stay thin rather than being inflated into a fake artifact language.

---

## Part 14: The Master Checklist

Before writing any implementation, answer these questions about your source ASDL:

### 14.1 Domain nouns
```
□ Listed every user-visible noun
□ Classified each as identity noun or property
□ Each identity noun has a stable ID
□ Each property is a field on its identity noun
□ No implementation nouns in the source (no buffers, threads, callbacks)
```

### 14.2 Sum types
```
□ Every "or" in the domain is an enum
□ Every enum has ≥ 2 variants
□ Each variant has its own fields (not shared with siblings)
□ No strings used where enums belong
□ Every variant is reachable from the UI
□ Every user action produces a valid variant
```

### 14.3 Containment
```
□ Drawn the containment tree
□ Each parent owns its children (no shared ownership)
□ Cross-references are ID numbers, not Lua references
□ Lists use ASDL *, not Lua tables
□ Recursive types use * or ? (no infinite structs)
```

### 14.4 Phases
```
□ Named each phase
□ Named each transition verb (lower, resolve, classify, schedule, compile)
□ Each phase consumes at least one decision (sum type eliminated or reduced)
□ Later phases have fewer sum types
□ Terminal phase has zero sum types
□ No phase can be merged without losing a meaningful distinction
□ No phase should be split without a clear additional decision to resolve
```

### 14.5 Coupling points
```
□ Identified every place where two subtrees need each other's information
□ Determined which must be resolved in the same phase
□ Determined which determines the other's order
□ These orderings are consistent (no cycles between phases)
```

### 14.6 Quality tests
```
□ Save/load: every user-visible aspect survives round-trip
□ Undo: reverting to previous ASDL node restores everything
□ Completeness: every variant reachable, every state representable
□ Minimality: every field independently editable
□ Orthogonality: independent fields don't constrain each other
□ Collaboration: edits to different subtrees merge cleanly
□ Testing: every function testable with one constructor + one assertion
□ No function needs mocks, fixtures, setup, teardown, or ordering
```

### 14.7 Incremental compilation
```
□ ASDL types are marked unique
□ Edits produce new nodes with structural sharing (not deep copy)
□ Memoize boundaries align with identity nouns
□ The changed subtree is small relative to the whole
□ Unchanged subtrees are identical Lua objects (not copies)
```

### 14.8 Parallelism
```
□ Independent subtrees can compile in parallel (no shared mutable state)
□ Memoize boundaries align with parallelism units (one per identity noun)
□ Granularity is coarse enough to avoid scheduling overhead
□ No implicit ordering between independent branches
```

### 14.9 Purity enforcement
```
□ Every boundary is a pure structural transform
□ Every boundary uses the canonical shape (record or enum)
□ The boundary vocabulary is: U.match, errs:each, errs:call, U.with, constructor
□ No mutable accumulators needed (data is self-contained per node)
□ No mid-chain lookups needed (references resolved in prior phase)
□ No imperative control flow needed (sum types handled by U.match)
□ If a boundary resists the canonical shape → fix the ASDL, not the code
```

### 14.10 Compilation / realization / execution split
```
□ Each function lives at one honest level: compilation, realization, or execution
□ Compilation-side code is pure, structural, memoized
□ Realization-side code handles install/artifact concerns, not source semantics
□ Functional helpers are treated as the authoring surface of the pure layer, not as the final runtime ontology
□ Execution-side code is specialized, state-owning, operational
□ No architecture-level reasoning happens in the execution layer
□ Terminals end semantic compilation even when APIs compress later realization steps
```

### 14.11 Machine design
```
□ Each terminal's semantic product is a machine, not merely an ad hoc function
□ Bake/live split is explicit: compile-time-known → gen/param, runtime-mutable → state
□ The canonical machine (gen/param/state) is clear before runtime packaging
□ Machine shape is narrow enough that hot execution is not rediscovering semantics
□ Parent/child machine composition reflects source containment where appropriate
```

### 14.12 Realization design
```
□ The proto language is explicit, even when it is thin
□ It is explicit whether the proto language stays thin or expands into richer artifact structure
□ If rich, the proto layer has honest nouns (proto, artifact, binding, install mode, key, blob, catalog)
□ Proto nouns do not leak upward into the domain source ASDL
□ Source-domain meaning does not get rediscovered inside proto code
□ Artifact identity is explicit when shape identity and installed identity differ
□ Bytecode / template artifacts / binding payload / source kernels are treated as artifacts, not source truth
□ The install/cache boundary is a truthful memo boundary
□ Template families and source-kernel families stay small and regular because semantics were already lowered upstream
□ The proto footguns in §6.10 were checked explicitly
```

### 14.13 Machine IR (when applicable)
```
□ Terminal input makes order, addressability, use-sites, resource identity, and state needs explicit
□ The machine receives typed shapes, not generic wiring it must interpret
□ If later branches share structure, headers carry the shared spine
□ If later branches need different aspects, facets carry orthogonal semantic planes
```

### 14.14 View / UI
```
□ View is a separate ASDL, projected from source
□ View elements carry semantic refs back to source
□ View has its own phase pipeline (Decl → Laid → Batched → Compiled)
□ Errors flow from domain pipeline to View via semantic refs
```

### 14.15 Implementation discovery (leaves-up)
```
□ Started at leaf compilers, not at top-level pipeline
□ Each leaf first clarified the machine it wants
□ Each leaf also clarified the smallest proto that would install that machine honestly
□ It was made explicit whether the proto language is thin or rich
□ Missing fields discovered by leaves were added to ASDL and propagated up
□ Layers above were modified to provide what leaves and proto demanded
□ Proto richness was justified by the leaf rather than invented speculatively
□ ASDL stabilized when leaves stopped demanding changes
□ Design (top-down) and implementation (bottom-up) interleaved until convergence
```

---

## Summary

```
THE MODELING METHOD

1. LIST THE NOUNS
   First ask whose language you are modeling.
   Domain nouns for source ASDL; proto nouns for proto ASDL.
   The proto language always exists architecturally, even when thin.

2. FIND IDENTITY vs PROPERTY
   Identity nouns get IDs and become records.
   Properties become fields.

3. FIND THE SUM TYPES
   Every "or" in the domain. Every choice.
   Each becomes an enum with variants.

4. DRAW THE CONTAINMENT TREE
   What owns what. Parents own children.
   Cross-references are IDs, validated later.

5. FIND THE COUPLING POINTS
   Where two subtrees need each other.
   These determine phase ordering.

6. DEFINE THE PHASES
   Each phase consumes decisions.
   Name the verb. If you can't name it, the phase shouldn't exist.
   Lower semantic phases should narrow toward machine-friendly forms.

7. TEST THE SOURCE ASDL
   Save/load, undo, completeness, minimality,
   orthogonality, collaboration, testing.
   Every function testable with one constructor + one assertion.
   Fix before implementing.

8. DESIGN FOR INCREMENTALITY
   ASDL unique. Structural sharing on edits.
   Memoize boundaries at identity nouns.

9. VERIFY PARALLELISM
   Independent subtrees compile in parallel — by construction.
   Same granularity as incrementality. No separate scheduling.
   The ASDL graph IS the execution plan.

10. DESIGN THE VIEW PROJECTION
    Separate ASDL. Semantic refs back to source.
    Own phase pipeline.

11. IMPLEMENT LEAVES-UP
    Start at the leaf compiler. First make the machine explicit.
    Then make the proto explicit: thin or rich, but always present.
    The leaf tells you what the ASDL and proto layer must provide.
    Fix the layer above. Recurse upward.

12. CONVERGE
    Steps 1-10 give a top-down draft. Step 11 tests it bottom-up.
    The ASDL expands under profiler pressure, then collapses
    as structural redundancy becomes visible.
    The design stabilizes when leaves stop demanding changes.
```

The hard part is not merely writing code. It is keeping the languages honest:
- source language for the domain
- machine language for semantic execution
- proto language for installation

The seventh concept is that proto language. Realization is the machine → proto → installed movement through it.

The leaves are the proof. They tell you whether the machine is honest, whether the proto is thin or rich, and whether the phases above them consumed enough knowledge. When the design is right, every leaf is a natural pure structural transform, every phase transition has one real verb, the proto language is explicit, and the installed artifact is exactly the one you wanted to run.

---

## Final statement

```
THE USER
    edits a domain program

THE SOURCE OF TRUTH
    source ASDL

THE INPUT LANGUAGE
    Event ASDL

STATE EVOLUTION
    Apply : (state, event) → state

THE SEVEN CONCEPTS
    source ASDL
    Event ASDL
    Apply
    transitions
    terminals
    proto language
    Unit / installed artifact

THE THREE LEVELS
    compilation decides the machine
    realization lowers machine → proto → installed artifact
    execution runs the installed result

THE CANONICAL LOWER STACK
    transitions
    → Machine IR
    → canonical machine: gen, param, state
    → proto language
    → Unit / installed artifact

THE LIVE SYSTEM
    poll → apply → compile → execute

THE BACKEND STORY
    source language and phase meaning stay stable
    proto language and realization policy vary below them
    LuaJIT by default; Terra by opt-in

THE REALIZATION RULE
    every machine crosses a proto boundary
    some protos stay thin as closures or native installs
    others expand into template → blob → bind or source-kernel families
    bytecode is an artifact, and source kernels are explicit artifacts too

THE DEEPEST RULE
    the source ASDL is the architecture

THE EXECUTION RULE
    functional structure builds machines;
    realization installs machines;
    installed artifacts run
```

> The pattern is not Terra. The pattern is domain-compilation-driven design for interactive software: the source ASDL describes a program whose meaning is progressively narrowed by transitions into Machine IR, then into a canonical machine, then through realization into installed runtime artifacts that execution runs until the source changes again. On LuaJIT, the default serious realization path should usually be template → bytecode blob → load + explicit binding, with direct closures reserved for the smallest simple cases and structural artifact/install frameworks used when named installation nouns are real. On Terra, realization may be explicit native code and native layout. Terra is one especially powerful realization style, not the definition of the pattern itself.
