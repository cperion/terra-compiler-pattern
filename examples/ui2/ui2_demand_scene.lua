local bit = require("bit")
local U = require("unit")

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
end

-- ============================================================================
-- UiDemand.Scene -> solve -> UiSolved.Scene
-- ----------------------------------------------------------------------------
-- This file implements the fourth ui2 compiler boundary.
--
-- Boundary meaning:
--   solver input language -> solved node-centered scene
--
-- What solve consumes:
--   - flat topology from UiDemand
--   - effective participation state
--   - solver-facing layout refs (including AnchoredTo indices)
--   - prepared text/image demand models
--   - normalized visual input
--   - geometry-query behavior/accessibility demand
--
-- What solve produces:
--   - solved outer/border/padding/content geometry per node
--   - solved child extent / optional scroll extent
--   - local clip shapes + effective active clip
--   - self-contained draw atoms
--   - geometry-attached behavior facts
--   - geometry-attached accessibility facts
--
-- What solve intentionally does NOT do:
--   - no packed render/query planes yet
--   - no kernel specialization yet
--   - no backend-native runtime payload yet
--
-- Current scope of the first implementation:
--   - supports None / Row / Column / Stack flow solving
--   - grid / wrap flows are still rejected explicitly
--   - anchored placement is implemented when the target geometry has already
--     been placed earlier in region placement order; otherwise we fail loudly
--     instead of inventing hidden fixup passes
--   - scroll extents currently use zero offsets because scroll position is not
--     authored UI structure and is not yet modeled in UiSession
--
-- Design note discovered during implementation:
--   UiDemand already had ShadowDecor, but the lower phases originally had no
--   structural place to carry solved/planned/kernel shadow items. Following the
--   compiler pattern, we fixed the ASDL first by threading shadow artifacts
--   through UiSolved / UiPlan / UiKernel rather than dropping them here.
-- ============================================================================

local function require_catalog(catalog, where)
    if catalog then return catalog end
    error((where or "UiDemand.Scene:solve") .. ": UiAsset.Catalog is required", 3)
end

local function id_value(id)
    return id and id.value or nil
end

local function max2(a, b)
    return a > b and a or b
end

local function clamp(v, lo, hi)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function rect(T, x, y, w, h)
    return T.UiCore.Rect(x, y, max2(0, w), max2(0, h))
end

local function size(T, w, h)
    return T.UiCore.Size(max2(0, w), max2(0, h))
end

local function inset_rect(T, r, insets)
    return rect(
        T,
        r.x + insets.left,
        r.y + insets.top,
        r.w - insets.left - insets.right,
        r.h - insets.top - insets.bottom
    )
end

local function corners_are_square(c)
    return c.top_left == 0
       and c.top_right == 0
       and c.bottom_right == 0
       and c.bottom_left == 0
end

local function clip_shape_for(T, r, corners)
    if corners_are_square(corners) then
        return T.UiCore.ClipRect(r)
    end
    return T.UiCore.ClipRoundedRect(r, corners)
end

local function hit_shape_for(T, r, corners)
    if corners_are_square(corners) then
        return T.UiCore.HitRect(r)
    end
    return T.UiCore.HitRoundedRect(r, corners)
end

