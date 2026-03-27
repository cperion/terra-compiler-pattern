# The Terra Compiler Pattern — Final Form

## Five primitives. No framework. The architecture IS the composition.

This document describes the terminal form of the Terra Compiler Pattern: the realization that when functional programming is not an add-on but the foundation, the entire pattern collapses to five primitives composed together. No DSL. No parser. No language extension. No framework. Just functions composing functions, producing native code.

The pattern rests on Terra (a low-level language embedded in Lua, JIT-compiled via LLVM) and four Lua-level tools: ASDL for domain types, `terralib.memoize` for caching, LuaFun for functional transforms, and Unit for compile products. Together they produce multi-stage incremental compilers that eliminate state management, memory management, dispatch, configuration, and infrastructure — not by solving these problems, but by making them structurally impossible.

---

## 1. The Five Primitives

### 1.1 ASDL unique — structural identity

```lua
local asdl = require 'asdl'
local T = asdl.NewContext()
T:Define [[
    Node = (number id, string kind, number* params) unique
]]

-- "unique" means: same arguments → same Lua object
local a = T.Node(1, "sine", {440})
local b = T.Node(1, "sine", {440})
assert(a == b)       -- true: same Lua object
assert(rawequal(a,b)) -- true: identity, not just equality
```

ASDL `unique` gives you structural identity for free. Two nodes with the same fields are the same Lua object. Not equal — identical. This is the foundation of incremental compilation: if the input didn't change, the cached output is correct, because "didn't change" means "is the same object."

Without `unique`, you need a diffing system. With `unique`, identity IS the diff.

### 1.2 terralib.memoize — identity-based caching

```lua
local compile_node = terralib.memoize(function(node, sample_rate)
    -- ... expensive compilation ...
    return Unit.leaf(...)
end)

-- First call: runs the function, caches result
local r1 = compile_node(node_a, 44100)

-- Second call with same node: cache hit, instant
local r2 = compile_node(node_a, 44100)
assert(r1 == r2)  -- same object returned
```

`terralib.memoize` caches by Lua equality on the argument list. Combined with ASDL `unique`, this gives structural caching: same domain configuration → same compiled output → returned instantly.

The memoize key IS the purity proof. If the function depends only on its explicit arguments, and the arguments haven't changed, the output hasn't changed. No invalidation tracking. No dirty flags. No observer subscriptions. No dependency graphs. Just: same arguments? Same result.

**Hard rule**: every semantic dependency must be in the explicit argument list. If the function closes over mutable state not in the arguments, the cache can return stale results. ASDL nodes are immutable. LuaFun transforms are pure. The pattern prevents this structurally.

### 1.3 LuaFun — functional transforms

```lua
local fun = require 'fun'

local nodes = fun.iter(track.devices)
    :filter(function(d) return d.enabled end)
    :map(compile_node)
    :totable()
```

LuaFun provides lazy, zero-allocation, JIT-friendly iterators: `map`, `filter`, `reduce`, `zip`, `chain`, `flatmap`, `enumerate`, `partition`, `all`, `any`, `head`, `take`, `drop`. Built for LuaJIT. The trace compiler sees through iterator chains and compiles them to the same machine code as hand-written loops.

LuaFun's role in the pattern is NOT just convenience. It is the mechanism that makes purity the path of least resistance. The API has no mutation verbs. There is no `set`, no `push`, no `remove`. You transform, filter, fold. The output is always a new value. The input is never modified.

When every transform is a LuaFun chain feeding into an ASDL constructor, impurity requires EFFORT. You'd have to break out of the functional vocabulary to mutate something. The tooling discourages it. The caching punishes it. The code review catches it. Purity is the default, not the aspiration.

### 1.4 Unit — the compile product

```lua
local Unit = {}
local EMPTY = tuple()

function Unit.new(fn, state_t)
    assert(terralib.isfunction(fn), "Unit.fn must be a TerraFunc")
    assert(terralib.types.istype(state_t), "Unit.state_t must be a TerraType")
    if state_t ~= EMPTY then
        local params = fn:gettype().parameters
        local found = false
        for _, p in ipairs(params) do
            if p == &state_t then found = true; break end
        end
        assert(found, "Unit.fn must take &state_t — the function must own its ABI")
    end
    fn:compile()  -- force LLVM NOW, not in the hot path
    return { fn = fn, state_t = state_t }
end
```

A Unit is `{ fn, state_t }` — a compiled Terra function paired with the exact state type it operates on. They are born together, cached together, and retired together. The function only makes sense with this state type. The state type only makes sense for this function. They are one artifact with two parts.

`Unit.new` enforces three things:
1. `fn` is a real Terra function
2. If the state type is non-empty, `fn` takes `&state_t` as a parameter (ABI ownership)
3. `fn:compile()` is called immediately — LLVM runs here, at construction time, never in the audio/render hot path

These three checks eliminate three categories of bugs:
- Passing the wrong state pointer to a function (ABI mismatch)
- JIT-compiling during audio rendering (latency spike)
- Using a Lua function where a Terra function was expected (type confusion)

### 1.5 Composition wrappers — the boundary vocabulary

```lua
local function transition(fn)
    return terralib.memoize(fn)
end

local function terminal(fn)
    return terralib.memoize(fn)
    -- Unit.new already validates ABI + calls fn:compile()
end

local function with_fallback(fn, neutral)
    return function(...)
        local ok, result = pcall(fn, ...)
        if ok then return result end
        return neutral
    end
end

local function with_errors(fn)
    return function(...)
        local errs = B.errors()
        local result = fn(errs, ...)
        return result, errs:get()
    end
end
```

Four higher-order functions. ~20 lines. These ARE the boundary kinds from the spec:
- `transition` = memoized ASDL-to-ASDL transform
- `terminal` = memoized ASDL-to-Unit compilation
- `with_fallback` = pcall + neutral substitution on failure
- `with_errors` = per-item error collection

They compose:

```lua
local lower_track = transition(
    with_errors(function(errs, track)
        return T.Authored.Track(
            track.id,
            T.Authored.Graph(errs:each(track.devices, lower_device, "id")),
            track.volume_db, track.pan
        )
    end)
)
```

`lower_track` is memoized. It collects per-item errors. It returns a typed ASDL node. It handles failure gracefully. All from composition. No registration. No declaration. No framework. Just functions wrapping functions.


---

