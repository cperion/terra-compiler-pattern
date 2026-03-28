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
local InspectCore = require("unit_inspect_core")

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
-- Unit.leaf — one function, own state
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

function U.leaf(state_t, params, body)
    state_t = state_t or EMPTY
    params = params or terralib.newlist()

    if state_t == EMPTY then
        local fn = terra([params])
            [body(nil, params)]
        end
        return U.new(fn, EMPTY)
    end

    local s = symbol(&state_t, "state")
    local fn = terra([params], [s])
        [body(s, params)]
    end
    return U.new(fn, state_t)
end


-- ═══════════════════════════════════════════════════════════════
-- Unit.compose — aggregate children's state
--
-- For a node that owns the combined state of its children.
-- Builds a struct with one field per non-empty child state.
-- Provides a .call(...) helper on each child for correct dispatch.
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

function U.compose(children, params, body)
    params = params or terralib.newlist()

    -- Build the composed state struct
    local S = terralib.types.newstruct("ComposedState")
    local kids = {}
    local field_count = 0

    for i, child in ipairs(children) do
        kids[i] = {
            fn       = child.fn,
            state_t  = child.state_t,
            has_state = child.state_t ~= EMPTY,
        }
        if child.state_t ~= EMPTY then
            field_count = field_count + 1
            local f = "s" .. field_count
            S.entries:insert({ field = f, type = child.state_t })
            kids[i].field = f
        end
    end

    -- If all children are stateless, the composed state is empty
    if field_count == 0 then S = EMPTY end

    -- Create the state symbol and resolve child state pointers
    local s = S ~= EMPTY and symbol(&S, "state") or nil

    for _, k in ipairs(kids) do
        -- Resolve state expression: a pointer into the parent struct
        if k.field and s then
            local f = k.field
            k.state_expr = `&(@[s]).[f]
        else
            k.state_expr = nil
        end

        -- The call helper: dispatches fn with correct state pointer
        -- Usage in body: emit(kid.call(buf, n))
        k.call = function(...)
            local args = terralib.newlist({...})
            if k.state_expr then
                return quote [k.fn]([args], [k.state_expr]) end
            else
                return quote [k.fn]([args]) end
            end
        end
    end

    -- Build the composed function
    local unit
    if s then
        unit = U.new(
            terra([params], [s]) [body(s, kids, params)] end, S)
    else
        unit = U.new(
            terra([params]) [body(nil, kids, params)] end, EMPTY)
    end

    unit.children = children
    unit.__composed_kids = kids

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

    return unit
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

function U.memoize(fn)
    return terralib.memoize(fn)
end

-- transition: memoized ASDL → ASDL transform
-- The workhorse. Phase narrowing. Knowledge consumed.
function U.transition(fn)
    return U.memoize(fn)
end

-- terminal: memoized ASDL → Unit compilation
-- Unit.new already validates ABI + calls fn:compile().
function U.terminal(fn)
    return U.memoize(fn)
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

function U.inspect(ctx, phases, pipeline_phases)
    local H = InspectCore.new(U)

    phases = phases or H.discover_phases(ctx)
    if #phases == 0 then phases = H.discover_phases(ctx) end
    pipeline_phases = pipeline_phases or phases

    local I = {
        ctx = ctx,
        phases = phases,
        pipeline_phases = pipeline_phases,
        types = {},
        type_map = {},
        boundaries = {},
    }

    local class_map = {}

    -- Inventory types by phase.
    U.each(phases, function(phase_name)
        local ns = ctx[phase_name]
        if type(ns) == "table" then
            U.each(H.sorted_class_names(ns), function(name)
                local class = ns[name]
                local fqname = phase_name .. "." .. name
                local t = {
                    phase = phase_name,
                    name = name,
                    fqname = fqname,
                    class = class,
                    kind = "record",
                    fields = class.__fields or {},
                    variants = {},
                    variant_types = {},
                    methods = {},
                }
                I.types[#I.types + 1] = t
                I.type_map[fqname] = t
                class_map[class] = t
                class.__name = class.__name or fqname
            end)
        end
    end)

    -- Derive enum metadata from ASDL parent.members.
    U.each(I.types, function(t)
        local variant_entries = {}
        if type(t.class.members) == "table" then
            U.each(t.class.members, function(member)
                if member ~= t.class then
                    local variant_t = class_map[member]
                    variant_entries[#variant_entries + 1] = {
                        class = member,
                        type = variant_t,
                        name = (variant_t and variant_t.name)
                            or member.kind
                            or H.basename(member.__name)
                            or tostring(member),
                    }
                end
            end)
        end

        table.sort(variant_entries, function(a, b)
            return a.name < b.name
        end)

        if #variant_entries > 0 and not t.class.__fields then
            t.kind = "enum"
            U.each(variant_entries, function(entry)
                local i = #t.variants + 1
                t.variants[i] = entry.name
                t.variant_types[i] = entry.type
                entry.class.__sum_parent = t.class
            end)
            t.class.__variants = t.variants
        end
    end)

    -- Discover installed methods.
    -- Sum-type parent methods are copied onto child variant classes by ASDL.
    -- Skip those inherited duplicates so Device:lower() appears once on the
    -- sum parent, not once per variant, unless a variant overrides it.
    U.each(I.types, function(t)
        local method_names = {}
        local parent = t.class.__sum_parent
        U.each(U.each_name({ t.class }), function(name)
            local fn = t.class[name]
            if H.is_public_method(name, fn)
                and not (parent and parent[name] == fn) then
                method_names[#method_names + 1] = name
            end
        end)
        t.methods = method_names

        U.each(method_names, function(name)
            I.boundaries[#I.boundaries + 1] = {
                receiver = t.fqname,
                receiver_name = t.name,
                name = name,
                fn = t.class[name],
                phase = t.phase,
                type = t,
            }
        end)
    end)

    H.sort_boundaries(I.boundaries)

    local function find_boundary(boundary_name)
        return H.find_boundary(I.boundaries, boundary_name)
    end

    local function is_stub(boundary)
        return H.is_stub(boundary)
    end

    local function resolve_type_name(type_name, phase_name)
        return H.resolve_type_name(I.type_map, type_name, phase_name)
    end

    local function direct_refs(t)
        return H.direct_refs(I.type_map, function(type_name, phase_name)
            return resolve_type_name(type_name, phase_name)
        end, t)
    end

    function I.find_boundary(boundary_name)
        return H.find_boundary(I.boundaries, boundary_name)
    end

    function I.resolve_type_name(type_name, phase_name)
        return resolve_type_name(type_name, phase_name)
    end

    function I.is_stub(boundary)
        return H.is_stub(boundary)
    end

    function I.progress()
        local info = {
            boundary_total = #I.boundaries,
            boundary_real = 0,
            boundary_stub = 0,
            boundary_coverage = 0,
            type_total = #I.types,
            record_total = 0,
            enum_total = 0,
            variant_total = 0,
            by_phase = {},
        }

        U.each(phases, function(phase_name)
            info.by_phase[phase_name] = H.new_phase_bucket()
        end)

        U.each(I.types, function(t)
            local phase = H.ensure_phase_bucket(info.by_phase, t.phase)

            phase.type_total = phase.type_total + 1
            if t.kind == "enum" then
                phase.enum_total = phase.enum_total + 1
                phase.variant_total = phase.variant_total + #t.variants
                info.enum_total = info.enum_total + 1
                info.variant_total = info.variant_total + #t.variants
            else
                phase.record_total = phase.record_total + 1
                info.record_total = info.record_total + 1
            end
        end)

        U.each(I.boundaries, function(b)
            local phase = H.ensure_phase_bucket(info.by_phase, b.phase)

            phase.boundary_total = phase.boundary_total + 1
            if is_stub(b) then
                phase.boundary_stub = phase.boundary_stub + 1
                info.boundary_stub = info.boundary_stub + 1
            else
                phase.boundary_real = phase.boundary_real + 1
                info.boundary_real = info.boundary_real + 1
            end
        end)

        U.each(phases, function(phase_name)
            local phase = info.by_phase[phase_name]
            if phase and phase.boundary_total > 0 then
                phase.boundary_coverage = phase.boundary_real / phase.boundary_total
            end
        end)

        if info.boundary_total > 0 then
            info.boundary_coverage = info.boundary_real / info.boundary_total
        end

        return info
    end

    function I.pipeline()
        local counts_by_phase = {}

        for _, b in ipairs(I.boundaries) do
            local counts = counts_by_phase[b.phase]
            if not counts then
                counts = {}
                counts_by_phase[b.phase] = counts
            end
            counts[b.name] = (counts[b.name] or 0) + 1
        end

        local edges = {}
        for i = 1, #pipeline_phases - 1 do
            local from = pipeline_phases[i]
            local to = pipeline_phases[i + 1]
            local counts = counts_by_phase[from] or {}
            local names = U.each_name({ counts })

            local verb = "?"
            local best = -1
            U.each(names, function(name)
                local count = counts[name]
                if count > best then
                    best = count
                    verb = name
                end
            end)

            edges[#edges + 1] = {
                from = from,
                to = to,
                verb = verb,
                count = best > 0 and best or 0,
            }
        end

        return edges
    end

    function I.type_graph(root_type, max_depth)
        return H.render_type_graph(
            I.type_map,
            function(type_name, phase_name)
                return resolve_type_name(type_name, phase_name)
            end,
            root_type,
            max_depth)
    end

    function I.prompt_for(boundary_name, max_depth)
        local b = H.find_boundary(I.boundaries, boundary_name)
        if not b then
            return "boundary not found: " .. tostring(boundary_name)
        end

        local child_items = H.collect_prompt_child_items(
            I.boundaries,
            function(t) return direct_refs(t) end,
            b)

        local sections = {}
        H.append_prompt_sections(
            sections,
            b,
            I.type_graph(b.receiver, max_depth or 3),
            child_items)

        return table.concat(sections, "\n\n")
    end

    function I.markdown()
        local lines = { "# Schema Documentation", "" }

        U.each(phases, function(phase_name)
            H.append_phase_markdown(lines, phase_name, I.types, I.boundaries)
        end)

        return table.concat(lines, "\n")
    end

    function I.test_all()
        local results = {}
        local passed = 0

        U.each(I.boundaries, function(b)
            local result = {
                boundary = b.receiver .. ":" .. b.name,
                exists = type(b.fn) == "function",
                stub = H.is_stub(b),
            }
            results[#results + 1] = result
            if result.exists and not result.stub then
                passed = passed + 1
            end
        end)

        return {
            results = results,
            passed = passed,
            total = #results,
        }
    end

    function I.scaffold(boundary_name)
        local b = H.find_boundary(I.boundaries, boundary_name)
        if not b then return nil end

        local t = b.type
        local lines = {
            "local U = require 'unit'",
            "",
            "-- " .. b.receiver .. ":" .. b.name .. "()",
            "-- Phase: " .. b.phase,
            "",
            "function " .. t.name .. ":" .. b.name .. "()",
        }

        if t.kind == "enum" then
            H.append_enum_scaffold(lines, t.variants)
            return table.concat(lines, "\n")
        end

        local child_calls = H.collect_record_scaffold_calls(
            I.type_map,
            function(type_name, phase_name)
                return resolve_type_name(type_name, phase_name)
            end,
            t,
            b.name)

        H.append_record_scaffold(lines, b.name, child_calls)
        return table.concat(lines, "\n")
    end

    function I.status()
        return H.render_status(I.progress(), phases)
    end

    return I
end


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
--   - ASDL lives in real .t modules that return strings
--   - one real schema module returns U.spec { ... }
--   - install boundary methods onto T.Phase.Type inside install = function(T)
--   - use U.install_stubs(T, plan) to install whole families of stub methods
--   - point the CLI at that schema module
--
-- Minimal example:
--
--   local U = require("unit")
--
--   local function stub(name)
--       return function(...)
--           error(name .. " not implemented", 2)
--       end
--   end
--
--   return U.spec {
--       texts = {
--           require("examples.foo.foo_asdl"),
--       },
--       pipeline = {
--           "Foo",
--           "Bar",
--       },
--       install = function(T)
--           U.install_stubs(T, {
--               ["Foo"] = "lower",
--               ["Bar.Scene"] = "compile",
--           })
--       end,
--   }
--
-- Then:
--   terra unit.t status examples/foo/foo_schema.t
--   terra unit.t boundaries examples/foo/foo_schema.t
--   terra unit.t scaffold examples/foo/foo_schema.t Foo.Node:lower
--
-- Thin reflection CLI over U.inspect(ctx, phases, pipeline).
-- No registry, no extra DSL, just a loader that returns:
--   { ctx = T, phases = {...}, pipeline = {...} }
-- or a U.spec { ... } config/result
-- or a function(U) -> one of those
-- or (ctx, phases)
-- ═══════════════════════════════════════════════════════════════

function U.read_file(path)
    local f, err = io.open(path, "rb")
    if not f then error(err or ("cannot open file: " .. tostring(path)), 2) end
    local text = assert(f:read("*a"))
    f:close()
    return text
end

function U.normalize_asdl_text(text)
    if type(text) ~= "string" then
        error("U.normalize_asdl_text: text must be a string", 2)
    end

    return (("\n" .. text):gsub("(\n[ \t]*)%-%-", "%1#")):sub(2)
end

function U.read_asdl_file(path)
    return U.normalize_asdl_text(U.read_file(path))
end

function U.is_asdl_class(value)
    return type(value) == "table"
        and type(value.isclassof) == "function"
end

function U.stub(boundary_name)
    return function(...)
        error((boundary_name or "boundary") .. " not implemented", 2)
    end
end

-- Install stub methods onto ASDL classes.
--
-- plan forms:
--   { ["TaskView"] = "lower" }
--   { ["TaskApp.State"] = { "apply", "project_view" } }
--
-- Namespace keys install onto all top-level classes in that namespace.
-- Fully qualified type keys install onto one exact ASDL class.
function U.install_stubs(ctx, plan)
    if type(ctx) ~= "table" then
        error("U.install_stubs: ctx must be an ASDL context", 2)
    end
    if type(plan) ~= "table" then
        error("U.install_stubs: plan must be a table", 2)
    end

    local function normalize_verbs(value)
        if type(value) == "string" then
            return { value }
        end
        if type(value) == "table" and value[1] ~= nil then
            return value
        end
        error("U.install_stubs: plan values must be a verb string or verb list", 3)
    end

    local function classes_in_namespace(phase_name)
        local ns = ctx[phase_name]
        if type(ns) ~= "table" then
            error("U.install_stubs: unknown namespace '" .. tostring(phase_name) .. "'", 3)
        end

        local out = {}
        U.each(U.each_name({ ns }), function(name)
            local class = ns[name]
            if U.is_asdl_class(class)
                and not class.__sum_parent
                and not class.kind then
                out[#out + 1] = {
                    fqname = phase_name .. "." .. name,
                    class = class,
                }
            end
        end)
        return out
    end

    local function resolve_target(target)
        if type(target) ~= "string" then
            error("U.install_stubs: plan keys must be namespace or fully qualified type strings", 3)
        end

        if target:find(".", 1, true) then
            local class = ctx.definitions and ctx.definitions[target]
            if not U.is_asdl_class(class) then
                error("U.install_stubs: unknown ASDL type '" .. tostring(target) .. "'", 3)
            end
            return {
                {
                    fqname = target,
                    class = class,
                }
            }
        end

        return classes_in_namespace(target)
    end

    local targets = U.each_name({ plan })

    U.each(targets, function(target)
        local verbs = normalize_verbs(plan[target])
        local classes = resolve_target(target)
        U.each(classes, function(info)
            U.each(verbs, function(verb)
                info.class[verb] = U.stub(info.fqname .. ":" .. verb)
            end)
        end)
    end)

    return ctx
end

function U.spec(config)
    if type(config) ~= "table" then
        error("U.spec: config must be a table", 2)
    end

    local asdl = require("asdl")
    local ctx = config.ctx or asdl.NewContext()

    local function define_asdl(source_name, text)
        local ok, err = pcall(function()
            ctx:Define(text)
        end)
        if ok then return end

        local msg = tostring(err)
        if msg:match("class name already defined") then
            error((
                "U.spec: ASDL source '%s' is not raw-terra-ASDL-compatible. "
                .. "This usually means two sum constructors in the same module "
                .. "share a name (for example Auto/Start/Center across multiple sums). "
                .. "Current terra/src/asdl.lua requires constructor class names to be unique within a module. "
                .. "You need an ASDL-module lowering pass that qualifies constructors before T:Define(...).\n\n"
                .. "Original error: %s"
            ):format(tostring(source_name), msg), 2)
        end

        error(err, 2)
    end

    if type(config.file) == "string" then
        define_asdl(config.file, U.read_asdl_file(config.file))
    end

    if type(config.text) == "string" then
        define_asdl("<inline text>", U.normalize_asdl_text(config.text))
    end

    if type(config.files) == "table" then
        for _, path in ipairs(config.files) do
            define_asdl(path, U.read_asdl_file(path))
        end
    end

    if type(config.texts) == "table" then
        for i, text in ipairs(config.texts) do
            define_asdl("<inline text #" .. tostring(i) .. ">", U.normalize_asdl_text(text))
        end
    end

    local function run_installer(inst)
        if type(inst) == "function" then
            return inst(ctx, U, config)
        end
        if type(inst) == "string" then
            local mod = require(inst)
            if type(mod) == "function" then
                return mod(ctx, U, config)
            end
            if type(mod) == "table" and type(mod.install) == "function" then
                return mod.install(ctx, U, config)
            end
            error("U.spec: installer module must return a function or { install = fn }", 3)
        end
        if type(inst) == "table" and type(inst.install) == "function" then
            return inst.install(ctx, U, config)
        end
        error("U.spec: installer must be a function, module name, or { install = fn }", 3)
    end

    if config.install ~= nil then
        if type(config.install) == "table" and config.install[1] ~= nil then
            for _, inst in ipairs(config.install) do
                run_installer(inst)
            end
        else
            run_installer(config.install)
        end
    end

    return {
        ctx = ctx,
        phases = config.phases,
        pipeline = config.pipeline,
    }
end

function U.load_inspect_spec(source)
    if type(source) ~= "string" or source == "" then
        error("U.load_inspect_spec: source must be a non-empty string", 2)
    end

    local function normalize(a, b)
        if type(a) == "function" and b == nil then
            return normalize(a(U))
        end

        if type(a) == "table" and type(a.inspect) == "function"
            and (a.ctx == nil or a.phases == nil) then
            local ctx, phases = a.inspect(U)
            return normalize(ctx, phases)
        end

        if type(a) == "table" and (a.files or a.file or a.texts or a.text or a.install)
            and a.ctx == nil then
            return U.spec(a)
        end

        if type(a) == "table" and a.ctx then
            return {
                ctx = a.ctx,
                phases = a.phases,
                pipeline = a.pipeline,
            }
        end

        if a ~= nil and type(b) == "table" then
            return {
                ctx = a,
                phases = b,
            }
        end

        error(
            "inspect spec must return { ctx = ..., phases = {...} }, "
            .. "a U.spec(...) config table, "
            .. "a function(U) -> one of those, or (ctx, phases)",
            3)
    end

    local function load_from_path(path)
        local ok_t, chunk_t = pcall(terralib.loadfile, path)
        if ok_t and type(chunk_t) == "function" then
            return normalize(chunk_t())
        end

        local chunk_lua, err_lua = loadfile(path)
        if not chunk_lua then
            error(err_lua or tostring(chunk_t), 3)
        end
        return normalize(chunk_lua())
    end

    local looks_like_path = source:find("/", 1, true)
        or source:find("\\", 1, true)
        or source:match("%.t$")
        or source:match("%.lua$")

    if looks_like_path then
        return load_from_path(source)
    end

    return normalize(require(source))
end

function U.inspect_from(source)
    local spec = U.load_inspect_spec(source)
    return U.inspect(spec.ctx, spec.phases, spec.pipeline)
end

function U.cli_usage()
    return table.concat({
        "usage: terra unit.t <command> <spec> [args...]",
        "",
        "commands:",
        "  status <spec>",
        "  markdown <spec>",
        "  pipeline <spec>",
        "  boundaries <spec>",
        "  type-graph <spec> <root> [max_depth]",
        "  prompt <spec> <boundary> [max_depth]",
        "  scaffold <spec> <boundary>",
        "  scaffold-all <spec>",
        "  test-all <spec>",
        "",
        "spec forms:",
        "  - path/module returning { ctx = T, phases = {...}, pipeline = {...} }",
        "  - path/module returning U.spec{ texts/files = {...}, install = ..., pipeline = {...} }",
        "  - path/module returning function(U) -> one of those",
        "  - path/module returning (ctx, phases)",
    }, "\n")
end

function U.cli(argv)
    argv = argv or rawget(_G, "arg") or {}

    local command = argv[1]
    if not command or command == "help" or command == "--help" or command == "-h" then
        io.write(U.cli_usage(), "\n")
        return 0
    end

    local spec_source = argv[2]
    if not spec_source then
        error("unit CLI: missing <spec>.\n\n" .. U.cli_usage(), 2)
    end

    local I = U.inspect_from(spec_source)

    if command == "status" then
        io.write(I.status(), "\n")
        return 0
    end

    if command == "markdown" then
        io.write(I.markdown(), "\n")
        return 0
    end

    if command == "pipeline" then
        for _, edge in ipairs(I.pipeline()) do
            io.write(string.format(
                "%s -%s[%d]-> %s\n",
                edge.from, edge.verb, edge.count, edge.to))
        end
        return 0
    end

    if command == "boundaries" then
        for _, b in ipairs(I.boundaries) do
            io.write(b.receiver, ":", b.name, "()\n")
        end
        return 0
    end

    if command == "type-graph" then
        local root = argv[3]
        if not root then
            error("unit CLI: type-graph requires <root>", 2)
        end
        local max_depth = tonumber(argv[4]) or 3
        io.write(I.type_graph(root, max_depth), "\n")
        return 0
    end

    if command == "prompt" then
        local boundary = argv[3]
        if not boundary then
            error("unit CLI: prompt requires <boundary>", 2)
        end
        local max_depth = tonumber(argv[4]) or 3
        io.write(I.prompt_for(boundary, max_depth), "\n")
        return 0
    end

    if command == "scaffold" then
        local boundary = argv[3]
        if not boundary then
            error("unit CLI: scaffold requires <boundary>", 2)
        end
        local scaffold = I.scaffold(boundary)
        if not scaffold then
            error("unit CLI: boundary not found: " .. tostring(boundary), 2)
        end
        io.write(scaffold, "\n")
        return 0
    end

    if command == "scaffold-all" then
        for i, b in ipairs(I.boundaries) do
            local name = b.receiver .. ":" .. b.name
            local scaffold = I.scaffold(name)
            if scaffold then
                if i > 1 then io.write("\n", string.rep("-", 72), "\n\n") end
                io.write("-- ", name, "\n")
                io.write(scaffold, "\n")
            end
        end
        return 0
    end

    if command == "test-all" then
        local results = I.test_all()
        io.write(string.format(
            "passed %d/%d\n",
            results.passed,
            results.total))
        for _, r in ipairs(results.results) do
            local status = r.exists and (r.stub and "stub" or "real") or "missing"
            io.write("- ", r.boundary, " : ", status, "\n")
        end
        return 0
    end

    error("unit CLI: unknown command '" .. tostring(command) .. "'", 2)
end

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
