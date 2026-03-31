# crochet-realize

`crochet-realize/` is the canonical **proto compiler** project.

It models the lower language that every machine crosses before it becomes an installed artifact.

In the current repository vocabulary:

- the **domain compiler** answers: what should exist?
- the **machine** answers: what should execute?
- the **proto compiler** answers: what is the smallest installable thing that hosts this machine on this backend?
- **installation** produces the final artifact that lives under that host contract

So the lower rule is:

```text
machine -> proto -> installed artifact
```

And the host-contract form is:

```text
realize(host_contract, machine) -> proto -> installed artifact
```

This is why `crochet-realize/` is not merely a codegen helper project. It is the explicit proto-language layer for Lua-hosted realization.

---

## What this project is for

This project exists to make the proto side of realization:

- explicit
- inspectable
- cacheable
- testable
- phase-structured

The key nouns here are not source-domain nouns like:

- track
- rule
- widget
- formula

The key nouns here are proto nouns like:

- proto
- catalog
- binding plan
- artifact family
- package mode
- shape key
- artifact key
- install artifact
- host contract

That is the architectural point of this project.

---

## Pipeline

The current pipeline is:

```text
CrochetRealizeSource
  -> check_realize
  -> CrochetRealizeChecked
  -> lower_realize
  -> CrochetRealizePlan
  -> prepare_install
  -> CrochetRealizeLua
  -> install
  -> installed artifact
```

This should be read as a real compiler pipeline for proto structure.

- **Source** — authored proto family selection and body form
- **Checked** — names resolved, ids assigned, invariants enforced
- **Plan** — artifact identity and install planning become explicit
- **Lua** — Lua-hosted install artifact prepared
- **install** — concrete installed artifact produced

---

## Proto families in Crochet

The most important current fact is:

> Crochet no longer has only one realization story.

It already has at least two real proto families.

### 1. Text / source / bytecode proto family

This family is source-oriented.

Its body language includes things like:

- `LineNode`
- `BlankNode`
- `NestNode`
- `TextPart`
- `ParamRef`
- `CaptureRef`

Its typical lower shape is:

```text
text proto
-> checked refs
-> planned source artifact
-> load / bytecode install
-> installed artifact
```

This is the right family when the honest proto is:

- inspectable generated source
- source artifact
- bytecode artifact restored from source-produced function shape

### 2. Direct closure proto family

This family is structurally closure-oriented.

Its body language includes closure IR forms such as:

- expressions
- statements
- locals
- loops
- returns

Its typical lower shape is:

```text
closure proto
-> checked closure IR
-> closure plan
-> direct closure install
-> installed closure artifact
```

This is the right family when the honest proto is already a closure-hosted installable unit and source rendering is not the real host contract.

---

## The crucial clarification

The documentation should be read with this distinction in mind:

- **text/source/bytecode proto** is one proto family
- **direct closure proto** is another proto family

These are not just cosmetic output modes.
They are different answers to the question:

> what kind of proto does this host want for this machine family?

That is the main architectural clarification.

---

## Host contracts

For the current Lua-oriented backend, the main host-facing choices are:

- `host_source()`
- `host_bytecode()`
- `host_closure()`

These should be understood as host-contract selections, not just formatting preferences.

### `host_source()`
Use when the honest artifact is inspectable generated source.

### `host_bytecode()`
Use when the honest artifact is a serialized/restorable bytecode form.
This is mainly an installation/artifact choice, not automatically a hot-loop speed choice.

### `host_closure()`
Use when the honest artifact is a directly installed closure family.
This is the best direct Lua realization path when source rendering is not the host contract.

---

## Current status of the implementation

The implementation is ahead of the old documentation.

Historically, closure mode could be described as mostly “closure artifact on top of source-oriented proto.”
That is no longer the full story.

Today, Crochet already contains:

- a source-oriented proto family
- a direct closure proto family

So the right architectural reading is not:

> closure is just another artifact mode of one textual proto language

The right reading is:

> Crochet contains multiple proto families under one proto-language system.

---

## What a proto does here

A proto is not just a package wrapper.
A proto is a **specialization boundary**.

Once something becomes a proto, Crochet forces the backend/install story to commit to:

- a concrete realizable family
- a concrete binding surface
- a concrete artifact identity
- a concrete install path

That is why Crochet is valuable. It prevents the backend from remaining a vague generic installer.

---

## Current footguns to watch

### 1. Treating all proto families as one vague mode switch

If text proto and closure proto are treated as the same thing with a few conditionals, specialization pressure is lost.

### 2. Letting source-oriented proto semantics leak into closure-first families

If a direct closure host still has to think like a text emitter, the wrong proto family is dominating.

### 3. Hiding binding contracts

If binding order or capture meaning is implicit, the install boundary becomes fragile.

### 4. Using source generation as an escape hatch for unfinished lowering

Generated source is a valid proto path only when source is the honest artifact for that family.

### 5. Collapsing machine shape and artifact identity carelessly

Shape key, artifact key, and installed identity are related, but they are not always the same thing.

---

## Why this matters for more-fun

`more-fun` now exposes compiler-shaped operations like:

- `:shape()`
- `:plan(kind)`
- `:compile(kind)`

That means it is already behaving like a small compiler.

`crochet-realize/` is the natural place to make the proto half of that compiler explicit.

The real target shape is:

```text
source + pipe + terminal
-> machine / plan
-> proto family
-> installed closure / bytecode / source artifact
```

---

## Role of crochet.lua

`crochet.lua` should remain the elegant public authoring surface.

A good division of labor is:

- `crochet-realize/` — canonical proto compiler / project model
- `crochet.lua` — ergonomic façade and authoring surface over that model

That keeps the architecture honest:

- the public API stays pleasant
- the proto language stays explicit
- the install story stays inspectable

---

## Rule of thumb

Use the proto family whose host contract is actually honest.

- if source is the honest artifact, use the source/text proto family
- if bytecode is the honest install artifact, use the bytecode proto family
- if direct closure is the honest install artifact, use the closure proto family

And if a new host needs new proto nouns, model them explicitly instead of hiding them in the installer.

That is the same rule as everywhere else in the compiler pattern:

> model the real language that exists
