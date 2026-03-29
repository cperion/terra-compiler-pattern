local U = require("unit")
local Assets = require("examples.ui.ui_asset_resolve")
local RawText = require("examples.ui.backend_text_sdl_ttf")
local ImageData = require("examples.ui.backend_image_sdl")

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
end

-- ============================================================================
-- UiFlat.Scene -> prepare_demands -> UiDemand.Scene
-- ----------------------------------------------------------------------------
-- This file implements the third ui2 compiler boundary.
--
-- Boundary meaning:
--   explicit flat topology + bound semantics -> explicit solver input language
--
-- What prepare_demands consumes:
--   - flat region-local topology from UiFlat
--   - bound semantic payload on each node
--   - explicit asset catalog for intrinsic text/image preparation
--   - ancestry state for effective visibility / enablement
--
-- What prepare_demands produces:
--   - effective participation state on every node
--   - solver-facing anchored target indices
--   - prepared local intrinsic demand models for text/image/custom content
--   - normalized visual input separated into effects + decorations
--   - geometry-query behavior demand vocabulary
--   - geometry-query accessibility demand vocabulary
--
-- What prepare_demands intentionally does NOT do:
--   - no geometry solving
--   - no clip solving from overflow/geometry
--   - no text shaping or line placement
--   - no draw atoms
--   - no packed render/query plan arrays
--
-- Key policy decisions embodied here:
--   - anchored targets become region-local node indices here, not earlier
--   - effective visibility / enablement is ancestry-folded here, not later
--   - paint is decomposed into solver-relevant visual inputs here
--   - intrinsic text/image demand is prepared here, but final shaping/fit is not
--
-- Important implementation note:
--   This phase still stays pure in the Terra Compiler Pattern sense. It uses
--   the explicit asset catalog to ask local measurement questions, but it does
--   not create backend-native runtime objects or mutate global UI state.
-- ============================================================================

local DEFAULT_IMAGE_INTRINSIC_W = 64
local DEFAULT_IMAGE_INTRINSIC_H = 64

local function require_catalog(catalog, where)
    if catalog then return catalog end
    error((where or "UiFlat.Scene:prepare_demands") .. ": UiAsset.Catalog is required", 3)
end

local function id_value(id)
    return id and id.value or nil
end

local function max2(a, b)
    return a > b and a or b
end

local function text_style_for(T, text)
    return T.UiCore.TextStyle(
        text.font,
        text.size_px,
        text.weight,
        text.slant,
        text.letter_spacing_px,
        text.line_height_px,
        text.color
    )
end

local function text_layout_for(T, text, wrap)
    return T.UiCore.TextLayout(
        wrap or text.wrap,
        text.overflow,
        text.align,
        text.line_limit
    )
end

local function measure_text(T, assets, text, wrap, max_width)
    local font_path = Assets.font_path(require_catalog(assets, "UiFlat.Scene:prepare_demands"), text.font)
    local measured = RawText.measure(
        nil,
        font_path,
        text.value,
        text_style_for(T, text),
        text_layout_for(T, text, wrap),
        max_width
    )
    return T.UiCore.Size(measured.w, measured.h)
end

local function max_word_width(T, assets, text)
    local raw = text.value and text.value.value or ""
    local best = 0

    for word in raw:gmatch("%S+") do
        local measured = RawText.measure(
            nil,
            Assets.font_path(assets, text.font),
            T.UiCore.TextValue(word),
            text_style_for(T, text),
            text_layout_for(T, text, T.UiCore.NoWrap()),
            nil
        )
        best = max2(best, measured.w)
    end

    return best
end

local function max_char_width(T, assets, text)
    local raw = text.value and text.value.value or ""
    local best = 0

    -- We prefer UTF-8 codepoint iteration when available so wrap-char demand is
    -- at least approximately character-aware instead of byte-aware.
    local ok, err = pcall(function()
        for _, codepoint in utf8.codes(raw) do
            local ch = utf8.char(codepoint)
            local measured = RawText.measure(
                nil,
                Assets.font_path(assets, text.font),
                T.UiCore.TextValue(ch),
                text_style_for(T, text),
                text_layout_for(T, text, T.UiCore.NoWrap()),
                nil
            )
            best = max2(best, measured.w)
        end
    end)

    if ok then return best end

    -- If the source string is malformed UTF-8, fall back to a conservative
    -- whole-string width rather than failing the entire compiler boundary.
    -- This keeps the demand model total while later validation can still decide
    -- how to surface malformed text if desired.
    local _ = err
    local measured = measure_text(T, assets, text, T.UiCore.NoWrap(), nil)
    return measured.w
end