## 2. The Unit System

The Unit is the atomic compile product of the pattern. Every compilation — at every level of the hierarchy — produces a Unit. A leaf DSP node produces a Unit. A chain of effects produces a Unit. A track produces a Unit. A session produces a Unit. The entire renderer IS a Unit.

### 2.1 Unit.leaf — own state, own function

For a node that owns its own persistent state:

```lua
function Unit.leaf(state_t, params, body)
    state_t = state_t or EMPTY
    if state_t == EMPTY then
        local fn = terra([params]) [body(nil, params)] end
        return Unit.new(fn, EMPTY)
    end
    local s = symbol(&state_t, "state")
    local fn = terra([params], [s]) [body(s, params)] end
    return Unit.new(fn, state_t)
end
```

Usage:

```lua
-- A biquad filter: 4 floats of state, baked coefficients
local compile_biquad = terminal(function(node, sr)
    local b0, b1, b2, a1, a2 = compute_coeffs(node.freq, node.q, sr)
    return Unit.leaf(
        struct { x1: float; x2: float; y1: float; y2: float },
        terralib.newlist{ symbol(&float, "buf"), symbol(int32, "n") },
        function(state, params)
            local buf, n = params[1], params[2]
            return quote
                for i = 0, @n - 1 do
                    var x = buf[i]
                    var y = [float](b0)*x + [float](b1)*state.x1
                          + [float](b2)*state.x2
                          - [float](a1)*state.y1 - [float](a2)*state.y2
                    state.x2 = state.x1; state.x1 = x
                    state.y2 = state.y1; state.y1 = y
                    buf[i] = y
                end
            end
        end
    )
end)

-- A gain: no state, baked coefficient
local compile_gain = terminal(function(node)
    local g = math.pow(10, node.db / 20)
    return Unit.leaf(nil,
        terralib.newlist{ symbol(&float, "buf"), symbol(int32, "n") },
        function(state, params)
            local buf, n = params[1], params[2]
            return quote
                for i = 0, @n - 1 do buf[i] = buf[i] * [float](g) end
            end
        end
    )
end)
```

The biquad's state is 4 floats. The gain has no state. Both produce Units. The parent doesn't care — it composes them identically.

The coefficients `b0, b1, b2, a1, a2` are Lua numbers computed at compilation time. They appear in the Terra quote as constants — `[float](b0)` splices the Lua number into the generated code as a float literal. At runtime, there is no coefficient table. No parameter struct. No config lookup. Just constants in the instruction stream, as if a C programmer had written `y = 0.0675f * x + ...`.

### 2.2 Unit.compose — aggregate children's state

For a node that owns the combined state of its children:

```lua
function Unit.compose(children, params, body)
    -- Build the composed state struct
    local S = terralib.types.newstruct("S")
    local kids = {}
    local n = 0
    for i, c in ipairs(children) do
        kids[i] = { fn = c.fn, state_t = c.state_t }
        if c.state_t ~= EMPTY then
            n = n + 1
            local f = "s" .. n
            S.entries:insert({ field = f, type = c.state_t })
            kids[i].field = f
        end
    end
    if n == 0 then S = EMPTY end

    -- Build state pointers for each child
    local s = S ~= EMPTY and symbol(&S, "state") or nil
    for _, k in ipairs(kids) do
        if k.field and s then
            local f = k.field
            k.state_expr = `&(@[s]).[f]
        end
        -- The call helper: dispatches with correct state pointer
        k.call = function(...)
            local a = terralib.newlist{...}
            if k.state_expr then
                return quote [k.fn]([a], [k.state_expr]) end
            else
                return quote [k.fn]([a]) end
            end
        end
    end

    -- Build the composed function
    if s then
        return Unit.new(
            terra([params], [s]) [body(s, kids, params)] end, S)
    else
        return Unit.new(
            terra([params]) [body(nil, kids, params)] end, EMPTY)
    end
end
```

Usage:

```lua
-- A serial chain: process each effect in order
local compile_chain = terminal(function(nodes, sr)
    local units = fun.iter(nodes)
        :map(function(node) return compile_node(node, sr) end)
        :totable()

    return Unit.compose(units,
        terralib.newlist{ symbol(&float, "buf"), symbol(int32, "n") },
        function(state, kids, params)
            local buf, n = params[1], params[2]
            return quote
                escape
                    for _, kid in ipairs(kids) do
                        emit(kid.call(buf, n))
                    end
                end
            end
        end
    )
end)
```

What `Unit.compose` does:
1. Collects each child's `state_t`
2. Builds a struct with one field per non-empty child state
3. For each child, computes a pointer expression `&state.s_N` that points into the parent struct at the child's state offset
4. Provides a `.call(...)` helper that appends the correct state pointer when calling the child function
5. Wraps everything in a new `Unit.new` — which validates ABI and forces `:compile()`

The child functions were already compiled (their `Unit.new` called `:compile()`). The parent function is small — it just calls pre-compiled children in sequence. LLVM compiles it in microseconds.

State ownership is structural:
- Each child's state lives AS A FIELD in the parent struct
- The parent OWNS the memory (one allocation for the whole tree)
- The child ACCESSES its state via a pointer the parent passes
- Nobody else can access the child's state — the pointer is local to the call
- There is no allocation, no free, no reference counting, no garbage collection in the audio path

### 2.3 Unit.silent — the neutral

```lua
function Unit.silent()
    return Unit.new(terra() end, EMPTY)
end
```

A no-op function with empty state. The identity element for Unit composition. Used as the fallback when a compilation fails — the pipeline continues, the failed node is silence, the user sees the error on the right element, everything else plays.

### 2.4 The state hierarchy

For a session with two tracks, each with three effects:

```
Session Unit
├── state_t = struct {
│       s1: TrackState,      ← Track 1
│       s2: TrackState,      ← Track 2
│   }
│
├── Track 1 Unit
│   ├── state_t = struct {
│   │       s1: BiquadState, ← Effect 1 (biquad)
│   │       s2: {},          ← Effect 2 (gain, stateless)
│   │       s3: ChorusState, ← Effect 3 (chorus)
│   │   }
│   └── fn calls: effect1.fn(buf, n, &state.s1.s1)
│                  effect2.fn(buf, n)
│                  effect3.fn(buf, n, &state.s1.s3)
│
├── Track 2 Unit
│   ├── state_t = struct {
│   │       s1: OscState,    ← Effect 1 (sine osc)
│   │       s2: {},          ← Effect 2 (gain, stateless)
│   │   }
│   └── fn calls: effect1.fn(buf, n, &state.s2.s1)
│                  effect2.fn(buf, n)
│
└── fn: terra(L, R, n, state)
        -- zeros output
        -- calls Track 1 fn with &state.s1
        -- calls Track 2 fn with &state.s2
    end
