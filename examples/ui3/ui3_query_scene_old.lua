local asdl = require("asdl")
local U = require("unit")
local F = require("fun")

local L = asdl.List

-- ============================================================================
-- UiGeometry.Scene + UiQueryFacts.Scene -> project_query_scene -> UiQueryScene.Scene
-- ----------------------------------------------------------------------------
-- ui3 query projection layer: resolve shared solved geometry plus query-side
-- facts into concrete query occurrences.
--
-- Current first-pass policy:
--   - requires region/header alignment between geometry and query facts
--   - projects only placed nodes
--   - emits direct hit/focus/key/scroll/edit/accessibility occurrences
--   - uses border-box hit rects for all current non-NoHit policies
--
-- Known current limitation:
--   UiQueryScene.HitOccurrence does not preserve the distinction between
--   SelfHit / SelfAndChildrenHit / ChildrenOnlyHit. The current ASDL only
--   carries concrete hit shape plus bindings, so this boundary necessarily
--   collapses those policy distinctions for now.
-- ============================================================================

local function Ls(xs)
    return L(xs or {})
end

local function region_header_equals(a, b)
    return a.id.value == b.id.value
       and a.root_index == b.root_index
       and a.debug_name == b.debug_name
end

local function hit_shape_for(T, rect)
    return T.UiCore.HitRect(rect)
end

local function placed_geometry(node)
    return U.match(node, {
        Excluded = function()
            return nil
        end,
        Placed = function(v)
            return v.node
        end,
    })
end

local function pointer_binding_for(T, binding)
    return U.match(binding, {
        HoverBinding = function(v)
            return T.UiQueryScene.HoverBinding(v.cursor, v.enter, v.leave)
        end,
        PressBinding = function(v)
            return T.UiQueryScene.PressBinding(v.button, v.click_count, v.command)
        end,
        ToggleBinding = function(v)
            return T.UiQueryScene.ToggleBinding(v.value, v.button, v.command)
        end,
        GestureBinding = function(v)
            return T.UiQueryScene.GestureBinding(v.gesture, v.command)
        end,
    })
end

local function drag_drop_binding_for(T, binding)
    return U.match(binding, {
        DraggableBinding = function(v)
            return T.UiQueryScene.DraggableBinding(v.payload, v.begin, v.finish)
        end,
        DropTargetBinding = function(v)
            return T.UiQueryScene.DropTargetBinding(v.policy, v.command)
        end,
    })
end

local function scroll_binding_for(T, scroll)
    if scroll == nil then return nil end
    return T.UiQueryScene.ScrollBinding(scroll.axis, scroll.model)
end

local function emit_query_occurrences(T, region, header, placed, fact, acc)
    local id = header.id
    local semantic_ref = header.semantic_ref

    local pointer = (#fact.pointer > 0) and F.range(1, #fact.pointer):map(function(i)
        return pointer_binding_for(T, fact.pointer[i])
    end):totable() or {}

    local drag_drop = (#fact.drag_drop > 0) and F.range(1, #fact.drag_drop):map(function(i)
        return drag_drop_binding_for(T, fact.drag_drop[i])
    end):totable() or {}

    local wants_hit = fact.hit.kind ~= "NoHit"
        or #pointer > 0
        or fact.scroll ~= nil
        or #drag_drop > 0

    if wants_hit then
        acc.hits[#acc.hits + 1] = T.UiQueryScene.HitOccurrence(
            id,
            semantic_ref,
            hit_shape_for(T, placed.border_box),
            region.z_index,
            Ls(pointer),
            scroll_binding_for(T, fact.scroll),
            Ls(drag_drop)
        )
    end

    if fact.focus ~= nil then
        acc.focus[#acc.focus + 1] = T.UiQueryScene.FocusOccurrence(
            id,
            semantic_ref,
            placed.border_box,
            fact.focus.mode,
            fact.focus.order
        )
    end

    if #fact.keys > 0 then
        F.range(1, #fact.keys):each(function(i)
            local key = fact.keys[i]
            acc.keys[#acc.keys + 1] = T.UiQueryScene.KeyOccurrence(
                id,
                key.chord,
                key.when,
                key.command,
                key.global
            )
        end)
    end

    if fact.scroll ~= nil then
        acc.scroll_hosts[#acc.scroll_hosts + 1] = T.UiQueryScene.ScrollHostOccurrence(
            id,
            semantic_ref,
            fact.scroll.axis,
            fact.scroll.model,
            placed.content_box,
            placed.content_extent
        )
    end

    if fact.edit ~= nil then
        acc.edit_hosts[#acc.edit_hosts + 1] = T.UiQueryScene.EditHostOccurrence(
            id,
            semantic_ref,
            fact.edit.model,
            placed.content_box,
            fact.edit.multiline,
            fact.edit.read_only,
            fact.edit.changed
        )
    end

    U.match(fact.accessibility, {
        NoAccessibility = function()
            return acc
        end,
        Exposed = function(v)
            acc.accessibility[#acc.accessibility + 1] = T.UiQueryScene.AccessibilityOccurrence(
                id,
                semantic_ref,
                v.role,
                v.label,
                v.description,
                placed.border_box,
                v.sort_priority
            )
            return acc
        end,
    })

    return acc