local function prepared_text(T, assets, text)
    local max_content = measure_text(T, assets, text, T.UiCore.NoWrap(), nil)

    local min_content_w = U.match(text.wrap, {
        NoWrap = function()
            return max_content.w
        end,
        WrapWord = function()
            return max_word_width(T, assets, text)
        end,
        WrapChar = function()
            return max_char_width(T, assets, text)
        end,
    })

    return T.UiDemand.PreparedText(
        text.value,
        text.font,
        text.size_px,
        text.weight,
        text.slant,
        text.letter_spacing_px,
        text.line_height_px,
        text.color,
        text.wrap,
        text.overflow,
        text.align,
        text.line_limit,
        min_content_w,
        max_content.w
    )
end

local function image_intrinsic(T, assets, image)
    local path = Assets.image_path(require_catalog(assets, "UiFlat.Scene:prepare_demands"), image.image)
    local ok, w, h = pcall(ImageData.size, path)
    if ok and w and h then
        return T.UiCore.Size(w, h)
    end

    return T.UiCore.Size(DEFAULT_IMAGE_INTRINSIC_W, DEFAULT_IMAGE_INTRINSIC_H)
end

local function demand_model_for(T, assets, content)
    return U.match(content, {
        NoContent = function()
            return T.UiDemand.NoDemand()
        end,
        Text = function(v)
            return T.UiDemand.TextDemand(prepared_text(T, assets, v.text))
        end,
        Image = function(v)
            return T.UiDemand.ImageDemand(
                T.UiDemand.PreparedImage(
                    v.image.image,
                    v.image.style,
                    image_intrinsic(T, assets, v.image)
                )
            )
        end,
        CustomContent = function(v)
            return T.UiDemand.CustomDemand(v.family, v.payload)
        end,
    })
end

