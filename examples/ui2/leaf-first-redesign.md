# ui2 redesign sketchpad

This file is the live working road for the `ui2` redesign.

It is not a frozen spec.
It is the place where we sketch, revise, throw away bad shapes, and keep the current best understanding of the ASDL.

We are restarting this redesign from the bottom.

Core rule:

> start from `gen / param / state`.

Not from the old middle pipeline.
Not from the current `UiLowered` sketch.
Not from existing node-shaped lower types.

If the machine shape is wrong, everything above it will be wrong in a more elaborate way.

---

## 0. what this file is for

Use this file to:

- sketch the machine from the bottom up
- record exact `gen`, `param`, and `state` responsibilities
- derive the machine IR that feeds them
- derive the render/query/geometry projections above that
- revise the ASDL repeatedly during the redesign session
- keep ourselves from drifting back into middle-first design

This file should be edited throughout the whole redesign.

---

## 1. redesign rule set

### 1.1 start from `gen / param / state`

The first real leaf is not “geometry” or “render plan”.
The first real leaf is the machine contract:

- `gen`   = what shapes code
- `param` = stable live machine input
- `state` = mutable runtime-owned machine state

Everything above this must justify itself by making those three roles simpler and truer.

### 1.2 the machine is the truth

Do not ask first:

- what lower node types seem tidy?
- what looks like a natural pipeline?

Ask first:

- what does the running machine actually execute over?
- what is stable enough to be `param`?
- what must be mutable runtime-owned `state`?
- what truly affects code shape and therefore belongs in `gen`?

### 1.3 no giant mixed lower nodes

We are explicitly suspicious of old shapes like:

- giant solver input nodes
- giant solved nodes
- one mixed render/query plan

If a lower type mixes facts needed by different machine roles, it is probably wrong.

### 1.4 later phases must narrow toward the machine

As we move downward:

- decisions should be consumed
- broad domain structure should disappear
- machine roles should become clearer
- the final render machine should look unsurprising

### 1.5 this file can revise anything

Nothing here is sacred.
If a later sketch reveals a bad assumption, revise the earlier sections.

---

## 2. current diagnosis

The benchmark already told us the main problem:

- compile is cheap warm
- the expensive work is upstream
- the lower ASDL is carrying the wrong structure

The important correction is:

> this is not mainly a caching problem.
> it is a machine-modeling and ASDL-design problem.

More specifically:

- the current lower phases still carry too much node-shaped mixed structure
- the machine does not actually run over those shapes
- therefore the pure pipeline is overbuilding data the machine does not want

So we restart from the machine.

---

## 3. bottom-most mental model

The bottom of the pattern here is:

```text
Machine IR -> gen, param, state -> Unit { fn, state_t }
```

For this redesign we begin with the right side and derive leftward.

### 3.1 `gen`

`gen` should contain only facts that actually change code shape or execution shape.

Questions:

- what causes different emitted runner structure?
- what affects batch family dispatch shape?
- what affects ABI / state layout / helper selection?

### 3.2 `param`

`param` should contain the stable machine input read by the runner.

Questions:

- what scene payload does the machine read every frame/run?
- what is stable enough to materialize structurally?
- what should be data, not code?

### 3.3 `state`

`state` should contain only mutable runtime-owned machine state.

Questions:

- what is updated over time by execution/materialization?
- what caches, handles, textures, GL/SDL/runtime-owned slots belong here?
- what should definitely not live in pure ASDL?

---

## 4. first design task: write the machine honestly

Before deciding upstream phases, we need the exact render machine contract.

We should answer:

1. what does the runner loop over?
2. what arrays or streams does it read?
3. what runtime-owned mutable slots does it need?
4. what code-shaping variants exist?

Only after that do we derive the machine IR.

---

## 5. provisional machine questions

These are the first questions we should answer in this file.

### Q1. what exactly is `gen` for ui2 render?

Current suspicion:

- render family availability
- custom family specialization
- maybe clip strategy choices
- maybe target/backend helper wiring

Current suspicion of what is **not** `gen`:

- the ordinary draw items themselves
- ordinary scene payload
- text strings
- image refs
- rect lists
- hit/query data

### Q2. what exactly is `param` for ui2 render?

Current suspicion:

- packed render batches
- packed clip table
- packed box/shadow/text/image/custom items
- region draw spans

Need to verify:

- should text item data live here, or should some of it already be moved into state ownership?
- should clip data be separate from batch state or embedded differently?
- should region headers survive all the way to the machine?

### Q3. what exactly is `state` for ui2 render?

Current suspicion:

- runtime-owned text textures / handles / text slot state
- runtime-owned image textures / handles if cached there
- any mutable materialized GPU resource ownership
- temporary live state required by the stable runner

Need to verify:

- which resources are truly machine-owned runtime state
- which things are only derivable payload and should stay in `param`
- whether current materialization still does semantic work that belongs above state

---

## 6. machine-first workflow

For this redesign, we use this order.

### step A: write `state`

Because mutable runtime ownership is often the clearest truth.
Ask:

- what does the running system mutate/own across updates?
- what would be lost if we rebuilt it every time?

### step B: write `param`

Ask:

- what stable input does the machine read?
- what should be structurally loaded, not recomputed inside the runner?

### step C: write `gen`

Ask:

- what small set of facts actually changes the execution machine?

### step D: write the machine IR above them

Only then write the typed IR that makes `gen / param / state` trivial.

### step E: derive the projections above the machine IR

Only after the machine IR is honest do we derive:

- render projection
- query projection
- geometry solve input/output
- flat/bound/source structure

---

## 7. domain summary

### authored nouns

- document
- region / root / overlay
- element
- layout
- paint
- text
- image
- custom payload
- hit/focus/scroll/edit behavior
- accessibility exposure

### persistent identity nouns

- `element_id`
- `semantic_ref`
- region/root identity

### lower coupling points

There are at least two important ones:

1. solved geometry
2. machine ownership boundaries

The redesign starts from the second one first.

---

## 8. the leaves, re-stated correctly

We previously spoke about geometry/render/query as the leaves.
That was too high.

The stricter leaf order is:

### leaf 0: machine roles

- `gen`
- `param`
- `state`

### leaf 1: machine IR

The typed IR that feeds those roles.

### leaf 2: render/query projections

The pure projections that make machine IR construction trivial.

### leaf 3: geometry solve language

The pure layout/geometry language needed before render/query projection.

### leaf 4: flat/bound/source

The higher authored model and containment structure.

This is the direction we should follow.

---

## 9. active design questions

### Q4. what is the exact render machine loop shape?

Need to decide:

- does it iterate by batch headers plus family-specific arrays?
- are text/image resources addressed by stable slot index, key, or both?
- what part of clip application is state-free versus runtime-owned?

### Q5. what exact machine IR sits above `gen / param / state`?

Need to decide:

- whether the current `UiKernel` shape is still right
- whether `UiKernel` is still too close to the old mixed plan
- whether render IR should already be more machine-regular than it is now

### Q6. what is the exact query machine or reducer input?

Need to decide:

- whether query should also be thought of in machine terms
- what stable packed query payload the reducer actually wants
- how separate that should be from render as early as possible

### Q7. what is the minimal geometry language that feeds render/query projection?

Need to decide:

- what exact solved geometry facts must exist
- what should not survive solve
- whether clip facts belong to geometry, render projection, or both

---

## 10. provisional status of current ASDL rewrite

Current status:

- the ASDL was provisionally redrawn around:
  - `UiFlat`
  - `UiLowered`
  - `UiGeometry`
  - `UiRender`
  - `UiQuery`
- schemas were switched to stubs only

Important:

> this redraw is provisional.

It is not yet justified from `gen / param / state`.
So we should treat it as a sketch we may revise again.

---

## 11. iteration log

### iteration 0: reset

Decision:

- stop treating geometry/render/query as the lowest design starting point
- restart from the actual machine contract
- use this file as the redesign road for the whole session

Consequence:

- every lower phase above the machine remains provisional until derived from
  `gen / param / state`

### iteration 1: provisional lower redraw

Observation:

- old `UiDemand` / `UiSolved` / `UiPlan` were too node-centric and mixed too many concerns

Action:

- provisionally replaced them with `UiLowered` / `UiGeometry` / `UiRender` / `UiQuery`
- switched schemas to stub-only so the architecture can be re-derived cleanly

Status:

- not yet accepted as final
- must still be checked against the machine-first derivation

---

## 12. what to write next

The next concrete content to add to this file is:

### next task

Write the exact machine sketch in this order:

1. `state` sketch
2. `param` sketch
3. `gen` sketch
4. immediate machine IR sketch above them

Only after that should we derive or revise:

- `UiKernel`
- `UiRender`
- `UiQuery`
- `UiGeometry`
- `UiLowered`

Status:

- `state` sketch: in progress below
- `param` sketch: not started
- `gen` sketch: not started
- machine IR sketch: not started

---

## 13. redesign checklist

Before accepting any lower type, check:

- does it make `gen` smaller or clearer?
- does it make `param` more structural and truthful?
- does it keep mutable ownership in `state` instead of pure ASDL?
- does a real consumer demand every field?
- does it narrow toward the machine instead of rewrapping node structure?
- can the boundary be described with a single verb?
- can the boundary be tested with constructor + assertion?

If not, revise the ASDL again.

---

## 14. state sketch v0

This is the first concrete bottom-up sketch.
It is provisional, but more concrete than the earlier sections.

Goal:

> identify what mutable runtime ownership the ui2 render machine actually needs.

### 14.1 what state is **not**

State is **not**:

- the authored tree
- solved geometry
- packed draw order
- region draw spans
- clip tables
- batch headers
- box/shadow/image/text draw item arrays as pure data

Those things may eventually be loaded into realized memory, but conceptually they are
`param`, not `state`.

So the first big correction is:

> scene description is not state.
> runtime-owned mutable realization is state.

### 14.2 what the current implementation suggests

The current backends strongly suggest that the machine really owns mutable runtime
resources for at least:

- text realization
- image realization
- maybe custom-family realization

and does **not** truly need mutable ownership for:

- boxes
- shadows
- ordinary batch headers
- ordinary clip descriptions

Those are just execution data.

### 14.3 candidate runtime-owned state families

#### A. text resource state

The machine likely needs persistent text resource ownership.

Why:

- text rasterization produces backend resources
- those resources have runtime lifetime
- rebuilding them every materialize is wrong
- they are not authored state and not pure payload facts

Candidate contents per text resource slot:

- stable text resource key/hash
- backend texture handle / native resource handle
- realized pixel width
- realized pixel height
- validity / installed flag
- maybe backend-specific bookkeeping

Important design pressure:

- the state should own the realized resource
- the param should not pretend to own textures

#### B. image resource state

Likely similar to text.

Why:

- decoded/uploaded image textures are runtime-owned resources
- their lifetime is not authored state
- they should not be recomputed as pure scene facts every time

Candidate contents per image resource slot:

- stable image resource key
- backend texture handle
- realized width/height
- validity / installed flag

Open question:

- should image resources be per-scene machine state or runtime-global asset state?
- if runtime-global, the machine state may only hold references/indices

For now we keep this open, but the important rule remains:

> image GPU/runtime ownership is state-like, not pure param.

#### C. custom family runtime state

This depends on the family.

Possible rule:

- closed built-in families define their own state shapes directly
- custom families may contribute their own runtime-owned state slots

Open question:

- should custom family mutable ownership be represented in `gen`/machine spec,
  in `state model`, or both?

#### D. scene installation bookkeeping

The machine may need a very small amount of scene-local mutable bookkeeping such as:

- installed counts/capacities
- slot array capacities
- maybe generation/version counters

This is real state because it changes as the machine materializes and updates.

### 14.4 what should probably move *out* of state

This is just as important.

The following look suspicious as state-owned data:

- batch arrays
- box arrays
- shadow arrays
- clip tables
- text placement rectangles
- image placement rectangles
- region draw headers

Those are much closer to `param`.

They may be copied into backend-native memory at realization time, but that copying is
an implementation detail. Architecturally they are not the machine's mutable runtime
ownership.

### 14.5 crucial text split

The current text path likely still conflates two different things:

1. **text resource realization**
   - content/style/wrap-dependent rasterized texture ownership
   - belongs in `state`

2. **text placement**
   - x/y/bounds/draw-state usage in the scene
   - belongs in `param`

This suggests the machine probably should not model one text item as one undifferentiated
thing all the way down.

Likely better split:

- `param` names a text resource and says where/how to draw it
- `state` owns the realized backend resource for that text resource

This is probably one of the key redesign truths.

### 14.6 candidate state model sketch

Very provisional machine-owned state families:

- `TextResourceState* text_resources`
- `ImageResourceState* image_resources`
- `CustomFamilyState* custom_states` or family-specific state regions
- small installation bookkeeping

Possible conceptual shape:

```text
RenderStateModel = {
  text_resource_capacity,
  image_resource_capacity,
  custom_state_capacity?,

  text_resources[*],
  image_resources[*],
  custom_states[*]?
}
```

with each text resource slot conceptually like:

```text
TextResourceState = {
  resource_key,
  backend_handle,
  width_px,
  height_px,
  valid
}
```

and each image resource slot like:

```text
ImageResourceState = {
  resource_key,
  backend_handle,
  width_px,
  height_px,
  valid
}
```

This is not final ASDL syntax yet.
It is just the machine truth sketch.

### 14.7 current provisional conclusion

Current best guess:

> `state` should be mostly resource ownership and mutable installation bookkeeping,
> not duplicated scene payload.

If that is true, then a lot of the current kernel/materialize shape is still too close to
"copy the scene into state" and not close enough to the true machine split.

That means the next section, `param`, should probably be written with this pressure in mind:

- `param` carries scene execution data
- `state` carries realized runtime resources referenced by that scene execution data

### 14.8 open questions after state sketch v0

1. are text resources keyed per draw item, or deduplicated separately from placement?
2. are image resources per machine, per target/runtime, or globally asset-owned?
3. what exact custom-family state extension mechanism do we want?
4. does the runner read resource slots by stable index, key lookup, or both?
5. how much of current `UiKernel.Payload` is actually param versus accidental state-shadow?

### 14.9 next step

Next write:

- `param` sketch v0

---

## 15. machine-happy shape vocabulary v0

This section captures the practical thing we were missing.

We do not merely need "some IR above the machine".
We need a set of **type shape families** that make the machine happy.

The point is to give the machine:

- explicit order
- explicit addressability
- explicit use-sites
- explicit resource identity
- explicit runtime ownership

without inventing a generic interpreted wiring language.

### 15.1 what this is not

This is **not** a plan to invent generic runtime nodes like:

- `Accessor(kind, ... )`
- `Processor(kind, ... )`
- `Emitter(kind, ... )`

That would risk rebuilding an accidental interpreter.

Instead, the machine-feeding layer should use **concrete typed shapes** that already
collapse semantic lookup into machine-friendly structure.

### 15.2 the candidate shape families

Current candidate shape families are:

1. **Span**
2. **Header**
3. **Ref**
4. **Instance**
5. **ResourceSpec**
6. **ResourceState**

This vocabulary is intentionally concrete.
It is not a generic DSL.
It is a checklist for the kinds of typed records the machine likely wants.

---

### 15.3 Span

A `Span` shape describes execution order over a contiguous region of homogeneous payload.

Examples:

- region draw span
- batch item span
- clip span
- focus-chain span

Conceptual examples:

```text
RegionSpan(draw_start, draw_count)
ItemSpan(start, count)
```

Machine role:

- tells loops where to start and stop
- removes the need for search/traversal
- turns containment/order into explicit machine order

Test question:

> can the machine advance with integer ranges instead of walking semantic structure?

If yes, a `Span` shape is probably needed.

---

### 15.4 Header

A `Header` shape describes one execution unit in a stream.

Examples:

- batch header
- region header
- command header
- query routing header

Conceptual examples:

```text
BatchHeader(kind, state_ref, item_start, item_count)
RegionHeader(draw_start, draw_count)
```

Machine role:

- carries fixed metadata for one loop body selection
- makes dispatch closed and explicit
- avoids rediscovering grouping at runtime

Test question:

> does the machine naturally loop over a stream of records where each record controls one execution slice?

If yes, a `Header` shape is probably needed.

---

### 15.5 Ref

A `Ref` shape is a compiled access path.

This is the safe form of "querying".
A `Ref` is not a semantic search. It is a typed way to reach already-resolved data.

Examples:

- clip ref
- text resource ref
- image resource ref
- transform ref
- draw-state ref
- custom-family slot ref

Conceptual examples:

```text
ClipRef(index)
TextResourceRef(slot)
ImageResourceRef(slot)
```

Machine role:

- gives addressability without search
- replaces ID chasing and tree walking
- makes reads look like slot/index access

Test question:

> can the machine reach the needed thing by a stable typed slot/index rather than by semantic lookup?

If yes, a `Ref` shape is probably needed.

---

### 15.6 Instance

An `Instance` shape describes one use-site of something in execution.

Examples:

- one text draw occurrence
- one image draw occurrence
- one box draw occurrence
- one shadow draw occurrence
- one hit-test item occurrence

Conceptual examples:

```text
TextDrawInstance(resource_ref, rect, clip_ref, opacity, transform_ref)
ImageDrawInstance(resource_ref, rect, clip_ref, corners)
BoxInstance(rect, fill, stroke, state_ref)
```

Machine role:

- separates "what resource exists" from "where/how it is used"
- makes scene usage explicit without semantic reinterpretation
- lets multiple uses refer to one resource

Test question:

> is this thing a reusable realized resource with multiple scene uses, or a direct scene-local occurrence?

If it is a use-site, it should probably be an `Instance`.

---

### 15.7 ResourceSpec

A `ResourceSpec` shape describes a realizable stable resource identity.

Examples:

- text resource specification
- image resource specification
- custom-family resource specification

Conceptual examples:

```text
TextResourceSpec(key, text, font, size, color, wrap, align, width)
ImageResourceSpec(key, image_ref, sampling)
```

Machine role:

- names what runtime resource may need to exist
- separates resource identity from scene placement
- gives `state` a clear install/update target

Test question:

> does the runtime own some realized artifact for this thing independent of one specific draw occurrence?

If yes, a `ResourceSpec` shape is probably needed.

---

### 15.8 ResourceState

A `ResourceState` shape describes runtime-owned mutable realization state.

Examples:

- text texture state
- image texture state
- custom-family runtime slot state

Conceptual examples:

```text
TextResourceState(key, backend_handle, width_px, height_px, valid)
ImageResourceState(key, backend_handle, width_px, height_px, valid)
```

Machine role:

- owns backend/runtime resources
- persists across materialization and execution
- should never be confused with authored or solved semantic data

Test question:

> would rebuilding this every update be semantically wrong or operationally wasteful because it is a runtime-owned realization?

If yes, it belongs in `ResourceState`.

---

### 15.9 why these shapes matter

These six shape families are a practical substitute for vague talk about "feeding the machine".

They let us ask concrete questions:

- what are the machine's spans?
- what headers does it loop over?
- what refs does it dereference?
- what instances does it execute?
- what resources does it realize?
- what resource state does it own?

This is much more useful than saying only:

- "we need a lower IR"
- or "we need wiring"

because it gives type-design pressure without inventing a generic interpreted layer.

### 15.10 likely consequence for ui2

