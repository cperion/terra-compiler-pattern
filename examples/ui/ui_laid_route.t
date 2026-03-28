local U = require("unit")
local F = require("fun")

local Routing = {}
local unpack_fn = table.unpack or unpack

local function L(xs)
    return terralib.newlist(xs or {})
end

local function chain_lists(lists)
    if #lists == 0 then return L() end
    return L(F.chain(unpack_fn(lists)):totable())
end

local function z_index_of(depth)
    return depth
end

local function accessibility_tree(T, element)
    local child_nodes = chain_lists(F.iter(element.children):map(function(child)
        return accessibility_tree(T, child)
    end):totable())

    return L {
        T.UiRouted.AccessibilityNode(
            element.id,
            element.semantic_ref,
            element.accessibility.role,
            element.accessibility.label,
            element.accessibility.description,
            element.accessibility.hidden,
            element.accessibility.sort_priority,
            element.accessibility.bounds,
            child_nodes
        )
    }
end

local function behavior_routes(T, element, depth)
    local behavior = element.behavior
    local semantic_ref = element.semantic_ref
    local bounds = element.border_box

    local hits = (behavior.hit_shape and L {
        T.UiRouted.HitEntry(
            element.id,
            semantic_ref,
            behavior.hit_shape,
            z_index_of(depth)
        )
    }) or L()

    local focus_chain = (behavior.focus and L {
        T.UiRouted.FocusEntry(
            element.id,
            semantic_ref,
            behavior.focus.order,
            behavior.focus.mode,
            behavior.focus.bounds
        )
    }) or L()

    local pointer_routes = L(F.iter(behavior.pointer):map(function(node)
        return U.match(node, {
            Hover = function(v)
                return T.UiRouted.HoverRoute(
                    element.id,
                    semantic_ref,
                    v.cursor,
                    v.enter,
                    v.leave
                )
            end,
            Press = function(v)
                return T.UiRouted.PressRoute(
                    element.id,
                    semantic_ref,
                    v.button,
                    v.click_count,
                    v.command
                )
            end,
            Toggle = function(v)
                return T.UiRouted.ToggleRoute(
                    element.id,
                    semantic_ref,
                    v.value,
                    v.button,
                    v.command
                )
            end,
            Gesture = function(v)
                return T.UiRouted.GestureRoute(
                    element.id,
                    semantic_ref,
                    v.gesture,
                    v.command
                )
            end,
        })
    end):totable())

    local scroll_routes = (behavior.scroll and L {
        T.UiRouted.ScrollRoute(
            element.id,
            semantic_ref,
            behavior.scroll.axis,
            behavior.scroll.model,
            behavior.scroll.viewport,
            behavior.scroll.content_size
        )
    }) or L()

    local key_routes = L(F.iter(behavior.keys):map(function(node)
        return T.UiRouted.KeyRoute(
            node.global and nil or element.id,
            node.chord,
            node.when,
            node.command,
            node.global
        )
    end):totable())

    local edit_routes = (behavior.edit and L {
        T.UiRouted.EditRoute(
            element.id,
            semantic_ref,
            behavior.edit.model,
            behavior.edit.multiline,
            behavior.edit.read_only,
            behavior.edit.changed,
            behavior.edit.bounds
        )
    }) or L()

    local acc_children = chain_lists(F.iter(element.children):map(function(child)
        return accessibility_tree(T, child)
    end):totable())

    local accessibility = L {
        T.UiRouted.AccessibilityNode(
            element.id,
            semantic_ref,
            element.accessibility.role,
            element.accessibility.label,
            element.accessibility.description,
            element.accessibility.hidden,
            element.accessibility.sort_priority,
            element.accessibility.bounds,
            acc_children
        )
    }

    return {
        hits = hits,
        focus_chain = focus_chain,
        pointer_routes = pointer_routes,
        scroll_routes = scroll_routes,
        key_routes = key_routes,
        edit_routes = edit_routes,
        accessibility = accessibility,
    }
end

local function merge_route_sets(route_sets)
    return {
        hits = chain_lists(F.iter(route_sets):map(function(s) return s.hits end):totable()),
        focus_chain = chain_lists(F.iter(route_sets):map(function(s) return s.focus_chain end):totable()),
        pointer_routes = chain_lists(F.iter(route_sets):map(function(s) return s.pointer_routes end):totable()),
        scroll_routes = chain_lists(F.iter(route_sets):map(function(s) return s.scroll_routes end):totable()),
        key_routes = chain_lists(F.iter(route_sets):map(function(s) return s.key_routes end):totable()),
        edit_routes = chain_lists(F.iter(route_sets):map(function(s) return s.edit_routes end):totable()),
        accessibility = chain_lists(F.iter(route_sets):map(function(s) return s.accessibility end):totable()),
    }
end

local function element_routes(T, element, depth)
    if not element.visible or not element.enabled then
        return merge_route_sets({
            {
                hits = L(),
                focus_chain = L(),
                pointer_routes = L(),
                scroll_routes = L(),
                key_routes = L(),
                edit_routes = L(),
                accessibility = accessibility_tree(T, element),
            }
        })
    end

    local self_routes = behavior_routes(T, element, depth)
    local child_route_sets = F.iter(element.children):map(function(child)
        return element_routes(T, child, depth + 1)
    end):totable()

    local merged_children = merge_route_sets(child_route_sets)

    return {
        hits = chain_lists { self_routes.hits, merged_children.hits },
        focus_chain = chain_lists { self_routes.focus_chain, merged_children.focus_chain },
        pointer_routes = chain_lists { self_routes.pointer_routes, merged_children.pointer_routes },
        scroll_routes = chain_lists { self_routes.scroll_routes, merged_children.scroll_routes },
        key_routes = chain_lists { self_routes.key_routes, merged_children.key_routes },
        edit_routes = chain_lists { self_routes.edit_routes, merged_children.edit_routes },
        accessibility = self_routes.accessibility,
    }
end

function Routing.install(T)
    T.UiLaid.Scene.route = U.transition(function(scene)
        local route_sets = chain_lists {
            L(F.iter(scene.roots):map(function(root)
                return element_routes(T, root.root, 0)
            end):totable()),
            L(F.iter(scene.overlays):map(function(overlay)
                return element_routes(T, overlay.root, overlay.z_index)
            end):totable()),
        }

        local merged = merge_route_sets(route_sets)

        return T.UiRouted.Scene(
            merged.hits,
            merged.focus_chain,
            merged.pointer_routes,
            merged.scroll_routes,
            merged.key_routes,
            merged.edit_routes,
            merged.accessibility
        )
    end)
end

return Routing
