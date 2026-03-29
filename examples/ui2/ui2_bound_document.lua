local U = require("unit")

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
end


-- ============================================================================
-- UiBound.Document -> flatten -> UiFlat.Scene
-- ----------------------------------------------------------------------------
-- This file implements the second ui2 compiler boundary.
--
-- Boundary meaning:
--   bound semantic tree -> explicit flat region topology
--
-- What flatten consumes:
--   - recursive containment as implicit structure
--   - root/child nesting inside each UiBound.Entry subtree
--
-- What flatten produces:
--   - one UiFlat.Region per UiBound.Entry
--   - one region-local UiFlat.Node array per region
--   - explicit parent/child/subtree topology metadata
--   - preserved bound semantic payload on every flat node
--
-- What flatten intentionally does NOT do:
--   - no effective visibility propagation
--   - no anchor resolution to indices yet
--   - no demand/intrinsic preparation
--   - no layout solving
--   - no shaping / clips / draw atoms
--   - no route extraction or packed planes
--
-- Core flattening policy:
--   - one region-local node array per entry
--   - region-local indices start at 1
--   - indices are assigned in pre-order depth-first order
--   - each subtree occupies one contiguous span
--   - subtree_count counts nodes, not the terminal index
--
-- Why this phase exists:
--   The solver and later packed planning phases want explicit structural spans
--   and region-local indices. Flatten consumes only containment, and nothing
--   else, so later phases can talk about topology without having to walk trees
--   or re-derive structural facts.
-- ============================================================================

local function require_viewport(T, viewport, where)
    if viewport then return viewport end
    error((where or "UiBound.Document:flatten") .. ": UiCore.Size viewport is required", 3)
end

local function flatten_entry(T, entry)
    local Node = T.UiFlat.Node
    local Region = T.UiFlat.Region

    local nodes = {}
    local next_index = 1

    local function new_flat_node(index, parent_index, first_child_index, child_count, subtree_count, node)
        return Node(
            index,
            parent_index,
            first_child_index,
            child_count,
            subtree_count,
            node.id,
            node.semantic_ref,
            node.debug_name,
            node.role,
            node.flags,
            node.layout,
            node.paint,
            node.content,
            node.behavior,
            node.accessibility
        )
    end

    local function new_flat_region(root_index)
        return Region(
            entry.id,
            entry.debug_name,
            root_index,
            entry.z_index,
            entry.modal,
            entry.consumes_pointer,
            L(nodes)
        )
    end

    -- ---------------------------------------------------------------------
    -- flatten_node(node, parent_index)
    -- ---------------------------------------------------------------------
    -- Assign one region-local index in pre-order, recurse through children in
    -- source order, then finalize the flat node once we know the subtree span.
    --
    -- Important invariants maintained here:
    --   - the node's own index is assigned before visiting descendants
    --   - if the node has children, the first immediate child will always be
    --     assigned the next index in pre-order
    --   - because recursion is depth-first, when we return from all children,
    --     next_index points one past the end of the subtree
    --   - therefore subtree_count = next_index - index
    -- ---------------------------------------------------------------------
    local function flatten_node(node, parent_index)
        local index = next_index
        next_index = next_index + 1

        local children = node.children
        local child_count = #children
        local first_child_index = child_count > 0 and next_index or nil

        for i = 1, child_count do
            flatten_node(children[i], index)
        end

        nodes[index] = new_flat_node(
            index,
            parent_index,
            first_child_index,
            child_count,
            next_index - index,
            node
        )

        return index
    end

    return new_flat_region(flatten_node(entry.root, nil))
end

return function(T)
    -- ---------------------------------------------------------------------
    -- Public boundary: UiBound.Document:flatten(viewport) -> UiFlat.Scene
    -- ---------------------------------------------------------------------
    -- Required side input:
    --   viewport : UiCore.Size
    --
    -- Why viewport is explicit here even though flatten is mostly structural:
    --   UiFlat.Scene is already the first scene-level flat product, and its
    --   type includes viewport as explicit scene context. The viewport is not
    --   hidden ambient runtime state; it is an ordinary compiler input coming
    --   from UiSession.State or another caller-owned scene source.
    --
    -- Policy:
    --   flatten requires the viewport argument explicitly. We do not silently
    --   invent a default viewport here because ui2's side-input policy is that
    --   cross-phase dependencies remain visible in boundary signatures.
    T.UiBound.Document.flatten = U.transition(function(document, viewport)
        viewport = require_viewport(T, viewport, "UiBound.Document:flatten")

        local regions = {}
        for _, entry in ipairs(document.entries) do
            regions[#regions + 1] = flatten_entry(T, entry)
        end

        return T.UiFlat.Scene(
            viewport,
            L(regions)
        )
    end)
end
