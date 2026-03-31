# The Minimal Architectural Vocabulary for ASDL

This document proposes a compact vocabulary for designing good ASDL in the compiler pattern.

The motivating question is:

> what is the smallest set of type-shapes and architectural roles we need in order to model interactive software well?

The claim of this document is that there are really **two different minimal sets**:

1. a minimal set of **formal type constructors**
2. a minimal set of **architectural roles**

Those two levels should not be confused.

At the formal level, ASDL only needs a small algebra.
At the architectural level, recurring design patterns emerge: entity, variant, projection, spine, facet.

The practical payoff is that once this vocabulary is clear, design becomes much more compositional:

you do not invent large custom shapes from scratch; you compose a small number of known shapes correctly.

---

## 1. Two minima

### 1.1 The formal minimum

At the deepest level, most useful ASDL can be built from:

- **product** — a record with fields
- **sum** — a tagged choice / enum / variant
- **sequence** — zero or more children
- **reference** — a stable cross-link by ID
- **identity** — stable naming of independently editable things

This is the algebra.

If all you want to know is the smallest mathematical basis, stop here.

But in practice, this basis is too low-level to guide architecture. It does not tell you:

- what deserves stable identity
- which choices belong in the source ASDL
- when a derived phase should split into branches
- when several branches should share one structural alignment space
- when one lower node should become several aligned semantic planes

For that, we need a second vocabulary.

### 1.2 The architectural minimum

A more useful working vocabulary for this repository is:

- **entity**
- **variant**
- **projection**
- **spine**
- **facet**

These are not new formal type constructors.
They are recurring architectural roles built out of products, sums, sequences, references, and stable identity.

This document argues that these five roles are close to the minimal practical vocabulary for designing ASDL well.

---

## 2. The five architectural roles

## 2.1 Entity

An **entity** is a persistent user-visible thing with stable identity.

Examples:

- track
- clip
- device
- block
- span
- cell
- chart
- layer
- node

An entity answers:

> what is the thing the user can point to and say "that one"?

An entity is usually:

- a product type
- marked `unique` when it is a concrete ASDL type
- given a stable numeric ID
- owned by exactly one parent in the containment tree

### Example: source entities in a text editor

```asdl
Editor.Document = (Block* blocks, Selection selection) unique
Editor.Block = (number id, BlockKind kind, Span* spans) unique
Editor.Span = (number id, SpanKind kind, string text) unique
```

Here:

- `Document`, `Block`, and `Span` are entities
- the user can independently edit blocks and spans
- the IDs must remain stable across reordering

### Non-entity example

```asdl
Editor.Block = (number id, string text, number line_count) unique
```

If `line_count` is derived from `text`, then `line_count` is **not** an entity and should not even be a source property. It is derived data.

So entity is about authored identity, not about every fact that can be named.

---

## 2.2 Variant

A **variant** is a real domain “or”.

Examples:

- a clip is audio **or** MIDI
- a selection is cursor **or** range
- a chart is bar **or** line **or** pie
- a node is gain **or** filter **or** oscillator

A variant answers:

> what closed set of kinds can this thing be?

A variant is usually a sum type.

### Example: authored domain variants

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

### Bad pattern

```asdl
Editor.Block = (number id, string kind, string text, string language) unique
```

This is a smell because:

- `kind` is a string instead of a sum
- `language` is only meaningful for some cases
- every boundary later has to interpret `kind`

Better:

```asdl
Editor.Block = (number id, BlockKind kind, Span* spans) unique
Editor.BlockKind = Paragraph | Quote | CodeBlock(string language)
```

---

## 2.3 Projection

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

Projection is crucial because the source ASDL must model the user’s world, not every consumer’s world.

### Example: source versus view

```asdl
Editor.Track = (number id, string name, Device* devices) unique
```

A view may need:

- a track header row
- a mixer strip
- a device list panel
- selected styling
- hit targets

That should not be stuffed into `Editor.Track`.
Instead:

```asdl
View.TrackHeader = (number track_id, string label, bool selected)
View.MixerStrip = (number track_id, string label, number meter_db)
View.DevicePanel = (number track_id, DeviceCard* cards)
```

This is a projection, not a mutation of the source.

### Example: a resolve phase

```asdl
Editor.Send = (number id, number target_track_id, number gain_db) unique
Resolved.Send = (number id, number target_track_id, number gain_db,
                 number target_bus_ix) unique
```

