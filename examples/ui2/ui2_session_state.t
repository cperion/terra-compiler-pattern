local U = require("unit")
local F = require("fun")

local function L(xs)
    return terralib.newlist(xs or {})
end

-- ============================================================================
-- UiSession.State initial/apply/apply_with_intents
-- ----------------------------------------------------------------------------
-- This file implements the pure ui2 interaction reducer plus the semantic
-- intent projection that sits on top of it.
--
-- Meanings:
--   UiSession.State.initial(viewport) -> UiSession.State
--   UiSession.State:apply(plan, event) -> UiSession.State
--   UiSession.State:apply_with_intents(plan, event) -> UiApply.Result
--
-- Domain role:
--   UiInput.Event is the raw input language.
--   UiSession.State is the reducer-owned interaction state.
--   UiPlan.Scene is the packed query plane consulted by the reducer.
--   UiIntent.Event is the semantic output language emitted after routing.
--
-- Design split:
--   apply_with_intents is the full explicit reducer result.
--   apply is the convenience projection to just the next session state.
--
-- This preserves both stories cleanly:
--   - the pattern's explicit semantic-output language
--   - the simple (state, event) -> state reducer helper many callers want
--
-- Current scope:
--   - region-first hit testing over UiPlan.Region spans
--   - hover / focus / press / toggle / scroll / key / text semantic intents
--   - viewport updates from UiInput.ViewportResized
--   - window focus loss clears hover/capture/pressed and emits hover/focus loss
--
-- Functional-style note:
--   This file follows the repository convention: small pure helpers,
--   map/filter/reduce style list construction, and explicit structural
--   construction for nil-clearing session updates.
-- ============================================================================

local unpack_fn = table.unpack or unpack

local function point(T, x, y)
    return T.UiCore.Point(x, y)
end

local function default_viewport(T)
    return T.UiCore.Size(1280, 720)
end

local function chain_lists(lists)
    if #lists == 0 then return L() end
    return L(F.chain(unpack_fn(lists)):totable())
end

local function with_state(T, state, overrides)
    local has = rawget
    return T.UiSession.State(
        has(overrides, "viewport") ~= nil and overrides.viewport or state.viewport,
        has(overrides, "pointer") ~= nil and overrides.pointer or state.pointer,
        has(overrides, "pointer_in_bounds") ~= nil and overrides.pointer_in_bounds or state.pointer_in_bounds,
        has(overrides, "window_focused") ~= nil and overrides.window_focused or state.window_focused,
        has(overrides, "pressed") ~= nil and overrides.pressed or state.pressed,
        has(overrides, "hovered") ~= nil and overrides.hovered or state.hovered,
        has(overrides, "focused") ~= nil and overrides.focused or state.focused,
        has(overrides, "captured") ~= nil and overrides.captured or state.captured,
        has(overrides, "drag") ~= nil and overrides.drag or state.drag
    )
end

local function same_button(a, b)
    if a == b then return true end
    if a == nil or b == nil then return false end
    return a.kind == b.kind
end

local function same_element_id(a, b)
    if a == b then return true end
    if a == nil or b == nil then return false end
    return a.value == b.value
end

local function same_key_chord(a, b)
    if a == b then return true end
    if a == nil or b == nil then return false end
    return a.ctrl == b.ctrl
       and a.alt == b.alt
       and a.shift == b.shift
       and a.meta == b.meta
       and a.keycode == b.keycode
end

local function pressed_without(state, button)
    return L(F.iter(state.pressed)
        :filter(function(press) return not same_button(press.button, button) end)
        :totable())
end

local function point_in_shape(shape, p)
    return U.match(shape, {
        HitRect = function(v)
            local r = v.rect
            return p.x >= r.x and p.y >= r.y and p.x <= (r.x + r.w) and p.y <= (r.y + r.h)
        end,
        HitRoundedRect = function(v)
            local r = v.rect
            return p.x >= r.x and p.y >= r.y and p.x <= (r.x + r.w) and p.y <= (r.y + r.h)
        end,
    })
end

local function region_hit(plan, region, p)
    local start_ix = region.hit_start
    local end_ix = region.hit_start + region.hit_count - 1

    for i = end_ix, start_ix, -1 do
        local hit = plan.hits[i]
        if point_in_shape(hit.shape, p) then
            return hit
        end
    end

    return nil
end

local function top_hit(plan, p)
    for region_ix = #plan.regions, 1, -1 do
        local region = plan.regions[region_ix]
        local hit = region_hit(plan, region, p)
        if hit then return hit end
        if region.modal or region.consumes_pointer then
            return nil
        end
    end

    return nil
end

local function hover_binding_for(hit)
    if not hit then return nil end
    return F.iter(hit.pointer)
        :filter(function(binding) return binding.kind == "HoverBinding" end)
        :nth(1)
end

local function press_bindings_for(hit, button)
    if not hit then return {} end
    return F.iter(hit.pointer)
        :filter(function(binding)
            return (binding.kind == "PressBinding" or binding.kind == "ToggleBinding")
               and same_button(binding.button, button)
               and ((binding.kind ~= "PressBinding") or binding.click_count == 1)
        end)
        :totable()
