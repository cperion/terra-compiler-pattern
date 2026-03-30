-- unit_luajit.lua
--
-- LuaJIT backend for the compiler pattern.
--
-- Shared pure helpers live in unit_core.lua.
-- This module adds the LuaJIT-specific terminal/runtime layer:
--   - FFI/cdata-backed typed state layouts
--   - monomorphic Unit construction for fn(state, ...)
--   - structural composition
--   - hot-swap slots
--   - app loop wiring
--
-- Important policy:
--   LuaJIT is not the "dynamic tables" backend. The intended production leaf
--   contract is the same Unit shape as Terra: Unit { fn, state_t }, with
--   state_t realized as FFI/cdata-backed typed layout. Pure phases stay typed
--   and structural above this layer.

local U = require("unit_core").new()

local has_ffi, ffi = pcall(require, "ffi")
local Schema = require("unit_schema")
local load_fn = loadstring or load
local setfenv_fn = setfenv


-- ═══════════════════════════════════════════════════════════════
-- STATE LAYOUTS
-- ═══════════════════════════════════════════════════════════════

U.EMPTY = {
    kind = "empty",
    alloc = function() return nil end,
    release = function() end,
}

local function is_callable(value)
    if type(value) == "function" then return true end
    local mt = getmetatable(value)
    return mt and type(mt.__call) == "function"
end

local function is_state_layout(value)
    return type(value) == "table"
        and type(value.alloc) == "function"
        and type(value.release) == "function"
end

function U.state(alloc, release, kind)
    if type(alloc) ~= "function" then
        error("U.state: alloc must be a function", 2)
    end

    return {
        kind = kind or "custom",
        alloc = alloc,
        release = release or function() end,
    }
end

-- Debug/scaffolding helper only.
-- Production backend leaves should use U.state_ffi(...) so compiled functions
-- run over typed FFI layouts rather than opaque Lua tables.
function U.state_table(init, release)
    return U.state(function()
        local state = {}
        if init then
            local replacement = init(state)
            if replacement ~= nil then state = replacement end
        end
        return state
    end, release, "table-debug")
end

function U.state_ffi(ctype, opts)
    if not has_ffi then
        error("U.state_ffi: LuaJIT FFI is required", 2)
    end

    opts = opts or {}
    ctype = type(ctype) == "string" and ffi.typeof(ctype) or ctype

    return U.state(function()
        local state = ffi.new(ctype)
        if opts.init then
            local replacement = opts.init(state)
            if replacement ~= nil then state = replacement end
        end
        return state
    end, opts.release, "ffi")
end

function U.state_compose(children)
    children = children or {}

    local has_state = U.fold(children, function(found, child)
        return found or ((child.state_t or U.EMPTY) ~= U.EMPTY)
    end, false)

    if not has_state then return U.EMPTY end

    return {
        kind = "compose",
        children = children,

        alloc = function()
            local state = {}
            local i = 0
            U.each(children, function(child)
                i = i + 1
                local state_t = child.state_t or U.EMPTY
                if state_t ~= U.EMPTY then
                    state[i] = state_t.alloc()
                end
            end)
            return state
        end,

        release = function(state)
            if not state then return end
            U.reverse_each(children, function(child, i)
                local state_t = child.state_t or U.EMPTY
                if state_t ~= U.EMPTY and state[i] ~= nil then
                    state_t.release(state[i])
                end
            end)
        end,
    }
end


-- ═══════════════════════════════════════════════════════════════
-- UNIT CONSTRUCTION
-- ═══════════════════════════════════════════════════════════════

function U.new(fn, state_t)
    state_t = state_t or U.EMPTY

    if not is_callable(fn) then
        error("U.new: fn must be callable, got " .. tostring(type(fn)), 2)
    end

    if state_t ~= U.EMPTY and not is_state_layout(state_t) then
        error("U.new: state_t must be a layout descriptor with alloc/release", 2)
    end

    return {
        fn = fn,
        state_t = state_t,
    }
end

function U.silent()
    return U.new(function() end, U.EMPTY)
end

function U.leaf(state_t, fn)
    return U.new(fn, state_t or U.EMPTY)
end

function U.machine_to_unit(machine)
    if not U.is_machine(machine) then
        error("U.machine_to_unit: expected a Machine", 2)
    end

    local state_t = machine.state_t or U.EMPTY

    if machine.shape == "step" then
        return U.new(function(state, ...)
            return U.machine_run(machine, state, ...)
        end, state_t)
    end

    if machine.shape == "iter" then
        return U.new(function(state, ...)
            return U.machine_iterate(machine, state, ...)
        end, state_t)
    end

    error("U.machine_to_unit: unknown machine shape '" .. tostring(machine.shape) .. "'", 2)
end

local function compose_children(children)
    local kids = U.map(children, function(child)
        local child_state_t = child.state_t or U.EMPTY
        return {
            fn = child.fn,
            state_t = child_state_t,
            has_state = child_state_t ~= U.EMPTY,
        }
    end)

    local i = 0
    U.each(kids, function(kid)
        i = i + 1
        local idx = i
        local fn = kid.fn

        if kid.has_state then
            kid.state = function(parent_state)
                return parent_state and parent_state[idx] or nil
            end
            kid.call = function(parent_state, ...)
                return fn(parent_state and parent_state[idx] or nil, ...)
            end
        else
            kid.state = function()
                return nil
            end
            kid.call = function(_, ...)
                return fn(nil, ...)
            end
        end
    end)

    return kids