local function visual_input_for(T, paint)
    local effects = {}
    local decorations = {}

    for _, op in ipairs(paint.ops) do
        U.match(op, {
            Box = function(v)
                decorations[#decorations + 1] = T.UiDemand.BoxDecor(
                    v.fill,
                    v.stroke,
                    v.stroke_width,
                    v.align,
                    v.corners
                )
            end,
            Shadow = function(v)
                decorations[#decorations + 1] = T.UiDemand.ShadowDecor(
                    v.brush,
                    v.blur,
                    v.spread,
                    v.dx,
                    v.dy,
                    v.shadow_kind,
                    v.corners
                )
            end,
            Clip = function(v)
                effects[#effects + 1] = T.UiDemand.LocalClip(v.corners)
            end,
            Opacity = function(v)
                effects[#effects + 1] = T.UiDemand.LocalOpacity(v.value)
            end,
            Transform = function(v)
                effects[#effects + 1] = T.UiDemand.LocalTransform(v.xform)
            end,
            Blend = function(v)
                effects[#effects + 1] = T.UiDemand.LocalBlend(v.mode)
            end,
            CustomPaint = function(v)
                decorations[#decorations + 1] = T.UiDemand.CustomDecor(v.family, v.payload)
            end,
        })
    end

    return T.UiDemand.VisualInput(L(effects), L(decorations))
end

local function hit_demand_for(T, hit)
    return U.match(hit, {
        HitNone = function() return T.UiDemand.NoHit() end,
        HitSelf = function() return T.UiDemand.SelfHit() end,
        HitSelfAndChildren = function() return T.UiDemand.SelfAndChildrenHit() end,
        HitChildrenOnly = function() return T.UiDemand.ChildrenOnlyHit() end,
    })
end

local function pointer_binding_for(T, binding)
    return U.match(binding, {
        Hover = function(v)
            return T.UiDemand.HoverBinding(v.cursor, v.enter, v.leave)
        end,
        Press = function(v)
            return T.UiDemand.PressBinding(v.button, v.click_count, v.command)
        end,
        Toggle = function(v)
            return T.UiDemand.ToggleBinding(v.value, v.button, v.command)
        end,
        Gesture = function(v)
            return T.UiDemand.GestureBinding(v.gesture, v.command)
        end,
    })
end

local function drag_drop_binding_for(T, binding)
    return U.match(binding, {
        Draggable = function(v)
            return T.UiDemand.DraggableBinding(v.payload, v.begin, v.finish)
        end,
        DropTarget = function(v)
            return T.UiDemand.DropTargetBinding(v.policy, v.command)
        end,
    })
end

local function behavior_input_for(T, behavior)
    local pointer = {}
    for _, binding in ipairs(behavior.pointer) do
        pointer[#pointer + 1] = pointer_binding_for(T, binding)
    end

    local keys = {}
    for _, binding in ipairs(behavior.keys) do
        keys[#keys + 1] = T.UiDemand.KeyBinding(
            binding.chord,
            binding.when,
            binding.command,
            binding.global
        )
    end

    local drag_drop = {}
    for _, binding in ipairs(behavior.drag_drop) do
        drag_drop[#drag_drop + 1] = drag_drop_binding_for(T, binding)
    end

    return T.UiDemand.BehaviorInput(
        hit_demand_for(T, behavior.hit),
        U.match(behavior.focus, {
            NotFocusable = function() return nil end,
            Focusable = function(v) return T.UiDemand.Focusable(v.mode, v.order) end,
        }),
        L(pointer),
        behavior.scroll and T.UiDemand.ScrollDemand(behavior.scroll.axis, behavior.scroll.model) or nil,
        L(keys),
        behavior.edit and T.UiDemand.EditDemand(
            behavior.edit.model,
            behavior.edit.multiline,
            behavior.edit.read_only,
            behavior.edit.changed
        ) or nil,
        L(drag_drop)
    )
end

local function accessibility_input_for(T, accessibility)
    return U.match(accessibility, {
        Hidden = function()
            return T.UiDemand.NoAccessibility()
        end,
        Exposed = function(v)
            return T.UiDemand.AccessibilityDemand(
                v.role,
                v.label,
                v.description,
                v.sort_priority
            )
        end,
    })
end

local function layout_input_for(T, node, id_to_index)
    local position = U.match(node.layout.position, {
        InFlow = function()
            return T.UiDemand.InFlow()
        end,
        Absolute = function(v)
            return T.UiDemand.Absolute(v.left, v.top, v.right, v.bottom)
        end,
        Anchored = function(v)
            local target_index = id_to_index[id_value(v.target.target)]
            if not target_index then
                error(
                    "UiFlat.Scene:prepare_demands: missing region-local anchor target index for ElementId("
                    .. tostring(id_value(v.target.target))
                    .. ") in node ElementId("
                    .. tostring(id_value(node.id))
                    .. ")",
                    3
                )
            end

            return T.UiDemand.AnchoredTo(
                target_index,
                v.self_x,
                v.self_y,
                v.target_x,
                v.target_y,
                v.dx,
                v.dy
            )
        end,
    })

    return T.UiDemand.LayoutInput(
        node.layout.width,
        node.layout.height,
        position,
        node.layout.flow,
        node.layout.grid,
        node.layout.cell,
        node.layout.main_align,
        node.layout.cross_align,
        node.layout.padding,
        node.layout.margin,
        node.layout.gap,
        node.layout.overflow_x,
        node.layout.overflow_y,
        node.layout.aspect
    )
end

local function region_id_index(region)
    local out = {}
    for _, node in ipairs(region.nodes) do
        out[id_value(node.id)] = node.index
    end
    return out
end

local function demand_region(T, assets, region)
    local id_to_index = region_id_index(region)
    local demand_nodes = {}

    -- Effective state is folded structurally using the already-explicit
    -- parent_index links. This consumes ancestry participation knowledge here
    -- so later phases can operate on direct booleans instead of repeatedly
    -- climbing the tree.
    for _, node in ipairs(region.nodes) do
        local parent_state = nil
        if node.parent_index ~= nil then
            parent_state = demand_nodes[node.parent_index].state
        end

        local local_visible = node.flags.visible
        local local_enabled = node.flags.enabled
        local effective_visible = local_visible and (parent_state == nil or parent_state.effective_visible)
        local effective_enabled = local_enabled and (parent_state == nil or parent_state.effective_enabled)

        demand_nodes[node.index] = T.UiDemand.Node(
            node.index,
            node.parent_index,
            node.first_child_index,
            node.child_count,
            node.subtree_count,
            node.id,
            node.semantic_ref,
            node.debug_name,
            node.role,
            T.UiDemand.NodeState(
                local_visible,
                local_enabled,
                effective_visible,
                effective_enabled
            ),
            layout_input_for(T, node, id_to_index),
            demand_model_for(T, assets, node.content),
            visual_input_for(T, node.paint),
            behavior_input_for(T, node.behavior),
            accessibility_input_for(T, node.accessibility)
        )
    end

    return T.UiDemand.Region(
        region.id,
        region.debug_name,
        region.root_index,
        region.z_index,
        region.modal,
        region.consumes_pointer,
        L(demand_nodes)
    )
end

return function(T)
    -- ---------------------------------------------------------------------
    -- Public boundary:
    --   UiFlat.Scene:prepare_demands(assets) -> UiDemand.Scene
    -- ---------------------------------------------------------------------
    -- Required side input:
    --   assets : UiAsset.Catalog
    --
    -- Why assets are explicit here:
    --   intrinsic text/image preparation needs catalog-backed resource facts,
    --   especially font lookup for text measurement. This is compiler input,
    --   not ambient runtime state, so the catalog remains an explicit argument.
    T.UiFlat.Scene.prepare_demands = U.transition(function(scene, assets)
        require_catalog(assets, "UiFlat.Scene:prepare_demands")

        local regions = {}
        for _, region in ipairs(scene.regions) do
            regions[#regions + 1] = demand_region(T, assets, region)
        end

        return T.UiDemand.Scene(scene.viewport, L(regions))
    end)
end