The current ui2 render path probably still mixes at least these two truths too much:

1. **resource identity**
   - text/image/custom realizable resource definition

2. **scene occurrence**
   - where/how that resource is used in one draw instance

This strongly suggests future ASDL sketches should test splits like:

- `TextResourceSpec` vs `TextDrawInstance`
- `ImageResourceSpec` vs `ImageDrawInstance`

instead of carrying one undifferentiated text/image item shape all the way down.

### 15.11 immediate design use

For each next sketch section (`param`, `gen`, machine IR), we should explicitly ask:

- which `Span` shapes exist?
- which `Header` shapes exist?
- which `Ref` shapes exist?
- which `Instance` shapes exist?
- which `ResourceSpec` shapes exist?
- which `ResourceState` shapes exist?

That gives us a concrete way to test whether the ASDL is genuinely becoming machine-friendly.

### 15.12 next step

Next write:

- `param` sketch v0

using the state sketch and these shape families as constraints.

---

## 16. param sketch v0

This is the next bottom-up sketch.

Goal:

> identify the stable machine input the ui2 render machine should read.

The main pressure from the `state` sketch is:

- `param` should carry scene execution data
- `state` should carry runtime-owned realized resources

So `param` must not pretend to own backend resources.
It should instead describe:

- execution order
- access paths
- use-sites
- resource references/specifications

in a form the machine can read directly.

### 16.1 what param is **not**

`param` is **not**:

- authored structure
- unresolved semantic structure
- runtime-owned backend handles
- mutable execution history
- semantic lookup instructions
- a generic command interpreter program

In particular, `param` should not force the machine to do things like:

- search by id
- walk a tree to rediscover order
- resolve a text resource from semantic text fields every frame
- resolve an image resource from a raw asset reference every frame

So the key rule is:

> `param` is stable machine input, not semantic work deferred to runtime.

### 16.2 what param probably contains

Given the machine-happy shape vocabulary, current best guess is that render `param`
should be mostly composed of these shape families:

- `Span`
- `Header`
- `Ref`
- `Instance`
- `ResourceSpec`

and explicitly **not** `ResourceState`.

That suggests a render-machine-facing param with components like:

- region draw spans
- batch headers
- draw-state refs / clip refs / transform refs
- family-specific draw instances
- text resource specs
- image resource specs
- maybe custom resource specs

### 16.3 likely `Span` shapes in render param

Candidate spans:

#### A. region draw spans

```text
RegionSpan(draw_start, draw_count)
```

Role:

- tells the machine which slice of batch headers belongs to one top-level region
- preserves region execution order without tree walking

#### B. item spans inside batch headers

```text
ItemSpan(start, count)
```

Role:

- tells the machine which homogeneous item slice to execute for one batch

Likely note:

- these may not need a standalone record if `BatchHeader` already carries them

### 16.4 likely `Header` shapes in render param

#### A. batch header

This still looks necessary.

Conceptual example:

```text
BatchHeader(
  kind,
  draw_state_ref,
  item_start,
  item_count
)
```

Possible `kind` cases:

- box
- shadow
- text
- image
- custom family

Role:

- closed dispatch for one execution slice
- one stable runner can iterate these headers and dispatch cheaply

#### B. maybe region header

Possible shape:

```text
RegionHeader(draw_start, draw_count)
```

Open question:

- do we need a distinct header record, or is `RegionSpan` enough?

Current guess:

- `RegionSpan` is probably enough unless more region-local machine metadata appears

### 16.5 likely `Ref` shapes in render param

This is probably where the biggest redesign truth sits.

Candidate refs:

#### A. `ClipRef`

```text
ClipRef(index)
```

Role:

- lets instances or draw states point at clip descriptions by stable slot

#### B. `DrawStateRef`

```text
DrawStateRef(index)
```

Role:

- lets batch headers or instances refer to stable draw-state records

Open question:

- should draw state be inlined into batch headers instead?

Current guess:

- if draw state is batch-local and cheap, inlining may be fine
- if it is shared or reused structurally, a ref shape is better

#### C. `TextResourceRef`

```text
TextResourceRef(slot)
```

Role:

- one text draw instance refers to a text resource spec/state slot
- separates text resource identity from text placement

This is likely essential.

#### D. `ImageResourceRef`

```text
ImageResourceRef(slot)
```

Role:

- one image draw instance refers to an image resource spec/state slot

Likely essential too.

#### E. custom refs

Possible examples:

```text
CustomResourceRef(slot)
CustomFamilyRef(family)
```

Open question:

- whether custom resource identity should be modeled like built-in resources or left
  family-defined

### 16.6 likely `ResourceSpec` shapes in render param

This is where current ui2 likely needs the largest correction.

#### A. text resource spec

Current conceptual shape:

```text
TextResourceSpec(
  key,
  text,
  font,
  size_px,
  color,
  wrap,
  align,
  width_px
)
```

Role:

- identifies the realizable text resource
- provides the stable data needed for install/update in `state`

Key consequence:

- text draw placement should not be fused into this shape

#### B. image resource spec

Current conceptual shape:

```text
ImageResourceSpec(
  key,
  image_ref,
  sampling
)
```

Open question:

- does fit/corner handling belong here or in the use-site instance?

Current guess:

- sampling and source identity look resource-like
- placement and destination corners look instance-like

#### C. custom resource spec

This depends on the family.

Possible rule:

- built-in families have typed core resource specs
- custom families may contribute resource spec payload through family-specific typed
  extensions or through a family payload slot that is already resolved enough for the
  backend/custom handler

### 16.7 likely `Instance` shapes in render param

This is the other major split.

#### A. box instance

```text
BoxInstance(
  rect,
  fill,
  stroke,
  stroke_width,
  corners,
  clip_ref?,
  draw_state_ref?
)
```

Open question:

- if batch state already carries clip/blend/opacity/transform, then some of this may
  stay outside the instance

#### B. shadow instance

```text
ShadowInstance(
  rect,
  brush,
  blur,
  spread,
  dx,
  dy,
  kind,
  corners,
  clip_ref?,
  draw_state_ref?
)
```

#### C. text draw instance

This is likely the key new split.

```text
TextDrawInstance(
  resource_ref,
  bounds,
  clip_ref?,
  draw_state_ref?
)
```

Maybe also:

- local x/y placement
- baseline offset if the runtime needs it explicitly

Key rule:

- text resource identity lives in `TextResourceSpec`
- scene occurrence lives in `TextDrawInstance`

#### D. image draw instance

```text
ImageDrawInstance(
  resource_ref,
  rect,
  corners,
  clip_ref?,
  draw_state_ref?
)
```

Key rule:

- image resource identity lives in `ImageResourceSpec`
- scene occurrence lives in `ImageDrawInstance`

#### E. custom instance

```text
CustomInstance(
  family,
  payload,
  clip_ref?,
  draw_state_ref?
)
```

Open question:

- should custom use-site and custom resource identity be separated the same way as text
  and image, or are some custom families inherently scene-local instances?

Current answer:

- keep this open per family
- do not force one answer too early

### 16.8 what param probably should stop carrying

Based on this sketch, param should probably stop pretending that these are one thing:

- text specification + text placement
- image specification + image placement
- resource identity + scene occurrence

This strongly suggests the current monolithic item path is too coarse.

Likely better direction:

- specs in one plane
- instances in another plane
- refs linking them

### 16.9 candidate param sketch

Very provisional conceptual render param:

```text
RenderParam = {
  region_spans[*],
  batch_headers[*],
  draw_states[*]?,
  clips[*]?,

  text_resource_specs[*],
  image_resource_specs[*],
  custom_resource_specs[*]?,

  box_instances[*],
  shadow_instances[*],
  text_instances[*],
  image_instances[*],
  custom_instances[*]
}
```

This is not final ASDL syntax.
It is the current machine-truth sketch.

### 16.10 relation to state sketch

If this sketch is right, then runtime execution roughly becomes:

1. iterate region spans
2. iterate batch headers
3. dispatch by closed family
4. for text/image families:
   - use `resource_ref` to reach resource spec
   - ensure corresponding `ResourceState` is installed/valid
   - draw the use-site instance
5. for box/shadow families:
   - execute directly from instances + draw state

That is much closer to a real machine than the current fused item story.

### 16.11 current provisional conclusion

Current best guess:

> render `param` should be a typed machine-feeding payload made mostly of spans,
> headers, refs, resource specs, and use-site instances.

And the most likely immediate redesign pressure is:

> split resource identity from scene occurrence, especially for text and image.

### 16.12 open questions after param sketch v0

1. should `DrawState` be a separate table + ref, or inlined into headers?
2. should clips be a separate table + `ClipRef`, or inlined into draw state?
3. are text resources deduplicated scene-wide by `TextResourceSpec.key`?
4. are image resources machine-local, runtime-global, or asset-global?
5. what is the right custom-family story for resource specs versus direct instances?
6. does query want analogous spec/instance splits, or mostly spans/instances only?

### 16.13 next step

Next write:

- `gen` sketch v0

using the `state` and `param` sketches together.

---

## 17. gen sketch v0

This is the third bottom-up sketch.

Goal:

> identify what truly shapes the render machine's code/execution form.

The pressure from the previous sections is:

- `state` owns runtime realization
- `param` carries stable machine-feeding payload
- `gen` should therefore be as small as possible

So `gen` should not become a hiding place for payload facts that merely happen to be
convenient to bake.

### 17.1 what gen is **not**

`gen` is **not**:

- ordinary scene payload
- region counts
- batch counts
- per-instance geometry
- text strings
- image refs
- clip rectangles
- draw item arrays
- resource specs themselves
- runtime resource state

Those are `param` or `state` concerns.

So the first rule is:

> if a fact can vary scene-to-scene without changing the machine's structural execution
> shape, it probably does **not** belong in `gen`.

### 17.2 what gen should answer

`gen` should answer questions like:

- what closed execution families exist?
- what family-specific loops/helpers must the runner contain?
- what state-schema families must the runner know how to address?
- what backend-target helper strategy is assumed?
- what dispatch shape is fixed at compile time?

So `gen` is primarily about:

- closed-world execution shape
- helper selection
- machine schema shape when that shape affects code

### 17.3 current likely gen-shaping facts for ui2 render

Current best guess:

#### A. active built-in render families

The render machine likely always understands a closed built-in set like:

- box
- shadow
- text
- image
- custom

Open question:

- should absent built-in families still exist in one generic runner, or should they be
  removable from the compiled machine?

Current guess:

- built-ins are probably cheap enough to keep as one closed runner shape
- custom families are the more meaningful `gen` pressure

#### B. active custom families

This is the clearest current `gen` fact.

Why:

- different custom families may require different helper wiring
- different custom families may imply different runtime state extension shape
- custom family support changes what the machine must know how to dispatch

So current likely `gen` shape includes something like:

```text
CustomFamilySet = { family_id* }
```

or equivalent typed family records.

#### C. resource-state family schema

If text/image/custom resource state families have different runtime slot schemas, the
runner may need to know that structure at compile time.

Examples:

- text resource slots exist
- image resource slots exist
- custom family state slots exist for specific families

This does **not** mean counts belong in `gen`.
It means the **kinds of runtime-owned state regions** may belong in `gen` if they affect
code shape and state layout.

#### D. target helper contract

This is a narrower possible `gen` fact.

Examples:

- clip application strategy
- custom callback ABI shape
- target-specific helper family signatures

Current guess:

- these are backend-realization concerns
- but the machine may still need a small amount of target/helper-shape information
  if it materially changes execution structure

So we should keep this possible but minimal.

### 17.4 what probably does **not** belong in gen

Important exclusions:

#### A. ordinary draw states

Things like:

- opacity values
- transforms
- blend modes
- clip refs

look much more like `param` than `gen`.

Even if a particular value could theoretically be baked, the machine role question is:

- does this alter the compiled machine's structural shape?

Usually the answer is no.

#### B. text/image resource specs

These should almost certainly stay in `param`.

Why:

- they vary with scene content
- they define realizable resources, not machine structure
- baking them into `gen` would over-specialize rebuilds badly

#### C. scene counts and spans

Counts and spans are `param` facts unless they literally determine a different machine
schema.

Current guess:

- counts should stay live in payload/param
- the runner shape should not depend on exact scene counts

### 17.5 provisional gen sketch

Current conceptual shape:

```text
RenderGen = {
  built_in_family_support,
  custom_families[*],
  resource_state_family_schema,
  target_helper_shape?
}
```

This is intentionally small.

The important pressure is:

> `gen` should describe the machine's closed execution vocabulary and schema shape,
> not the current scene.

### 17.6 relation to param and state

If the current sketches are right, the split becomes:

#### `gen`

- what family loops/helpers exist
- what runtime state regions exist
- what closed dispatch shape exists

#### `param`

- which headers/spans/refs/specs/instances are present in this scene

#### `state`

- realized runtime-owned resources and mutable installation bookkeeping

This is much cleaner than letting the same facts leak across all three roles.

### 17.7 likely consequence for current ui2 kernel design

Current likely issue:

- `UiKernel.Spec` may still be too weakly defined
- `UiKernel.Payload` may still mix resource identity and use-site payload too much
- `UiMachine.StateModel` may still be too count-oriented and not enough resource-schema-
  oriented

So after these sketches, we should expect the eventual Machine IR rewrite to revisit all
three of those shapes together.

### 17.8 current provisional conclusion

Current best guess:

> `gen` should stay very small and mostly describe closed family support, custom family
> specialization, and any state-schema facts that truly alter machine code/layout shape.

If `gen` starts accumulating scene payload, we are likely hiding a bad split elsewhere.

### 17.9 open questions after gen sketch v0

1. should built-in families always remain in one canonical runner shape?
2. how exactly should custom family support extend state schema?
3. does text/image resource-state existence affect code shape enough to live in `gen`, or
   is that fixed for all ui2 render machines?
4. what target/helper contract facts really belong to the machine layer rather than pure
   backend realization?
5. is `UiKernel.Spec` still the right name, or should eventual ASDL use a name that makes
   "machine shape" more explicit?

### 17.10 next step

Next write:

- machine IR sketch v0

using the `state`, `param`, and `gen` sketches together.

---

## 18. machine IR sketch v0

This is the first combined sketch.

Goal:

> define what the machine IR above `gen, param, state` should actually be.

We now have enough pressure from the prior sections to say something stronger.

Machine IR is not just:

- a plan
- a payload
- a solved node tree
- a lower representation in the vague sense

Machine IR is:

> the **typed machine-feeding layer** that makes machine order, addressability,
> use-sites, resource identity, and runtime ownership requirements explicit so
> `gen`, `param`, and `state` become trivial to derive.

That is now the working canonical definition for this redesign.

### 18.1 naming pressure

The old names now look suspiciously weak:

- `Spec`
- `Payload`
- `StateModel`

Those names are not wrong, but they hide the stronger shape we now want.

Current naming pressure:

- `Spec` is really about **machine shape**
- `Payload` is really about **machine input**
- `StateModel` is really about **runtime state schema**

So the more canonical naming family may be something like:

- `MachineShape`
- `MachineInput`
- `StateSchema`

or, preserving the canonical machine terms more directly:

- `GenShape`
- `ParamInput`
- `StateSchema`

Current best guess:

- the machine roles should stay named `gen`, `param`, `state`
- the IR above them should use names that make their feeder roles explicit

So a likely eventual naming direction is:

```text
MachineIR.Shape
MachineIR.Input
MachineIR.StateSchema
```

or for ui2 specifically:

```text
UiMachineIR.Shape
UiMachineIR.Input
UiMachineIR.StateSchema
```

Open question:

- should the IR record keep the pair/triple shape directly, or should one `Render`
  record contain all three feeder components?

### 18.2 what machine IR must contain

Based on the prior sketches, a good render Machine IR should contain enough typed shape
for all of these to be explicit:

#### A. order

Examples:

- region spans
- batch headers
- item spans

#### B. addressability

Examples:

- clip refs
- draw-state refs
- text resource refs
- image resource refs
- custom refs

#### C. use-sites

Examples:

- box instances
- shadow instances
- text draw instances
- image draw instances
- custom instances

#### D. resource identity

Examples:

- text resource specs
- image resource specs
- custom resource specs

#### E. runtime ownership requirements

Examples:

- text resource state schema
- image resource state schema
- custom state schema
- installation bookkeeping schema

That means Machine IR is wider than `param` alone.
It includes the facts that make `param` and `state` derivable and the facts that make
`gen`'s machine shape explicit.

### 18.3 a first combined conceptual shape

Very provisional conceptual shape:

```text
RenderMachineIR = {
  shape,
  input,
  state_schema
}
```

where:

```text
shape = {
  built_in_family_support,
  custom_families[*],
  helper_shape?
}

input = {
  region_spans[*],
  batch_headers[*],
  draw_states[*]?,
  clips[*]?,

  text_resource_specs[*],
  image_resource_specs[*],
  custom_resource_specs[*]?,

  box_instances[*],
  shadow_instances[*],
  text_instances[*],
  image_instances[*],
  custom_instances[*]
}

state_schema = {
  text_resource_schema?,
  image_resource_schema?,
  custom_state_schemas[*]?,
  installation_bookkeeping_schema?
}
```

This is not yet final ASDL syntax.
It is the conceptual machine-feeding split.

### 18.4 relation to canonical machine roles

This conceptual shape should collapse naturally into:

#### `gen`
Derived mainly from:

- `shape`
- any state-schema facts that alter code/layout shape

#### `param`
Derived mainly from:

- `input`

#### `state`
Derived mainly from:

- `state_schema`
- realized runtime-owned resources installed according to that schema

This is a better explanation of the layers than the older story where a terminal just
received some broad payload and somehow decided what was code, data, or state.

### 18.5 the likely ui2 correction

If this sketch is right, then the current ui2 bottom stack likely needs at least these
corrections:

#### correction 1: split machine input from state schema more explicitly

The old `Payload` naming is too likely to blur:

- scene execution input
- runtime-owned resource schema/ownership

These should be more clearly separated.

#### correction 2: split resource specs from draw/query instances

Especially for:

- text
- image

Likely also maybe for some custom families.

#### correction 3: make machine shape a real closed-world shape

`Spec` should probably be described more canonically as machine shape:

- what families/helpers/schema extensions exist
- not scene payload facts

### 18.6 what machine IR is still not

Even with this stronger definition, Machine IR is still **not**:

- a generic runtime graph language
- a semantic query DSL
- a callback routing framework
- a mini bytecode for interpreted execution

The whole point is the opposite.

Machine IR should be the place where semantic uncertainty has already been consumed into
ordinary typed machine-feeding shapes.

### 18.7 possible eventual naming rewrite for ui2

Current provisional rename direction:

Instead of:

```text
UiKernel.Render(
  Spec spec,
  Payload payload
)

UiMachine.Render(
  Gen gen,
  Param param,
  StateModel state
)
```

consider something more explicit like:

```text
UiMachineIR.Render(
  MachineShape shape,
  MachineInput input,
  StateSchema state_schema
)

UiMachine.Render(
  Gen gen,
  Param param,
  State state
)
```

or, if we want to keep `UiKernel` as the Machine IR module name:

```text
UiKernel.Render(
  Shape shape,
  Input input,
  StateSchema state_schema
)

UiMachine.Render(
  Gen gen,
  Param param,
  State state
)
```