```

One struct. One allocation. Contains all state for all tracks, all effects, all oscillator phases, all filter histories. Allocated once with `terralib.new(SessionState)`. Freed when the session is recompiled and the old state is no longer referenced (Lua GC collects it).

During playback: zero allocations. Zero frees. Zero memory management. The audio callback receives a pointer to this struct and runs arithmetic. That's all it can do.


---

## 3. Multi-Stage Pipeline

The pipeline is function composition. No declaration. No framework. Just `f(g(h(x)))`.

### 3.1 Stages as functions

```lua
-- Stage 1: Editor → Authored (lower)
-- Flatten user-facing containers into semantic graphs.
local lower_device = transition(function(device) ... end)
local lower_track  = transition(function(track) ... end)
local lower        = transition(function(project) ... end)

-- Stage 2: Authored → Scheduled (schedule)
-- Assign buffer slots, flatten to linear job list.
local schedule_graph = transition(function(graph) ... end)
local schedule       = transition(function(authored) ... end)

-- Stage 3: Scheduled → Unit (compile)
-- Each job becomes a leaf Unit, session becomes composed Unit.
local compile_job     = terminal(function(job, sr) ... end)
local compile_session = terminal(function(scheduled) ... end)

-- The pipeline:
local function build(project)
    return compile_session(schedule(lower(project)))
end
```

Three stages. Three function calls. Each stage is a family of memoized functions that transform ASDL nodes into ASDL nodes (transitions) or ASDL nodes into Units (terminals). The pipeline IS the call chain. The order IS the composition order. There is nothing else to declare.

### 3.2 Incremental compilation via memoize

When the user turns a knob — say, changes a filter's cutoff from 2000 Hz to 2500 Hz — only the changed path recompiles:

```lua
-- Original session
local p1 = T.Editor.Project("Song", {
    T.Editor.Track(1, "Lead", {
        T.Editor.Device(1, "sine", {440}),
        T.Editor.Device(2, "biquad", {2000, 0.7}),  -- ← this changes
        T.Editor.Device(3, "gain", {-6}),
    }, 0, 0, false),
    T.Editor.Track(2, "Bass", {
        T.Editor.Device(4, "sine", {110}),
        T.Editor.Device(5, "gain", {-3}),
    }, 0, 0, false),
}, 44100)

local r1 = build(p1)

-- User changes biquad cutoff from 2000 to 2500
local p2 = T.Editor.Project("Song", {
    T.Editor.Track(1, "Lead", {
        T.Editor.Device(1, "sine", {440}),
        T.Editor.Device(2, "biquad", {2500, 0.7}),  -- ← changed
        T.Editor.Device(3, "gain", {-6}),
    }, 0, 0, false),
    T.Editor.Track(2, "Bass", {
        T.Editor.Device(4, "sine", {110}),
        T.Editor.Device(5, "gain", {-3}),
    }, 0, 0, false),
}, 44100)

local r2 = build(p2)
```

What happens inside `build(p2)`:

```
lower(p2):
    lower_track(Track 2: Bass)
        → Bass track in p2 is ASDL unique with same fields as p1
        → p2.Track2 == p1.Track2 (identity!)
        → CACHE HIT. Zero work. Returns same Authored.Track object.

    lower_track(Track 1: Lead)
        → Lead track has different biquad device
        → p2.Track1 ~= p1.Track1
        → CACHE MISS. Must lower.
            lower_device(Device 1: sine 440)     → CACHE HIT
            lower_device(Device 2: biquad 2500)  → MISS (new params)
            lower_device(Device 3: gain -6)      → CACHE HIT
        → Constructs new Authored.Track for Lead

    lower(p2) itself:
        → Track 2 result is cached (same object)
        → Track 1 result is new
        → New Authored.Project

