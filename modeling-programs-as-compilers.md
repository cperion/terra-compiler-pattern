# Modeling Programs as Compilers

## Part 1: The Core Insight

### 1.1 The ASDL is a language

The ASDL is not a data format. It is not a schema. It is not a description of what the program stores.

The ASDL is a LANGUAGE.

The source ASDL is the input language of a compiler. The user is the programmer. The UI is the IDE. Every user gesture is a program edit. Every edit produces a new program (a new ASDL tree). The compiler compiles it. The output runs.

Getting the ASDL right means getting the LANGUAGE right. A good language has:
- Clear nouns (types that correspond to domain concepts)
- Clear verbs (edits that produce new valid programs)
- Orthogonal features (independent fields that don't interfere)
- Completeness (every valid state is expressible)
- Minimality (no redundancy, no derived values)
- Composability (small pieces combine into larger programs)

These are the same properties that make a PROGRAMMING LANGUAGE good. Because that's what the source ASDL is — a domain-specific programming language whose programs are domain artifacts (songs, documents, spreadsheets, games) and whose compiler produces executables that realize those artifacts.

Every interactive program is a compiler. The source language is the UI. The ASDL is the IR. The pipeline is the optimizer. But the most important product in the middle is not "a function." It is a MACHINE. More precisely, the canonical lower stack of the pattern is:

- **transitions**
- **Machine IR**
- **canonical Machine** (`gen`, `param`, `state`)
- **backend lowering**
- **Unit runtime** (`Unit { fn, state_t }`)

Or stated as a flow:

```text
transitions
→ Machine IR
→ canonical Machine
→ backend lowering
→ Unit runtime
```

So the deeper statement is not just that the ASDL becomes code. It is that the ASDL becomes a machine, and `Unit` is how that machine is packaged for installation and execution on a backend.

And because the ASDL and the pipeline are pure — ASDL nodes are immutable values, transitions are memoized functions, compositions are structural — the entire design is target-independent. The same ASDL types, the same phases, and the same transitions can realize Terra/LLVM native code, LuaJIT-specialized closures, JavaScript, or WASM. Only the leaf compilation — the terminal boundary where ASDL becomes executable machinery — touches the backend. The modeling method described in this document produces an architecture that is portable across targets without redesign, because the design decisions live in the pure layer, and the pure layer doesn't know what machine it's on.

Design the language well, and the compiler writes itself. Design it poorly, and no amount of implementation effort can fix it. The ASDL is the architecture. Everything else is derived.

### 1.2 A program is a function from user intent to machine execution

Every interactive program takes human gestures (clicks, keystrokes, drags, voice commands) and produces machine behavior (pixels on screen, samples to speakers, bytes to network, commands to hardware).

Between intent and execution, there is a GAP. The user thinks in domain concepts ("make this louder," "move this paragraph," "connect these nodes"). The machine operates on registers, memory addresses, shader programs, and audio buffers. The program's job is to bridge this gap.

Traditional programs bridge the gap at runtime, every frame, with dispatch tables, virtual calls, config lookups, and state machines. They are INTERPRETERS — they re-answer "what should I do?" every cycle.

The compiler pattern bridges the gap at edit time, once, by COMPILING the user's intent into a specialized executable machine. On Terra that may be explicit native code. On LuaJIT it may be a highly specialized closure and state layout that the host JIT compiles aggressively. The compiled result runs until the intent changes. When it changes, the compiler runs again (incrementally — only the changed subtree).

That wording matters. The terminal is not best understood as merely "returning a function." It is better understood as defining the machine the runtime should host. Backend packaging then gives that machine a calling convention, state layout, lifecycle, and installation story.

### 1.3 The gap has layers

The gap between intent and execution is never one step. There are always intermediate representations — levels of knowledge between "what the user said" and "what the machine does."

```
User intent:      "I want a low-pass filter at 2kHz on this synth"
    ↓
UI vocabulary:    Track → DeviceChain → Device(Biquad, freq=2000, q=0.7)
    ↓
Semantic model:   Graph → Node(biquad_kind, params=[2000, 0.7])
    ↓
Execution plan:   Job(biquad, bus=3, coeffs=[b0, b1, b2, a1, a2])
    ↓
Machine code:     Terra fn / LuaJIT-specialized loop: y = 0.067*x + 0.135*x1 + 0.067*x2 - ...
```

Each layer consumes knowledge — it resolves a decision that the layer above left open. The UI layer knows the user said "Biquad." The semantic layer resolves what that means in the graph. The execution plan computes the coefficients. The machine code bakes them as constants.

### 1.4 These layers ARE your phases

Each layer is an ASDL module. Each transition between layers is a memoized function. The phases are not arbitrary — they reflect the actual structure of knowledge resolution in your domain.

The question "how many phases should I have?" is answered by: "how many distinct levels of knowledge resolution does your domain have?" Not more. Not fewer. Each phase should consume at least one meaningful decision. If a phase doesn't resolve anything, it shouldn't exist. If a phase resolves two unrelated things, it should be two phases.

### 1.5 The source phase is the most important

The source phase — the first phase, the one the user edits — determines everything. It is the input language of your compiler. Every other phase is derived from it. Every boundary transforms it. Every Unit compiles it.

If the source phase is wrong — if it models the wrong concepts, or models them at the wrong granularity, or couples things that should be independent, or separates things that should be together — every downstream phase inherits the mistake. The entire pipeline compiles the wrong thing correctly.

Getting the source phase right requires understanding the domain deeply enough to answer: "what are the NOUNS of this domain?" Not the implementation nouns (buffers, callbacks, handlers). The DOMAIN nouns (tracks, clips, parameters, curves, connections, constraints). The things the USER thinks about. The things that appear in the UI. The things that get saved to disk and loaded back.

### 1.6 The hard part

The architectural primitives — ASDL `unique`, Event ASDL, Apply, memoized stage boundaries, pure structural transforms, and Unit — are tools. They don't tell you WHAT to compile. They don't tell you what your types should be. They don't tell you what phases to define. They don't tell you where knowledge is consumed. They don't tell you which sum types to create or when to eliminate them.

That's the hard part. And it must be done RIGHT, upfront, before a single line of implementation. Because the ASDL IS the architecture. A wrong type in the source phase propagates through every phase, every boundary, every compiled output. You can't refactor a phase boundary after 50 functions depend on it. The cost of a wrong early decision compounds through the entire pipeline.

This document is about how to make those design decisions — and about the architecture that makes them pay off.

---

## Part 2: The Six Concepts and the Live Loop

The pattern is built from six concepts. They are small enough to state in a paragraph each and powerful enough to organize an entire interactive application.

### 2.1 Source ASDL

This is what the program IS — the user-authored, user-visible, persistent model of the domain.

In a music tool: tracks, clips, devices, routings, parameters. In a text editor: document, blocks, spans, cursors, selections. In a UI system: widgets, layout declarations, paint declarations, bindings. In a spreadsheet: sheets, cells, formulas, formatting rules, charts.

The source ASDL is not runtime scaffolding. It is not a cache of derived facts. It is the authored program. It must answer: what did the user author? What should survive save/load? What should undo restore? What objects exist as user-visible things? What choices are independent user choices versus derived consequences?

If the source tree cannot answer those questions cleanly, it is not yet the right source tree.

### 2.2 Event ASDL

This is what can HAPPEN to the program. Instead of treating interaction as arbitrary callbacks, the pattern models input as a language too.

Examples: pointer moved, key pressed, node inserted, selection changed, parameter edited, transport started, file opened.

Events are part of the architecture because they determine how the source program evolves. Modeling them explicitly as typed ASDL makes the input language inspectable, testable, and serializable — just like the source language.

### 2.3 Apply

The pure reducer:

```
Apply : (state, event) → state
```

Apply does not reach into a global environment or mutate the world in place. It takes the current source ASDL plus an event and returns the next source ASDL.

That purity is not cosmetic. It is what makes:
- undo simple (restore the previous tree)
- structural sharing possible (unchanged subtrees are the same objects)
- memoization coherent (same inputs → same outputs)
- tests trivial (construct state, apply event, assert result)

If Apply is correct, state evolution becomes explicit and inspectable.

### 2.4 Transitions

A transition is a pure, memoized boundary from one phase to another:

- source → authored
- authored → resolved
- resolved → classified
- classified → scheduled

A transition consumes unresolved knowledge. That phrase matters. A real phase boundary should answer a real question: resolve IDs into validated structural facts, classify a variant into a smaller set of cases, attach derived semantic information, flatten a rich domain form into a leaf-oriented shape.

A transition is not just "another pass." It is a point where ambiguity is reduced.

### 2.5 Terminals

A terminal is a pure, memoized boundary that takes a phase-local node and ultimately produces an executable `Unit`.

This is where the architecture stops being purely descriptive and becomes operational. The terminal says: this part of the program is now concrete enough — here is the specialized machine that performs it, here is the stable input it reads, here is the runtime state it owns.

The terminal should be understood as the bottom of a canonical stack:

```text
transitions
→ Machine IR
→ canonical Machine
→ backend lowering
→ Unit runtime
```

At the terminal boundary specifically, that means:

1. earlier transitions have already produced the right Machine IR
2. the terminal defines the canonical machine: `gen` (the execution rule), `param` (stable machine input), `state` (mutable runtime-owned state)
3. backend lowering then packages that machine as `Unit { fn, state_t }`

This is not a minor explanatory refinement. It is the right terminal philosophy. The compiler's semantic product is the machine. `Unit` is the backend/runtime packaging of that machine.

Depending on backend, this may mean a quoted Terra function + Terra struct type, a specialized Lua closure + FFI-backed state representation, or some other target-specific executable product.

### 2.6 Unit

A `Unit` is the packaged runtime artifact for a compiled machine. Conceptually: executable behavior paired with owned runtime state layout.

```
Unit { fn, state_t }
```

The exact representation varies by backend, but the role is stable: the Unit packages a machine for installation, composition, hot swap, and execution on a particular backend. Units compose structurally — the same way the source tree composes structurally. Parent Units own child state. Composition is structural, not a separate architecture.

### 2.7 The live loop

Put together, those six concepts yield the live loop:

```
poll → apply → compile → execute
```

**poll** — Read an input from the outside world: a UI event, an audio/control change, a file-system update, a timer tick, a network message.

**apply** — Use the pure reducer to turn the current source program into the next source program. If nothing meaningful changed, much of the structure stays identical. If something local changed, only that subtree gets a new identity.

**compile** — Re-run the memoized transitions and terminals. Because boundaries are pure and nodes preserve structural identity where possible, only the changed parts need to be recomputed. This is incremental compilation as a direct consequence of architecture, not a bolt-on subsystem.

**execute** — Run the currently realized Units. That may mean: call the audio callback, draw the frame, answer hit tests, advance a simulation step. The execution layer should not be re-deciding architecture-level questions. It should be running the machine that the compiler has already specialized, with `Unit` serving only as the installed packaging of that machine.

### 2.8 Hot swap is the natural execution story

The live loop makes hot swap a natural operation rather than a special subsystem. The story is:

- the previous source program compiled to some installed Units
- a new event changes the source
- affected subtrees recompile to new machines and freshly packaged Units
- the runtime installs or swaps those Units
- execution continues using the new machine

There is no need to invent a separate conceptual layer called "live object behavior" that must somehow be synchronized with compilation output. The Unit IS the live-eligible compiled artifact.

### 2.9 The loop is continuous, not one-shot

This is not a traditional ahead-of-time compiler where the program is compiled once and then run forever. The program is alive. The user keeps editing it. So the system repeats: receive new event, derive new source program, recompile affected parts, keep running the new machine.

That is why the pattern is so suitable for interactive software. It treats interaction as editing a live program.

### 2.10 Multiple compilation targets from one source

The same source program may feed multiple derived products:

- execution Units (audio, simulation)
- view projections (pixels on screen)
- inspection structures (debug views, scaffolding)
- error reports
- hit-test structures

These are all memoized pure products derived from the same source tree, possibly through different phase paths. The architecture already assumes this — it is not an extension.

### 2.11 Why this is better than "just use immutable data"

Many systems use immutable data and still remain interpreter-shaped. They still walk generic trees every frame, branch dynamically on variants in hot paths, separate code generation from state ownership awkwardly, bolt on caches after the fact, and treat runtime traversal as the real architecture.

The compiler pattern is stronger. Its real claim is:

> the program should be explicitly modeled as source, and its execution should be the result of repeated specialization rather than repeated interpretation.

That is a much bigger design statement than "use immutable data."

---

## Part 3: The Two Levels — Compilation and Execution

The pattern stays coherent because it maintains a strong distinction between two kinds of code:

1. Code that **decides what the machine should be** (compilation level)
2. Code that **is the machine that runs** (execution level)

A lot of architecture becomes muddy because these two levels are mixed together. The application ends up half describing the program and half executing it at the same time, with no clear boundary between the two.

### 3.1 The compilation level

The compilation level is where the system reasons about the user's program. It includes:

- Source ASDL
- Event ASDL
- Apply
- transitions
- projections
- terminals
- structural error collection
- inspection derived from the modeled program
- the typed Machine IRs and terminal inputs that make machine construction obvious

Its characteristic properties are: pure, structural, memoized at stage boundaries, testable by constructor + assertion, driven by modeled data rather than ambient context.

This is the level where questions get answered: which variant is this really? Which IDs resolve to what? Which defaults apply? What layout should be produced? What machine should exist for this subtree? What specialized leaf machine should be emitted for it?

### 3.2 The execution level

The execution level is where the machine actually runs. It includes:

- a Terra function executing on native state
- a LuaJIT closure running over FFI-backed state
- a callback invoked by SDL or an audio driver
- a hit-test routine answering geometry queries
- a draw routine traversing already-lowered batches
- the runtime packaging and calling conventions that host installed machines as Units

Its characteristic properties are different: it may be imperative internally, it mutates only its owned runtime state, it should not be rediscovering high-level domain semantics, and it should be specialized enough that dynamic architectural reasoning has already been consumed.

The execution level is not where the app decides what exists. It is where the compiled artifact does the work it has already been specialized to do. The machine is the semantic executable abstraction; the Unit is the backend/runtime container that hosts it.

### 3.3 Why this split matters

If the execution level starts doing too much reasoning, you get symptoms: repeated dynamic branching on wide sum types, repeated lookups to resolve semantic facts that should have been attached earlier, runtime dependency on global context objects, mutable caches answering basic structural questions, difficulty testing without standing up large parts of the runtime.

Those are all signs that compilation work leaked downward into execution.

Likewise, if the compilation level starts taking on too much runtime machinery: pure boundaries become full of mutable orchestration state, terminals become hard to test without a live driver, backend concerns contaminate ASDL → Unit logic, phases stop reading like structural transformations and start reading like little runtimes.

### 3.4 The slogan

> **The compilation level decides the machine. The execution level runs it.**

### 3.5 Compilation-level code

The compilation level should be written in a recognizably structural style: `U.match`, `U.with`, `errs:each`, `errs:call`, ASDL constructors, small pure constructors, explicit error attachment. The goal is not to satisfy a functional-programming aesthetic. The goal is to ensure that phase boundaries behave like compiler passes: input structure in, output structure out, no hidden ambient dependence, no secret stateful side channels.

This is also the right place to understand the framework's functional helpers correctly. Operations like `U.each`, `U.fold`, `U.map`, `U.find`, `U.match`, `U.with`, and structural error collection are the **authoring vocabulary of the compilation level**. They are the surface language for writing pure compiler passes. They are NOT the deepest runtime ontology of the architecture.

That distinction matters. Functional structure is how you describe and transform typed programs. Machines are what eventually run. So the right slogan is:

> **functional structure builds machines; machines become Units; Units run.**

The functional API remains first-class, but in the right role: it is the language of the pure layer, not the final semantic model of execution.

### 3.6 Execution-level code

Imperative code is not banned from the system. It is just supposed to live in the right place.

At the execution level, the semantic center is no longer the functional helper vocabulary. It is the machine:

- `gen` — what rule runs
- `param` — what stable payload it reads
- `state` — what mutable state it owns

And below that, the backend packages the machine as a `Unit` suitable for installation and runtime calling conventions.

Acceptable imperative behavior at the execution level: update filter delay elements in runtime state, increment frame counters, push pixels to a backend API, call SDL/GL/native APIs from installed code, mutate an allocated state struct during a callback.

What is not acceptable is smuggling architecture-level reasoning into that imperative code. The execution layer should not be where we repeatedly decide which domain variant something is, whether a reference is valid, which layout policy applies, or how a wide authored form should be interpreted this frame. Those questions belong upstream.

### 3.7 Illustration: healthy vs unhealthy split

**Healthy text rendering:**
- Compilation: resolve font, attach style defaults, shape text, compute line breaks, derive glyph runs, produce draw-ready items, terminal emits a specialized Unit
- Execution: iterate already-shaped runs, read glyph positions, issue drawing operations

**Unhealthy text rendering:**
- Execution: choose a font, discover wrap mode, resolve alignment, shape text on the fly, compute line layout every frame for the same unchanged subtree

**Healthy audio filter:**
- Compilation: read authored filter type and parameters, resolve channel topology, compute coefficients, emit a leaf fixed to the concrete filter kind, define `state_t` that owns only live integrator history
- Execution: read sample input, update state history, run the fixed arithmetic path

**Unhealthy audio filter:**
- Execution: what kind of filter is this? How many channels? Where are my coefficients? Which code path for this variant?

### 3.8 Terminals are on the compilation side

Even though terminals produce executable artifacts, terminals themselves are still part of the compilation level. A terminal is a pure function from phase-local data to a machine, and then to a packaged Unit. The terminal should remain structural and testable. Backend API details should be encapsulated in the produced Unit, not leaked into the terminal's semantic input model.

### 3.9 Error handling differs by level

At the compilation level, errors are structural: missing reference, unknown asset, invalid authored combination. They can be attached to the relevant subtree, collected, and sometimes replaced with neutral fallback behavior so unaffected siblings still compile.

At the execution level, errors are operational: runtime backend failure, device failure, driver unavailability, hard execution faults.

Mixing these two kinds of error handling leads to poor design.

### 3.10 Testing differs by level

Compilation-level tests should look like: construct ASDL input, call reducer/transition/terminal, assert output. No mocks, no containers, no elaborate runtime setup.

Execution-level tests may involve: smoke tests, benchmark harnesses, backend integration checks, profiling and latency measurements.

Both matter, but they test different things.

### 3.11 Backend neutrality depends on this split

The compilation level is where most of the application's meaning lives: modeled source, event handling, transitions, projections, terminal design. If that layer stays pure and structural, then different backends can realize the resulting Units differently without forcing a redesign. If instead the compilation layer is full of backend-specific runtime assumptions, the architecture stops being portable.

---

## Part 4: Unit — The Packaged Runtime Artifact

### 4.1 What a Unit is

A `Unit` is the packaged runtime artifact for a compiled machine for a subtree of the source program. It pairs specialized behavior with the runtime state layout that behavior owns.

```
Unit { fn, state_t }
```

- `fn` describes realized behavior — the executable code under this backend's calling convention
- `state_t` describes owned runtime state — the layout the code operates on

The compilation level decides the machine that should exist. Backend realization packages that machine as a Unit. The execution level operates on the packaged result.

### 4.2 Why Unit is better than "just a function"

A plain function does not necessarily tell you what runtime state it owns, how that state should be allocated, how child state composes into parent state, what the lifecycle of that state is, or how hot swap should treat state compatibility.

The Unit concept is richer because it keeps the runtime packaging, state ABI, and executable behavior coupled. That is especially important in a system built around repeated recompilation. If the compiled artifact changes, the state ownership model may change too, and the architecture should represent that explicitly. But it is equally important to remember that Unit is still not the first machine concept. The semantic machine exists one layer above: `gen`, `param`, `state`.

### 4.3 Why Unit is better than codegen plus external runtime objects

Another common alternative is to generate code but keep runtime state in a separate object system. That usually leads to either: the codegen is not really in charge of the running machine, or the runtime object layer becomes a shadow architecture competing with the source ASDL.

The Unit avoids that split. The compiled machine owns its runtime state contract. Composition owns child state structurally. The runtime object graph does not need to be the real architecture.

### 4.4 What belongs inside state_t

Good examples:
- integrator history for filters
- mutable counters owned by the machine
- parent-owned child state aggregation
- cached runtime handles that are truly execution ownership
- temporary execution-time fields that persist only as long as the machine does

Poor examples:
- authored parameter choices (belong in source)
- unresolved references (belong in source, resolved in a phase)
- derived semantic facts that should have been attached structurally before terminalization

### 4.5 Unit composition

Because Units compose structurally, they give the architecture a natural locality story:

- child A has `state_t_A`
- child B has `state_t_B`
- parent `compose` builds a parent `state_t` containing those as fields plus any parent-local state

The result is a single structural layout reflecting the same containment story as the source tree. The source tree composes structurally. The compiled Units compose structurally. The runtime state layout also composes structurally. All three relationships line up.

This is cleaner than scattered heap objects, external registries, dynamic table lookup by child index, or generic runtime containers holding opaque state blobs.

If a source subtree is unchanged, its terminal hits the memoize cache, its Unit can be reused, and the parent composition may also be reused depending on identity structure. Runtime installation can often remain stable.

### 4.6 The canonical machine: gen, param, state

The `Unit { fn, state_t }` is the packaged runtime artifact, but it is not the first machine concept. The canonical machine layer immediately above that packaging is:

- **gen** — the execution rule / code-shaping part
- **param** — the stable machine input it reads
- **state** — the mutable runtime-owned state it preserves

So the bottom of the architecture is best understood as a canonical chain, not a single handoff:

1. **transitions** — pure boundaries that consume knowledge and produce the right lower typed forms
2. **Machine IR** — the typed machine-feeding layer that makes order, access, use-sites, resource identity, and runtime ownership explicit
3. **canonical Machine** — `gen`, `param`, `state`
4. **backend lowering** — target-specific realization of that machine
5. **Unit runtime** — installed runtime packaging as `Unit { fn, state_t }`

This is not an optional explanatory trick. It is the right way to think about terminal design. The compiler's semantic product is the machine. The Unit is how that machine is installed, composed, swapped, and run on a particular backend.

This also clarifies the role of the framework's older functional surface. The functional helper vocabulary is still essential, but its job is to BUILD and FEED machines, not to replace them as the semantic center. In other words:

- **functional API** — the authoring surface for pure transitions, projections, reducers, and terminal construction
- **Machine** — the canonical execution model
- **Unit** — backend-specific installed realization of that machine

Many terminal design mistakes come from compressing those three questions too early. A leaf may look awkward not because Unit is the wrong contract, but because the phase above it is not making gen, param, and state obvious enough.

### 4.7 Machine IR

A good Machine IR above the canonical machine is the **typed machine-feeding layer** that makes the machine's compiled wiring explicit. The machine is the real semantic executable abstraction; Machine IR exists to make that machine trivial to derive; Unit then packages it for runtime. Machine IR should answer five things directly:

1. **Order** — what loops exist? What spans or ranges are executed? What headers determine one execution slice?

2. **Addressability** — how does execution reach what it needs? What refs, slots, indices, or handles are already resolved?

3. **Use-sites** — what concrete occurrences are executed? What instances of drawing, querying, routing, or processing exist?

4. **Resource identity** — what realizable resources may need runtime ownership? What stable resource specifications identify them?

5. **Runtime ownership requirements** — what mutable runtime state must persist? What state schema does the machine require?

That is a more useful way to think about Machine IR than calling it merely a planning layer. Its job is to make gen, param, and state trivial to derive.

This does NOT mean introducing a generic interpreted wiring DSL. The pattern should not devolve into runtime nodes like `Accessor(kind, ...)` or `Processor(kind, ...)` that execution must interpret dynamically. That would recreate the accidental interpreter at a different layer.

Instead, the wiring should already have been compiled into ordinary typed shapes the machine can consume directly: spans and ranges, headers and closed dispatch records, slot/index refs, instance records, resource specifications, runtime state schemas.

The practical test is:

> does the machine receive explicit order, addressability, use-sites, resource identity, and persistent state needs — or does it still have to invent them while running?

If it still has to invent them, the ASDL and phase structure above the terminal are still too high-level.

### 4.8 The header pattern

When several later branches must remain aligned after a shared flattening phase, it is often a mistake to keep widening one giant node record so every later branch can still find the same thing.

A better design is often:

1. Define a **shared structural header vocabulary**
2. Let later branches carry only their own orthogonal fact planes
3. Rejoin those branches structurally through the shared header/index space rather than through semantic lookup

A header is not just metadata. It is a typed structural carrier for truths such as: stable identity, parent/child topology, subtree spans, region-local index space — whatever minimal structural alignment later branches must share.

The key discipline is:

> keep shared structure in the header spine; keep branch-specific meaning in separate fact planes.

Without a header spine, there is constant pressure to build oversized lower nodes that carry geometry facts, render facts, query facts, accessibility facts, and routing facts all together, merely so later phases can still line them up. That creates broad rebuilds, hidden coupling between branches, and expensive late splitting.

The practical test is:

> if several later branches need the same structural identity/topology but different semantic facts, should there be one shared header spine instead of one wider node type?

Very often, yes.

### 4.9 The facet pattern

If the header spine carries the shared structural truth, then the next question is: what different aspects of meaning are attached to that shared structure, and which later consumers actually need which aspects?

A **facet** is one orthogonal semantic plane aligned to the shared header/index space. Typical examples: layout facts, paint facts, content facts, behavior facts, accessibility facts.

Instead of widening one lower node record until it carries everything, a better design is:

1. One shared header spine
2. Several aligned facet planes
3. Branch-specific lowerings that consume only the facets they actually need

In that shape: the header answers "what thing is this in the shared structure?" and the facet answers "what aspect of that thing are we talking about?"

This matters because many bad lower designs come from bundling concerns that do not need to travel together. Geometry solve does not usually need paint facts. Render lowering does not usually need key-route facts. Accessibility often does not need to travel with render semantics at all.

The facet pattern is both a modeling improvement and a performance improvement. With the right facet split: each lowering phase does less semantic work, unrelated edits stay more local, memoization boundaries stay cleaner, and joins remain structural through the shared header/index space.

Together, headers and facets give a powerful way to design lower ASDL that stays local, branchable, and machine-friendly:

- **headers** carry shared structural truth
- **facets** carry orthogonal semantic truth

### 4.10 Errors and fallback at the Unit boundary

Suppose a subtree cannot be compiled cleanly because an asset is missing, a reference is invalid, or a backend does not support some requested form yet. A good architecture can:

- attach an error to that subtree
- produce a neutral fallback Unit if appropriate
- continue compiling unaffected siblings

A missing image may compile to a placeholder visual Unit. An unsupported effect may compile to a no-op Unit plus an attached error. An invalid reference may compile to silence in an audio subtree. This is much cleaner than turning one subtree problem into a global runtime failure.

---

## Part 5: Designing the ASDL

### 5.1 Step 1: List the nouns

Open the program you're modeling (or imagine it if it doesn't exist). Look at every element the user can see and interact with. Write down every noun.

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