Current best guess:

- keep `UiMachine` for the canonical machine layer
- either rename `UiKernel` to a more explicit Machine IR name later, or keep it but
  rename its fields to `Shape / Input / StateSchema`

This should be decided after the next iteration, not frozen immediately.

### 18.8 relation to query and geometry

This sketch is for the render machine, but it also gives us pressure on the earlier
phases.

If render Machine IR wants:

- spans
- headers
- refs
- instances
- resource specs
- state schema requirements

then the layers above it must feed those directly.

That means eventual `UiRender` should probably not be thought of as "render payload"
any more. It should be thought of as the phase that projects solved semantics into
machine-feeding typed shapes.

Likewise, `UiGeometry` should be judged by whether it makes those shapes easy to derive,
not by whether it feels like a nice solved scene object model.

### 18.9 current provisional conclusion

Current best guess:

> Machine IR should be modeled as a typed machine-feeding split such as
> `Shape / Input / StateSchema`, whose purpose is to make canonical `gen, param,
> state` derivation trivial.

That is stronger and clearer than the old `Spec / Payload` language.

### 18.10 open questions after machine IR sketch v0

1. should Machine IR always carry an explicit `StateSchema`, or can some systems derive
   it directly from `Shape`?
2. should `DrawState` remain a first-class table/ref in `Input`, or collapse into headers
   or instances?
3. should clips be first-class resource-like specs, plain tables, or draw-state-attached
   input?
4. is `UiKernel` still the right module name, or does it hide the stronger Machine IR
   concept too much?
5. for query, do we need an analogous `Shape / Input / StateSchema` split, or mostly just
   a machine input story?

### 18.11 next step

Next write:

- query machine sketch v0

before deriving the earlier pure phases again.

---

## 19. query machine sketch v0

We now switch to the other major machine-feeding consumer.

Goal:

> identify the machine-facing shape for query/reducer/routing work.

This section matters because earlier ui2 design kept render and query mixed too long.
We now want to ask the same machine questions for query that we just asked for render.

### 19.1 first correction: query may not need the same full machine split as render

The render side clearly wants:

- runtime-owned resource state
- resource specs
- family-specific execution payload
- a real `gen / param / state` split

Query may be different.

Current suspicion:

- query may still want machine-happy typed shapes
- but it may need much less `state`
- and possibly much less `gen`

That means the query side should still be designed machine-first, but we should not force
it to mimic render mechanically.

### 19.2 what the query machine actually does

At a high level, query/reducer work likely wants to answer questions like:

- what hit item is under this point?
- what focus item comes next/previous?
- what scroll host handles this delta?
- what edit host receives this text/edit action?
- what command binding matches this key event?
- what accessibility items exist in query order?

Those are machine questions too.
But they are different from rendering.

### 19.3 likely query machine-happy shape families

Current best guess:

#### definitely needed

- `Span`
- `Header` or region routing header equivalent
- `Instance`
- maybe a few `Ref` shapes

#### maybe not needed, or much less needed

- `ResourceSpec`
- `ResourceState`

That already suggests query Machine IR may be much leaner than render Machine IR.

### 19.4 likely query order shapes

The query machine still needs explicit execution order.

Candidate order shapes:

#### A. region routing span

```text
QueryRegionSpan(
  hit_start, hit_count,
  focus_start, focus_count,
  key_start, key_count,
  scroll_start, scroll_count,
  edit_start, edit_count,
  accessibility_start, accessibility_count
)
```

Role:

- preserves top-level region order
- preserves region-local query slices without tree walking
- gives the reducer/router one stable routing structure

This looks very likely.

#### B. maybe specialized spans per plane

Possible additional shapes:

- `HitSpan`
- `FocusSpan`
- `KeySpan`
- `ScrollSpan`
- `EditSpan`
- `AccessibilitySpan`

Current guess:

- standalone span records may be unnecessary if region headers/spans already carry these
  ranges directly

### 19.5 likely query header shapes

The query machine probably wants at least region-level routing headers.

Conceptual example:

```text
QueryRegionHeader(
  z_index,
  modal,
  consumes_pointer,
  hit_start, hit_count,
  focus_start, focus_count,
  key_start, key_count,
  scroll_start, scroll_count,
  edit_start, edit_count,
  accessibility_start, accessibility_count
)
```

Role:

- gives one execution/routing unit for top-level reducer queries
- closes over modality/pointer-consumption semantics at region granularity

Current guess:

- region routing header is more likely than many smaller header streams

### 19.6 likely query instance shapes

This is probably the real core of query input.

#### A. hit instance

Conceptual example:

```text
HitInstance(
  id,
  semantic_ref?,
  shape,
  z_index,
  pointer_bindings,
  scroll_binding?,
  drag_drop_bindings
)
```

Open question:

- should `z_index` live on the instance or be implied by region ordering?

Current guess:

- region ordering may already carry enough top-level order
- but keeping explicit z/order on hit items may still simplify the reducer

#### B. focus instance

```text
FocusInstance(
  id,
  semantic_ref?,
  rect,
  mode,
  order?
)
```

#### C. key route instance

```text
KeyRouteInstance(
  id,
  chord,
  when,
  command,
  global
)
```

#### D. scroll host instance

```text
ScrollHostInstance(
  id,
  semantic_ref?,
  axis,
  model?,
  viewport_rect,
  content_extent
)
```

#### E. edit host instance

```text
EditHostInstance(
  id,
  semantic_ref?,
  model,
  rect,
  multiline,
  read_only,
  changed?
)
```

#### F. accessibility instance

```text
AccessibilityInstance(
  id,
  semantic_ref?,
  role,
  label?,
  description?,
  rect,
  sort_priority
)
```

These all look much more like direct query instances than like resources.

### 19.7 likely query refs

Query may still want some refs, but likely fewer than render.

Possible examples:

- `RegionRef(index)` for routing context
- `ScrollModelRef(index?)` if query payload gets normalized further
- maybe focus-chain refs if focus navigation is compiled into linked order

Current best guess:

- query mostly wants direct instance records plus region headers/spans
- refs are secondary here unless they simplify focus/key routing materially

### 19.8 does query need resources?

Current answer:

- probably not in the same sense as render

Why:

- query is mostly about solved geometry-attached interaction facts
- it does not usually realize backend-owned resources like textures
- it does not obviously need `ResourceSpec` / `ResourceState` families for built-in query

That is a useful asymmetry.

It means query Machine IR may be mostly:

- shape
- input

with trivial or absent state schema.

### 19.9 possible query machine split

Very provisional conceptual shape:

```text
QueryMachineIR = {
  shape,
  input,
  state_schema?
}
```

where:

```text
shape = {
  region_routing_policy,
  focus_navigation_shape?,
  key_routing_shape?
}

input = {
  region_headers[*],
  hit_instances[*],
  focus_instances[*],
  key_route_instances[*],
  scroll_host_instances[*],
  edit_host_instances[*],
  accessibility_instances[*]
}

state_schema = {
  maybe_focus_runtime_state?,
  maybe_edit_runtime_state?
}
```

Current guess:

- query `state_schema` may be empty or tiny for the core query machine
- session/editor state likely stays outside this machine in `UiSession.State`

### 19.10 relation to reducer state

Important distinction:

- `UiSession.State` is app-visible interaction/session state
- query machine state, if any, would be machine-owned runtime state

Current strong suspicion:

- most focus/hover/selection/edit session truth belongs in `UiSession.State`, not in the
  query machine's runtime state

So we should be careful not to smuggle session state into a fake query-machine `state`
just because render has a strong resource-state story.

### 19.11 likely consequence for phase design

If this sketch is right, then query projection should probably produce a very direct
instance/header language.

That means the eventual query-side pure phase wants to answer:

- what are the region routing headers?
- what are the hit/focus/key/scroll/edit/accessibility instances?

not:

- what solved node tree shall we preserve for later query extraction?

This reinforces the earlier diagnosis that mixed node-centered solved/query structures were
wrong.

### 19.12 current provisional conclusion

Current best guess:

> query Machine IR is likely much leaner than render Machine IR: mostly region routing
> headers/spans plus direct query instances, with little or no resource-spec/resource-state
> story for built-in query.

That asymmetry is probably important and should not be flattened away for aesthetic
symmetry.

### 19.13 open questions after query machine sketch v0

1. does query need any real `state_schema` for built-ins, or is it effectively stateless?
2. should focus navigation be represented as plain ordered instances, or as an explicit
   compiled navigation structure?
3. should key routing stay as direct instances, or be normalized into a more indexed form?
4. should hit ordering rely purely on region order + item order, or include explicit z/order
   fields on instances?
5. how much of current reducer work belongs in query projection versus `UiSession.State`?

### 19.14 next step

Next write:

- consequences for earlier phases

Now that both render and query machine sketches exist.

---

## 20. consequences for earlier phases v0

We now have enough bottom-up pressure to revisit the layers above the machines.

We have sketched:

- render `state`
- render `param`
- render `gen`
- render Machine IR
- query Machine IR

So now we ask:

> what earlier phases must exist to make those machine-feeding shapes easy and honest to produce?

This section is the first real attempt to re-derive the pure layers above the machines.

### 20.1 strongest bottom-up conclusions so far

Current strongest conclusions:

1. render and query should separate earlier than they used to
2. resource identity and scene occurrence should separate, especially for text/image
3. runtime resource ownership belongs in machine `state`, not in pure lower phases
4. machine input wants spans/headers/refs/instances/specs, not giant solved nodes
5. query likely wants a much leaner machine-feeding shape than render

These conclusions already put strong pressure on the old middle pipeline.

### 20.2 what geometry must now do

Geometry is still a real coupling point.

Both render and query need solved geometry.
But geometry no longer looks like it should produce:

- draw atoms
- visual state trees
- behavior nodes
- accessibility nodes with mixed solved semantics
- packed plan payloads

Instead, geometry should likely produce only the solved facts that render/query actually
share.

Current best guess:

### geometry should produce

- solved rects/boxes
- content boxes / padding boxes / border boxes if needed
- child extents / scroll extents
- maybe solved hit shape base geometry if that is truly geometry-coupled

### geometry should not produce

- render instances
- query instances
- resource specs
- clip tables as final machine-feeding records
- family batching
- key routes
- accessibility packed order tables

So geometry should get narrower than the old `UiSolved` concept.

### 20.3 likely consequence: the old giant lowered node is still too broad

Earlier we provisionally introduced `UiLowered` as one orthogonal lowered phase.

That may still be too broad.

Why:

- render wants resource specs + draw instances
- query wants routing headers + direct query instances
- geometry only wants layout/intrinsic/participation facts

This suggests there may be at least three different pure consumers above source/bound/flat:

1. geometry input facts
2. render projection facts
3. query projection facts

So the key question becomes:

> do we really want one shared `UiLowered`, or do we want a smaller shared base plus
> earlier branching into render/query-specific fact languages?

Current suspicion:

- one giant lowered phase is probably still too convenient and too broad

### 20.4 likely earlier pure-layer split

Current best guess of the pure shape above the machines:

```text
UiBound
  -> flatten
UiFlat
  -> lower_geometry
UiGeometryInput
  -> solve
UiGeometry
  -> project_render_facts
UiRenderInput
  -> build_machine_ir
UiRenderMachineIR

UiGeometry
  -> project_query_facts
UiQueryInput
  -> build_machine_ir
UiQueryMachineIR
```

This is stronger than the provisional redraw.

It says:

- one shared geometry path is real
- render/query projection should branch after geometry
- but render/query may each want their own machine-feeding input language before machine IR

### 20.5 possible naming revision

The provisional names may now be too weak or too broad.

Current naming pressure:

#### shared path

- `UiFlat`
- `UiGeometryInput`
- `UiGeometry`

#### render branch

- `UiRenderInput`
- `UiRenderMachineIR`

#### query branch

- `UiQueryInput`
- `UiQueryMachineIR`

This suggests that the provisional `UiLowered` name may not survive.

Better possibility:

- replace `UiLowered` with a more specific `UiGeometryInput`
- let render/query-specific lowering happen **after** geometry, not before

Why this is attractive:

- geometry is the real shared coupling point
- render/query do not need to share all lowered structure before that point
- it avoids a broad pseudo-shared lower language

### 20.6 revised role of `UiRender`

The provisional `UiRender` idea may also need refinement.

We now have two possible meanings:

1. render projection as a pure scene-level representation
2. render machine-feeding IR itself

Current best guess:

- we should distinguish them if the distinction is real
- but we should not invent both if one collapses naturally into the other

Question:

> does render really need both `UiRenderInput` and `UiRenderMachineIR`, or can one of
> them simply be the Machine IR?

Current suspicion:

- render may be happiest if its post-geometry projection already directly produces
  machine-feeding shapes
- in that case, `UiRenderInput` and `UiRenderMachineIR` may collapse into one phase

So for render, a plausible simpler path is:

```text
UiGeometry
  -> project_render_machine_ir
UiRenderMachineIR
  -> derive gen/param/state
```

That is attractive because it avoids a fake extra layer.

### 20.7 revised role of `UiQuery`

The same question applies to query.

Current suspicion:

- query may not need an intermediate layer either
- `UiGeometry -> project_query_machine_ir` may be enough

because query Machine IR already looked very direct:

- region routing headers
- query instances

So a plausible simpler query path is:

```text
UiGeometry
  -> project_query_machine_ir
UiQueryMachineIR
```

Again, this avoids a fake extra layer.

### 20.8 current best candidate phase path

This is now the strongest candidate path so far:

```text
UiDecl
  -> bind
UiBound
  -> flatten
UiFlat
  -> lower_geometry
UiGeometryInput
  -> solve
UiGeometry
  -> project_render_machine_ir
UiRenderMachineIR
  -> derive gen/param/state
UiMachine
  -> realize Unit

UiGeometry
  -> project_query_machine_ir
UiQueryMachineIR
  -> feed reducer/query execution
```

This is a meaningful revision of the provisional redraw.

Key differences from the provisional redraw:

- `UiLowered` may disappear
- `UiRender` may collapse into render Machine IR
- `UiQuery` may collapse into query Machine IR
- geometry remains the one real shared solved coupling point

### 20.9 what this says about the old phases

#### old `UiDemand`

Looks wrong because it mixed:

- geometry input
- render facts
- query facts
- accessibility facts

into one lowered node language.

#### old `UiSolved`

Looks wrong because it mixed:

- geometry
- draw atoms / visual state
- behavior nodes
- accessibility solved facts

into one solved node language.

#### old `UiPlan`

Looks wrong because it still implied a mixed packed output before the machine truth had
been made explicit enough.

### 20.10 current provisional conclusion

Current best guess:

> the real shared pure phase after flattening is probably `UiGeometryInput -> UiGeometry`.
> After that, render and query should likely project directly into their own machine IRs
> rather than detouring through broad shared lower representations.

This is currently the strongest bottom-up architectural candidate.

### 20.11 open questions after earlier-phase consequences v0

1. does `UiFlat` already need to split into facet planes, or can `UiGeometryInput` do that
   cleanly enough?
2. should accessibility travel with query from the moment geometry is projected, or is any
   earlier special casing needed?
3. does render really need a pure pre-machine layer distinct from render Machine IR?
4. does query need any explicit machine module at all, or only a packed query IR consumed
   by reducer logic?
5. what is the simplest naming family that makes the new path obvious?

### 20.12 next step

Next write:

- candidate phase path and naming revision v0

so we can decide what to rename in the ASDL before implementing again.

---

## 21. candidate phase path and naming revision v0

We now try to freeze the best current candidate architecture strongly enough that we can
revise the ASDL around it.

This section is still provisional, but it is the first attempt to turn the machine-first
reasoning into a concrete naming/path recommendation.

### 21.1 phase-path goal

The goal is not to preserve prior names.
The goal is to choose names and boundaries that tell the truth about:

- what is shared
- what knowledge is consumed
- what directly feeds the machines

So naming should now follow the strongest bottom-up conclusions rather than historical
habit.

### 21.2 strongest current candidate path

Current best candidate path:

```text
UiDecl
  -> bind
UiBound
  -> flatten
UiFlat
  -> lower_geometry
UiGeometryInput
  -> solve
UiGeometry
  -> project_render_machine_ir
UiRenderMachineIR
  -> define_machine
UiMachine
  -> realize Unit

UiGeometry
  -> project_query_machine_ir
UiQueryMachineIR
  -> feed reducer/query execution
```

This is currently the most honest path we have.

### 21.3 candidate naming family

The old names now appear too weak in several places.

#### keep

These still look right:

- `UiDecl`
- `UiBound`
- `UiFlat`
- `UiGeometry`
- `UiMachine`

#### replace or revise

These are currently suspect:

- `UiLowered`
- `UiRender`
- `UiQuery`
- `UiKernel`
- `Spec`
- `Payload`
- `StateModel`

### 21.4 recommended replacements

Current best guess:

#### `UiLowered` -> `UiGeometryInput`

Reason:

- this is the real shared input language for the geometry solver
- it should not pretend to be one generic lowered language for everything

Verb:

- `UiFlat.Scene:lower_geometry() -> UiGeometryInput.Scene`

#### `UiKernel` -> maybe keep for now, but likely rename to `UiRenderMachineIR`

Reason:

- the stronger concept is no longer merely "kernel"
- it is explicitly the render machine-feeding IR
- `UiKernel` may still be acceptable as a short name, but it now hides the stronger truth

Current pragmatic recommendation:

- in design docs/sketching, prefer `UiRenderMachineIR`
- when revising code, decide whether to keep `UiKernel` as a historical implementation
  name or rename the module fully

#### `UiRender` -> probably remove as a separate module unless it proves real

Reason:

- current bottom-up reasoning suggests render projection may directly produce render
  Machine IR
- a separate `UiRender` phase may be fake unless it consumes real knowledge distinct from
  `project_render_machine_ir`

#### `UiQuery` -> probably remove as a separate module unless it proves real

Reason:

- current bottom-up reasoning suggests query projection may directly produce query
  Machine IR
- query Machine IR already looked very close to the reducer-facing packed form

### 21.5 recommended field naming at the machine IR layer

If we keep a dedicated render Machine IR module/record, current best naming pressure is:

Instead of:

```text
Render(
  Spec spec,
  Payload payload
)
```

prefer:

```text
Render(
  Shape shape,
  Input input,
  StateSchema state_schema
)
```

Reason:

- `Shape` says what feeds `gen`
- `Input` says what feeds `param`
- `StateSchema` says what feeds runtime `state`

This is much more canonical than `Spec / Payload`.

### 21.6 recommended field naming at the machine layer

Current pressure:

Instead of:

```text
Render(
  Gen gen,
  Param param,
  StateModel state
)
```

prefer:

```text
Render(
  Gen gen,
  Param param,
  State state
)
```

or, if we need to distinguish pure schema from realized runtime state more clearly in the
ASDL:

```text
Render(
  Gen gen,
  Param param,
  StateSchema state
)
```

Current best guess:

- the canonical machine layer should stay named `Gen / Param / State`
- but if the ASDL record is still describing the required runtime state shape rather than
  live runtime state itself, `StateSchema` may still be the more truthful type name inside
  Machine IR rather than inside `UiMachine`

This needs one more pass when we actually rewrite the ASDL.

### 21.7 candidate module path options

We now have two plausible naming strategies.