end

local function hit_item_for(plan, element_id)
    return F.iter(plan.hits)
        :filter(function(item) return same_element_id(item.id, element_id) end)
        :nth(1)
end

local function focus_item_for(plan, element_id)
    return F.iter(plan.focus_chain)
        :filter(function(item) return same_element_id(item.id, element_id) end)
        :nth(1)
end

local function edit_host_for(plan, element_id)
    return F.iter(plan.edit_hosts)
        :filter(function(item) return same_element_id(item.id, element_id) end)
        :nth(1)
end

local function key_routes_for(plan, focused, chord, when)
    return F.iter(plan.key_routes)
        :filter(function(route)
            return same_key_chord(route.chord, chord)
               and route.when.kind == when.kind
               and (route.global or same_element_id(route.id, focused))
        end)
        :totable()
end

local function with_pointer_target(T, state, p)
    return with_state(T, state, {
        pointer = p,
        pointer_in_bounds = true,
    })
end

local function with_hover_from_point(T, state, plan, p)
    local hit = top_hit(plan, p)
    local next_state = with_pointer_target(T, state, p)

    if hit then
        return with_state(T, next_state, {
            hovered = hit.id,
        }), hit
    end

    return T.UiSession.State(
        next_state.viewport,
        next_state.pointer,
        next_state.pointer_in_bounds,
        next_state.window_focused,
        next_state.pressed,
        nil,
        next_state.focused,
        next_state.captured,
        next_state.drag
    ), nil
end

local function hover_intents(T, state, plan, hit)
    local old_hover = state.hovered
    local new_hover = hit and hit.id or nil
    if same_element_id(old_hover, new_hover) then return L() end

    local old_hit = old_hover and hit_item_for(plan, old_hover) or nil
    local old_hover_binding = hover_binding_for(old_hit)
    local new_hover_binding = hover_binding_for(hit)
    local old_semantic_ref = old_hit and old_hit.semantic_ref or nil

    return chain_lists {
        old_hover_binding and old_hover_binding.leave and L {
            T.UiIntent.Command(old_hover_binding.leave, old_hover, old_semantic_ref)
        } or L(),
        L {
            T.UiIntent.Hover(
                new_hover,
                hit and hit.semantic_ref or nil,
                new_hover_binding and new_hover_binding.cursor or nil
            )
        },
        new_hover_binding and new_hover_binding.enter and L {
            T.UiIntent.Command(new_hover_binding.enter, new_hover, hit and hit.semantic_ref or nil)
        } or L(),
    }
end

local function focus_intent(T, state, next_focus, semantic_ref)
    if same_element_id(state.focused, next_focus) then return L() end
    return L {
        T.UiIntent.Focus(next_focus, semantic_ref)
    }
end

local function press_intents(T, hit, button)
    return L(F.iter(press_bindings_for(hit, button)):map(function(binding)
        if binding.kind == "PressBinding" then
            return T.UiIntent.Command(binding.command, hit.id, hit.semantic_ref)
        end
        return T.UiIntent.Toggle(binding.command, binding.value, hit.id, hit.semantic_ref)
    end):totable())
end

local function scroll_intents(T, hit, dx, dy)
    if not hit or not hit.scroll then return L() end
    return L {
        T.UiIntent.Scroll(hit.scroll.model, dx, dy, hit.id, hit.semantic_ref)
    }
end

local function key_edit_action(T, chord)
    if chord.keycode == 8 then return T.UiIntent.Backspace() end
    if chord.keycode == 127 then return T.UiIntent.Delete() end
    if chord.keycode == 13 then return T.UiIntent.Submit() end
    if chord.ctrl and chord.keycode == 97 then return T.UiIntent.SelectAll() end
    if chord.keycode == 37 then return T.UiIntent.MoveCaret(T.UiIntent.MoveLeft(), chord.shift) end
    if chord.keycode == 39 then return T.UiIntent.MoveCaret(T.UiIntent.MoveRight(), chord.shift) end
    if chord.keycode == 38 then return T.UiIntent.MoveCaret(T.UiIntent.MoveUp(), chord.shift) end
    if chord.keycode == 40 then return T.UiIntent.MoveCaret(T.UiIntent.MoveDown(), chord.shift) end
    return nil
end

local function apply_hover_result(T, state, plan, p)
    local next_state, hit = with_hover_from_point(T, state, plan, p)
    return T.UiApply.Result(next_state, hover_intents(T, state, plan, hit))
end

local function apply_pointer_press_result(T, state, plan, p, button)
    local hover_result = apply_hover_result(T, state, plan, p)
    local hit = top_hit(plan, p)
    if not hit then return hover_result end

    local focus = focus_item_for(plan, hit.id)
    local next_focus = focus and focus.id or hover_result.session.focused
    local next_state = with_state(T, hover_result.session, {
        pressed = L(F.chain(
            F.iter(pressed_without(state, button)),
            F.iter {
                T.UiSession.PointerPress(button, hit.id, 1)
            }
        ):totable()),
        captured = hit.id,
        focused = next_focus,
    })

    return T.UiApply.Result(
        next_state,
        chain_lists {
            hover_result.intents,
            focus_intent(T, state, next_focus, hit.semantic_ref),
            press_intents(T, hit, button),
        }
    )