### 5.2 Step 2: Find the identity nouns

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

### 5.3 Step 3: Find the sum types

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

The terminal phase has ZERO sum types. Everything is concrete. No branches, no dispatch, no type checks. Just concrete fields and predictable access paths. This is what lets the backend optimize aggressively — whether that is LLVM on Terra or host-JIT specialization on LuaJIT — because there is nothing semantic left to dispatch on.

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

**`U.terminal(name, fn)`** — a memoized terminal compilation. Takes a node from the final phase, uses the pure structural authoring vocabulary to define the canonical machine for that node, and returns its packaged `Unit { fn, state_t }` realization.

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

### 7.4 Leaves-up discovery

The modeling method (Part 2) gives you a first draft of the ASDL. That draft is a hypothesis. Implementation tests it. The testing direction is bottom-up: start at the leaves, let each leaf tell you what the layers above must provide, and fix the ASDL from the bottom up.

#### Write the leaf you want to write

Don't start by implementing the full pipeline top-down. Start at the leaf — the function that takes one phase-local node, defines the machine you want, and produces the packaged `Unit` for it. Write the leaf you WANT to write, the one that would be natural if the ASDL were perfect.

This is not a trick for implementation. It is the core design method.

After you identify the top-level domain nouns and draft the source ASDL, the next question is not:

