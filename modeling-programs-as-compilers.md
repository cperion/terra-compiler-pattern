# Modeling Programs as Compilers — The Design Method

## The hard part is not the pattern. The hard part is the ASDL.

Historically, this repository called the architecture the Terra Compiler Pattern. But the modeling method described here is backend-neutral. The six architectural primitives are still the same in spirit: ASDL `unique`, Event ASDL, Apply, memoized stage boundaries, LuaFun-style pure transforms, and Unit. The implementation is small, and the real `unit.t` includes `Unit.inspect(...)` so progress, docs, scaffolds, prompts, and tests are derived directly from the ASDL and installed methods. They produce incremental multi-stage compilers with hot-swap, state management, error handling, and zero-alloc execution — all as emergent properties of composition.

But the primitives are tools. They don't tell you WHAT to compile. They don't tell you what your types should be. They don't tell you what phases to define. They don't tell you where knowledge is consumed. They don't tell you which sum types to create or when to eliminate them.

That's the hard part. And it must be done RIGHT, upfront, before a single line of implementation. Because the ASDL IS the architecture. A wrong type in the source phase propagates through every phase, every boundary, every compiled output. You can't refactor a phase boundary after 50 functions depend on it. The cost of a wrong early decision compounds through the entire pipeline.

This document is about how to make those decisions.

---

## 1. First Principles

### 1.1 A program is a function from user intent to machine execution

Every interactive program takes human gestures (clicks, keystrokes, drags, voice commands) and produces machine behavior (pixels on screen, samples to speakers, bytes to network, commands to hardware).

Between intent and execution, there is a GAP. The user thinks in domain concepts ("make this louder," "move this paragraph," "connect these nodes"). The machine operates on registers, memory addresses, shader programs, and audio buffers. The program's job is to bridge this gap.

Traditional programs bridge the gap at runtime, every frame, with dispatch tables, virtual calls, config lookups, and state machines. They are INTERPRETERS — they re-answer "what should I do?" every cycle.

The compiler pattern bridges the gap at edit time, once, by COMPILING the user's intent into a specialized executable machine. On Terra that may be explicit native code. On LuaJIT it may be a highly specialized closure and state layout that the host JIT compiles aggressively. The compiled result runs until the intent changes. When it changes, the compiler runs again (incrementally — only the changed subtree).

### 1.2 The gap has layers

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

### 1.3 These layers ARE your phases

Each layer is an ASDL module. Each transition between layers is a memoized function. The phases are not arbitrary — they reflect the actual structure of knowledge resolution in your domain.

The question "how many phases should I have?" is answered by: "how many distinct levels of knowledge resolution does your domain have?" Not more. Not fewer. Each phase should consume at least one meaningful decision. If a phase doesn't resolve anything, it shouldn't exist. If a phase resolves two unrelated things, it should be two phases.

### 1.4 The source phase is the most important

The source phase — the first phase, the one the user edits — determines everything. It is the input language of your compiler. Every other phase is derived from it. Every boundary transforms it. Every Unit compiles it.

If the source phase is wrong — if it models the wrong concepts, or models them at the wrong granularity, or couples things that should be independent, or separates things that should be together — every downstream phase inherits the mistake. The entire pipeline compiles the wrong thing correctly.

Getting the source phase right requires understanding the domain deeply enough to answer: "what are the NOUNS of this domain?" Not the implementation nouns (buffers, callbacks, handlers). The DOMAIN nouns (tracks, clips, parameters, curves, connections, constraints). The things the USER thinks about. The things that appear in the UI. The things that get saved to disk and loaded back.

---

## 2. The Modeling Method

### 2.1 Step 1: List the nouns

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

### 2.2 Step 2: Find the identity nouns

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

### 2.3 Step 3: Find the sum types

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

Each "or" becomes an ASDL enum. Each option becomes a variant. This is where domain expertise matters most — missing a variant means the system can't represent something the user needs. Adding a variant later means every `Unit.match` in the pipeline needs a new arm.

### 2.4 Step 4: Find the containment hierarchy

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

### 2.5 Step 5: Find the coupling points

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

### 2.6 Step 6: Define the phases

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


---

## 3. Quality Tests for the Source Phase

The source ASDL determines everything downstream. These tests help you know if it's right.

### 3.1 The Save/Load test

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

### 3.2 The Undo test

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

### 3.3 The Collaboration test

