# The Compiler Pattern — Rewrite Draft

> Working draft for the `terra-compiler-pattern.md` rewrite.
> Written section by section so the original document stays untouched until the rewrite is ready to merge.

---

## 1. Historical name, actual discovery

This architecture has historically been called the **Terra Compiler Pattern** because Terra was the environment in which the pattern first became unmistakably visible.

That historical name is understandable. Terra made several things unusually explicit all at once:

- code can be built structurally
- compile-time facts can be baked directly into generated functions
- state layout can be synthesized as native types
- the generated result can be handed to LLVM for optimization

If you discover the architecture through Terra, it is natural to describe it in Terra terms at first. Terra makes the compiler-like nature of the system hard to miss. You can see the staging boundary. You can see the native state layout. You can see that a domain description is being turned into a machine.

But the deeper discovery, and the one this rewrite needs to put at the center, is this:

> **The pattern is not fundamentally about Terra.**

That point is easy to say too quickly, so it is worth spelling out carefully.

The pattern is not:

- a Terra trick
- a Lua/Terra metaprogramming idiom
- an LLVM architecture in disguise
- a design that only makes sense when you can quote native code explicitly

The pattern is broader than that.

What the pattern actually says is:

- the user is editing a **program in a domain language**
- that program should be represented explicitly as **source ASDL**
- user input should be represented explicitly as an **Event ASDL**
- state changes should be modeled by a pure **Apply** reducer
- unresolved knowledge should be consumed across real **phases**
- phase-local structures should be realized as specialized executable **Units**
- execution should run the current Units until the source program changes again

None of that requires Terra specifically.

Terra is one way to realize the backend step. A very strong one. In some situations the strongest one available. But still just one backend.

That is the architectural reframing this document needs to make explicit.

### Why this matters

If we say "the pattern is Terra," then attention naturally drifts toward the backend first:

- how to quote code
- how to build structs
- how to talk to LLVM
- how to install native function pointers

Those are real and important questions, but they are **not the first architectural questions**.

The first architectural questions are:

- what is the user's source language?
- what are the domain nouns?
- what things have stable identity?
- what choices are real sum types?
- what knowledge should be resolved in which phase?
- what must the eventual leaf compiler know in order to emit a trivial machine?

Those questions exist before any backend decision.

So the architecture should be centered on the modeled domain and the compilation path, not on Terra itself.

### Terra revealed the pattern, but did not define it

Terra deserves a lot of credit because it made three parts of the architecture especially legible.

#### 1. Explicit staging

In Terra, the separation between:

- the compiler-side logic
- the generated program
- the runtime execution of the generated program

is unusually concrete.

You can literally build code as code. That makes the compiler structure obvious.

#### 2. Explicit native layout

In Terra, a `Unit` is not just an abstract idea. It can directly own:

- a native function
- a native struct type
- a precise ABI-facing representation of its state

That makes the `Unit { fn, state_t }` idea feel exact and operational rather than merely conceptual.

#### 3. LLVM as an explicit optimization stage

In Terra, when you narrow the program and bake decisions into the leaf, you are not merely hoping the host runtime notices the simplification. You can explicitly generate specialized native code and hand it to LLVM.

That makes the compiler framing extremely persuasive.

But there is a difference between **the environment that made the pattern obvious** and **the pattern itself**.

Terra revealed the pattern.
It did not define the only valid form of the pattern.

### The newer discovery: JIT-native runtimes already contain much of the backend compiler

The newer result in this repository is that once the architecture is factored correctly, a JIT-native runtime like LuaJIT can realize the same pattern remarkably well.

That changes the framing in an important way.

If the host runtime already provides:

- JIT compilation
- specialization on stable closure structure
- good performance on monomorphic hot loops
- efficient FFI/native-ish state access

then the backend question is no longer:

> how do we build a compiler at all?

Instead it becomes:

> how do we realize Units in a form that this host runtime can optimize aggressively?

That is a very different question.

In Terra, terminal realization is explicit:

- emit this native function
- synthesize this state type
- compile with LLVM

In LuaJIT, terminal realization is more implicit, but still real:

- produce stable specialized closures
- capture compile-time-known values as upvalues
- shape composition so traces stay simple
- represent state in a typed FFI/cdata layout the runtime can access cheaply

The crucial constraint is that the leaf must still be fully lowered. No opaque runtime tables. No ad hoc object graphs. No dynamic interpreter hiding in the callback. The typed source program must narrow all the way down to a monomorphic LuaJIT + FFI leaf, just as a Terra backend narrows all the way down to native code + native layout.

In both cases, the architectural move is the same. The difference is in the backend realization strategy.

### An illustration

Suppose the user authors a simple signal chain:

- oscillator
- gain
- biquad filter

The source question is not "should this be Terra or LuaJIT?"
The source question is:

- what is an oscillator in the user's language?
- what is a gain node?
- what is a biquad node?
- how are they connected?
- what parts are authored choices?
- what parts are derived coefficients?
- what does the final sample-processing leaf need to know?

Once those questions are answered, the backend can vary.

A Terra backend might realize the result as:

- a synthesized native state struct
- a fully specialized native sample function
- constants baked into code or struct fields
- LLVM-optimized arithmetic

A LuaJIT backend might realize the same authored program as:

- a specialized Lua closure chain
- FFI-backed state storage
- coefficients captured or stored in stable layout
- trace-optimized arithmetic over a monomorphic path

Different realization.
Same architecture.
Same authored program.
Same phase story.

That is the crucial point.

### The right architectural statement

So the document should now say, plainly:

> The so-called Terra Compiler Pattern is historically named, but the architecture itself is a backend-neutral compiler architecture for interactive software.

And more specifically:

> The core of the pattern is modeled domain data, explicit events, pure state evolution, memoized phase narrowing, and specialized executable Units.

Under that framing:

- Terra is one backend
- LuaJIT is one backend
- another host runtime could also be a backend

The app architecture does not need to change when the backend changes, as long as the backend can realize the `Unit` contract and support the live compile/execute loop.

### The practical policy that falls out of this

This reframing leads to a very practical default policy for the repository:

> **LuaJIT by default. Terra by opt-in.**

That is not a demotion of Terra. It is a clarification of its role.

LuaJIT should be the default backend on JIT-native platforms because:

- it has a much lighter deployment story
- terminal build/compile cost is dramatically cheaper
- scalar steady-state performance is highly competitive
- the same architecture applies cleanly
- the host runtime is already doing much of the backend work

But that does **not** mean LuaJIT is the permissive dynamic-tables backend. The backend contract is still strict. Pure phases remain typed ASDL + LuaFun-style transforms. Terminal leaves must lower to monomorphic LuaJIT code over typed FFI/cdata-backed state and payload layouts.

Terra then becomes the explicit strong backend when you need what only Terra gives clearly and reliably:

- explicit staging
- static native types
- exact struct synthesis
- ABI control
- LLVM optimization
- low-level native interop expressed directly in the backend

That is a better architectural split than making Terra the definition of the whole pattern.

### Key takeaway

In short:

> The pattern is not Terra. The pattern is domain-compilation-driven design for interactive software. Terra is one powerful backend realization of that pattern, and JIT-native runtimes may realize much of the same backend work with different tradeoffs.

---

## 2. What the pattern actually is

Once the historical framing is corrected, the next job is to state the pattern itself in the simplest possible way.

The pattern is a way to build interactive software by treating the software as a compiler pipeline rather than as a perpetually re-interpreted runtime object graph.

That sentence is dense, so it helps to unpack both sides.

### The conventional shape

In a conventional architecture, an interactive application is often imagined as:

- a mutable world of objects
- a set of callbacks or message handlers
- a bunch of services, registries, managers, or stores
- a rendering or execution pass that repeatedly walks the live object graph
- a growing collection of caches and invalidation rules to avoid doing too much work

The system "works" by keeping this runtime world alive and continuously asking it questions:

- what exists right now?
- what depends on what?
- what needs redraw?
- what needs recompute?
- what behavior should happen for this object?
- which code path should this variant take?

That architecture often becomes expensive in two senses at once:

1. **runtime expense** — too much dynamic branching, dispatch, and repeated interpretation
2. **design expense** — too many moving parts that must be reconciled with each other

You end up building infrastructure around the architecture just to keep the architecture manageable.

### The compiler-pattern shape

The compiler pattern takes a different view.

It says:

- the user is editing a program
- that program should be represented explicitly
- changes to that program should also be represented explicitly
- the program should be narrowed through pure phases
- the result should be turned into a specialized executable artifact
- execution should run the artifact until the program changes again

In other words, instead of treating the system as a living graph of behavior that must always be interpreted, we treat it as a source program that can be repeatedly compiled.

That is the core move.

### The six concepts

A compact way to describe the pattern is with six concepts.

#### 1. Source ASDL

This is what the program **is**.

It is the user-authored, user-visible, persistent model of the domain.

Examples:

- in a music tool: tracks, clips, devices, routings, parameters
- in an editor: document, blocks, spans, cursors, selections
- in a UI system: widgets, layout declarations, paint declarations, bindings, interaction rules
- in a spreadsheet: sheets, cells, formulas, formatting rules, charts

This is not runtime scaffolding.
It is the authored program.

#### 2. Event ASDL

This is what can **happen** to the program.

Instead of treating interaction as arbitrary callbacks, the pattern models input as a language too.

Examples:

- pointer moved
- key pressed
- node inserted
- selection changed
- parameter edited
- transport started
- file opened

Events are part of the architecture because they determine how the source program evolves.

#### 3. Apply

This is the pure reducer:

`(state, event) -> state`

The reducer does not reach into a global environment or mutate the world in place. It takes the current source ASDL plus an event and returns the next source ASDL.

That purity is not cosmetic. It is what makes:

- undo simple
- structural sharing possible
- memoization coherent
- tests trivial

If Apply is correct, state evolution becomes explicit and inspectable.

#### 4. Transitions

A transition is a pure, memoized boundary from one phase to another:

- source → resolved
- resolved → scheduled
- authored → bound
- semantic → visual
- visual → kernel payload

A transition consumes unresolved knowledge.

That phrase matters.
A real phase boundary should answer a real question.

Examples:

- resolve IDs into validated structural facts
- classify a variant into a smaller set of cases
- attach derived semantic information
- flatten a rich domain form into a leaf-oriented shape

A transition is not just "another pass." It is a point where ambiguity is reduced.

#### 5. Terminals

A terminal is a pure, memoized boundary that takes a phase-local node and produces an executable `Unit`.

This is where the architecture stops being purely descriptive and becomes operational.

The terminal should be understood in two layers:

1. it first defines the canonical machine immediately above `Unit`:
   - `gen`
   - `param`
   - `state`
2. backend realization then packages that machine as `Unit { fn, state_t }`

So the terminal says:

- this part of the program is now concrete enough
- here is the specialized machine that performs it
- here is the stable machine input it reads
- here is the runtime state ownership required to run it

Depending on backend, this may mean:

- quoted Terra function + Terra struct type
- specialized Lua closure + FFI/layout-backed state representation
- JavaScript function + object layout plan
- some other target-specific executable product

#### 6. Unit

A `Unit` is the compile product.

Conceptually:

- executable behavior
- owned runtime state layout

In shorthand:

`Unit { fn, state_t }`

The exact representation varies by backend, but the role is stable: the `Unit` is the specialized machine the compiler produced for that subtree of the program.

### The live loop

Put together, those six concepts yield the live loop:

```text
poll → apply → compile → execute
```

This loop is almost suspiciously small, so it is worth explaining each piece.

#### poll
Read an input from the outside world.

That might be:

- a UI event
- an audio/control change
- a file-system update
- a timer tick
- a network message

#### apply
Use the pure reducer to turn the current source program into the next source program.

If nothing meaningful changed, much of the structure stays identical.
If something local changed, only that subtree gets a new identity.

#### compile
Re-run the memoized transitions and terminals.

Because boundaries are pure and nodes preserve structural identity where possible, only the changed parts need to be recomputed.

This is incremental compilation, but importantly it is not a separate subsystem grafted onto the application. It falls out of the architecture.

#### execute
Run the current realized Units.

That may mean:

- call the audio callback
- draw the frame
- answer hit tests
- advance a simulation step
- process a protocol packet

The execution layer should not be re-deciding architecture-level questions. It should be running the machine that the compiler has already specialized.

### A concrete illustration: text editor

Take a text editor as an example.

In a conventional architecture, one might keep a large mutable object graph and repeatedly ask:

- what blocks are visible?
- which spans are selected?
- which style applies here?
- what layout should I compute now?
- what paint commands should I issue?

In the compiler pattern, the architecture is more explicit.

#### Source ASDL
The authored/editor state might contain:

- document
- block IDs
- span structure
- cursor or range selection
- persisted view options the user owns

#### Event ASDL
Events might contain:

- InsertText
- DeleteBackward
- MoveCursor
- SetSelection
- ToggleBold
- ScrollViewport

#### Apply
The reducer updates the document and editor state structurally.

#### Transitions
Later phases may:

- resolve style inheritance
- shape text runs
- compute line layout
- project source state into view state
- derive paint-ready rows

#### Terminal
A terminal may produce a Unit that:

- draws glyph runs for the current shaped lines
- answers hit tests against the current line boxes
- updates scroll-state-owned caches in `state_t`

The execution code is then relatively stupid in a good way. It draws what was compiled.

### A concrete illustration: synthesizer graph

The same logic applies to audio.

#### Source ASDL
The user authors:

- oscillators
- envelopes
- filters
- gain stages
- routing graph
- parameter values

#### Event ASDL
Events express:

- note on/off
- parameter automation edits
- node insertion/removal
- patch cable changes
- preset load

#### Apply
The reducer updates the patch structurally.

#### Transitions
Later phases may:

- validate references
- resolve routing
- classify node kinds
- compute coefficients
- flatten subgraphs into leaf-oriented execution forms

#### Terminal
A terminal emits the actual sample-processing Unit for the target backend.

That Unit might be Terra-native or LuaJIT-specialized, but either way the architecture is the same:

- the authored patch is the source program
- the audio machine is the compiled result

### Why this is better than "just use immutable data"

It is important not to undersell the pattern as merely "use immutable data and memoization." That description is too weak.

Many systems use immutable data and still remain interpreter-shaped. They still:

- walk generic trees every frame
- branch dynamically on variants in hot paths
- separate code generation from state ownership awkwardly
- bolt on caches after the fact
- treat runtime traversal as the real architecture

The compiler pattern is stronger than that.

Its real claim is:

> the program should be explicitly modeled as source, and its execution should be the result of repeated specialization rather than repeated interpretation.

That is a much bigger design statement.

### The role of purity

Purity matters here, but it is serving architecture, not ideology.

Why do transitions and terminals need to be pure?
Because purity ensures that:

- a subtree means the same thing everywhere it appears
- memoization is semantically sound
- tests are constructor + assertion rather than setup theatre
- incremental recompilation has clean boundaries
- errors can be attached structurally rather than handled through ambient control flow

Purity is what lets the architecture behave like a compiler instead of like a web of callbacks.

### The role of specialization

Just as important is specialization.

The point is not merely to transform data beautifully. The point is to produce machines that are easier for the backend to execute efficiently.

That means terminals should try to emit Units that are:

- monomorphic
- closed over compile-time-known facts
- structurally simple
- local in their state access
- free of avoidable dynamic dispatch

On Terra, this tends to mean quoted native code and concrete structs.
On LuaJIT, it tends to mean stable closure/code shape and cheap layout access.

Different mechanisms, same objective.

### A useful one-sentence definition

If this whole section had to collapse to one sentence, it would be this:

> The compiler pattern models interactive software as a source program plus an event language, evolves that program through a pure reducer, narrows it across memoized phases, and repeatedly realizes specialized executable Units that run until the source changes again.

That is what the pattern actually is.

### What this section should make clear before moving on

Before going deeper into ASDL design, the reader should be holding the right mental picture:

- the app is not fundamentally a live runtime object graph
- the app is fundamentally a program in a domain language
- events edit that program
- phases consume unresolved knowledge
- terminals realize specialized machines
- execution runs those machines until the program changes again

Once that picture is clear, the rest of the design rules follow much more naturally.

That is the right starting point for the rest of the document.

---

## 3. Domain-compilation-driven design

Once the pattern is understood as a compiler architecture, the next question is how one actually designs a system within it.

The answer is:

> design from the domain downward and from the leaf upward, meeting in the ASDL and the phase structure.

This section matters because it is very easy to hear "interactive software as a compiler" and then still design the application in the old way:

- start from handlers
- start from services
- start from runtime object relationships
- start from rendering APIs
- start from callback topology
- start from backend mechanisms

That path produces a system that may use some compiler words without actually being compiler-shaped.

The pattern demands a more disciplined design method.

### The wrong starting point: runtime machinery

A lot of software design begins by naming implementation furniture:

- store
- controller
- manager
- service
- registry
- renderer
- subsystem
- event bus
- dependency container

Those names may describe pieces that eventually exist somewhere, but they are almost never the right starting point for this architecture.

Why not?
Because they are descriptions of **how we imagine code will be organized**, not of **what the user is authoring**.

In the compiler pattern, architecture should begin with the authored domain.

If the first nouns in the design are things like:

- callback
- renderer state
- texture cache
- thread handle
- subscription
- service locator

then the design has almost certainly started too low.

Those may be backend details, runtime details, or operational details. They are not the source language.

### The right starting point: domain nouns

Instead, begin with the nouns the user actually sees, edits, names, saves, loads, and expects to persist.

For example:

#### In a DAW or synth tool
- track
- clip
- note
- device
- parameter
- graph
- routing
- automation lane

#### In a text editor
- document
- block
- span
- cursor
- selection
- mark
- style rule

#### In a UI system
- node
- layout rule
- visual style
- content
- interaction binding
- view state the user owns

#### In a spreadsheet
- sheet
- cell
- formula
- range
- chart
- formatting rule

Those nouns are the beginning of the architecture because they tell you what the source program is made of.

### Step 1: identify identity nouns

Not every noun is equal.
Some things are just properties of other things.
Some things are persistent objects the user thinks of as "that one."

Identity nouns usually have these properties:

- they persist across edits
- they can be independently referenced
- they can often be reordered without changing what they are
- the user can point at them conceptually
- save/load must preserve them as the same thing

Examples:

- a track in a DAW
- a widget node in a retained UI document
- a block in an editor
- a chart in a sheet
- a named parameter source

These should usually get:

- their own ASDL node
- a stable ID
- `unique` if they are concrete ASDL types in this system's vocabulary

By contrast, some things are just properties:

- a gain value on a gain node
- a text color on a style
- padding on a layout rule
- blur radius on a shadow

Those do not need independent identity unless the domain genuinely lets the user target them as standalone objects.

This distinction matters because bad identity modeling destroys incrementality.

If a thing that should have stable identity is instead identified by position, then simple reordering looks like deletion plus reinsertion. Memoization locality gets worse. Undo gets uglier. References get fragile.

### Illustration: track identity vs index

Suppose a music app stores tracks only by position in a list.

If the user moves track 5 to track 2, then from the system's perspective:

- every intervening item changed position
- many downstream paths may appear different
- references tied to index may become invalid or semantically wrong

But if tracks have stable IDs, then the change is much more truthful:

- the same tracks still exist
- only their ordering relation changed
- references remain valid
- memoized compilation can often preserve more structure

That is why domain identity is not bookkeeping. It is architectural truth.

### Step 2: identify sum types honestly

Every real domain "or" should be represented explicitly.

If the domain says:

- a clip is audio **or** MIDI
- a selection is cursor **or** range
- a widget content is text **or** image **or** custom
- overflow is visible **or** hidden **or** scroll

then the ASDL should say the same thing as an enum or tagged union.

This is one of the simplest and most important modeling rules.

When a fixed domain choice is encoded instead as:

- string tags
- loose tables
- nil-filled bags of optional fields

the cost shows up everywhere else:

- branch logic becomes ad hoc
- exhaustiveness disappears
- reducers become fragile
- transitions have to defensively rediscover the shape of the program
- terminals receive forms that are wider than they should be

By contrast, explicit sum types let the architecture say what exists clearly.

### Illustration: selection

Bad source model:

- `selection_start`
- `selection_end`
- `selection_mode = "cursor" | "range"`

Better source model:

- `Selection = Cursor(pos) | Range(anchor, focus)`

Why is the second better?
Because it reflects the domain directly. A cursor is not just a range with equal endpoints in all systems. It may participate in different invariants, interaction rules, view rules, or leaf requirements.

The sum type expresses that truth instead of forcing later code to rediscover it.

### Step 3: draw containment

After nouns and sum types, determine ownership.

Containment is the answer to the question:

> what conceptually owns what?

Examples:

- a document owns blocks
- a sheet owns cells
- a graph owns nodes
- a UI tree node owns its children
- a track may own clips

Containment matters because it heavily influences memoization locality.

If two things should evolve mostly independently, forcing them into one oversized node makes every small edit look large. If one thing truly owns another, flattening them apart too early can make local reasoning harder than it needs to be.

The best containment structure is usually the one that makes both domain sense and incremental compilation sense.

### Illustration: UI subtree locality

Suppose a UI document has a root with many child subtrees.

If editing a style on one small subtree should not disturb the others, then those subtrees should remain structurally separate long enough that:

- only one source subtree changes identity
- only one binding/lowering path misses the cache
- only one or a few terminals recompile

If instead the source model flattens everything prematurely into one large list of renderer-ish commands, then a small authored change may force widespread regeneration.

That is a modeling mistake, not just a performance problem.

### Step 4: identify coupling points

A coupling point is where separate parts of the domain need each other's information.

Examples:

- an ID reference from one node to another
- layout needing child intrinsic sizes
- style inheritance needing ancestor context
- routing validation needing global graph knowledge
- text shaping needing font resolution

Coupling points are where phase design becomes necessary.

If a source node refers to another node by ID, that is usually a sign that the source model is correct — because authored cross-references should be IDs — and that some later phase must resolve or validate that relationship.

The wrong reaction is often to smuggle live object references into the source tree or to add ambient context everywhere.

The right reaction is usually:

- keep the source honest
- add or refine a resolution phase
- attach the derived fact structurally in a later representation

### Step 5: decide what belongs in source, what belongs later, what belongs in runtime state

This is one of the most important design splits in the whole pattern.

A useful rule is:

- **independent user choice** → source ASDL
- **derived semantic knowledge** → later phase
- **compiled/native execution state** → `Unit.state_t`

That sounds simple, but it prevents a lot of category errors.

#### Source ASDL should contain
- authored choices
- stable IDs
- persistent user-visible configuration
- references by ID
- explicit variants and structure

#### Later phases should contain
- validated references
- resolved defaults
- attached semantic facts
- classified forms
- flattened leaf-oriented data

#### Runtime `state_t` should contain
- counters
- buffers
- filters' integrator history
- cached opaque native handles owned by the running machine
- mutable execution-time data that should not be saved as authored state

### Illustration: biquad coefficients

Suppose the user authors a filter node with:

- filter kind
- cutoff
- resonance

Do the numeric coefficients belong in source?
Usually no.

The user did not author them directly. They are derived.
So a good design is:

- source ASDL stores filter kind/cutoff/resonance
- a later phase computes coefficients
- the terminal either bakes or stores those coefficients as appropriate
- runtime state stores only live integrator history or mutable execution data

This split makes save/load, undo, and testing cleaner.

### Step 6: write the leaf you want to write

This is the other half of the design method.

Start asking what the terminal leaf actually needs.

For example, suppose you want to emit a paint leaf for a box.
Ask:

- does it need the style variant already resolved?
- does it need exact colors instead of theme references?
- does it need concrete pixel bounds?
- does it need clipping already attached?
- does it need blend state in a normalized form?

Or suppose you want to emit an audio leaf.
Ask:

- does it need a fixed operator kind?
- does it need coefficients precomputed?
- does it need channel count fixed?
- does it need routing flattened?
- does it need state layout known statically?

The leaf is a truth serum for the model.

When the leaf feels awkward, the diagnosis is often not "the leaf is hard" but rather:

- a required fact is missing upstream
- a phase is missing
- the source model is too vague
- a sum type has not been consumed early enough
- identity boundaries are wrong

### Illustration: leaf pressure revealing a missing phase

Imagine a UI text renderer leaf that is expected to draw glyphs.

But when you try to write it, you discover it keeps needing to:

- look up the font family
- resolve default weight/slant
- shape text on the fly
- compute wrapping decisions
- infer alignment
- discover overflow mode dynamically

That leaf is doing too much.

The correct diagnosis is probably:

- binding/resolution is incomplete
- shaping/layout phases are missing or too late
- the terminal input is still too close to authored text syntax

The fix is not to write a smarter leaf. The fix is to add the missing narrowing phases so the leaf receives a trivial, paint-ready form.

### Design is a bidirectional process

So the real design loop is:

1. model the user-facing domain honestly
2. sketch the leaf compiler you wish you had
3. notice what that leaf requires
4. revise source ASDL or insert phases until those requirements arrive naturally
5. only then implement the boundaries

This is why the pattern is not just a data-modeling exercise and not just a codegen exercise.
It is the meeting point of domain truth and leaf truth.

### Why backend-first design is dangerous

If you start from backend constraints too early, you often pollute the source model with implementation details.

Examples of bad source contamination:

- storing renderer caches in authored nodes
- storing buffer slots in source state
- storing native handles in persisted structures
- storing resolved pointers instead of IDs
- storing backend-specific layout fields the user did not author

That makes the program harder to save/load, harder to undo, harder to test, and harder to port across backends.

Backend needs are real, but they should shape the **phase path** and the **terminal input**, not the authored source vocabulary unless the user truly owns that concept.

### A good design question set

When working on a new feature, the useful questions are:

#### Domain questions
- what is the user editing?
- what persists?
- what has identity?
- what choices are sum types?
- what references other things?

#### Phase questions
- what facts are unresolved in source?
- what boundary should resolve them?
- can each phase be named with a real verb?
- does each phase reduce ambiguity?

#### Leaf questions
- what does the compiled machine actually need?
- what should be constant by then?
- what should be a field in `state_t`?
- what should have been validated already?

If those questions are answered well, implementation usually becomes straightforward.

### A full miniature example: button with shadow, hover, and click action

Take a UI button.

At the domain level, the user may own:

- button node identity
- label text
- visual style variants
- hover/press behavior declarations
- click action declaration
- layout placement

The user probably does **not** own directly:

- shaped glyph positions
- resolved font handle
- final pixel bounds
- renderer command stream
- GPU-ready batch rows

So the design might look like this.

#### Source ASDL
Contains:

- `Button(id, label, style_ref, on_click, layout, children?)`
- style references
- interaction declarations
- authored text content

#### Later phases
A binding phase may:

- resolve style refs
- attach defaulted style values
- validate action references

A layout phase may:

- compute concrete bounds
- derive content boxes

A view/render preparation phase may:

- shape label text
- derive shadow items
- flatten paint operations

#### Terminal
The terminal may then emit:

- a draw Unit for the visual subtree
- a hit-test Unit for geometry queries
- perhaps a behavior Unit for interaction routing

The important point is that the terminal receives something like:

- concrete bounds
- concrete colors
- concrete shaped text
- concrete shadow kind
- concrete hit regions

rather than raw authored declarations.

That is good design because the leaf becomes simple.

### The phrase to remember

If there is one phrase to remember from this section, it is this:

> **Design the source from the domain, and design the phases from the leaves.**

That is the method.

The source should express what the user means.
The leaves should express what the machine needs.
The phases should be the honest path between them.

### What this section should establish before moving on

Before the next section, the reader should understand that the pattern is not asking for a clever implementation technique layered onto an arbitrary model.

It is asking for a disciplined modeling process:

- find the domain nouns
- model identity and variants explicitly
- keep the source honest and minimal
- let leaf requirements reveal missing phases
- treat implementation resistance as a diagnostic about the ASDL or phase structure

Once that mindset is in place, we can talk more precisely about the strongest claim in the pattern:

> the source ASDL is the architecture.

---

## 4. The source ASDL is the architecture

This is the strongest and most easily misunderstood statement in the entire pattern.

It does **not** mean merely that the program happens to store some data structure representing state.
Almost every nontrivial application stores state somewhere.
That is not interesting by itself.

It means something much stronger:

> the source ASDL is the authoritative description of the user-facing program, and therefore it is the real architectural center of the system.

If that sentence is true, then many downstream consequences follow.
If it is false, the rest of the pattern becomes shaky or fake.

So this section is about spelling out exactly what that claim means.

### The source ASDL is not a cache of runtime facts

In many systems, "application state" is really a grab bag containing whatever happened to be useful to keep around:

- authored settings
- temporary UI state
- derived fields
- cached computations
- references to runtime objects
- backend details
- convenience flags
- maybe a few things that should actually be elsewhere

That kind of state container can still be useful operationally, but it is not a source language.

A source ASDL is different.
It is not just a bag of facts about the current runtime.
It is the **program the user is editing**.

That means it has to answer questions like:

- what did the user author?
- what should survive save/load?
- what should undo restore exactly?
- what objects exist as user-visible things?
- what choices are independent user choices versus derived consequences?

If the source tree cannot answer those questions cleanly, it is not yet the right source tree.

### Why this is an architectural statement rather than a data-modeling preference

If the source ASDL is the architecture, then the system's important structure lives in:

- the types of the authored program
- the identities of its persistent nodes
- the sum types that express domain alternatives
- the containment structure that expresses ownership
- the cross-references that express authored coupling points
- the phase boundaries that consume unresolved knowledge

That means the architecture is not primarily defined by:

- service classes
- managers
- registries
- subsystems
- dependency graphs over runtime objects
- hand-built invalidation machinery

Those things may still exist in some form, especially near backend boundaries, but they are no longer the place where the program's semantics are fundamentally organized.

The semantics live in the source model and its compilation path.

That is why a bad source ASDL poisons the system so thoroughly. If the source is wrong, then:

- reducers become awkward
- transitions become overly broad or meaningless
- terminals receive the wrong shapes
- save/load becomes lossy
- undo becomes fragile
- memoization locality worsens
- tests require hidden setup

The whole architecture bends around the wrong center.

### What must be in the source ASDL

A good source ASDL should contain the things the user actually owns.

More concretely, it should contain:

#### 1. Independent authored choices
These are choices the user can vary independently and expects to persist.

Examples:

- the text of a label
- whether overflow is clip or scroll
- which image asset a node uses
- the routing target of a graph edge
- the cutoff value on a filter
- the list/order of tracks in a project

If a change is something the user can intentionally make and expect to see again after save/load, it is a strong candidate for source.

#### 2. Stable identities for persistent things
If the user thinks of something as "that one," it likely needs a stable identity.

Examples:

- a track ID
- a node ID
- a block ID
- a sheet ID
- a binding ID

Identity should describe the thing, not its current position.

If reordering changes identity, the model is often wrong.

#### 3. Explicit sum types for real domain alternatives
Whenever the domain has a fixed set of alternatives, the source should express them directly.

Examples:

- text or image or custom content
- cursor or range selection
- row or column or stack flow
- visible or hidden or scroll overflow
- audio or MIDI clip

The source language should not make later phases infer these alternatives from informal conventions.

#### 4. Authored cross-references as IDs
If one authored thing refers to another outside containment, the reference should usually be by ID.

Examples:

- an action points to a command by ID
- a graph edge points to source/target node IDs
- a style use points to a style definition ID
- a binding points to a named resource or font ID

The source should describe relationships declaratively.
It should not embed live pointers into the authored tree.

#### 5. User-visible persisted configuration
Anything the user expects to be part of the authored document should be in source even if it also affects view or execution.

Examples:

- visual theme choices the user actually authored
- layout declarations
- default tool mode if it is saved as part of the document
- persistent presentation choices that are genuinely authored

The question is not "does this affect rendering?"
The question is "does the user own this as part of the program?"

### What should not be in the source ASDL

The source model becomes unhealthy when it starts carrying facts that belong to later phases or runtime execution.

Common examples that should usually stay **out** of source:

#### 1. Derived semantic data
Examples:

- resolved defaults
- computed coefficients
- validated target pointers
- layout boxes
- shaped glyph runs
- classification tags that can be derived from authored structure

These are real and important, but they are products of later phases, not authored truth.

#### 2. Backend scheduling data
Examples:

- buffer slots
- packed row offsets
- native handle tables
- renderer batch indices
- device-specific scheduling decisions

Those belong to later lowered forms or to runtime state.

#### 3. Native/runtime execution state
Examples:

- DSP integrator history
- mutable cursor blink timer if it belongs to the running machine rather than the authored document
- cached GPU handles
- frame-to-frame counters used only by execution
- hot runtime resources owned by a `Unit`

These belong in `Unit.state_t` or in backend-managed runtime ownership, not in the authored source.

#### 4. Live Lua object references across the authored tree
This is one of the most dangerous shortcuts.

If a source node needs another source node, the reference should usually be by ID, then resolved later.

Embedding live references in the source model makes:

- save/load harder
- undo less truthful
- tests more implicit
- structural sharing less meaningful
- cross-phase reasoning more brittle

The source should remain declarative.

### Save/load is a diagnostic

A very useful test of source quality is save/load.

Ask:

> if I serialize the source ASDL and load it again, will the user get back the same authored program?

If the answer is no, something is wrong.

Maybe an authored choice was left out of source.
Maybe the design accidentally stored an important fact only in some derived phase or runtime object.
Maybe a supposedly derived field is actually authored after all.

Save/load is not just a persistence feature. It is a truth test for the source model.

### Undo is a diagnostic too

Another excellent test is undo.

Ask:

> if I restore the previous source tree, does the system naturally recover the previous behavior without repair logic?

If undo requires custom fixups, hidden repair passes, or strange runtime reconciliation, then the source model or the phase split is probably wrong.

Why?
Because in a correct compiler-shaped design, the source tree already contains the authoritative authored truth. Returning to an old source tree should simply mean recompiling the old program.

That is one of the clearest signals that the architecture is centered correctly.

### Illustration: authored style vs resolved style

Suppose a UI node has a style reference and there is also a theme/defaulting system.

What belongs in source?
Usually things like:

- `style_ref = PrimaryButton`
- locally authored overrides
- user-owned variant choices

What does **not** usually belong in source?
Things like:

- the fully resolved fill color after theme inheritance
- the final numeric border width after defaults are applied
- the concrete font handle after asset binding

Those are later-phase facts.

Why does this matter?
Because if resolved values are stored in source, then:

- source becomes noisy and redundant
- changing a theme may force awkward source rewrites
- save/load mixes authored truth with derived consequence
- terminals cannot tell what is authored versus what was merely computed

A better architecture is:

- source stores authored style intent
- a binding/resolution phase computes resolved style
- a terminal receives only the concrete values it needs

The source remains honest and small.

### Illustration: layout boxes are not authored state

Consider a UI tree again.

The user may author:

- width policy
- height policy
- padding
- margin
- flow direction
- alignment rules

But the user usually does **not** author:

- the final pixel rectangle of every node for the current window size

Those rectangles are phase outputs.
They depend on:

- authored layout rules
- available space
- intrinsic content sizes
- perhaps current viewport or platform constraints

So a good architecture keeps:

- layout declarations in source
- solved boxes in a later phase
- execution-time draw state in the terminal/runtime layer

This keeps source portable, testable, and faithful to authorship.

### Minimal but complete

A good source ASDL is both **minimal** and **complete**.

Those words need to be held together.
If you only aim for minimality, you risk leaving out authored truth.
If you only aim for completeness, you may dump derived junk into source.

#### Minimal means:
- every source field should correspond to a real authored choice or stable authored identity
- derived facts should not be stored there just because they are convenient

#### Complete means:
- every user-reachable authored state should be representable
- save/load should preserve what the user means
- undo should restore behavior by restoring source

The best source model is not the smallest possible model.
It is the smallest model that is still fully truthful about what the user authored.

### Orthogonality matters

Another useful diagnostic is orthogonality.

Ask:

> do these fields actually vary independently in the domain?

If two fields cannot vary independently, they may not belong as separate nullable knobs on one record. They may indicate a hidden sum type.

Example:

Suppose a node has:

- `content_kind`
- `text_value?`
- `image_ref?`
- `custom_payload?`

That shape is often worse than:

- `Content = Text(...) | Image(...) | Custom(...) | None`

Why?
Because the second model expresses the domain directly and prevents impossible combinations.

Orthogonality is one of the ways the ASDL stays honest.

### Containment is part of the architecture too

When we say the source ASDL is the architecture, we also mean its containment structure is architectural.

A document that owns blocks is saying something real.
A graph that owns nodes is saying something real.
A UI tree that owns child nodes is saying something real.

Containment determines:

