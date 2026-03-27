# The Terra Compiler Pattern — Final Form

## Six primitives. No framework. The architecture IS the composition.

This document describes the terminal form of the Terra Compiler Pattern: the realization that when functional programming is not an add-on but the foundation, the entire pattern collapses to six primitives composed together. No DSL. No parser. No language extension. No framework. Just functions composing functions, producing native code.

The pattern rests on Terra (a low-level language embedded in Lua, JIT-compiled via LLVM) and six Lua-level tools: ASDL for domain types, Event ASDL for the input language, Apply for state transitions, `terralib.memoize` for caching, LuaFun for functional transforms, and Unit for compile products. Together they produce multi-stage incremental compilers that eliminate state management, memory management, dispatch, configuration, and infrastructure — not by solving these problems, but by making them structurally impossible.

The six primitives:

```
ASDL unique          what the program IS          (state)
Event ASDL           what can HAPPEN              (input)
Apply                how state CHANGES            (reducer)
Memoize              what DIDN'T change           (cache)
Unit                 what the machine DOES         (output)
LuaFun               how everything is ENFORCED   (discipline)

Six concepts. One loop. Every program.

poll → apply → compile → execute
  ↑                         │
  └─────────────────────────┘
```

---

## 1. The Six Primitives

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

### 1.3 LuaFun — the implementation discipline

```lua
local fun = require 'fun'

local nodes = fun.iter(track.devices)
    :filter(function(d) return d.enabled end)
    :map(compile_node)
    :totable()
```

LuaFun provides lazy, zero-allocation, JIT-friendly iterators: `map`, `filter`, `reduce`, `zip`, `chain`, `flatmap`, `enumerate`, `partition`, `all`, `any`, `head`, `take`, `drop`. Built for LuaJIT. The trace compiler sees through iterator chains and compiles them to the same machine code as hand-written loops.

LuaFun's role in the pattern is NOT convenience. It is NOT glue. It is the **enforcement mechanism** that makes the purity guarantees real.

ASDL gives you immutable values. Memoize gives you identity-based caching. But neither prevents you from writing impure functions that ignore the guarantees — a `for` loop with a mutable accumulator, a closure over external state, a `table.insert` that builds a new table without preserving structural sharing. LuaFun prevents this structurally. The API has no mutation verbs. There is no `set`, no `push`, no `remove`. You transform, filter, fold. The output is always a new value. The input is never modified.

**The rule is simple: every function in the pure layer is a LuaFun chain.** Transitions, terminals, apply reducers, projections, helpers — all of them. When you write a function, you use LuaFun. Point blank. This is not a style preference. It is the mechanism that closes the purity loop.

**LuaFun is also the ASDL quality probe.** If you cannot express a transformation as a natural LuaFun chain, the problem is not LuaFun — the problem is the ASDL:

```
Smell: you need a mutable accumulator in a transform
    → the data should be structured so the transform is a map,
      not a fold with mutation

Smell: you need to look up a value by ID mid-chain
    → the ID should be resolvable structurally, or the lookup
      belongs in a separate phase that already resolved it

Smell: you need to coordinate two transforms over different subtrees
    → the data they share should be in the same ASDL node,
      or they belong in a phase that sees both subtrees

Smell: you need to break out of the iterator to do something imperative
    → the ASDL is not modeling the domain correctly.
      Fix the types, not the code.
```

When every transform is a LuaFun chain feeding into an ASDL constructor, impurity requires EFFORT. You'd have to break out of the functional vocabulary to mutate something. The tooling discourages it. The caching punishes it. The code review catches it. LuaFun is what gives you the guarantees on the implementation of the ASDL. Purity is the default, not the aspiration.

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
        local errs = Unit.errors()
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


### 1.6 Event ASDL — the input language

Events ARE an ASDL sum type. Each variant is something that can happen. Without events, the compiler runs once and stops. With them, it's a live system. The event is what makes the ASDL change. The change is what triggers recompilation. The recompilation is what produces new Units. The Units are what the user sees and hears.

```lua
T:Define [[
    module Event {
        Event
            -- Input devices
            = KeyDown(number key, number mods)
            | KeyUp(number key, number mods)
            | MouseDown(number x, number y, number button)
            | MouseUp(number x, number y, number button)
            | MouseMove(number x, number y)
            | Scroll(number dx, number dy)
            | TextInput(string text)

            -- System
            | Resize(number width, number height)
            | Focus | Blur
            | Quit

            -- Domain (app-specific variants)
            | Midi(number status, number data1, number data2)
            | FileDropped(string path)
            | TimerTick(number dt)
            | NetworkMessage(string payload)

            -- Internal (from UI behavior layer)
            | Action(string name, number target_id)
            | ParamChange(number target_id, string field, number value)
            | Selection(number target_id)
            | Undo | Redo
    }
]]
```

Events are ASDL `unique` — same fields, same object. Same event pattern, same memoize hit. The event type is the exhaustiveness contract: `U.match` on the event sum forces you to handle every variant. You cannot ignore a new event kind without a compile-time error from the match.

Domain events (Midi, ParamChange, etc.) are the bridge between the external world and the compiler. An event enters the system, changes the ASDL state, and the pipeline recompiles from the changed state. The event IS the input language of the compiler.


### 1.7 Apply — the pure reducer

The apply function is `U.transition` — pure, memoized, `(state, event) → state`:

```lua
local apply = U.transition(function(state, event)
    return U.match(event, {
        KeyDown = function(e)
            return apply_key(state, e.key, e.mods)
        end,
        MouseDown = function(e)
            local hit = hit_test(state.view, e.x, e.y)
            if hit then return apply_click(state, hit) end
            return state
        end,
        ParamChange = function(e)
            return update_param(state, e.target_id, e.field, e.value)
        end,
        Undo = function(e)
            -- Pop history. The old state IS the undo.
            -- Memoize cache hit → zero recompilation.
            return state.history[#state.history]
        end,
        Redo = function(e)
            return state.future[1]
        end,
        Resize = function(e)
            return U.with(state, {
                viewport_w = e.width,
                viewport_h = e.height,
            })
        end,
        Quit = function(e)
            return U.with(state, { running = false })
        end,
    })
end)
```

The reducer is pure. Same state + same event → same new state. Memoize proves this. The pattern — `U.match` on an event sum, returning a new state — is Elm, is Redux, is every event-sourcing architecture. The difference is that this one compiles to native code in the same pipeline.

The key pattern is functional update deep in the tree with structural sharing:

```lua
local update_param = U.transition(function(state, target_id, field, value)
    local new_tracks = fun.iter(state.project.tracks)
        :map(function(track)
            local new_devices = fun.iter(track.devices)
                :map(function(device)
                    if device.id ~= target_id then return device end
                    return U.with(device, { [field] = value })
                    -- Every OTHER device: same object.
                    -- Every OTHER track: same object.
                    -- Memoize hits on all unchanged subtrees.
                end)
                :totable()
            if devices_unchanged(track.devices, new_devices) then
                return track
            end
            return U.with(track, { devices = new_devices })
        end)
        :totable()

    return U.with(state, {
        project = U.with(state.project, { tracks = new_tracks }),
        history = append(state.history, state),
    })
end)
```

One param changes. Every unchanged device returns the same ASDL object. Every unchanged track returns the same ASDL object. Memoize sees identity on all unchanged paths. Only the changed leaf recompiles. Undo is a cache hit — the old state is still in the memoize table.

Note that `apply` is written entirely in LuaFun style — `fun.iter():map():totable()`, `U.match`, `U.with`. This is not optional. The reducer is a pure function in the pure layer. It is `ASDL → ASDL`. Every function in the pure layer is a LuaFun chain (Section 1.3). Apply is no exception. If the reducer resists being written as a LuaFun chain — if you need mutable accumulators, imperative loops, or side effects to express a state transition — the ASDL is wrong. The event types are wrong, or the state structure is wrong, or a phase boundary is missing. LuaFun is the probe.


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