Two users edit the same project simultaneously. They edit different things (different tracks, different parameters). Can their edits be merged?

ASDL trees are VALUES, not mutable objects. Merging two value-trees is a structural operation: for each node, take the newer version. If both users edited the same node, conflict. This works naturally if:

- Each identity noun has a stable ID
- Edits produce new ASDL nodes (structural sharing for unchanged subtrees)
- The merge algorithm walks both trees and picks the non-conflicting updates

If merging requires understanding the semantics of the edit (not just the structure), the source ASDL is too coarse-grained. Each independently editable thing should be its own ASDL node.

### 3.4 The Completeness test

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

### 3.5 The Minimality test

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

### 3.6 The Orthogonality test

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

### 3.7 The LuaFun test

For each function you write — every transition, every terminal, every reducer arm, every projection — ask: "Can I express this as a LuaFun chain?" If yes, the ASDL is well-modeled. If no, the ASDL is wrong.

This is the most practical of all the quality tests. It catches problems at implementation time, not design time. You designed the ASDL, you passed the save/load test, the undo test, the completeness test. You start writing the transition function. And the code resists.

```
You need a mutable accumulator:
    fun.iter(nodes):map(f):totable()  should work.
    If it doesn't — if f needs state from previous iterations —
    the nodes are not independent. They're coupled.
    → Split the data so each node is self-contained,
      or add a phase that resolves the coupling first.

You need to look up another node by ID:
    fun.iter(nodes):map(function(n)
        local target = find_by_id(all_nodes, n.target_id)  -- breaking out!
        ...
    end)
    → The lookup means you need context the current node doesn't carry.
      This belongs in a Resolved phase that already linked the references.
      After resolution, the data the node needs is ON the node.

You need imperative control flow (break, early return, mutation):
    for i, node in ipairs(nodes) do
        if node.kind == "special" then
            result[i] = handle_special(node)  -- can't do this in map
        else ...
    → The sum type should make "special" a variant.
      Unit.match handles it. LuaFun maps over the rest.
      The imperative control flow was compensating for a missing variant.
```

The rule is: **every function in the pure layer is a LuaFun chain.** Transitions, terminals, apply reducers, projections, helpers. All of them. If a function resists LuaFun, don't fight LuaFun — fix the ASDL. LuaFun is the quality probe that catches modeling errors at the moment you try to implement them.

This is also why LuaFun is listed as a primitive, not a utility. It is the enforcement mechanism that makes the purity guarantees real. ASDL gives you immutable values. Memoize gives you identity-based caching. LuaFun gives you the guarantee that the functions operating on those values are actually pure. Without it, purity is a discipline. With it, purity is the path of least resistance.

### 3.8 The Testing test

For each function you write, ask: "Can I test this with nothing but an ASDL constructor and an assertion?" If yes, the design is right. If no — if you need mocks, fixtures, setup, teardown, a running server, a database, environment variables, or a specific ordering of prior calls — then the function has hidden dependencies, which means the ASDL is incomplete or the function is impure.

This is not really a separate test. It is a consequence of all the other tests passing. If the ASDL is complete (3.4), minimal (3.5), orthogonal (3.6), and the functions are LuaFun chains (3.7), then testability falls out automatically. But it is worth calling out as its own checkpoint because it catches a specific failure mode: functions that look pure but reach into context.

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

The rule is: **every function is testable with one constructor call and one assertion.** If it needs more, trace the extra dependency back to the ASDL. Either the data is missing (incomplete ASDL), the phases are wrong (unresolved coupling), or the function is impure (escaping LuaFun). The fix is always upstream, never at the test site.

This also means the entire testing infrastructure dissolves:
- **No test framework** — setup/teardown have nothing to set up.
- **No mocks** — pure functions have no external dependencies.
- **No fixtures** — ASDL constructors are self-contained.
- **No regression suite** — memoize is the regression oracle. Same input to changed function: if memoize recomputes, behavior changed.
- **No property testing library** — ASDL types define the space of valid inputs. Random testing is: random ASDL constructor arguments → call function → assert structural properties.
- **No flaky tests** — pure functions produce the same output for the same input. Always.

### 3.9 The memoize-hit-ratio test

Once the pipeline exists, there is another extremely practical design test available:

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

Use it the same way you use the save/load test, the undo test, and the LuaFun test: not as a performance tweak, but as a diagnostic for whether the model and phase boundaries are right.

---

## 4. Type Design Principles