- local reasoning boundaries
- structural sharing boundaries
- likely memoization boundaries
- what edits are local versus global

If containment is wrong, the system often feels wrong in many downstream places at once.

### The source ASDL is the user contract

Another way to say all this is:

> the source ASDL is the contract between the user and the system.

It says:

- these are the things that exist
- these are the things you may choose
- these are the ways they are related
- these are the alternatives that are meaningful
- these are the identities that persist

Everything else in the system should respect that contract.

Transitions may narrow it.
Terminals may realize it.
Execution may run what it compiles to.
But none of those later layers get to redefine what the user's program fundamentally is.

### A practical checklist for source truth

When revising the source ASDL, useful questions are:

- if I save and load this, do I preserve all authored intent?
- if I undo, does behavior return naturally?
- does each persistent thing have stable identity?
- are domain alternatives represented as sum types rather than conventions?
- are cross-references IDs rather than live pointers?
- did I accidentally store derived or backend-specific data in source?
- is the model minimal without being lossy?
- does containment reflect real ownership and locality?

If several answers are bad, the architecture is probably drifting away from the pattern.

### The deep consequence

Once this section is taken seriously, a major consequence becomes clear:

> implementation difficulty is often a source-model problem in disguise.

When later code becomes awkward, the first suspect should often be the source ASDL:

- a missing identity noun
- an unmodeled sum type
- a bad containment boundary
- authored and derived facts mixed together
- an important persisted choice omitted from source

That is why the pattern treats ASDL revision as normal, not as failure.
The source model is not documentation after the fact. It is the architecture being discovered.

### Key takeaway

In short:

> The source ASDL is not just where the app keeps state; it is the authoritative definition of the user's program, and therefore the real center of the architecture.

Once that is clear, the next distinction becomes easier to explain:

- what belongs to the pure compilation level
- and what belongs to the specialized execution level.

---

## 5. The two levels: compilation and execution

One reason the pattern stays coherent is that it maintains a very strong distinction between two different kinds of code:

1. code that **decides what the machine should be**
2. code that **is the machine that runs**

Those are not the same thing.

A lot of architecture becomes muddy because these two levels are mixed together. The application ends up half describing the program and half executing it at the same time, with no clear boundary between the two.

The compiler pattern works best when this distinction is explicit and protected.

### Level 1: the compilation level

The compilation level is the level where the system reasons about the user's program.

This level includes:

- source ASDL
- Event ASDL
- Apply
- transitions
- projections
- terminals
- structural error collection
- scaffolding or inspection derived from the modeled program

Its characteristic properties are:

- pure
- structural
- memoized at stage boundaries
- testable by constructor + assertion
- driven by modeled data rather than ambient context

This is the level where questions get answered.

Examples:

- Which variant is this really?
- Which IDs resolve to what?
- Which defaults apply?
- What layout should be produced from these authored rules?
- What exact draw items or DSP items should exist now?
- What specialized leaf machine should be emitted for this subtree?

The compilation level is therefore the domain of:

- modeling
- narrowing
- validation
- projection
- realization planning

### Level 2: the execution level

The execution level is the level where the machine actually runs.

This level includes things like:

- a Terra function executing on native state
- a LuaJIT closure running over FFI-backed state
- a callback invoked by SDL or an audio driver
- a hit-test routine answering geometry queries
- a draw routine traversing already-lowered rows or batches

Its characteristic properties are different:

- it may be imperative internally
- it mutates only its owned runtime state
- it should not be rediscovering high-level domain semantics
- it should be specialized enough that dynamic architectural reasoning has already been consumed

The execution level is not where the app decides what exists.
It is where the compiled artifact does the work it has already been specialized to do.

### Why this split matters

This split is not about elegance for its own sake.
It is what prevents the architecture from collapsing back into interpretation.

If the execution level starts doing too much reasoning, you get symptoms like:

- repeated dynamic branching on wide sum types
- repeated lookups to resolve semantic facts that should have been attached earlier
- runtime dependency on global context objects
- mutable caches used to answer basic structural questions
- difficulty testing behavior without standing up large parts of the runtime

Those are all signs that compilation work leaked downward into execution.

Likewise, if the compilation level starts taking on too much backend/runtime machinery, you get the opposite kind of confusion:

- pure boundaries become full of mutable orchestration state
- terminals become hard to test without a live driver
- backend installation concerns contaminate ASDL → Unit logic
- phases stop reading like structural transformations and start reading like little runtimes

The health of the pattern depends on keeping the two jobs distinct.

### A simple slogan

A useful slogan is:

> **The compilation level decides. The execution level runs.**

That is the intended relationship.

### What purity means at the compilation level

The compilation level should be written in a style that is recognizably structural.

That means operations such as:

- map
- filter
- reduce/fold
- flatmap
- `U.match`
- `U.with`
- small pure constructors
- explicit error attachment / error accumulation

The goal is not to satisfy a functional-programming aesthetic. The goal is to ensure that phase boundaries behave like compiler passes.

A compiler pass should be understandable as:

- input structure in
- output structure out
- no hidden ambient dependence
- no secret stateful side channels

That is what makes memoization meaningful and design pressure visible.

### What imperative code is allowed to do

Imperative code is not banned from the system.
It is just supposed to live in the right place.

Examples of acceptable imperative behavior at the execution level:

- update filter delay elements in runtime state
- increment frame counters owned by the running machine
- push pixels to a backend API
- call SDL/GL/TTF/native APIs from emitted or installed code
- mutate an allocated state struct during a callback

What is not acceptable is smuggling architecture-level reasoning into that imperative code.

For example, the execution layer should not be where we repeatedly decide:

- which domain variant something is
- whether a reference is valid
- which layout policy applies
- which semantic defaults should be attached
- how a wide authored form should be interpreted this frame

Those questions belong upstream.

### Illustration: text layout

Consider text rendering again.

A healthy split looks like this.

#### Compilation level
- resolve font choice
- attach concrete style defaults
- shape text
- compute line breaks
- derive positioned glyph runs
- produce draw-ready rows/items
- terminal emits a Unit specialized for those rows/items

#### Execution level
- iterate the already-shaped runs
- read glyph positions
- issue drawing operations
- update only local runtime state if needed

An unhealthy split would leave the execution layer to repeatedly:

- choose a font
- discover wrap mode
- resolve alignment
- shape text on the fly
- compute line layout every frame for the same unchanged subtree

That is interpreter-shaped execution sneaking back in.

### Illustration: audio filter node

A healthy split for a biquad filter might be:

#### Compilation level
- read authored filter type and parameter expressions
- resolve channel topology
- compute coefficients or coefficient expressions in the correct phase
- emit a leaf whose body is fixed to the concrete filter kind
- define a `state_t` that owns only live integrator history and related runtime state

#### Execution level
- read sample input
- update state history
- run the fixed arithmetic path

An unhealthy split would have the runtime callback repeatedly asking:

- what kind of filter is this?
- how many channels does it have?
- where do I look up my coefficients?
- which code path should apply for this authored node variant?

That is compilation work happening too late.

### Terminals are on the compilation side

This point is worth emphasizing because it is easy to get wrong.

Even though terminals produce executable artifacts, terminals themselves are still part of the **compilation level**.

A terminal is a pure function from phase-local data to a `Unit`.

That means:

- the terminal should remain structural and testable
- the terminal should not itself depend on a hidden live runtime
- backend API details should be encapsulated in the produced `Unit` and its installation path, not leaked into the terminal's semantic input model

This is especially important when the backend is low-level.

For example, if a Terra leaf will eventually call into SDL or perform low-level buffer writes, that does **not** mean the Lua-side terminal that builds the leaf gets to become an imperative mess. The terminal is still compiler-side code.

Likewise in LuaJIT, if the produced closure will mutate FFI state quickly at runtime, that does **not** justify writing the boundary from ASDL to `Unit` as an ad hoc runtime framework.

Compiler-side code should stay compiler-shaped.

### Runtime state belongs to the Unit

The distinction between levels is also why runtime state should belong to the `Unit` rather than being managed externally in generic architecture objects.

Why?
Because execution state is part of what the machine needs in order to run, and different compiled machines may own different state layouts.

That leads naturally to the pattern's `Unit { fn, state_t }` idea:

- `fn` describes behavior
- `state_t` describes owned runtime state

The compilation level chooses this pairing.
The execution level operates on it.

This is cleaner than splitting those concerns across:

- a code generator over here
- a state manager over there
- a runtime registry elsewhere

The Unit keeps execution ownership structurally coupled to compiled behavior.

### Error handling differs by level

Another benefit of the split is that error handling becomes more sensible.

At the compilation level, many errors are best treated structurally:

- missing reference
- unknown asset
- invalid authored combination
- unsupported leaf combination for a backend

These can often be attached to the relevant subtree, collected, and sometimes replaced with neutral fallback behavior so unaffected siblings still compile.

At the execution level, the notion of an error is different.
There it is more about:

- runtime backend failure
- device failure
- driver unavailability
- callback environment issues
- hard execution faults

Mixing these two kinds of error handling often leads to poor design.

The compilation level wants structural, local, explainable failure.
The execution level wants robust operational handling.

### Testing differs by level too

The split also clarifies testing.

#### Compilation-level tests
These should usually look like:

1. construct ASDL input
2. call reducer/transition/terminal/projection
3. assert output

These tests should not need mocks, containers, or elaborate runtime setup unless a boundary is incorrectly designed.

#### Execution-level tests
These may involve:

- smoke tests
- benchmark harnesses
- backend integration checks
- driver-level behavior checks
- profiling and latency measurements

Both kinds of tests matter, but they are testing different things.

### A common mistake: letting convenience erase the boundary

It is tempting to erode this distinction for convenience.
For example:

- "I'll just look this up at runtime instead of adding a phase"
- "I'll keep a global context to make terminal construction easier"
- "I'll store this derived layout back into source so I don't have to recompute it cleanly"
- "I'll let the callback handle multiple authored variants directly"

These may feel expedient in the moment, but they slowly reintroduce exactly the kind of accidental interpreter the pattern is designed to eliminate.

The compilation/execution split is therefore not a luxury. It is one of the main guardrails keeping the system honest.

### Backend neutrality depends on this split

This distinction is also what makes backend neutrality possible.

The compilation level is where most of the application's meaning lives:

- modeled source
- event handling
- transitions
- projections
- terminal design

If that layer stays pure and structural, then different backends can realize the resulting Units differently without forcing a redesign of the application itself.

If instead the compilation layer is full of backend-specific runtime assumptions, then the architecture stops being portable across backends.

So backend-neutrality is not just a matter of abstract interfaces. It depends on preserving the compilation/execution distinction in practice.

### The practical question to ask

When writing any function in this pattern, a useful question is:

> is this function still deciding what machine should exist, or is it part of the machine that runs?

If the answer is the former, it should probably be:

- pure
- structural
- phase-local
- testable with constructors and assertions

If the answer is the latter, it should probably be:

- specialized
- state-owning
- operational
- narrow in responsibility

That question alone catches many design mistakes.

### Key takeaway

In short:

> The compilation level decides what the machine is; the execution level runs that machine. When those two levels are kept distinct, the architecture stays compiler-shaped instead of collapsing back into runtime interpretation.

With that distinction in place, we can now explain the central artifact that connects the two levels:

- the `Unit`.

---

## 6. Unit: the compile product

If the source ASDL is the authored program, and the compilation level is the part of the system that decides what machine should exist, then the obvious next question is:

> what exactly is the thing that compilation produces?

In this pattern, the answer is:

> a `Unit`

The `Unit` is the central executable artifact of the architecture.
It is the thing terminals produce.
It is the thing composition builds upward.
It is the thing execution installs and runs.
It is the thing hot swap replaces when the source program changes.

That makes `Unit` one of the most important concepts to understand clearly.

### A simple definition

A `Unit` is the pairing of:

- executable behavior
- owned runtime state layout

In shorthand, the repository has traditionally described that as something like:

```lua
Unit {
    fn,
    state_t,
}
```

That compact representation is deceptively powerful.
It says that code generation and runtime state ownership are not separate architectural concerns. They are one compiled artifact.

That is one of the places where this pattern is stronger than many conventional designs.

### Why behavior and state should be paired

A lot of systems separate these concerns awkwardly:

- one subsystem decides behavior
- another owns mutable runtime state
- another decides installation/lifecycle
- another knows how children are aggregated

Once those responsibilities are pulled apart, additional machinery usually appears to glue them back together:

- state registries
- lifecycle managers
- dependency containers
- callback tables
- runtime dispatch objects
- custom ownership protocols

The `Unit` idea avoids much of that by saying:

- if a machine exists, it knows the state it needs
- if a parent machine contains child machines, that containment should be represented structurally
- if a compiled artifact is swapped, its associated state ownership model should be explicit too

The behavior is not abstracted away from the state shape that makes it runnable.
The two belong together.

### What a leaf Unit means

At the leaf level, a `Unit` is often easiest to understand.

Take a simple audio leaf such as a gain stage.
The user authored some node that eventually narrows to something like:

- multiply input by constant gain
- maybe keep a tiny bit of runtime state if smoothing is needed

A leaf terminal can then produce a `Unit` whose meaning is:

- `fn`: the specialized sample-processing function for this gain stage
- `state_t`: the runtime state layout required by that exact function

If the gain is fully static and no mutable state is needed, `state_t` may be trivial.
If smoothing or envelope-following is required, `state_t` may own those mutable fields.

The same applies to a UI leaf.
A terminal for a draw-ready box or shaped text run can produce a `Unit` whose meaning is:

- `fn`: the specialized routine that draws or answers queries for that already-lowered form
- `state_t`: only the mutable execution-time state that routine actually owns

In both cases, the compiled machine is not "code over here plus some external state manager elsewhere." It is one artifact.

### What a composed Unit means

The idea becomes even more important above the leaf level.

A parent node in the program often contains child subprograms.
That structural relationship should be reflected in the compiled output.

So if child subtrees each compile to their own `Unit`s, a parent can produce a larger `Unit` that composes them.

Conceptually, composition means:

- the parent owns child behavior structurally
- the parent owns child state structurally
- the parent execution path knows how to invoke child execution paths in the correct arrangement

This is why `U.compose` is such a central operation in the pattern.
It is not just concatenation. It is structural aggregation of executable artifacts.

### Illustration: UI subtree composition

Suppose a UI node has three children:

- background box
- text label
- icon

Each child might compile to its own `Unit`.
The parent's compiled `Unit` might then:

- run the background child
- run the text child
- run the icon child
- perhaps own parent-local execution state if needed

The parent's `state_t` should then structurally include the state required by each child Unit, plus any parent-local state.

The exact realization depends on backend, but the architectural meaning is the same:

- composition in the source tree becomes composition in the compiled artifact

That is much cleaner than flattening everything into unrelated runtime objects and then trying to reconstruct structural ownership later.

### Illustration: audio chain composition

Consider a signal chain:

- oscillator
- filter
- gain

Each stage may compile to a leaf Unit.
A composed Unit for the whole chain might:

- run oscillator code
- feed its result into filter code
- feed that into gain code
- own one structural runtime state layout containing the state required by all three

Again, the important point is not only that behavior is composed, but that state ownership is composed in the same structural way.

This is where the architecture gets a lot of its simplicity.

### The Unit boundary is where specialization becomes operational

Upstream of the terminal, phases are still descriptive.
They narrow, resolve, validate, classify, and lower.

At the `Unit` boundary, something stronger happens:

- a concrete executable form is chosen
- a concrete runtime state ownership model is chosen
- the subtree stops being only a data description and becomes an installable machine

That is why the Unit boundary feels like a real threshold in the architecture.
Before it, we are still describing what should happen.
After it, we have something that can run.

### Backend-neutral meaning, backend-specific realization

The repository now has a much clearer story here than before.
The meaning of `Unit` is backend-neutral, even though its realization is not.

#### Backend-neutral contract

A `Unit` always means:

- here is the specialized behavior for this subtree
- here is the runtime state layout this behavior owns
- here is the structurally composable executable artifact for this phase-local node

#### Terra realization

On Terra, that usually means something close to:

- `fn` is a Terra function
- `state_t` is a Terra type
- `compose` synthesizes a larger Terra struct type from child state types
- installation may involve native pointers and explicit compiled code objects

This is the most explicit realization of the idea.

#### LuaJIT realization

On LuaJIT, that should mean something just as strict in architectural terms:

- `fn` is a specialized monomorphic Lua function
- `state_t` is a typed FFI/cdata-backed layout
- `compose` creates a structural typed state arrangement that child functions access predictably
- installation/hot-swap uses the host runtime rather than an explicit LLVM-native pipeline

The important point is that LuaJIT is **not** the permissive dynamic-tables backend.
The same Unit contract still applies.
The same type pressure still applies.
The types are not ornamental metadata around the runtime; they are the runtime shape that the compiled function actually executes over.

So the intended split is:

- pure phases operate on ASDL-defined typed values
- LuaJIT leaves operate on backend-native typed FFI layouts
- no opaque runtime tables belong in the designed execution model

This is a different realization, but still the same architectural role.
That is exactly why the backend-neutral reframing works.
The Unit contract survives the backend change.

### Why `Unit` is better than "just a function"

It may be tempting to think of the terminal result as simply "a function to call." But that is too weak.

A plain function does not necessarily tell you:

- what runtime state it owns
- how that state should be allocated
- how child state should compose into parent state
- what the lifecycle of that state is
- how hot swap should treat state compatibility

The `Unit` concept is richer because it keeps the state ABI and the executable behavior coupled.

That is especially important in a system built around repeated recompilation.
If the compiled artifact changes, the state ownership model may change too, and the architecture should represent that explicitly.

### Why `Unit` is better than "codegen output plus external runtime object"

Another common alternative is to generate code but keep runtime state in a separate object system.
That usually leads to one of two outcomes:

1. the codegen is not really in charge of the running machine
2. the runtime object layer becomes a shadow architecture competing with the source ASDL

The pattern avoids that split.
A `Unit` says:

- the compiled machine owns its runtime state contract
- composition owns child state structurally
- the runtime object graph does not need to be the real architecture

That is one of the key eliminations this pattern offers.

### Unit composition and locality

Because Units compose structurally, they also give the architecture a natural locality story.

If a source subtree is unchanged, then ideally:

- its terminal hits the memoize cache
- its Unit can be reused
- the parent composition may also be reused or partially reused depending on identity structure
- runtime installation can often remain stable or cheaply updated

This is another reason Units are not just outputs. They are the granularity at which the compiled system retains structure.

