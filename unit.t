-- unit.t
--
-- The Terra Compiler Pattern — Final Form
--
-- Six primitives. No framework. The architecture IS the composition.
--
-- ASDL unique     → structural identity (state)
-- Event ASDL      → what can happen (input)
-- Apply           → (state, event) → state (reducer)
-- terralib.memoize → identity-based caching
-- Unit            → compile product { fn, state_t } (output)
-- LuaFun          → functional transforms (glue)
--
-- The loop: poll → apply → compile → execute
--           ↑                        │
--           └────────────────────────┘

local U = require("unit_core").new()

-- ═══════════════════════════════════════════════════════════════
-- The empty state type. tuple() with same args returns same type.
-- Used for stateless Units (pure functions with no history).
-- ═══════════════════════════════════════════════════════════════

local EMPTY = tuple()
U.EMPTY = EMPTY


-- ═══════════════════════════════════════════════════════════════
-- Unit.new — the validated constructor
--
-- Every Unit passes through here. Three invariants enforced:
--   1. fn is a Terra function
--   2. if state_t is non-empty, fn takes &state_t (ABI ownership)
--   3. fn:compile() called immediately (LLVM runs here, not later)
-- ═══════════════════════════════════════════════════════════════

function U.new(fn, state_t)
    state_t = state_t or EMPTY

    -- Invariant 1: fn must be a Terra function
    if not terralib.isfunction(fn) then
        error("Unit.new: fn must be a Terra function, got "
            .. tostring(type(fn)), 2)
    end

    -- Invariant 2: fn must accept &state_t if state is non-empty
    if state_t ~= EMPTY then
        if not terralib.types.istype(state_t) then
            error("Unit.new: state_t must be a Terra type, got "
                .. tostring(type(state_t)), 2)
        end
        local ptr_t = &state_t
        local params = fn:gettype().parameters
        local found = false
        for _, p in ipairs(params) do
            if p == ptr_t then found = true; break end
        end
        if not found then
            error("Unit.new: fn must take &state_t as a parameter. "
                .. "The function must own its ABI. Got fn type: "
                .. tostring(fn:gettype()), 2)
        end
    end

    -- Invariant 3: force LLVM compilation now
    fn:compile()

    return { fn = fn, state_t = state_t }
end


-- ═══════════════════════════════════════════════════════════════
-- Unit.silent — the neutral element
--
-- A no-op function with empty state. The identity for composition.
-- Used as the fallback when compilation fails: the pipeline
-- continues, the failed node is silence, everything else plays.
-- ═══════════════════════════════════════════════════════════════

function U.silent()
    return U.new(terra() end, EMPTY)
end


-- ═══════════════════════════════════════════════════════════════
-- Unit.leaf — normalized backend-agnostic leaf packaging
--
-- The architectural contract is the same across backends:
--   U.leaf(state_t, fn) -> Unit { fn, state_t }
--
-- Terra-specific quote building lives in U.leaf_quote(...), which realizes
-- the backend-native Terra function first and then packages it through U.leaf.
-- ═══════════════════════════════════════════════════════════════

function U.leaf(state_t, fn)
    return U.new(fn, state_t or EMPTY)
end


-- ═══════════════════════════════════════════════════════════════
-- Unit.leaf_quote — Terra-specific leaf realization helper
--
-- For a node that owns its own persistent state (e.g. an
-- oscillator phase accumulator, a filter history).
--
-- state_t:  a Terra struct, or nil for stateless
-- params:   a terralib.newlist of Terra symbols for the fn params
-- body:     function(state_sym, params) → Terra quote
--           state_sym is a symbol of type &state_t (or nil if stateless)
--           params is the same list passed in
--
-- The resulting fn signature:
--   if stateful:  terra(params..., state: &state_t)
--   if stateless: terra(params...)
-- ═══════════════════════════════════════════════════════════════

function U.leaf_quote(state_t, params, body)
    state_t = state_t or EMPTY
    params = params or terralib.newlist()

    if state_t == EMPTY then
        local fn = terra([params])
            [body(nil, params)]
        end
        return U.leaf(EMPTY, fn)
    end

    local s = symbol(&state_t, "state")
    local fn = terra([params], [s])
        [body(s, params)]
    end
    return U.leaf(state_t, fn)
end


local function build_compose_layout(children)
    local S = terralib.types.newstruct("ComposedState")
    local kids = {}
    local field_count = 0

    for i, child in ipairs(children) do
        kids[i] = {
            fn = child.fn,
            state_t = child.state_t,
            has_state = child.state_t ~= EMPTY,
        }
        if child.state_t ~= EMPTY then
            field_count = field_count + 1
            local f = "s" .. field_count
            S.entries:insert({ field = f, type = child.state_t })
            kids[i].field = f
        end
    end

    if field_count == 0 then S = EMPTY end
    return S, kids
end

function U.state_compose(children)
    local S = build_compose_layout(children or {})
    return S
end

local attach_compose_lifecycle