end

function U.compose(children, fn)
    children = children or {}
    if type(fn) ~= "function" then
        error("U.compose: fn must be a function", 2)
    end

    local unit = U.new(fn, U.state_compose(children))
    unit.children = children
    return unit
end

function U.compose_closure(children, body)
    children = children or {}
    if type(body) ~= "function" then
        error("U.compose_closure: body must be a function", 2)
    end

    local kids = compose_children(children)
    local unit = U.compose(children, function(state, ...)
        return body(state, kids, ...)
    end)

    unit.__composed_kids = kids
    return unit
end

local function build_linear_fn(children)
    local lines = { "return function(state, ...)" }
    local env = {}
    local has_any = false

    for i, child in ipairs(children) do
        local fname = "f" .. tostring(i)
        env[fname] = child.fn
        has_any = true

        if (child.state_t or U.EMPTY) ~= U.EMPTY then
            lines[#lines + 1] = string.format("  %s(state[%d], ...)", fname, i)
        else
            lines[#lines + 1] = string.format("  %s(nil, ...)", fname)
        end
    end

    if not has_any then
        lines[#lines + 1] = "  return"
    end

    lines[#lines + 1] = "end"
    local source = table.concat(lines, "\n")

    local chunk, err = load_fn(source, "unit_luajit.compose_linear")
    if not chunk then
        error("U.compose_linear: could not build function: " .. tostring(err), 2)
    end

    if setfenv_fn then
        setfenv_fn(chunk, env)
    end

    return chunk()
end

function U.compose_linear(children)
    children = children or {}

    local unit = U.new(build_linear_fn(children), U.state_compose(children))
    unit.children = children
    return unit
end

U.chain = U.compose_linear


-- ═══════════════════════════════════════════════════════════════
-- HOT SWAP
-- ═══════════════════════════════════════════════════════════════

local function release_instance(instance)
    if not instance or not instance.unit or not instance.unit.state_t then
        return
    end

    local state_t = instance.unit.state_t
    if state_t ~= U.EMPTY then
        state_t.release(instance.state)
    end
end

function U.hot_slot()
    local retired = {}
    local current = {
        unit = U.silent(),
        state = nil,
    }

    return {
        callback = function(...)
            return current.unit.fn(current.state, ...)
        end,

        swap = function(self_or_unit, maybe_unit)
            local unit = maybe_unit or self_or_unit

            if type(unit) ~= "table" or not is_callable(unit.fn) then
                error("U.hot_slot.swap: expected a Unit", 2)
            end

            local next_state = nil
            if unit.state_t and unit.state_t ~= U.EMPTY then
                next_state = unit.state_t.alloc()
            end

            local prev = current
            current = {
                unit = unit,
                state = next_state,
            }

            if prev and prev.unit ~= nil then
                retired[#retired + 1] = prev
            end

            return next_state
        end,

        peek = function()
            return current.unit, current.state
        end,

        collect = function()
            U.each(retired, function(instance)
                release_instance(instance)
            end)
            retired = {}
        end,

        close = function()
            U.each(retired, function(instance)
                release_instance(instance)
            end)
            retired = {}
            release_instance(current)
            current = {
                unit = U.silent(),
                state = nil,
            }
        end,
    }
end


-- ═══════════════════════════════════════════════════════════════
-- U.app — the universal application loop
-- ═══════════════════════════════════════════════════════════════

function U.app(config)
    if type(config) ~= "table" then
        error("U.app: config must be a table", 2)
    end
    if type(config.initial) ~= "function" then
        error("U.app: config.initial must be a function", 2)
    end
    if type(config.apply) ~= "function" then
        error("U.app: config.apply must be a function", 2)
    end

    local names = U.each_name({
        config.outputs,
        config.compile,
        config.start,
        config.stop,
    })

    local slots = {}
    U.each(names, function(name)
        slots[name] = U.hot_slot()
    end)

    local state = config.initial()

    U.each(names, function(name)
        local compiler = config.compile and config.compile[name]
        if compiler and slots[name] then
            slots[name].swap(compiler(state))
        end
    end)

    if config.start then
        U.each(names, function(name)
            local start_fn = config.start[name]
            if start_fn and slots[name] then
                start_fn(slots[name].callback)
            end
        end)
    end

    while state.running ~= false do
        local event = config.poll and config.poll() or nil
        if not event then break end

        local new_state = config.apply(state, event)
        if new_state ~= state then
            state = new_state
            U.each(names, function(name)
                local compiler = config.compile and config.compile[name]
                if compiler and slots[name] then
                    slots[name].swap(compiler(state))
                end
            end)
        end
    end

    if config.stop then
        U.each(names, function(name)
            local stop_fn = config.stop[name]
            if stop_fn and slots[name] then
                stop_fn()
            end
        end)
    end

    U.each(names, function(name)
        slots[name].close()
    end)

    return state
end


Schema.install(U)

return U