end

local function project_region(T, geometry_region, facts_region, acc)
    if not region_header_equals(geometry_region.header, facts_region.header) then
        error("UiGeometry.Scene:project_query_scene: region headers are not aligned", 3)
    end

    if #geometry_region.headers ~= #geometry_region.nodes then
        error("UiGeometry.Scene:project_query_scene: geometry region headers/nodes length mismatch", 3)
    end

    if #geometry_region.headers ~= #facts_region.node_facts then
        error("UiGeometry.Scene:project_query_scene: geometry/query-facts node count mismatch", 3)
    end

    local hit_start = #acc.hits
    local focus_start = #acc.focus
    local key_start = #acc.keys
    local scroll_start = #acc.scroll_hosts
    local edit_start = #acc.edit_hosts
    local accessibility_start = #acc.accessibility

    F.range(1, #geometry_region.headers):each(function(i)
        local placed = placed_geometry(geometry_region.nodes[i])
        if placed ~= nil then
            emit_query_occurrences(
                T,
                facts_region,
                geometry_region.headers[i],
                placed,
                facts_region.node_facts[i],
                acc
            )
        end
    end)

    acc.regions[#acc.regions + 1] = T.UiQueryScene.Region(
        geometry_region.header,
        facts_region.z_index,
        facts_region.modal,
        facts_region.consumes_pointer,
        hit_start,
        #acc.hits - hit_start,
        focus_start,
        #acc.focus - focus_start,
        key_start,
        #acc.keys - key_start,
        scroll_start,
        #acc.scroll_hosts - scroll_start,
        edit_start,
        #acc.edit_hosts - edit_start,
        accessibility_start,
        #acc.accessibility - accessibility_start
    )

    return acc
end

local function project_query_scene(T, geometry, query_facts)
    if #geometry.regions ~= #query_facts.regions then
        error("UiGeometry.Scene:project_query_scene: region count mismatch", 3)
    end

    local acc = F.range(1, #geometry.regions):reduce(function(state, i)
        return project_region(T, geometry.regions[i], query_facts.regions[i], state)
    end, {
        regions = {},
        hits = {},
        focus = {},
        keys = {},
        scroll_hosts = {},
        edit_hosts = {},
        accessibility = {},
    })

    return T.UiQueryScene.Scene(
        Ls(acc.regions),
        Ls(acc.hits),
        Ls(acc.focus),
        Ls(acc.keys),
        Ls(acc.scroll_hosts),
        Ls(acc.edit_hosts),
        Ls(acc.accessibility)
    )
end

return function(T)
    T.UiGeometry.Scene.project_query_scene = U.transition(function(geometry, query_facts)
        return project_query_scene(T, geometry, query_facts)
    end)
end
