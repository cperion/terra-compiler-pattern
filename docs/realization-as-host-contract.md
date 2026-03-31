# Realization as Host Contract

## Why realization exists

A canonical machine is not yet a running system.

That sentence is the whole reason realization deserves its own philosophy.

In the compiler pattern, the semantic compiler gives us something immensely valuable:

- a source language
- a series of meaning-consuming phases
- a Machine IR
- a canonical machine

But even after all of that, something is still missing.

The machine is semantically correct, but it is not yet **alive**.
It does not yet know:

- where it runs
- who calls it
- what state ownership means in this host
- how it is installed
- how it is swapped
- what timing model governs it
- what resource boundaries it lives inside
- what error boundary surrounds it

That missing step is **realization**.

Realization is not merely “code generation.”
It is the act of binding a machine to a **host contract**.

That is the deeper claim of this article:

> realization exists because machine meaning is not yet hosted meaning.

---

## The compiler pattern already points here

The lower stack of the architecture is:

```text
transitions
→ Machine IR
→ canonical Machine
→ realization
→ Unit / installed artifact
```

This ordering matters.

A `Unit` is not the first machine concept.
A `Unit` is the packaged installed artifact.
The semantic executable abstraction above it is the canonical machine.

So the question after semantic compilation is not:

> can I turn this into code?

The better question is:

> under what host contract does this machine become a real installed thing?

That is realization.

---

## A backend is not just a target language

The word “backend” is often too weak.
It makes people think only of:

- LuaJIT
- Terra
- WASM
- C
- JavaScript

Those matter, but they are only part of the story.

In practice, many systems do not merely target a language runtime. They target a **host world**.

For example, in a serious interactive system, you may have distinct host contracts for:

- **audio**
- **view**
- **network**
- **export**
- **control / MIDI / automation**
- **storage / persistence**

Each of these is not merely “another library.”
Each is a different answer to the question:

> what does it mean for this machine to be installed and alive here?

That is why realization should be understood in terms of **host contracts**, not only in terms of backend languages.

---

## The central pattern

The simplest form of the idea is:

```text
installed_artifact = realize(host_contract, machine)
```

This is the canonical realization pattern.

A semantic compiler gives you a machine.
A host contract tells you how that machine is hosted.
Realization binds the two.

This is cleaner than treating runtime integration as ambient glue code, because it makes the boundary explicit:

- machine meaning on one side
- host contract on the other
- installed artifact as the result

This is not ordinary dependency injection.
The host contract is not a bag of services passed into arbitrary runtime code.
It is the parameter to a controlled transformation.

---

## What a host contract is

A host contract is a structured account of what a runtime host expects and provides.

It may include things like:

- installation API
- uninstallation API
- swap policy
- calling convention
- state ownership model
- timing model
- resource lifetime rules
- error boundary
- serialization or transport rules
- permitted realization forms

A host contract is not just:

- “use LuaJIT”
- “use Terra”
- “emit source”
- “use bytecode”

Those are partial realization policies.
The host contract is the wider runtime truth that those policies must satisfy.

---

## Audio, view, and network are different realization worlds

This is easiest to see in a DAW-like or live interactive system.

One source program may compile into several machines:

- an **audio machine**
- a **view machine**
- a **network machine**
- perhaps a **control machine**

Those are different semantic machines.
But even after they exist, they are not hosted the same way.

### Audio host contract

An audio host contract might define:

- callback shape
- sample/block timing model
- state retention policy
- hot-swap behavior
- driver integration
- resource ownership of buffers and handles
- real-time safety rules

### View host contract

A view host contract might define:

- frame/tick boundary
- draw submission shape
- input event boundary
- surface lifecycle
- GPU resource ownership
- redraw policy
- swap policy

### Network host contract

A network host contract might define:

- send/receive boundaries
- connection ownership
- serialization expectations
- retry / reconnection policy
- backpressure model
- message framing
- fault boundary

These are not interchangeable details.
They are different realization worlds.

That is why it makes sense to say:

> the parameters of the realization layer are whole host contracts.

---

## The DAW example

A DAW-like architecture makes the pattern especially clear.

A single source program may yield:

```text
ProjectSource
  → compile_audio_machine
  → AudioMachine

ProjectSource
  → project_view
  → compile_view_machine
  → ViewMachine

ProjectSource
  → project_network
  → compile_network_machine
  → NetworkMachine
```

Then realization binds each machine to its host:

```text
audio_artifact   = realize(audio_contract,   AudioMachine)
view_artifact    = realize(view_contract,    ViewMachine)
network_artifact = realize(network_contract, NetworkMachine)
```

The source language did not need to know anything about:

- audio callback ABI
- render loop mechanics
- network transport boundaries

Those belong to realization.

This is one of the deepest payoffs of the compiler pattern:

> source truth stays domain-honest while host integration becomes an explicit lower contract.

---

## Why whole backends can become parameters

People sometimes say they want to “pass whole backends as variables.”
That intuition is correct, but it needs precise language.

What is actually being parameterized is not just a code generator.
It is the **host contract**.

That means the variable is not merely:

- a different output syntax
- a different emitter
- a different bytecode option

It is a different answer to:

- who installs this machine?
- who calls it?
- what state does it own here?
- how is it swapped?
- what are the legal artifact forms?
- what runtime world receives it?

So yes, in the strongest sense, whole backends can become parameters — because realization is where host contracts become first-class.

---

## This is not just backend abstraction

Ordinary backend abstraction usually says:

- hide platform differences behind interfaces
- pass services around
- branch in a few runtime integration points

That is weaker than what realization can express.

Realization says:

1. compile semantic meaning first
2. make the machine explicit
3. bind that machine to a host contract
4. install the resulting artifact

That sequence matters.