`Resolved.Send` is a projection that has consumed a routing decision.

Projection is the generic “derived phase-local shape” role.
Later sections show that spine and facet are more specialized projection patterns.

---

## 2.4 Spine

A **spine** is a shared structural alignment space used by several downstream branches.

A spine answers:

> what shared structure must later branches remain aligned on?

Typical spine facts:

- stable identity
- flattened order
- parent/child topology
- subtree spans
- region-local indices
- addressability
- execution order

A spine is usually carried by a header-like product type.
That is why the main document often says **header spine**.

### Important claim

**Header is not a separate primitive next to spine.**

A **header** is usually the concrete carrier record for the **spine** role.
So the cleaner ontology is:

- **spine** = the architectural role
- **header** = the common record shape that carries it

### Example: flattened view spine

Suppose a document view is flattened for later layout, paint, hit-test, and accessibility passes.
A bad design is one giant lower node:

```asdl
BadView.Node = (
    number id,
    number parent_id,
    number start_ix,
    number end_ix,
    Rect rect,
    PaintStyle paint,
    string text,
    HitBehavior hit,
    A11yRole role,
    A11yLabel label
) unique
```

Every branch now carries everything just to stay aligned.

A spine-based design is:

```asdl
View.Header = (
    number id,
    number parent_ix,
    number start_ix,
    number end_ix,
    NodeRole role
) unique
```

Now every later branch can stay aligned through `Header` rather than through a giant semantic bag.

### Example: audio schedule spine

Several later audio branches may need the same execution and bus topology:

```asdl
Scheduled.Header = (
    number node_id,
    number order_ix,
    number input_bus_ix,
    number output_bus_ix,
    number channel_count
) unique
```

A coefficient compiler may need `node_id` and `channel_count`.
A bus allocator may need `input_bus_ix` and `output_bus_ix`.
An execution pass may need `order_ix`.
They share one spine instead of one swollen node.

---

## 2.5 Facet

A **facet** is one orthogonal semantic plane aligned to a shared spine.

A facet answers:

> given the shared structure, what aspect of this thing are we talking about?

Typical facets:

- layout facet
- paint facet
- content facet
- behavior facet
- accessibility facet
- query facet
- animation facet
- routing facet

A facet is not the structure itself. It is meaning attached to a shared structural alignment space.

### Example: UI facets aligned to one header spine

```asdl
View.Header = (
    number id,
    number parent_ix,
    number start_ix,
    number end_ix,
    NodeRole role
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

All four facets align to the shared `id` / index space defined by the header spine.

Now:

- layout lowering can use `Header + LayoutFacet`
- paint lowering can use `Header + LayoutFacet + PaintFacet`
- hit testing can use `Header + LayoutFacet + HitFacet`
- accessibility can use `Header + A11yFacet`

This is better than one giant lower node because unrelated edits remain more local.

### Example: audio facets aligned to one schedule spine

```asdl
Scheduled.Header = (
    number node_id,
    number order_ix,
    number input_bus_ix,
    number output_bus_ix,
    number channel_count
) unique

Scheduled.CoeffFacet = (
    number node_id,
    double* coeffs
) unique

Scheduled.MeterFacet = (
    number node_id,
    bool meter_enabled,
    number meter_bus_ix
) unique
```

A render callback may need `Header + CoeffFacet`.
A UI meter projection may need `Header + MeterFacet`.
Those concerns no longer travel together by force.

---

## 3. The formal basis and the architectural basis are related

The five architectural roles are not magic. They are compositions of the formal basis.

| Architectural role | Usually built from |
|---|---|
| Entity | product + identity + containment |
| Variant | sum |
| Projection | products/sums derived from earlier phases |
| Spine | product + identity + index/order/topology fields |
| Facet | product aligned to a spine by shared ID/index space |

This is why the architectural vocabulary feels small and reusable: it is a disciplined way of arranging a very small algebra.

---

## 4. Source phases versus lower phases

A common source of confusion is trying to use lower-phase concepts too early.

The source ASDL and lower ASDL do not have the same jobs.

## 4.1 Source-phase vocabulary

At the source level, the dominant concepts are:

- entity
- property
- variant
- containment
- reference

Questions at this layer:

- what are the user-visible nouns?
- which nouns have stable identity?
- what fixed choices are true domain variants?
- what owns what?
- what cross-references must be represented by ID?

### Example: source document

```asdl
Editor.Document = (Block* blocks, Selection selection) unique
Editor.Block = (number id, BlockKind kind, Span* spans) unique
Editor.Span = (number id, SpanKind kind, string text) unique
Editor.Selection = Cursor(number span_id, number offset)
                 | Range(number start_span_id, number start_offset,
                         number end_span_id, number end_offset)