### Hot swap makes more sense with Units

Hot swap becomes conceptually simple when the compile output is a Unit.

The story is:

- source subtree changes
- affected transitions/terminals re-run
- a new Unit is produced for the changed region
- the installed machine swaps to the new behavior/state contract as needed

You do not need a separate conceptual model for "the live thing" versus "the compiled thing." The Unit is the live-eligible compiled thing.

This is one reason pointer-swap or slot-swap style installation can remain so simple in the architecture.

### What belongs inside `state_t`

A Unit's `state_t` should contain the runtime data needed by execution, not whatever happened to be convenient.

Good examples:

- integrator history for filters
- mutable counters owned by the machine
- parent-owned child state aggregation
- cached runtime handles that are truly execution ownership rather than authored truth
- temporary execution-time fields that should persist only as long as the machine does

Poor examples for `state_t` would be things that really belong in source or in a derived phase representation, such as:

- authored parameter choices
- unresolved references
- derived semantic facts that should have been attached structurally before terminalization

The Unit boundary should be reached only after the machine's semantic shape is sufficiently concrete.

### The canonical machine above `Unit`

`Unit { fn, state_t }` is the packaged runtime artifact, but it is not the first machine concept.
The canonical machine layer immediately above that packaging is:

- `gen` = the execution rule / code-shaping part
- `param` = the stable machine input it reads
- `state` = the mutable runtime-owned state it preserves

This is not an optional explanatory trick. It is the right way to think about terminal design in this pattern.
Many terminal design mistakes come from compressing those three questions too early.
A leaf may look awkward not because `Unit` is the wrong contract, but because the phase above it is not making `gen`, `param`, and `state` obvious enough.

A good Machine IR above that canonical machine is therefore not just "more data". It should be understood as the **typed machine-feeding layer** that makes the machine's compiled wiring explicit.

In practical terms, a good Machine IR should answer five things directly:

1. **order**
   - what loops exist?
   - what spans or ranges are executed?
   - what headers determine one execution slice?

2. **addressability**
   - how does execution reach what it needs?
   - what refs, slots, indices, or handles are already resolved?

3. **use-sites**
   - what concrete occurrences are executed?
   - what instances of drawing, querying, routing, or processing exist?

4. **resource identity**
   - what realizable resources may need runtime ownership?
   - what stable resource specifications identify them?

5. **runtime ownership requirements**
   - what mutable runtime state must persist?
   - what state schema does the machine require?

That is a more useful way to think about Machine IR than calling it merely a planning layer or a packed payload. Its job is to make `gen`, `param`, and `state` trivial to derive by making machine-facing order, access, instances, resource identity, and state needs explicit.

That does **not** mean introducing a generic interpreted wiring DSL. The pattern should not devolve into runtime nodes like `Accessor(kind, ...)`, `Processor(kind, ...)`, or `Emitter(kind, ...)` that execution must interpret dynamically. That would simply recreate the accidental interpreter at a different layer.

Instead, the wiring should already have been compiled into ordinary typed shapes the machine can consume directly, such as:

- spans and ranges
- headers and closed dispatch records
- slot/index refs
- instance/use-site records
- resource specifications
- runtime state schemas

### The header pattern

One especially important consequence of this machine-feeding view is the **header pattern**.

When several later branches must remain aligned after a shared flattening or topology-establishing phase, it is often a mistake to keep widening one giant node record just so every later branch can still find the same thing.

A better design is often:

1. define a **shared structural header vocabulary**
2. let later branches carry only their own orthogonal fact planes
3. rejoin those branches structurally through the shared header/index space rather than through semantic lookup

In this pattern, a header is not just metadata.
It is a typed structural carrier for truths such as:

- stable identity
- parent/child topology
- subtree spans
- region-local index space
- whatever minimal structural alignment later branches must share

And the key discipline is:

> keep shared structure in the header spine; keep branch-specific meaning in separate fact planes.

This matters because many bad lower designs come from failing to separate those two roles.
Without a header spine, there is constant pressure to build oversized lower nodes that carry:

- geometry facts
- render facts
- query facts
- accessibility facts
- routing facts
- resource facts

all together, merely so later phases can still line them up.

That usually creates exactly the kinds of problems the pattern is trying to eliminate:

- broad node records that rebuild too much
- hidden coupling between branches
- expensive late splitting
- repeated rediscovery of alignment
- temptation to rejoin branches by ID search or tree walking

The header pattern gives a better alternative.
A shared flattening phase can establish one canonical structural spine, and then later phases can branch into orthogonal planes while still remaining joinable by construction.

For example, after a shared flat phase, several later branches might all reuse the same region/node header vocabulary while carrying different facts:

- one branch carries geometry input facts
- one branch carries render-specific facts
- one branch carries query-specific facts
- one later phase carries solved geometry

The later projections can then rejoin by shared region-local index rather than by rediscovering semantic relationships.

This is both a modeling improvement and a performance improvement.
It is a modeling improvement because it forces you to ask a sharper question:

> what truths are genuinely shared structure, and what truths are branch-local facts?

And it is a performance improvement because, with the right ASDL, joins become structural and memo-friendly by construction.
You do not need extra lookup machinery merely to reconnect truths that should have shared a structural spine from the start.

This also changes how flattening should be understood.
Flattening is not only a way to make later execution faster.
It is often the moment where you establish the shared structural header spine for multiple later branches.

That means header design is an ASDL question, not an implementation afterthought.
A good header vocabulary can make later branches local, orthogonal, and cheaply joinable.
A bad or missing header vocabulary can force the system back toward giant mixed nodes or ad hoc runtime join logic.

The practical test is:

> if several later branches need the same structural identity/topology but different semantic facts, should there be one shared header spine instead of one wider node type?

Very often, the answer is yes.

In that sense, the header pattern is one of the main ways the compiler pattern turns "multiple derived views of the same structure" into typed, local, memo-friendly phases instead of into an accidental interpreted graph.

### The facet pattern

The header pattern naturally leads to a second design pattern: the **facet pattern**.

If the header spine carries the shared structural truth, then the next question is:

> what different aspects of meaning are attached to that shared structure, and which later consumers actually need which aspects?

A facet is one orthogonal semantic plane aligned to the shared header/index space.

Typical examples are things like:

- layout facts
- paint facts
- content facts
- behavior facts
- accessibility facts

So instead of widening one lower node record until it carries everything:

- identity
- topology
- geometry facts
- render facts
- query facts
- accessibility facts

all together, a better design is often:

1. one shared header spine
2. several aligned facet planes
3. branch-specific lowerings that consume only the facets they actually need

In that shape:

- the header answers **what thing is this in the shared structure?**
- the facet answers **what aspect of that thing are we talking about?**

This is an important ASDL design shift.
It means lower design should often stop thinking in terms of "one node, but with more fields" and start thinking in terms of:

- shared structural spine
- orthogonal semantic facets
- branch-specific consumers

This matters because many bad lower designs come from bundling concerns that do not need to travel together.
For example:

- geometry solve does not usually need paint facts
- render lowering does not usually need key-route facts
- query lowering does not usually need brush and image resource identity
- accessibility often does not need to travel with render semantics at all

If those concerns are forced into one lower node anyway, the result is usually:

- oversized records
- broad rebuilds
- hidden coupling between branches
- late splitting work
- repeated recomputation of things that should have stayed orthogonal

The facet pattern gives a cleaner alternative.
Once a shared flattening phase has established the structural spine, later phases can preserve orthogonality by carrying aligned facet planes and lowering each branch from the facets it truly needs.

For example, one branch might consume:

- header + layout facet + part of content facet

while another consumes:

- header + paint facet + part of content facet

and another consumes:

- header + behavior facet + accessibility facet

That is often a much better design than forcing all of those concerns through a single mixed lower node.

This is also a performance pattern.
With the right facet split:

- each lowering phase does less semantic work
- unrelated edits stay more local
- memoization boundaries stay cleaner
- joins remain structural through the shared header/index space
- the system does less work by construction

So the facet pattern is not only an implementation convenience.
It is one of the ways ASDL design can directly enforce orthogonality, locality, and incremental performance.

The practical test is:

> if several later consumers share the same structure but need different semantic aspects, should those aspects become aligned facet planes instead of one wider lower node?

Very often, the answer is yes.

In that sense, the facet pattern is the semantic companion to the header pattern:

- **headers** carry shared structural truth
- **facets** carry orthogonal semantic truth

Together, they give a powerful way to design lower ASDL that stays local, branchable, and machine-friendly without collapsing back into a giant interpreted node graph.

In that sense, "querying" still belongs above execution — but only after it has been compiled into typed access paths. Good querying here means:

- read slot `i`
- read span `[start, count]`
- read pre-resolved clip/index/resource refs

Not:

- search the world
- walk a tree looking for meaning
- chase IDs at runtime
- rediscover semantic structure in the hot path

This is the practical test for Machine IR and terminal input design:

> does the machine receive explicit order, addressability, use-sites, resource identity, and persistent state needs — or does it still have to invent them while running?

If it still has to invent them, the ASDL and phase structure above the terminal are still too high-level.

### Leaf-driven constraints show up here clearly

The pattern's advice to "write the leaf you want to write" is especially visible at the Unit boundary.

When designing a terminal, ask:

- what exact function shape should exist?
- what exact runtime state does it need?
- what data should be baked in?
- what data should remain live in state?
- what ambiguities should already be eliminated before I build this Unit?

If the answers are unclear, then the problem is often upstream.

The Unit boundary exposes missing modeling work mercilessly. That is a feature, not a flaw.

### Errors and fallback at the Unit boundary

The Unit boundary is also where structural error handling becomes especially useful.

Suppose a subtree cannot be compiled cleanly because:

- an asset is missing
- a reference is invalid
- a backend does not support some requested form yet

A good architecture can often:

- attach an error to that subtree
- produce a neutral fallback Unit if appropriate
- continue compiling unaffected siblings

That keeps the compiler structure local and resilient.

For example:

- a missing image may compile to a placeholder visual Unit
- an unsupported effect may compile to a no-op Unit plus an attached error
- an invalid reference may compile to silence or neutral behavior in an audio subtree if that is semantically acceptable

This is much cleaner than turning one subtree problem into a global runtime failure by default.

### The Unit is the handoff artifact between levels

Another useful way to think about `Unit` is this:

- above the Unit boundary, the system speaks in ASDL and phase-local data
- at the Unit boundary, the system speaks in compiled artifacts
- below the Unit boundary, the system speaks in installed machine behavior and owned runtime state

So the Unit is the handoff artifact between compilation and execution.

That is why it is so central.

### Key takeaway

In short:

> A `Unit` is the compiled machine for a subtree: it pairs specialized behavior with the runtime state layout that behavior owns, and it composes structurally in the same way the source program composes structurally.

With the Unit made explicit, the next piece becomes easier to explain operationally:

- the live loop that keeps recompiling and running the program.

---

## 7. The live loop

One of the striking things about the pattern is how small the live loop is once the architecture is aligned properly.

In its simplest form, it is just:

```text
poll → apply → compile → execute
```

That compactness can make it look simplistic at first glance, as if important operational detail must be hiding somewhere else.
But the whole point of the architecture is that much of the usual "somewhere else" has been dissolved into the modeled source, the phase structure, and the Unit boundary.

So the live loop is small not because the system is naive, but because the architecture has pushed the right complexity into the right place.

This section explains why that loop is enough, what each step means, and how hot swap and incremental recompilation fit into it.

### Why the loop is so small

Traditional interactive systems often accumulate a much larger conceptual loop:

- poll events
- update controllers
- notify observers
- invalidate views
- reconcile data stores
- schedule layout
- rebuild command lists
- update services
- propagate changes
- redraw
- maybe rebuild caches
- maybe diff a runtime object graph
- maybe synchronize with a secondary model

Each of those steps often exists because the architecture has multiple partially overlapping "sources of truth" and needs machinery to keep them in sync.

The compiler pattern tries to remove that multiplicity.

There is one authored program.
Events transform it.
Compilation derives what should run.
Execution runs it.

That is why the loop can stay conceptually tight.

### Step 1: poll

`poll` means: receive an input from the outside world.

Depending on the application, this might be:

- pointer motion
- mouse button press or release
- key input
- window resize
- audio/control input
- timer tick
- file change notification
- network packet
- transport state change
- user command invocation

In the pattern, the key design decision is that these are not just arbitrary callbacks flying into random runtime objects.
They should be representable as an Event ASDL.

That means the outside world is translated into a structured input language.

This is a major simplification because it turns "everything that can happen" into a modeled set of cases.
The rest of the application can then reason about those cases structurally rather than through ad hoc callback topology.

### Illustration: UI polling

In a UI application, the platform might produce raw events like:

- SDL mouse move
- SDL mouse down
- SDL mouse up
- SDL wheel scroll
- SDL text input
- SDL key press
- window expose
- resize

A platform layer can normalize those into an Event ASDL such as:

- `PointerMoved(x, y)`
- `PointerPressed(button, x, y)`
- `PointerReleased(button, x, y)`
- `WheelScrolled(dx, dy)`
- `TextEntered(text)`
- `KeyDown(key, modifiers)`
- `WindowResized(w, h)`
- `Quit()`

That normalized event language becomes the input to Apply.

### Step 2: apply

`apply` means: take the current source program and the next event and compute the next source program.

In other words:

```text
(state, event) -> state
```

This is the reducer step.

The reducer should be pure.
It should not mutate ambient runtime objects or depend on hidden state if that can be avoided. It should take the current authored/program state and return the next one.

Why is that so important?
Because once Apply is pure:

- undo is naturally representable as returning to an older tree
- memoization can rely on structural identity
- tests become straightforward
- state evolution is inspectable and reproducible
- there is no mystery about where changes came from

### What Apply is actually doing

Apply is not just "updating app state" in a generic sense.
In this architecture, it is editing the source program.

That is a subtle but important difference.

If the user clicks a button, types text, moves a node, changes a filter parameter, or scrolls a view, Apply is not merely tweaking a runtime bag of fields. It is computing the next version of the program the system should compile and run.

That framing changes the design of interaction.

### Illustration: typed text in an editor

Suppose the user types the letter `a`.

A conventional system may think:

- callback fires
- editor controller mutates buffer object
- view maybe invalidates some region
- text layout cache maybe updates

The compiler-pattern view is:

- poll yields `InsertText("a")`
- Apply returns a new source tree with updated document and selection
- compilation reuses everything it can and recomputes only affected derived forms
- execution runs the updated Units

The same user action happened, but the architecture is now explicit and compiler-shaped.

### Structural sharing matters here

Apply should preserve structural sharing for unchanged parts of the tree.

That means:

- if only one subtree changed, sibling subtrees should ideally retain identity
- if only one parameter changed, unrelated branches should stay structurally identical
- if a reorder preserves item identity, nodes should not be recreated gratuitously

This matters because `compile` depends on the resulting identity story.
If Apply destroys structural locality, the compiler loses much of its incrementality.

So Apply is not just semantically important. It is also the front door to memoization locality.

### Step 3: compile

`compile` means: re-run the memoized transitions and terminals over the current source program.

At first this may sound expensive. In a naive design, recompiling everything after every change would indeed be too costly.

But the whole point of the pattern is that:

- boundaries are pure
- nodes preserve identity where unchanged
- transitions and terminals are memoized

So "compile" does not usually mean "rebuild the entire world from scratch in the expensive sense."
It means:

- walk the structure of the current program
- reuse previous transition/terminal results where identities still match
- recompute only along changed paths
- produce updated Units where necessary

This is incremental compilation as a direct consequence of architecture rather than as a bolt-on subsystem.

### What gets recompiled

What gets recompiled depends on the change.

Examples:

- changing a button label may require re-shaping just that text subtree and perhaps re-solving some layout above it
- changing a track routing may require re-resolving one part of an audio graph and recompiling affected Units downstream
- toggling a style may affect one visual subtree and any dependent layout if size changed
- resizing a window may preserve authored source entirely but change some later projection or layout phase that depends on viewport constraints

The important point is that the pattern gives a principled place for each of these effects to happen.
It is not all shoved into one generic invalidation bucket.

### Compilation may mean more than one pipeline

It is also important to notice that "compile" is not necessarily one single linear pipeline in all applications.

The same source program may feed multiple derived products, for example:

- execution Units
- view projections
- inspection/scaffolding structures
- error reports
- hit-test structures

These can all be understood as memoized pure products derived from the same source tree, possibly through different phase paths.

For example, in a UI system you may have at least two distinct compilation products:

- one path producing draw/hit-test Units
- another path producing an inspector tree or editor-facing debug projection

Both are compiler products, but they need not be the same phase chain.

### Step 4: execute

`execute` means: run the currently realized machine.

What this means depends on the domain.

Examples:

- in audio: call the current callback/function over the current runtime state
- in UI: draw the current frame and answer current queries
- in a simulation: run the current step machine
- in a protocol engine: process current events with the current compiled handler structure

Execution should be narrow.
It should not be re-deciding domain architecture on the fly.

Ideally, by the time execution happens:

- variants are already narrowed enough
- references are already resolved enough
- layout/semantic questions are already answered enough
- the runtime loop is mostly doing arithmetic, pointer/state updates, or tight structural traversal over lowered forms

That is what makes the system feel compiled rather than interpreted.

### The loop is continuous, not one-shot

This is not a traditional ahead-of-time compiler where the program is compiled once and then run forever.
The program is alive.
The user keeps editing it.
So the system repeats:

1. receive new event
2. derive new source program
3. recompile affected parts
4. keep running the new machine

That is why the pattern is so suitable for interactive software.
It treats interaction as editing a live program.

### Hot swap is the natural execution story

A major strength of the pattern is that hot swap becomes a natural operation rather than a special subsystem.

The story is straightforward:

- the previous source program compiled to some installed Units
- a new event changes the source
- affected subtrees recompile to new Units
- the runtime installs or swaps those Units
- execution continues using the new machine

The architectural reason this works is that the Unit is already the runtime-relevant compiled artifact.
There is no need to invent a second conceptual layer called "live object behavior" that must somehow be synchronized with compilation output.

### Illustration: swap in an audio callback

Consider a running audio engine.
A user tweaks a filter parameter or inserts a new device.

A conventional design may rely on:

- runtime graph mutation
- lock-sensitive shared structures
- indirect dispatch through live nodes
- careful cache invalidation

In the compiler pattern, the conceptual story is simpler:

- Apply returns a new authored graph
- affected phases recompute derived forms
- the terminal emits a new Unit for the changed region or full graph, depending on granularity
- a hot slot / installed pointer swaps to the new function and associated state contract
- the callback continues against the new compiled machine

The implementation details can still be serious, especially for realtime constraints, but the architecture remains clear.

### Illustration: swap in a UI tree

The same story works for UI.
A user action changes the document or view state.

Then:

- source tree changes
- binding/layout/render-prep phases rerun where needed
- affected visual/hit-test Units are re-realized
- the next frame executes the new machine

No giant runtime object graph has to be consulted every frame to rediscover what the UI means. The UI meaning was already recompiled.

### Why this eliminates much invalidation machinery

The live loop explains why the pattern can eliminate so much traditional invalidation infrastructure.

In many systems, invalidation exists because the system needs to remember which parts of a live interpreted world need to be reconsidered.

Here, the answer is more direct:

- Apply produces a new source tree
- structural identity says what changed
- memoized compilation reuses the rest

Invalidation is not a separate architecture. It is mostly implicit in identity and memoize boundaries.

That does not mean no operational bookkeeping exists anywhere, but it does mean the architecture no longer revolves around invalidation graphs and repair protocols.

### Not all steps must happen at the same rate

Another useful clarification is that the conceptual loop does not require every stage to run at exactly the same cadence.

For example:

- events may arrive irregularly
- Apply may run per event
- compile may run only after a batch of events or once per frame
- execute may run on a steady audio callback cadence or render cadence

The important point is the logical relationship, not a rigid lockstep implementation.

The machine being executed should correspond to some coherent compiled view of source.
When source changes enough to matter, compilation eventually produces a new machine.

### The loop can include multiple targets

Because the target backend can be treated as another input to compilation, the same source change may trigger multiple execute products.

For example:

- one source tree may feed a LuaJIT UI backend
- the same source tree or related source may feed a Terra audio backend
- an inspector or debug projection may update in parallel

Conceptually the loop is still the same. It just has multiple compilation/execution outputs.

That is one reason the pattern scales well to multi-view or multi-backend systems.

### The key operational question

The most useful operational question in this loop is often not:

> what function is hot?

but rather:

> why did this event require this amount of recompilation?

That question points directly to the architecture:

- Did Apply preserve structure poorly?
- Is identity too coarse?
- Is a phase boundary too broad?
- Is a terminal compiling too much at once?
- Is a derived representation missing locality?

The live loop makes these questions visible because recompilation has architectural meaning.

### Key takeaway

In short:

> The live system is a repeating compiler loop: events are polled, the source program is updated by Apply, memoized phases recompile the affected parts into Units, and execution keeps running the currently installed machine until the source changes again.

Once that live operational story is clear, we can step back and describe the broader structural picture more explicitly:

- the backend-neutral architecture and its layers.

---

## 8. The backend-neutral architecture

Now that the core pattern is on the table, we can describe the larger structural consequence of the rewrite.

The architecture should be understood as having **three layers**:

1. the **domain layer**
2. the **pattern layer**
3. the **backend layer**

This layering is one of the most important results of the repository's recent evolution, because it makes it possible to talk clearly about what is essential to the app, what is essential to the pattern, and what is specific to a particular runtime target.

Without this separation, people tend to blur together three very different things:

- the user's language
- the compiler architecture
- the target-specific realization machinery

Once those are separated, the whole system becomes easier to reason about.

### The three-layer picture

A compact picture looks like this:

```text
┌───────────────────────────────────────────────┐
│                 YOUR DOMAIN                   │
│                                               │
│  source ASDL, Event ASDL, Apply,              │
│  phase structure, projections, Machine IR     │
│  intent, domain semantics                     │
│                                               │
│  This is your application.                    │
├───────────────────────────────────────────────┤
│               THE PATTERN                     │
│                                               │
│  Unit, gen/param/state, transition,           │
│  terminal, memoize, match, with,              │
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

This diagram is simple, but it carries a lot.

### Layer 1: the domain layer

The domain layer is the application's actual semantic content.

This includes:

- the source ASDL
- the Event ASDL
- the Apply reducer
- the real phases that consume unresolved knowledge
- any view projections from source into presentation forms
- the Machine IRs you want the compiler to reach
- the semantic meaning of the application's nouns and variants
- the terminal inputs you want the compiler to reach

This is where questions like these live:

- what is a node?
- what is a track?
- what is a block?
- what is a visual style?
- what is a graph edge?
- what is a layout rule?
- what should save/load preserve?
- what should undo restore?
- what are the real phase boundaries in this problem?

This layer is not backend-specific.
It is the architecture of the application itself.

That is why this rewrite keeps insisting that the source ASDL is the architecture. The domain layer is where the app's truth lives.

### Layer 2: the pattern layer

The pattern layer is the reusable compiler-shaped vocabulary used to express the domain layer.

This includes concepts and helpers such as:

- the canonical `gen, param, state` machine split
- Machine IR as the typed machine-feeding layer
- `Unit`
- `transition`
- `terminal`
- memoization at boundaries
- `U.match`
- `U.with`
- structural error collection
- fallback wrapping
- structural inspection/scaffolding support

This layer is not the app's semantics, but it gives the app a disciplined way to express those semantics.

It says, in effect:

- this boundary narrows ASDL to ASDL
- this boundary lowers ASDL to Machine IR or to `Unit`
- this is how machine order/access/state become explicit
- this is how sum types are matched exhaustively
- this is how structural updates are represented
- this is how partial failures can stay local
- this is how compiled artifacts compose structurally

The pattern layer is therefore architectural, but not domain-specific and not target-specific.

It is the middle layer.

### Layer 3: the backend layer

The backend layer is where the target-specific realization lives.

This includes things like:

- how a leaf becomes executable code on this target
- how runtime state is represented on this target
- how child state is composed on this target
- how a compiled Unit is installed or swapped on this target
- how external drivers or native libraries are called on this target
- what host compiler or JIT is relied upon on this target

This is the layer where Terra and LuaJIT differ most visibly.

In Terra, backend realization may involve:

- quoted native functions
- synthesized Terra struct types
- LLVM compilation
- native ABI-facing installation paths

In LuaJIT, backend realization may instead involve:

- specialized closures
- FFI-backed state layouts
- host JIT trace formation
- runtime installation through ordinary Lua/JIT mechanisms

The backends are different, but the domain and pattern layers can remain the same.

That is the key point.

### Why this split is better than saying "abstract over the backend"

It would be easy to phrase this as just another abstraction story:

- define an interface
- plug in different backends
- keep the app generic

But that description is too weak and somewhat misleading.

The real reason the architecture can support multiple backends is not merely that it has some abstract interface layer. The deeper reason is that the application's semantics live in modeled data and pure phases rather than in target-specific runtime machinery.

In other words, backend neutrality works because the app was designed correctly, not just because a backend API was introduced.

If the app's logic were tangled up with Terra-specific staging assumptions or LuaJIT-specific runtime conventions all through the semantic layer, then "abstracting the backend" would be superficial.

The clean separation only works when:

- the domain layer is really domain-first
- the pattern layer is really structural and reusable
- the backend layer is really where target-specific realization is confined

### What should remain shared across backends

For a well-factored app in this repository, the following should be shared across backends as much as possible:

- the source ASDL
- the Event ASDL
- the Apply reducer
- phase boundaries and their semantic meaning
- view projection logic
- terminal intent and terminal input design
- most structural helper logic
- tests for pure-layer behavior

This is the stable architectural core.

If changing backends requires changing large parts of this core, it is often a sign that target concerns leaked too far upward.

### What should vary across backends

The following things should be allowed to vary per backend:

- the exact representation of `Unit`
- the exact representation of `state_t`
- how `compose` realizes structural aggregation
- the exact leaf code shape
- installation and hot-swap strategy
- driver integration
- performance strategy at the machine-code/JIT level
- backend-specific limits or unsupported features

This is where target-specific engineering belongs.

### Illustration: one app, two backends

Imagine a single authored application model for a UI-driven audio tool.

The shared app architecture might include:

- a source ASDL for the document/tool state
- an Event ASDL for user and system interaction
- Apply for editing that source tree
- transitions for binding, layout, graph resolution, and semantic lowering
- view projection for editor/inspector presentation
- terminal boundaries describing what visual and audio leaves need

Now imagine two backend realizations.

#### LuaJIT realization
- UI Units become Lua closures over stable layout-backed state
- audio Units become LuaJIT-specialized DSP closures
- hot swap uses ordinary runtime replacement of active closures/state slots
- compile/build cost is very low

#### Terra realization
- UI or audio leaves become Terra-native functions where useful
- state layout becomes Terra struct synthesis
- LLVM performs the final low-level optimization
- ABI-facing installation is explicit

The same app architecture can drive both.
That is not an afterthought. It is the natural result of the three-layer split.

### The target can be treated as data

One of the elegant consequences of this split is that the target backend itself can be treated as another compile input.

That means the compilation story naturally generalizes to:

- source program
- maybe environment/config inputs
- target backend
- realized Unit

In practice, this means the target can act like another memoize key.

The source does not need to change in order for the backend realization to change.
The same authored subtree may yield:

- a Terra Unit on one target
- a LuaJIT Unit on another target
- a different lowered product on another runtime entirely

This is a much cleaner view than treating portability as something bolted on after the app already exists.

### Why backend-neutral does not mean backend-agnostic in performance

It is important not to misunderstand the phrase "backend-neutral."

It does **not** mean the backend is irrelevant.
The backend matters a great deal for:

- compile/build cost
- steady-state throughput
- available low-level operations
- ABI control
- integration strategy
- data layout choices
- what kinds of specialization are cheap or expensive

What backend-neutral means is:

- the architecture is not defined by one backend
- the source model and phase structure can remain stable across backend choices
- target-specific realization can vary without forcing the entire app to be redesigned

That is a strong claim, but it is not the same as saying all backends are equivalent.

### The three-layer split clarifies documentation too

This rewrite itself is really an expression of the three-layer split.

The old framing tended to let the backend layer dominate the explanation because Terra made the pattern vivid first.
But once the layers are separated properly, the documentation can proceed in a healthier order:

1. explain the domain-compilation-driven architecture
2. explain the pattern vocabulary used to express it
3. explain the backends and their tradeoffs

That order is much more faithful to how systems in this repository should now be designed.

### Backend-specific strength should still be described honestly

A backend-neutral architecture does **not** mean flattening every backend into a bland interchangeable box.
That would undersell real engineering differences.

The right move is:

- keep the architecture centered on the domain and pattern layers
- then describe each backend honestly in its own section

That is exactly why this document will later give Terra a dedicated section rather than treating it as merely one checkbox in a generic matrix.

Terra still has real strengths.
LuaJIT still has real strengths.
The architecture simply no longer mistakes either one for the definition of the pattern itself.

### The practical design consequence

If this section is taken seriously, a practical design rule falls out:

> when implementing a feature, first decide the domain model and phase story; only then decide how each terminal family should be realized on the available backends.

That is the correct order.

Not:

- pick a backend first
- shape the app around its mechanics
- hope the domain model can be fit into it later

That old order is exactly what this rewrite is trying to correct.

### Key takeaway

In short:

> The architecture has three layers — domain, pattern, and backend — and a well-factored app keeps its semantics in the first layer, expresses them through the second, and realizes them on targets through the third.

With that structure in place, we can now turn to the first major practical backend conclusion of the rewrite:

- why LuaJIT should usually be the default backend.

---

## 9. LuaJIT as the default backend

Once the pattern is understood correctly as backend-neutral, the next question is no longer "is Terra the architecture?" but rather:

> which backend should be the default choice on a JIT-native platform?

The answer this repository now supports is:

> **LuaJIT should usually be the default backend.**

That is a significant conclusion, and it deserves to be justified carefully, because it does not mean Terra is unimportant or obsolete. It means the architectural baseline has changed.

The reason is simple:

> on a JIT-native host, much of the backend compiler already exists.

If the host runtime can already:

- JIT-compile hot code paths
- specialize effectively on stable closure shapes and captured constants
- access stable FFI-backed state efficiently
- execute tight scalar loops very well

then the backend's main job is not necessarily to build a full explicit native compilation pipeline from scratch. The backend's main job becomes:

- emit highly specialized, ultra-monomorphic code shape
- preserve stable state access patterns
- avoid dynamic dispatch in hot paths
- let the host JIT see simple, optimizable structure

That is exactly where LuaJIT becomes extremely attractive.

### Why "default" matters

Calling LuaJIT the default backend is not merely a performance claim.
It is also a statement about development cost, deployment cost, iteration speed, and architectural fit.

A default backend is the backend you should reach for first because it gives the best overall balance for common cases.

That balance includes:

- ease of setup
- simplicity of deployment
- speed of iteration
- compilation/build latency
- runtime performance in common workloads
- architectural cleanliness

LuaJIT scores very well on that full bundle.

### LuaJIT already gives a large part of the backend story

What makes LuaJIT so compelling here is that it already provides several things that a compiler-pattern backend needs.

#### 1. A real JIT

The host runtime can already compile hot paths to native code.
That means the backend does not need to justify itself solely by saying "I can make native code exist." Native code can already exist.

The more important question becomes whether the backend can shape code so the JIT can optimize it well.

#### 2. Specialization via closure shape and stable control flow

If terminals emit code with:

- stable branches
- fixed loop shapes
- compile-time-known values captured in upvalues
- predictable child composition

then LuaJIT can often optimize that extremely well.

In other words, the compiler-pattern insight still applies. It just applies through the host JIT rather than through explicit quoted native functions.

#### 3. Fast execution of the pure layer

LuaJIT also runs the compiler-side pure layer quickly.
That matters more than people sometimes realize.

In this pattern, performance is not only about the final callback or draw loop. It is also about how cheaply you can repeatedly:

- run Apply
- run transitions
- allocate new structural nodes as needed
- hit memoize boundaries
- rebuild changed terminals

A fast host for the pure layer is therefore part of the end-to-end story.

#### 4. Cheap terminal construction

Compared with an explicit LLVM-backed path, LuaJIT terminal realization is typically much cheaper to build.

You are not generally paying for:

- full native code generation startup per leaf family
- LLVM optimization passes
- Terra compilation latency
- explicit native struct synthesis cost at the same scale

That makes a large difference in interactive workflows where the program changes often.

### The compile/build cost story is crucial

One of the strongest practical outcomes of the recent benchmarking work is that build/compile cost matters a lot in this architecture.

Why?
Because the whole pattern is based on repeated recompilation of changed subtrees.

A backend that has slightly better steady-state throughput but much higher build cost is not automatically the right default. The architecture lives in the loop:

- edit
- apply
- recompile
- continue running

So the cost of producing new Units matters directly to perceived responsiveness.

This is one reason LuaJIT becomes the natural baseline. It is very cheap to produce new specialized closures and associated runtime layouts compared with a more explicit native compilation path.

### The benchmark result in practical terms

The repository's backend benchmark work supports a nuanced conclusion rather than a simplistic one.

At a high level, the results show something like this:

- LuaJIT compile/build cost is dramatically cheaper than Terra
- LuaJIT scalar leaf performance can be extremely close to Terra
- composed-chain throughput is still slower on LuaJIT than on Terra, but not by an overwhelming margin after the recent optimization work

That combination matters.

If LuaJIT were far slower in steady-state execution, the cheaper build cost might not be enough. But that is not what the results suggest for the current scalar DSP-style workload family.

Instead, the results support the much more interesting conclusion:

> for many practical cases, LuaJIT delivers enough of the runtime performance while being vastly cheaper to build and easier to deploy.

That is exactly what a default backend should do.

### Illustration: why cheaper rebuilds matter

Imagine a live-coded or interactively edited audio patch.
The user tweaks:

- filter cutoff
- routing
- oscillator kind
- modulation amount
- envelope shape

Each edit potentially changes some portion of the compiled machine.

If the backend makes those rebuilds expensive, the live feel of the architecture degrades even if the final callback is extremely fast once rebuilt.

If the backend makes rebuilds cheap, then the system can feel far more responsive even if the final callback is modestly slower.

That tradeoff is especially favorable to LuaJIT in many interactive settings.

### LuaJIT aligns well with the pattern's terminal objective

The pattern's terminal objective is not "generate native code by any means necessary." It is:

> produce backend-friendly Units that are as monomorphic and specialization-friendly as possible.

On LuaJIT, that objective can be met by terminal code that:

- closes over compile-time-known facts
- chooses fixed operator families ahead of time
- avoids data-dependent variant dispatch in hot loops
- accesses state through stable predictable typed FFI layouts
- composes child operations in simple linear or structural forms that trace well
- consumes rich semantic structure before execution rather than interpreting it in the callback

That is a very good match for the architecture.

A useful way to think about this is to look at libraries like `fun.lua`. Their performance does not come from treating Lua as a free-form dynamic object world. It comes from normalizing many rich surface forms into one tiny regular execution protocol. Good LuaJIT leaves should do the same thing: lower rich typed phase data into a tiny canonical machine that the JIT can trace aggressively.

The terminal is still doing real compiler work. It is just targeting the optimization strengths of the host JIT rather than an explicit LLVM-native path.

### Development and deployment are materially simpler

There is also a straightforward engineering reason LuaJIT should be the default.

A default backend should minimize incidental cost for the common case.
LuaJIT helps by keeping things lighter in practice:

- easier environment story on JIT-native platforms
- no mandatory Terra/LLVM dependency for all users
- faster startup and iteration
- fewer moving parts in the default path

That matters both for contributors and for users of software built with the pattern.

A backend can be theoretically elegant and still be the wrong default if it raises the everyday cost too much.

### Default does not mean only

It is important to say this clearly:

> default does not mean exclusive.

The architecture is not moving from "Terra-only" to "LuaJIT-only."
It is moving from "Terra treated as the defining center" to "LuaJIT treated as the normal starting point, with Terra available when its specific strengths are justified."

That is a much healthier policy.

It means a feature or subsystem can start on LuaJIT and later opt into Terra when benchmarking or backend requirements say it should.

### When LuaJIT is especially attractive

LuaJIT is especially attractive when:

- the target platform already supports it comfortably
- the workload is dominated by scalar or moderately composed kernels
- build/compile latency matters a lot
- iteration speed matters a lot
- deployment simplicity matters
- explicit ABI control is not the main requirement
- the backend mostly needs specialization-friendly code shape rather than explicit low-level staging power

That describes a surprisingly large set of interactive applications.

### What the backend design should optimize for on LuaJIT

If LuaJIT is the default backend, then backend engineering should focus on the things that matter most for it.

That means designing terminals and composition around questions like:

- are the hot loops monomorphic?
- are important constants captured rather than looked up dynamically?
- is state access predictable and cheap?
- is that state realized as typed FFI/cdata layout rather than opaque tables?
- is live payload realized as typed FFI/cdata layout rather than opaque tables?
- is child composition shaped so traces stay stable?
- are wide domain sum types consumed before execution?
- is the closure/code graph simple enough for the JIT to understand?

These are not secondary implementation details. They are the LuaJIT form of the backend compiler story.
And they are exactly how LuaJIT can impose nearly the same design pressure as Terra: if the leaf still wants arbitrary tables, missing-field checks, tag strings, or interpreter-style tree walking, then the lowering is not finished.

### A concrete mental shift

The important mental shift is this:

In a Terra-first framing, one might think:

- the compiler emits native code
- therefore we have a compiled architecture

In the new LuaJIT-default framing, the better thought is:

- the compiler emits specialization-friendly code shape for the host runtime
- the host runtime performs much of the final low-level compilation work
- therefore we still have a compiled architecture

That is a more general and more accurate understanding of what is happening.

### Why this is not a retreat from ambition

It might be tempting to misread "LuaJIT by default" as a retreat from serious systems work. It is the opposite.

It reflects a more mature understanding of where explicit compilation is necessary and where the host runtime already provides enough of it.

Good architecture is not about maximizing visible machinery.
It is about placing machinery where it buys the most.

If the host JIT can already do a lot of the backend work, then using that fact is not compromise. It is architectural honesty.

### The practical policy

A good practical policy is therefore:

1. design the domain backend-neutrally
2. design leaves and phase boundaries with Terra-level explicitness in mind
3. implement the shared pure layer once
4. target LuaJIT first on JIT-native platforms
5. benchmark the important leaf families and compositions
6. opt into Terra where explicit native power is worth the extra cost

This policy matches both the architecture and the current empirical results. It keeps Terra's design pressure without making Terra the mandatory default realization path.

### Key takeaway

In short:

> On JIT-native platforms, LuaJIT should usually be the default backend because the host runtime already provides much of the final compiler, making terminal construction extremely cheap while still delivering strong performance when Units are shaped for specialization.

With LuaJIT established as the default, the next section can give Terra the treatment it deserves:

- not as the definition of the pattern, but as the explicit strong backend with capabilities that still matter a great deal.

---

## 10. Terra as the opt-in strong backend

If the previous section establishes the new default, this section needs to establish the equally important complement:

> **Terra is still a major strength of this architecture.**

The correction in this rewrite is not that Terra was a mistake.
The correction is that Terra should no longer be mistaken for the architecture itself.

Once that distinction is made, Terra can be described more honestly and more usefully.
It becomes:

- not the definition of the pattern
- but the strongest explicit-native backend available in this repository when its particular powers are needed

That is a very good role for Terra.

In fact, it is arguably a better role than the old one, because it lets us talk clearly about what Terra actually contributes rather than using it as a vague synonym for "compiled."

### What makes Terra special

Terra is special because it gives the backend explicit control over the last stage of realization.

Where LuaJIT asks the backend to shape code so the host JIT can specialize it, Terra allows the backend to directly express the specialized native machine it wants.

That difference matters a lot.

In Terra, you can decide more explicitly:

- what code exists
- what type layout exists
- what gets baked into code
- what becomes a field in a struct
- what the ABI looks like
- how low-level native operations are expressed

This is not merely "more optimization." It is a different degree of authorship over the machine.

### 10.1 Explicit staging

One of Terra's biggest strengths is explicit staging.

In Terra, the distinction between:

- compiler-side Lua logic
- generated Terra code
- runtime execution of that code

is concrete and programmable.

That means a terminal can do things like:

- inspect a phase-local node
- decide exactly which arithmetic or control structure should exist
- quote that structure directly into the generated function
- bake compile-time-known values into the emitted code

This is much more explicit than relying on host-JIT heuristics.

#### Why that matters

In a host-JIT backend, you often aim for:

- stable closure shape
- simple loops
- captured constants
- predictable traces

That works well, but it is still an indirect style of control. You are shaping code for another compiler.

In Terra, you can say more directly:

- emit this exact branch structure
- emit this exact loop shape
- inline this known choice structurally
- specialize this path for this variant now

That makes Terra especially strong when the backend needs confident control over emitted machine shape rather than merely hoping the host JIT will infer it.

#### Illustration: variant elimination

Suppose a source operator can eventually narrow to one of several fixed concrete kinds.

In LuaJIT, a good terminal might emit a closure that captures the final operator kind by choosing one specialized closure family and thereby avoids dynamic runtime branching.

In Terra, a good terminal can go one step further and literally generate the final operator body for that exact kind. There does not need to be a remaining notion of "operator kind" in the hot execution path at all unless you choose to leave one there.

That is a very strong form of specialization.

### 10.2 Static native types

Another major Terra strength is that native types are first-class in the backend language.

This matters because the pattern's `Unit { fn, state_t }` idea becomes extremely literal in Terra.

A Terra Unit can own:

- a native function with a concrete signature
- a native `state_t` with exact fields
- explicit pointer-level access patterns
- concrete data layout known at compile time

This gives the backend something much stronger than "fast runtime data access." It gives it **type-level authorship over the machine's runtime layout**.

#### Why that matters

Many performance-sensitive systems care deeply not just about what arithmetic runs, but about:

- how state is laid out in memory
- whether field offsets are static
- whether child state can be aggregated into one known struct
- whether API boundaries see exactly the expected ABI
- whether pointer indirection is minimized in a controlled way

Terra lets the backend control those questions directly.

### 10.3 Struct synthesis in `Unit.compose`

This is one of the places where Terra feels especially natural for the pattern.

Because child state layouts are native types, `Unit.compose` can synthesize larger native state layouts structurally.

That means parent composition can do something like:

- child A has `state_t_A`
- child B has `state_t_B`
- child C has `state_t_C`
- parent `compose` builds a parent `state_t` containing those as fields plus any parent-local state

The result is a single structural native layout reflecting the same containment story as the source tree.

That is a profound fit with the architecture.

The source tree composes structurally.
The compiled Units compose structurally.
The runtime state layout also composes structurally.

In Terra, all three of those relationships can line up very explicitly.

#### Why this is better than ad hoc state ownership

Without something like Terra struct synthesis, it is easy for a runtime to drift toward looser arrangements such as:

- scattered heap objects
- external registries of child state
- dynamic table lookup by child index
- generic runtime containers holding opaque state blobs

Sometimes those are acceptable, but they are weaker architectural matches.

Terra makes the strong version easy to express:

- parent owns child state structurally
- field layout is concrete
- access paths are statically known
- the composed machine is one native thing

That is one of Terra's most compelling contributions to the pattern.

### 10.4 LLVM as the final low-level optimizer

Terra's other obvious strength is that it feeds the generated program into LLVM.

This matters for several reasons.

#### Constant propagation and simplification
If terminals bake decisions and literal values into emitted code, LLVM can continue simplifying from there.

#### Instruction selection
LLVM has a much broader view of low-level instruction generation than a scripting-language host JIT typically does.

#### Vectorization opportunities
For some workloads, especially those where loops and data access patterns are made explicit enough, LLVM may expose vectorization and related low-level optimizations that are difficult or unavailable in a host-JIT setting.

#### Predictable native compilation model
With Terra, the backend can often reason in a more direct way about the path from staged code to native code. It is not merely relying on whether a hot trace forms the way you hope.

That does not mean LLVM is magic or always wins absolutely. It means Terra gives you a more explicit relationship to a serious native optimization pipeline.

### 10.5 Terra as design pressure

There is another Terra advantage that is less often stated explicitly, but it matters a great deal in practice:

> Terra is not only a strong backend. It is also a stricter teacher.

Or said even more directly:

> Designing with Terra in mind makes the right structure simple and makes bad structure hard to miss.

That is, Terra often makes weak architecture harder to ignore.

This happens for two related reasons.

#### Explicit types force modeling honesty

Because Terra wants concrete native types, it becomes much harder to hide vagueness inside loose runtime structure.

A backend written in Terra tends to force questions like:

- what variant is this really?
- what is the actual state layout?
- what belongs in authored source versus a later phase?
- what belongs in runtime state rather than semantic data?
- what should be baked into code versus kept live in state?

In a looser runtime, you can often postpone those decisions by leaning on:

- generic tables
- optional fields everywhere
- stringly conventions
- dynamic branching deep in the hot path
- ambient context lookups that "just work for now"

Terra makes those evasions less comfortable.
That is good for the architecture.

#### The LLVM tax makes coarse design visible

Terra also imposes a nontrivial compile/build cost.
That cost is not merely a downside. It is also diagnostic.

If the architecture is poorly factored, Terra tends to make the pain show up quickly.
For example, you feel it when:

- a tiny edit causes too much recompilation
- identity boundaries are too coarse
- a terminal is compiling too much at once
- a missing phase leaves too much unresolved work for the leaf
- state ownership is vague enough that composition becomes awkward

In other words, Terra does not make bad design invisible.
It often makes bad design **expensive enough to notice immediately**.

That pressure can be very healthy.
A host-JIT backend may be forgiving enough that architectural sloppiness still seems acceptable for a while. Terra is less forgiving, and that can improve the design.

#### Explicit staging exposes phase leaks

Terra is especially good at revealing when a leaf is still being asked to interpret too much.

If a Terra terminal still needs to emit a machine that:

- branches over wide authored variants
- resolves references on the fly
- consults string tags repeatedly
- discovers layout policy at runtime
- depends on ambient context to make basic semantic decisions

then the design feels wrong immediately.

And usually it is wrong.
The leaf input is still too unresolved.
A phase is missing, too late, or too weak.

That is valuable feedback.

#### Struct synthesis exposes ownership mistakes too

Because Terra makes structural state composition so explicit, it also puts pressure on ownership clarity.

When `Unit.compose` wants to produce one concrete state layout, you are forced to answer:

- what state does this child actually own?
- what belongs to the parent?
- what should be persistent authored data rather than runtime state?
- what should have been derived before the Unit boundary?

Again, that pressure is good.
It forces the boundary between authored semantics, phase-local derived forms, and execution-time state to become more honest.

#### Why this matters for the rewrite

This is an important reason Terra should still be presented as a major asset of the pattern even though it is no longer the pattern's definition.

Terra contributes not only:

- native performance potential
- explicit ABI control
- static layout synthesis
- explicit staging power

It also contributes:

- modeling pressure
- phase-discipline pressure
- ownership clarity
- earlier visibility into coarse recompilation boundaries

That is a real architectural advantage.

So a more complete statement is:

> Terra is valuable not only because it can produce excellent native code, but because its explicit types, explicit staging, and nontrivial compile cost exert healthy design pressure. Missing phases, vague source models, coarse memoization boundaries, and unclear state ownership become much harder to ignore.

### 10.6 ABI control

Terra is also strong because it gives precise control over native calling conventions and layout boundaries.

This is one of the least flashy but most important advantages.

When the compiled machine must interface with native systems, it can matter a great deal to know exactly:

- what function pointer signature exists
- what struct layout exists
- how memory is passed
- how callbacks interoperate with native libraries or drivers

In those cases, Terra is not just faster in some vague sense. It is **clearer** and **safer** about what machine boundary has been created.

This matters especially for:

- audio callback interfaces
- graphics/OS/native library interop
- low-level systems boundaries
- exported native functions
- tightly controlled runtime ownership conventions

LuaJIT can also interoperate with native code, of course, especially through FFI. But Terra gives a stronger sense that the backend is defining the native artifact itself, not merely calling into native code from a JITed host environment.

### 10.7 Low-level native expressiveness

Terra also remains attractive because certain low-level operations are simply more natural when the backend can speak in an explicitly native vocabulary.

Examples include:

- pointer manipulation
- packed/native struct handling
- low-level numeric code where exact type/control matters
- specialized buffer or memory layout strategies
- explicit calls into native APIs as part of emitted code

When a terminal family truly wants to operate at this level, Terra often feels like the right tool rather than an optional extra.

### 10.8 When Terra is the right choice

So when should a subsystem or terminal family opt into Terra?

Terra is the right choice when one or more of these are important enough to justify it:

#### 1. You need explicit staged code generation
You want to directly author the emitted machine shape rather than shape code indirectly for a host JIT.

#### 2. You need static native layout synthesis
You want `state_t` to be a true native type with concrete field layout, especially in composed structures.

#### 3. You need stronger ABI guarantees
The compiled artifact must cross a native boundary with exact control over signatures and layout.

#### 4. You need LLVM's optimization strengths
The workload benefits from explicit native compilation, possibly including vectorization or deeper low-level optimization than the host JIT can reliably deliver.

#### 5. You need Terra-native low-level expressiveness
The leaf body or state representation is simply more natural to express in Terra.

### Illustration: scalar DSP vs more demanding kernels

The benchmark story in this repository strongly suggests that for scalar DSP-style workloads, LuaJIT is often strong enough to be the baseline backend.

But that does not make Terra irrelevant.
It means the threshold for opting into Terra becomes more specific and more honest.

For example, Terra becomes increasingly attractive when moving toward cases like:

- more elaborate kernels where explicit code shape matters more
- stronger demands on exact layout and ABI
- cases where LLVM's low-level optimization pipeline has more room to help
- terminal families where static struct synthesis meaningfully simplifies the machine

That is the correct way to think about Terra now: not as the default answer to everything, but as the backend with extra power when the workload or integration boundary truly wants it.

### 10.9 Terra and architectural clarity

One subtle but important point is that treating Terra as an opt-in backend can actually improve Terra usage.

Why?
Because it encourages us to use Terra where its strengths are real, rather than wrapping the whole architecture in Terra-first assumptions whether they help or not.

When Terra is used deliberately, its benefits stand out more clearly:

- the staged code is there for a reason
- the static layout is there for a reason
- the ABI control is there for a reason
- the LLVM cost is being paid for a reason

That is better engineering than treating Terra as mandatory background radiation.

### 10.10 The relationship between Terra and the pattern now

This section should correct the relationship precisely.

The old, overly strong framing would be something like:

- the pattern is Terra-shaped
- therefore Terra is central to every serious use of it

The better framing is:

- the pattern is a compiler architecture centered on modeled source, phases, and Units
- Terra is the explicit strong backend for cases that benefit from explicit staging, native types, struct synthesis, ABI control, and LLVM

That is a cleaner and more stable relationship.

It respects what Terra really adds without forcing the rest of the architecture to pretend it depends on Terra for its identity.

### 10.11 A practical opt-in policy

A good practical policy for Terra is:

1. begin from the shared domain and pure-layer architecture
2. design the leaves so they would be simple to realize in Terra
3. realize terminal families on LuaJIT by default where appropriate
4. benchmark and inspect the workloads that matter
5. move a terminal family or subsystem to Terra when explicit native control buys enough
6. keep the source model and phase story shared whenever possible

This policy preserves the best part of the rewrite:

- one architecture
- multiple honest backends
- Terra used where it is strongest

### Key takeaway

In short:

> Terra is the opt-in strong backend of the pattern: it offers explicit staging, static native types, structural state-layout synthesis, ABI control, and LLVM optimization when a terminal family truly benefits from direct authorship over the native machine.

With the two main backend positions now clear — LuaJIT by default, Terra by opt-in — the next step is to explain how to think about performance within this architecture more generally.

---

## 11. Performance model

One of the easiest ways to misunderstand this pattern is to evaluate performance only through the narrow lens of steady-state execution speed.

That would be a mistake.

Because this architecture is built around a live compile loop, performance has to be understood across **both** of these dimensions:

1. **how expensive it is to rebuild the machine when the source changes**
2. **how efficiently the rebuilt machine runs once installed**

Both matter.
And the whole point of the architecture is that they are connected.

A backend that produces brilliant machine code but is very expensive to rebuild may be the wrong default for an interactive workload.
A backend that rebuilds instantly but executes too slowly may also be the wrong choice.

So the performance model has to begin with the live compiler loop rather than with raw callback throughput alone.

### The first performance question is architectural

In this pattern, the first useful performance question is often not:

> what function is hot?

but rather:

> why did this change require this amount of recompilation?

That question immediately points toward the actual architecture.

If a tiny edit causes a large amount of recompilation, possible reasons include:

- Apply failed to preserve structural sharing
- identity boundaries are too coarse
- source containment is too broad
- a transition is doing too much work over too much structure
- a terminal is compiling too large a region at once
- a later phase flattened away locality too early

All of those are architectural issues, not mere micro-optimization issues.

This is one reason the pattern can feel refreshing: performance debugging often becomes a question about model boundaries and phase clarity rather than about scattered runtime heuristics.

### The two costs: rebuild cost and run cost

A good way to think about the system is as balancing two costs.

### Memoize hit ratio is a design metric

There is also a highly practical metric that sits between modeling and performance:

> **the memoize hit ratio at real stage boundaries**

This metric matters because it measures the architecture more directly than raw throughput does.

If one small edit causes:

- a few local misses
- many sibling hits
- misses mostly at the edited subtree and its expected parents

then the ASDL decomposition is probably healthy.

If one small edit causes:

- misses across unrelated leaves
- misses across most siblings
- widespread recompilation after local edits

then the architecture is telling you that something is wrong.

Typical causes are:

- broken structural sharing
- unstable IDs
- memoize keys that include volatile data
- boundaries that are too coarse
- phases that flatten away locality too early

That is why memoize instrumentation is so valuable. It lets you ask not just "how fast is this backend?" but also:

- how much work did this edit really cause?
- which boundaries miss too often?
- are leaves being reused the way the model claims they should be?

In practice, the runtime now supports optional named boundaries plus a shared inspector interface:

- `U.memoize("name", fn)`
- `U.transition("name", fn)`
- `U.terminal("name", fn)`
- `U.memo_stats(boundary_fn)`
- `U.memo()`
- `U.memo_report()`
- `U.memo_quality()`
- `U.memo_diagnose()`
- `U.memo_measure_edit(description, fn)`

That gives `Unit` a pleasant top-level inspection surface instead of forcing callers to assemble a separate diagnostics object every time.

In other words, the cache hit ratio is not just a runtime statistic.
It is a design-quality inspector for the ASDL and the phase structure.

#### 1. Rebuild cost
This is the cost paid when the source program changes.

It includes things like:

- reducer work
- structural allocation of changed nodes
- transition recomputation
- terminal recomputation
- backend-specific Unit construction
- installation or hot swap of the new compiled artifact

#### 2. Run cost
This is the cost of the installed machine while it is executing.

It includes things like:

- callback throughput
- draw loop throughput
- state access cost
- arithmetic cost
- control-flow cost
- memory locality in the hot path

A healthy architecture tries to minimize the combined cost appropriate for the application rather than optimizing one while blindly sacrificing the other.

### Why interactive systems care about rebuild cost so much

In an ahead-of-time compiler, rebuild cost can often be paid rarely.
In an interactive system, rebuild cost is part of the user experience.

Every time the user:

- types a character
- moves a node
- tweaks a parameter
- resizes a window
- changes a style
- edits a routing

the system may need to rebuild some part of the machine.

That means rebuild latency affects:

- responsiveness
- live feel
- editability
- confidence that the system is truly incremental

This is why cheap terminal construction and good structural locality matter so much.

### Why run cost still matters enormously

Of course, rebuild cost is not everything.
Once the machine is installed, execution may happen at a high frequency:

- audio callback rate
- frame rate
- simulation tick
- query throughput

If the installed machine is too slow, the architecture still fails.

So the right question is not "rebuild or run?"
It is:

> where is the right balance for this workload, this backend, and this machine shape?

That balance may differ across subsystems.

### The bake/live split

One of the most useful performance questions at the terminal boundary is:

> what should shape `gen`, what should remain stable in `param`, and what should remain mutable in `state_t`?

This is a central optimization question in the pattern.
The older shorthand of "bake vs live" is still useful, but the fuller machine split is usually clearer:

- bake into `gen` when code shape should change
- keep in `param` when the machine should read stable execution data
- keep in `state_t` when runtime ownership and mutation are genuinely required

#### Bake into the machine when:
- the fact is compile-time-known for the subtree
- removing the variability simplifies control flow materially
- constant propagation or specialization will likely help
- it reduces repeated branching or lookup in the hot path

Examples:

- fixed operator kind
- fixed blend mode
- known channel count
- resolved shadow kind
- known filter topology

#### Keep live in `state_t` when:
- the value is execution-time mutable
- the value changes frequently without requiring semantic recompilation
- the machine genuinely needs runtime ownership of it
- rebuilding for every tiny change would be the wrong tradeoff

Examples:

- filter delay history
- counters and accumulators
- mutable runtime buffers
- execution-time smoothing state
- backend-owned handles or caches tied to the installed machine

The right bake/live split often determines whether a leaf feels compiled or still half interpreted.

### Illustration: filter parameter vs filter history

Take a biquad filter.

Possible authored facts:

- filter kind
- cutoff
- resonance

Possible runtime facts:

- previous input/output history
- smoothing accumulator

A good performance-oriented phase split may be:

- source stores authored filter intent
- a later phase computes coefficients or normalized coefficient inputs
- the terminal decides whether coefficients are baked, captured, or stored in a stable runtime location depending on backend and update frequency
- runtime `state_t` stores only the mutable execution history and similar live data

This avoids confusing authored semantics with hot mutable execution state.

### Narrowing sum types early helps both costs

A wide sum type reaching the hot path usually hurts both rebuild cost and run cost.

It hurts run cost because the machine keeps branching on semantic alternatives that should often have been decided already.
It hurts rebuild cost because terminals become more complex and less local when they must interpret broad authored structure directly.

That is why the pattern keeps insisting that later phases should usually narrow rather than widen.

A good terminal input should be much more monomorphic than the authored source.

### Locality is performance

Structural locality is not an abstract nicety. It is performance.

If the source model and phases preserve locality well, then:

- small edits change small subtrees
- memoization hits stay high
- terminals re-run only where necessary
- installation work stays smaller
- the programmer can reason more clearly about what recompiles

If locality is poor, performance suffers before any low-level arithmetic question even arises.

This is why stable IDs, honest containment, and structural sharing are so central to the architecture's performance story.

### Performance debugging through architecture

When performance is disappointing, the first diagnostic questions should often be architectural:

#### Rebuild-side questions
- Did an edit change more structure than it should have?
- Are identities stable enough?
- Is a phase boundary too coarse?
- Did we flatten a subtree too early?
- Is a terminal receiving too much unresolved information?
- Are we recompiling siblings unnecessarily?

#### Run-side questions
- Did a wide sum type reach execution?
- Are we still doing dynamic dispatch in the hot path?
- Should more facts have been baked into the Unit?
- Is state access too indirect?
- Is the composed machine shape too generic for the backend to optimize?

This diagnostic style is much more aligned with the pattern than immediately reaching for low-level tuning everywhere.

### Backend-specific performance questions still exist

The general performance model is shared, but each backend has its own local questions.

#### LuaJIT-oriented questions
- Are the emitted closures monomorphic enough to trace well?
- Are important constants captured in upvalues?
- Is state access stable and cheap?
- Are loops and composition shapes simple enough for the JIT?
- Are we accidentally causing trace instability with overly generic composition?

#### Terra-oriented questions
- Are we staging the right facts into emitted code?
- Is the native state layout as explicit and local as it should be?
- Are we paying LLVM cost at the right granularity?
- Should a larger or smaller subtree be the Unit boundary?
- Are we making the compile tax worthwhile with sufficient steady-state benefit?

These are different questions, but both sit within the same larger architectural frame.

### The granularity question

One of the hardest performance questions in the pattern is Unit granularity.

If Units are too coarse:

- small edits may trigger too much recompilation
- terminals may become huge and hard to reason about
- local changes lose incrementality

If Units are too fine:

- composition overhead may increase
- state fragmentation may increase
- backend optimization may become less effective
- the system may behave like a tiny interpreter over lots of micro-Units rather than a well-specialized machine

There is no universal answer here.
The right granularity depends on:

- the domain
- the edit patterns
- the backend
- the runtime constraints
- the machine shapes being emitted

But the pattern gives a principled way to think about the choice.
A Unit should usually correspond to a real semantic or structural submachine, not an arbitrary bookkeeping fragment.

### Benchmarking should mirror the architecture

Benchmarks in this pattern are most useful when they reflect real architectural questions.

Examples:

- leaf compile/build cost
- composed-chain compile/build cost
- steady-state callback throughput
- effect of composition strategy on runtime speed
- effect of changed subtree size on recompilation cost

This is better than benchmarking only isolated arithmetic kernels with no relation to the actual compilation structure.

The repository's backend benchmark work is valuable precisely because it compares both:

- build cost
- run cost

across shared structural workloads.

That makes the backend conclusions meaningful architecturally, not just numerically.

### The recursive benchmarking law

There is a deeper workflow consequence here that is worth stating explicitly.

In this pattern, phases are not only data transformations. Each phase boundary is also the point where one language becomes the next language's execution problem.

That means a phase can be treated in two ways at once:

- as a **compiler** from one representation to another
- and, once its consumer is trusted, as the **runtime feeder** for the next machine

This yields a powerful recursive design law:

> In a leaf-first workflow, once the leaf for a layer has been benchmarked and made good, the performance of the layer above becomes a direct test of the ASDL and phase design feeding that leaf.

Or more concretely:

> after the lower machine is known-good, compile speed at the next layer is execution speed for that layer's output language.

This is one of the pattern's most practically important insights.

It means performance debugging can proceed upward through the compiler story rather than remaining trapped at the backend leaf.

#### Why this is true in practice

Suppose you start correctly:

1. write the leaf you want
2. benchmark the leaf
3. make the leaf/backend realization fast enough
4. only then move one layer up

At that point, when the next boundary is slow, the obvious excuse is gone.
You already know the lower machine is good.
So if the boundary feeding it is still expensive, that boundary is not merely suffering from bad low-level implementation luck.
It is strong evidence that the representation above it is still wrong for that consumer.

The layer is still doing too much thinking.
It is still carrying too much unresolved structure.
It is still interpreting where it should already be compiling.

That is why, in this workflow, slow lowering is not just a local optimization problem.
It is usually an ASDL diagnostic.

#### The recursive form

This same law applies repeatedly.

- if the final backend leaf is good, then a slow machine-IR projection points above itself
- if the machine-IR projection is then fixed and trusted, a slow solved-phase projection points above itself
- if the solved phase is then fixed and trusted, a slow lowering phase points above itself
- and so on

So the pattern gives you a recursive debugging method:

1. validate the lowest machine first
2. move one boundary up
3. benchmark that boundary in isolation
4. if it is slow, redesign the ASDL **above** it
5. repeat

This is a much stronger method than trying to optimize the whole stack at once.

#### Why this belongs to the pattern rather than to benchmarking folklore

This is not merely a nice engineering habit.
It follows from the architecture itself.

Because:

- each phase consumes real knowledge
- each boundary is memoized
- identity is structural
- later phases should narrow toward machines
- and lower layers are validated before higher layers are trusted

a slow boundary means the upstream language is still too expensive for the downstream machine to consume cleanly.

That is exactly the kind of signal the pattern wants you to notice.

#### Illustration: UI pipeline

Suppose a UI render machine has already been designed and benchmarked successfully.
You know the stable runner over spans/headers/instances/resources is good.

Now imagine the projection feeding it is still slow.
For example, `project_render_machine_ir` repeatedly rebuilds too much structure.

At that point, the right question is not:

- can the backend draw loop be micro-optimized again?

The right questions are architectural:

- why is this projection still discovering resource identity so late?
- why are use-sites and resource specs still fused?
- why is clip or draw-state sharing still unclear?
- what facts should have been split in the ASDL above?

Because the lower machine is already validated, the slow projection is telling you that the representation feeding it is wrong.

#### Illustration: geometry solve

The same logic applies one level up.

Suppose geometry solve has been benchmarked and made good for its honest input language.
Then the phase feeding geometry should be judged by how cheaply it can produce that language.

If `lower_geometry` is slow, and the geometry solver below it is already trusted, then the diagnosis is no longer "maybe geometry solve is just expensive." The more useful diagnosis becomes:

- is layout input still mixed with render/query facts?
- are custom intrinsics still too opaque?
- is the shared flat language too broad?
- did we keep information bundled that the solver does not actually need?

Again, the fix points upward into the ASDL.

#### What this lets you do

This recursive law gives a very practical implementation workflow:

- benchmark the leaf first
- then benchmark each higher boundary as soon as it exists
- treat slowness as evidence of a bad upstream representation
- redesign the ASDL tree above the offending boundary
- only then continue implementing upward

This is one of the cleanest ways to keep design, implementation, and performance aligned.

It also explains why leaf-first design is so powerful in this pattern.
It does not merely help you imagine the right terminal.
It gives you a performance-proof workflow for discovering whether each higher phase is honest.

#### The phrase to remember

A useful way to summarize this is:

> once a lower machine is trusted, a slow boundary above it is usually a type-shape failure above, not a backend failure below.

Or even more compactly:

> in a leaf-first compiler workflow, compile speed becomes execution speed recursively, one layer at a time.

That is not a claim that stopwatch timings are literally identical.
It is the stronger architectural claim that, after the lower machine has been validated, the next layer's performance directly measures how much unnecessary semantic work still remains in the language above it.

### Why LuaJIT-by-default follows from this model

This whole performance model is what supports the LuaJIT default policy.

LuaJIT wins an enormous amount on rebuild cost.
Its run cost is often close enough for many important workloads.
That means the total live-loop cost can be very favorable.

The more interactive and frequently changing the workload, the more important this tends to be.

### Why Terra still matters within this model

The same performance model also explains why Terra remains important.

If a subsystem has:

- stricter native ABI requirements
- stronger need for exact state layout
- more demanding steady-state kernels
- more benefit from explicit staged specialization
- backend shapes where LLVM can materially outperform the host JIT

then Terra can become worth its extra rebuild cost.

That is the right tradeoff model.

### Performance is a property of the whole compiler story

A final important point is that performance in this pattern is never just a property of the leaf arithmetic.
It is a property of the whole compiler story:

- source model quality
- identity stability
- phase clarity
- terminal input narrowness
- Unit granularity
- backend realization strategy
- hot-path machine shape

That is one of the deepest lessons of the architecture.

A poor source model can waste more performance than a clever arithmetic trick can recover.
A missing phase can cost more than a backend micro-optimization can save.
A bad Unit boundary can dominate everything downstream.

### Key takeaway

In short:

> Performance in the compiler pattern is the combined cost of rebuilding and running specialized machines, and the biggest wins often come first from better modeling, better phase boundaries, and better Unit granularity rather than from isolated low-level tuning.

With that performance model in place, we can now make explicit one of the most attractive consequences of the pattern:

- how much infrastructure it allows the architecture to eliminate.

---

## 12. What the pattern eliminates

One of the most attractive features of the compiler pattern is that it often makes a surprising amount of conventional infrastructure unnecessary.

This can sound almost too good to be true if stated carelessly, so it is important to explain the reason precisely.

The pattern does **not** eliminate complexity by pretending complex programs are simple.
It eliminates infrastructure by removing the architectural conditions that made so much coordinating machinery necessary in the first place.

That is an important distinction.

In many conventional designs, a large amount of system complexity exists because the architecture has multiple overlapping partial truths:

- a runtime object graph
- a store or model layer
- a rendering layer with its own derived structures
- caches remembering what changed
- invalidation rules tracking who depends on whom
- controller/service logic that reinterprets the same domain repeatedly

When those partial truths drift, the system needs more machinery to reconcile them.

The compiler pattern reduces that need because:

- the source program is explicit
- interaction is explicit
- phase boundaries are explicit
- compiled artifacts are explicit
- state ownership is explicit
- recompilation is driven structurally rather than by ad hoc invalidation protocols

Once those things are true, many familiar pieces of infrastructure either disappear or shrink dramatically.

### 12.1 State management frameworks

A large class of application complexity comes from trying to manage state indirectly.

Examples include:

- centralized stores that become shadow architectures
- action/effect plumbing that exists mainly to make mutation legible
- observer-heavy state propagation systems
- elaborate consistency protocols between multiple runtime models

In the compiler pattern, much of this falls away because the core state question is simpler:

- the source ASDL is the authored program
- Apply computes the next source ASDL
- later phases derive what should run

This does not mean the app has no state. It means the state is no longer architecturally mysterious.

You do not need as much meta-infrastructure just to answer "what is the application right now?"

### 12.2 Invalidation frameworks

Many UI and reactive systems develop complex invalidation machinery to track:

- what changed
- what needs to be recomputed
- what is still valid
- what derived caches must be repaired
- what subtrees need redraw or rerender

In this pattern, much of that becomes a direct consequence of structural identity plus memoized boundaries.

If Apply preserves unchanged subtrees and boundaries are pure, then unchanged nodes naturally hit the cache.
Changed nodes naturally miss it.

That means a lot of invalidation logic can be replaced by:

- structural sharing
- memoize keys
- honest phase granularity

The system is still incremental, but incrementality is no longer a second architecture bolted onto the first one.

### 12.3 Observer buses and event-dispatch webs

In many systems, event handling expands into a broad web of:

- listeners
- subscriptions
- bubbling systems layered over other event systems
- change-notification graphs
- domain observers reacting to mutations happening elsewhere

Some local event routing may still be useful in specific execution contexts, but much of the broad architectural event machinery becomes unnecessary when:

- inputs are modeled as an Event ASDL
- Apply is the explicit state transition function
- later phases rederive the consequences structurally

Instead of saying:

- notify everyone who might care
- let them each inspect and mutate their own corner

the compiler-pattern story is more like:

- represent what happened explicitly
- compute the next source program
- recompile the consequences

That is usually much easier to reason about.

### 12.4 Dependency-injection containers and service-locator architecture

A lot of modern architecture accumulates global service access because key functions cannot get the information they need structurally from their inputs.

So systems grow things like:

- service containers
- dependency injection graphs
- registries passed everywhere
- context objects threaded through all major operations

Those tools can be useful in some environments, but in this pattern they are often symptoms that the modeled program or phase structure is underspecified.

If a pure transition or terminal keeps needing ambient access to global context just to do its semantic job, common causes include:

- missing source fields
- missing resolution phases
- hidden cross-references that should have been explicit IDs
- authored and derived facts mixed together

The better fix is often architectural, not infrastructural.

### 12.5 Hand-built runtime interpretation layers

Perhaps the biggest elimination is the accidental interpreter itself.

A lot of software ends up repeatedly interpreting domain structure at runtime through layers such as:

- dynamic dispatch tables over variants
- generic node walkers asking "what are you?" repeatedly
- runtime graph traversals rediscovering semantic facts
- renderer-style command systems that are really uncompiled authored trees
- general callback routers deciding domain behavior on the fly

The compiler pattern tries to consume that uncertainty earlier.

By the time execution runs, many of those questions should have already been answered.
The runtime machine should be much narrower and much less interpretive.

That is one of the pattern's deepest simplifications.

### 12.6 Redundant test scaffolding

When pure functions are really pure and their inputs are explicit modeled data, testing often becomes dramatically simpler.

A large amount of conventional test scaffolding exists to compensate for hidden dependencies, such as:

- mocks for services
- fake runtime environments
- setup frameworks
- elaborate fixtures standing in for global state
- custom dependency injection for tests

In the pure layer of this pattern, tests often reduce to:

1. construct ASDL input
2. call reducer/transition/terminal/projection
3. assert output

That is not a stylistic preference. It is a consequence of architectural explicitness.

When such tests become difficult, it is often a design diagnostic.
Something hidden is leaking into the supposedly pure layer.

### 12.7 Redundant runtime ownership machinery

Because Units pair behavior with owned runtime state, the architecture often avoids a lot of generic runtime ownership systems such as:

- external state registries
- independent lifecycle managers for compiled children
- detached runtime objects mirroring compiled structure
- custom per-node installation bookkeeping layers

This does not mean lifecycle concerns disappear entirely.
It means they are more often represented structurally by the Unit composition itself rather than by a second architecture invented to manage the first.

### 12.8 Framework-like glue that only exists to reconnect split truths

A useful way to summarize many of these eliminations is this:

> the pattern eliminates glue whose only job was to reconnect truths that should never have been split apart.

For example:

- if authored truth and semantic truth are explicitly connected by transitions, less glue is needed
- if compiled behavior and runtime state ownership are one Unit, less glue is needed
- if change propagation is largely handled by identity plus memoization, less glue is needed
- if interaction is an explicit Event language, less glue is needed

That is why the eliminations feel so broad.
They are all downstream of the same architectural simplification.

### What does not disappear

It is also important to be honest about what the pattern does **not** eliminate.

It does not eliminate:

- the need for careful domain modeling
- the need for backend engineering
- the need for integration with drivers, OS APIs, graphics libraries, audio systems, etc.
- the need for operational error handling in real runtime environments
- the need for performance work
- the need for judgment about phase design and Unit granularity

The pattern is not magic. It simply moves complexity to places where it is more explicit, more local, and more meaningful.

### Illustration: UI framework complexity vs compiler-shaped UI

A conventional UI framework may require layers for:

- retained state objects
- invalidation rules
- layout requests
- draw scheduling
- style resolution caches
- hit-test routing caches
- observer updates
- widget lifecycle bookkeeping

A compiler-shaped UI architecture can often collapse much of that into:

- source UI ASDL
- Event ASDL + Apply
- binding/layout/render-prep phases
- draw/hit-test Units
- structural memoization

The work has not vanished.
But the amount of separate coordinating infrastructure is often much smaller because the system no longer keeps rediscovering what the UI means through a live interpreted graph.

### Illustration: audio graph frameworks vs compiled Units

Likewise, an audio graph system may conventionally accumulate:

- runtime graph nodes
- mutation protocols
- scheduling infrastructure
- invalidation and dependency repair
- indirect per-node execution dispatch
- runtime state ownership protocols separate from graph description

A compiler-shaped audio architecture instead aims for:

- authored graph ASDL
- Event ASDL + Apply
- resolution/classification/lowering phases
- compiled signal-processing Units
- structural state composition
- hot swap of the installed machine

Again, the system is still doing real work. But far less effort is spent reconciling multiple architectural shadows of the same program.

### Elimination through better modeling, not through minimalism theater

It is worth emphasizing that the pattern does not eliminate infrastructure by being ascetic or by refusing to name necessary pieces.

It eliminates infrastructure by asking better questions first:

- what is the authored program?
- what are the real identities and variants?
- what knowledge should each phase consume?
- what should the leaf machine need?
- what runtime state should the Unit own?

When those questions are answered well, many conventional layers become unnecessary because they were compensating for weak answers to those questions.

### A warning against reintroducing the eliminated machinery

Once the pattern starts simplifying a codebase, there is still a temptation to reintroduce the old furniture by habit.

Common temptations include:

- adding a state manager where the source ASDL should suffice
- adding an observer bus where Event ASDL + Apply should suffice
- adding invalidation flags where identity + memoize should suffice
- adding a service container where a resolution phase should suffice
- adding runtime registries where Unit composition should suffice

Sometimes some of these tools are genuinely needed at specific backend boundaries.
But they should be treated as exceptions that require justification, not as default architecture.

### Key takeaway

In short:

> The compiler pattern eliminates a great deal of conventional infrastructure not by hiding complexity, but by removing the architectural splits that made so much coordinating machinery necessary in the first place.

With that consequence established, the next step is to widen the reader's imagination a bit:

- what kinds of systems this architecture can actually build.

---

## 13. What you can build

One risk of any architecture document is that readers unconsciously narrow the pattern to the examples that happened to reveal it first.

Because this repository grew out of Terra, code generation, audio ideas, and low-level runtime concerns, it would be easy for a reader to assume the pattern is mainly for:

- DSP graphs
- realtime audio engines
- low-level systems tools
- explicitly staged metaprogramming experiments

That would be much too narrow.

The compiler pattern is applicable anywhere the user is really editing a structured program in some domain and where repeated specialization is a better architectural fit than repeated interpretation.

That includes much more than audio.

### The general rule

A good domain for this pattern usually has several properties:

- the user is editing structured, persistent domain objects
- those objects have meaningful identity and relationships
- interaction changes the authored program over time
- later computation depends on derived semantic decisions
- the final runtime workload benefits from specialization
- repeated interpretation of the full domain structure would be wasteful or architecturally messy

Whenever that shape appears, the compiler pattern becomes a strong candidate.

### 13.1 Audio tools and synthesizers

Audio remains one of the clearest fits.

Why?
Because the domain naturally has:

- explicit user-authored structure
- graph or chain composition
- stable identities for devices, clips, nodes, routings, parameters
- derived semantic phases such as resolution, scheduling, and coefficient computation
- a hot execution path where repeated interpretation is undesirable

Examples include:

- synth graphs
- effects chains
- modular routing systems
- sequencers
- DAWs
- live performance tools

In all of these, the user is really editing a program.
The callback should run the compiled result of that program, not repeatedly rediscover what the program means in the hot path.

### 13.2 Text editors and structured editors

Text editors are another strong fit, especially once you stop thinking of them as merely mutable buffers.

A serious editor often contains rich structure such as:

- documents
- blocks
- spans
- cursors
- selections
- marks
- style rules
- folding state
- semantic references

User events edit that structure:

- insert
- delete
- move cursor
- change selection
- apply formatting
- scroll
- navigate

Later phases may then:

- resolve styles
- shape text
- compute line layout
- derive paint-ready runs
- produce hit-test structures

The visual execution layer benefits from receiving something much narrower than the raw authored editor model.

This is exactly the compiler-pattern story.

It becomes even more compelling in structured editors where the source is not merely text but some richer authored language.

### 13.3 UI systems and retained declarative interfaces

UI systems are one of the most interesting application areas for the pattern.

A retained UI tree is already very close to a source program.
It often contains:

- nodes
- content declarations
- layout rules
- visual styles
- interaction bindings
- references to resources
- view-specific or session-specific authored state

Later phases can then perform:

- binding and validation
- demand analysis
- layout solving
- flattening of visual items
- batching or payload lowering
- terminal realization for draw and hit-test Units

This often yields a much cleaner architecture than keeping a permanently live object graph that is interrogated every frame.

The UI is not a bag of widgets to be asked what they want over and over.
It is a program that can be recompiled when it changes.

### 13.4 Spreadsheets and notebook-like tools

A spreadsheet is an especially revealing example because people do not always think of it as a compiler architecture, even though it clearly is one in spirit.

The user authors:

- sheets
- cells
- formulas
- references
- formatting
- charts
- ranges

The system then needs to:

- resolve references
- compute dependency information
- evaluate formulas
- derive visual presentation
- update charts and views

This is a compiler-pattern-friendly problem because:

- the source is structured and persistent
- identities matter
- cross-references matter
- multiple derived products exist
- incremental recomputation matters a lot

The same is true of notebook-like tools that combine authored content, evaluation semantics, and presentation.

### 13.5 Vector editors, scene editors, and design tools

Visual authoring tools are also a strong fit.

Examples:

- vector editors
- layout tools
- node-based design tools
- scene editors
- animation editors
- visual diagram systems

These domains often involve:

- explicit persistent object identity
- containment and layering
- references and constraints
- authored styling and geometry intent
- derived layout, snapping, solved transforms, batching, and rendering payloads
- interaction-rich editing of a structured document

Such tools often accumulate a great deal of invalidation and object-lifecycle complexity when built as live interpreted graphs.

The compiler pattern offers a different route:

- source document as authored program
- event language for editing
- pure transitions for semantic and geometric solving
- specialized Units for draw/query/interaction execution

### 13.6 Protocol systems and structured interaction engines

The pattern is not limited to visibly graphical or audio domains.

Any domain with a user-authored or system-authored structured program can fit.
For example:

- protocol handlers
- workflow engines
- rules systems with closed domain structure
- structured interaction engines
- simulation control systems

If the runtime repeatedly asks a broad generic structure how to behave, and if that behavior can instead be narrowed and specialized ahead of execution, the pattern may help.

The key question is always:

> is the runtime repeatedly interpreting a structured program that could instead be compiled into a narrower machine?

If yes, the pattern may apply.

### 13.7 Simulations and live-authored systems

Simulations can also benefit, especially when the authored setup is rich and persistent.

Examples:

- scenario editors
- physics setup tools
- rule-based world configuration
- interactive simulations with authored entities and behaviors

The source model may contain:

- entities
- relationships
- authored parameters
- scenario structure
- interactive controls

Later phases may:

- validate references
- classify behavior families
- derive execution schedules
- compile step/query/render Units

Again, the advantage comes when execution can run specialized products rather than continually rediscovering the authored world's semantics.

### 13.8 Multi-output tools

Another important category is tools where the same source program feeds multiple outputs.

For example:

- one source tree drives execution
- another projection drives an editor view
- another projection drives an inspector/debugger
- another target emits export/build artifacts

This fits the pattern especially well because the architecture already assumes that multiple memoized products can be derived from the same source.

This is much cleaner than inventing several loosely synchronized models that each think they are the real app state.

### What all these domains have in common

Across all these examples, the same deep pattern appears.

There is:

- a user-facing language or structured program
- a meaningful authored state that persists
- an event language that changes it
- derived phases that consume knowledge
- one or more execution or presentation products
- benefit from specialization and incremental recompilation

That is the common shape.

The pattern is not tied to audio, not tied to graphics, not tied to Terra syntax, and not tied to any single backend.
It is tied to this shape of problem.

### What is a weaker fit

It is also worth saying that not every problem benefits equally.

The pattern is a weaker fit when:

- there is little or no persistent authored structure
- there are no meaningful phase boundaries
- execution is inherently generic and does not benefit from specialization
- the domain is mostly ad hoc dynamic scripting with little stable semantic structure
- the cost of modeling the source language exceeds the value of the resulting clarity and specialization

That does not mean the pattern cannot be stretched into such areas, only that its strongest advantages appear when the domain genuinely has a program-like shape.

### The imagination shift the reader should make

The most important thing this section should do is expand the reader's imagination.

The right question is not:

> is my domain like audio codegen?

The right question is:

> is my user editing a structured program whose meaning I keep rediscovering at runtime, and would it be better to compile that meaning into narrower machines?

That is the broader applicability test.

### Key takeaway

In short:

> The compiler pattern applies anywhere the user is really editing a structured domain program and repeated specialization yields a cleaner architecture than repeatedly interpreting a live generic object graph.

With that broader scope established, the final section can bring the whole rewrite together into one clear synthesis.

---

## 14. Final synthesis

This rewrite began by correcting the document's framing, but the real goal was larger than a terminology fix.

The goal was to state the pattern in the right order of importance.

Not:

- Terra first
- backend mechanics first
- code generation first

But instead:

- domain first
- source language first
- phase structure first
- Unit as the compile product
- backend as the realization layer

That is the real synthesis.

### The picture

By now, the architecture should read as one coherent story.

The user is editing a program.
That program is represented explicitly as source ASDL.
Inputs are represented explicitly as an Event ASDL.
Apply computes the next version of the source program.
Transitions consume unresolved knowledge across real phases.
Terminals first define the canonical `gen, param, state` machine for phase-local nodes, then backend realization packages that machine as executable Units.
Execution runs those Units until the source changes again.

That is the pattern.

### The one-sentence definition

If the whole document had to collapse to one sentence, it would be this:

> The compiler pattern treats interactive software as a live compiler: the user's domain program is modeled explicitly as source ASDL, evolved by a pure event reducer, narrowed across memoized phases into typed Machine IRs that make machine order, access, instances, resource identity, and state requirements explicit, compiled into canonical `gen, param, state` machines, and repeatedly packaged as specialized Units that run until the program changes again.

That sentence now says the important part first.

### The deepest design rule

The deepest design rule remains:

> the source ASDL is the architecture.

That is the center from which everything else follows.

If the source model is correct:

- save/load becomes truthful
- undo becomes natural
- transitions become simple
- terminals become local
- incrementality becomes natural
- backend choice becomes cleaner

If the source model is wrong, the rest of the system bends around that mistake.

That is why the pattern keeps returning to:

- domain nouns
- stable identity
- honest sum types
- correct containment
- clear authored vs derived vs runtime state splits

The architecture is downstream of those modeling choices.

### The live loop is small because the architecture is explicit

The loop:

```text
poll → apply → compile → execute
```

is not a simplification by omission.
It is a simplification by explicit architecture.

- poll gives explicit events
- apply edits the explicit source program
- compile rederives specialized artifacts through explicit phases
- execute runs the installed machine

Many conventional layers disappear not because they were never needed, but because the architectural ambiguity that required them has been removed.

### The two levels stay distinct

The pattern stays healthy when it preserves the distinction between:

- the compilation level, which decides what machine should exist
- the execution level, which runs that machine

This is why compiler-side boundaries must remain pure and structural, even when the emitted code will eventually talk to real backends like SDL, OpenGL, fonts, audio drivers, or native libraries.

The compiler side decides.
The runtime side runs.

That is one of the pattern's most important guardrails against drifting back into accidental interpretation.

### Units are the handoff artifact

The `Unit` is the architectural handoff between those two levels.

Immediately above that handoff is the canonical machine layer:

- `gen`
- `param`
- `state`

And `Unit` packages that machine as:

- specialized realized behavior
- owned runtime state layout

The resulting artifact still composes structurally the same way the source program composes structurally.

This is why the Unit concept matters so much:

- it keeps behavior and state ownership together
- it makes hot swap conceptually simple
- it keeps runtime structure aligned with source structure
- it turns compiled subtrees into explicit installable artifacts

The Unit is where "this subtree means something" becomes "this subtree is now a machine."

### The architecture is backend-neutral

The central correction of this rewrite is now easy to state cleanly:

> The pattern is not Terra.

Historically, Terra made the architecture visible first.
But the architecture itself is backend-neutral.

The stable center is:

- modeled source ASDL
- Event ASDL
- Apply
- phase structure
- Machine IR
- canonical `gen, param, state`
- terminals
- Units
- memoized incremental recompilation

That center can be realized by more than one backend.

### The three-layer split

The architecture now has a clear three-layer form:

#### 1. Domain layer
The application's actual semantics:

- source model
- events
- reducer
- phases
- projections
- Machine IRs and terminal intent

#### 2. Pattern layer
The reusable compiler vocabulary:

- canonical `gen, param, state` machine thinking
- Machine IR as the typed machine-feeding layer
- Unit
- transition
- terminal
- memoize
- match
- with
- fallback
- errors
- inspect

#### 3. Backend layer
The target-specific realization:

- leaf code shape
- state representation
- compose realization
- installation/hot swap
- drivers
- host compiler or JIT

This split is what makes one app architecture usable across multiple targets.

### The backend policy

The practical backend policy that follows is:

> **LuaJIT by default. Terra by opt-in.**

That policy is not anti-Terra.
It is pro-clarity.

LuaJIT is the default on JIT-native platforms because:

- the host runtime already provides much of the final compiler
- terminal construction is very cheap
- deployment is lighter
- iteration is faster
- runtime performance is often strong enough to be the best overall tradeoff

Terra is the opt-in strong backend because it gives:

- explicit staging
- static native types
- structural state-layout synthesis
- ABI control
- LLVM optimization
- low-level native expressiveness

That is a better relationship between the backends and the architecture.

### Terra still has a special role beyond raw speed

One of the important clarifications added during this rewrite is that Terra matters for more than just throughput.

Terra also acts as design pressure.
It makes the right structure easier to see and bad structure harder to hide.

Because Terra forces explicitness in:

- type layout
- staging boundaries
- state ownership
- machine shape
- compilation granularity

it often reveals:

- missing phases
- vague source models
- coarse recompilation boundaries
- unclear authored/runtime splits
- over-wide leaf inputs

That is why a good mental model is:

> design with Terra-level explicitness in mind, even when LuaJIT is the default realization backend.

Or more sharply:

> designing with Terra in mind makes the right structure simple and makes bad structure hard to miss.

But once the LuaJIT backend is constrained correctly, a second statement also becomes true:

> strict LuaJIT can impose almost the same architectural pressure, because the leaf must still end as `Unit { fn, state_t }` over typed backend-native layout.

The difference is that Terra provides stronger mechanical enforcement through explicit native staging, while LuaJIT provides the same pressure only if the backend rules are kept strict.

This is one of Terra's enduring architectural values.

### The performance model is architectural first

Another important synthesis is that performance in this pattern is not merely about hot arithmetic.
It is about the whole compiler loop.

The two major costs are:

- rebuild cost
- run cost

And the biggest performance wins often come first from:

- better source modeling
- better identity boundaries
- narrower phases
- better Unit granularity
- better bake/live decisions
- and redesigning the ASDL above the first slow boundary whose lower consumer is already trusted

Only after those are right do low-level backend optimizations pay their full value.

This is a healthier performance model than starting with isolated micro-benchmarks detached from the compilation architecture.
It is also why the recursive benchmarking law matters: once a lower machine is trusted, the next slow boundary points upward into the language and phase design above it.

### What the pattern eliminates

Because the architecture is explicit, it often removes the need for large amounts of conventional glue:

- state-management scaffolding
- invalidation frameworks
- observer webs
- service-container architecture
- redundant runtime ownership systems
- heavy test scaffolding
- hand-built accidental interpreters over the live object graph

Again, this is not because the pattern denies complexity.
It is because it removes architectural splits that used to require coordination machinery.

### What the pattern can build

Finally, the rewrite should leave the reader with a widened sense of scope.

This architecture is not only for:

- audio
- DSP
- Terra metaprogramming demos

It is also for:

- UI systems
- text editors
- spreadsheets
- notebooks
- vector and scene editors
- simulation tools
- structured protocol systems
- many other domains where the user is really editing a structured program

The common shape is what matters, not the original example family.

### The mental model

If the reader should leave with one complete mental model, it is this:

- the user edits a program
- the source ASDL is that program
- events edit it through Apply
- transitions narrow it across phases
- terminals realize it as Units
- Units own the runtime state needed to execute
- the backend decides how those Units become executable on this target
- the live loop keeps recompiling and running as the program changes

That is the architecture in its final, backend-neutral form.

### Compact summary

```text
THE USER
    edits a domain program

THE SOURCE OF TRUTH
    source ASDL

THE INPUT LANGUAGE
    Event ASDL

STATE EVOLUTION
    Apply : (state, event) -> state

THE PURE ARCHITECTURE
    memoized transitions and terminals

THE COMPILE PRODUCT
    Unit { behavior, state ownership }

THE LIVE SYSTEM
    poll -> apply -> compile -> execute

THE BACKEND STORY
    LuaJIT by default
    Terra by opt-in

THE TERRA INSIGHT
    explicit types and staging are not just backend power
    they are design pressure

THE DEEPEST RULE
    the source ASDL is the architecture
```

And the final sentence of the whole document can be simple:

> The pattern is not Terra. The pattern is domain-compilation-driven design for interactive software, and Terra is one especially powerful way to realize it when explicit native control is worth the cost.