> how do I fit this feature into the current runtime architecture?

The next question is:

> what machine do I wish I could install?

That means imagining the highest-performance stable kernel that would execute this domain well:

- what would the terminal `fn` actually do in the hot path?
- what would its `state_t` need to own live across calls?
- what values should be baked into code?
- what values should stay live in state?
- should it walk a tree, or a flat plan, or a packed command stream?
- should it be one monomorphic runner, or a composition of genuine submachines?

Only after you can picture that machine should you ask what phase-local data structure would feed it cleanly.

The leaf immediately tells you what its input node must contain. A sine oscillator leaf needs frequency, waveform shape, gain. A biquad filter leaf needs pre-computed coefficients. A text renderer leaf needs resolved font metrics and glyph positions. A UI kernel leaf may need flat boxes, clip ranges, hit-test regions, and draw commands. If the terminal input node doesn't have those fields — if the leaf can't get what it needs from its single argument — the ASDL is wrong.

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

Now stop looking at the source tree and imagine the installed machine you actually WANT.

A high-performance UI kernel probably does **not** want to traverse that authored tree every frame. It probably wants a stable function with one or a few tight loops over flat payload:

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

That imagined kernel tells you several truths immediately:

1. The kernel does not want symbolic bindings.
2. The kernel does not want the authored tree shape.
3. The kernel does not want unresolved constraints.
4. The kernel probably wants one stable runner over packed plan data.
5. Therefore the final phase before compilation should not be `Widget`. It should be something like `Ui.Plan`.

