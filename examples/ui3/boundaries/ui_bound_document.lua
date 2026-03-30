local asdl = require("asdl")
local U = require("unit")

local List = asdl.List

local function L(xs)
    return List(xs or {})
end

local function require_viewport(T, viewport, where)
    if viewport then return viewport end
    error((where or "UiBound.Document:flatten") .. ": UiCore.Size viewport is required", 3)
end

local function flat_node_header(T, index, parent_index, first_child_index, child_count, subtree_count, node)
    return T.UiFlatShape.NodeHeader(
        index,
        parent_index,
        first_child_index,
        child_count,
        subtree_count,
        node.id,
        node.semantic_ref,
        node.debug_name,
        node.role
    )
end

local function flatten_entry(T, entry)
    local headers = {}
    local visibility = {}
    local interactivity = {}
    local layout = {}
    local content = {}
    local paint = {}
    local behavior = {}
    local accessibility = {}
    local next_index = 1

    local function flatten_node(node, parent_index)
        local index = next_index
        next_index = next_index + 1

        local child_count = #node.children
        local first_child_index = child_count > 0 and next_index or nil

        local i = 1
        while i <= child_count do
            flatten_node(node.children[i], index)
            i = i + 1
        end

        headers[index] = flat_node_header(
            T,
            index,
            parent_index,
            first_child_index,
            child_count,
            next_index - index,
            node
        )
        visibility[index] = T.UiFlat.VisibilityFacet(node.flags.visible)
        interactivity[index] = T.UiFlat.InteractivityFacet(node.flags.enabled)
        layout[index] = T.UiFlat.LayoutFacet(node.layout)
        content[index] = T.UiFlat.ContentFacet(node.content)
        paint[index] = T.UiFlat.PaintFacet(node.paint)
        behavior[index] = T.UiFlat.BehaviorFacet(node.behavior)
        accessibility[index] = T.UiFlat.AccessibilityFacet(node.accessibility)

        return index
    end

    local root_index = flatten_node(entry.root, nil)

    return T.UiFlat.Region(
        T.UiFlatShape.RegionHeader(entry.id, entry.debug_name, root_index),
        T.UiFlat.RenderRegionFacet(entry.z_index),
        T.UiFlat.QueryRegionFacet(entry.modal, entry.consumes_pointer),
        L(headers),
        L(visibility),
        L(interactivity),
        L(layout),
        L(content),
        L(paint),
        L(behavior),
        L(accessibility)
    )
end

return function(T)
    T.UiBound.Document.flatten = U.transition(function(document, viewport)
        viewport = require_viewport(T, viewport, "UiBound.Document:flatten")

        local regions = {}
        local i = 1
        while i <= #document.entries do
            regions[#regions + 1] = flatten_entry(T, document.entries[i])
            i = i + 1
        end

        return T.UiFlat.Scene(viewport, L(regions))
    end)
end