local function package_compose(children, fn, S, kids)
    local unit = U.new(fn, S)
    unit.children = children
    unit.__composed_kids = kids
    attach_compose_lifecycle(unit, children, kids, S)
    return unit
end

attach_compose_lifecycle = function(unit, children, kids, S)
    local has_child_init = false
    local has_child_release = false
    for _, child in ipairs(children) do
        has_child_init = has_child_init or (child.state_t ~= EMPTY and child.init ~= nil)
        has_child_release = has_child_release or (child.state_t ~= EMPTY and child.release ~= nil)
    end

    if has_child_init and S ~= EMPTY then
        unit.init = function(state)
            for i, child in ipairs(children) do
                local kid = kids[i]
                if child.state_t ~= EMPTY and child.init and kid.field then
                    child.init(state[kid.field])
                end
            end
        end
    end

    if has_child_release and S ~= EMPTY then
        unit.release = function(state)
            for i = #children, 1, -1 do
                local child = children[i]
                local kid = kids[i]
                if child.state_t ~= EMPTY and child.release and kid.field then
                    child.release(state[kid.field])
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Unit.compose — normalized backend-agnostic compose packaging
--
-- The architectural contract is:
--   U.compose(children, fn) -> Unit { fn, composed_state_t }
--
-- Terra-specific quote building lives in U.compose_quote(...), which realizes
-- the backend-native Terra function first and then packages it through
-- U.compose.
-- ═══════════════════════════════════════════════════════════════

function U.compose(children, fn)
    children = children or {}
    if not terralib.isfunction(fn) then
        error("U.compose: fn must be a Terra function", 2)
    end

    local S, kids = build_compose_layout(children)
    return package_compose(children, fn, S, kids)
end


-- ═══════════════════════════════════════════════════════════════
-- Unit.compose_quote — Terra-specific composition realization helper
--
-- children: a list of Units (each with fn and state_t)
-- params:   a terralib.newlist of Terra symbols
-- body:     function(state_sym, annotated_children, params) → Terra quote
--
-- Each annotated child has:
--   .fn         the child's compiled function
--   .state_t    the child's state type
--   .has_state  boolean
--   .state_expr Terra quote &state.s_N (or nil if stateless)
--   .call(...)  dispatches with correct state pointer
-- ═══════════════════════════════════════════════════════════════