So now you can derive the phase path backward:

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
    ↓ compile_kernel
Unit { fn, state_t }
```

Notice what happened. The kernel shape forced the terminal input shape. The terminal input shape forced the solved phase. The solved phase forced the flattening phase. The flattening phase forced a prior binding-resolution phase. This is the method.

The source tree was still designed from the user domain. But once the user domain is known, the downstream phases are discovered by asking what the installed machine wants, then recursively asking what each prior layer must provide.

This is what "leaf-first" means in practice:

- not "start with implementation details and retrofit the domain"
- but "after modeling the domain, design the machine you wish you could install, then derive the ASDL that makes compiling to it mechanical"

#### What to inspect in the imagined kernel

When you imagine the leaf, inspect these questions explicitly.

**Code shape**
- Is the hot path one stable loop or many small submachines?
- Should child calls remain visible, or disappear via inlining?
- Does runtime still dispatch on a sum type that should have been consumed earlier?

**State shape**
- What facts change often but should not trigger recompilation?
- What runtime history must persist in `state_t`?
- What payload should live in parent state rather than in many child Units?

**Memory shape**
- Does the machine want arrays, trees, command streams, or region-local payload?
- Should the plan be packed by region, by z-order, by text run, by draw material?

**Boundary shape**
- What is the ideal function signature?
- What is the smallest terminal input node that makes the leaf trivial?

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

## Part 9: The Backend-Neutral Architecture

### 9.1 The pattern is not Terra

This architecture was historically called the Terra Compiler Pattern because Terra was the environment in which it first became unmistakably visible. Terra made the compiler-like nature hard to miss: you could literally build code as code, synthesize native state layouts, and hand the result to LLVM.

But the deeper discovery is: **the pattern is not fundamentally about Terra.**

The pattern is: the user is editing a program in a domain language, that program is represented as source ASDL, input is represented as Event ASDL, state changes are modeled by a pure Apply reducer, unresolved knowledge is consumed across real phases, lower phases become machine-feeding structures, terminals define canonical machines, backends package those machines as executable Units, and execution runs those Units until the source changes again.

None of that requires Terra specifically. Terra is one way to realize the backend step — a very strong one — but still just one backend.

Terra revealed the pattern. It did not define it.

### 9.2 The three-layer architecture

The architecture has three layers:

```
┌───────────────────────────────────────────────┐
│                 YOUR DOMAIN                   │
│                                               │
│  source ASDL, Event ASDL, Apply,              │
│  phase structure, projections, Machine IR      │
│  intent, domain semantics                     │
│                                               │
│  This is your application.                    │
├───────────────────────────────────────────────┤
│               THE PATTERN                     │
│                                               │
│  Machine IR, Unit, gen/param/state,           │
│  transition, terminal, memoize, match, with, │
│  fallback, errors, inspect                    │
│                                               │
│  This is the compiler architecture vocabulary │
│  used to express the app.                     │
├───────────────────────────────────────────────┤
│                THE BACKEND                    │
│                                               │
│  leaf realization, state layout, compose      │
│  realization, installation, hot swap,         │
│  target drivers, host compiler/JIT            │
│                                               │
│  This is target-specific.                     │
└───────────────────────────────────────────────┘
```

**Layer 1: Domain** — The application's actual semantic content. Source ASDL, Event ASDL, Apply, the real phases, projections, Machine IRs, terminal inputs. This is where questions like "what is a track?" and "what should save/load preserve?" live. This layer is not backend-specific.

**Layer 2: Pattern** — The reusable compiler vocabulary. Machine IR thinking, canonical `gen/param/state` machine thinking, Unit, transition, terminal, memoize, match, with, errors, inspect. This layer is not the app's semantics, but it gives the app a disciplined way to express them.

**Layer 3: Backend** — How a leaf becomes executable code on this target. How runtime state is represented. How Units are installed and swapped. How external drivers are called. This is where Terra and LuaJIT differ.

### 9.3 What should be shared across backends

For a well-factored app, the following should be shared:

- the source ASDL
- the Event ASDL
- the Apply reducer
- phase boundaries and their semantic meaning
- view projection logic
- terminal intent and terminal input design
- structural helper logic
- tests for pure-layer behavior

If changing backends requires changing large parts of this core, target concerns leaked too far upward.

### 9.4 What should vary across backends

- the exact representation of Unit
- the exact representation of state_t
- how compose realizes structural aggregation
- the exact leaf code shape
- installation and hot-swap mechanics
- driver integration
- the host compiler or JIT relied upon

### 9.5 Backend policy: LuaJIT by default, Terra by opt-in

This reframing leads to a practical policy:

> **LuaJIT by default. Terra by opt-in.**

That is not a demotion of Terra. It is a clarification of its role.

LuaJIT should be the default backend on JIT-native platforms because:

- the host runtime already provides much of the final compiler (JIT, specialization, native code)
- terminal construction is extremely cheap compared to LLVM
- deployment is lighter, iteration is faster
- scalar steady-state performance is highly competitive
- the same architecture applies cleanly

But LuaJIT is NOT the permissive dynamic-tables backend. The backend contract is still strict. Pure phases remain typed ASDL + pure structural transforms. Terminal leaves must lower to monomorphic LuaJIT code over typed FFI/cdata-backed state and payload layouts. If the leaf still wants arbitrary tables, missing-field checks, tag strings, or interpreter-style tree walking, the lowering is not finished.

### 9.6 What makes Terra special

Terra becomes the opt-in strong backend when you need what only Terra gives clearly and reliably:

**Explicit staging.** In Terra, the separation between compiler-side logic, generated code, and runtime execution is concrete and programmable. You can literally emit specific branch structures, inline known choices, and specialize paths — not by shaping code and hoping the JIT notices, but by authoring the generated machine directly.

**Static native types.** A Terra Unit can own a native function with a concrete signature, a native state_t with exact fields, explicit pointer-level access patterns, and concrete data layout known at compile time.

**Struct synthesis in compose.** Because child state layouts are native types, `Unit.compose` can synthesize larger native state layouts structurally — one explicit composite struct reflecting the containment hierarchy.

**ABI control.** When the integration boundary demands a specific calling convention or data layout, Terra provides it directly.

**LLVM optimization.** Constants baked into code, dead code elimination, instruction selection, vectorization potential — LLVM continues simplifying from where the terminal left off.

### 9.7 Terra as design pressure

One subtle but important point: Terra matters for more than raw speed.

Terra also acts as design pressure. Because it forces explicitness in type layout, staging boundaries, state ownership, machine shape, and compilation granularity, it often reveals missing phases, vague source models, coarse recompilation boundaries, and unclear authored/runtime splits.

A good mental model is:

> design with Terra-level explicitness in mind, even when LuaJIT is the default realization backend.

Once the LuaJIT backend is constrained correctly, a second statement also becomes true:

> strict LuaJIT can impose almost the same architectural pressure, because the leaf must still end as `Unit { fn, state_t }` over typed backend-native layout.

The difference is that Terra provides stronger mechanical enforcement through explicit native staging, while LuaJIT provides the same pressure only if the backend rules are kept strict.

### 9.8 When to opt into Terra

Terra is especially worthwhile when:
- explicit staging control matters more than build speed
- exact struct layout and ABI compatibility are required
- LLVM can materially outperform the host JIT for this kernel family
- the workload is heavy enough that LLVM compile cost is repaid by runtime throughput
- native interop requires direct low-level expression

### 9.9 A practical opt-in policy

1. Design the domain backend-neutrally
2. Design leaves with Terra-level explicitness in mind
3. Implement the shared pure layer once
4. Target LuaJIT first on JIT-native platforms
5. Benchmark the important leaf families and compositions
6. Opt into Terra where explicit native power buys enough

---

## Part 10: Performance Model

### 10.1 Performance is not just steady-state throughput

Because this architecture is built around a live compile loop, performance must be understood across two dimensions:

1. **Rebuild cost** — how expensive it is to rebuild the machine when the source changes
2. **Run cost** — how efficiently the rebuilt machine runs once installed

Both matter. A backend that produces brilliant machine code but is very expensive to rebuild may be the wrong default for interactive workloads. A backend that rebuilds instantly but executes too slowly may also be wrong.

### 10.2 The first performance question is architectural

In this pattern, the first useful performance question is often not "what function is hot?" but rather:

> why did this change require this amount of recompilation?

That question immediately points toward the actual architecture:

- Did Apply fail to preserve structural sharing?
- Are identity boundaries too coarse?
- Is source containment too broad?
- Is a transition doing too much work over too much structure?
- Is a terminal compiling too large a region at once?
- Did a later phase flatten away locality too early?

These are architectural issues, not micro-optimization issues. Performance debugging often becomes a question about model boundaries and phase clarity rather than about scattered runtime heuristics.

### 10.3 Rebuild cost

Rebuild cost is paid when the source program changes. It includes:

- reducer work
- structural allocation of changed nodes
- transition recomputation
- terminal recomputation
- backend-specific Unit construction
- installation or hot swap of the new compiled artifact

In interactive systems, rebuild cost is part of the user experience. Every keystroke, every parameter tweak, every node move potentially triggers a rebuild. Rebuild latency affects responsiveness, live feel, and confidence that the system is truly incremental.

This is why cheap terminal construction matters so much. LuaJIT wins an enormous amount on rebuild cost — producing specialized closures and FFI state layouts is dramatically cheaper than an explicit LLVM-backed path.

### 10.4 Run cost

Run cost is the cost of the installed machine while executing: callback throughput, draw loop throughput, state access cost, arithmetic cost, memory locality in the hot path.

If the installed machine is too slow, the architecture still fails. Audio callbacks at 44.1kHz, 60fps rendering, and low-latency simulation all impose hard run-cost constraints.

### 10.5 The bake/live split

One of the most useful performance questions at the terminal boundary is:

> what should shape `gen`, what should remain stable in `param`, and what should remain mutable in `state_t`?

**Bake into the machine when:**
- the fact is compile-time-known for the subtree
- removing the variability simplifies control flow materially
- constant propagation or specialization will help
- it reduces repeated branching in the hot path

Examples: fixed operator kind, fixed blend mode, known channel count, resolved shadow kind, known filter topology.

**Keep live in state_t when:**
- the value is execution-time mutable
- the value changes frequently without requiring semantic recompilation
- the machine genuinely needs runtime ownership of it
- rebuilding for every tiny change would be the wrong tradeoff

Examples: filter delay history, counters, mutable buffers, smoothing state, backend-owned handles.

The right bake/live split often determines whether a leaf feels compiled or still half interpreted.

### 10.6 Narrowing sum types early helps both costs

A wide sum type reaching the hot path hurts run cost (the machine keeps branching on semantic alternatives) and hurts rebuild cost (terminals become more complex when they must interpret broad authored structure). That is why later phases should narrow rather than widen. A good terminal input should be much more monomorphic than the authored source.

### 10.7 Locality is performance

If the source model and phases preserve locality well, then small edits change small subtrees, memoization hits stay high, terminals re-run only where necessary, and installation work stays smaller. If locality is poor, performance suffers before any low-level arithmetic question even arises.

This is why stable IDs, honest containment, and structural sharing are so central to the architecture's performance story.

### 10.8 The recursive benchmarking law

Once a lower machine is trusted, the next slow boundary points upward into the language and phase design above it. The biggest performance wins often come first from better source modeling, better identity boundaries, narrower phases, better Unit granularity, and better bake/live decisions — and only after those are right do low-level backend optimizations pay their full value.

A poor source model can waste more performance than a clever arithmetic trick can recover. A missing phase can cost more than a backend micro-optimization can save. A bad Unit boundary can dominate everything downstream.

### 10.9 The memoize-hit-ratio test

There is also a highly practical metric that sits between modeling and performance:

> **the memoize hit ratio at real stage boundaries**

This metric measures the architecture more directly than raw throughput does. If one small edit causes a few local misses and many sibling hits, the decomposition is healthy. If one small edit causes misses across unrelated leaves and widespread recompilation, the ASDL or phase boundaries are wrong.

Instrumentation through `U.memo_report()`, `U.memo_measure_edit()`, and `U.memo_quality()` makes this observable. The hit ratio is the design-quality metric for incremental compilation.

- **90%+ reuse** — decomposition is excellent
- **70–90% reuse** — healthy but worth inspecting
- **below 50% reuse** — the ASDL or phase boundaries are too coarse, structural sharing is broken, or keys are unstable

### 10.10 Backend-specific performance questions

**LuaJIT-oriented:** Are the emitted closures monomorphic enough to trace well? Are important constants captured in upvalues? Is state access stable and cheap via FFI? Are loops and composition shapes simple enough for the JIT?

**Terra-oriented:** Are we staging the right facts into emitted code? Is the native state layout as explicit and local as it should be? Are we paying LLVM cost at the right granularity? Is the compile tax worthwhile with sufficient steady-state benefit?

Different questions, same architectural frame.

---

## Part 11: What the Pattern Eliminates

The pattern does not eliminate complexity by pretending complex programs are simple. It eliminates infrastructure by removing the architectural conditions that made so much coordinating machinery necessary in the first place.

In many conventional designs, a large amount of system complexity exists because the architecture has multiple overlapping partial truths — a runtime object graph, a store or model layer, a rendering layer with its own derived structures, caches remembering what changed, invalidation rules tracking who depends on whom, controller/service logic that reinterprets the same domain repeatedly. When those partial truths drift, the system needs more machinery to reconcile them.

The compiler pattern reduces that need because the source program is explicit, interaction is explicit, phase boundaries are explicit, compiled artifacts are explicit, state ownership is explicit, and recompilation is driven structurally rather than by ad hoc invalidation protocols.

### 11.1 State management frameworks

Centralized stores that become shadow architectures, action/effect plumbing, observer-heavy propagation systems, elaborate consistency protocols between multiple runtime models. In the compiler pattern, the source ASDL is the authored program, Apply computes the next source ASDL, later phases derive what should run. The state is no longer architecturally mysterious. You do not need meta-infrastructure just to answer "what is the application right now?"

### 11.2 Invalidation frameworks

Complex machinery to track what changed, what needs recomputation, what caches must be repaired. In this pattern, structural identity plus memoized boundaries handle it: unchanged nodes hit the cache, changed nodes miss it. Incrementality is not a second architecture bolted onto the first one.

### 11.3 Observer buses and event-dispatch webs

Listeners, subscriptions, bubbling systems, change-notification graphs. Much of this becomes unnecessary when inputs are modeled as Event ASDL, Apply is the explicit state transition, and later phases rederive consequences structurally. Instead of "notify everyone who might care and let them each mutate their corner," the story is: represent what happened explicitly, compute the next program, recompile the consequences.

### 11.4 Dependency-injection containers and service-locator architecture

Global service access accumulates because key functions cannot get the information they need structurally from their inputs. Service containers, DI graphs, registries passed everywhere, context objects threaded through all operations. These are often symptoms that the source model or phase structure is underspecified — missing source fields, missing resolution phases, hidden cross-references. The better fix is architectural, not infrastructural.

### 11.5 Hand-built runtime interpretation layers

Perhaps the biggest elimination: the accidental interpreter itself. Dynamic dispatch tables over variants, generic node walkers asking "what are you?" repeatedly, runtime graph traversals rediscovering semantic facts, renderer-style command systems that are really uncompiled authored trees, general callback routers deciding domain behavior on the fly. The compiler pattern consumes that uncertainty earlier. By the time execution runs, those questions should already have been answered.

### 11.6 Redundant test scaffolding

Mocks for services, fake runtime environments, setup frameworks, elaborate fixtures standing in for global state. In the pure layer, tests reduce to: construct ASDL input, call function, assert output. When such tests become difficult, something hidden is leaking into the supposedly pure layer.

### 11.7 Redundant runtime ownership machinery

External state registries, independent lifecycle managers for compiled children, detached runtime objects mirroring compiled structure. Because Units pair behavior with owned runtime state, lifecycle concerns are more often represented structurally by the Unit composition itself rather than by a second architecture.

### 11.8 The general principle

> The pattern eliminates glue whose only job was to reconnect truths that should never have been split apart.

If authored truth and semantic truth are explicitly connected by transitions, less glue. If compiled behavior and state ownership are one Unit, less glue. If change propagation is handled by identity plus memoization, less glue. If interaction is an explicit Event language, less glue.

### 11.9 What does not disappear

The pattern does not eliminate: the need for careful domain modeling, backend engineering, integration with drivers/OS/graphics/audio, operational error handling, performance work, or judgment about phase design and Unit granularity. It moves complexity to places where it is more explicit, more local, and more meaningful.

### 11.10 A warning against reintroducing the eliminated machinery

Once the pattern starts simplifying a codebase, there is a temptation to reintroduce the old furniture by habit: adding a state manager where the source ASDL should suffice, adding an observer bus where Event ASDL + Apply should suffice, adding invalidation flags where identity + memoize should suffice, adding a service container where a resolution phase should suffice, adding runtime registries where Unit composition should suffice.

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

---

## Part 13: What You Can Build

The pattern is applicable anywhere the user is editing a structured program in some domain and where repeated specialization is a better architectural fit than repeated interpretation.

The general rule: a good domain for this pattern has structured persistent domain objects with meaningful identity and relationships, interaction that changes the authored program over time, later computation that depends on derived semantic decisions, a final runtime workload that benefits from specialization, and where repeated interpretation of the full domain structure would be wasteful or architecturally messy.

### 13.1 Audio tools and synthesizers

Audio is one of the clearest fits. The domain naturally has explicit user-authored structure, graph or chain composition, stable identities for devices/clips/nodes/parameters, derived semantic phases (resolution, scheduling, coefficient computation), and a hot execution path where repeated interpretation is undesirable. Synth graphs, effects chains, modular routing, sequencers, DAWs, live performance tools.

### 13.2 Text editors and structured editors

A serious editor contains rich structure: documents, blocks, spans, cursors, selections, marks, style rules, folding state. Events edit that structure: insert, delete, move cursor, change selection, apply formatting. Later phases resolve styles, shape text, compute line layout, derive paint-ready runs, produce hit-test structures. The visual execution layer benefits from receiving something much narrower than the raw authored model. Especially compelling in structured editors where the source is richer than text.

### 13.3 UI systems and retained declarative interfaces

A retained UI tree is already very close to a source program. It contains nodes, layout declarations, visual style, content, interaction bindings, view state. Events edit it, phases resolve styles/bindings, compute layout, flatten paint operations, produce draw/hit-test Units. The same architecture that drives an audio compiler drives a UI compiler — different source vocabulary, same compilation story.

### 13.4 Spreadsheets and notebooks

Sheets, cells, formulas, charts, formatting rules. Formulas parse to expression trees, references validate into dependency graphs, evaluation IS compilation. The compiled spreadsheet doesn't interpret formulas — it runs a native function that produces all cell values. Notebooks extend this with richer cell types and execution semantics.

### 13.5 Drawing and scene editors

Shapes with transforms, styles, layers. Transforms resolve to absolute, groups flatten, bounds compute, text shapes, draw calls sort by GPU efficiency. The same compilation pipeline as UI — different source vocabulary (artistic properties vs layout properties), same draw-call terminal.

### 13.6 Protocol engines and structured communication

If a system processes structured messages through semantic phases — validate, bind, classify, route, respond — it may fit the compiler shape. Source model may be session or protocol state, events are incoming messages, phases resolve and classify, terminals produce specialized handlers.

### 13.7 Simulations and live-authored systems

Scenario editors, physics setup tools, rule-based world configuration, interactive simulations with authored entities and behaviors. Source model contains entities, relationships, parameters, scenario structure. Later phases validate references, classify behavior families, derive execution schedules, compile step/query/render Units.

### 13.8 Multi-output tools

Tools where the same source program feeds multiple outputs: execution, editor view, inspector/debugger, export/build artifacts. The architecture already assumes multiple memoized products from the same source. This is much cleaner than inventing several loosely synchronized models that each think they are the real app state.

### 13.9 The applicability test

The right question is not "is my domain like audio codegen?" The right question is:

> is my user editing a structured program whose meaning I keep rediscovering at runtime, and would it be better to compile that meaning into narrower machines?

### 13.10 What is a weaker fit

The pattern is a weaker fit when there is little or no persistent authored structure, no meaningful phase boundaries, execution is inherently generic and does not benefit from specialization, the domain is mostly ad hoc dynamic scripting with little stable semantic structure, or the cost of modeling the source language exceeds the value of the resulting clarity.

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

### 14.10 Compilation/execution split
```
□ Each function is either deciding what machine should exist or being the machine
□ Compilation-side code is pure, structural, memoized
□ Functional helpers are treated as the authoring surface of the pure layer, not as the final runtime ontology
□ Execution-side code is specialized, state-owning, operational
□ No architecture-level reasoning happens in the execution layer
□ Terminals are on the compilation side, even though they produce executable artifacts
```

### 14.11 Unit design
```
□ Each terminal's semantic product is a machine, not merely an ad hoc function
□ Each terminal produces a packaged Unit { fn, state_t }
□ state_t contains only execution-time mutable data, not authored choices
□ Bake/live split is explicit: compile-time-known → baked, runtime-mutable → state_t
□ The canonical machine (gen/param/state) is clear before packaging as Unit
□ Unit composition reflects source containment structure
```

### 14.12 Machine IR (when applicable)
```
□ Terminal input makes order, addressability, use-sites, resource identity, and state needs explicit
□ The machine receives typed shapes, not generic wiring it must interpret
□ If later branches share structure, headers carry the shared spine
□ If later branches need different aspects, facets carry orthogonal semantic planes
```

### 14.13 View / UI
```
□ View is a separate ASDL, projected from source
□ View elements carry semantic refs back to source
□ View has its own phase pipeline (Decl → Laid → Batched → Compiled)
□ Errors flow from domain pipeline to View via semantic refs
```

### 14.14 Implementation discovery (leaves-up)
```
□ Started at leaf compilers, not at top-level pipeline
□ Each leaf compiles as a clean structural transform — no reaching, no context args
□ Missing fields discovered by leaves were added to ASDL and propagated up
□ Layers above were modified to provide what leaves demanded
□ ASDL stabilized when leaves stopped demanding changes
□ Design (top-down) and implementation (bottom-up) interleaved until convergence
```

---

## Summary

```
THE MODELING METHOD