end

local function apply_pointer_release_result(T, state, plan, p, button)
    local next_state, hit = with_hover_from_point(T, state, plan, p)
    local next_pressed = pressed_without(state, button)

    return T.UiApply.Result(
        T.UiSession.State(
            next_state.viewport,
            next_state.pointer,
            next_state.pointer_in_bounds,
            next_state.window_focused,
            next_pressed,
            next_state.hovered,
            next_state.focused,
            (#next_pressed > 0) and state.captured or nil,
            next_state.drag
        ),
        hover_intents(T, state, plan, hit)
    )
end

local function apply_pointer_exit_result(T, state)
    local next_state = T.UiSession.State(
        state.viewport,
        state.pointer,
        false,
        state.window_focused,
        state.pressed,
        nil,
        state.focused,
        state.captured,
        state.drag
    )

    return T.UiApply.Result(
        next_state,
        state.hovered and L { T.UiIntent.Hover(nil, nil, nil) } or L()
    )
end

local function apply_wheel_result(T, state, plan, p, dx, dy)
    local next_state, hit = with_hover_from_point(T, state, plan, p)
    return T.UiApply.Result(
        next_state,
        chain_lists {
            hover_intents(T, state, plan, hit),
            scroll_intents(T, hit, dx, dy),
        }
    )
end

local function apply_key_result(T, state, plan, when, chord)
    local commands = L(F.iter(key_routes_for(plan, state.focused, chord, when)):map(function(route)
        return T.UiIntent.Command(route.command, route.global and nil or route.id, nil)
    end):totable())

    local edit_host = state.focused and edit_host_for(plan, state.focused) or nil
    local edit_action = (when.kind == "KeyDown" or when.kind == "KeyRepeat") and edit_host and key_edit_action(T, chord) or nil

    return T.UiApply.Result(
        state,
        chain_lists {
            commands,
            edit_action and L {
                T.UiIntent.Edit(edit_host.model, edit_action, edit_host.id, edit_host.semantic_ref, edit_host.changed)
            } or L(),
        }
    )
end

local function apply_text_result(T, state, plan, text)
    local edit_host = state.focused and edit_host_for(plan, state.focused) or nil
    return T.UiApply.Result(
        state,
        edit_host and L {
            T.UiIntent.Edit(
                edit_host.model,
                T.UiIntent.InsertText(text),
                edit_host.id,
                edit_host.semantic_ref,
                edit_host.changed
            )
        } or L()
    )
end

local function apply_window_focus_result(T, state, focused)
    local next_state = T.UiSession.State(
        state.viewport,
        state.pointer,
        focused and state.pointer_in_bounds or false,
        focused,
        focused and state.pressed or L(),
        focused and state.hovered or nil,
        state.focused,
        focused and state.captured or nil,
        state.drag
    )

    return T.UiApply.Result(
        next_state,
        focused and L() or chain_lists {
            state.hovered and L { T.UiIntent.Hover(nil, nil, nil) } or L(),
            state.focused and L { T.UiIntent.Focus(nil, nil) } or L(),
        }
    )
end

return function(T)
    T.UiSession.State.initial = U.transition(function(viewport)
        viewport = viewport or default_viewport(T)
        return T.UiSession.State(
            viewport,
            point(T, 0, 0),
            false,
            true,
            L(),
            nil,
            nil,
            nil,
            nil
        )
    end)

    -- ---------------------------------------------------------------------
    -- Full reducer result with semantic outputs.
    -- ---------------------------------------------------------------------
    T.UiSession.State.apply_with_intents = U.transition(function(state, plan, event)
        return U.match(event, {
            PointerMoved = function(v)
                return apply_hover_result(T, state, plan, v.position)
            end,
            PointerPressed = function(v)
                return apply_pointer_press_result(T, state, plan, v.position, v.button)
            end,
            PointerReleased = function(v)
                return apply_pointer_release_result(T, state, plan, v.position, v.button)
            end,
            PointerExited = function()
                return apply_pointer_exit_result(T, state)
            end,
            WheelScrolled = function(v)
                return apply_wheel_result(T, state, plan, v.position, v.dx, v.dy)
            end,
            KeyChanged = function(v)
                return apply_key_result(T, state, plan, v.when, v.chord)
            end,
            TextEntered = function(v)
                return apply_text_result(T, state, plan, v.text)
            end,
            FocusChanged = function(v)
                return apply_window_focus_result(T, state, v.focused)
            end,
            ViewportResized = function(v)
                return T.UiApply.Result(with_state(T, state, { viewport = v.viewport }), L())
            end,
        })
    end)

    -- ---------------------------------------------------------------------
    -- Convenience projection to just the next session state.
    -- ---------------------------------------------------------------------
    T.UiSession.State.apply = U.transition(function(state, plan, event)
        return state:apply_with_intents(plan, event).session
    end)
end
