-- unit.t
--
-- The Terra Compiler Pattern — Final Form
--
-- Five primitives. No framework. The architecture IS the composition.
--
-- ASDL unique     → structural identity
-- terralib.memoize → identity-based caching
-- LuaFun          → functional transforms (external, optional)
-- Unit            → compile product { fn, state_t }
-- Wrappers        → transition, terminal, with_fallback, with_errors
--
-- ~200 lines. Everything else is your domain.

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

    -- Check exhaustiveness if the ASDL class tracks variants
    if mt then
        -- ASDL sum types store subclass names
        -- Walk the class hierarchy to find all variant names
        local variants = {}
        if mt.__variants then
            variants = mt.__variants
        elseif mt.__index and type(mt.__index) == "table" then
            -- Fallback: check if the parent class has variant info
            local parent = mt.__index
            if parent.__variants then
                variants = parent.__variants
            end
        end

        for _, vname in ipairs(variants) do
            if not arms[vname] then
                error(("U.match: missing variant '%s' on %s. "
                    .. "All variants must be handled."):format(
                    vname, mt.__name or tostring(mt)), 2)
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
-- MODULE
-- ═══════════════════════════════════════════════════════════════

return U