### 4.1 Sum types are domain decisions

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

### 4.2 Fewer sum types downstream

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

### 4.3 Records should be deep modules

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

### 4.4 IDs should be structural, not sequential

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

### 4.5 Lists vs. maps

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

### 4.6 References across the tree

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


---

## 5. Phase Design

### 5.1 The universal phase pattern

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

### 5.2 Phase 1: Vocabulary

This is the user's language. The types mirror the UI. Every button, every panel, every editable field corresponds to a field in this phase.

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

### 5.3 Phase 2: Semantic model

The vocabulary contains user-facing abstractions that hide complexity. Phase 2 UNFOLDS these abstractions into their semantic meaning.

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

### 5.4 Phase 3: Resolved

Cross-references are validated. IDs are stable. Everything that references something else is confirmed to reference a real thing.

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

### 5.5 Phase 4: Classified

Domain-specific classification. In a DAW: rate classes (sample, block, init, constant). In a layout engine: sizing categories (fixed, flex, intrinsic). In a spreadsheet: cell volatility (static, depends-on-volatile).

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

### 5.6 Phase 5: Scheduled

The execution plan. Resources allocated. Order determined. This is the last phase before compilation. Everything is concrete — numbers, indices, offsets.

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

### 5.7 Phase 6: Compiled

Terminal boundaries produce Units. This is not a "phase" in the ASDL sense — there are no ASDL types. The output is `{ fn, state_t }`. The Unit IS the final phase.

### 5.8 When to merge phases

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

---

## 6. Designing for Incremental Compilation

The memoize cache is the incremental compilation system. Its effectiveness depends on how the ASDL is structured.

### 6.1 Structural sharing

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

Or with `Unit.with`:

```lua
local new_track = Unit.with(old_track, { volume_db = -3 })
-- Returns a new ASDL node with volume_db changed, all other fields identical.
-- The devices field is the SAME object as old_track.devices.
-- Memoize on devices hits.
```

### 6.2 The granularity tradeoff

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

### 6.3 What makes a good memoize key

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

---

## 7. Parallelism Falls Out of the ASDL

The ASDL dependency graph IS the execution plan. Multithreading, parallelization, and execution planning are not features you add on top — they are properties you READ from the ASDL structure.

### 7.1 The graph encodes the dependencies

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

### 7.2 Why this works

The pattern's purity guarantees make parallelism safe by construction:

- **Memoized functions are pure.** They depend only on their explicit arguments. No shared mutable state, no side effects, no ordering requirements.
- **ASDL nodes are immutable.** Once constructed, they never change. Two parallel threads reading the same node see the same value.
- **Memoize handles deduplication.** If two parallel branches reach the same shared subnode, one compiles and caches, the other gets a cache hit.
- **Identity is structural.** ASDL `unique` means the same arguments produce the same object. No race on identity — identity is determined at construction.

Traditional architectures need thread pools, schedulers, synchronization primitives, and dependency graphs as SEPARATE INFRASTRUCTURE because their dependency information is scattered across mutable state, callbacks, and implicit ordering. The pattern concentrates all dependencies in one place — the ASDL tree — and makes them immutable.

### 7.3 The modeling consequence

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

The same granularity that gives you good incrementality (Section 6) also gives you good parallelism. One memoize boundary per identity noun means one unit of parallelism per identity noun. The design choices compose.

### 7.4 What this eliminates

No thread pool. No task queue. No fork-join framework. No dependency graph library. No work-stealing scheduler. No futures or promises for compilation coordination. The ASDL graph is all of these things — it just doesn't know it.

This is the same pattern as every other "eliminated" system: the information already exists in the ASDL structure. Building a separate system to represent it is redundant. Building a separate system to manage it is reconciliation work that shouldn't exist.

---

## 8. Designing the View / UI Projection

Every program has at least two pipelines from the same source:

```
Source ASDL ──transition──> ... ──terminal──> Execution Unit
             │
             └──projection──> View ASDL ──terminal──> Render Unit
```

The execution pipeline produces the domain output (audio, computed cells, game frame). The view pipeline produces the visual representation (pixels on screen). Both start from the same source ASDL. Both are memoized independently. Editing the source recompiles both — but only the changed subtrees.

### 8.1 The View is NOT the source

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

### 8.2 The View's own phase pipeline

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

### 8.3 The semantic ref connection

