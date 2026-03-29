local U = require("unit")
local F = require("fun")

local Apply = {}

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
end

local function find_by(xs, pred, where)
    local values = F.iter(xs):filter(pred):totable()
    if #values > 0 then return values[1] end
    error(where, 3)
end

local function option_or(value, fallback)
    if value ~= nil then return value end
    return fallback
end

local function contains(xs, value)
    return F.iter(xs):any(function(v) return v == value end)
end

local function chain_lists(lists)
    local out = {}
    for _, xs in ipairs(lists) do
        for _, v in ipairs(xs) do out[#out + 1] = v end
    end
    return L(out)
end

local function default_text_style(T)
    return T.UiCore.TextStyle(nil, nil, nil, nil, nil, nil, nil)
end

local function default_text_layout(T)
    return T.UiCore.TextLayout(T.UiCore.NoWrap(), T.UiCore.ClipText(), T.UiCore.TextStart(), 1)
end

local function default_image_style(T)
    return T.UiCore.ImageStyle(T.UiCore.StretchImage(), T.UiCore.Linear(), 1.0, T.UiCore.Corners(0, 0, 0, 0))
end

local function default_layout(T)
    return T.UiDecl.Layout(
        T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto()),
        T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto()),
        T.UiCore.InFlow(),
        T.UiCore.None(),
        nil,
        nil,
        T.UiCore.Start(),
        T.UiCore.CrossStart(),
        T.UiCore.Insets(0, 0, 0, 0),
        T.UiCore.Insets(0, 0, 0, 0),
        0,
        T.UiCore.Visible(),
        T.UiCore.Visible(),
        nil
    )
end

local function default_behavior(T)
    return T.UiDecl.Behavior(
        T.UiDecl.HitNone(),
        T.UiDecl.NotFocusable(),
        L(),
        nil,
        L(),
        nil,
        L()
    )
end

local function default_accessibility(T)
    return T.UiDecl.Accessibility(T.UiCore.AccNone(), nil, nil, false, 0)
end

local function merge_patch(T, base, extra)
    return T.DesignResolved.Patch(
        extra.layout or base.layout,
        extra.paint or base.paint,
        extra.content or base.content,
        extra.affordance or base.affordance,
        extra.accessibility or base.accessibility
    )
end

local function variant_selected(active, selection)
    return F.iter(active):any(function(v)
        return v.axis == selection.axis and v.value == selection.value
    end)
end

local function variants_match(active, required)
    return F.iter(required):all(function(selection)
        return variant_selected(active, selection)
    end)
end

local function state_active(active, state)
    return contains(active, state)
end

local function state_selector_matches(active, selector)
    return F.iter(selector.all_of):all(function(state)
        return state_active(active, state)
    end) and F.iter(selector.none_of):all(function(state)
        return not state_active(active, state)
    end)
end

local function find_theme(doc, ref)
    return find_by(doc.themes, function(theme)
        return theme.id == ref
    end, ("DesignUse.Instance:apply: unknown theme ref %s"):format(tostring(ref and ref.value)))
end

local function find_mode(theme, ref)
    return find_by(theme.modes, function(mode)
        return mode.id == ref
    end, ("DesignUse.Instance:apply: unknown mode ref %s"):format(tostring(ref and ref.value)))
end

local function find_recipe(mode, ref)
    return find_by(mode.recipes, function(recipe)
        return recipe.id == ref
    end, ("DesignUse.Instance:apply: unknown recipe ref %s in selected mode"):format(tostring(ref and ref.value)))
end

local function find_slot(recipe, ref)
    return find_by(recipe.slots, function(slot)
        return slot.id == ref
    end, ("DesignUse.Instance:apply: unknown slot ref %s in recipe"):format(tostring(ref and ref.value)))
end

local function find_slot_env(env, ref)
    return find_by(env.slots, function(slot_env)
        return slot_env.slot == ref
    end, ("DesignUse.Instance:apply: missing DesignApply.SlotEnv for slot %s"):format(tostring(ref and ref.value)))
end

