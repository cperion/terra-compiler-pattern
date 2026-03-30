local asdl = require("asdl")
local U = require("unit")
local F = require("fun")

local L = asdl.List

-- ============================================================================
-- UiQueryScene.Scene -> organize_query_machine_ir -> UiQueryMachineIR.Scene
-- ----------------------------------------------------------------------------
-- ui3 query organization layer: pack an already-concrete query occurrence scene
-- into reducer/query-facing access streams.
--
-- Current policy:
--   - preserve region order
--   - preserve hit/focus/scroll/edit/accessibility occurrence order
--   - derive explicit focus-order stream from FocusOccurrence.order
--   - bucket key routes by (chord, when, scope) within each region
-- ============================================================================

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function Ls(xs)
    return L(xs or {})
end

local function pointer_binding_for(T, binding)
    return U.match(binding, {
        HoverBinding = function(v)
            return T.UiQueryMachineIR.HoverBinding(v.cursor, v.enter, v.leave)
        end,
        PressBinding = function(v)
            return T.UiQueryMachineIR.PressBinding(v.button, v.click_count, v.command)
        end,
        ToggleBinding = function(v)
            return T.UiQueryMachineIR.ToggleBinding(v.value, v.button, v.command)
        end,
        GestureBinding = function(v)
            return T.UiQueryMachineIR.GestureBinding(v.gesture, v.command)
        end,
    })
end

local function drag_drop_binding_for(T, binding)
    return U.match(binding, {
        DraggableBinding = function(v)
            return T.UiQueryMachineIR.DraggableBinding(v.payload, v.begin, v.finish)
        end,
        DropTargetBinding = function(v)
            return T.UiQueryMachineIR.DropTargetBinding(v.policy, v.command)
        end,
    })
end

local function scroll_binding_for(T, binding)
    if binding == nil then return nil end
    return T.UiQueryMachineIR.ScrollBinding(binding.axis, binding.model)
end

local function key_scope_for(T, key)
    if key.global then return C(T.UiQueryMachineIR.GlobalScope) end
    return C(T.UiQueryMachineIR.FocusScope)
end

local function key_bucket_sig(key)
    local chord = key.chord
    local scope = key.global and "g" or "f"
    return table.concat({
        chord.ctrl and "1" or "0",
        chord.alt and "1" or "0",
        chord.shift and "1" or "0",
        chord.meta and "1" or "0",
        tostring(chord.keycode),
        key.when.kind,
        scope,
    }, ":")
end

local function copy_hits(T, scene)
    if #scene.hits == 0 then return {} end
    return F.range(1, #scene.hits):map(function(i)
        local hit = scene.hits[i]
        local pointer = (#hit.pointer > 0) and F.range(1, #hit.pointer):map(function(j)
            return pointer_binding_for(T, hit.pointer[j])
        end):totable() or {}
        local drag_drop = (#hit.drag_drop > 0) and F.range(1, #hit.drag_drop):map(function(j)
            return drag_drop_binding_for(T, hit.drag_drop[j])
        end):totable() or {}
        return T.UiQueryMachineIR.HitInstance(
            hit.id,
            hit.semantic_ref,
            hit.shape,
            hit.z_index,
            Ls(pointer),
            scroll_binding_for(T, hit.scroll),
            Ls(drag_drop)
        )
    end):totable()
end

local function copy_focus(T, scene)
    if #scene.focus == 0 then return {} end
    return F.range(1, #scene.focus):map(function(i)
        local focus = scene.focus[i]
        return T.UiQueryMachineIR.FocusInstance(
            focus.id,
            focus.semantic_ref,
            focus.rect,
            focus.mode,
            focus.order
        )
    end):totable()
end

local function copy_scroll_hosts(T, scene)
    if #scene.scroll_hosts == 0 then return {} end
    return F.range(1, #scene.scroll_hosts):map(function(i)
        local host = scene.scroll_hosts[i]
        return T.UiQueryMachineIR.ScrollHostInstance(
            host.id,
            host.semantic_ref,
            host.axis,
            host.model,
            host.viewport_rect,
            host.content_extent
        )
    end):totable()
end

local function copy_edit_hosts(T, scene)
    if #scene.edit_hosts == 0 then return {} end
    return F.range(1, #scene.edit_hosts):map(function(i)
        local host = scene.edit_hosts[i]
        return T.UiQueryMachineIR.EditHostInstance(
            host.id,
            host.semantic_ref,
            host.model,
            host.rect,
            host.multiline,
            host.read_only,
            host.changed
        )
    end):totable()
end