schedule(new_authored):
    schedule_graph(Track 2 graph)
        → Track 2 graph is the SAME object (returned from lower's cache)
        → CACHE HIT. Zero work.

    schedule_graph(Track 1 graph)
        → Track 1 graph is new → MISS
        → But scheduling is cheap (assigns bus IDs)

compile_session(new_scheduled):
    compile_job(sine 440)    → CACHE HIT (same ASDL node)
    compile_job(biquad 2500) → MISS → LLVM compiles new biquad (~1ms)
    compile_job(gain -6)     → CACHE HIT
    compile_job(sine 110)    → CACHE HIT
    compile_job(gain -3)     → CACHE HIT

    Unit.compose(...)
        → New shell function (calls 5 child functions)
        → Shell is tiny: 5 call instructions
        → LLVM compiles in microseconds
```

The total work for one knob turn:

```
Cache hits (instant):           9 out of 12 function calls
LuaJIT work (microseconds):     new ASDL nodes, new LuaFun chains
LLVM work (milliseconds):       one biquad function (~1ms)
                                one shell function (~0.1ms)
Pointer swap:                   instant

Total wall time:                ~1.5ms
```

Everything unchanged was free. Not "fast." Free. The memoize cache returned the identical Lua object — no work at all. The only LLVM invocation was for the one changed biquad. Everything else was a pointer comparison returning a cached result.

### 3.3 How identity flows through stages

This is the critical mechanism. Each stage's output is an ASDL `unique` node. When that node is passed to the next stage, `terralib.memoize` checks identity. If the node is the same object that was passed last time, the next stage returns its cached result instantly.

```
Editor.Track(1, "Lead", {...})     unique → Lua object A
    ↓ lower_track
Authored.Track(1, graph_a, ...)    unique → Lua object B
    ↓ schedule
Scheduled.Job(1, "sine", {440})    unique → Lua object C
    ↓ compile_job
Unit { fn_sine, OscState }         cached as memoize[C] → result D

-- Next frame, nothing changed:
Editor.Track(1, "Lead", {...})     unique → SAME Lua object A
    ↓ lower_track
    memoize[A] → HIT → returns SAME Lua object B
    ↓ schedule
    memoize[B] → HIT → returns SAME Lua object C
    ↓ compile_job
    memoize[C] → HIT → returns SAME result D

-- Entire pipeline was free. Zero work at every stage.
```

Identity flows through the pipeline like water through pipes. Each stage preserves identity for unchanged subtrees. The next stage sees identity and skips. This is not an optimization bolted on — it is the fundamental mechanism. Remove `unique` and the pipeline still works, but recompiles everything every time. Add `unique` and incremental compilation emerges from identity comparison.

### 3.4 Adding more stages

Need a classification pass between scheduling and compilation? Add a function:

```lua
local classify = transition(function(scheduled)
    return T.Classified.Project(
        scheduled.sample_rate,
        fun.iter(scheduled.jobs)
            :map(classify_job)
            :totable()
    )
end)

-- Updated pipeline:
local function build(project)
    return compile_session(classify(schedule(lower(project))))
end
```

One new function. One more call in the chain. No framework to update. No pipeline declaration to modify. No configuration to change. The pipeline grew by one stage because you composed one more function.

Need a View projection for the UI? It's not a pipeline stage — it's a separate function:

```lua
local project_to_view = transition(function(project)
    return V.Root(
        fun.iter(project.tracks)
            :map(track_to_view)
            :totable()
    )
end)

-- UI path:
local view = project_to_view(editor_project)

-- Audio path:
local unit = build(editor_project)

-- Both paths start from the same ASDL node.
-- Both are memoized independently.
-- Changing a track recompiles only the affected path in each.
```

Two pipelines from the same source. No framework coordination. Each is just functions calling memoized functions. The ASDL identity ensures shared subtrees get cache hits in both pipelines.


---

## 4. Hot Swap

Three Terra built-ins. No infrastructure.

```lua
-- Two globals: the function pointer and the state pointer
local render_ptr = global({&float, &float, int32, &uint8} -> {})
local state_ptr  = global(&uint8)

-- The audio callback. Compiled ONCE. Never changes.
-- Registered with JACK/CoreAudio as a plain C function pointer.
terra audio_callback(L: &float, R: &float, n: int32)
    render_ptr(L, R, n, state_ptr)
end

-- Register with the audio driver once at startup
jack_set_process_callback(audio_callback:getpointer())
```

On edit:

```lua
local result = build(new_project)
state_ptr:set(terralib.cast(&uint8, terralib.new(result.state_t)))
render_ptr:set(result.fn:getpointer())
-- Done. Next audio callback calls the new function.
```

`build()` runs the full pipeline (mostly cache hits). `terralib.new(result.state_t)` allocates one struct containing all state for the entire session. `result.fn:getpointer()` returns a C function pointer to the already-compiled native code. The two `:set()` calls swap the pointers. The next audio callback reads the new pointers and calls the new function with the new state.

What we didn't write:

```
No message queue between edit thread and audio thread
No lock, mutex, or semaphore
No double-buffering system
No "pending swap" state machine
No compilation scheduler
No JIT trigger management
No thread-safe state transition protocol
```

The audio callback is a static Terra function. It reads two globals and calls through them. The edit code writes two globals. A pointer-width write is atomic on all architectures Terra targets. The swap is instant.

The old function and old state remain valid — they're in the memoize cache (function) and in Lua's GC heap (state). If something still references the old state, it stays alive. When nothing references it, Lua's GC collects it. No manual lifecycle management.

Undo is a cache hit. The user reverts to the previous project state. `build(old_project)` returns the previously cached Unit. Swap the pointers. The old renderer is back instantly, with the correct state type, because the memoize cache kept it alive.

---

## 5. Allocation and State

### 5.1 The allocation model

```
Startup:
    terralib.new(SessionState_v1)          ALLOC #1

Playing... (zero allocs, zero frees, forever)

User edits (turns a knob):
    terralib.new(SessionState_v2)          ALLOC #2
    state_ptr:set(v2)
    Lua GC eventually collects v1          FREE #1

Playing... (zero allocs, zero frees, forever)

User edits again:
    terralib.new(SessionState_v3)          ALLOC #3
    state_ptr:set(v3)
    Lua GC eventually collects v2          FREE #2

Playing... (zero allocs, zero frees, forever)

User hits undo:
    memoize cache hit → SessionState_v2 still alive
    state_ptr:set(v2)                      ZERO ALLOC
    Lua GC eventually collects v3          FREE #3

3-hour session, 500 edits:
    Total allocations:     ~500  (one per edit, edit thread)
    Total frees:           ~500  (Lua GC, asynchronous)
    Allocations per audio buffer: 0
    Frees per audio buffer:       0
    Allocations in the hot path:  0
    Frees in the hot path:        0
```

### 5.2 Why state management doesn't exist

Traditional architectures have state management because code and state are separate things with independent lifetimes. The EQ object has a state block. The compressor has a state block. The track has a buffer pool. Each is allocated separately, owned separately, freed separately. Each can be in an inconsistent state relative to the others. Each needs lifetime tracking.

In this pattern, state is COMPILED, not managed. `Unit.compose` generates a struct. The struct contains all child state as fields. The parent owns the memory. The children access their state via pointers the parent passes. Ownership, lifetime, and access paths are structural properties of the type — not runtime decisions.

```
Traditional:
    Code and state are separate things.
    Code runs. State changes. Someone must reconcile them.
    That reconciliation IS "state management."

This pattern:
    Code and state are ONE thing: { fn, state_t }.
    The function was compiled FOR this state type.
    The state type was generated BY this compilation.
    They are born together. Cached together. Retired together.
    There is nothing to reconcile.
```

### 5.3 Why memory management doesn't exist

Memory management exists because objects have independent lifetimes. Object A references Object B. Who frees B? What if A is freed first? What if C also references B? Reference counting? Garbage collection? Ownership rules?

In this pattern, there is ONE object: the session state struct. It is allocated once with `terralib.new`. It is freed when Lua's GC collects it (when nothing references it). There are no references between objects — the struct is flat. There is no graph of ownership — the struct is a value. There is no lifetime tracking — the struct lives until it's replaced.

```
Where is the state allocated?   → terralib.new(SessionState) — ONE
When is it freed?               → when the next edit replaces it
Who owns it?                    → the session — it's one struct
Can it dangle?                  → no — old pair stays in cache
Can it leak?                    → no — each edit replaces previous
Can it race?                    → no — audio reads global, edit writes global
How many allocations per buffer? → zero
How many allocations per second? → zero during playback
```

---

## 6. What This Eliminates

The five primitives, composed functionally, eliminate entire categories of software infrastructure. Not by solving them. By making them structurally impossible.

### 6.1 Things that don't exist

```
State management          → state is compiled as { fn, state_t }
                            no separate lifecycle, no tracking

Memory management         → one allocation per edit, zero in hot path
                            no pools, no arenas, no ref counting

Dispatch / vtables        → all decisions resolved at compile time
                            the compiled function is monomorphic

Configuration systems     → configuration is ASDL nodes
                            compiled away to constants

Plugin interfaces         → ASDL types ARE the interface
                            no ABI to maintain, no versioning

Observer / event systems  → recompile from ASDL on change
                            no subscriptions, no invalidation cascades

Dependency injection      → dependencies are function arguments
                            memoize keys on them

Loading systems           → compilation state IS loading state
                            each node either has a Unit or doesn't

Serialization formats     → early-phase ASDL IS the persistence format
                            no separate schema to maintain

Thread synchronization    → pointer swap is atomic
                            no locks, no queues, no double-buffering

Build systems             → terralib.memoize IS the build cache
                            same inputs → same outputs

Mocking / test doubles    → ASDL constructors build real objects
                            the compiler compiles them for real
                            tests run real machine code

Error routing             → errors are values with semantic refs
                            they flow through the same pipeline
                            no error bus, no event system

Progress tracking         → the function list IS the inventory
                            status is whether an impl exists

Incremental updates       → memoize + unique = structural caching
                            no dirty flags, no change tracking

Code generation           → closure composition, not text generation
                            LuaJIT traces through closures
```

### 6.2 Why they don't exist

Each eliminated system exists in traditional architectures to reconcile two things that are independent but shouldn't be:

```
State management:     reconciles code and data
Memory management:    reconciles allocation and lifetime
Dispatch:             reconciles type and behavior
Configuration:        reconciles design-time and runtime decisions
Plugin interfaces:    reconciles separate compilation units
Observers:            reconciles source and dependent
Loading:              reconciles declaration and availability
Serialization:        reconciles in-memory and on-disk formats
Synchronization:      reconciles concurrent access paths
```

The pattern eliminates independence. Code and data are one Unit. Allocation and lifetime are one edit. Type and behavior are one compilation. Configuration and runtime are one value (baked constants). Declaration and availability are one function (exists or doesn't). In-memory and on-disk are one ASDL type. The reconciliation systems have nothing to reconcile.

### 6.3 The ctx smell

Every `ctx`, `void*`, or indirection in compiled output is a confession that the compiler didn't finish its job. Something was known at compile time but leaked to runtime as a pointer, a table, a dispatch.

```
void pointer:     "I don't know what this points to"
                  → the COMPILER knew. Why doesn't the code?

ctx parameter:    "I need runtime context to do my job"
                  → the compiler HAD the context. Why didn't it
                    compile it away?

virtual dispatch: "I don't know what function to call"
                  → the compiler knew the type. Why is there
                    a table lookup at runtime?

config struct:    "I read my settings at runtime"
                  → the settings were known at edit time.
                    They should be constants in the instruction stream.

hash table:       "I look up a value by name at runtime"
                  → the name was known at compile time.
                    It should be a direct field access.
```

The pattern bakes everything it knows into the generated code. Filter coefficients become float literals. Node connections become direct function calls. Buffer sizes become loop bounds. Gain values become multiply constants. At runtime, there is no indirection. No lookup. No dispatch. Just arithmetic on arrays.

LLVM optimizes BETTER than C because it sees specialized code with baked constants, not general code with runtime parameters. The compiler produces code that is MORE optimized than hand-written C, because hand-written C must handle all configurations, while the generated code handles only THIS configuration.


---

## 7. The Two Levels

The architecture has exactly two levels with different contracts.

```
COMPILATION LEVEL (Lua + LuaJIT):
    lower(project)           → Authored.Project
    schedule(authored)        → Scheduled.Project
    compile_session(sched)    → Unit { fn, state_t }

    Pure. Same input → same output.
    Enforced by terralib.memoize.
    No side effects. No hidden state.
    ASDL in, ASDL or Unit out. Always.

EXECUTION LEVEL (Terra + LLVM):
    fn(out_L, out_R, n, state)

    Closed. Mutates, but only explicit parameters.
    Reads only from its arguments.
    Writes only to its arguments.
    Touches no globals. Allocates nothing. Frees nothing.
    Calls no external systems. Has no hidden inputs.
    Its behavior is ENTIRELY determined by its arguments.
```

Every function you REASON about is pure (compilation level). Every function you DON'T reason about is closed (execution level). They never mix.

Purity is where the thinking is — caching, incremental recompilation, hot-swap, state isolation, correctness. Mutation is where the arithmetic is — sample processing, buffer filling, filter ticking. The pure level generates the impure level. The impure level runs the math. The pure level never runs math. The impure level never makes decisions.

```
All REASONING happens at the pure level:
    Caching         → memoize checks equality on pure inputs
    Incremental     → unchanged inputs return cached outputs
    Hot-swap        → swap one pure product for another
    State isolation → each pure compilation produces its own state type
    Correctness     → same config always produces the same function

The impure part — sample processing — is BELOW the reasoning level.
The pattern generates it and moves on. The generated code mutates,
but inside a box the pure level constructed. The box walls are state_t.
Nobody reaches in. Nobody reaches out.
```

### 7.1 The five enforcement layers

No single layer is airtight. Lua is too dynamic. But the layers compound until impurity requires deliberate effort:

```
Layer 1: ASDL constructors
    → produce NEW immutable nodes
    → no setter API exists
    → to "change" a node, you construct a new one
    → mutation of domain objects is structurally unavailable

Layer 2: LuaFun iterators
    → map, filter, reduce — no mutation verbs
    → the natural path IS the pure path
    → impurity requires breaking out of the API

Layer 3: terralib.memoize
    → if your function is impure, the cache returns wrong results
    → impurity is a VISIBLE BUG, not a silent one
    → the memoize cache is the purity enforcer

Layer 4: Unit.new
    → validates ABI ownership
    → calls fn:compile() immediately
    → the compile product is sealed at creation

Layer 5: Composition wrappers (transition, terminal, with_fallback)
    → wrap with pcall + neutral
    → wrap with type check
    → wrap with memoize
    → the developer's function is inside three layers of validation
```

To write impure code in this stack, you would have to:
1. Bypass ASDL constructors (use raw table mutation) — looks wrong
2. Ignore the memoize cache bug — the bug is visible immediately
3. Use raw table assignment instead of LuaFun — sticks out visually
4. Get it past code review — it looks wrong in context

The economics of effort favor correctness. Every deviation costs more than compliance.

---

## 8. Why FP Eliminates the Framework

This is the key insight that led to the final form.

### 8.1 What boundary.t was compensating for

`boundary.t` was a 2000-line Terra language extension with a parser, validator, closure composer, pipeline deriver, and CLI. It existed to enforce:

```
memoized boundaries         → transition() already does this
typed arguments             → ASDL types already does this
return type checking        → ASDL constructors already do this
pipeline consistency        → function composition already does this
exhaustive dispatch         → B.match already does this
error collection            → with_errors already does this
fallback on failure         → with_fallback already does this
Unit ABI validation         → Unit.new already does this
auto fn:compile()           → Unit.new already does this
```

Every row in the enforcement matrix was already handled by the FP primitives. The DSL was duplicating enforcement that composition already provided. It was governance for an imperative world applied to a functional one.

### 8.2 The framework dissolved because the pattern IS the framework

In an imperative codebase:
- A developer might forget to memoize → boundary.t wraps with memoize
- A developer might pass a table arg → boundary.t rejects at parse time
- A developer might return the wrong type → boundary.t checks at runtime
- A developer might skip error handling → boundary.t wraps with pcall

In a functional codebase:
- `transition()` IS memoize — you can't use it without memoize
- ASDL nodes ARE typed — there are no table args to pass
- ASDL constructors validate fields — you can't return the wrong shape
- `with_errors()` IS error handling — it composes naturally

The framework was a POLICING LAYER. When the code is functional, there's nothing to police. The pattern self-enforces through composition.

### 8.3 What remains

The five primitives: ASDL, memoize, LuaFun, Unit, composition wrappers. Plus two optional libraries:

```
B.match     — exhaustive dispatch (runtime check, ~15 lines)
B.errors    — error collection with refs (~40 lines)
B.with      — functional update (~10 lines)
```

Total: ~120 lines of supporting code. Everything else is the developer's domain logic composed with these primitives.

The DSL features that were genuinely useful — not enforcement, but TOOLING — can exist as standalone utilities:

```
Progress tracking:  scan function list, count impls
Test generation:    for each memoized fn, test cache behavior
Documentation:      walk ASDL types, emit markdown
Scaffolding:        generate function stubs from ASDL types
Prompt generation:  walk type graph, emit context for AI
```

These don't need a parser. They need access to the ASDL context and the function registry. Both are plain Lua objects. A 200-line CLI module can provide all of this without a language extension.

### 8.4 The framework/language/library distinction dissolves

```
Framework:   you register with it, it calls you back
Library:     you call it, it returns
Language:    you express in it, it enforces rules

The five primitives are none of these. They are COMPOSITION TOOLS.
You compose them. They compose each other. There is no registration,
no callback, no enforcement. Just functions returning functions
returning Units.

The "framework" is the DISCIPLINE of composing correctly.
The "language" is the VOCABULARY of transition/terminal/with_fallback.
The "library" is the TOOLBOX of LuaFun + B.match + B.errors.

They're the same thing. There is no distinction to make.
The architecture IS the composition.
```

---

## 9. The Development Flow

### 9.1 Start with ASDL

Define your domain types. This is the real work. The types encode every domain decision.

```lua
local T = asdl.NewContext()
T:Extern("TerraType", terralib.types.istype)
T:Extern("TerraFunc", terralib.isfunction)
T:Define [[
    module Editor {
        Project = (...) unique
        Track = (...) unique
        Device = NativeDevice(...) | LayerDevice(...) | ... unique
    }
    module Authored { ... }
    module Scheduled { ... }
]]
```

Getting the types right is the hard part. Which fields belong on which type? Which phase resolves which decision? Where do coupling points land? These are domain expertise questions. The pattern doesn't answer them. Your understanding of audio, layout, text, MIDI answers them.

### 9.2 Write leaf compilers

One `terminal` function per node kind. Each takes an ASDL node and returns a Unit.

```lua
local compile_sine = terminal(function(node, sr)
    return Unit.leaf(struct { phase: float }, params, function(state, p)
        -- ... sine wave with baked frequency ...
    end)
end)

local compile_biquad = terminal(function(node, sr)
    return Unit.leaf(struct { x1: float; x2: float; y1: float; y2: float },
        params, function(state, p)
        -- ... biquad with baked coefficients ...
    end)
end)
```

### 9.3 Write composition compilers

Each takes a list of children and produces a composed Unit.

```lua
local compile_chain = terminal(function(nodes, sr)
    local units = fun.iter(nodes):map(compile_node):totable()
    return Unit.compose(units, params, function(state, kids, p)
        return quote escape
            for _, kid in ipairs(kids) do emit(kid.call(buf, n)) end
        end end
    end)
end)
```

### 9.4 Write transition functions

Each transforms ASDL from one phase to the next.

```lua
local lower_track = transition(function(track)
    return T.Authored.Track(
        track.id,
        T.Authored.Graph(fun.iter(track.devices):map(lower_device):totable()),
        track.volume_db, track.pan
    )
end)
```

### 9.5 Compose the pipeline

```lua
local function build(project)
    return compile_session(schedule(lower(project)))
end
```

### 9.6 Connect to the audio driver

```lua
local render_ptr = global({&float, &float, int32, &uint8} -> {})
local state_ptr = global(&uint8)

terra audio_callback(L: &float, R: &float, n: int32)
    render_ptr(L, R, n, state_ptr)
end

jack_set_process_callback(audio_callback:getpointer())

-- On edit:
local r = build(new_project)
render_ptr:set(r.fn:getpointer())
state_ptr:set(terralib.cast(&uint8, terralib.new(r.state_t)))
```

### 9.7 Done

That's a working audio engine. Add more node types by writing more `terminal` functions. Add more phases by writing more `transition` functions. Add error handling by wrapping with `with_errors`. Add fallbacks by wrapping with `with_fallback`. Everything composes.

There is no initialization step. No configuration phase. No registration. No startup sequence. You define functions, compose them, and call the result. The pipeline exists because the functions call each other. The caching exists because `transition` and `terminal` wrap with memoize. The state management exists because Unit.compose embeds child state. The hot swap exists because Terra globals are pointers.


---

## 10. The Complete Framework

The entire framework in one file. ~80 lines.

```lua
-- unit.lua — the Terra Compiler Pattern, final form

local EMPTY = tuple()

local Unit = {}

function Unit.new(fn, state_t)
    state_t = state_t or EMPTY
    assert(terralib.isfunction(fn), "Unit.fn must be a TerraFunc")
    assert(terralib.types.istype(state_t), "Unit.state_t must be a TerraType")
    if state_t ~= EMPTY then
        local params = fn:gettype().parameters
        local found = false
        for _, p in ipairs(params) do
            if p == &state_t then found = true; break end
        end
        assert(found,
            "Unit.fn must take &state_t — the function must own its ABI")
    end
    fn:compile()
    return { fn = fn, state_t = state_t }
end

function Unit.silent()
    return Unit.new(terra() end, EMPTY)
end

function Unit.leaf(state_t, params, body)
    state_t = state_t or EMPTY
    if state_t == EMPTY then
        local fn = terra([params]) [body(nil, params)] end
        return Unit.new(fn, EMPTY)
    end
    local s = symbol(&state_t, "state")
    local fn = terra([params], [s]) [body(s, params)] end
    return Unit.new(fn, state_t)
end

function Unit.compose(children, params, body)
    local S = terralib.types.newstruct("S")
    local kids = {}
    local n = 0
    for i, c in ipairs(children) do
        kids[i] = { fn = c.fn, state_t = c.state_t }
        if c.state_t ~= EMPTY then
            n = n + 1
            local f = "s" .. n
            S.entries:insert({ field = f, type = c.state_t })
            kids[i].field = f
        end
    end
    if n == 0 then S = EMPTY end
    local s = S ~= EMPTY and symbol(&S, "state") or nil
    for _, k in ipairs(kids) do
        if k.field and s then
            local f = k.field
            k.state_expr = `&(@[s]).[f]
        end
        k.call = function(...)
            local a = terralib.newlist{...}
            if k.state_expr then
                return quote [k.fn]([a], [k.state_expr]) end
            else
                return quote [k.fn]([a]) end
            end
        end
    end
    if s then
        return Unit.new(
            terra([params], [s]) [body(s, kids, params)] end, S)
    else
        return Unit.new(
            terra([params]) [body(nil, kids, params)] end, EMPTY)
    end
end

-- Boundary wrappers

function Unit.transition(fn)
    return terralib.memoize(fn)
end

function Unit.terminal(fn)
    return terralib.memoize(fn)
end

function Unit.with_fallback(fn, neutral)
    return function(...)
        local ok, result = pcall(fn, ...)
        if ok then return result end
        return neutral
    end
end

function Unit.with_errors(fn)
    return function(...)
        local errs = Unit.errors()
        local result = fn(errs, ...)
        return result, errs:get()
    end
end

-- Error collector

function Unit.errors()
    local list = {}
    return {
        each = function(self, items, fn, ref_field)
            local fun = require 'fun'
            return fun.iter(items)
                :map(function(item)
                    local ok, result, child_errs = pcall(fn, item)
                    if ok then
                        if child_errs then
                            for _, e in ipairs(child_errs) do
                                list[#list+1] = e
                            end
                        end
                        return result
                    end
                    list[#list+1] = {
                        ref = item[ref_field], err = tostring(result)
                    }
                    return Unit.silent()
                end)
                :totable()
        end,
        call = function(self, target, fn)
            local ok, result, child_errs = pcall(fn, target)
            if ok then
                if child_errs then
                    for _, e in ipairs(child_errs) do
                        list[#list+1] = e
                    end
                end
                return result
            end
            list[#list+1] = {
                ref = target.id, err = tostring(result)
            }
            return Unit.silent()
        end,
        get = function(self) return #list > 0 and list or nil end,
    }
end

-- Functional update

function Unit.with(node, overrides)
    local class = getmetatable(node)
    local fields = class.__fields
    local args = {}
    for i, field in ipairs(fields) do
        if overrides[field.name] ~= nil then
            args[i] = overrides[field.name]
        else
            args[i] = node[field.name]
        end
    end
    return class(unpack(args))
end

-- Exhaustive match

function Unit.match(value, arms)
    local class = getmetatable(value)
    if class and class.__variants then
        for _, vname in ipairs(class.__variants) do
            if not arms[vname] then
                error(("match on %s missing variant '%s'"):format(
                    class.__name or "?", vname), 2)
            end
        end
    end
    local handler = arms[value.kind]
    if not handler then
        error(("unhandled variant '%s'"):format(value.kind), 2)
    end
    return handler(value)
end

return Unit
```

That's the entire framework. ~140 lines with the helper library included. Everything else is your domain code.


---


## 11. Performance Model

### 11.1 Two JIT compilers

The architecture has two JIT compilers working at two levels:

```
LuaJIT:     compiles the compilation layer
            transition/terminal functions, LuaFun chains,
            ASDL construction, memoize lookups
            → ~0.001-0.1ms per boundary call

LLVM:       compiles the execution layer
            the generated Terra functions (biquads, oscillators, gains)
            → ~1-5ms per leaf function, ~0.1ms per shell function
```

LuaJIT traces through LuaFun iterator chains and compiles them to tight native loops. There is no performance cost to the functional style. `fun.iter(nodes):map(f):totable()` compiles to the same machine code as a hand-written for loop.

LLVM sees specialized code with baked constants. It optimizes BETTER than C because C code must handle all configurations, while the generated code handles only THIS configuration. A biquad with coefficients `b0=0.0675, b1=0.135, ...` compiles to multiplies by float literals — the compiler can fold, reorder, and vectorize freely.

### 11.2 Time budget for one edit

```
User turns a knob
    ↓
ASDL tree update (construct new node)     ~0.001ms   LuaJIT
    ↓
LuaFun chain through transition()        ~0.01ms    LuaJIT
    ↓
memoize hits on unchanged subtrees        ~0.001ms   LuaJIT (per hit)
    ↓
memoize miss on changed leaf              ~0.001ms   LuaJIT
    ↓
Terminal: generate Terra quote            ~0.1ms     LuaJIT
    ↓
LLVM compiles one leaf function           ~1-3ms     LLVM ← the bottleneck
    ↓
LLVM compiles shell function              ~0.1ms     LLVM (tiny)
    ↓
Pointer swap                              ~0.000ms

Total:                                    ~1.5-3.5ms
```

99% of the wall time is LLVM on the one changed leaf. Everything else is LuaJIT at native speed. And LLVM only compiles one small function because memoize cached everything else.

### 11.3 Scaling

```
2 tracks, 6 nodes:       ~3ms per edit, ~48 bytes state
20 tracks, 60 nodes:     ~3ms per edit, ~480 bytes state
200 tracks, 600 nodes:   ~3ms per edit, ~4800 bytes state

Same time. Because memoize means LLVM only sees the ONE changed node.
The 200-track session compiles as fast as the 2-track session.
```

State size scales linearly with node count. Compilation time is constant per edit (one leaf recompile). Memory is one allocation for the entire state struct. The architecture is O(1) per edit, O(n) in memory, O(n) in initial cold compilation.


---


## 12. The Philosophical Core

### 12.1 The compiler IS the program

The DAW is not a program that runs a renderer. It is a COMPILER that produces a renderer. Every edit recompiles. The renderer is ephemeral output. The compiler is the permanent artifact.

```
Traditional DAW:
    The program starts. It loads plugins. It allocates buffers.
    It runs a loop. The loop dispatches to plugins. Plugins process.
    The program IS the loop.

This pattern:
    The compiler starts. It reads the ASDL. It generates a renderer.
    The renderer runs. The user edits. The compiler regenerates.
    The compiler IS the program. The renderer is its output.
```

### 12.2 We build translators, not interpreters

An interpreter re-asks questions every frame: "What type is this? What branch do I take? Where is this field?" The answers are always the same. The work is wasted.

A translator asks once, writes down the answer as code, and never asks again. The cost is paid once. The result runs forever — or until the input changes, at which point you translate again.

Layering translators is safe because each is a total function. ASDL in, ASDL out (or ASDL in, Unit out). Each layer narrows. Each layer consumes knowledge. The layers don't interact except through typed interfaces.

### 12.3 Quotes are the better pointers

Pointers live at runtime. They're subject to time — they can dangle, leak, race. They're addresses into mutable memory. Every pointer is a question: "is this still valid?"

Quotes live at compile time. They're consumed during compilation and cease to exist at runtime. They're code fragments, not addresses. They can't dangle because they don't exist after compilation. They can't leak because they're not allocated. They can't race because they're not shared.

The pattern replaces pointers with quotes wherever possible. Node connections are not pointer graphs at runtime — they're quote compositions at compile time. Parameter bindings are not pointer lookups — they're baked constants. State access is not pointer chasing — it's struct field offsets computed by Terra.

### 12.4 Configuration is a staging error

Every `ctx`, `void*`, config struct, or hash table lookup at runtime represents knowledge that was available at compile time but failed to be consumed. The compiler had the answer. It leaked to runtime as an indirection.

The pattern consumes ALL configuration at compile time:
- Filter frequencies → baked as float constants
- Node connections → baked as direct function calls
- Buffer sizes → baked as loop bounds
- Channel counts → baked as struct layouts
- Gain values → baked as multiply constants

At runtime there is no configuration. No settings. No parameters (in the infrastructure sense). Just arithmetic on arrays of floats. The "configuration" was consumed by the compiler. What remains is the output of that consumption: specialized native code.

### 12.5 Alloc and free are edit events

The traditional audio engine allocates and frees during playback: buffer checkouts, event queues, temporary storage, parameter smoothing state. Each allocation is a potential priority inversion. Each free is a potential GC pause.

In this pattern, alloc happens once per edit (one `terralib.new(SessionState)`). Free happens when the next edit replaces the old state (Lua GC collects it asynchronously). During playback: zero allocations. Zero frees. The audio thread doesn't know how to allocate. The compiled function operates on a pre-allocated state struct via a pointer. That's all it can do.

### 12.6 The architecture reduces to composition

No framework. No DSL. No registration. No configuration. No lifecycle. No event system. No dependency injection. No plugin interface. No build system. No test framework. No documentation system.

Just:
- ASDL types (domain model)
- LuaFun (functional transforms)
- memoize (caching)
- Unit (compile products)
- transition/terminal/with_fallback/with_errors (boundary wrappers)

These compose into a multi-stage incremental compiler with hot-swap, error handling, state management, memory management, and complete elimination of runtime dispatch.

~140 lines of framework. The rest is your domain.


---


## 13. Summary

```
THE TERRA COMPILER PATTERN — FINAL FORM

PRIMITIVES:
    ASDL unique         structural identity
    terralib.memoize    identity-based caching
    LuaFun              functional transforms
    Unit                compile product { fn, state_t }
    transition()        memoized ASDL → ASDL
    terminal()          memoized ASDL → Unit
    with_fallback()     pcall + neutral
    with_errors()       per-item error collection

PROPERTIES (emergent, not designed):
    incremental compilation     memoize + unique
    state isolation             Unit owns its ABI
    state composition           Unit.compose embeds children
    code size control           memoize boundaries = call boundaries
    hot swap                    global + :set() + :getpointer()
    error boundaries            with_fallback + with_errors
    zero-alloc playback         one terralib.new per edit
    undo = cache hit            memoize keeps old results

LEVELS:
    compilation (Lua)           pure — same input, same output
    execution (Terra)           closed — mutates only owned state

PIPELINE:
    f(g(h(x)))                  function composition IS the pipeline

FRAMEWORK SIZE:
    ~140 lines                  Unit + wrappers + helpers

WHAT DOESN'T EXIST:
    state management            memory management
    dispatch / vtables          configuration systems
    observer / events           dependency injection
    loading systems             serialization formats
    thread synchronization      build systems
    mocking / test doubles      error routing infrastructure
    progress tracking infra     incremental update tracking

WHY:
    FP makes purity the default.
    Memoize makes impurity self-defeating.
    ASDL makes mutation unavailable.
    Unit makes ABI ownership structural.
    Composition makes the pipeline implicit.
    LuaJIT makes the functional style free.
    LLVM makes the compiled output optimal.

    The architecture IS the composition.
    The discipline IS the framework.
    The pattern IS the program.
```