local function find_child(env, semantic_ref)
    return find_by(env.children.children, function(child)
        return child.semantic_ref == semantic_ref
    end, ("DesignUse.Instance:apply: missing DesignApply.Child for semantic ref (%s,%s)")
        :format(tostring(semantic_ref and semantic_ref.domain), tostring(semantic_ref and semantic_ref.value)))
end

local function bindings_for_slot(instance, slot_ref)
    return F.iter(instance.slots):filter(function(binding)
        return binding.slot == slot_ref
    end):totable()
end

local function first_binding(bindings, kind)
    local values = F.iter(bindings):filter(function(binding)
        return binding.kind == kind
    end):totable()
    return #values > 0 and values[1] or nil
end

local function child_bindings(bindings)
    local single = F.iter(bindings)
        :filter(function(binding) return binding.kind == "BindChild" end)
        :map(function(binding) return binding.child end)
        :totable()

    local many = F.iter(bindings)
        :filter(function(binding) return binding.kind == "BindChildren" end)
        :map(function(binding) return binding.children end)
        :totable()

    local refs = {}
    for _, ref in ipairs(single) do refs[#refs + 1] = ref end
    for _, group in ipairs(many) do
        for _, ref in ipairs(group) do refs[#refs + 1] = ref end
    end
    return refs
end

local function resolved_patch_for_slot(T, recipe, instance, slot)
    local matching_slot_patches = F.iter(recipe.rules)
        :filter(function(rule)
            return U.match(rule, {
                VariantRule = function(v)
                    return variants_match(instance.variants, v.when)
                end,
                StateRule = function(v)
                    return state_selector_matches(instance.states, v.when)
                end,
            })
        end)
        :map(function(rule)
            local patches = U.match(rule, {
                VariantRule = function(v) return v.patches end,
                StateRule = function(v) return v.patches end,
            })
            return F.iter(patches):filter(function(slot_patch)
                return slot_patch.slot == slot.id
            end):totable()
        end)
        :totable()

    local flattened = {}
    for _, patches in ipairs(matching_slot_patches) do
        for _, slot_patch in ipairs(patches) do
            flattened[#flattened + 1] = slot_patch.patch
        end
    end

    return F.iter(flattened):reduce(function(base, extra)
        return merge_patch(T, base, extra)
    end, slot.base)
end

local function lower_measure(T, measure)
    return U.match(measure, {
        Auto = function() return T.UiCore.Auto() end,
        Px = function(v) return T.UiCore.Px(v.value) end,
        Percent = function(v) return T.UiCore.Percent(v.value) end,
        Content = function() return T.UiCore.Content() end,
        Flex = function(v) return T.UiCore.Flex(v.weight) end,
    })
end

local function lower_size_spec(T, spec)
    return T.UiCore.SizeSpec(
        lower_measure(T, spec.min),
        lower_measure(T, spec.preferred),
        lower_measure(T, spec.max)
    )
end

local function lower_edge(T, edge)
    return U.match(edge, {
        Unset = function() return T.UiCore.Unset() end,
        EdgePx = function(v) return T.UiCore.EdgePx(v.value) end,
        EdgePercent = function(v) return T.UiCore.EdgePercent(v.value) end,
    })
end

local function lower_track(T, track)
    return U.match(track, {
        AutoTrack = function() return T.UiCore.AutoTrack() end,
        PxTrack = function(v) return T.UiCore.PxTrack(v.value) end,
        ContentTrack = function() return T.UiCore.ContentTrack() end,
        FlexTrack = function(v) return T.UiCore.FlexTrack(v.weight) end,
    })
end

local function lower_position(T, env, position)
    return U.match(position, {
        InFlow = function() return T.UiCore.InFlow() end,
        Absolute = function(v)
            return T.UiCore.Absolute(
                lower_edge(T, v.left),
                lower_edge(T, v.top),
                lower_edge(T, v.right),
                lower_edge(T, v.bottom)
            )
        end,
        Anchored = function(v)
            return T.UiCore.Anchored(
                find_slot_env(env, v.target).element_id,
                v.self_x,
                v.self_y,
                v.target_x,
                v.target_y,
                v.dx,
                v.dy
            )
        end,
    })
end

local function lower_layout(T, env, patch)
    if not patch then return default_layout(T) end
    return T.UiDecl.Layout(
        option_or(option_map(patch.width, function(v) return lower_size_spec(T, v) end), T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto())),
        option_or(option_map(patch.height, function(v) return lower_size_spec(T, v) end), T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto())),
        option_or(option_map(patch.position, function(v) return lower_position(T, env, v) end), T.UiCore.InFlow()),
        patch.flow or T.UiCore.None(),
        option_map(patch.grid, function(v)
            return T.UiCore.GridTemplate(
                L(F.iter(v.columns):map(function(track) return lower_track(T, track) end):totable()),
                L(F.iter(v.rows):map(function(track) return lower_track(T, track) end):totable()),
                v.column_gap,
                v.row_gap,
                v.auto_flow
            )
        end),
        patch.cell,
        patch.main_align or T.UiCore.Start(),
        patch.cross_align or T.UiCore.CrossStart(),
        patch.padding or T.UiCore.Insets(0, 0, 0, 0),
        patch.margin or T.UiCore.Insets(0, 0, 0, 0),
        patch.gap or 0,
        patch.overflow_x or T.UiCore.Visible(),
        patch.overflow_y or T.UiCore.Visible(),
        patch.aspect
    )
end

local function lower_paint(T, patch)
    if not patch then return T.UiDecl.Paint(L()) end
    return T.UiDecl.Paint(L(F.iter(patch.ops):map(function(op)
        return U.match(op, {
            Box = function(v)
                return T.UiDecl.Box(v.fill, v.stroke, v.stroke_width, v.align, v.corners)
            end,
            Shadow = function(v)
                return T.UiDecl.Shadow(v.brush, v.blur, v.spread, v.dx, v.dy, v.kind, v.corners)
            end,
            Clip = function(v)
                return T.UiDecl.Clip(v.corners)
            end,
            Opacity = function(v)
                return T.UiDecl.Opacity(v.value)
            end,
            Transform = function(v)
                return T.UiDecl.Transform(v.xform)
            end,
            Blend = function(v)
                return T.UiDecl.Blend(v.mode)
            end,
            CustomPaint = function(v)
                return T.UiDecl.CustomPaint(v.kind, v.payload)
            end,
        })
    end):totable()))
end

local function lower_content(T, patch, bindings)
    local text_binding = first_binding(bindings, "BindText")
    local image_binding = first_binding(bindings, "BindImage")

    if text_binding then
        return U.match(patch or T.DesignResolved.NoContent(), {
            TextContent = function(v)
                return T.UiDecl.Text(text_binding.value, T.UiCore.TextStyle(v.style.font, v.style.size_px, v.style.weight, v.style.slant, v.style.letter_spacing_px, v.style.line_height_px, v.style.color), v.layout)
            end,
            NoContent = function()
                return T.UiDecl.Text(text_binding.value, default_text_style(T), default_text_layout(T))
            end,
            ImageContent = function()
                return T.UiDecl.Text(text_binding.value, default_text_style(T), default_text_layout(T))
            end,
        })
    end

    if image_binding then
        return U.match(patch or T.DesignResolved.NoContent(), {
            ImageContent = function(v)
                return T.UiDecl.Image(image_binding.image, v.style)
            end,
            NoContent = function()
                return T.UiDecl.Image(image_binding.image, default_image_style(T))
            end,
            TextContent = function()
                return T.UiDecl.Image(image_binding.image, default_image_style(T))
            end,
        })
    end

    return T.UiDecl.NoContent()
end

local function lower_hit_policy(T, hit)
    return U.match(hit, {
        HitNone = function() return T.UiDecl.HitNone() end,
        HitSelf = function() return T.UiDecl.HitSelf() end,
        HitSelfAndChildren = function() return T.UiDecl.HitSelfAndChildren() end,
        HitChildrenOnly = function() return T.UiDecl.HitChildrenOnly() end,
    })
end

local function lower_focus_policy(T, focus)
    return U.match(focus, {
        NoFocus = function() return T.UiDecl.NotFocusable() end,
        Focusable = function(v) return T.UiDecl.Focusable(v.mode, v.order) end,
    })
end

local function lower_drag_rule(T, slot_env, drag)
    return U.match(drag, {
        Draggable = function(v)
            if not slot_env.drag_payload then
                error(("DesignUse.Instance:apply: slot %s requires drag_payload env"):format(tostring(slot_env.slot and slot_env.slot.value)), 3)
            end
            return T.UiDecl.Draggable(slot_env.drag_payload, slot_env.drag_begin, slot_env.drag_finish)
        end,
        DropTarget = function(v)
            if not slot_env.drop_command then
                error(("DesignUse.Instance:apply: slot %s requires drop_command env"):format(tostring(slot_env.slot and slot_env.slot.value)), 3)
            end
            return T.UiDecl.DropTarget(v.policy, slot_env.drop_command)
        end,
    })
end

local function lower_behavior(T, patch, slot_env)
    if not patch then return default_behavior(T) end

    local pointer = patch.hover_cursor and L { T.UiDecl.Hover(patch.hover_cursor, nil, nil) } or L()
    local scroll = patch.scroll and T.UiDecl.ScrollRule(patch.scroll.axis, slot_env.scroll_model) or nil
    local edit = patch.edit and (function()
        if not slot_env.text_model then
            error(("DesignUse.Instance:apply: slot %s requires text_model env"):format(tostring(slot_env.slot and slot_env.slot.value)), 3)
        end
        return T.UiDecl.EditRule(slot_env.text_model, patch.edit.multiline, patch.edit.read_only, slot_env.changed)
    end)() or nil
    local drag_drop = patch.drag_drop and L { lower_drag_rule(T, slot_env, patch.drag_drop) } or L()

    return T.UiDecl.Behavior(
        patch.hit and lower_hit_policy(T, patch.hit) or T.UiDecl.HitNone(),
        patch.focus and lower_focus_policy(T, patch.focus) or T.UiDecl.NotFocusable(),
        pointer,
        scroll,
        L(),
        edit,
        drag_drop
    )
end

local function lower_accessibility(T, patch)
    if not patch then return default_accessibility(T) end
    return T.UiDecl.Accessibility(
        patch.role or T.UiCore.AccNone(),
        patch.label,
        patch.description,
        patch.hidden or false,
        0
    )
end

local function disabled_state(T, instance)
    return state_active(instance.states, T.DesignCore.Disabled())
end

function Apply.install(T)
    local apply_slot

    apply_slot = function(instance, recipe, env, slot)
        local slot_env = find_slot_env(env, slot.id)
        local bindings = bindings_for_slot(instance, slot.id)
        local patch = resolved_patch_for_slot(T, recipe, instance, slot)

        local recipe_children = L(F.iter(slot.children):map(function(child_ref)
            return apply_slot(instance, recipe, env, find_slot(recipe, child_ref))
        end):totable())

        local bound_children = L(F.iter(child_bindings(bindings)):map(function(child_ref)
            return find_child(env, child_ref).element
        end):totable())

        local semantic_ref = slot_env.semantic_ref or (slot.id == recipe.root_slot and instance.semantic_ref or nil)

        return T.UiDecl.Element(
            slot_env.element_id,
            semantic_ref,
            slot.name,
            slot.element_role,
            T.UiDecl.Flags(true, not disabled_state(T, instance)),
            lower_layout(T, env, patch.layout),
            lower_paint(T, patch.paint),
            lower_content(T, patch.content, bindings),
            lower_behavior(T, patch.affordance, slot_env),
            lower_accessibility(T, patch.accessibility),
            chain_lists { recipe_children, bound_children }
        )
    end

    T.DesignUse.Instance.apply = U.transition(function(instance, resolved, env)
        local theme_ref = instance.theme or resolved.default_theme
        if not theme_ref then
            error("DesignUse.Instance:apply: theme required (instance.theme or resolved.default_theme)", 2)
        end

        local theme = find_theme(resolved, theme_ref)
        local mode = find_mode(theme, instance.mode or theme.default_mode)
        local recipe = find_recipe(mode, instance.recipe)

        return apply_slot(instance, recipe, env, find_slot(recipe, recipe.root_slot))
    end)
end

return Apply
