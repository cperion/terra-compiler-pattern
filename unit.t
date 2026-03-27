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

local U = {}

-- ═══════════════════════════════════════════════════════════════
-- The empty state type. tuple() with same args returns same type.
-- Used for stateless Units (pure functions with no history).
-- ═══════════════════════════════════════════════════════════════

local EMPTY = tuple()
U.EMPTY = EMPTY

local unpack_fn = table.unpack or unpack


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
    if s then
        return U.new(
            terra([params], [s]) [body(s, kids, params)] end, S)
    else
        return U.new(
            terra([params]) [body(nil, kids, params)] end, EMPTY)
    end
end


-- ═══════════════════════════════════════════════════════════════
-- COMPOSITION WRAPPERS
-- These are the boundary vocabulary. Each wraps a function
-- with the appropriate contract.
-- ═══════════════════════════════════════════════════════════════

-- transition: memoized ASDL → ASDL transform
-- The workhorse. Phase narrowing. Knowledge consumed.
function U.transition(fn)
    return terralib.memoize(fn)
end

-- terminal: memoized ASDL → Unit compilation
-- Unit.new already validates ABI + calls fn:compile().
function U.terminal(fn)
    return terralib.memoize(fn)
end

-- with_fallback: pcall + neutral substitution on failure
-- On throw: returns the neutral value. Pipeline continues.
function U.with_fallback(fn, neutral)
    return function(...)
        local ok, result = pcall(fn, ...)
        if ok then return result end
        return neutral
    end
end

-- with_errors: thread an error collector through the function
-- The function receives errs as its first argument.
-- Returns (result, error_list).
function U.with_errors(fn)
    return function(...)
        local errs = U.errors()
        local result = fn(errs, ...)
        return result, errs:get()
    end
end


-- ═══════════════════════════════════════════════════════════════
-- ERROR COLLECTOR
--
-- Collects per-item errors with semantic refs.
-- Used inside boundary implementations.
-- Thread-local (created per boundary call, not shared).
-- ═══════════════════════════════════════════════════════════════