## 5. The Event Loop

The previous sections described a batch compiler: ASDL in, Unit out. But real programs don't stop after one compilation. They react to events. The event loop is what makes the pattern a live system.

### 5.1 poll → apply → compile → execute

Every program is this loop:

```
poll:     OS → events              (input)
apply:    (state, event) → state   (pure reducer)
compile:  state → Unit per output  (memoized, incremental)
execute:  Unit → device            (native, zero-dispatch)
```

`U.app` implements this loop. You provide the parts; the loop composes them:

```lua
U.app {
    initial = function()
        return T.AppState(T.Editor.Project(...), true)
    end,

    outputs = {
        audio = {&float, &float, int32} -> {},
        gpu   = {&uint8, int32} -> {},
    },

    compile = {
        audio = compile_audio,
        gpu   = compile_view,
    },

    start = {
        audio = start_portaudio,
        gpu   = start_glfw,
    },

    stop = {
        audio = stop_portaudio,
        gpu   = stop_glfw,
    },

    poll = poll_events,
    apply = apply,
}
```

The loop does exactly four things each iteration:

1. **poll**: Ask the OS for the next event. Returns `nil` when done.
2. **apply**: Feed the event into the pure reducer. Get a new state.
3. **compile**: If the state changed, recompile all outputs. Memoize means only changed subtrees recompile.
4. **execute**: The compiled Units are already installed in hot-swap slots. The audio/GPU drivers call them on the next callback.

The loop exits when `state.running` is `false` (set by the `Quit` event) or `poll()` returns `nil`.

### 5.2 Hot-swap slots per output

Each output device (audio, GPU, etc.) gets a `U.hot_slot`. The slot holds two Terra globals — a function pointer and a state pointer. The driver callback reads them. The edit path writes them. A pointer-width write is atomic. No locks.

```lua
local slot = U.hot_slot({&float, &float, int32} -> {})
-- Register with driver once:
jack_set_callback(slot.callback:getpointer())
-- On every recompile:
slot:swap(compile_audio(new_state))
```

`U.app` manages N slots automatically. You name them in `config.outputs`, provide compilers in `config.compile`, and the loop swaps them whenever state changes.

### 5.3 Incremental per output

Not every output needs recompiling on every event. A `Resize` event changes the GPU output but not the audio output. A `ParamChange` on a filter changes audio but not GPU.