local function top_clip(clips)
    return clips[#clips]
end

local function next_sibling_index(nodes, index)
    if index == nil then return nil end
    local node = nodes[index]
    return index + node.subtree_count
end

local function measure_value(measure, available, content)
    return U.match(measure, {
        Auto = function() return content end,
        Px = function(v) return v.value end,
        Percent = function(v) return available * v.value end,
        Content = function() return content end,
        Flex = function(_) return available end,
    })
end

local function size_spec_value(spec, available, content)
    local min_v = measure_value(spec.min, available, content)
    local pref_v = measure_value(spec.preferred, available, content)
    local max_raw = measure_value(spec.max, available, content)
    local max_v = (max_raw <= 0 and spec.max.kind == "Auto") and nil or max_raw
    return clamp(pref_v, min_v, max_v)
end

local function is_auto_size_spec(spec)
    return spec.min.kind == "Auto"
       and spec.preferred.kind == "Auto"
       and spec.max.kind == "Auto"
end

local function count_text_lines(text_value, line_limit)
    local raw = text_value and text_value.value or ""
    if raw == "" then return 1 end

    local lines = 1
    for _ in raw:gmatch("\n") do
        lines = lines + 1
    end

    if line_limit and line_limit > 0 and lines > line_limit then
        return line_limit
    end
    return lines
end

local function intrinsic_content_size(T, demand)
    return U.match(demand, {
        NoDemand = function()
            return size(T, 0, 0)
        end,
        TextDemand = function(v)
            local line_count = count_text_lines(v.text.value, v.text.line_limit)
            return size(T, v.text.max_content_w, v.text.line_height_px * line_count)
        end,
        ImageDemand = function(v)
            return v.image.intrinsic
        end,
        CustomDemand = function(_)
            return size(T, 0, 0)
        end,
    })
end

local function node_content_extent(T, node, intrinsic, child_extent)
    local max_w = max2(intrinsic.w, child_extent.w)
    local max_h = max2(intrinsic.h, child_extent.h)

    if node.behavior.scroll ~= nil then
        return T.UiCore.ScrollExtent(max_w, max_h, 0, 0)
    end

    return nil
end

local function local_clip_shapes(T, node, border_box, content_box)
    local out = {}

    for _, effect in ipairs(node.visual.effects) do
        if effect.kind == "LocalClip" then
            out[#out + 1] = clip_shape_for(T, border_box, effect.corners)
        end
    end

    if node.layout.overflow_x.kind ~= "Visible" or node.layout.overflow_y.kind ~= "Visible" then
        out[#out + 1] = clip_shape_for(T, content_box, T.UiCore.Corners(0, 0, 0, 0))
    end

    return out
end

local function resolved_visual_state(T, effects, active_clip)
    local opacity = 1
    local blend = T.UiCore.BlendNormal()
    local transform = nil

    for _, effect in ipairs(effects) do
        U.match(effect, {
            LocalClip = function() end,
            LocalOpacity = function(v)
                opacity = opacity * v.value
            end,
            LocalTransform = function(v)
                transform = v.xform
            end,
            LocalBlend = function(v)
                blend = v.mode
            end,
        })
    end

    return T.UiSolved.VisualState(active_clip, blend, opacity, transform)
end

local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619
local UINT32_MOD = 4294967296

local function hash_text_part(hash, value)
    local s
    if value == nil then
        s = "<nil>"
    elseif type(value) == "table" and value.value ~= nil then
        s = tostring(value.value)
    else
        s = tostring(value)
    end

    for i = 1, #s do
        hash = bit.tobit((bit.bxor(hash, s:byte(i)) * FNV_PRIME) % UINT32_MOD)
    end
    return hash
end

local function text_block_cache_key(text, bounds)
    local hash = FNV_OFFSET
    hash = hash_text_part(hash, text.value and text.value.value or "")
    hash = hash_text_part(hash, text.font and text.font.value or 0)
    hash = hash_text_part(hash, text.size_px)
    hash = hash_text_part(hash, text.color.r)
    hash = hash_text_part(hash, text.color.g)
    hash = hash_text_part(hash, text.color.b)
    hash = hash_text_part(hash, text.color.a)
    hash = hash_text_part(hash, bounds.x)
    hash = hash_text_part(hash, bounds.y)
    hash = hash_text_part(hash, bounds.w)
    hash = hash_text_part(hash, bounds.h)
    hash = hash_text_part(hash, text.wrap.kind)
    hash = hash_text_part(hash, text.align.kind)
    if hash < 0 then hash = hash + UINT32_MOD end
    return hash
end

local function solved_text_block(T, text, bounds)
    return T.UiSolved.TextBlock(
        text_block_cache_key(text, bounds),
        text.value,
        text.font,
        text.size_px,
        text.color,
        bounds,
        text.wrap,
        text.align
    )
end

local function draw_atoms_for(T, _assets, node, geometry, visual_state)
    if not node.state.effective_visible then
        return L {}
    end

    local draws = {}

    for _, decor in ipairs(node.visual.decorations) do
        U.match(decor, {
            BoxDecor = function(v)
                draws[#draws + 1] = T.UiSolved.BoxDraw(
                    geometry.border_box,
                    v.fill,
                    v.stroke,
                    v.stroke_width,
                    v.align,
                    v.corners,
                    visual_state
                )
            end,
            ShadowDecor = function(v)
                draws[#draws + 1] = T.UiSolved.ShadowDraw(
                    geometry.border_box,
                    v.brush,
                    v.blur,
                    v.spread,
                    v.dx,
                    v.dy,
                    v.shadow_kind,
                    v.corners,
                    visual_state
                )
            end,
            CustomDecor = function(v)
                draws[#draws + 1] = T.UiSolved.CustomDraw(v.family, v.payload, visual_state)
            end,
        })
    end

    U.match(node.demand, {
        NoDemand = function() end,
        TextDemand = function(v)
            draws[#draws + 1] = T.UiSolved.TextDraw(
                solved_text_block(T, v.text, geometry.content_box),
                visual_state
            )
        end,
        ImageDemand = function(v)
            draws[#draws + 1] = T.UiSolved.ImageDraw(
                v.image.image,
                geometry.content_box,
                v.image.style.sampling,
                v.image.style.corners,
                visual_state
            )
        end,
        CustomDemand = function(v)
            draws[#draws + 1] = T.UiSolved.CustomDraw(v.family, v.payload, visual_state)
        end,
    })

    return L(draws)
end

local function behavior_node_for(T, node, geometry)
    if not node.state.effective_visible or not node.state.effective_enabled then
        return T.UiSolved.BehaviorNode(nil, nil, L {}, nil, L {}, nil, L {})
    end

    local hit = U.match(node.behavior.hit, {
        NoHit = function()
            return nil
        end,
        SelfHit = function()
            return T.UiSolved.HitNode(hit_shape_for(T, geometry.border_box, T.UiCore.Corners(0, 0, 0, 0)))
        end,
        SelfAndChildrenHit = function()
            return T.UiSolved.HitNode(hit_shape_for(T, geometry.border_box, T.UiCore.Corners(0, 0, 0, 0)))
        end,
        ChildrenOnlyHit = function()
            return nil
        end,
    })

    local focus = node.behavior.focus and T.UiSolved.FocusNode(
        geometry.border_box,
        node.behavior.focus.mode,
        node.behavior.focus.order
    ) or nil

    local scroll = node.behavior.scroll and T.UiSolved.ScrollNode(
        node.behavior.scroll.axis,
        node.behavior.scroll.model,
        geometry.content_box,
        geometry.scroll_extent and size(T, geometry.scroll_extent.content_w, geometry.scroll_extent.content_h)
            or size(T, geometry.child_extent.w, geometry.child_extent.h)
    ) or nil

    local edit = node.behavior.edit and T.UiSolved.EditNode(
        node.behavior.edit.model,
        geometry.content_box,
        node.behavior.edit.multiline,
        node.behavior.edit.read_only,
        node.behavior.edit.changed
    ) or nil

    return T.UiSolved.BehaviorNode(
        hit,
        focus,
        node.behavior.pointer,
        scroll,
        node.behavior.keys,
        edit,
        node.behavior.drag_drop
    )
end

local function accessibility_node_for(T, node, geometry)
    if not node.state.effective_visible then return nil end

    return U.match(node.accessibility, {
        NoAccessibility = function()
            return nil
        end,
        AccessibilityDemand = function(v)
            return T.UiSolved.AccessibilityNode(
                v.role,
                v.label,
                v.description,
                geometry.border_box,
                v.sort_priority
            )
        end,
    })
end

local function content_box_for_child_guess(T, node, intrinsic, available_w, available_h)
    local margin = node.layout.margin
    local padding = node.layout.padding
    local avail_w = max2(0, available_w - margin.left - margin.right)
    local avail_h = max2(0, available_h - margin.top - margin.bottom)
    local border_w = size_spec_value(node.layout.width, avail_w, intrinsic.w + padding.left + padding.right)
    local border_h = size_spec_value(node.layout.height, avail_h, intrinsic.h + padding.top + padding.bottom)
    return size(T, border_w + margin.left + margin.right, border_h + margin.top + margin.bottom)
end

local function positioned_origin_for_flow(node, content_box, cursor_x, cursor_y, child_outer_w, child_outer_h)
    return U.match(node.layout.position, {
        InFlow = function()
            return { x = cursor_x, y = cursor_y, participates = true }
        end,
        Absolute = function(v)
            local left = U.match(v.left, {
                Unset = function() return nil end,
                EdgePx = function(px) return px.value end,
                EdgePercent = function(p) return content_box.w * p.value end,
            })
            local top = U.match(v.top, {
                Unset = function() return nil end,
                EdgePx = function(px) return px.value end,
                EdgePercent = function(p) return content_box.h * p.value end,
            })
            local right = U.match(v.right, {
                Unset = function() return nil end,
                EdgePx = function(px) return px.value end,
                EdgePercent = function(p) return content_box.w * p.value end,
            })
            local bottom = U.match(v.bottom, {
                Unset = function() return nil end,
                EdgePx = function(px) return px.value end,
                EdgePercent = function(p) return content_box.h * p.value end,
            })
            return {
                x = content_box.x + (left or ((right and (content_box.w - right - child_outer_w)) or 0)),
                y = content_box.y + (top or ((bottom and (content_box.h - bottom - child_outer_h)) or 0)),
                participates = false,
            }
        end,
        AnchoredTo = function(_)
            -- For extent solving, anchored nodes do not participate in flow.
            -- Their final origin depends on target geometry and is handled in the
            -- placement pass below.
            return {
                x = content_box.x,
                y = content_box.y,
                participates = false,
            }
        end,
    })
end

local function anchored_origin(T, region_nodes, placed, node, child_outer_w, child_outer_h)
    local target = placed[node.layout.position.target_index]
    if not target then
        error(
            "UiDemand.Scene:solve: anchored target must already be placed in the current implementation; target index "
            .. tostring(node.layout.position.target_index)
            .. " for ElementId(" .. tostring(id_value(node.id)) .. ") was not available",
            3
        )
    end

    local border = target.geometry.border_box
    local position = node.layout.position

    local function anchor_x(which)
        return U.match(which, {
            Left = function() return border.x end,
            CenterX = function() return border.x + border.w / 2 end,
            Right = function() return border.x + border.w end,
        })
    end

    local function anchor_y(which)
        return U.match(which, {
            Top = function() return border.y end,
            CenterY = function() return border.y + border.h / 2 end,
            Bottom = function() return border.y + border.h end,
        })
    end

    local target_x = anchor_x(position.target_x)
    local target_y = anchor_y(position.target_y)
    local self_dx = U.match(position.self_x, {
        Left = function() return 0 end,
        CenterX = function() return child_outer_w / 2 end,
        Right = function() return child_outer_w end,
    })
    local self_dy = U.match(position.self_y, {
        Top = function() return 0 end,
        CenterY = function() return child_outer_h / 2 end,
        Bottom = function() return child_outer_h end,
    })

    return {
        x = target_x - self_dx + position.dx,
        y = target_y - self_dy + position.dy,
        participates = false,
    }
end

local function solve_region(T, assets, region, viewport)
    local nodes = region.nodes
    local outer = {}
    local child_extent = {}
    local placed = {}

    local function compute_outer(index, available_w, available_h)
        if outer[index] then return outer[index] end

        local node = nodes[index]
        local intrinsic = intrinsic_content_size(T, node.demand)
        local margin = node.layout.margin
        local padding = node.layout.padding
        local avail_w = max2(0, available_w - margin.left - margin.right)
        local avail_h = max2(0, available_h - margin.top - margin.bottom)
        local border_w = size_spec_value(node.layout.width, avail_w, intrinsic.w + padding.left + padding.right)
        local border_h = size_spec_value(node.layout.height, avail_h, intrinsic.h + padding.top + padding.bottom)
        local content_box = rect(T, 0, 0, border_w - padding.left - padding.right, border_h - padding.top - padding.bottom)
        local flow = node.layout.flow

        if flow.kind ~= "None" and flow.kind ~= "Row" and flow.kind ~= "Column" and flow.kind ~= "Stack" then
            error("UiDemand.Scene:solve currently supports only None/Row/Column/Stack flows", 3)
        end

        local cursor_x = content_box.x
        local cursor_y = content_box.y
        local max_w = intrinsic.w
        local max_h = intrinsic.h
        local child_index = node.first_child_index

        for _ = 1, node.child_count do
            local child = nodes[child_index]
            local remaining_w = (flow.kind == "Row") and max2(0, content_box.w - (cursor_x - content_box.x)) or content_box.w
            local remaining_h = (flow.kind == "Column") and max2(0, content_box.h - (cursor_y - content_box.y)) or content_box.h
            local child_intrinsic = intrinsic_content_size(T, child.demand)
            local child_guess = content_box_for_child_guess(T, child, child_intrinsic, remaining_w, remaining_h)
            local pos = positioned_origin_for_flow(child, content_box, cursor_x, cursor_y, child_guess.w, child_guess.h)
            local child_outer = compute_outer(child_index, remaining_w, remaining_h)

            if pos.participates then
                if flow.kind == "Row" then
                    cursor_x = cursor_x + child_outer.w + node.layout.gap
                    max_w = max_w + child_outer.w + node.layout.gap
                    max_h = max2(max_h, child_outer.h)
                elseif flow.kind == "Column" then
                    cursor_y = cursor_y + child_outer.h + node.layout.gap
                    max_h = max_h + child_outer.h + node.layout.gap
                    max_w = max2(max_w, child_outer.w)
                else
                    max_w = max2(max_w, child_outer.w)
                    max_h = max2(max_h, child_outer.h)
                end
            else
                max_w = max2(max_w, child_outer.w)
                max_h = max2(max_h, child_outer.h)
            end

            child_index = next_sibling_index(nodes, child_index)
        end

        if node.child_count > 0 then
            if flow.kind == "Row" then
                max_w = max_w - node.layout.gap
            elseif flow.kind == "Column" then
                max_h = max_h - node.layout.gap
            end
        end

        child_extent[index] = size(T, max2(0, max_w), max2(0, max_h))

        if is_auto_size_spec(node.layout.width) then
            border_w = max2(border_w, child_extent[index].w + padding.left + padding.right)
        end
        if is_auto_size_spec(node.layout.height) then
            border_h = max2(border_h, child_extent[index].h + padding.top + padding.bottom)
        end

        outer[index] = size(T, border_w + margin.left + margin.right, border_h + margin.top + margin.bottom)
        return outer[index]
    end

    local function place_node(index, origin_x, origin_y, parent_clip)
        local node = nodes[index]
        local margin = node.layout.margin
        local padding = node.layout.padding
        local node_outer = outer[index]
        local border_w = max2(0, node_outer.w - margin.left - margin.right)
        local border_h = max2(0, node_outer.h - margin.top - margin.bottom)
        local border_box = rect(T, origin_x + margin.left, origin_y + margin.top, border_w, border_h)
        local padding_box = border_box
        local content_box = inset_rect(T, border_box, padding)
        local local_clips = L(local_clip_shapes(T, node, border_box, content_box))
        local active_clip = top_clip(local_clips) or parent_clip
        local geometry = T.UiSolved.Geometry(
            node_outer,
            border_box,
            padding_box,
            content_box,
            child_extent[index],
            node_content_extent(T, node, intrinsic_content_size(T, node.demand), child_extent[index])
        )
        local visual_state = resolved_visual_state(T, node.visual.effects, active_clip)

        placed[index] = T.UiSolved.Node(
            node.index,
            node.parent_index,
            node.first_child_index,
            node.child_count,
            node.subtree_count,
            node.id,
            node.semantic_ref,
            node.debug_name,
            node.role,
            T.UiSolved.SolvedState(node.state.effective_visible, node.state.effective_enabled),
            geometry,
            local_clips,
            active_clip,
            draw_atoms_for(T, assets, node, geometry, visual_state),
            behavior_node_for(T, node, geometry),
            accessibility_node_for(T, node, geometry)
        )

        local flow = node.layout.flow
        local cursor_x = content_box.x
        local cursor_y = content_box.y
        local child_index = node.first_child_index

        for _ = 1, node.child_count do
            local child = nodes[child_index]
            local child_outer = outer[child_index]
            local pos = U.match(child.layout.position, {
                InFlow = function()
                    return positioned_origin_for_flow(child, content_box, cursor_x, cursor_y, child_outer.w, child_outer.h)
                end,
                Absolute = function()
                    return positioned_origin_for_flow(child, content_box, cursor_x, cursor_y, child_outer.w, child_outer.h)
                end,
                AnchoredTo = function()
                    return anchored_origin(T, nodes, placed, child, child_outer.w, child_outer.h)
                end,
            })

            place_node(child_index, pos.x, pos.y, active_clip)

            if pos.participates then
                if flow.kind == "Row" then
                    cursor_x = cursor_x + child_outer.w + node.layout.gap
                elseif flow.kind == "Column" then
                    cursor_y = cursor_y + child_outer.h + node.layout.gap
                end
            end

            child_index = next_sibling_index(nodes, child_index)
        end
    end

    compute_outer(region.root_index, viewport.w, viewport.h)
    place_node(region.root_index, 0, 0, nil)

    return T.UiSolved.Region(
        region.id,
        region.debug_name,
        region.root_index,
        region.z_index,
        region.modal,
        region.consumes_pointer,
        L(placed)
    )
end

return function(T)
    -- ---------------------------------------------------------------------
    -- Public boundary:
    --   UiDemand.Scene:solve(assets) -> UiSolved.Scene
    -- ---------------------------------------------------------------------
    -- Required side input:
    --   assets : UiAsset.Catalog
    --
    -- Why assets are still explicit here:
    --   this boundary remains part of the compiler path and may still need
    --   explicit resource-backed solving inputs as the machine evolves.
    T.UiDemand.Scene.solve = U.transition(function(scene, assets)
        require_catalog(assets, "UiDemand.Scene:solve")

        local regions = {}
        for _, region in ipairs(scene.regions) do
            regions[#regions + 1] = solve_region(T, assets, region, scene.viewport)
        end

        return T.UiSolved.Scene(scene.viewport, L(regions))
    end)
end