It prevents the common architectural collapse where runtime integration starts leaking upward into the source language or semantic phases.

The source language should not know about callback ABIs.
The machine should not know about installer maps.
The realization layer should not rediscover source-domain semantics.

Each layer has its own truth.

---

## The three kinds of parameters

One way to make the architecture clear is to separate three categories of parameters.

## 1. Source parameters

These are authored by the user in the domain language.

Examples:

- tempo
- routing
- track structure
- grammar rules
- widget layout
- formulas
- scene entities

These are source truth.

## 2. Machine parameters

These are stable semantic inputs required by the machine.

Examples:

- coefficients
- slot indices
- resolved refs
- parser tables
- flat draw plans
- dependency order
- resolved layouts

These belong to `param` in the canonical machine or to the lower machine-feeding structures above it.

## 3. Realization parameters

These are supplied by the host contract.

Examples:

- callback/install ABI
- swap lifecycle
- resource ownership rules
- frame/tick boundary
- transport contract
- package/install policy
- closure/source/bytecode choice
- host-specific error model

These belong to realization.

This distinction is one of the cleanest ways to keep architecture honest.

---

## Why realization may need its own language

Sometimes realization is direct.

For example:

- a small machine becomes a specialized Lua closure
- a native Terra machine becomes a native `Unit`

In such cases, realization may be simple enough to remain a thin boundary.

But sometimes realization develops real nouns of its own:

- proto
- capture binding
- artifact family
- install mode
- shape key
- artifact key
- source blob
- closure blob
- bytecode blob
- install catalog
- bundle
- package

When those nouns are real, realization deserves its own language.

That is not architectural drift.
That is architectural honesty.

A realization language is appropriate when installation itself has meaningful structure that should be inspectable, cacheable, testable, and composable.

---

## Proto is a realization noun

This is why proto matters.

Proto is not necessarily the correct noun for the domain source language.
A parser source language should usually start with:

- grammar
- token
- rule
- product

not:

- proto
- chunk name
- bytecode blob

But proto may be exactly the right noun lower down, once the question becomes:

> what is the installable realizable unit of this machine family?

At that layer, proto is excellent because it gives you:

- identity
- memo boundary
- install boundary
- cache boundary
- swap boundary

That is the hallmark of a good realization noun.

---

## Audio contract, view contract, network contract

To make the point concrete, here is the shape of the idea in pseudo-notation.

## Audio

```text
AudioContract = {
  install,
  uninstall,
  swap,
  callback_shape,
  timing_model,
  state_policy,
  resource_policy,
  error_policy
}

AudioArtifact = realize(AudioContract, AudioMachine)
```

## View

```text
ViewContract = {
  install,
  uninstall,
  swap,
  frame_shape,
  input_shape,
  surface_policy,
  resource_policy,
  error_policy
}

ViewArtifact = realize(ViewContract, ViewMachine)
```

## Network

```text
NetworkContract = {
  install,
  uninstall,
  send_shape,
  receive_shape,
  connection_policy,
  serialization_policy,
  retry_policy,
  error_policy
}

NetworkArtifact = realize(NetworkContract, NetworkMachine)
```

The exact types will differ by system, but the pattern remains:

> a host contract is the parameter by which a machine becomes an installed artifact.

---

## Why this is better than hidden glue

Without explicit realization, systems often accumulate:

- installer maps keyed by mysterious strings
- hidden code caches
- one-off bytecode registries
- scattered `load` / `loadstring` wrappers
- backend conditionals spread throughout semantic code
- runtime service access just to answer installation questions

All of that is usually a sign that realization was real, but never modeled honestly.

Once realization is explicit:

- host contracts become values
- artifact identity becomes explicit
- installation policies become inspectable
- source truth stays clean
- semantic compilation stops leaking into backend glue

This is exactly the same kind of simplification the compiler pattern achieves elsewhere:

> make the missing language explicit, and the accidental infrastructure disappears.

---

## The deep rule

The source language says what the user means.
The machine says what should execute.
The realization layer says where and under what contract that machine lives.

That is the whole stack.

If you collapse those levels, you get confusion:

- source polluted by artifact nouns
- machines polluted by host glue
- realization polluted by semantic rediscovery
- runtimes full of accidental interpreters

If you keep them distinct, each layer becomes much simpler.

---

## Direct realization and explicit realization

One final distinction matters.

Not every system needs an explicit realization language.
Sometimes direct realization is the honest answer.

The rule is:

- if installation has no real structure, realize directly
- if installation has honest nouns, model them

That means:

### Direct realization is right when

- there is no meaningful artifact identity beyond the machine
- installation is simple
- host contract is thin
- no source/closure/bytecode/package distinctions matter
- no explicit install catalog is needed

### Explicit realization is right when

- artifact identity matters
- multiple realization forms matter
- install caching matters
- emitted payloads deserve structure
- named installable units matter
- whole host contracts vary in meaningful ways

This is not overengineering.
It is just the same rule as always:

> model the real language that exists.

---

## Realization is where machines meet worlds

That may be the cleanest summary.

A source program is a language.
A machine is semantic executable meaning.
A host contract is a world.

Realization is the layer where the machine meets the world.

That is why realization deserves its own language.
That is why whole backends can become parameters.
That is why audio, view, and network are not just “outputs,” but distinct host contracts.
That is why bytecode is not source truth.
That is why proto can be the right noun below the machine boundary and the wrong noun above it.

The machine is not yet alive until realization binds it to a host.

---

## Final thesis

> Realization is not the final detail of compilation. It is the first-class layer that binds canonical machines to host contracts. In serious systems, those host contracts are entire runtime worlds — audio, view, network, export, control — and they are the true parameters of the realization layer.

That is why realization exists.