#### Option A: explicit machine-ir naming

```text
UiDecl
UiBound
UiFlat
UiGeometryInput
UiGeometry
UiRenderMachineIR
UiQueryMachineIR
UiMachine
```

Pros:

- very explicit
- aligns with the new terminology directly
- easiest to reason about during redesign

Cons:

- longer names
- bigger code churn

#### Option B: pragmatic shorter names with stronger field names

```text
UiDecl
UiBound
UiFlat
UiGeometryInput
UiGeometry
UiKernel        -- but with Shape/Input/StateSchema fields
UiQuery         -- only if truly machine-ir-like
UiMachine
```

Pros:

- less churn
- easier migration from current code

Cons:

- hides the stronger concept more
- risks keeping old mental models alive

Current best guess:

- use explicit names in the redesign/sketch doc
- decide later whether code should keep some shorter names for pragmatism

### 21.8 recommended reducer-facing naming

Since query may project directly into query Machine IR or near-machine packed query input,
the reducer boundary should probably stop talking about a mixed `plan`.

Recommended conceptual signatures:

```text
UiSession.State:apply(query_ir, event)
UiSession.State:apply_with_intents(query_ir, event)
```

not:

```text
UiSession.State:apply(plan, event)
```

because the reducer does not consume render-machine truth.

### 21.9 current recommended provisional rename map

Current rename map:

```text
UiLowered         -> UiGeometryInput
UiKernel.Spec     -> UiRenderMachineIR.Shape
UiKernel.Payload  -> UiRenderMachineIR.Input
UiMachine.StateModel or kernel-side state schema
                  -> StateSchema
UiRender          -> maybe delete/collapse
UiQuery           -> maybe delete/collapse
```

And current conceptual render path:

```text
UiGeometry
  -> project_render_machine_ir
UiRenderMachineIR
  -> define_machine
UiMachine
```

Current conceptual query path:

```text
UiGeometry
  -> project_query_machine_ir
UiQueryMachineIR
  -> reducer/query execution
```

### 21.10 what should remain undecided for now

We should still avoid freezing these too early:

1. whether `UiKernel` gets fully renamed in code or only conceptually
2. whether query gets its own explicit machine module name
3. whether `State` vs `StateSchema` is the right type name in `UiMachine`
4. whether render/query Machine IRs should share a common naming pattern in code
5. whether `UiFlat` itself needs field-shape revision before `UiGeometryInput` is designed

### 21.11 current provisional conclusion

Current best naming/path recommendation:

> Shared pure path:
> `UiDecl -> UiBound -> UiFlat -> UiGeometryInput -> UiGeometry`
>
> Then branch directly into machine-facing IRs:
> `UiRenderMachineIR` and `UiQueryMachineIR`
>
> Then derive canonical `gen, param, state` from render Machine IR and package as `Unit`.

This is now the strongest candidate architecture in the redesign road.

### 21.12 next step

Next write:

- concrete ASDL rewrite plan v0

listing exactly which provisional modules/types should be removed, renamed, or added.

---

## 22. concrete ASDL rewrite plan v0

We now turn the current strongest architecture candidate into an explicit rewrite plan.

Goal:

> list exactly which provisional modules and type families should be removed,
> renamed, kept, or newly added before implementation restarts.

This is still a sketch, but it should now be concrete enough to drive the next ASDL edit.

### 22.1 current target architecture to rewrite toward

Current best candidate target:

```text
UiDecl
  -> bind
UiBound
  -> flatten
UiFlat
  -> lower_geometry
UiGeometryInput
  -> solve
UiGeometry
  -> project_render_machine_ir
UiRenderMachineIR
  -> define_machine
UiMachine
  -> realize Unit

UiGeometry
  -> project_query_machine_ir
UiQueryMachineIR
  -> reducer/query execution
```

### 22.2 modules to keep

These still look structurally right and should remain:

- `UiCore`
- `UiAsset`
- `UiDecl`
- `UiInput`
- `UiSession`
- `UiIntent`
- `UiApply`
- `UiBound`
- `UiFlat`
- `UiGeometry`
- `UiMachine`

Caveat:

- some internal type shapes inside `UiFlat`, `UiGeometry`, and `UiMachine` may still need
  revision
- "keep" here means keep the module role, not necessarily every current type unchanged

### 22.3 modules to remove or replace

#### remove/replace `UiLowered`

Reason:

- too broad as a shared lowered language
- current bottom-up reasoning says the real shared lower consumer is geometry input

Replacement:

- `UiGeometryInput`

#### remove/replace `UiRender`

Reason:

- may be a fake intermediate layer if render projection can directly produce render
  Machine IR

Replacement:

- `UiRenderMachineIR`

#### remove/replace `UiQuery`

Reason:

- may be a fake intermediate layer if query projection can directly produce query
  machine-facing input

Replacement:

- `UiQueryMachineIR`

#### remove/replace current `UiKernel`

Reason:

- conceptually this is now understood as render Machine IR
- current names `Spec / Payload` under-describe what it really should be

Replacement options:

- full rename to `UiRenderMachineIR`
- or retain module but rename types/fields to the stronger canonical names

Current design recommendation:

- conceptually treat it as `UiRenderMachineIR`
- decide full code/module rename later when implementing

### 22.4 new modules to add explicitly

#### `UiGeometryInput`

Role:

- shared pure solver input language
- only geometry-relevant facts

Boundary:

- `UiFlat.Scene:lower_geometry() -> UiGeometryInput.Scene`

#### `UiRenderMachineIR`

Role:

- render machine-feeding typed layer
- should make `gen / param / state` derivation trivial

Boundary:

- `UiGeometry.Scene:project_render_machine_ir() -> UiRenderMachineIR.Render`

#### `UiQueryMachineIR`

Role:

- query machine-feeding typed layer
- likely much leaner than render Machine IR

Boundary:

- `UiGeometry.Scene:project_query_machine_ir() -> UiQueryMachineIR.Scene`

### 22.5 module-level rename map

Current provisional module rewrite map:

```text
UiLowered          => UiGeometryInput
UiRender           => remove or fold into UiRenderMachineIR
UiQuery            => remove or fold into UiQueryMachineIR
UiKernel           => conceptually UiRenderMachineIR
```

### 22.6 type-family rewrite plan for `UiFlat`

`UiFlat` is currently kept, but likely remains an important split point.

Current plan:

#### keep conceptually

- `Scene`
- `Region`
- topology/header truth

#### revise as needed

Likely ensure it can feed geometry lowering cleanly without dragging query/render semantics
as one giant node record.

Two options remain open:

##### option A: facet-split `UiFlat`

Keep explicit planes such as:

- headers
- layout facets
- content facets
- visual facets
- query facets
- accessibility facets

##### option B: simpler flat node + immediate geometry lowering

Keep a somewhat richer flat node, but ensure `lower_geometry` quickly projects only
geometry-relevant facts.

Current guess:

- the facet split still seems attractive
- but it should be decided after the first concrete `UiGeometryInput` sketch

So rewrite instruction for now:

> do not freeze `UiFlat` further until `UiGeometryInput` is sketched concretely.

### 22.7 type-family rewrite plan for `UiGeometryInput`

This is the first new shared lower language.

It should contain only what the geometry solver wants.

#### keep/move into `UiGeometryInput`

From current provisional/lower shapes, likely move or re-express:

- participation truth relevant to layout
- size specs
- flow/grid/cell/alignment/padding/margin/gap
- overflow/aspect facts relevant to solving
- anchor targets lowered to flat indices
- intrinsic size descriptors for:
  - text
  - image
  - custom

#### explicitly exclude from `UiGeometryInput`

- render draw instances
- render resource specs
- query routing instances
- accessibility packed output
- final clip tables
- final batching
- any resource-state schema

So rewrite instruction:

> `UiGeometryInput` must be strictly geometry-feeding, not general lowered scene truth.

### 22.8 type-family rewrite plan for `UiGeometry`

`UiGeometry` should remain the solved shared coupling point.

#### keep

- solved boxes/rects
- content/padding/border boxes if needed
- child extents / scroll extents

#### remove if still present conceptually

- draw atoms
- render visual state bundles
- query node bundles
- packed plan projections
- resource specs
- resource state schema

So rewrite instruction:

> `UiGeometry` should be solved geometry only, plus only the minimum carried identity/
> semantic attachment needed for later projection.

### 22.9 type-family rewrite plan for render machine IR

Whether named `UiKernel` or `UiRenderMachineIR`, the render machine IR should be rebuilt
around the stronger split:

#### replace

- `Spec` -> `Shape`
- `Payload` -> `Input`

#### add explicitly

- `StateSchema`

#### likely `Input` subfamilies

- region spans
- batch headers
- maybe draw-state table / clip table
- text resource specs
- image resource specs
- optional custom resource specs
- box instances
- shadow instances
- text draw instances
- image draw instances
- custom instances

#### likely `Shape` subfamilies

- built-in family support
- custom family set
- helper/state-schema extension shape if needed

#### likely `StateSchema` subfamilies

- text resource state schema
- image resource state schema
- custom state schema
- installation bookkeeping schema

So rewrite instruction:

> rebuild render machine IR around `Shape / Input / StateSchema` and test all current
> `Spec / Payload` records against that split.

### 22.10 type-family rewrite plan for query machine IR

This is new and likely leaner.

#### add explicitly

- region routing headers/spans
- hit instances
- focus instances
- key route instances
- scroll host instances
- edit host instances
- accessibility instances

#### maybe add

- tiny `Shape` if focus/key routing policy materially alters reducer machine shape
- tiny `StateSchema` only if query truly owns runtime machine state

#### likely exclude

- resource specs
- resource state schema for built-in query
- render-family concepts

So rewrite instruction:

> keep query machine IR direct and lean; do not force render-like symmetry where the
> query machine does not need it.

### 22.11 type-family rewrite plan for `UiMachine`

`UiMachine` remains the canonical machine layer and should stay.

#### keep conceptually

- `Gen`
- `Param`
- `State`
- `Render`

#### revise naming pressure

Current pressure:

- if `UiMachine` still carries a pure schema rather than live runtime state meaning, we may
  need to check whether `State` or `StateSchema` is the more truthful ASDL type name there
- but the canonical role names should remain clearly readable as `gen / param / state`

Rewrite instruction:

> keep `UiMachine` as the canonical machine layer; revisit only the exact type names inside
> it after render/query machine IR rewrite is sketched more concretely.

### 22.12 boundary rewrite plan

Current boundary rewrite target:

```text
UiDecl.Document:bind() -> UiBound.Document
UiBound.Document:flatten() -> UiFlat.Scene
UiFlat.Scene:lower_geometry() -> UiGeometryInput.Scene
UiGeometryInput.Scene:solve() -> UiGeometry.Scene
UiGeometry.Scene:project_render_machine_ir() -> UiRenderMachineIR.Render
UiGeometry.Scene:project_query_machine_ir() -> UiQueryMachineIR.Scene
UiRenderMachineIR.Render:define_machine() -> UiMachine.Render
UiMachine.Gen:compile(target) -> Unit
UiMachine.Render:materialize(target, assets, state)
UiSession.State:apply(query_ir, event)
UiSession.State:apply_with_intents(query_ir, event)
```

This is the rewrite target for the schema surface.

### 22.13 recommended implementation order after ASDL rewrite

Once the ASDL is revised, current best implementation order is:

1. `UiGeometryInput` sketch in ASDL
2. render Machine IR sketch in ASDL
3. query Machine IR sketch in ASDL
4. schema stub rewrite
5. `lower_geometry`
6. `solve`
7. `project_render_machine_ir`
8. `project_query_machine_ir`
9. `define_machine`
10. reducer adaptation to query IR

### 22.14 current provisional conclusion

Current best rewrite plan:

> Replace the broad provisional lower stack with a geometry-shared path and direct
> machine-IR branches:
>
> - `UiLowered` becomes `UiGeometryInput`
> - `UiRender` and `UiQuery` likely disappear as separate broad intermediate modules
> - render Machine IR is rebuilt around `Shape / Input / StateSchema`
> - query Machine IR is introduced as a direct lean routing/instance layer
> - `UiMachine` stays the canonical `gen / param / state` layer

### 22.15 next step

Next write:

- first concrete `UiGeometryInput` ASDL sketch

because that is now the first shared pure phase that the whole rewrite depends on.

---

## 23. red-team review of the sketch v0

This section is the deliberate attack phase.

The goal is not to defend the current sketch.
The goal is to find every place where the current sketch would either:

- force unnecessary work
- hide semantic coupling
- duplicate structure uselessly
- leak runtime work upward or semantic work downward
- or tempt us into rebuilding an accidental interpreter during implementation

The stronger design thesis here is:

> with the correct ASDL, stable identity, and memoized boundaries at the real coupling
> points, the implementation can always be pushed toward doing the least semantically
> necessary work.

So red-teaming the ASDL early is performance work.

### 23.1 biggest issue: `UiGeometry` is too pure to feed later projections by itself

Current sketch path says:

```text
UiGeometry
  -> project_render_machine_ir
UiRenderMachineIR

UiGeometry
  -> project_query_machine_ir
UiQueryMachineIR
```

But the current `UiGeometry` sketch contains only:

- headers
- solved geometry
- participation

It does **not** contain:

- render facts
- query facts
- accessibility facts
- content facts needed for render resource specs

So as written, `UiGeometry` alone cannot honestly feed either render or query Machine IR.

This is the single most important issue discovered so far.

#### why this matters

If we ignore this, implementation will be forced to cheat by:

- reaching back to earlier phases ad hoc
- threading hidden side inputs
- rebuilding semantic facts late
- or widening `UiGeometry` again until it quietly becomes another mixed solved node layer

That would recreate the original problem.

#### current candidate fixes

There are only a few honest options:

##### option A: carry sidecar fact planes through geometry

Make `UiGeometry.Region` hold:

- headers
- geometry nodes
- render facets
- query facets
- accessibility facets

This keeps geometry solved, but carries the non-geometry fact planes structurally alongside
it for later projection.

Risk:

- `UiGeometry` becomes broader again
- but if the carried planes are orthogonal and unchanged, this may still be acceptable

##### option B: split post-flat branching earlier

Instead of one shared path all the way to `UiGeometry`, do something more like:

```text
UiFlat
  -> lower_geometry -> UiGeometryInput
  -> lower_render_facts -> UiRenderFacts
  -> lower_query_facts -> UiQueryFacts

UiGeometryInput -> solve -> UiGeometry
UiGeometry + UiRenderFacts -> project_render_machine_ir
UiGeometry + UiQueryFacts  -> project_query_machine_ir
```

This is currently the cleanest-looking option.

Why:

- geometry stays geometry-only
- render/query facts stay orthogonal
- later projection has exactly the two inputs it really needs

Current red-team judgment:

> option B is currently the strongest candidate.

##### option C: widen `UiGeometryInput` and `UiGeometry` into one giant shared lower truth again

This would be the regression path.

Current judgment:

- reject unless forced by some later discovery

### 23.2 likely wrong current assumption: one shared post-flat lowered language

The current sketch already moved away from the old `UiLowered`, but not far enough.

The red-team conclusion is:

> there is likely no single honest shared lowered language after `UiFlat` other than the
> geometry input language itself.

The real shared thing is:

- topology
- identity
- geometry coupling inputs

Render-specific and query-specific lowered facts probably want to branch **before** the
geometry solve and then rejoin geometry later by stable flat identity.

This is a major architectural conclusion.

### 23.3 custom intrinsic is too weak in `UiGeometryInput`

Current sketch says:

```text
Intrinsic = ... | Custom(number family, number payload)
```

This is too weak for a geometry solver.

Why:

- a custom intrinsic must still tell geometry something measurable
- raw `family + payload` is just deferred interpretation
- the solver cannot know min/max/content extent from that shape alone

So this is an accidental-interpreter warning.

#### likely fix

Custom intrinsic likely needs a real geometry-facing type, for example something like:

- `FixedIntrinsic(Size intrinsic)`
- `RangeIntrinsic(min_w, min_h, ideal_w, ideal_h, max_w?, max_h?)`
- or a family-specific already-measured intrinsic summary

Current red-team judgment:

> custom intrinsic must be lowered into a solver-facing measurable form, not left as an
> opaque family/payload pair.

### 23.4 built-in family booleans in render `Shape` may be fake `gen`

Current render `Shape` sketch includes:

- `supports_boxes`
- `supports_shadows`
- `supports_text`
- `supports_images`

Red-team concern:

- if built-ins are always part of the canonical runner, these booleans are not true
  machine-shaping facts
- they then become ornamental data pretending to be `gen`

That would weaken the split.

#### likely fix

Current likely better answer:

- built-in family support is canonical and fixed
- only custom family set and any truly variable helper/schema extensions belong in
  `Shape`

Current red-team judgment:

> remove fixed built-in support booleans from `Shape` unless we prove they genuinely alter
> code shape per machine.

### 23.5 query `Shape` may also be fake `gen`

Current query `Shape` sketch includes:

- `region_first_routing`
- `ordered_focus_navigation`
- `global_key_routes`

Red-team concern:

- these may be global invariants of the query architecture, not per-machine shape facts
- if so, they do not belong in `gen`

#### likely fix

Current likely better answer:

- make these semantics fixed by the query machine design itself
- only introduce explicit query `Shape` fields if there are real varying machine forms

Current red-team judgment:

> query may not need a meaningful `Shape` record at all in the built-in path.

This is a useful asymmetry and should not be papered over.

### 23.6 `StateSchema` is still too placeholder-like

Current render `StateSchema` sketch has records like:

- `TextStateSchema(enabled)`
- `ImageStateSchema(enabled)`
- `InstallationSchema(tracks_capacities)`

This is still too weak to justify itself.

Red-team concern:

- booleans here may just be placeholders, not real schema truth
- if text/image state families are canonical, their mere presence should not need a field
- if custom families extend state, that extension shape is the real schema fact

#### likely fix

A better schema may need to describe:

- which runtime-owned state families exist canonically
- which families are extension points
- what slot families or resource-state families exist

Current red-team judgment:

> `StateSchema` should describe runtime-owned state families structurally, not as vague
> enable flags.

### 23.7 `DrawStateRef` may be premature abstraction

Current render Machine IR uses:

- `DrawStateRef`
- separate `DrawState*` table

Red-team concern:

- if draw state is used only batch-locally, this indirection may buy nothing
- unnecessary refs create extra conceptual machinery without reducing work

#### likely fix

Need to decide by machine honesty:

- if draw state is genuinely shared structurally, keep table + ref
- if it is only batch-local metadata, inline it into `BatchHeader`

Current red-team judgment:

> do not keep `DrawStateRef` unless there is real sharing or locality value.

### 23.8 `Clip` may not be a resource-like table

Current render Machine IR has:

- `Clip* clips`
- `ClipRef`

This may be right, but it is not yet proven.

Red-team concern:

- clip policy might be more naturally a batch-local draw-state attribute
- or a deduped table might indeed be the right shared access shape

Current judgment:

- unresolved
- but must be justified by either sharing, locality, or code-shape simplification

### 23.9 `UiGeometry.NodeHeader` duplication may be unnecessary

Current sketch duplicates `NodeHeader` in:

- `UiGeometryInput`
- `UiGeometry`

Red-team concern:

- this may just be mechanical duplication
- if the header shape truly does not change, one shared header type may be enough