function U.errors()
    local list = {}

    return {
        -- Map a list through a function, collect per-item errors.
        -- Items that fail are replaced with neutral values.
        --
        --   fn:         function(item) → result
        --   neutral_fn: function(item) → fallback value
        --   ref_field:  string naming the field to use as error ref
        --               (e.g. "id" → error.ref = item.id)
        --
        -- If LuaFun is available, uses fun.iter for lazy evaluation.
        -- Otherwise falls back to a plain loop.
        each = function(self, items, fn, ref_field, neutral_fn)
            local results = {}
            for i, item in ipairs(items) do
                local ok, result, child_errs = pcall(function()
                    return fn(item)
                end)
                if ok then
                    if child_errs then
                        for _, e in ipairs(child_errs) do
                            list[#list + 1] = e
                        end
                    end
                    results[i] = result
                else
                    list[#list + 1] = {
                        ref = ref_field and item[ref_field] or i,
                        err = tostring(result),
                    }
                    if neutral_fn then
                        results[i] = neutral_fn(item)
                    elseif U._silent_unit then
                        results[i] = U._silent_unit
                    end
                end
            end
            return results
        end,

        -- Call a single function, collect error if it fails.
        -- Returns the result or the neutral value.
        call = function(self, target, fn, neutral_fn)
            local ok, result, child_errs = pcall(fn, target)
            if ok then
                if child_errs then
                    for _, e in ipairs(child_errs) do
                        list[#list + 1] = e
                    end
                end
                return result
            end
            list[#list + 1] = {
                ref = target and target.id or nil,
                err = tostring(result),
            }
            if neutral_fn then return neutral_fn(target) end
            return nil
        end,

        -- Merge a child error list into this collector.
        merge = function(self, child_errs)
            if child_errs then
                for _, e in ipairs(child_errs) do
                    list[#list + 1] = e
                end
            end
        end,

        -- Return the collected errors (nil if none).
        get = function(self)
            if #list > 0 then return list end
            return nil
        end,
    }
end

-- Cache one silent unit for error fallbacks
U._silent_unit = nil
local function get_silent()
    if not U._silent_unit then
        U._silent_unit = U.silent()
    end
    return U._silent_unit
end


-- ═══════════════════════════════════════════════════════════════
-- HELPER LIBRARY
-- Pure Lua. No parser. No framework. Just useful functions.
-- ═══════════════════════════════════════════════════════════════

-- Exhaustive match on an ASDL sum type.
-- Checks that every variant has a handler.
-- Errors at runtime on first call if a variant is missing.
-- Because boundaries are memoized, first call = only call per input.
--
--   value: an ASDL sum type instance (has .kind field)
--   arms:  table mapping variant name → function(value) → result
--
-- Usage:
--   U.match(device, {
--       NativeDevice  = function(d) ... end,
--       LayerDevice   = function(d) ... end,
--   })
function U.match(value, arms)
    local mt = getmetatable(value)

    -- Check exhaustiveness if reflection metadata is available.
    -- U.inspect(ctx, phases) enriches ASDL sum types with __variants on the
    -- parent and __sum_parent on each child variant. If that metadata is not
    -- present yet, U.match still dispatches on value.kind, but cannot prove
    -- exhaustiveness.
    if mt then
        local parent = mt.__sum_parent
        local variants = mt.__variants
            or (parent and parent.__variants)
            or {}

        for _, vname in ipairs(variants) do
            if not arms[vname] then
                error(("U.match: missing variant '%s' on %s. "
                    .. "All variants must be handled."):format(
                    vname,
                    (parent and parent.__name) or mt.__name or tostring(mt)),
                    2)
            end
        end
    end

    local kind = value.kind
    if not kind then
        error("U.match: value has no .kind field — "
            .. "is this an ASDL sum type?", 2)
    end

    local handler = arms[kind]
    if not handler then
        error(("U.match: unhandled variant '%s'"):format(kind), 2)
    end

    return handler(value)
end


-- Functional update on an ASDL record.
-- Returns a NEW node with some fields changed. Original untouched.
-- Like Clojure's assoc or Elixir's Map.put.
--
--   node:      an ASDL record instance
--   overrides: table of { field_name = new_value }
--
-- Usage:
--   local louder = U.with(track, { volume_db = -3 })
function U.with(node, overrides)
    local mt = getmetatable(node)
    if not mt then
        error("U.with: node has no metatable — "
            .. "is this an ASDL type?", 2)
    end

    -- ASDL classes store field metadata
    local fields = mt.__fields
    if not fields then
        error("U.with: metatable has no __fields — "
            .. "is this an ASDL type created by context:Define()?", 2)
    end

    local args = {}
    for i, field in ipairs(fields) do
        local name = field.name or field[1]
        if overrides[name] ~= nil then
            args[i] = overrides[name]
        else
            args[i] = node[name]
        end
    end

    return mt(unpack_fn(args, 1, #fields))
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
    local function discover_phases()
        local out = {}
        local names = {}
        local namespaces = (ctx and ctx.namespaces) or {}

        for name, ns in pairs(namespaces) do
            if type(ns) == "table" then
                for _, value in pairs(ns) do
                    if type(value) == "table"
                        and type(value.isclassof) == "function" then
                        names[#names + 1] = name
                        break
                    end
                end
            end
        end

        table.sort(names)
        return names
    end

    phases = phases or discover_phases()
    if #phases == 0 then phases = discover_phases() end
    pipeline_phases = pipeline_phases or phases

    local function basename(name)
        if not name then return nil end
        return name:match("([^.]+)$") or name
    end

    local function is_asdl_class(value)
        return type(value) == "table"
            and type(value.isclassof) == "function"
    end

    local function field_type_string(field)
        local suffix = ""
        if field.optional then suffix = "?"
        elseif field.list then suffix = "*" end
        return tostring(field.type) .. suffix
    end

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
    for _, phase_name in ipairs(phases) do
        local ns = ctx[phase_name]
        if type(ns) == "table" then
            local names = {}
            for name, class in pairs(ns) do
                if is_asdl_class(class) then
                    names[#names + 1] = name
                end
            end
            table.sort(names)

            for _, name in ipairs(names) do
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
            end
        end
    end

    -- Derive enum metadata from ASDL parent.members.
    for _, t in ipairs(I.types) do
        local variant_entries = {}
        if type(t.class.members) == "table" then
            for member, _ in pairs(t.class.members) do
                if member ~= t.class then
                    local variant_t = class_map[member]
                    variant_entries[#variant_entries + 1] = {
                        class = member,
                        type = variant_t,
                        name = (variant_t and variant_t.name)
                            or member.kind
                            or basename(member.__name)
                            or tostring(member),
                    }
                end
            end
        end

        table.sort(variant_entries, function(a, b)
            return a.name < b.name
        end)

        if #variant_entries > 0 and not t.class.__fields then
            t.kind = "enum"
            for i, entry in ipairs(variant_entries) do
                t.variants[i] = entry.name
                t.variant_types[i] = entry.type
                entry.class.__sum_parent = t.class
            end
            t.class.__variants = t.variants
        end
    end

    local function is_public_method(name, value)
        return type(value) == "function"
            and name ~= "isclassof"
            and name ~= "init"
            and not name:match("^__")
    end

    -- Discover installed methods.
    -- Sum-type parent methods are copied onto child variant classes by ASDL.
    -- Skip those inherited duplicates so Device:lower() appears once on the
    -- sum parent, not once per variant, unless a variant overrides it.
    for _, t in ipairs(I.types) do
        local method_names = {}
        local parent = t.class.__sum_parent
        for name, fn in pairs(t.class) do
            if is_public_method(name, fn)
                and not (parent and parent[name] == fn) then
                method_names[#method_names + 1] = name
            end
        end
        table.sort(method_names)
        t.methods = method_names

        for _, name in ipairs(method_names) do
            I.boundaries[#I.boundaries + 1] = {
                receiver = t.fqname,
                receiver_name = t.name,
                name = name,
                fn = t.class[name],
                phase = t.phase,
                type = t,
            }
        end
    end

    table.sort(I.boundaries, function(a, b)
        if a.receiver == b.receiver then
            return a.name < b.name
        end
        return a.receiver < b.receiver
    end)

    local function find_boundary(boundary_name)
        for _, b in ipairs(I.boundaries) do
            if b.receiver .. ":" .. b.name == boundary_name then
                return b
            end
        end
        return nil
    end

    local function is_stub(boundary)
        local ok, err = pcall(boundary.fn, nil)
        if ok then return false end
        return tostring(err):lower():match("not implemented") ~= nil
    end

    local function resolve_type_name(type_name, phase_name)
        if type(type_name) ~= "string" then return nil end

        if I.type_map[type_name] then
            return type_name
        end

        if phase_name then
            local fqname = phase_name .. "." .. type_name
            if I.type_map[fqname] then
                return fqname
            end
        end

        local match = nil
        for fqname, _ in pairs(I.type_map) do
            if basename(fqname) == type_name then
                if match and match ~= fqname then
                    return nil
                end
                match = fqname
            end
        end
        return match
    end

    local function direct_refs(t)
        local refs, seen = {}, {}

        local function add(fqname)
            if fqname and not seen[fqname] then
                seen[fqname] = true
                refs[#refs + 1] = I.type_map[fqname]
            end
        end

        if t.kind == "enum" then
            for _, variant_t in ipairs(t.variant_types) do
                if variant_t then add(variant_t.fqname) end
            end
        end

        for _, field in ipairs(t.fields or {}) do
            add(resolve_type_name(field.type, t.phase))
        end

        table.sort(refs, function(a, b)
            return a.fqname < b.fqname
        end)

        return refs
    end

    function I.find_boundary(boundary_name)
        return find_boundary(boundary_name)
    end

    function I.resolve_type_name(type_name, phase_name)
        return resolve_type_name(type_name, phase_name)
    end

    function I.is_stub(boundary)
        return is_stub(boundary)
    end

    function I.progress()
        local info = {
            total = #I.boundaries,
            real = 0,
            stub = 0,
            coverage = 0,
            by_phase = {},
        }

        for _, phase_name in ipairs(phases) do
            info.by_phase[phase_name] = {
                total = 0,
                real = 0,
                stub = 0,
                coverage = 0,
            }
        end

        for _, b in ipairs(I.boundaries) do
            local phase = info.by_phase[b.phase]
            if not phase then
                phase = { total = 0, real = 0, stub = 0, coverage = 0 }
                info.by_phase[b.phase] = phase
            end

            phase.total = phase.total + 1
            if is_stub(b) then
                phase.stub = phase.stub + 1
                info.stub = info.stub + 1
            else
                phase.real = phase.real + 1
                info.real = info.real + 1
            end
        end

        for _, phase_name in ipairs(phases) do
            local phase = info.by_phase[phase_name]
            if phase and phase.total > 0 then
                phase.coverage = phase.real / phase.total
            end
        end

        if info.total > 0 then
            info.coverage = info.real / info.total
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
            local names = {}
            for name, _ in pairs(counts) do
                names[#names + 1] = name
            end
            table.sort(names)

            local verb = "?"
            local best = -1
            for _, name in ipairs(names) do
                local count = counts[name]
                if count > best then
                    best = count
                    verb = name
                end
            end

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
        max_depth = max_depth or 3

        local visited = {}
        local sections = {}

        local function walk(type_name, depth)
            if visited[type_name] then return end
            if depth > max_depth then return end

            local t = I.type_map[type_name]
            if not t then return end

            visited[type_name] = true

            local indent = string.rep("  ", depth)
            local lines = {}
            local title = indent .. "### " .. t.fqname
            if t.kind == "enum" then
                title = title .. " (" .. #t.variants .. " variants)"
            end
            lines[#lines + 1] = title

            if t.kind == "enum" then
                for _, vname in ipairs(t.variants) do
                    lines[#lines + 1] = indent .. "| " .. vname
                end
            end

            for _, field in ipairs(t.fields or {}) do
                lines[#lines + 1] = indent .. "- "
                    .. tostring(field.name or field[1] or "?")
                    .. ": " .. field_type_string(field)
            end

            sections[#sections + 1] = table.concat(lines, "\n")

            if depth >= max_depth then return end

            if t.kind == "enum" then
                for _, variant_t in ipairs(t.variant_types) do
                    if variant_t then walk(variant_t.fqname, depth + 1) end
                end
            end

            for _, field in ipairs(t.fields or {}) do
                local ref = resolve_type_name(field.type, t.phase)
                if ref then walk(ref, depth + 1) end
            end
        end

        local root_name = root_type
        if type(root_type) == "table" and root_type.fqname then
            root_name = root_type.fqname
        end

        walk(root_name, 0)
        return table.concat(sections, "\n\n")
    end

    function I.prompt_for(boundary_name, max_depth)
        local b = find_boundary(boundary_name)
        if not b then
            return "boundary not found: " .. tostring(boundary_name)
        end

        local child_items = {}
        local seen = {}
        for _, ref_t in ipairs(direct_refs(b.type)) do
            if ref_t and type(ref_t.class[b.name]) == "function" then
                local item = ref_t.fqname .. ":" .. b.name .. "()"
                if not seen[item] then
                    seen[item] = true
                    child_items[#child_items + 1] = item
                end
            end
        end

        if #child_items == 0 then
            for _, other in ipairs(I.boundaries) do
                if other.phase == b.phase and other.receiver ~= b.receiver then
                    local item = other.receiver .. ":" .. other.name .. "()"
                    if not seen[item] then
                        seen[item] = true
                        child_items[#child_items + 1] = item
                    end
                end
            end
        end

        table.sort(child_items)

        local sections = {
            "## Phase: " .. b.phase,
            "## Input type: " .. b.receiver,
            I.type_graph(b.receiver, max_depth or 3),
            "## Available child boundaries:",
        }

        if #child_items == 0 then
            sections[#sections + 1] = "- none"
        else
            for _, item in ipairs(child_items) do
                sections[#sections + 1] = "- " .. item
            end
        end

        sections[#sections + 1] = "## Implement: " .. boundary_name
        sections[#sections + 1] =
            "## Available: U.match, U.errors, U.with, U.transition, U.terminal"

        return table.concat(sections, "\n\n")
    end

    function I.markdown()
        local lines = { "# Schema Documentation", "" }

        for _, phase_name in ipairs(phases) do
            lines[#lines + 1] = "## Phase: " .. phase_name
            lines[#lines + 1] = ""

            for _, t in ipairs(I.types) do
                if t.phase == phase_name then
                    lines[#lines + 1] = "### " .. t.fqname
                        .. " (" .. t.kind .. ")"

                    if t.kind == "enum" then
                        for _, vname in ipairs(t.variants) do
                            lines[#lines + 1] = "- `" .. vname .. "`"
                        end
                    end

                    for _, field in ipairs(t.fields or {}) do
                        lines[#lines + 1] = "- `"
                            .. tostring(field.name or field[1] or "?")
                            .. ": " .. field_type_string(field) .. "`"
                    end

                    lines[#lines + 1] = ""
                end
            end

            local have_boundaries = false
            for _, b in ipairs(I.boundaries) do
                if b.phase == phase_name then
                    if not have_boundaries then
                        lines[#lines + 1] = "### Boundaries"
                        have_boundaries = true
                    end
                    lines[#lines + 1] = "- `" .. b.receiver
                        .. ":" .. b.name .. "()`"
                end
            end

            lines[#lines + 1] = ""
        end

        return table.concat(lines, "\n")
    end

    function I.test_all()
        local results = {}
        local passed = 0

        for _, b in ipairs(I.boundaries) do
            local result = {
                boundary = b.receiver .. ":" .. b.name,
                exists = type(b.fn) == "function",
                stub = is_stub(b),
            }
            results[#results + 1] = result
            if result.exists and not result.stub then
                passed = passed + 1
            end
        end

        return {
            results = results,
            passed = passed,
            total = #results,
        }
    end

    function I.scaffold(boundary_name)
        local b = find_boundary(boundary_name)
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
            lines[#lines + 1] = "    return U.match(self, {"
            for _, vname in ipairs(t.variants) do
                lines[#lines + 1] = "        " .. vname .. " = function(self)"
                lines[#lines + 1] = "            -- TODO: implement"
                lines[#lines + 1] = "        end,"
            end
            lines[#lines + 1] = "    })"
            lines[#lines + 1] = "end"
            return table.concat(lines, "\n")
        end

        local child_calls = {}
        for _, field in ipairs(t.fields or {}) do
            local ref = resolve_type_name(field.type, t.phase)
            local ref_t = ref and I.type_map[ref] or nil
            if ref_t and type(ref_t.class[b.name]) == "function" then
                child_calls[#child_calls + 1] = {
                    field = field,
                    ref = ref_t,
                }
            end
        end

        if #child_calls > 0 then
            lines[#lines + 1] = "    local errs = U.errors()"
            lines[#lines + 1] = ""

            for _, call in ipairs(child_calls) do
                local fname = tostring(call.field.name or call.field[1] or "field")
                if call.field.list then
                    lines[#lines + 1] = "    local " .. fname
                        .. " = errs:each(self." .. fname
                        .. ", function(x)"
                    lines[#lines + 1] = "        return x:" .. b.name .. "()"
                    lines[#lines + 1] = "    end, \"id\")"
                else
                    lines[#lines + 1] = "    local " .. fname
                        .. " = errs:call(self." .. fname
                        .. ", function(x)"
                    lines[#lines + 1] = "        return x:" .. b.name .. "()"
                    lines[#lines + 1] = "    end)"
                end
                lines[#lines + 1] = ""
            end

            lines[#lines + 1] = "    -- TODO: construct return value"
            lines[#lines + 1] = "    -- return ..., errs:get()"
        else
            lines[#lines + 1] = "    -- TODO: implement"
        end

        lines[#lines + 1] = "end"
        return table.concat(lines, "\n")
    end

    function I.status()
        local p = I.progress()
        local lines = {}

        for _, phase_name in ipairs(phases) do
            local phase = p.by_phase[phase_name]
            if phase and phase.total > 0 then
                local bar_len = 20
                local filled = math.floor((phase.real / phase.total) * bar_len)
                local bar = string.rep("█", filled)
                    .. string.rep("░", bar_len - filled)

                lines[#lines + 1] = string.format(
                    "  %-14s %s  %d/%d",
                    phase_name .. ":",
                    bar,
                    phase.real,
                    phase.total)
            end
        end

        lines[#lines + 1] = string.rep("─", 45)
        lines[#lines + 1] = string.format(
            "  %-14s %d/%d (%.1f%%)",
            "Total:",
            p.real,
            p.total,
            p.coverage * 100)

        return table.concat(lines, "\n")
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
-- CLI helpers
--
-- Thin reflection CLI over U.inspect(ctx, phases).
-- No registry, no extra DSL, just a loader that returns:
--   { ctx = T, phases = { ... } }
-- or a function(U) -> that table
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