function U.compose_quote(children, params, body)
    children = children or {}
    params = params or terralib.newlist()

    local S, kids = build_compose_layout(children)
    local s = S ~= EMPTY and symbol(&S, "state") or nil

    for _, k in ipairs(kids) do
        if k.field and s then
            local f = k.field
            k.state_expr = `&(@[s]).[f]
        else
            k.state_expr = nil
        end

        k.call = function(...)
            local args = terralib.newlist({...})
            if k.state_expr then
                return quote [k.fn]([args], [k.state_expr]) end
            else
                return quote [k.fn]([args]) end
            end
        end
    end

    local fn
    if s then
        fn = terra([params], [s]) [body(s, kids, params)] end
    else
        fn = terra([params]) [body(nil, kids, params)] end
    end

    return package_compose(children, fn, S, kids)
end


-- ═══════════════════════════════════════════════════════════════
-- COMPOSITION WRAPPERS
-- These are the boundary vocabulary. Each wraps a function
-- with the appropriate contract.
--
-- The backend-independent versions of with_fallback / with_errors /
-- errors / match / with now live in unit_core.lua.
-- Terra keeps ownership of memoize / transition / terminal because
-- they must use terralib.memoize identity caching.
-- ═══════════════════════════════════════════════════════════════

function U.memoize(name_or_fn, maybe_fn)
    return U._memoize_with(terralib.memoize, "memoize", name_or_fn, maybe_fn)
end

-- transition: memoized ASDL → ASDL transform
-- The workhorse. Phase narrowing. Knowledge consumed.
function U.transition(name_or_fn, maybe_fn)
    return U._memoize_with(terralib.memoize, "transition", name_or_fn, maybe_fn)
end

-- terminal: memoized ASDL → Unit compilation
-- Unit.new already validates ABI + calls fn:compile().
function U.terminal(name_or_fn, maybe_fn)
    return U._memoize_with(terralib.memoize, "terminal", name_or_fn, maybe_fn)
end


-- ═══════════════════════════════════════════════════════════════
-- INSPECTION
--
-- QoL derived from the ASDL context plus installed methods.
-- No separate DSL. No parser. Just reflection on the objects that
-- already exist.
--
-- Usage:
--   local I = U.inspect(T, {"Editor", "Authored", "Scheduled"})
--   print(I.status())
--   print(I.markdown())
--   print(I.prompt_for("Editor.Track:lower"))
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- HOT SWAP HELPERS
--
-- Convenience for the global pointer swap pattern.
-- The audio callback reads from globals. The edit path writes.
-- ═══════════════════════════════════════════════════════════════

-- Create a hot-swappable render slot.
-- Returns: { callback, swap }
--   callback: a Terra function to register with the audio driver
--   swap:     a Lua function that takes a Unit and installs it
--
-- fn_type: the Terra function type for the render function
--          e.g. {&float, &float, int32} -> {}
--
-- Usage:
--   local slot = U.hot_slot({&float, &float, int32} -> {})
--   jack_set_callback(slot.callback:getpointer())
--   -- On edit:
--   slot.swap(compile_session(new_project))
function U.hot_slot(fn_type)
    local render_ptr = global(fn_type)
    local state_ptr = global(&uint8)

    -- Install a silent initial function
    local silent = U.silent()
    render_ptr:set(silent.fn:getpointer())

    -- The audio callback: reads globals, calls through pointer.
    -- Compiled ONCE. Never changes. Registered with the driver.
    local params = terralib.newlist()
    local param_types = fn_type.type.parameters
    for i, pt in ipairs(param_types) do
        params:insert(symbol(pt, "p" .. i))
    end

    local callback = terra([params])
        render_ptr([params], state_ptr)
    end
    callback:compile()

    return {
        callback = callback,
        swap = function(unit)
            local new_state = terralib.new(unit.state_t)
            state_ptr:set(terralib.cast(&uint8, new_state))
            render_ptr:set(unit.fn:getpointer())
            return new_state
        end,
        render_ptr = render_ptr,
        state_ptr = state_ptr,
    }
end


-- ═══════════════════════════════════════════════════════════════
-- U.app — the universal application loop
--
-- Every program is:
--   poll → apply → compile → execute
--
-- poll:     OS → events
-- apply:    (state, event) → state     pure, functional
-- compile:  state → Unit per output    memoized, incremental
-- execute:  Unit → device              native, zero-dispatch
--
-- config:
--   initial()            → initial ASDL state
--   outputs              → { name = fn_type, ... }
--   compile              → { name = compiler_fn, ... }
--   start                → { name = start_fn(driver_callback), ... }
--   stop                 → { name = stop_fn, ... }  (optional)
--   poll()               → event or nil
--   apply(state, event)  → new_state
-- ═══════════════════════════════════════════════════════════════

function U.app(config)
    -- Create hot-swap slots for each output device
    local slots = {}
    for name, fn_type in pairs(config.outputs) do
        slots[name] = U.hot_slot(fn_type)
    end

    -- Initial state
    local state = config.initial()

    -- Initial compilation — all outputs
    for name, compiler in pairs(config.compile) do
        if slots[name] then
            slots[name]:swap(compiler(state))
        end
    end

    -- Start output drivers
    for name, start_fn in pairs(config.start) do
        if slots[name] then
            start_fn(slots[name].callback:getpointer())
        end
    end

    -- The loop
    while state.running ~= false do
        local event = config.poll()
        if not event then break end

        local new_state = config.apply(state, event)

        if new_state ~= state then
            state = new_state
            -- Recompile only changed outputs
            -- (memoize handles per-output incrementality)
            for name, compiler in pairs(config.compile) do
                if slots[name] then
                    slots[name]:swap(compiler(state))
                end
            end
        end
    end

    -- Cleanup
    if config.stop then
        for name, stop_fn in pairs(config.stop) do
            if slots[name] then
                stop_fn()
            end
        end
    end

    return state
end


-- ═══════════════════════════════════════════════════════════════
-- CLI helpers + schema installation bootstrap
--
-- Keep this simple:
--   - ASDL lives in schema/*.asdl, schema/*.lua, or schema/*.t files
--   - project directories are the primary CLI source
--   - install boundary methods onto T.Phase.Type from boundaries/*.lua
--   - use U.install_stubs(T, plan) to install truthful stub inventories
--   - point the CLI at the project directory or a direct .asdl file
--
-- Minimal project shape:
--
--   examples/foo/
--     schema/
--       app.asdl
--     pipeline.lua
--     boundaries/
--       Foo_Node.lua
--
-- Then:
--   terra unit.t status examples/foo
--   terra unit.t boundaries examples/foo
--   terra unit.t scaffold-file examples/foo Foo.Node
--
-- Thin reflection CLI over U.inspect(ctx, phases, pipeline).
-- No registry, no extra DSL, just project loading plus inspection.
-- ═══════════════════════════════════════════════════════════════

require("unit_schema").install(U)

local function _unit_running_as_main()
    local argv = rawget(_G, "arg")
    local script = argv and argv[0]
    if not script then return false end
    local base = tostring(script):match("([^/\\]+)$") or tostring(script)
    return base == "unit.t" or base == "unit.lua"
end

if _unit_running_as_main() then
    package.loaded["unit"] = U

    local ok, result = xpcall(function()
        return U.cli(rawget(_G, "arg"))
    end, debug.traceback)

    if not ok then
        io.stderr:write(result, "\n")
        os.exit(1)
    end

    if type(result) == "number" and result ~= 0 then
        os.exit(result)
    end
end


-- ═══════════════════════════════════════════════════════════════
-- MODULE
-- ═══════════════════════════════════════════════════════════════

return U