```

This is not the place to introduce layout facets or paint facets.
The user does not author those.

## 4.2 Lower-phase vocabulary

At lower phases, the dominant concepts become:

- projection
- spine
- facet
- schedule/address/order/header records
- closed terminal payloads

Questions at this layer:

- what derived shape does the machine need?
- what structural alignment must later branches share?
- which meanings should be split into orthogonal facets?
- what decisions must be consumed before the leaf?

### Example: lower view phase

```asdl
View.Header = (number id, number parent_ix, number start_ix, number end_ix) unique
View.LayoutFacet = (number id, Rect rect) unique
View.PaintFacet = (number id, PaintKind kind, Color fg, Color bg) unique
View.HitFacet = (number id, HitKind hit, number action_id) unique
```

This is the right layer for spines and facets.

---

## 5. Why header is not separate from spine

The main document uses the phrase **header spine** for a reason.

A header is usually the record that carries shared structural truth:

- identity
- topology
- ranges
- ordering
- local indices
- addressability

That is exactly what the spine role is.

So the cleaner statement is:

> the spine is the role; the header is the common carrier.

If we treat `header` and `spine` as two separate primitives, the taxonomy gets muddy.

A better taxonomy is:

- entity
- variant
- projection
- spine
- facet

with the note that:

- a spine is often represented by a `Header` type

---

## 6. A worked example: from source entities to spine + facets

Consider a small document editor with paragraphs, code blocks, and links.

## 6.1 Source ASDL

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

This is a good source design because it models:

- entities: `Document`, `Block`, `Span`
- variants: `BlockKind`, `SpanKind`, `Selection`
- references: `target_block_id`
- containment: document owns blocks, blocks own spans

## 6.2 A bad lower design

Suppose a later phase flattens the document for view rendering and interaction. A bad design is:

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

This is too wide. Every later branch carries everything.

## 6.3 A better lower design

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
    PaintKind paint,
    bool selected
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

Now the design is clearer:

- `View.Header` is the shared spine
- content, layout, paint, hit, and accessibility are facets
- later branches consume only what they need

## 6.4 Downstream consumers

Layout solver:

- consumes `Header + ContentFacet`
- produces `LayoutFacet`

Painter:

- consumes `Header + LayoutFacet + PaintFacet + ContentFacet`

Hit testing:

- consumes `Header + LayoutFacet + HitFacet`

Accessibility:

- consumes `Header + A11yFacet + ContentFacet`

This is the value of the split: joins remain structural, not semantic.

---

## 7. A worked example: audio scheduling

Consider a source audio graph.

## 7.1 Source ASDL

```asdl
Editor.Project = (Track* tracks) unique
Editor.Track = (number id, string name, Device* devices, Send* sends) unique
Editor.Send = (number id, number target_track_id, number gain_db) unique

Editor.Device = Osc(number id, number hz)
              | Gain(number id, number db)
              | Filter(number id, number hz, number q)
```

This is source/authored shape:

- entities: project, track, send, device instances
- variants: `Device`
- refs: `target_track_id`

## 7.2 Resolve and schedule projections

A resolve phase may attach routed bus information:

```asdl
Resolved.Send = (
    number id,
    number target_track_id,
    number gain_db,
    number target_bus_ix
) unique
```

A schedule phase may create a shared execution spine:

```asdl
Scheduled.Header = (
    number node_id,
    number order_ix,
    number input_bus_ix,
    number output_bus_ix,
    number channel_count
) unique

Scheduled.OscFacet = (
    number node_id,
    number hz
) unique

Scheduled.GainFacet = (
    number node_id,
    number linear_gain
) unique

