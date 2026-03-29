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