Errors from the domain pipeline carry semantic refs (TrackRef, DeviceRef, ClipRef). The View knows which visual elements correspond to which semantic refs (because the projection maintained the mapping). When an error says `DeviceRef(42) failed`, the View finds the visual element for Device 42 and shows the error there.

This works because the source ASDL node identity (the `id` field) flows through both pipelines — through the domain compilation AND through the View projection. The ID is the shared key.

---

## 9. Common Modeling Mistakes

### 9.1 Modeling the implementation instead of the domain

```
WRONG (implementation model):
    AudioEngine = (BufferPool pool, CallbackFn callback,
                   ThreadHandle thread, MutexHandle lock)

RIGHT (domain model):
    Project = (Track* tracks, Transport transport,
               TempoMap tempo, AssetBank assets)
```

The implementation model describes HOW the program works. The domain model describes WHAT the user works with. The pattern compiles the domain model INTO the implementation. If you put the implementation in the source, you're compiling the compiler.

### 9.2 Mixing phases

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

### 9.3 Over-flattening

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

### 9.4 Under-flattening

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

### 9.5 Missing a phase

Symptom: a boundary function is doing two unrelated things. It resolves cross-references AND assigns buffer slots. It lowers containers AND validates connections.

Fix: split into two phases. Each boundary should do ONE kind of knowledge consumption. If it does two, you're missing a phase between them.

### 9.6 Using strings where enums belong

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
    -- Each variant has its own fields. Unit.match is exhaustive.
    -- Adding a variant forces all match sites to handle it.
```

Strings are bags. Enums are types. Every string that represents a fixed set of options should be an enum. Every string that represents a fixed set of choices with different fields should be an enum with fields.


---

## 10. The Implementation Discovery

The modeling method (Sections 1-6) gives you a first draft of the ASDL. That draft is a hypothesis. Implementation tests it. The testing direction is bottom-up: start at the leaves, let each leaf tell you what the layers above must provide, and fix the ASDL from the bottom up.

### 10.1 Write the leaf you want to write

Don't start by implementing the full pipeline top-down. Start at the leaf — the function that takes one phase-local node and produces a `Unit` for the machine. Write the leaf you WANT to write, the one that would be natural if the ASDL were perfect.

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

### 10.2 Modify the layer above

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

### 10.3 Why this gives the earliest ASDL warnings

The leaf compiler is the smallest function in the system — often 10-20 lines. It is also the most honest function. It has no room to hide a bad ASDL.

```
Missing field           → ASDL is incomplete, add to source and propagate
LuaFun resistance       → prior phase didn't resolve a coupling
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

### 10.4 The design cycle

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

You model a bit (Sections 1-6), sketch a kernel, discover the model is wrong, fix it, sketch the next leaf, discover another missing phase, fix that. The modeling method tells you WHERE to look — which nouns, which phases, which coupling points. The leaves tell you WHAT to put there — which fields, which resolutions, which phase boundaries. Neither works alone. Together, they converge on the correct ASDL: the one where every leaf is a natural LuaFun chain, every phase transition has one real verb, and the installed machine is exactly the one you wanted to build.

The convergence criterion is:

**every leaf compiles as a clean structural transform with no reaching, no hidden context, no runtime interpretation of authored structure, and a clear bake/live split between code and `state_t`.**

When that's true, the ASDL is done. When it's not, the resistance tells you exactly what to fix and where.


---

## 11. Worked Examples

### 11.1 Text editor

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

### 11.2 Spreadsheet

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

### 11.3 Drawing / vector graphics app

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

### 11.4 Game / simulation

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

## 12. The Master Checklist

Before writing any implementation, answer these questions about your source ASDL:

### 12.1 Domain nouns
```
□ Listed every user-visible noun
□ Classified each as identity noun or property
□ Each identity noun has a stable ID
□ Each property is a field on its identity noun
□ No implementation nouns in the source (no buffers, threads, callbacks)
```

### 12.2 Sum types
```
□ Every "or" in the domain is an enum
□ Every enum has ≥ 2 variants
□ Each variant has its own fields (not shared with siblings)
□ No strings used where enums belong
□ Every variant is reachable from the UI
□ Every user action produces a valid variant
```

### 12.3 Containment
```
□ Drawn the containment tree
□ Each parent owns its children (no shared ownership)
□ Cross-references are ID numbers, not Lua references
□ Lists use ASDL *, not Lua tables
□ Recursive types use * or ? (no infinite structs)
```