Scheduled.FilterFacet = (
    number node_id,
    number hz,
    number q,
    double* coeffs
) unique
```

Here the source variant does not survive unchanged into the hot path.
Instead:

- the schedule/header establishes shared structure
- each branch gets variant-specific facts in its own facet or specialized payload
- the terminal can monomorphize from a narrow input

If the leaf still switches on `"osc"` versus `"gain"` at runtime, the lowering is incomplete.

---

## 8. Composition recipes

Once the vocabulary is clear, many good designs reduce to a few recipes.

## 8.1 Entity + Variant

Use when a persistent thing has meaningful kinds.

```asdl
Editor.Node = (number id, NodeKind kind) unique
Editor.NodeKind = Gain(number db) | Filter(number hz, number q)
```

## 8.2 Entity + Reference

Use when one persistent thing points to another outside containment.

```asdl
Editor.Send = (number id, number target_track_id, number gain_db) unique
```

## 8.3 Projection + Spine

Use when later consumers need shared flattened structure.

```asdl
View.Header = (number id, number parent_ix, number start_ix, number end_ix) unique
```

## 8.4 Spine + Facets

Use when several downstream branches need the same structure but different semantic facts.

```asdl
View.Header = (...)
View.LayoutFacet = (...)
View.PaintFacet = (...)
View.HitFacet = (...)
```

## 8.5 Projection → closed terminal payload

Use when the leaf needs a monomorphic input.

```asdl
Scheduled.Biquad = (number node_id, number bus_in, number bus_out,
                    double b0, double b1, double b2, double a1, double a2) unique
```

At that point the leaf no longer interprets authored structure. It executes a fully consumed payload.

---

## 9. Design tests for each role

## 9.1 Entity test

Ask:

- can the user point to this as “that one”?
- does it persist independently?
- would reordering change its identity? If yes, the ID design is wrong.

## 9.2 Variant test

Ask:

- is this a real fixed-set domain “or”?
- would a missing case be a bug?
- do different cases carry different meaningful payloads?

If yes, use a sum type.

## 9.3 Projection test

Ask:

- is this shape derived for some downstream concern?
- would putting it in the source ASDL distort user-authored truth?

If yes, make it a projection.

## 9.4 Spine test

Ask:

- do several later branches need the same structural identity/order/topology?
- is one lower node widening only so branches can stay aligned?

If yes, introduce a spine.

## 9.5 Facet test

Ask:

- are several semantic concerns currently bundled only for convenience?
- could some downstream branches ignore some of these facts?
- would splitting them make edits more local and joins more structural?

If yes, introduce facets.

---

## 10. Common category mistakes

## 10.1 Treating a property as an entity

```asdl
Editor.Block = (number id, number line_count, string text) unique
```

If `line_count` is derived from `text`, it is not an authored entity and should not be modeled as such.

## 10.2 Treating a variant as a string

```asdl
Editor.Node = (number id, string kind, number value) unique
```

If the set of kinds is fixed, use a sum type.

## 10.3 Treating a projection as source truth

```asdl
Editor.Track = (number id, string name, number meter_db) unique
```

If `meter_db` is runtime/view state rather than authored truth, this is the wrong layer.

## 10.4 Treating spine and facet as source primitives

Do not begin source modeling with layout facets or paint facets unless the domain itself is literally authored in those terms.

The source phase should model user nouns first.

## 10.5 Treating header as separate from spine

This tends to create unnecessary terminology duplication.
A header is usually the carrier of the spine role.

---

## 11. The proposed minimal vocabulary

If we want one compact architectural vocabulary for this repository, a strong candidate is:

- **entity** — persistent authored thing
- **variant** — closed domain alternative
- **projection** — derived phase-local ASDL
- **spine** — shared structural alignment space
- **facet** — orthogonal semantic plane aligned to a spine

And beneath it, the formal basis remains:

- product
- sum
- sequence
- reference
- identity

That gives a nice two-level picture:

### Formal level

Build everything from:

- product
- sum
- sequence
- reference
- identity

### Architectural level

Arrange them as:

- entity
- variant
- projection
- spine
- facet

This is small enough to feel canonical, but rich enough to explain most good ASDL patterns in practice.

---

## 12. Final claim

Good ASDL design is less about inventing many special-purpose structures and more about composing a small number of architectural roles correctly.

A practical summary is:

- **source ASDL** is mostly entities, variants, containment, and references
- **lower ASDL** is mostly projections
- when lower branches share structure, introduce a **spine**
- when lower branches need different semantic aspects, split them into **facets**
- when the terminal is near, collapse to a closed monomorphic payload

In that sense, the design game is not endless invention.
It is mostly disciplined composition over a small vocabulary.