Possible fix:

- reuse `UiGeometryInput.NodeHeader` in `UiGeometry.Region`
- or introduce one canonical flat header type in `UiFlat`

Current judgment:

- this is probably not the deepest issue, but worth simplifying early

### 23.10 region semantics may be over-carried in geometry input

`UiGeometryInput.Region` currently keeps:

- `z_index`
- `modal`
- `consumes_pointer`

Red-team question:

- are these genuinely needed by geometry input, or only needed later by render/query
  projection?

Likely answer:

- geometry solve itself probably does not need them
- but carrying them at region level may still be fine if the shared region header is the
  stable place they belong

Current judgment:

- acceptable for now, but they should remain clearly region-header semantics, not solver
  facts

### 23.11 query instances may still be too eager in some places

Current query machine sketch carries direct instances such as:

- `KeyRouteInstance`
- `FocusInstance`
- `ScrollHostInstance`

This mostly looks right.

But red-team question:

- are all of these really direct instances, or do some want an indexed/access-shaped form
  for faster routing?

Example:

- key routing might eventually want chord-grouped indexing rather than a flat list
- focus navigation might want an explicit navigation structure rather than relying only on
  sorted instances

Current judgment:

- the direct-instance sketch is a good truthful first pass
- but query may still want some additional access structures derived from instances
  if reducer routing cost matters

### 23.12 accessibility probably belongs entirely on the query branch

Current sketches already lean that way.

Red-team confirmation:

- accessibility has no render-machine resource story
- accessibility has no geometry-solver-specific role beyond needing solved rects
- accessibility should likely travel with query-side projection only

Current judgment:

> keep accessibility on the query branch; do not reintroduce it into shared geometry or
> render machine IR.

### 23.13 likely revised candidate architecture after red-team pass

After attacking the current sketch, the strongest candidate now looks like:

```text
UiDecl
  -> bind
UiBound
  -> flatten
UiFlat
  -> lower_geometry       -> UiGeometryInput
  -> lower_render_facts   -> UiRenderFacts
  -> lower_query_facts    -> UiQueryFacts

UiGeometryInput
  -> solve
UiGeometry

UiGeometry + UiRenderFacts
  -> project_render_machine_ir
UiRenderMachineIR
  -> define_machine
UiMachine
  -> Unit

UiGeometry + UiQueryFacts
  -> project_query_machine_ir
UiQueryMachineIR
  -> reducer/query execution
```

This is now stronger than the earlier single-branch shared-path story.

### 23.14 current strongest architectural conclusion

Current strongest red-team conclusion:

> the shared pure path likely ends at geometry.
> render/query-specific lowered facts should probably branch from `UiFlat` before solve,
> then rejoin solved geometry by stable flat identity during machine-ir projection.

That is the current best answer to the biggest discovered flaw.

### 23.15 consequences for naming

If the above conclusion holds, the naming likely wants another revision.

Instead of only:

- `UiGeometryInput`
- `UiGeometry`
- `UiRenderMachineIR`
- `UiQueryMachineIR`

we may also need explicit branch-side fact modules such as:

- `UiRenderFacts`
- `UiQueryFacts`

These would be pure lowered fact languages, not machine IR yet.

Current judgment:

- do not commit fully yet
- but this is now the leading candidate

### 23.16 implementation-risk summary

Biggest risks if we ignore the red-team findings:

1. `UiGeometry` will silently widen back into another mixed solved layer
2. custom intrinsic will become a hidden interpreter hook in the solver
3. `Shape` and `StateSchema` will accumulate ornamental booleans instead of real machine
   facts
4. render/query projection will cheat by reaching back to earlier phases implicitly
5. implementation will reintroduce semantic lookup because the ASDL did not give enough
   explicit access structure

### 23.17 next step recommendation

Before implementing against the current sketch, we should do one more design step:

> sketch `UiRenderFacts` and `UiQueryFacts` as candidate branch-side lowered fact modules
> and compare that architecture against the current simpler path.

If those sketches look cleaner, we should revise the target architecture before touching
live implementation.

---

## 24. red-team review after adding `UiRenderFacts` and `UiQueryFacts`

We now attack the revised sketch again.

The new candidate architecture is better than before, but it still has several likely
problems. This section tries to surface them before any implementation starts.

### 24.1 major positive result: the architecture is now much more honest

First, the good news.

Adding:

- `UiRenderFacts`
- `UiQueryFacts`

was a major correction.

It fixed the biggest earlier lie:

- `UiGeometry` no longer has to pretend to contain non-geometry truth
- later machine-ir projection no longer has to pretend it can run from geometry alone

So the architecture is now substantially more truthful than the previous candidate.

That means the red-team focus shifts from "this is the wrong overall shape" to:

- are these new fact modules themselves shaped correctly?
- are the machine-ir shapes now truly machine-facing, or still carrying placeholders?

### 24.2 biggest remaining issue: alignment between branches is still implicit

We now have three sibling outputs from `UiFlat`:

- `UiGeometryInput`
- `UiRenderFacts`
- `UiQueryFacts`

These will later rejoin by flat identity.

But the current sketch still leaves the actual join contract too implicit.

#### current risk

If the join is only "same region order, same fact order, trust me", implementation may be
forced to:

- assume positional alignment informally
- rebuild lookup tables ad hoc
- or reintroduce semantic joins by id when projecting machine IR

That would weaken both clarity and performance.

#### likely fix

We likely need one explicit alignment guarantee.

Current best options:

##### option A: each fact plane is indexed exactly like `UiFlat` headers

That means:

- one fact record per flat node
- region arrays match node-header order exactly
- projection joins by integer index only

This is probably the strongest option.

##### option B: each fact plane carries explicit `node_index`

That is weaker and more redundant, but still explicit.

Current red-team judgment:

> the branch-side fact planes should probably align one-to-one with the flat node index
> space, and that contract should be explicit in the ASDL comments and type intent.

### 24.3 `UiRenderFacts.Region` is currently too weak

Current sketch:

```text
Region(id, Fact* facts)
```

This is probably too weak.

Why:

- it does not say whether `facts[i]` aligns with flat node `i`
- it does not carry root/header/topology context
- it leaves join semantics too implicit

#### likely fix

Current likely better shape:

- either include shared node headers explicitly
- or state clearly that `facts` is a region-local node-aligned array indexed exactly like
  `UiFlat` / `UiGeometryInput` / `UiGeometry`

Current red-team judgment:

> `UiRenderFacts.Region` needs an explicit alignment contract, not just `Fact* facts`.

### 24.4 `UiQueryFacts.Region` has the same alignment problem

Current sketch:

```text
Region(id, z_index, modal, consumes_pointer, Fact* facts)
```

The region-level query semantics are useful, but the per-node fact alignment is still too
implicit.

#### likely fix

Same as render facts:

- explicit aligned-by-index contract
- or explicit node index carried per fact

Current judgment:

> the branch-side fact modules should not rely on tacit positional agreement.

### 24.5 `TextContent.resource_key` is probably premature and maybe wrong

This is one of the most important new issues.

Current sketch in `UiRenderFacts.TextContent` includes:

- `resource_key`

Red-team concern:

- final text resource identity likely depends on solved geometry, especially width
- wrapping and final rasterization identity may depend on the solved content width
- therefore a final `resource_key` may not be knowable yet at `lower_render_facts`

This is a serious issue.

#### why it matters

If we bake `resource_key` too early, then either:

- it is wrong and must be recomputed later
- or it omits width-dependent truth and creates cache aliasing bugs
- or it forces hidden semantics into projection

#### likely fix

Replace early `resource_key` with something more honest, such as:

- `resource_seed` or no key at all
- then compute final `TextResourceSpec.key` during `project_render_machine_ir` when
  geometry is available

Current red-team judgment:

> final text resource identity should probably be derived at render-machine-ir projection,
> not earlier.

### 24.6 `ImageContent.corners` is probably in the wrong place

Current sketch puts image corners in:

- `ImageContent`

But corners look much more like:

- scene occurrence / instance use
n- destination drawing shape

than resource identity.

#### likely fix

Move image corners out of resource-like content identity and into the eventual image draw
instance or decoration-like use-site facts.

Current red-team judgment:

> image resource identity and image draw-shape occurrence are still partially mixed.

### 24.7 `UiRenderFacts.Content.Custom(number family, number payload)` is still too opaque

This is the render-side version of the earlier custom-intrinsic problem.

Red-team concern:

- if later projection must interpret raw custom payload to discover whether it represents
  a resource-like thing, a pure instance, or some hybrid, then we are deferring machine
  modeling too late

#### likely fix

Current likely better answer:

- split custom render facts into more explicit closed categories where possible, such as:
  - `CustomResourceLike(...)`
  - `CustomInstanceLike(...)`
  - or a family-specific already-lowered render fact shape

Current red-team judgment:

> raw custom render payload is still an interpreter risk unless the family boundary is
> already semantically lowered enough.

### 24.8 `UiQueryFacts.Fact` may still mix too much per-node query truth

The query side is much better than before, but the current shape is still one broad record:

- hit
- focus
- pointer
- scroll
- keys
- edit
- drag_drop
- accessibility

Red-team concern:

- this may still be too much bundling if different projections/use paths vary separately
- especially accessibility may not vary with the same concerns as pointer/edit/key

Counterpoint:

- unlike render, query Machine IR projection may still naturally consume one node-aligned
  interaction fact bundle

Current judgment:

- acceptable for now
- but we should stay suspicious if implementation starts peeling this apart repeatedly

### 24.9 `UiQueryMachineIR.Input` may eventually want indexed substructures

Current query Machine IR uses flat instance arrays.
That is a good first pass.

But red-team concern remains:

- key routing may want chord-grouped access
- focus navigation may want explicit next/prev structures
- hit routing may want pre-sorted order guarantees beyond raw arrays

Current judgment:

- keep flat arrays for now
- but watch for projection code that repeatedly rebuilds routing indices
- if that happens, those indexed access structures belong in query Machine IR

### 24.10 `UiRenderMachineIR.Shape` still contains likely fake facts

The new branch-side facts did not solve this earlier issue.

Current sketch still has:

- `supports_boxes`
- `supports_shadows`
- `supports_text`
- `supports_images`

Red-team judgment remains:

> these should probably go unless we prove they materially alter machine shape.

The better current guess is:

- built-ins are canonical runner vocabulary
- custom family set and true extension shape are the real `Shape` facts

### 24.11 `UiQueryMachineIR.Shape` still likely wants deletion or collapse

Same issue as before.

If query routing policy is canonical, then:

- `region_first_routing`
- `ordered_focus_navigation`
- `global_key_routes`

are probably not per-machine shape facts.

Current red-team judgment:

> query built-ins may not need an explicit `Shape` record at all.

Possible replacement:

- `QueryMachineIR.Scene(Input input)` only
- or `Shape` exists only when genuine query machine variants appear

### 24.12 `UiMachine.Query` may be premature abstraction

Current sketch gives query a canonical machine form:

- `QueryGen`
- `QueryParam`
- `QueryState?`

That is architecturally clean, but red-team concern:

- the reducer may simply consume `UiQueryMachineIR` directly without a meaningful extra
  define-machine step
- if so, `UiMachine.Query` may be needless ceremony

Current judgment:

- keep it conceptually for now
- but do not force a code-level query machine layer if it adds no real narrowing

### 24.13 `UiGeometryInput.Region` may still be carrying too much region semantics

Current geometry input region includes:

- `z_index`
- `modal`
- `consumes_pointer`

These are still not geometry-solver facts.

We previously tolerated this because they are shared region semantics.
But now that render/query facts have their own branches, this deserves another look.

#### likely fix

Possible better answer:

- keep one shared `UiFlat.RegionHeader` and let each lower branch decide what region
  semantics it actually carries
- geometry input may not need all region semantics directly

Current judgment:

> geometry input should be rechecked for region-header over-carrying after the alignment
> contract is made explicit.

### 24.14 the new likely core invariant

The strongest invariant emerging from this pass is:

> after `UiFlat`, all branch-side pure outputs should probably share the same region/local
> node index space and align by index, so later joins are structural and memo-friendly.

This is likely the crucial ASDL invariant that prevents hidden join work.

### 24.15 likely revised architecture after second red-team pass

The current strongest candidate now looks like:

```text
UiDecl
  -> bind
UiBound
  -> flatten
UiFlat
  -> lower_geometry      -> UiGeometryInput
  -> lower_render_facts  -> UiRenderFacts
  -> lower_query_facts   -> UiQueryFacts

UiGeometryInput
  -> solve
UiGeometry

UiGeometry + UiRenderFacts   (aligned by flat region/node index)
  -> project_render_machine_ir
UiRenderMachineIR
  -> define_machine
UiMachine.Render
  -> Unit

UiGeometry + UiQueryFacts    (aligned by flat region/node index)
  -> project_query_machine_ir
UiQueryMachineIR
  -> reducer/query execution
```

### 24.16 strongest current conclusions

Current strongest conclusions after the second red-team pass:

1. branch-side fact planes were the right correction
2. those fact planes now need an explicit alignment contract
3. text resource identity likely cannot be finalized before geometry
4. image content still mixes resource identity with use-site shape
5. query machine shape is probably much smaller than currently sketched
6. query may not need a real `UiMachine` layer in code unless a later step proves it
7. render Machine IR `Shape` and `StateSchema` still need another tightening pass

### 24.17 next recommended design step

Before implementation, the next best move is:

> revise the sketch ASDL itself around the strongest red-team findings:
> - add explicit alignment intent for `UiRenderFacts` / `UiQueryFacts`
> - remove or weaken premature `resource_key` on text content
> - split image identity vs occurrence more honestly
> - tighten or collapse fake `Shape` fields
> - strengthen `StateSchema`

That should happen before the live ASDL rewrite.

---

## 25. shared-header redesign pass

We now attack the next highest-leverage issue:

- shared header ownership
- region/header duplication
- structural join guarantees across branches

### 25.1 conclusion

Current best answer:

> after `UiFlat`, branch-side and solved phases should reuse one canonical shared flat
> header vocabulary so joins happen by construction rather than by convention.

This means the sketch should prefer one shared header language reused by:

- `UiGeometryInput`
- `UiGeometry`
- `UiRenderFacts`
- `UiQueryFacts`

### 25.2 why this is better

This buys several things at once:

- removes duplicated header type definitions
- makes branch alignment explicit in the types
- reduces risk of silent shape drift across branches
- keeps joins index-based and memo-friendly
- makes later projection code structurally simpler

### 25.3 what should be shared

Current best shared minimum:

- region identity/header
- flat node header/topology

Current best non-shared truth:

- geometry input facts
- solved geometry
- render facts
- query facts
- region semantics that only some branches need

### 25.4 region semantics should not all be forced into geometry input

This pass also reinforces an earlier concern:

- `z_index`
- `modal`
- `consumes_pointer`

do not belong to the geometry solver as solver facts.

They may still belong to render/query branches as region semantics.
So the shared region header should stay minimal.

### 25.5 current status after this pass

The sketch now wants a canonical shared header vocabulary, with branch-specific region
semantics layered on top where needed.

That is a cleaner answer than duplicating headers in every module or forcing all region
semantics through the geometry path.

### 25.6 next red-team target

The next highest-leverage remaining issues are now:

1. render/query fact branch shapes themselves
2. custom render/query family lowering honesty
3. whether `Clip` and `DrawState` in render machine IR are the right access shapes
4. whether query wants additional indexed access structures beyond direct instances

---

## 26. `UiFlat` sketch consequence

After the shared-header pass, the next obvious implication is that `UiFlat` itself should
be understood as the first shared structural spine plus orthogonal source-side fact planes.

Current best sketch direction:

- `UiFlat` owns canonical shared region/node headers
- `UiFlat` owns region semantics
- `UiFlat` carries node-aligned branch source planes for:
  - geometry lowering
  - render lowering
  - query lowering

This is stronger than thinking of `UiFlat` as one more fat node record.

### 26.1 current best role of `UiFlat`

`UiFlat` should probably be the place where we first make explicit:

- one shared structural spine
- several orthogonal fact planes

That means `UiFlat` is not merely:

- tree flattened into arrays

It is more specifically:

> the canonical branch source from which multiple later lowerings proceed while staying
> structurally aligned by construction.

### 26.2 why this matters

This gives a cleaner story for the next boundaries:

- `lower_geometry`
- `lower_render_facts`
- `lower_query_facts`

because each of those can now be understood as consuming one aligned fact plane rather
than peeling fields off another giant lower node.

### 26.3 current open risk

Even with this improvement, we still need to red-team whether `UiFlat` is carrying too much
pre-lowered branch content versus the right amount of source-side meaning.

That remains the next pressure point.

---

## 27. red-team review of `UiFlat`

We now attack the new `UiFlat` sketch specifically.

This is an important stage, because `UiFlat` is starting to look like the true branching
point of the whole lower architecture.
If it is shaped wrong, every later branch will inherit that mistake.

### 27.1 major positive result

The new `UiFlat` sketch is a large improvement over a giant mixed flat node.

It now gives us:

- a canonical shared structural spine
- explicit region semantics
- separate branch source planes

That is already much healthier.

But the red-team question is now:

> are the branch source planes at the right semantic height?

### 27.2 biggest issue: `UiFlat` may already be too lowered for branch source

Current branch source planes include things like:

- fully explicit text style fields
- image intrinsic size in geometry source
- paint and behavior directly reused from bound-level structures

Red-team concern:

- `UiFlat` may be doing more semantic commitment than the structural branch point should do
- if so, `UiFlat` stops being a clean shared flat source and becomes another disguised
  lowering phase

#### likely design rule

Current likely better rule:

> `UiFlat` should establish structural alignment and preserve already-bound semantics,
> but should avoid consumer-specific lowering decisions where those are not yet forced.

That means `UiFlat` should probably stay closer to:

- aligned source-side/bound-side facet planes

than to:

- already consumer-tailored lowered fact records

### 27.3 `GeometrySource` may be too solver-shaped already

Current `GeometrySource` includes:

- explicit measurable custom content
- explicit geometry text content fields
- explicit image intrinsic size

Some of that is right.
But red-team concern:

- if `UiFlat` already carries fully solver-shaped intrinsic forms, then `lower_geometry`
  may become a meaningless phase
- that would mean we pushed too much geometry-specific lowering into the flattening step

#### likely fix

We should distinguish more clearly between:

- `UiFlat.GeometrySource` = aligned branch source facts
- `UiGeometryInput` = actual solver-facing lowered language

Current likely better answer:

- `UiFlat.GeometrySource` should preserve enough bound/source-side meaning to remain a real
  branch source
- `lower_geometry` should still have meaningful work, such as:
  - participation folding
n  - anchor lowering to flat indices
  - intrinsic summarization
  - geometry-specific normalization

Current red-team judgment:

> `GeometrySource` should probably be less solver-shaped than the current sketch.

### 27.4 `RenderSource` may be too close to `UiRenderFacts`

Current `RenderSource` includes:

- `UiBound.Paint`
- `RenderContent`

Red-team concern:

- if `RenderSource` already looks too much like `UiRenderFacts`, then `lower_render_facts`
  will become weak or redundant
- `UiFlat` should probably carry source-side/bound-side render meaning, not already-lowered
  render fact forms

#### likely fix

Possible better direction:

- `RenderSource` should maybe just carry `UiBound.Paint` and `UiBound.Content`
- let `lower_render_facts` produce `Effect / Decoration / RenderContent` as a real lowering

Current red-team judgment:

> `RenderSource` is likely too lowered already and should stay closer to bound semantics.

### 27.5 `QuerySource` may actually be close to right

Current `QuerySource` is:

- `UiBound.Behavior`
- `UiBound.Accessibility`

This currently looks more plausible.

Why:

- query lowering still has plenty of real work to do:
  - convert behavior syntax into query facts
  - lower accessibility hidden/exposed into query-facing truth
  - attach/normalize route facts

So current judgment:

> `QuerySource` may already be near the right semantic height.

### 27.6 `RegionSemantics` placement looks right

Current `UiFlat.RegionSemantics` contains:

- `z_index`
- `modal`
- `consumes_pointer`

This looks much better here than inside geometry input.

Current judgment:

> region semantics probably belong at `UiFlat` and should be selectively carried into the
> render/query branches that need them.

### 27.7 `UiFlat` may need even stronger facet purity

Current `UiFlat` has three branch source planes:

- geometry
- render
- query

But a further red-team question is:

- should `UiFlat` itself avoid branch naming and instead expose more primitive aligned
  facets like `layout`, `content`, `paint`, `behavior`, `accessibility`, `flags`?

This would push branch grouping one step later.

Possible advantage:

- more reusable orthogonal planes
- less risk of branch-specific early bundling

Possible downside:

- more lowering functions must assemble what each branch needs
- branch source boundaries become slightly less explicit

Current judgment:

- unresolved
- but worth keeping in mind if the current branch-source shapes start collapsing into each
  other awkwardly

### 27.8 likely issue: custom content is still not branch-honest enough

In `UiFlat`, custom content currently appears in different branch-specific ways.
That is already better than before, but still dangerous.

Red-team concern:

- custom handling may be forcing us to invent ad hoc content variants in each branch
- if custom meaning is not lowered honestly enough per branch, custom paths will become the
  place where hidden interpretation leaks back in

Current judgment:

> custom facts likely need branch-specific lowering contracts that are more explicit than
> raw `family/payload`, especially for geometry and render.

### 27.9 strongest likely revision to `UiFlat`

Current best red-team guess:

`UiFlat` should probably carry aligned **facet planes** closer to bound semantics, such as:

- flags/participation source
- layout source
- content source
- paint source
- behavior source
- accessibility source

and then the branch lowerings should consume those aligned facets to produce:

- `UiGeometryInput`
- `UiRenderFacts`
- `UiQueryFacts`

This may be cleaner than making `UiFlat` itself pre-group facts into geometry/render/query
source planes.

### 27.10 likely revised understanding

That suggests a revised architecture reading:

```text
UiBound
  -> flatten
UiFlat              -- shared headers + aligned facet planes
  -> lower_geometry
UiGeometryInput
  -> solve
UiGeometry

UiFlat + UiGeometry
  -> lower/project render branch
UiRenderFacts / UiRenderMachineIR

UiFlat + UiGeometry
  -> lower/project query branch
UiQueryFacts / UiQueryMachineIR
```

or perhaps more concretely:

```text
UiFlat
  -> lower_geometry      -> UiGeometryInput
  -> lower_render_facts  -> UiRenderFacts
  -> lower_query_facts   -> UiQueryFacts
```

but with `UiFlat` itself staying facet-oriented rather than branch-source-oriented.

### 27.11 strongest current conclusion

Current strongest conclusion after red-teaming `UiFlat`:

> `UiFlat` should likely be the shared aligned facet plane layer, not a partly lowered
> branch-source language.

That is an important refinement.

### 27.12 next recommended action

The sketch ASDL should likely be revised accordingly:

- replace branch-source-heavy `UiFlat` records with more facet-oriented aligned planes
- keep branch-specific meaning for the actual lower_* phases

That is probably the next highest-value sketch correction.

---

## 28. red-team review of `UiGeometryInput`

Now that `UiFlat` has been revised into aligned facet planes, we can attack `UiGeometryInput`
more honestly.

The key question is now:

> does `UiGeometryInput` really look like a geometry solver language, or is it still
> carrying too much source-side and branch-irrelevant meaning?

### 28.1 major positive result

`UiGeometryInput` is much healthier than the old giant lowered node.

It is already limited to:

- shared headers
- participation-like truth
- layout specs
- intrinsic descriptors

That is a strong improvement.

### 28.2 biggest issue: `Participation.visible/enabled` is still suspicious

Current sketch uses:

- `visible`
- `enabled`

Red-team concern:

- `enabled` does not look like a geometry-solver fact
- geometry likely cares about layout participation, not interaction enablement
- even `visible` may be too UI-semantic if the true solver question is simply whether a
  node participates in layout

#### likely fix

Current likely better answer:

- rename/simplify this to a geometry-specific participation truth, e.g.
  `included_in_layout`
- keep interaction enablement on the query/render side, not in geometry input

Current red-team judgment:

> `enabled` should almost certainly leave `UiGeometryInput`.

### 28.3 `TextIntrinsic` is still probably too raw

Current sketch still carries many raw text fields in `TextIntrinsic`.

Red-team concern:

- if `UiGeometryInput` is truly solver-facing, it should carry measurable text intrinsic
  summaries, not a large text-style packet unless the solver really computes text metrics
  itself
- if min/max widths are already present, many of the raw style fields may be an upstream
  measurement concern rather than a geometry-solver concern

#### likely fix

Current likely better answer:

- keep only the text facts geometry truly needs for intrinsic measurement and height
  estimation
- move the rest of raw render-text identity/style to render facts

Current red-team judgment:

> `TextIntrinsic` likely needs tightening toward measurement summaries rather than rich raw
> text styling.

### 28.4 `ImageIntrinsic` looks closer to right

Current sketch:

- image ref
- intrinsic size

This is closer to a genuine geometry input.

Red-team concern remains:

- if geometry only needs the solved intrinsic size, the image ref itself may be decorative
- but it may still be useful if later phases need structural continuity

Current judgment:

- acceptable for now
- less urgent than text intrinsic

### 28.5 `CustomIntrinsic` is much better, but still incomplete

The earlier opaque `family/payload` problem was fixed.
That is good.

Current concern:

- the current measurable custom summary may still be too weak if aspect/min/max behavior is
  more complex than the current fields express

Current judgment:

- much improved
- acceptable for now as a placeholder measurable contract
- revisit only if custom geometry pressure grows

### 28.6 `Layout` still likely mixes some non-solver semantics

Current layout includes:

- overflow_x / overflow_y
- aspect
- grid/cell/alignment/gap/padding/margin

Most of this looks solver-facing.
But red-team concern:

- some overflow semantics may matter more for later clipping/render than for pure geometry
- we should verify that every field in `Layout` changes solved geometry rather than only
  later visual behavior

Current judgment:

- probably mostly right
- but overflow should remain under suspicion until the projection story settles

### 28.7 `lower_geometry` must still be a real phase

This is the implementation-discovery test.

If `UiFlat` is now facet-oriented, `lower_geometry` should have real work such as:

- convert flags into geometry participation truth
- lower anchor references to flat indices
- normalize layout into solver-facing fields
- summarize text/image/custom intrinsic measurement facts

If we find that `UiGeometryInput` can be built by trivial field copy, then the split is
still wrong.

Current red-team judgment:

> `lower_geometry` should remain a meaningful narrowing phase, not a mere rearrangement.

### 28.8 likely strongest correction

Current strongest likely correction is:

- tighten `Participation` toward geometry participation only
- tighten `TextIntrinsic` toward measurable geometry-facing summary

Those are the highest-leverage fixes in `UiGeometryInput` right now.

### 28.9 next recommended sketch correction

Revise the sketch ASDL to:

- remove `enabled` from geometry participation
- rename/simplify geometry participation to a layout-specific truth
- tighten `TextIntrinsic` one step toward intrinsic measurement summary

That should happen before the next red-team pass.

---

## 29. red-team review of `UiRenderFacts`

Now we attack the render fact branch itself.

This branch matters a lot because it is the place where render-specific meaning should be
preserved without prematurely becoming machine IR.
If it is too high-level, projection will rediscover too much.
If it is too low-level, `lower_render_facts` becomes fake and `UiFlat` was too broad.

### 29.1 major positive result

The current `UiRenderFacts` sketch is already much better than the old mixed lowered node.

It now clearly separates:

- render-side facts
- solved geometry
- machine IR
- runtime state

That is a real architectural win.

### 29.2 biggest issue: `TextContent` is now too weak on the render side

In the previous pass we correctly removed premature `resource_key`.
That was good.

But the current `TextContent` may now have gone too far in the other direction.

Red-team concern:

- render resource identity likely depends on more than just text/font/size/color/wrap/align
- line height, overflow policy, and line limit may still materially affect the realized
  text resource
- if these are missing here, render-machine-ir projection will have to reach back to
  earlier phases or silently invent defaults

#### likely fix

Current likely better answer:

- keep `resource_key` out of `UiRenderFacts`
- but keep the full render-relevant text identity facts here

Current red-team judgment:

> `UiRenderFacts.TextContent` should be rich enough to determine final text resource
> identity once solved geometry is known, even though the final key itself is computed later.

### 29.3 `ImageContent` still needs a cleaner identity/use split

We improved this by moving corners out.
That was good.

But red-team concern remains:

- image fit likely affects how solved geometry becomes the final draw instance
- if fit is absent here, later projection may have to recover it from earlier bound/source
  meaning

#### likely fix

Current likely better answer:

- image identity-like content should include:
  - image ref
  - sampling
  - fit
- image occurrence/use should include:
  - destination-shape-only facts such as rounded corners

Current red-team judgment:

> `ImageContent` probably still needs `fit`, while `Use` should keep only occurrence-level
> shape.

### 29.4 custom render is still the biggest interpreter risk in this branch

Current sketch improved custom from one opaque slot into a somewhat more explicit split.
But it is still risky.

Red-team concern:

- `CustomResource` and `CustomInstance` as raw family/payload pairs are still only a weak
  hint at meaning
- if later projection has to rediscover whether a family is resource-like, instance-like,
  or both, then machine design is still happening too late

#### likely fix

Current likely better answer:

- require `lower_render_facts` to choose a clearer branch-local custom category
- keep custom occurrence-only payload out of the same slot as custom resource identity
- do not let raw `family/payload` remain the only semantic contract if later projection
  must branch heavily on it

Current red-team judgment:

> custom render facts are improved but still the weakest honesty point in the render branch.

### 29.5 `Use` should stay occurrence-only

Current `Use` mechanism is promising.

The right design rule seems to be:

> `Content` carries identity-like render meaning; `Use` carries occurrence-only render shape.

This is good because it matches the machine split we discovered later:

- resource identity
- scene occurrence

So red-team conclusion:

- keep `Use`
- keep it strictly occurrence-level
- do not let identity creep back into it

### 29.6 `Decoration` vs `Content` split looks healthy

This part currently looks good.

Why:

- box/shadow decoration are not the same thing as content identity
- text/image/custom content can remain separate from local decoration/effect facts

Current judgment:

> keep `Effect / Decoration / Content / Use` as the current main render-fact split unless a
> later implementation pressure proves otherwise.

### 29.7 likely current correction set

Current strongest corrections for the sketch are:

1. enrich `TextContent` with the full render-relevant text identity fields
2. add `fit` to `ImageContent`
3. simplify `Use` so it stays strictly occurrence-only
4. tighten custom render categories one step further where possible

### 29.8 next recommended sketch correction

Revise the sketch ASDL to:

- strengthen `UiRenderFacts.TextContent`
- add `fit` to `UiRenderFacts.ImageContent`
- keep `Use` occurrence-only
- simplify custom render shape one step if possible

before the next red-team pass.

---

## 30. red-team review of `UiRenderMachineIR`

Now we attack the render machine IR directly.

This is the place where the render branch must finally become honest about:

- execution order
- addressability
- resource identity
- use-sites
- runtime ownership requirements

So the main question is:

> does the current `UiRenderMachineIR` actually expose the machine truth clearly enough,
> or is it still leaving important wiring implicit?

### 30.1 major positive result

The current sketch already has the right broad decomposition:

- `Shape`
- `Input`
- `StateSchema`
- resource specs separated from instances
- clips and batches made explicit

That is a strong foundation.

### 30.2 biggest issue: `RegionSpan` is named like draw order but actually spans batches

Current sketch uses:

- `RegionSpan(draw_start, draw_count)`

But the machine input does not contain a monolithic draw array.
It contains:

- `BatchHeader* batches`
- family-specific instance arrays

So the region span is really spanning the batch order, not a generic draw order.

Current red-team judgment:

> this is a naming/shape honesty problem and should be corrected.

### 30.3 `BatchHeader` inlining `DrawState` currently looks right

This was previously under suspicion.
Current red-team judgment is more favorable.

Why:

- batches are already the unit of adjacent compatible draw order
- draw state is consumed at batch granularity
- if state is only used there, an extra `DrawStateRef` table may be needless indirection

So current judgment:

> keep `DrawState` inlined on `BatchHeader` for now.

### 30.4 `TextResourceSpec` is now out of sync with render facts

Earlier we correctly enriched `UiRenderFacts.TextContent`.
But `TextResourceSpec` still only carries a smaller subset.

Red-team concern:

- text resource identity and realization almost certainly still depend on more fields than
  are currently present here
- otherwise projection will either drop distinctions or recover hidden defaults

Current likely correction:

- `TextResourceSpec` should carry the full render-resource-defining text facts plus solved
  geometry-dependent width

Current red-team judgment:

> `TextResourceSpec` must be strengthened to match the richer text-content truth now carried
> above it.

### 30.5 `ImageResourceSpec` vs `ImageDrawInstance` still needs the use-site line drawn clearly

Current sketch has:

- `ImageResourceSpec(image, sampling)`
- `ImageDrawInstance(resource, rect, corners)`

But `UiRenderFacts.ImageContent` now also contains `fit`.

Red-team concern:

- `fit` is not resource identity
- but it is a draw/use-site fact the machine likely needs explicitly

Current likely correction:

- keep `ImageResourceSpec` as resource identity
- add `fit` to `ImageDrawInstance`

Current red-team judgment:

> `fit` belongs in the image draw instance, not in the image resource spec.

### 30.6 biggest structural weakness: custom resource wiring is still implicit

Current sketch has:

- `CustomResourceSpec* custom_resources`
- `CustomInstance* customs`

but the custom instance currently does not clearly say whether it:

- references a resource slot
- is instance-only
- is both family-specific and resource-backed

That means the machine truth is still not explicit enough.

Current likely correction:

- split custom instances into explicit resource-backed vs inline-instance forms
- make the resource reference visible in the machine IR itself

Current red-team judgment:

> custom render remains the biggest unresolved honesty problem, and the machine IR should at
> least make resource-backed vs inline-instance custom use explicit.

### 30.7 `StateSchema` is still somewhat generic, but not the first problem

Current sketch uses:

- `ResourceStateFamily*`
- `CustomStateFamily*`
- `InstallationStateFamily`

Red-team concern:

- `CapacityTracking()` may still be too ornamental as a schema fact
- but this is not the highest-value correction right now compared to the resource/use-site
  honesty issues above

Current judgment:

- keep under suspicion
- do not spend the next correction pass here first

### 30.8 likely current correction set

Current strongest immediate corrections are:

1. rename/fix `RegionSpan` so it honestly spans batches
2. strengthen `TextResourceSpec`
3. add `fit` to `ImageDrawInstance`
4. make custom instance wiring explicit with resource-backed vs inline-instance forms

### 30.9 next recommended sketch correction

Revise the sketch ASDL to:

- rename `RegionSpan(draw_start, draw_count)` to batch-oriented naming
- strengthen `TextResourceSpec`
- move image `fit` into `ImageDrawInstance`
- split `CustomInstance` into explicit variants with visible resource reference where needed

before the next red-team pass.

---

## 31. red-team review of `UiQueryMachineIR`

Now we attack the query machine IR directly.

This branch is intentionally asymmetrical with render.
It likely wants:

- direct query use-sites
- compiled access paths for common reducer operations
- little or no runtime-owned machine state

So the main question is:

> is the current `UiQueryMachineIR` really exposing compiled access paths, or is it still
> too close to a bag of instances that the reducer must search?

### 31.1 major positive result

The current sketch already does several important things right:

- region policy is explicit
- hit/focus/key/edit/scroll/accessibility are separated
- there is no fake heavy query state schema
- it does not force a premature `UiMachine.Query`

That is all good.

### 31.2 biggest issue: key routing is still too search-shaped

Current sketch has:

- `KeyRouteInstance* key_routes`
- region spans over those routes

Red-team concern:

- reducer hot-path key handling should not need to scan all region key routes looking for a
  chord/event match
- the machine IR should expose a compiled access path for that match

Current likely correction:

- add explicit key buckets grouped by `(chord, when, scope)`
- let regions span key buckets rather than raw routes

Current red-team judgment:

> key routing needs one more level of compiled access structure.

### 31.3 focus navigation likely also wants a compiled order path

Current sketch has:

- `FocusInstance* focus`
- region spans over focus instances

Red-team concern:

- tab/shift-tab style navigation should not need to rediscover focus order from raw focus
  instances on every query
- if focus order matters, the machine IR should expose that ordered path directly

Current likely correction:

- keep raw focus instances for geometry/hit-linked uses
- add a separate focus-order stream of references or indices

Current red-team judgment:

> focus likely needs an explicit ordered access stream in addition to raw focus instances.

### 31.4 hit instances look much closer to right

Current sketch has:

- region headers
- hit spans
- direct hit instances with shapes and bindings

This looks much more machine-honest already.

Why:

- pointer query really does consume ordered hit shapes directly
- there is no obviously missing additional indexing structure yet beyond draw/query order

Current judgment:

- keep hit routing close to the current shape for now

### 31.5 scroll/edit/accessibility also look plausibly direct

These appear much less index-hungry than key/focus.

Current judgment:

- keep them direct unless benchmark or implementation pressure proves otherwise

### 31.6 region policy placement still looks right

Current `RegionHeader` carries:

- modality
- pointer consumption
- per-kind spans

That still looks like the right place for region-level query policy.

Current judgment:

> keep region policy in `RegionHeader`.

### 31.7 strongest current correction set

Current strongest corrections are:

1. add explicit key-routing buckets
2. add explicit focus-order access stream
3. keep hit/edit/scroll/accessibility direct for now
4. do not force a query-machine state/schema layer unless a later real need appears

### 31.8 next recommended sketch correction

Revise the sketch ASDL to:

- add `KeyRouteBucket`
- add `FocusOrderEntry`
- change region spans from raw key-route ranges to key-bucket ranges
- add focus-order spans alongside raw focus spans

before the next red-team pass.

---

## 32. red-team review of `UiGeometry`

Now we attack the shared solved geometry layer itself.

This is a critical coupling point.
If `UiGeometry` is too broad, then render/query remain entangled.
If it is too weak, then later branches will have to rediscover solved geometry facts or reach
back into earlier phases.

So the main question is:

> does `UiGeometry` contain only genuinely shared solved geometry truth?

### 32.1 major positive result

The broad phase distinction still looks correct.