### 12.4 Phases
```
□ Named each phase
□ Named each transition verb (lower, resolve, classify, schedule, compile)
□ Each phase consumes at least one decision (sum type eliminated or reduced)
□ Later phases have fewer sum types
□ Terminal phase has zero sum types
□ No phase can be merged without losing a meaningful distinction
□ No phase should be split without a clear additional decision to resolve
```

### 12.5 Coupling points
```
□ Identified every place where two subtrees need each other's information
□ Determined which must be resolved in the same phase
□ Determined which determines the other's order
□ These orderings are consistent (no cycles between phases)
```

### 12.6 Quality tests
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

### 12.7 Incremental compilation
```
□ ASDL types are marked unique
□ Edits produce new nodes with structural sharing (not deep copy)
□ Memoize boundaries align with identity nouns
□ The changed subtree is small relative to the whole
□ Unchanged subtrees are identical Lua objects (not copies)
```

### 12.8 Parallelism
```
□ Independent subtrees can compile in parallel (no shared mutable state)
□ Memoize boundaries align with parallelism units (one per identity noun)
□ Granularity is coarse enough to avoid scheduling overhead
□ No implicit ordering between independent branches
```

### 12.9 LuaFun enforcement
```
□ Every transition function is expressible as a LuaFun chain
□ Every reducer arm is expressible as a LuaFun chain
□ No mutable accumulators needed (data is self-contained per node)
□ No mid-chain lookups needed (references resolved in prior phase)
□ No imperative control flow needed (sum types handled by Unit.match)
□ If a function resists LuaFun → fix the ASDL, not the code
```

### 12.10 View / UI
```
□ View is a separate ASDL, projected from source
□ View elements carry semantic refs back to source
□ View has its own phase pipeline (Decl → Laid → Batched → Compiled)
□ Errors flow from domain pipeline to View via semantic refs
```

### 12.11 Implementation discovery (leaves-up)
```
□ Started at leaf compilers, not at top-level pipeline
□ Each leaf compiles as a clean LuaFun chain — no reaching, no context args
□ Missing fields discovered by leaves were added to ASDL and propagated up
□ Layers above were modified to provide what leaves demanded
□ ASDL stabilized when leaves stopped demanding changes
□ Design (top-down) and implementation (bottom-up) interleaved until convergence
```

---

## 13. The Deep Insight

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

These are the same properties that make a PROGRAMMING LANGUAGE good. Because that's what the source ASDL is — a domain-specific programming language whose programs are domain artifacts (songs, documents, spreadsheets, games) and whose compiler produces native executables that realize those artifacts.

Every interactive program is a compiler. The source language is the UI. The ASDL is the IR. The pipeline is the optimizer. The Unit is the object code.

And because the ASDL and the pipeline are pure — ASDL nodes are immutable values, transitions are memoized functions, compositions are structural — the entire design is target-independent. The same ASDL types, the same phases, and the same transitions can realize Terra/LLVM native code, LuaJIT-specialized closures, JavaScript, or WASM. Only the leaf compilation — the terminal boundary where ASDL becomes executable machinery — touches the backend. The modeling method described in this document produces an architecture that is portable across targets without redesign, because the design decisions live in the pure layer, and the pure layer doesn't know what machine it's on.

Design the language well, and the compiler writes itself. Design it poorly, and no amount of implementation effort can fix it. The ASDL is the architecture. Everything else is derived.

---

## 14. Summary

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
    Start at the leaf compiler. Write the function you want to write.
    The leaf tells you what the ASDL must provide.
    Fix the layer above. Recurse upward to the source ASDL.
    Every function is a LuaFun chain. If it resists — fix the ASDL.

12. CONVERGE
    Steps 1-10 give a top-down draft. Step 11 tests it bottom-up.
    The ASDL stabilizes when leaves stop demanding changes.
    Design and implementation interleave until convergence.
```

The hard part is steps 1-10. Step 11 is where the leaves either confirm the design is right or send you back to fix it. The direction is bottom-up: write the leaf you want to write, discover what it needs, modify each layer above to provide it, recurse to the source ASDL. Steps 1-10 tell you WHERE to look. Step 11 tells you WHAT to put there. When the ASDL is correct, every leaf is a natural LuaFun chain and every phase transition is obvious. When it's not, the leaf resistance is the signal — and it arrives in 10 lines, not 500. The ASDL is the architecture. The leaves are the proof.