1. LIST THE NOUNS
   Everything the user sees and names.

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
   Each phase consumes decisions (eliminates sum types).
   Name the verb. If you can't name it, the phase shouldn't exist.
   Terminal phase has zero sum types.

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
    Own phase pipeline to GPU.

11. IMPLEMENT LEAVES-UP
    Start at the leaf compiler. Write the machine you want to install.
    The leaf tells you what the ASDL must provide.
    Fix the layer above. Recurse upward to the source ASDL.
    Every boundary is a pure structural transform. If it resists — fix the ASDL.

12. CONVERGE
    Steps 1-10 give a top-down draft. Step 11 tests it bottom-up.
    The ASDL expands under profiler pressure, then collapses
    as structural redundancy becomes visible (Part 8).
    The ASDL stabilizes when leaves stop demanding changes.
```

The hard part is steps 1-10. Step 11 is where the leaves either confirm the design is right or send you back to fix it. The direction is bottom-up: write the leaf you want to write, discover what it needs, modify each layer above to provide it, recurse to the source ASDL. Steps 1-10 tell you WHERE to look. Step 11 tells you WHAT to put there. When the ASDL is correct, every leaf is a natural pure structural transform and every phase transition is obvious. When it's not, the leaf resistance is the signal — and it arrives in 10 lines, not 500. The ASDL is the architecture. The leaves are the proof.

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

THE TWO LEVELS
    compilation level decides the machine; execution level runs it

THE CANONICAL LOWER STACK
    transitions
    → Machine IR
    → canonical machine: gen, param, state
    → backend lowering
    → Unit runtime: { fn, state_t }

THE LIVE SYSTEM
    poll → apply → compile → execute

THE BACKEND STORY
    LuaJIT by default
    Terra by opt-in

THE TERRA INSIGHT
    explicit types and staging are not just backend power
    they are design pressure

THE DEEPEST RULE
    the source ASDL is the architecture

THE EXECUTION RULE
    functional structure builds machines;
    machines become Units; Units run
```

> The pattern is not Terra. The pattern is domain-compilation-driven design for interactive software: the source ASDL describes a program whose meaning is progressively narrowed by transitions into Machine IR, then into a canonical machine, then through backend lowering into Unit runtime artifacts that execution runs until the source changes again. Terra is one especially powerful way to realize that architecture when explicit native control is worth the cost.