A separate shared solved geometry layer makes sense because both later branches plausibly need:

- solved rects
- stable flat alignment
- some solved extent facts

So the phase itself still looks real.

### 32.2 biggest issue: `Participation + rects` in one record is dishonest

Current sketch has a single record:

- `Participation state`
- `border_box`
- `padding_box`
- `content_box`
- `child_extent`
- `scroll_extent`

Red-team concern:

- if a node is not included in layout, what do these rects mean?
- carrying boolean participation next to always-present solved boxes suggests fake geometry
  values for excluded nodes
- that is exactly the kind of mixed-state record the redesign is trying to avoid

Current likely correction:

- make solved geometry presence a sum type
- e.g. an excluded node vs a placed node

Current red-team judgment:

> `UiGeometry.GeometryNode` should be a sum type, not a record with an inclusion boolean.

### 32.3 `child_extent` is probably the wrong name

Current sketch uses `child_extent`.

Red-team concern:

- the more semantically honest shared solved fact is probably the solved content extent of the
  node's laid out children/content region
- `child_extent` sounds implementation-shaped and slightly ambiguous

Current likely correction:

- rename it to `content_extent`

Current red-team judgment:

> `content_extent` is likely the more honest shared geometry name.

### 32.4 `scroll_extent` is plausible, but should stay under suspicion

Current sketch carries `scroll_extent` on solved geometry.

This may be correct because:

- it is derived from solved geometry
- query scroll-host projection likely needs it directly
- render may eventually need it too for scroll visuals or clip interpretation

But the concern is:

- it may still be a branch-side derivative rather than core shared geometry

Current judgment:

- acceptable for now
- keep it if we interpret it as solved overflow geometry rather than query policy

### 32.5 solved geometry should stay occurrence geometry only

A useful test here is:

- does this fact describe where/how big the node ended up?
- or does it describe how some later consumer wants to interpret that geometry?

Only the first kind belongs in `UiGeometry`.

That means `UiGeometry` should keep:

- solved rectangles
- solved extents
- solved clipping-relevant geometry if truly geometric

but should not grow things like:

- render clip stacks
- hit policies
- accessibility geometry wrappers
- route ordering semantics

Current judgment:

> the module boundary is right; the main correction is the node shape, not the phase itself.

### 32.6 strongest current correction set

Current strongest corrections are:

1. replace boolean participation-with-rects by an explicit sum type
2. rename `child_extent` to `content_extent`
3. keep `scroll_extent` provisionally, but interpret it narrowly as solved geometry-derived
   overflow extent

### 32.7 next recommended sketch correction

Revise the sketch ASDL to:

- replace `GeometryNode(state, ...)` with `Excluded() | Placed(...)`
- rename `child_extent` to `content_extent`
- keep the rest of the solved geometry layer lean

before the next red-team pass.

---

## 33. red-team review of `UiFlat` content facet and branch-lowering honesty

Now we attack a more subtle question:

> is `ContentFacet = UiBound.Content` the right use of the facet pattern,
> or is it still too raw and too tied to the bound layer?

This matters because content is the main place where geometry and render overlap:

- geometry needs intrinsic consequences of content
- render needs realization identity and use-site consequences of content

So if this boundary is wrong, both branches will be awkward.

### 33.1 major positive result

One important thing should be preserved:

- `content` probably is still **one real facet**

Why:

- `content` is a real domain noun on the node
- and it contains a real domain sum type:
  - no content
  - text
  - image
  - custom

That means the facet pattern should **not** be misread as:

- split every content variant into separate sparse facet arrays

That would be a mistake.

Current judgment:

> keep one `ContentFacet`.

### 33.2 biggest issue: `ContentFacet = UiBound.Content` is too raw a pass-through

Current sketch makes the flat content facet just reuse the entire bound-layer content value.

Red-team concern:

- this makes `UiFlat` too much of a shallow transport of an earlier phase vocabulary
- it hides whether the flat/source-side content contract is actually the right one for later
  branch lowerings
- it leaves branch-lowering honesty underspecified, because the real narrowing work still has
  to be guessed from a reused upstream type

Current red-team judgment:

> `UiFlat` should have its own `ContentSource` vocabulary rather than directly aliasing
> `UiBound.Content`.

### 33.3 do not split a real sum type into fake facet planes

A tempting move would be:

- `TextFacet`
- `ImageFacet`
- `CustomFacet`

Red-team judgment:

- that would likely be wrong here
- text/image/custom are not orthogonal simultaneously-present aspects
- they are mutually exclusive variants of one domain choice

So this would not be a real facet split.
It would be a sum-type decomposition pretending to be facetting.

Current strongest conclusion:

> keep `content` as a single sum-typed facet.

### 33.4 but content still needs a flat-specific source vocabulary

The right correction is probably:

- keep one content facet
- but define `UiFlat.ContentSource`
- make that vocabulary explicit about what later branch lowerings are allowed to rely on

This gives `UiFlat` a real contract of its own.
It stops `UiFlat` from merely inheriting whatever happened to be true of `UiBound.Content`.

### 33.5 text source should likely stay rich here

Current red-team judgment:

- text source probably should remain rich at `UiFlat`
- geometry and render both depend on overlapping text facts
- prematurely stripping text source down here would just force later phases to reach back or
  duplicate summary work

So unlike `UiGeometryInput.TextIntrinsic`, `UiFlat.TextSource` should likely remain close to
bound text meaning.

### 33.6 image source should avoid occurrence-only shape where possible

Current red-team concern:

- image content tends to mix resource identity and use-site/render shape too easily
- at the flat content source level, we should preserve the image source facts that branch
  lowerings need, but avoid sneaking in later occurrence-only rendering shape if it does not
  belong to content itself

Current likely answer:

- image source should carry image identity plus the source-side style facts that later branch
  lowerings genuinely need to derive geometry/render facts
- but `UiFlat` should make this explicit in its own type, not by silently inheriting bound
  image shape wholesale

### 33.7 custom content remains the unresolved honesty point

Current red-team judgment:

- `family/payload` is still only a placeholder source contract
- that is acceptable at flat/source height if later lowerings are explicitly responsible for
  choosing branch-honest measurable/resource/use forms
- but it should remain marked as the weakest point in the content contract

### 33.8 strongest current correction set

Current strongest corrections are:

1. keep one `ContentFacet`
2. stop directly aliasing `UiBound.Content`
3. introduce an explicit flat-layer `ContentSource` sum type
4. keep text/image/custom as variants inside that one source facet

### 33.9 next recommended sketch correction

Revise the sketch ASDL to:

- replace `ContentFacet(UiBound.Content content)` with `ContentFacet(ContentSource content)`
- introduce explicit `TextSource`, `ImageSource`, and `CustomSource` records under
  `UiFlat.ContentSource`
- keep `ContentFacet` as one sum-typed facet rather than splitting it into sparse variant
  planes

before the next red-team pass.

---

## 34. red-team review of `UiFlat` layout/flags boundary

Now we attack the layout/flags boundary specifically.

The key question is:

> are `layout` and `flags` truly orthogonal flat facets, or is one of them just an upstream
> convenience bag that should not survive into the shared flat spine unchanged?

### 34.1 major positive result

`layout` still looks like a real facet.

Why:

- it is a coherent domain concern
- it is mostly consumed by geometry lowering
- later branches should not need to reinterpret broad layout semantics except through solved
  geometry or narrowly selected consequences

Current judgment:

> keep a dedicated layout facet.

### 34.2 biggest issue: `Flags(visible, enabled)` is not one honest lower facet

Current sketch has:

- `FlagsFacet(UiBound.Flags flags)`

where bound flags are:

- `visible`
- `enabled`

Red-team concern:

- these do not look like one coherent lower semantic plane
- `visible` and `enabled` have different downstream consumers and likely different meanings
- geometry may care about layout participation consequences of visibility
- query likely cares strongly about enabled state
- render may care about visibility but not enabled

So bundling them together as one flat facet is probably preserving an upstream convenience bag,
not expressing a real lower architectural truth.

Current red-team judgment:

> `FlagsFacet` should not survive as one mixed flat plane.

### 34.3 do not merge flags into layout just because geometry uses part of them

A tempting correction would be:

- put flags into layout
- let `layout` mean all geometry-relevant source truth

Red-team concern:

- that would mix authored layout intent with participation/interactivity source truth
- it would make layout less semantically clean
- it would also hide the fact that `enabled` is not a geometry concern

Current judgment:

> do not merge `flags` wholesale into `layout`.

### 34.4 likely better split: visibility and interactivity should separate

Current likely better answer:

- keep `layout` as its own facet
- split the old flags bag into narrower source facets, likely along lines such as:
  - visibility/presence source
  - enabled/interactivity source

Why this is better:

- geometry can consume visibility and map it to layout inclusion truth if that is the right
  semantic rule
- render can consume visibility without being forced to care about enabled
- query can consume enabled without being forced to care about layout semantics

Current strongest conclusion:

> `flags` should be decomposed, not preserved.

### 34.5 this is an important facet-pattern lesson

This is a general design lesson inside the ui2 redesign:

- not every upstream record deserves to survive as a flat facet
- facet planes should represent real lower semantic concerns
- convenience bags from earlier phases should often be broken apart if their fields feed
  different later branches

So this is a good example of the facet pattern being more than "copy each existing field
cluster into its own plane".

### 34.6 open semantic caution: what exactly does `visible` mean?

There is still an unresolved semantic question:

- does `visible = false` mean excluded from layout,
- or present in layout but not painted,
- or absent from both render and query?

That exact rule should remain a branch-lowering decision, not be hidden in the flat layer.

That is another reason to keep `visible` as its own source truth rather than prematurely
forcing it into `UiGeometryInput` or `layout`.

### 34.7 strongest current correction set

Current strongest corrections are:

1. keep a dedicated layout facet
2. remove the mixed `FlagsFacet`
3. replace it with narrower source facets
4. let branch lowerings decide how those source truths map into geometry/render/query facts

### 34.8 next recommended sketch correction

Revise the sketch ASDL to:

- remove `FlagsFacet`
- add a `VisibilityFacet`
- add an `InteractivityFacet`
- keep `LayoutFacet` separate

before the next red-team pass.

---

## 35. red-team review of `UiFlat` paint facet and render-facts boundary

Now we attack the paint boundary specifically.

The key question is:

> is `PaintFacet = UiBound.Paint` an honest flat/source contract,
> or is it still just leaking the bound-layer vocabulary downward without making the render
> branch boundary explicit enough?

### 35.1 major positive result

Paint still looks like **one real facet**.

Why:

- it is one coherent node-local visual concern
- unlike `flags`, it is not just a convenience bag of unrelated branch consumers
- several paint operations can co-exist on one node as one local visual intent bundle

So current judgment:

> keep one `PaintFacet`.

### 35.2 do not split paint into fake sparse facets

A tempting move would be to split paint into things like:

- `ClipFacet`
- `OpacityFacet`
- `BlendFacet`
- `DecorationFacet`

Red-team concern:

- that would likely be the wrong use of the facet pattern here
- paint is not several independent always-present aspects; it is one ordered local visual
  intent vocabulary
- splitting it into sparse planes would likely destroy locality and force later phases to
  reconstruct ordering semantics

Current strongest conclusion:

> paint should remain one ordered source facet, not many sparse mini-facets.

### 35.3 biggest issue: direct aliasing to `UiBound.Paint` is too weak a flat contract

Current sketch uses:

- `PaintFacet(UiBound.Paint paint)`

Red-team concern:

- this leaves `UiFlat` with no explicit paint contract of its own
- it hides what the render branch is actually allowed to rely on at the flat/source layer
- it makes `lower_render_facts` look underspecified, because the phase appears to consume an
  upstream type rather than a flat-layer source vocabulary

Current red-team judgment:

> `UiFlat` should define its own `PaintSource` vocabulary.

### 35.4 ordered source visual intent is the right semantic height here

The most important property of paint at this level is probably not just which operations exist,
but that they form an ordered local source-side visual intent stream.

That is exactly the kind of thing `lower_render_facts` should consume and classify into later
render facts such as:

- local effects
- decorations
- custom render facts

So current judgment:

> keep ordered paint ops at `UiFlat`, and let `lower_render_facts` perform the real
> classification/narrowing.

### 35.5 this boundary is analogous to content, but not identical

Like content:

- paint should not just alias a bound-layer type
- `UiFlat` should define its own explicit source-side vocabulary

Unlike content:

- paint is not mainly one mutually-exclusive sum type
- paint is an ordered list of local visual operations

So the right flat shape is not `ContentSource`, but rather something like:

- `PaintSource(PaintOpSource* ops)`

### 35.6 custom paint remains the main weak point here

Current red-team judgment:

- custom paint at this level can still remain a source-side placeholder form like
  `family/payload`
- but it should remain clearly marked as source intent, not mistaken for already-lowered
  render machine meaning

### 35.7 strongest current correction set

Current strongest corrections are:

1. keep one `PaintFacet`
2. stop directly aliasing `UiBound.Paint`
3. introduce explicit `PaintSource` / `PaintOpSource`
4. preserve ordered local visual intent at `UiFlat`
5. let `lower_render_facts` do the real effect/decoration/custom lowering

### 35.8 next recommended sketch correction

Revise the sketch ASDL to:

- replace `PaintFacet(UiBound.Paint paint)` with `PaintFacet(PaintSource paint)`
- introduce explicit flat-layer `PaintSource`
- introduce explicit flat-layer `PaintOpSource`
- keep the paint source ordered rather than splitting it into sparse subfacets

before the next red-team pass.

---

## 36. red-team review of `UiFlat` behavior/accessibility boundary

Now we attack the query-side source boundary.

The key question is:

> should `behavior` and `accessibility` remain separate flat facets,
> and if so, should they still just alias the bound-layer vocabulary?

### 36.1 major positive result

`behavior` still looks like **one real facet**.

Why:

- it is one coherent node-local interaction intent bundle
- several behavior rules can co-exist on one node
- later query lowering should still classify and project these rules into direct query facts and
  access structures

So current judgment:

> keep one `BehaviorFacet`.

### 36.2 `behavior` should not be split into fake sparse facets

A tempting move would be to create separate flat facets for:

- hit
- focus
- pointer
- scroll
- key
- edit
- drag/drop

Red-team concern:

- that would likely be the wrong use of the facet pattern here
- these are not several independent architectural branches yet; they are one source-side
  interaction vocabulary that `lower_query_facts` should still consume and classify
- splitting them into separate flat planes now would likely push query-specific decomposition too
  early into `UiFlat`

Current strongest conclusion:

> keep one behavior facet with a structured source vocabulary.

### 36.3 biggest issue: `BehaviorFacet = UiBound.Behavior` is too weak a flat contract

Current sketch uses:

- `BehaviorFacet(UiBound.Behavior behavior)`

Red-team concern:

- this makes `UiFlat` a shallow transport of the bound query vocabulary
- it underspecifies what the flat/query-source contract actually is
- it makes `lower_query_facts` feel like it is consuming an upstream type rather than a
  deliberate flat-layer source language

Current red-team judgment:

> `UiFlat` should define its own `BehaviorSource` vocabulary.

### 36.4 accessibility should stay separate from behavior

A tempting move would be:

- merge accessibility into behavior because both feed the query branch

Red-team concern:

- branch consumer does not determine facet identity
- accessibility is a distinct semantic concern from interaction behavior
- the user can author/change accessibility semantics independently from pointer/key/edit rules
- keeping them separate preserves orthogonality even if the same later branch consumes both

Current strongest conclusion:

> keep `BehaviorFacet` and `AccessibilityFacet` separate.

### 36.5 but accessibility should also get an explicit flat source contract

Current sketch still aliases:

- `AccessibilityFacet(UiBound.Accessibility accessibility)`

This is less damaging than the behavior alias because accessibility is already a small explicit
sum type.
But the same design rule still applies:

- `UiFlat` should define its own flat/source contract, not merely reuse the bound-layer one by
  accident

Current likely answer:

- add `AccessibilitySource = Hidden() | Exposed(...)`
- keep it simple

### 36.6 query lowering should still have real work

Even after introducing explicit behavior/accessibility source vocabularies,
`lower_query_facts` should still do real work such as:

- turn source interaction intent into direct query facts
- derive hit/focus/key/edit/scroll bindings
- build key buckets
- build focus-order access paths
- keep accessibility as a direct query-side semantic plane

So this correction does not collapse the later phase.
It clarifies its input contract.

### 36.7 strongest current correction set

Current strongest corrections are:

1. keep one `BehaviorFacet`
2. keep `AccessibilityFacet` separate
3. stop directly aliasing `UiBound.Behavior`
4. stop directly aliasing `UiBound.Accessibility`
5. introduce explicit flat-layer `BehaviorSource` and `AccessibilitySource`

### 36.8 next recommended sketch correction

Revise the sketch ASDL to:

- replace `BehaviorFacet(UiBound.Behavior behavior)` with `BehaviorFacet(BehaviorSource behavior)`
- replace `AccessibilityFacet(UiBound.Accessibility accessibility)` with
  `AccessibilityFacet(AccessibilitySource accessibility)`
- introduce explicit flat-layer source vocabularies for both
- keep behavior as one structured source facet rather than splitting it into many sparse planes

before the next red-team pass.

---

## 37. red-team review of the `UiFlat` branch-consumption matrix

Now we attack the whole `UiFlat` contract from another angle.

The question is no longer just whether each individual facet looks plausible.
The question is:

> if we write down which lower branch is allowed to consume which facet, does the matrix look
> clean and honest?

This is a strong test of whether the facet split is real.

### 37.1 proposed branch-consumption matrix

Current best reading is:

- `lower_geometry` should consume:
  - `visibility`
  - `layout`
  - `content`
- `lower_render_facts` should consume:
  - `visibility`
  - `content`
  - `paint`
  - render-region semantics
- `lower_query_facts` should consume:
  - `visibility` (if query participation depends on it)
  - `interactivity`
  - `behavior`
  - `accessibility`
  - query-region semantics

And importantly:

- `lower_geometry` should **not** consume interactivity/behavior/accessibility/paint
- `lower_render_facts` should **not** consume layout directly for final placement
- `lower_query_facts` should **not** consume paint/content except via later solved geometry where
  needed for rects/hit shapes already derived structurally

This matrix already looks much healthier than the old broad lower pipeline.

### 37.2 major positive result

At the node level, the current facet split now mostly passes this test.

In particular:

- `visibility` being cross-branch source truth looks plausible
- `content` being shared by geometry and render looks plausible
- `paint` staying render-only looks plausible
- `interactivity + behavior + accessibility` feeding query looks plausible

So the recent node-facet revisions were directionally correct.

### 37.3 biggest issue: region semantics is still a mixed branch bag

Current sketch still has:

- `RegionSemantics(z_index, modal, consumes_pointer)`

Red-team concern:

- this is the same mistake we already fixed at the node level with `Flags`
- `z_index` is not the same kind of fact as `modal` and `consumes_pointer`
- render primarily cares about z-ordering
- query cares about modality / pointer-consumption policy, and may also care about z-order for
  hit precedence
- geometry does not care about any of these

So this current record is still a convenience bag, not the cleanest branch contract.

Current strongest conclusion:

> region semantics should be split into branch-honest region facets too.

### 37.4 likely better region split

Current likely better answer:

- `RenderRegionFacet(z_index)`
- `QueryRegionFacet(modal, consumes_pointer)`

Possibly query may also want region ordering information later, but that can be expressed through
projection rather than by keeping one mixed region bag here.

### 37.5 visibility remains the only intentionally cross-branch node source truth

This is worth stating explicitly.

Most facets now map cleanly to one or two branches.
But `visibility` is different.
It is a source truth whose consequences may differ across branches:

- geometry may map it to layout inclusion
- render may map it to paint participation
- query may map it to hit/focus participation

That is okay.
This is not a design failure.
It is exactly the kind of shared source truth a flat facet layer should preserve.

### 37.6 this validates the facet pattern, not just the types

The important thing about this pass is that it validates the **consumption rules**:

- shared structural spine
- branch-honest facet planes
- later branch lowerings that only read the least necessary facets

That is the real architectural test.

### 37.7 strongest current correction set

Current strongest corrections are:

1. keep the current node-facet split
2. make the branch-consumption matrix explicit in the design notes
3. split region semantics into render/query region facets
4. keep visibility as an intentional cross-branch source truth

### 37.8 next recommended sketch correction

Revise the sketch ASDL to:

- replace `RegionSemantics(z_index, modal, consumes_pointer)`
- with separate `RenderRegionFacet` and `QueryRegionFacet`
- update `UiFlat.Region` to carry those separately
- keep the rest of the node-facet split as-is for now

before the next red-team pass.

---

## 38. red-team review of `UiFlat -> lower_geometry -> UiGeometryInput`

Now we attack the full geometry-lowering contract.

The key question is:

> given the current `UiFlat` facet split, does `UiGeometryInput` now look like a true
> solver-facing language, or is it still carrying some source/render/query baggage by habit?

### 38.1 major positive result

The contract now basically looks real.

Current best reading is:

- `lower_geometry` consumes only:
  - `visibility`
  - `layout`
  - `content`
- plus shared headers/topology
- and it produces only:
  - layout participation truth
  - solver-facing layout
  - intrinsic measurement summaries

That is a real narrowing phase.

### 38.2 biggest issue: some intrinsic records still leak source identity

Current sketch still has:

- `ImageIntrinsic(image, intrinsic)`
- `CustomIntrinsic(family, ...)`

Red-team concern:

- if geometry truly only needs measurable consequences, then these identity-like fields are not
  solver facts
- carrying them here weakens the contract by letting source identity leak into geometry input
- this is the same general problem we have been trying to eliminate elsewhere

Current strongest conclusion:

> geometry input should carry measurable intrinsic summaries, not resource/custom identity,
> unless the solver truly branches on those identities.

### 38.3 current likely correction

Current likely better answer:

- `ImageIntrinsic` should carry only intrinsic size
- `CustomIntrinsic` should carry only measurable custom intrinsic summary
- if a future solver genuinely branches on custom family-specific geometry rules, that should be
  represented by an honest geometry-facing sum type or measurable contract, not by leaving raw
  family identity in place by default

### 38.4 `TextIntrinsic` now looks much closer to right

After the earlier tightening, `TextIntrinsic` now looks much more solver-honest:

- line height
- min content width
- max content width

Current judgment:

- keep this shape for now
- it is a measurement summary rather than a render-style bag

### 38.5 `Layout` still looks like a real solver language

Current `Layout` still contains things like:

- size specs
- position
- flow
- grid/cell
- align
- padding/margin/gap
- overflow
- aspect

Current judgment:

- still plausible as true solver input
- especially because overflow and aspect can affect solved extents and placement

### 38.6 the phase verb is now clearer

This pass makes the actual job of `lower_geometry` more explicit.
It is not merely copying fields.
It is doing things like:

- map visibility source into layout participation truth
- lower bound position into solver-facing positions with flat anchor indices
- summarize content into geometry intrinsic descriptors
- discard non-geometry identity and branch baggage

That is a real phase.

### 38.7 strongest current correction set

Current strongest corrections are:

1. make the allowed geometry inputs explicit in the design notes
2. remove image identity from `ImageIntrinsic`
3. remove custom family identity from `CustomIntrinsic`
4. keep `TextIntrinsic` as a measurement summary

### 38.8 next recommended sketch correction

Revise the sketch ASDL to:

- tighten `ImageIntrinsic` to size-only measurement truth
- tighten `CustomIntrinsic` to measurable summary only
- keep the rest of `UiGeometryInput` structurally the same for now

before the next red-team pass.

---

## 39. red-team review of `UiGeometry + UiRenderFacts -> UiRenderMachineIR`

Now we attack the render-side join itself.

The key question is:

> once solved geometry rejoins render facts, can we honestly project directly to render machine
> IR, or is that boundary still hiding two different phases inside one function?

### 39.1 major positive result

The inputs to the render-side join now look much healthier than before.

We have:

- `UiGeometry` carrying only shared solved geometry truth
- `UiRenderFacts` carrying only render-side meaning that geometry does not solve

That means the join point itself is real.

### 39.2 biggest issue: direct projection to machine IR is probably still too large a verb

If we project directly from:

- `UiGeometry + UiRenderFacts`

to:

- `UiRenderMachineIR`

then one boundary must do all of these at once:

- filter excluded nodes
- choose which solved box each render use-site should consume
- combine node-local effects into concrete draw-state occurrences
- linearize ordered render occurrences
- derive text/image/custom occurrence geometry
- derive resource specs from occurrence/content facts
- dedupe clips/resources
- batch adjacent compatible occurrences
- assign final machine refs/slots

That is too much for one honest verb.

Current strongest conclusion:

> this direct join is still hiding two real phases.

### 39.3 likely missing intermediate layer: concrete render occurrence scene

The likely missing phase is a render-side occurrence scene between render facts and machine IR.

Current likely path:

```text
UiGeometry + UiRenderFacts
  -> project_render_scene
UiRenderScene
  -> schedule_render_machine_ir
UiRenderMachineIR
```

This is attractive because it cleanly separates two jobs:

1. **project render scene**
   - resolve node-aligned render meaning against solved geometry
   - produce concrete ordered render occurrences with occurrence-level draw state

2. **schedule render machine ir**
   - dedupe resources/clips
   - batch compatible occurrences
   - assign refs/slots
   - pack final machine tables

That feels like two real verbs instead of one overloaded one.

### 39.4 what `UiRenderScene` should contain

Current likely answer:

- region ordering spans
- ordered concrete render occurrences
- occurrence-level resolved draw state
- content/use merged with solved geometry at occurrence level

But it should NOT yet contain:

- resource refs
- clip refs
- batch headers
- deduped resource tables
- runtime state schema

So this is still above machine IR.

### 39.5 why this is better than jumping directly to machine IR

This fixes the exact problem we have been diagnosing repeatedly:

- when one boundary is doing multiple unrelated jobs,
- it is often evidence that a phase is missing.

That appears to be true here.

Current judgment:

> the missing render-occurrence scene is likely a real phase, not just a convenience layer.

### 39.6 strongest current correction set

Current strongest corrections are:

1. stop claiming a direct `UiGeometry + UiRenderFacts -> UiRenderMachineIR` projection
2. introduce an explicit `UiRenderScene` phase
3. move concrete occurrence derivation there
4. keep batching/ref assignment/resource dedupe in `UiRenderMachineIR` projection

### 39.7 next recommended sketch correction

Revise the sketch ASDL to:

- insert `UiRenderScene`
- change the architecture comments accordingly
- change `UiRenderMachineIR` meaning to consume `UiRenderScene`
- keep `UiRenderScene` occurrence-oriented and `UiRenderMachineIR` machine-packing-oriented

before the next red-team pass.

---

## 40. red-team review of `UiRenderScene -> UiRenderMachineIR`

Now we attack the scheduling/packing boundary itself.

The key question is:

> once we already have a concrete render occurrence scene, does the next boundary really look
> like a single honest scheduling/packing phase?

### 40.1 major positive result

After introducing `UiRenderScene`, this boundary is much healthier.

It now plausibly has one real job:

- dedupe shared occurrence state/resources
- batch adjacent compatible occurrences
- assign refs/slots
- pack machine tables

That is a much cleaner verb than the previous overloaded direct projection.

### 40.2 biggest issue: clip-stack semantics are still mismatched across the boundary

Current `UiRenderScene` has:

- `OccurrenceState(clips: UiCore.ClipShape*)`

But current `UiRenderMachineIR` still has:

- `Clip(shape)`
- `DrawState(clip: ClipRef?)`

Red-team concern:

- the occurrence scene is carrying a clip **stack/list**
- the machine IR is still pretending a clip ref points to one clip shape
- that means scheduling would have to either collapse stack semantics or silently reinterpret
  what a "clip" means

Current strongest conclusion:

> machine IR should represent a dedupable clip stack/path, not a single clip shape.

### 40.3 custom resource-backed occurrences are still underspecified

Current `UiRenderScene.CustomOccurrence` distinguishes:

- `InlineCustom(state, family, payload)`
- `ResourceCustom(state, family, payload)`

Red-team concern:

- for a resource-backed custom occurrence, scheduling may need both:
  - resource identity payload
  - instance/use-site payload
- with only one payload field, the boundary is still hiding an interpretation choice

Current strongest conclusion:

> resource-backed custom occurrences should explicitly carry both resource identity payload and
> instance payload if both may exist.

### 40.4 everything else looks much closer to a real scheduling phase

Current judgment:

- text occurrence -> text resource spec + text draw instance looks honest
- image occurrence -> image resource spec + image draw instance looks honest
- batch headers over packed family-specific arrays look honest
- inlined batch draw state still looks fine

So the remaining big issues are mainly:

- clip-stack representation
- custom resource-backed occurrence contract

### 40.5 strongest current correction set

Current strongest corrections are:

1. replace single-shape machine `Clip` with a clip-stack/path record
2. keep `DrawState.clip` as a ref, but let it refer to a deduped clip stack/path
3. strengthen `UiRenderScene.ResourceCustom(...)` to carry separate resource and instance payloads
4. keep the rest of the scheduling boundary as-is for now

### 40.6 next recommended sketch correction

Revise the sketch ASDL to:

- replace `UiRenderMachineIR.Clip(shape)` with a clip-stack/path form
- keep `ClipRef` pointing to that deduped stack/path
- strengthen `UiRenderScene.CustomOccurrence.ResourceCustom(...)` to carry separate resource and
  instance payloads
- keep the rest of `UiRenderScene -> UiRenderMachineIR` structurally the same for now

before the next red-team pass.

---

## 41. red-team review of `UiGeometry + UiQueryFacts -> UiQueryMachineIR`

Now we attack the query-side join contract.

The key question is:

> is direct projection from solved geometry + query facts to query machine IR really honest,
> or is query also hiding a missing occurrence/access-layer split?

### 41.1 major positive result

Query still remains asymmetrically simpler than render.

It still appears true that query does **not** naturally want:

- resource-spec tables
- runtime resource state
- batching as a major machine concern

That asymmetry should remain visible.

### 41.2 biggest issue: direct projection is still probably doing two jobs

Current direct path would still have to do all of this at once:

- filter excluded nodes
- attach solved geometry to query facts
- derive concrete hit/focus/edit/scroll/accessibility occurrences
- derive region-local raw query streams
- build focus-order access paths
- build key-route buckets
- pack final query machine tables

That is the same pattern we just diagnosed on the render side, even if the query side is lighter.

Current strongest conclusion:

> query likely also wants an intermediate concrete occurrence scene, but a much leaner one than
> render.

### 41.3 likely missing phase: `UiQueryScene`

Current likely path:

```text
UiGeometry + UiQueryFacts
  -> project_query_scene
UiQueryScene
  -> organize_query_machine_ir
UiQueryMachineIR
```

This separates:

1. **project query scene**
   - resolve node-aligned query facts against solved geometry
   - produce concrete query occurrences

2. **organize query machine ir**
   - build key buckets
   - build focus-order access paths
   - pack final query tables/region headers

That feels much more honest.

### 41.4 why query remains asymmetrical anyway

Even with this new intermediate layer, query remains much simpler than render.

Why:

- no resource identity story
- no resource state schema
- no batching/materialization machinery
- direct occurrences are already close to machine input

So the new phase should be light.
It is not a mirror of render complexity.

### 41.5 what `UiQueryScene` should contain

Current likely answer:

- region policy and raw per-kind spans
- concrete hit occurrences
- concrete focus occurrences
- concrete key occurrences
- concrete scroll/edit/accessibility occurrences

But it should NOT yet contain:

- key buckets
- focus-order access streams
- other packed access structures that are clearly an organization/indexing step

### 41.6 strongest current correction set

Current strongest corrections are:

1. stop claiming a direct `UiGeometry + UiQueryFacts -> UiQueryMachineIR` projection
2. insert an explicit `UiQueryScene`
3. let `UiQueryScene` hold concrete query occurrences
4. let `UiQueryMachineIR` hold the packed/indexed access structures
5. preserve the query/render asymmetry by keeping query scene and query machine IR lean

### 41.7 next recommended sketch correction

Revise the sketch ASDL to:

- insert `UiQueryScene`
- change the architecture comments accordingly
- change `UiQueryMachineIR` meaning to consume `UiQueryScene`
- keep `UiQueryScene` occurrence-oriented and `UiQueryMachineIR` organization/indexing-oriented

before the next red-team pass.

---

## 42. full red-team consolidation pass

We now stop doing purely local red-team passes and ask a broader question:

> after all of these corrections, is the current sketch architecture coherent enough to
> rewrite the live `ui2` ASDL around it, or are there still unresolved structural mistakes at
> sketch level?

This section summarizes the current state.

### 42.1 strongest stable architectural results

The following now look genuinely stable.

#### A. shared structural spine after flattening

This now looks like a real design discovery, not a local patch:

- `UiFlatShape.RegionHeader`
- `UiFlatShape.NodeHeader`

These give the shared structural alignment space for all later branches.

Current judgment:

> stable and likely ready to carry into the live rewrite.

#### B. `UiFlat` as aligned facet planes, not a mixed lowered node

This also now looks stable.

The strongest current reading is:

- `UiFlat` is the shared aligned source/facet layer
- not a branch-specific lowered language
- not a giant node record

Current judgment:

> stable and likely ready to carry into the live rewrite.

#### C. branch-honest facet split

The current node/region facet split now looks substantially healthier:

Node-level:

- `VisibilityFacet`
- `InteractivityFacet`
- `LayoutFacet`
- `ContentFacet(ContentSource)`
- `PaintFacet(PaintSource)`
- `BehaviorFacet(BehaviorSource)`
- `AccessibilityFacet(AccessibilitySource)`

Region-level:

- `RenderRegionFacet`
- `QueryRegionFacet`

Current judgment:

> stable in principle, though some field details may still move.

#### D. geometry branch split is real

This now looks stable:

```text
UiFlat
  -> lower_geometry
UiGeometryInput
  -> solve
UiGeometry
```

And more specifically:

- `lower_geometry` is now a real narrowing phase
- `UiGeometryInput` is now a true solver-facing language
- `UiGeometry` is now a true shared solved coupling point

Current judgment:

> stable in architecture.

#### E. render and query both needed an occurrence scene before machine organization

This is the biggest structural result from the later red-team passes.

The direct joins:

- `UiGeometry + UiRenderFacts -> UiRenderMachineIR`
- `UiGeometry + UiQueryFacts -> UiQueryMachineIR`

were both hiding missing phases.

The current stronger architecture is:

```text
UiGeometry + UiRenderFacts
  -> project_render_scene
UiRenderScene
  -> schedule_render_machine_ir
UiRenderMachineIR

UiGeometry + UiQueryFacts
  -> project_query_scene
UiQueryScene
  -> organize_query_machine_ir
UiQueryMachineIR
```

Current judgment:

> this looks like a real architectural correction, not a sketch flourish.

### 42.2 current architecture that now looks most plausible

The current strongest candidate architecture is now:

```text
UiDecl
  -> bind
UiBound
  -> flatten
UiFlat

UiFlat
  -> lower_geometry
UiGeometryInput
  -> solve
UiGeometry

UiFlat
  -> lower_render_facts
UiRenderFacts

UiFlat
  -> lower_query_facts
UiQueryFacts

UiGeometry + UiRenderFacts
  -> project_render_scene
UiRenderScene
  -> schedule_render_machine_ir
UiRenderMachineIR
  -> define_machine
UiMachine.Render
  -> Unit

UiGeometry + UiQueryFacts
  -> project_query_scene
UiQueryScene
  -> organize_query_machine_ir
UiQueryMachineIR
  -> reducer/query execution
```

This is much clearer than the earlier broad lower pipeline.

### 42.3 strongest remaining unresolved weak points

Even after all of this, a few weak points remain.

#### A. custom contracts remain the least honest area

This is still true across:

- `ContentSource.CustomSource`
- `UiRenderFacts.CustomContent`
- `UiRenderScene.CustomOccurrence`
- `UiRenderMachineIR.CustomResourceSpec / CustomInstance`

Current judgment:

- custom is no longer completely opaque
- but it is still the part of the sketch most at risk of hiding family-specific interpreter
  pressure too late

This remains the main structural risk.

#### B. exact visibility semantics are still not frozen

We have intentionally preserved `visibility` as a shared source truth.
That was the right move.

But one semantic question remains open:

- does `visible = false` imply exclusion from layout,
- render only suppression,
- query suppression,
- or some branch-specific combination?

Current judgment:

- this should remain explicit in lowering contracts
- but the exact rule is not fully frozen yet

#### C. `UiRenderScene` draw-state shape may still need one more pass

The current shape is much better, but still may need refinement around:

- clip-path representation
- whether occurrence state is the right grouping boundary for all render families
- whether some custom families need more explicit occurrence typing

Current judgment:

- improved enough to proceed
- but still worth validating during implementation

#### D. `UiQueryScene` may still prove slightly too broad or too narrow

The current query scene is intentionally lean.
That is good.

But one open question remains:

- whether some query occurrence kinds should stay direct to machine IR,
  while others alone deserve organization/indexing

Current judgment:

- current split is plausible enough to implement
- but query may still simplify further once real code pressure appears

### 42.4 what no longer looks like a major uncertainty

Several earlier uncertainties now look substantially reduced.

- `UiFlat` is probably not branch-source grouped anymore; facet orientation looks right.
- `UiGeometryInput` no longer looks like a mixed lower language.
- `UiGeometry` no longer looks like a mixed participation/rect record.
- render direct-to-machine-ir no longer looks honest.
- query direct-to-machine-ir no longer looks honest either.

This is a meaningful reduction in architectural risk.

### 42.5 are we ready to rewrite the live ASDL?

Current answer:

> yes, probably with one explicit caution.

The caution is:

- the custom-family story is still the least settled part of the design

But the overall phase architecture now looks coherent enough that waiting for perfect certainty is
unlikely to buy much more.

So current judgment:

> the sketch now appears stable enough to start rewriting the live `ui2` ASDL/schema around it,
> while keeping custom-family handling explicitly provisional and easy to revise.

### 42.6 recommended next step

The next highest-value move is no longer another broad red-team pass.
The next move should be:

1. rewrite the live `ui2` ASDL/schema around this architecture
2. keep custom-family portions visibly provisional
3. then resume implementation in pipeline order from the bottom of each branch upward

Current recommendation:

> begin the live ASDL/schema rewrite now.