Memoize handles this naturally. If `compile_audio(new_state)` returns the same Unit as before (because the audio-relevant parts of state didn't change), `slot:swap()` is a no-op — the function pointer and state pointer are the same values. The cost of "recompiling" an unchanged output is one memoize lookup: a pointer comparison.

### 5.4 Undo is a cache hit

The `apply` reducer stores previous states in a history list. On `Undo`, it returns the previous state object. That state was already compiled. The memoize cache still has its Unit. The slot swap installs the old Unit. Zero compilation. Zero LLVM. The user sees the old renderer instantly.

```lua
Undo = function(e)
    -- state.history[#state.history] is a previous ASDL object
    -- compile_audio(old_state) is a memoize cache hit
    -- slot:swap(same_unit) is a no-op
    return state.history[#state.history]
end
```

### 5.5 The complete application

A minimal interactive audio application using `U.app`:

```lua
local U = require 'unit'
local asdl = require 'asdl'
local fun = require 'fun'

local T = asdl.NewContext()
T:Define [[
    module Editor {
        Project = (string name, Track* tracks, number sample_rate) unique
        Track = (number id, string name, Device* devices, number volume_db) unique
        Device = Sine(number freq) | Biquad(number freq, number q) | Gain(number db) unique
    }
    module Event {
        Event = ParamChange(number target_id, string field, number value)
              | Undo | Quit
    }
]]

local apply = U.transition(function(state, event)
    return U.match(event, {
        ParamChange = function(e)
            return update_param(state, e.target_id, e.field, e.value)
        end,
        Undo = function(e)
            return state.history[#state.history] or state
        end,
        Quit = function(e)
            return U.with(state, { running = false })
        end,
    })
end)

local compile_audio = U.terminal(function(state)
    local units = fun.iter(state.project.tracks)
        :map(compile_track)
        :totable()
    return Unit.compose(units,
        terralib.newlist{ symbol(&float, "L"), symbol(&float, "R"), symbol(int32, "n") },
        function(s, kids, params)
            return quote escape
                for _, kid in ipairs(kids) do emit(kid.call(params[1], params[2], params[3])) end
            end end
        end)
end)

U.app {
    initial = function()
        return T.Editor.Project("Song", { ... }, 44100)
    end,
    outputs = { audio = {&float, &float, int32} -> {} },
    compile = { audio = compile_audio },
    start = { audio = start_jack },
    stop = { audio = stop_jack },
    poll = poll_jack_events,
    apply = apply,
}
```

That's a complete interactive audio engine. Input handling, undo, hot-swap, incremental compilation, zero-allocation playback. All from the pattern.

---

## 6. Allocation and State

### 6.1 The allocation model

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

### 6.2 Why state management doesn't exist

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

### 6.3 Why memory management doesn't exist

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

## 7. What This Eliminates

The six primitives, composed functionally, eliminate entire categories of software infrastructure. Not by solving them. By making them structurally impossible.

### 7.1 Things that don't exist

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

Execution planning        → ASDL graph IS the dependency graph
                            independent subtrees compile in parallel
                            no scheduler, no thread pool, no task queue

Build systems             → terralib.memoize IS the build cache
                            same inputs → same outputs

Mocking / test doubles    → every function is ASDL → ASDL, pure
                            construct input, call function, assert output
                            no mocks, no fixtures, no harness
                            the test IS the function call

Test infrastructure       → LuaFun purity + ASDL types = testable by construction
                            memoize IS the regression oracle
                            ASDL constructors ARE the test data generators
                            Unit.inspect derives test scaffolds from types

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

### 7.2 Why they don't exist

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
Execution planning:   reconciles dependency analysis and scheduling
```

The pattern eliminates independence. Code and data are one Unit. Allocation and lifetime are one edit. Type and behavior are one compilation. Configuration and runtime are one value (baked constants). Declaration and availability are one function (exists or doesn't). In-memory and on-disk are one ASDL type. The reconciliation systems have nothing to reconcile.

### 7.3 The ctx smell

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

### 7.4 Testing dissolves

Testing in the pattern is not simplified. It dissolves — the same way state management, memory management, and dispatch dissolve. The mechanisms that make the pattern work are the same mechanisms that make testing trivial. No test framework is needed because the architecture already provides everything a test framework would.

**Why every function is trivially testable.** Every function in the pure layer is `ASDL → ASDL` or `ASDL → Unit`, enforced by LuaFun. To test it: construct an ASDL node, call the function, assert the output. There is nothing else. No setup, no teardown, no mocking, no fixtures, no dependency injection, no test harness.

```
-- This IS the test. There is nothing else to write.
local input = Source.Track {
    name = "kick",
    clips = { Source.AudioClip { file = "kick.wav", start = 0, length = 44100 } }
}
local resolved = resolve_track(input)
assert(resolved.clips[1].sample_rate == 44100, "sample rate resolved")
```

The function under test has no hidden inputs. No global state. No database connection. No file system. No network. No clock. No environment variables. Its behavior is entirely determined by its arguments — because LuaFun enforces this and ASDL makes mutation unavailable. The test is the function call.

**Mocks don't exist because dependencies don't exist.** In traditional architectures, you mock the database, the file system, the network, the clock. You mock them because the function under test reaches into external systems. In the pattern, functions don't reach into anything. Their inputs are ASDL nodes — immutable values constructed right there in the test. There is nothing to mock because there is nothing to reach into.

**Memoize IS the regression oracle.** When you change a function, memoize tells you exactly what changed. Same ASDL input to the old function and the new function — if memoize returns the cached result, the behavior is identical. If it recomputes, the behavior changed. This is not a test you write. It is a property of the cache. The regression oracle is built into the runtime.

```
-- Memoize makes regression visible without tests:
-- Before: resolve_track(track_A) → cached_result_X
-- After code change: resolve_track(track_A) → recomputed_result_Y
-- If X ≠ Y, behavior changed. Memoize already knows.
```

**ASDL constructors ARE the test data generators.** Property testing requires generating random valid inputs. In the pattern, the ASDL types define exactly the space of valid inputs. Every valid ASDL node is a valid test input. Every constructor enforces the type constraints. You cannot construct an invalid input — the constructor rejects it. Random testing becomes: generate random arguments to ASDL constructors, call the function, assert structural properties of the output.

```
-- The ASDL type IS the property test specification:
-- Source.Track { name: string, clips: AudioClip list }
-- Valid inputs = all combinations of valid names × valid clip lists
-- The constructor enforces "valid" — no separate validation needed
```

**Unit.inspect derives test scaffolds from types.** Unit.inspect already walks the ASDL types and method tables for tooling. The same reflection produces test scaffolds — enumerate all sum type variants, generate one test input per variant, call the function, verify exhaustive handling. This is not a test generator you write. It is a consequence of ASDL types being inspectable values.

**What falls out:**
```
Mocking / test doubles      → functions have no external dependencies
Test fixtures               → ASDL constructors ARE the fixtures
Test harness                → the function call IS the test
Regression testing          → memoize IS the oracle
Property testing            → ASDL types define the input space
Mutation testing            → LuaFun chains have no branches to mutate
Integration testing         → composition IS integration
                              f(g(h(x))) tests the whole pipeline
End-to-end testing          → construct source ASDL, compile to Unit,
                              inspect the compiled output
Test coverage               → Unit.match is exhaustive by construction
                              every variant is handled or doesn't compile
```

**What doesn't exist:**
```
Test framework              setup/teardown/before/after — nothing to set up
Mock library                nothing to mock
Fixture management          ASDL constructors are self-contained
Test database               no database to simulate
Test environment            no environment to configure
CI test matrix              one input type, one output type, one path
Flaky tests                 pure functions don't flake
Test ordering bugs          pure functions don't depend on order
```

The testing argument is the same as every other elimination in this section: the pattern doesn't solve the testing problem. It makes the testing problem structurally impossible. When every function is pure, total (via Unit.match), and operates on immutable values (via ASDL), the only thing left to test is the logic — and the test for logic is: call the function.


---

## 8. The Two Levels

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

### 8.1 The five enforcement layers

No single layer is airtight. Lua is too dynamic. But the layers compound until impurity requires deliberate effort:

```
Layer 1: ASDL constructors
    → produce NEW immutable nodes
    → no setter API exists
    → to "change" a node, you construct a new one
    → mutation of domain objects is structurally unavailable

Layer 2: LuaFun iterators
    → map, filter, reduce — no mutation verbs
    → every function in the pure layer is a LuaFun chain
    → impurity requires breaking out of the API
    → if a function resists LuaFun, the ASDL is wrong (quality probe)

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
3. Break out of LuaFun into imperative loops — a smell that the ASDL needs fixing
4. Get it past code review — it looks wrong in context

The economics of effort favor correctness. Every deviation costs more than compliance.

---

## 9. Why FP Eliminates the Framework

This is the key insight that led to the final form.

### 9.1 What boundary.t was compensating for

`boundary.t` was a 2000-line Terra language extension with a parser, validator, closure composer, pipeline deriver, and CLI. It existed to enforce:

```
memoized boundaries         → transition() already does this
typed arguments             → ASDL types already does this
return type checking        → ASDL constructors already do this
pipeline consistency        → function composition already does this
exhaustive dispatch         → Unit.match already does this
error collection            → with_errors already does this
fallback on failure         → with_fallback already does this
Unit ABI validation         → Unit.new already does this
auto fn:compile()           → Unit.new already does this
```

Every row in the enforcement matrix was already handled by the FP primitives. The DSL was duplicating enforcement that composition already provided. It was governance for an imperative world applied to a functional one.

### 9.2 The framework dissolved because the pattern IS the framework

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

### 9.3 What remains

The six primitives: ASDL, Event ASDL, Apply, memoize, Unit, LuaFun. In the real implementation, `unit.t` also includes integrated helpers:

```
Unit.match      — exhaustive dispatch derived from ASDL variants
Unit.errors     — error collection with refs
Unit.with       — functional update on ASDL records
Unit.hot_slot   — hot-swappable render slot (two globals + callback + swap)
Unit.app        — the universal event loop (poll → apply → compile → execute)
Unit.inspect    — progress, docs, scaffolds, prompts, tests, pipeline views
```

The important point is that the pattern does not need a parser, DSL, validator language, or separate tooling framework. The implementation stays small, and the QoL layer is just reflection.

The features that `boundary.t` used to provide are derived by walking the ASDL context plus the installed methods:

```
Progress tracking:  inspect installed methods vs discovered types
Test generation:    one structural test per discovered boundary
Documentation:      walk ASDL types, emit markdown
Scaffolding:        generate method skeletons from ASDL reflection
Prompt generation:  walk the type graph, emit implementation context
Pipeline view:      inspect phase-local verbs and phase order
```

`Unit.inspect(ctx, phases)` lives in the same `unit.t` file. It reads the metadata already present in ASDL classes and installed methods. Still no parser. Still no language extension. Still one file.

### 9.4 The framework/language/library distinction dissolves

```
Framework:   you register with it, it calls you back
Library:     you call it, it returns
Language:    you express in it, it enforces rules

The six primitives are none of these. They are COMPOSITION TOOLS.
You compose them. They compose each other. There is no registration,
no callback, no enforcement. Just functions returning functions
returning Units.

The "framework" is the DISCIPLINE of composing correctly.
The "language" is the VOCABULARY of transition/terminal/with_fallback.
The "library" is the TOOLBOX of LuaFun + Unit.match + Unit.errors + Unit.inspect.

They're the same thing. There is no distinction to make.
The architecture IS the composition.
```

---

## 10. The Development Flow

The development order is leaves-up. You start at the bottom of the pipeline — the leaf compiler that produces machine code — and let it tell you what the layers above must provide. This is the recursive process that discovers the correct ASDL.

### 10.1 Start at the leaf

Don't start with the ASDL. Start with the leaf compiler. Write the function you WANT to write — the one that takes a single node and produces a Unit.

```lua
local compile_sine = terminal(function(node, sr)
    return Unit.leaf(struct { phase: float }, params, function(state, p)
        -- ... sine wave with baked frequency ...
    end)
end)
```

This function tells you exactly what `node` must contain. The sine generator needs a frequency, a waveform shape, a gain. If the ASDL node doesn't have those fields, the leaf won't compile. That's the signal: **the leaf dictates what the ASDL must provide.**

Don't fix the leaf. Fix the layer above.

### 10.2 The recursive process

The leaf says: "I need frequency, waveform, gain on this node."

Now go to the layer that PRODUCES this node — the phase transition above. That transition must put frequency, waveform, and gain onto the node. To do that, it needs those values from ITS input. If its input ASDL doesn't have them, go one layer higher. That layer must provide them. Recurse.

```
leaf compiler:        "I need resolved frequency on the node"
    ↓ fix
scheduling phase:     "I need frequency to schedule — get it from resolved"
    ↓ fix
resolution phase:     "I need to resolve frequency — get it from authored"
    ↓ fix
lowering phase:       "I need frequency in authored — get it from source"
    ↓ fix
source ASDL:          add frequency field to the oscillator type
```

This is the process: **write the leaf you want to write, then modify each layer above to give you what you need.** Apply recursively from the leaves up. The source ASDL is the LAST thing that settles, not the first.

### 10.3 Why leaves-up gives the earliest warnings

The leaf compiler is the smallest function in the system — 10-20 lines. It is also the most honest. It has no room to hide a bad ASDL. If the node is missing a field, you know immediately. If the node has coupled data that should have been resolved in a prior phase, LuaFun resists. If the identity noun is the wrong granularity, the leaf is either trivial (too fine) or enormous (too coarse).

```
LEAF WARNINGS (discovered in 10 lines):
    Missing field           → ASDL is incomplete
    LuaFun resistance       → prior phase didn't resolve a coupling
    Trivial function        → identity noun is too fine-grained
    Enormous function       → identity noun is too coarse, or missing phase
    Needs sibling context   → containment hierarchy is wrong
    Needs global lookup     → missing resolution phase
```

By contrast, if you start top-down — design the complete ASDL first, then implement — you don't discover these problems until you've written hundreds of lines of phase transitions. The leaf would have told you in ten.

### 10.4 Write more leaves, build upward

One `terminal` function per node kind. Each leaf discovers its own requirements.

```lua
local compile_biquad = terminal(function(node, sr)
    return Unit.leaf(struct { x1: float; x2: float; y1: float; y2: float },
        params, function(state, p)
        -- ... biquad with baked coefficients ...
    end)
end)
```

The biquad leaf says: "I need pre-computed filter coefficients." That tells you the scheduling or classification phase must compute them. Which tells you the classification phase needs the filter type and cutoff frequency. Which tells you the source ASDL needs those fields on the filter node. Every leaf tightens the ASDL from below.

### 10.5 Write composition compilers

Once leaves work, composition tells you whether the containment hierarchy is right.

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

If composing children requires knowing about siblings, the hierarchy is wrong. If you need cross-child information, that's a missing resolution phase — go add it to the layer above. Same recursive process.

### 10.6 Write transition functions

Each transforms ASDL from one phase to the next. By this point, the leaves have already told you what each phase must produce. The transition function's job is now clear — it must provide what the layer below demands.

```lua
local lower_track = transition(function(track)
    return T.Authored.Track(
        track.id,
        T.Authored.Graph(fun.iter(track.devices):map(lower_device):totable()),
        track.volume_db, track.pan
    )
end)
```

If the transition function is hard to write, the problem is in the phase design — but you already know what it must produce (the leaves told you) and what it receives (the layer above told it). The hard part is the transformation logic itself, which is the actual domain expertise.

### 10.7 Compose the pipeline

```lua
local function build(project)
    return compile_session(schedule(lower(project)))
end
```

### 10.8 Connect to the audio driver

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

### 10.9 Define events and the reducer

Define what can happen, and how each event changes state:

```lua
T:Define [[
    module Event {
        Event = ParamChange(number target_id, string field, number value)
              | Undo | Redo | Quit
    }
]]

local apply = U.transition(function(state, event)
    return U.match(event, {
        ParamChange = function(e)
            return update_param(state, e.target_id, e.field, e.value)
        end,
        Undo = function(e) return state.history[#state.history] or state end,
        Redo = function(e) return state.future[1] or state end,
        Quit = function(e) return U.with(state, { running = false }) end,
    })
end)
```

### 10.10 Run the application

```lua
U.app {
    initial = function() return T.AppState(T.Editor.Project(...), true) end,
    outputs = { audio = {&float, &float, int32} -> {} },
    compile = { audio = compile_session },
    start   = { audio = start_jack },
    stop    = { audio = stop_jack },
    poll    = poll_events,
    apply   = apply,
}
```

### 10.11 Done

That's a working interactive application. But the order in which it was built is the critical insight: leaves first, then composition, then transitions, then pipeline, then events. Each layer was shaped by the layer below it. The ASDL wasn't designed once and implemented — it was discovered through the recursive pressure of implementation.

Add more node types by writing more `terminal` functions — each one will tell you if the ASDL needs adjustment. Add more phases by writing more `transition` functions — the leaves already told you what they need. Add more event kinds by extending the Event ASDL sum type and adding arms to the reducer. Everything composes, and the leaves remain the source of truth about what the machine actually needs.

### 10.12 The ASDL design cycle

The modeling method (the other document) gives you a first draft of the ASDL. That draft is a hypothesis. The leaves-up implementation tests it.

```
DESIGN (top-down):        model the domain → draft ASDL → draft phases
IMPLEMENT (bottom-up):    write leaf → leaf demands → fix layer above → recurse
CONVERGE:                 the ASDL stabilizes when leaves stop demanding changes
```

These are not separate activities. They interleave. You model a bit, implement a leaf, discover the model is wrong, fix it, implement the next leaf. The modeling method tells you WHERE to look. The leaves tell you WHAT to put there. Neither works alone. Together, they converge on the correct ASDL — the one where every leaf is a natural LuaFun chain and every phase transition is obvious.


---

## 11. The Complete Framework

The framework lives in one file. The code below is an illustrative excerpt of that real `unit.t`: it shows the shape of the runtime core. The actual file also includes `Unit.inspect`, hot-swap helpers, and other reflection-based QoL. The file can grow; the architecture stays the same.

```lua
-- unit.t — illustrative excerpt of the Terra Compiler Pattern core

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

-- The event loop

function Unit.app(config)
    local slots = {}
    for name, fn_type in pairs(config.outputs) do
        slots[name] = Unit.hot_slot(fn_type)
    end

    local state = config.initial()

    for name, compiler in pairs(config.compile) do
        if slots[name] then
            slots[name]:swap(compiler(state))
        end
    end

    for name, start_fn in pairs(config.start) do
        if slots[name] then
            start_fn(slots[name].callback:getpointer())
        end
    end

    while state.running ~= false do
        local event = config.poll()
        if not event then break end

        local new_state = config.apply(state, event)

        if new_state ~= state then
            state = new_state
            for name, compiler in pairs(config.compile) do
                if slots[name] then
                    slots[name]:swap(compiler(state))
                end
            end
        end
    end

    if config.stop then
        for name, stop_fn in pairs(config.stop) do
            stop_fn()
        end
    end

    return state
end

return Unit
```

Read the excerpt as a shape sketch, not as a claim that the file ends here. The real framework is the single `unit.t`, and that file includes `Unit.inspect(...)`, `Unit.hot_slot(...)`, and other reflection-based QoL without introducing another module or DSL. The file gets longer; the architecture does not.


---


## 12. Performance Model

### 12.1 Two JIT compilers

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

### 12.2 Time budget for one edit

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

### 12.3 Scaling

```
2 tracks, 6 nodes:       ~3ms per edit, ~48 bytes state
20 tracks, 60 nodes:     ~3ms per edit, ~480 bytes state
200 tracks, 600 nodes:   ~3ms per edit, ~4800 bytes state

Same time. Because memoize means LLVM only sees the ONE changed node.
The 200-track session compiles as fast as the 2-track session.
```

State size scales linearly with node count. Compilation time is constant per edit (one leaf recompile). Memory is one allocation for the entire state struct. The architecture is O(1) per edit, O(n) in memory, O(n) in initial cold compilation.


---


## 13. The Backend Interface

The pattern is not Terra-specific. Terra is the first backend — and the best one, because LLVM produces optimal native code and Terra quotes give you zero-cost code composition. But the architecture — ASDL + memoize + pure pipeline + events + Unit — is a model that any backend can implement.

The pattern is a portable **architecture**, not a portable codebase. Each backend is a real implementation with its own strengths and tradeoffs. But the thinking, the structure, the six primitives, the loop — those are universal.

### 13.1 The three layers

```
┌─────────────────────────────────────────────┐
│                YOUR DOMAIN                   │
│                                              │
│  ASDL types, transitions, compositions,      │
│  events, apply, view projection              │
│                                              │
│  Portable. This IS your application.         │
├─────────────────────────────────────────────┤
│              THE PATTERN                     │
│                                              │
│  memoize, Unit, transition, terminal,        │
│  with_fallback, with_errors, match, with     │
│                                              │
│  Portable. Pure functional.                  │
│  Doesn't know what a pixel or sample is.     │
├─────────────────────────────────────────────┤
│              THE BACKEND                     │
│                                              │
│  Leaf compilation, state allocation,         │
│  hot-swap mechanism, event loop, drivers     │
│                                              │
│  Target-specific. The ONLY thing that changes.│
└─────────────────────────────────────────────┘
```

The top two layers are pure. They produce ASDL values and Units. The bottom layer is the only thing that touches the real world — it compiles leaf bodies, allocates state, swaps pointers, polls for events, and drives output devices.

### 13.2 The backend contract

A backend must provide five things:

```
leaf(state_layout, body) → Unit
    How to compile a leaf computation to executable code.

swap(slot, unit)
    How to install a new Unit on an output device.

poll() → Event | nil
    How to get input from the world.

start(output_name, callback)
    How to register a callback with an output device.

alloc(state_layout) → state
    How to allocate state for a compiled Unit.
```

Five functions. That's the entire backend contract. Everything above is pure, target-independent functional computation over ASDL values.

### 13.3 What changes per backend, what doesn't

What is **universal** (same on every target):

- ASDL type definitions and the `unique` interning behavior
- The memoize pattern (same input → same output, skip work)
- The boundary wrappers (transition, terminal, with_fallback, with_errors)
- The helpers (match, with, errors)
- The event loop structure (poll → apply → compile → execute)
- The app-level domain logic (transitions, events, apply reducer)

What is **backend-specific** (reimplemented per target):

- Leaf body format: Terra quotes, JS closures, WASM opcodes, Lua functions
- State representation: Terra structs, typed arrays, FFI buffers
- Compose internals: how children's state is aggregated and sliced
- Hot-swap mechanism: pointer swap, postMessage, table replacement
- Memoize implementation: `terralib.memoize`, WeakMap, custom cache
- ASDL runtime: the library that provides constructors and `unique`
- Output drivers: PortAudio, AudioWorklet, SDL, GLFW

### 13.4 Example backends

**Terra + LLVM (native)** — the primary backend. Leaf bodies are Terra quotes that get spliced into generated functions and compiled by LLVM to native code. State is a Terra struct allocated with `terralib.new`. Hot-swap is two Terra globals (function pointer + state pointer). This is the backend described throughout this document. It produces the best output: fully specialized native code with baked constants, zero-dispatch, zero-allocation execution.

**LuaJIT (interpreted)** — for prototyping. Leaf bodies are plain Lua functions. LuaJIT traces through them — not LLVM-fast, but still fast. State is FFI-allocated buffers. Hot-swap is a table field replacement. Same pattern, same architecture, same incremental behavior. No LLVM. Useful for rapid development before writing Terra leaves.

**JavaScript (browser)** — leaf bodies are JS closures with baked constants in the closure scope. State is `Float64Array`. Hot-swap is `postMessage` to an AudioWorklet or reassignment of a `requestAnimationFrame` callback. Memoize is a WeakMap keyed on frozen ASDL objects. The pattern works because JS closures with captured constants are effectively "baked" — V8 optimizes them the same way LLVM optimizes constant-folded code.

**WASM (embeddable)** — leaf bodies are WASM opcode sequences. The pattern compiles domain ASDL → WASM bytecode, producing a `.wasm` binary that any host can execute. This is the most interesting non-Terra backend because WASM is itself an ASDL (the WASM spec is literally defined in ASDL), so the pattern compiles one ASDL into another.

### 13.5 What the backends share

The differences are real — each backend has its own leaf format, state model, and swap mechanism. But the architecture is identical:

```
Every backend:
    ASDL unique → structural identity → memoize cache key
    memoize     → same input, skip work
    transition  → memoized ASDL → ASDL
    terminal    → memoized ASDL → Unit
    compose     → aggregate children's state, dispatch calls
    apply       → (state, event) → state, pure
    app loop    → poll → apply → compile → execute
```

The domain code — your ASDL types, your transitions, your event definitions, your apply reducer — expresses the same logic on every backend. It's not shared source code (Lua syntax is not JS syntax), but it's shared **structure**. A port from Terra to JS is a syntactic translation, not an architectural redesign.

### 13.6 Why Terra is the best backend

Terra is not just one backend among equals. It is the best one, for specific reasons:

- **Quotes as values**: Terra quotes are code fragments that compose at the Lua level and compile at the LLVM level. No other backend has this. JS closures are already compiled. WASM opcodes are a manual IR. Only Terra gives you "code as a composable Lua value that compiles to optimal native code."
- **LLVM optimization**: LLVM sees fully specialized code with baked constants and optimizes it better than hand-written C. A JS JIT sees closures and does its best. LLVM sees monomorphic functions with literal constants and produces perfect code.
- **Typed state structs**: `Unit.compose` builds a Terra struct type at compile time. Child state is a named field with a known offset. The pointer expression `&state.s1` compiles to a constant offset — zero runtime cost. In JS, you'd index into a flat array. In LuaJIT, you'd use FFI structs (close, but not as integrated).
- **Atomic pointer swap**: Terra globals are C-level pointers. A pointer-width write is atomic on all architectures. JS needs postMessage. Lua needs a table write (which is atomic in LuaJIT but not guaranteed).
- **Two-JIT synergy**: LuaJIT compiles the pure layer. LLVM compiles the execution layer. Each JIT handles the level it was designed for. No other backend has two JIT compilers working at two levels.

Other backends implement the pattern. Terra implements it optimally.

### 13.7 The target is a memoize key

Only the leaves touch the backend. Transitions are ASDL → ASDL — pure data, no code generation. Compose aggregates children — structural, not target-specific. Match, with, errors — pure helpers. The leaf is the single point where "what to compute" becomes "how to compute it."

This means the target is just another argument to the terminal:

```lua
-- Single target (current):
local compile_biquad = terminal(function(node, sr)
    return backend.leaf(...)
end)

-- Multi-target (the backend IS a memoize key):
local compile_biquad = terminal(function(node, sr, target)
    return target.leaf(...)
end)
```

Same node + same sample rate + same target → same Unit. Different target → different Unit. Both are in the memoize cache simultaneously. Compile for WASM and the native Unit is still cached. Compile for native and the WASM Unit is still cached.

The implications:

```
One ASDL tree.
N targets.
Each target's Units cached independently.
Change a parameter → only the changed leaf recompiles, per target.
The unchanged target's cache is untouched.

Cross-compilation is incremental compilation
with the target as a cache key.
```

The pattern doesn't need a "cross-compilation mode." Cross-compilation IS compilation. The target is data. Data is a memoize key. The cache handles the rest.

A concrete example: a DAW that shares its view via a browser link. The Terra program runs locally, compiling audio leaves to native code for real-time playback. The same ASDL tree, passed to a WASM target, compiles the view leaves to a `.wasm` binary. That binary is served to a remote browser. The browser runs the same view — same ASDL, same pipeline, different backend. When the user turns a knob, the audio leaf recompiles (native, ~1ms), the view leaf recompiles (WASM, incrementally), and the new binary is pushed to the browser. The remote viewer sees the change live. Two targets, one ASDL tree, one memoize cache partitioned by target. The pattern already supports this — it's just two entries in `config.compile`.

The compilation boundary IS the loading boundary. When the WASM binary arrives at the browser, instantiating it is the "load." It happens at the exact moment compilation produced a new Unit — not before (nothing to load), not after (the Unit is ready). The timing is structurally correct because compilation and loading are the same event. And the loading is incremental because the compilation is incremental: the browser doesn't reload the entire application, it receives the recompiled leaves. Unchanged leaves are already instantiated. This is Section 7.1's insight — "compilation state IS loading state" — composed with Section 13.7's insight — "the target is a memoize key." Correct remote loading falls out for free.

### 13.8 Parallelism falls out of the graph

The ASDL dependency graph IS the execution plan. No separate scheduler, no thread pool abstraction, no "parallel framework." The information is already in the data.

An ASDL tree is a DAG of immutable values. Every node knows its children. Every memoized function depends only on its explicit arguments. This means the dependency structure is fully visible at the Lua level before any compilation happens:

```
        root
       /    \
    mix_L   mix_R
    / \      / \
  eq  comp  eq  comp
  |    |    |    |
 osc  osc  osc  osc
```

Nodes that don't share ancestors are independent. `mix_L` and `mix_R` can compile in parallel. All four `osc` leaves can compile in parallel. The graph tells you which work is independent — you don't need to discover it at runtime.

```lua
-- Sequential (current):
local units = fun.iter(nodes):map(compile_node):totable()

-- Parallel (same semantics, different execution):
local units = parallel_map(nodes, compile_node)
```

The function `compile_node` is memoized and pure. It has no side effects, no shared mutable state, no ordering requirements. Calling it on independent nodes in parallel is safe by construction — the pattern's purity guarantees this. Memoize handles deduplication: if two parallel branches reach the same shared subnode, one compiles and caches, the other gets a cache hit. No locks needed because ASDL nodes are immutable and memoize is keyed on identity.

This extends to every level:

```
Leaf compilation:     independent leaves compile in parallel
                      (the LLVM calls are the bottleneck — parallelize them)

Subtree compilation:  independent subtrees compile in parallel
                      (each subtree's memoize cache is independent)

Multi-target:         compile for native + WASM in parallel
                      (target is a memoize key — Section 13.7)

Multi-output:         compile audio + video pipelines in parallel
                      (different ASDL trees, fully independent)
```

The execution plan is not something you build on top of the pattern. It is something you READ from the ASDL graph. The graph's structure already encodes what depends on what, what can run concurrently, and what must be sequential. Traditional architectures need a separate scheduling layer because their dependency information is scattered across mutable state, callbacks, and implicit ordering. The pattern concentrates all dependencies in one place — the ASDL tree — and makes them immutable. The execution plan is a property of the data, not a property of the runtime.

Parallelism, like cross-compilation (Section 13.7) and remote loading (Section 13.7), is not a feature added to the pattern. It is a consequence that falls out of the structural properties that already exist: immutable values, explicit dependencies, memoized pure functions.


---


## 14. The Philosophical Core

### 14.1 The compiler IS the program

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

### 14.2 We build translators, not interpreters

An interpreter re-asks questions every frame: "What type is this? What branch do I take? Where is this field?" The answers are always the same. The work is wasted.

A translator asks once, writes down the answer as code, and never asks again. The cost is paid once. The result runs forever — or until the input changes, at which point you translate again.

Layering translators is safe because each is a total function. ASDL in, ASDL out (or ASDL in, Unit out). Each layer narrows. Each layer consumes knowledge. The layers don't interact except through typed interfaces.

### 14.3 Quotes are the better pointers

Pointers live at runtime. They're subject to time — they can dangle, leak, race. They're addresses into mutable memory. Every pointer is a question: "is this still valid?"

Quotes live at compile time. They're consumed during compilation and cease to exist at runtime. They're code fragments, not addresses. They can't dangle because they don't exist after compilation. They can't leak because they're not allocated. They can't race because they're not shared.

The pattern replaces pointers with quotes wherever possible. Node connections are not pointer graphs at runtime — they're quote compositions at compile time. Parameter bindings are not pointer lookups — they're baked constants. State access is not pointer chasing — it's struct field offsets computed by Terra.

### 14.4 Configuration is a staging error

Every `ctx`, `void*`, config struct, or hash table lookup at runtime represents knowledge that was available at compile time but failed to be consumed. The compiler had the answer. It leaked to runtime as an indirection.

The pattern consumes ALL configuration at compile time:
- Filter frequencies → baked as float constants
- Node connections → baked as direct function calls
- Buffer sizes → baked as loop bounds
- Channel counts → baked as struct layouts
- Gain values → baked as multiply constants

At runtime there is no configuration. No settings. No parameters (in the infrastructure sense). Just arithmetic on arrays of floats. The "configuration" was consumed by the compiler. What remains is the output of that consumption: specialized native code.

### 14.5 Alloc and free are edit events

The traditional audio engine allocates and frees during playback: buffer checkouts, event queues, temporary storage, parameter smoothing state. Each allocation is a potential priority inversion. Each free is a potential GC pause.

In this pattern, alloc happens once per edit (one `terralib.new(SessionState)`). Free happens when the next edit replaces the old state (Lua GC collects it asynchronously). During playback: zero allocations. Zero frees. The audio thread doesn't know how to allocate. The compiled function operates on a pre-allocated state struct via a pointer. That's all it can do.

### 14.6 The architecture reduces to composition

No framework. No DSL. No registration. No configuration. No lifecycle. No event system. No dependency injection. No plugin interface. No build system. No separate test framework. No separate documentation system.

Just:
- ASDL types (domain model, state)
- Event ASDL (input language, what can happen)
- Apply / U.transition (pure reducer, how state changes)
- LuaFun (functional transforms, glue)
- memoize (caching, what didn't change)
- Unit (compile products, output)
- transition/terminal/with_fallback/with_errors (boundary wrappers)
- Unit.match / Unit.errors / Unit.with (small helpers)
- Unit.hot_slot / Unit.app (runtime: hot-swap + event loop)
- Unit.inspect (reflection-derived QoL, in the same file)

These compose into a live interactive system with multi-stage incremental compilation, hot-swap, event handling, undo, error recovery, state management, memory management, complete elimination of runtime dispatch, and tooling derived from the same ASDL. The loop is: poll → apply → compile → execute.

A small implementation with reflection-derived helpers. The rest is your domain.


---


## 15. What You Can Build

The pattern is not specific to audio. It applies to any interactive program where the user edits a domain model and the program produces machine output from it. Every example below follows the same structure: ASDL source → memoized pipeline → Unit output → hot-swap → event loop. The same six primitives. The same loop. Different domains.

### 15.1 A text editor (neovim clone)

A text editor is a compiler. The user writes text; the editor compiles it into GPU draw calls (or terminal escape sequences). Every keystroke is an edit event. Every edit recompiles — incrementally, because memoize caches unchanged lines.

**Source ASDL:**

```lua
T:Define [[
    Editor = (Buffer* buffers, Window* windows, Mode mode,
              Keymap keymap, number active_window) unique

    Buffer = (number id, Line* lines, number cursor_line,
              number cursor_col, Mark* marks, string filepath,
              boolean modified) unique

    Line = (number id, string text) unique

    Window = (number id, number buffer_id, number top_line,
              number width, number height, Split? split) unique

    Split = Horizontal(Window left, Window right, number ratio)
          | Vertical(Window top, Window bottom, number ratio)

    Mode = Normal | Insert | Visual(Selection sel) | Command(string input)

    Selection = (number start_line, number start_col,
                 number end_line, number end_col) unique

    Mark = (string name, number line, number col) unique

    Keymap = (KeyBinding* bindings) unique
    KeyBinding = (string key, string action, Mode? mode_filter) unique
]]
```

**Events:**

```lua
T:Define [[
    Event = KeyPress(string key, boolean ctrl, boolean alt, boolean shift)
          | Resize(number width, number height)
          | Mouse(number x, number y, MouseAction action)
          | FileEvent(string path, FileAction kind)

    MouseAction = Click | Drag | Scroll(number delta)
    FileAction = Changed | Deleted | Created
]]
```

**What falls out:**

```
Incremental rendering      A keystroke changes one Line node.
                           Memoize caches all other lines.
                           Only the changed line recompiles to draw calls.
                           A 10,000-line file renders as fast as a 10-line file
                           after the first frame.

Undo                       Previous Editor ASDL node → memoize cache hit → instant.
                           No undo stack implementation. No diff/patch.
                           Undo IS "use the old tree." The old render is still cached.

Multiple windows           Each Window compiles independently.
                           Split view of same buffer: two Windows, same Buffer node,
                           memoize hits on the shared Buffer's line compilation.
                           Two views, one compilation.

Modal editing              Mode is a sum type. The reducer pattern-matches on it.
                           Normal mode: h/j/k/l move cursor → new Buffer node.
                           Insert mode: characters insert → new Line node.
                           Visual mode: motion extends Selection → new Mode node.
                           Command mode: input builds command string → new Mode node.
                           No mode state machine. No mode flags. No "if mode == ..."
                           scattered through the codebase. One match in the reducer.

Syntax highlighting        A second terminal boundary, same pipeline.
                           Line → tokenize → styled spans → draw calls.
                           Memoized per line. Change one line, retokenize one line.
                           The tokenizer is a leaf compiler. It falls out.

Multiple outputs           Terminal backend: Line → ANSI escape sequences.
                           GPU backend: Line → textured quads.
                           Same ASDL, same pipeline, different leaves.
                           Both cached independently (target is a memoize key).

Parallelism                Independent buffers compile in parallel.
                           Independent windows compile in parallel.
                           Within a buffer, independent line groups compile in parallel.
                           The ASDL graph tells you what's independent.

File watching              FileEvent is an Event variant. The reducer handles it:
                           FileChanged → reload buffer → new Buffer node → recompile.
                           Same loop. No separate file-watching infrastructure.

Search/replace             Replace produces new Line nodes for affected lines.
                           Unaffected lines: same ASDL objects, memoize hits.
                           A 10,000-line file with 3 replacements recompiles 3 lines.

Configuration              Keymap is ASDL. It compiles into the reducer.
                           No runtime keymap lookup. The keybindings are baked.
                           Change a binding → new Keymap node → recompile reducer.
```

**What doesn't exist:**

```
No event bus               poll → apply → compile → execute. That's it.
No plugin API              ASDL types ARE the interface. Add a NodeKind variant.
No redraw scheduling       Compilation produces the frame. Hot-swap installs it.
No dirty-region tracking   Memoize IS the dirty-region tracker.
No undo stack              Memoize cache IS the undo stack.
No mode state machine      Mode is a sum type in the reducer.
No buffer management       Buffer is an ASDL node. GC handles lifetime.
No layout engine           Window positions are computed in a transition phase.
No command parser          Command mode accumulates a string. Parse in the reducer.
```

**Performance budget:**

```
Keystroke in insert mode:
    Construct new Line node          ~0.001ms   (ASDL unique)
    Construct new Buffer node        ~0.001ms   (structural sharing)
    Construct new Editor node        ~0.001ms
    Reducer: pattern match Mode      ~0.001ms   (LuaJIT)
    Memoize: hit on all other lines  ~0.001ms   (per hit)
    Memoize: miss on changed line    ~0.001ms
    Terminal: compile line to draws   ~0.1ms    (one line of text)
    Swap                             ~0.000ms
    Total:                           ~0.1ms     (10,000 FPS headroom)
```

One keystroke: 0.1ms. The bottleneck is the leaf compiler, and a line-to-draw-calls compiler is trivial. With the LuaJIT backend (no LLVM), this gets even faster — a Lua closure that produces ANSI escape codes traces instantly.

### 15.2 A spreadsheet

A spreadsheet is a compiler. Formulas are source code. The spreadsheet compiles them into a native evaluation function. Every cell edit recompiles — incrementally, because memoize caches cells whose dependencies haven't changed.

**What falls out:**

```
Incremental evaluation     Change cell A1. Only cells that depend on A1 recompute.
                           The dependency graph IS the ASDL structure.
                           Memoize caches the rest. A 10,000-cell sheet with one
                           edit recomputes only the affected subgraph.

Compiled formulas          =SUM(A1:A10) compiles to:
                               terra: return cells[0]+cells[1]+...+cells[9]
                           No formula interpreter. No AST walker at runtime.
                           The formula was consumed by the compiler. What remains
                           is a native add chain with baked cell offsets.

Circular dependency        The Resolved phase builds the dependency DAG.
                           A cycle means two cells are in the same SCC.
                           This is an error with semantic refs: CellRef(A1), CellRef(B1).
                           The error flows through with_errors. The View shows it.
                           No special circular-dependency checker. It falls out
                           of the topological sort.

Parallel evaluation        Independent subgraphs evaluate in parallel.
                           Cells that don't depend on each other compile in parallel.
                           The dependency DAG tells you everything. No scheduler.

Charts                     A chart is a second terminal from the same ASDL.
                           Sheet → values → chart data → GPU draw calls.
                           Change a cell → the chart recompiles incrementally.
                           Only the affected series redraws.

Multiple views             Same Sheet, multiple Windows (tab view, chart view,
                           pivot table view). Each is a projection from the same
                           source ASDL. Each memoized independently.

Undo                       Previous Sheet node → memoize hits → instant.
                           The old evaluation results are still cached.
```

### 15.3 A vector graphics editor

A vector graphics editor is a compiler. Shapes are source. The editor compiles them into GPU draw calls. Every drag, every color pick, every path edit recompiles the changed shape. Everything else is cached.

**What falls out:**

```
Incremental rendering      Move one shape. That shape's leaf recompiles.
                           All other shapes: memoize hit. A canvas with 10,000
                           shapes renders a single-shape edit in the same time
                           as a canvas with 10 shapes.

Layer composition          Layers are ASDL nodes. Layer order is a list.
                           Reordering layers produces a new list with the same
                           child nodes (structural sharing). Memoize hits on
                           every layer's content. Only the composition recompiles.

Group transforms           Group → children with relative transforms.
                           Moving a group changes the Group node's transform.
                           Children are the SAME ASDL nodes (they didn't change).
                           Memoize hits on children. Only the group shell recompiles.

Export                      Export to SVG, PDF, PNG are different terminals.
                           Same ASDL → different leaf compilers.
                           Target is a memoize key. All exports cached independently.

Boolean operations         Union, intersection, difference on paths.
                           These are transition phases: Shape × Shape → Shape.
                           The result is a new ASDL node. Memoize caches it.
                           Editing either input shape recompiles the boolean result.
                           Editing neither: cache hit.

Zoom/pan                   Viewport is ASDL. Zoom changes the viewport node.
                           Shape compilation is viewport-independent (shapes are
                           in document coordinates). Only the final projection
                           from document to screen coordinates changes.
                           With the right phase boundary, zoom is a cache hit
                           on all shapes — only the projection shell recompiles.
```

### 15.4 A game engine (scene editor)

A game engine editor is a compiler. The scene graph is source. The engine compiles it into a render function AND a physics step function. Both from the same ASDL, both memoized independently.

**What falls out:**

```
Two pipelines, one source  Scene ASDL → render pipeline → GPU Unit
                           Scene ASDL → physics pipeline → Step Unit
                           Change a mesh → render recompiles, physics cached.
                           Change a collider → physics recompiles, render cached.
                           Independent pipelines from shared source.

Incremental scene compile  Move an entity. One entity's transform changes.
                           All other entities: memoize hit.
                           Add a light. One light added. Existing lights cached.
                           The compiled render function only recompiles the
                           affected draw calls.

Level of detail            LOD is a classification phase decision.
                           Camera distance → LOD level → different mesh.
                           The LOD decision is baked into the compiled render call.
                           No runtime LOD check. The compiled function already
                           uses the right mesh.

Material compilation       Material = PBR(albedo, roughness, metallic, ...)
                           Compiles to a specialized shader with baked constants.
                           Change roughness → recompile one shader.
                           Other materials: cached.

Live editing               Move an entity in the editor → new ASDL node →
                           recompile → hot-swap → see the change on screen.
                           Same loop as the DAW. Same latency (~1-3ms per edit).
                           No separate "editor mode" vs "play mode."
                           Editing IS recompilation. Play IS execution.

Prefabs                    A prefab is an ASDL subtree. Instancing is
                           structural sharing. 100 instances of the same prefab
                           are 100 references to the same ASDL node.
                           Memoize compiles it once. Change the prefab →
                           one recompilation, 100 instances updated.
```

### 15.5 A UI toolkit

A UI toolkit is a compiler. The element tree is source. The toolkit compiles it into GPU draw calls. Every state change recompiles the changed subtree. This is what React tries to be, but with real compilation instead of virtual DOM diffing.

**What falls out:**

```
Incremental layout         Change one element's text. That element relayouts.
                           Siblings with independent sizing: memoize hit.
                           Parent shell recompiles (new child size).
                           Unaffected subtrees: cached.

No virtual DOM             ASDL unique IS the diff. Same node = same object.
                           No tree comparison. No reconciliation algorithm.
                           Identity is structural. The "diff" is a pointer
                           comparison that LuaJIT compiles to a single instruction.

Compiled event handlers    Event handlers are part of the ASDL.
                           They compile into the reducer. No addEventListener.
                           No event delegation. No event bubbling implementation.
                           The compiled function handles the event directly.

Theming                    Theme is ASDL. Change the theme → new ASDL node →
                           every element that depends on the theme recompiles.
                           Elements with hardcoded colors: memoize hit
                           (they don't depend on the theme node).

Responsive layout          Window size is an event. Resize → new ASDL →
                           recompile layout. Only elements affected by the
                           size change recompile. Fixed-size elements: cached.

Accessibility              Accessibility tree is a third terminal.
                           Same element ASDL → a11y tree → screen reader output.
                           Change an element → a11y recompiles incrementally.
                           Same pattern, third output.
```

### 15.6 The pattern is the same

Every example above has the same shape:

```
1. Define the source ASDL          (what the user works with)
2. Define the events               (what can happen)
3. Write the reducer               (how state changes)
4. Write the phase transitions     (ASDL → ASDL, memoized)
5. Write the leaf compilers        (ASDL → native code, memoized)
6. Compose with Unit.compose       (aggregate children)
7. Connect to output with U.app    (poll → apply → compile → execute)
```

Seven steps. Same seven steps for a text editor, a spreadsheet, a vector graphics app, a game engine, and a UI toolkit. The domain changes. The ASDL types change. The leaf compilers change. The pattern does not.

And in every case, the same properties fall out for free:
- Incremental compilation (memoize + unique)
- Undo (previous tree + cache hit)
- Parallelism (ASDL graph = execution plan)
- Multiple outputs (different terminals, same source)
- Backend portability (target = memoize key)
- Hot-swap (atomic pointer replacement)
- Zero-alloc execution (one allocation per edit)
- Error boundaries (with_errors + semantic refs)

These are not features you implement. They are consequences of the six primitives composed correctly. The pattern is small. What it produces is not.


---


## 16. Summary

```
THE TERRA COMPILER PATTERN — FINAL FORM

PRIMITIVES (six concepts, one loop, every program):
    ASDL unique         what the program IS          (state)
    Event ASDL          what can HAPPEN              (input)
    Apply               how state CHANGES            (reducer)
    terralib.memoize    what DIDN'T change           (cache)
    Unit                what the machine DOES         (output)
    LuaFun              how everything is ENFORCED   (discipline)

THE LOOP:
    poll → apply → compile → execute
      ↑                         │
      └─────────────────────────┘

BOUNDARY WRAPPERS:
    transition()        memoized ASDL → ASDL
    terminal()          memoized ASDL → Unit
    with_fallback()     pcall + neutral
    with_errors()       per-item error collection

HELPERS:
    Unit.match          exhaustive runtime match on ASDL sums
    Unit.errors         structural error collection
    Unit.with           functional ASDL update
    Unit.hot_slot       hot-swappable render slot
    Unit.app            the universal event loop
    Unit.inspect        reflection-derived tooling from ASDL + methods

PROPERTIES (emergent, not designed):
    incremental compilation     memoize + unique
    state isolation             Unit owns its ABI
    state composition           Unit.compose embeds children
    code size control           memoize boundaries = call boundaries
    hot swap                    global + :set() + :getpointer()
    error boundaries            with_fallback + with_errors
    inspection tooling          Unit.inspect walks ASDL + methods
    zero-alloc playback         one terralib.new per edit
    undo = cache hit            memoize keeps old results
    live interactivity          Event ASDL + Apply + U.app
    parallelism                 ASDL graph = execution plan, no scheduler
    testing dissolves           pure + ASDL = testable by construction

LEVELS:
    compilation (Lua)           pure — same input, same output
    execution (Terra)           closed — mutates only owned state

PIPELINE:
    f(g(h(x)))                  function composition IS the pipeline

DEVELOPMENT FLOW:
    leaves-up                   write the leaf you want to write
                                fix the layer above to provide what it needs
                                recurse upward to the source ASDL
                                ASDL stabilizes when leaves stop demanding

IMPLEMENTATION SHAPE:
    small implementation        Unit + wrappers + helpers + event loop
    one file                    unit.t includes everything

BACKEND INTERFACE (five functions, per target):
    leaf(state_layout, body)    compile a leaf computation
    swap(slot, unit)            install a Unit on an output device
    poll() → Event              get input from the world
    start(name, callback)       register with an output driver
    alloc(state_layout)         allocate state for a Unit

    Terra + LLVM:   quotes → native code, struct types, pointer swap
    LuaJIT:         closures → traced Lua, FFI buffers, table swap
    JS + V8:        closures → JIT'd JS, Float64Array, postMessage
    WASM:           opcodes → .wasm binary, linear memory

    The pattern is a portable architecture.
    Terra is the best backend. It is not the only one.

WHAT DOESN'T EXIST:
    state management            memory management
    dispatch / vtables          configuration systems
    observer / events           dependency injection
    loading systems             serialization formats
    thread synchronization      build systems
    mocking / test doubles      test framework / harness
    test fixtures               regression suite
    execution planning          separate progress/docs infra
    incremental update tracking event bus / pub-sub
    application framework       error routing infrastructure

WHY:
    FP makes purity the default.
    Memoize makes impurity self-defeating.
    ASDL makes mutation unavailable.
    Events make the input exhaustive.
    Apply makes state changes pure.
    LuaFun makes purity enforceable — and tests the ASDL.
    Unit makes ABI ownership structural.
    Composition makes the pipeline implicit.
    LuaJIT makes the functional style free.
    LLVM makes the compiled output optimal.

    The architecture IS the composition.
    The discipline IS the framework.
    The pattern IS the program.
```