local function copy_accessibility(T, scene)
    if #scene.accessibility == 0 then return {} end
    return F.range(1, #scene.accessibility):map(function(i)
        local acc = scene.accessibility[i]
        return T.UiQueryMachineIR.AccessibilityInstance(
            acc.id,
            acc.semantic_ref,
            acc.role,
            acc.label,
            acc.description,
            acc.rect,
            acc.sort_priority
        )
    end):totable()
end

local function focus_order_entries(T, scene, region)
    local ordered = {}
    local first = region.focus_start + 1
    local last = region.focus_start + region.focus_count

    local i = first
    while i <= last do
        local focus = scene.focus[i]
        if focus.order ~= nil then
            ordered[#ordered + 1] = {
                focus_index = i - 1,
                order = focus.order,
                rect = focus.rect,
            }
        end
        i = i + 1
    end

    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.rect.y ~= b.rect.y then return a.rect.y < b.rect.y end
        if a.rect.x ~= b.rect.x then return a.rect.x < b.rect.x end
        return a.focus_index < b.focus_index
    end)

    if #ordered == 0 then return {} end
    return F.range(1, #ordered):map(function(j)
        return T.UiQueryMachineIR.FocusOrderEntry(ordered[j].focus_index)
    end):totable()
end

local function key_buckets_and_routes(T, scene, region)
    local bucket_list = {}
    local bucket_by_sig = {}
    local first = region.key_start + 1
    local last = region.key_start + region.key_count

    local i = first
    while i <= last do
        local key = scene.keys[i]
        local sig = key_bucket_sig(key)
        local bucket = bucket_by_sig[sig]
        if bucket == nil then
            bucket = {
                chord = key.chord,
                when = key.when,
                scope = key_scope_for(T, key),
                routes = {},
            }
            bucket_by_sig[sig] = bucket
            bucket_list[#bucket_list + 1] = bucket
        end
        bucket.routes[#bucket.routes + 1] = T.UiQueryMachineIR.KeyRouteInstance(
            key.id,
            key.command
        )
        i = i + 1
    end

    return bucket_list
end

local function append_region(T, scene, region, acc)
    local focus_order_start = #acc.focus_order
    local focus_order = focus_order_entries(T, scene, region)
    F.range(1, #focus_order):each(function(i)
        acc.focus_order[#acc.focus_order + 1] = focus_order[i]
    end)

    local key_bucket_start = #acc.key_buckets
    local bucket_list = key_buckets_and_routes(T, scene, region)
    if #bucket_list > 0 then
        F.range(1, #bucket_list):each(function(i)
            local bucket = bucket_list[i]
            local route_start = #acc.key_routes
            if #bucket.routes > 0 then
                F.range(1, #bucket.routes):each(function(j)
                    acc.key_routes[#acc.key_routes + 1] = bucket.routes[j]
                end)
            end
            acc.key_buckets[#acc.key_buckets + 1] = T.UiQueryMachineIR.KeyRouteBucket(
                bucket.chord,
                bucket.when,
                bucket.scope,
                route_start,
                #bucket.routes
            )
        end)
    end

    acc.regions[#acc.regions + 1] = T.UiQueryMachineIR.RegionHeader(
        region.header.id,
        region.header.debug_name,
        region.z_index,
        region.modal,
        region.consumes_pointer,
        region.hit_start,
        region.hit_count,
        region.focus_start,
        region.focus_count,
        focus_order_start,
        #focus_order,
        key_bucket_start,
        #bucket_list,
        region.scroll_start,
        region.scroll_count,
        region.edit_start,
        region.edit_count,
        region.accessibility_start,
        region.accessibility_count
    )

    return acc
end

local function organize_query_machine_ir(T, scene)
    local acc = F.range(1, #scene.regions):reduce(function(state, i)
        return append_region(T, scene, scene.regions[i], state)
    end, {
        regions = {},
        focus_order = {},
        key_buckets = {},
        key_routes = {},
    })

    return T.UiQueryMachineIR.Scene(
        T.UiQueryMachineIR.Input(
            Ls(acc.regions),
            Ls(copy_hits(T, scene)),
            Ls(copy_focus(T, scene)),
            Ls(acc.focus_order),
            Ls(acc.key_buckets),
            Ls(acc.key_routes),
            Ls(copy_scroll_hosts(T, scene)),
            Ls(copy_edit_hosts(T, scene)),
            Ls(copy_accessibility(T, scene))
        )
    )
end

return function(T)
    T.UiQueryScene.Scene.organize_query_machine_ir = U.transition(function(scene)
        return organize_query_machine_ir(T, scene)
    end)
end
