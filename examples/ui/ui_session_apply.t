local U = require("unit")
local F = require("fun")

local Apply = {}
local unpack_fn = table.unpack or unpack

local function L(xs)
    return terralib.newlist(xs or {})
end

local function chain_lists(lists)
    if #lists == 0 then return L() end
    return L(F.chain(unpack_fn(lists)):totable())
end

local function point_in_rect(point, rect)
    return point.x >= rect.x
       and point.y >= rect.y
       and point.x <= rect.x + rect.w
       and point.y <= rect.y + rect.h
end

local function point_in_hit_shape(shape, point)
    return U.match(shape, {
        HitRect = function(v)
            return point_in_rect(point, v.rect)
        end,
        HitRoundedRect = function(v)
            return point_in_rect(point, v.rect)
        end,
    })
end

local function top_hit(routed, point)
    local hits = F.iter(routed.hits)
        :filter(function(hit)
            return point_in_hit_shape(hit.shape, point)
        end)
        :totable()

    local best = nil
    for _, hit in ipairs(hits) do
        if best == nil or hit.z_index >= best.z_index then
            best = hit
        end
    end
    return best
end

local function first_or_nil(xs)
    local list = F.iter(xs):totable()
    return list[1]
end

local function hover_route_for(routed, element)
    return first_or_nil(F.iter(routed.pointer_routes)
        :filter(function(route)
            return route.kind == "HoverRoute" and route.element == element
        end))
end

local function press_routes_for(routed, element, button)
    return F.iter(routed.pointer_routes)
        :filter(function(route)
            return route.element == element
               and (route.kind == "PressRoute" or route.kind == "ToggleRoute")
               and route.button.kind == button.kind
        end)
        :totable()
end

local function focus_entry_for(routed, element)
    return first_or_nil(F.iter(routed.focus_chain)
        :filter(function(entry) return entry.element == element end))
end

local function scroll_route_for(routed, element)
    return first_or_nil(F.iter(routed.scroll_routes)
        :filter(function(route) return route.element == element end))
end

local function edit_route_for(routed, element)
    return first_or_nil(F.iter(routed.edit_routes)
        :filter(function(route) return route.element == element end))
end

local function key_routes_for(routed, focused, chord, when)
    return F.iter(routed.key_routes)
        :filter(function(route)
            return route.when.kind == when.kind
               and route.chord == chord
               and (route.global or route.scope == focused)
        end)
        :totable()
end

local function pressed_without(state, button)
    return L(F.iter(state.pressed)
        :filter(function(press) return press.button ~= button end)
        :totable())
end

local function with_pointer_target(T, state, point)
    return U.with(state, {
        pointer = point,
        pointer_in_bounds = true,
    })
end

local function hover_intents(T, state, routed, hit)
    local old_hover = state.hovered
    local new_hover = hit and hit.element or nil
    if old_hover == new_hover then return L() end

    local leave_route = old_hover and hover_route_for(routed, old_hover) or nil
    local enter_route = new_hover and hover_route_for(routed, new_hover) or nil

    return chain_lists {
        leave_route and leave_route.leave and L {
            T.UiIntent.Command(leave_route.leave, leave_route.element, leave_route.semantic_ref)
        } or L(),
        L {
            T.UiIntent.Hover(
                new_hover,
                hit and hit.semantic_ref or nil,
                enter_route and enter_route.cursor or nil
            )
        },
        enter_route and enter_route.enter and L {
            T.UiIntent.Command(enter_route.enter, enter_route.element, enter_route.semantic_ref)
        } or L(),
    }
end

local function apply_hover(T, state, routed, point)
    local hit = top_hit(routed, point)
    local intents = hover_intents(T, state, routed, hit)
    local next_state = U.with(with_pointer_target(T, state, point), {
        hovered = hit and hit.element or nil,
    })
    return T.UiApply.Result(next_state, intents)
end

local function apply_pointer_exit(T, state, routed)
    local intents = state.hovered and L { T.UiIntent.Hover(nil, nil, nil) } or L()
    local next_state = U.with(state, {
        pointer_in_bounds = false,
        hovered = nil,
    })
    return T.UiApply.Result(next_state, intents)
end

local function apply_focus_change(T, state, focused_element, semantic_ref)
    if state.focused == focused_element then
        return T.UiApply.Result(state, L())
    end
    local next_state = U.with(state, { focused = focused_element })
    return T.UiApply.Result(next_state, L {
        T.UiIntent.Focus(focused_element, semantic_ref)
    })
end

local function button_press_intents(T, routes)
    return L(F.iter(routes):map(function(route)
        return U.match(route, {
            PressRoute = function(v)
                return T.UiIntent.Command(v.command, v.element, v.semantic_ref)
            end,
            ToggleRoute = function(v)
                return T.UiIntent.Toggle(v.command, v.value, v.element, v.semantic_ref)
            end,
            HoverRoute = function(_) error("unreachable", 2) end,
            GestureRoute = function(_) error("unreachable", 2) end,
        })
    end):totable())
end

local function apply_pointer_press(T, state, routed, point, button)
    local hit = top_hit(routed, point)
    local hovered = hit and hit.element or nil
    local focused = hit and focus_entry_for(routed, hit.element) or nil
    local routes = hovered and press_routes_for(routed, hovered, button) or {}
    local press = hovered and T.UiSession.PointerPress(button, hovered, 1) or nil

    local hover_events = hover_intents(T, state, routed, hit)
    local focus_result = focused and apply_focus_change(T, state, focused.element, hit.semantic_ref)
        or T.UiApply.Result(state, L())

    local next_pressed = chain_lists {
        pressed_without(state, button),
        press and L { press } or L(),
    }

    local next_state = U.with(with_pointer_target(T, focus_result.session, point), {
        hovered = hovered,
        pressed = next_pressed,
        captured = hovered,
    })

    return T.UiApply.Result(
        next_state,
        chain_lists {
            hover_events,
            focus_result.intents,
            button_press_intents(T, routes),
        }
    )
end

local function apply_pointer_release(T, state, point, button)
    local next_state = U.with(with_pointer_target(T, state, point), {
        pressed = pressed_without(state, button),
        captured = (state.captured and state.captured == (state.hovered or state.captured)) and nil or state.captured,
    })
    return T.UiApply.Result(next_state, L())
end

local function apply_wheel(T, state, routed, point, dx, dy)
    local hit = top_hit(routed, point)
    local scroll = hit and scroll_route_for(routed, hit.element) or nil
    local next_state = with_pointer_target(T, state, point)
    return T.UiApply.Result(
        next_state,
        scroll and L {
            T.UiIntent.Scroll(scroll.model, dx, dy, scroll.element, scroll.semantic_ref)
        } or L()
    )
end

local function submit_edit(T, route, action)
    return T.UiIntent.Edit(route.model, action, route.element, route.semantic_ref, route.changed)
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

local function apply_key(T, state, routed, when, chord)
    local commands = L(F.iter(key_routes_for(routed, state.focused, chord, when)):map(function(route)
        return T.UiIntent.Command(route.command, route.scope or state.focused, nil)
    end):totable())

    local edit_route = state.focused and edit_route_for(routed, state.focused) or nil
    local edit_action = (when.kind == "KeyDown" or when.kind == "KeyRepeat") and edit_route and key_edit_action(T, chord) or nil

    return T.UiApply.Result(
        state,
        chain_lists {
            commands,
            edit_action and L { submit_edit(T, edit_route, edit_action) } or L(),
        }
    )
end

local function apply_text(T, state, routed, text)
    local edit_route = state.focused and edit_route_for(routed, state.focused) or nil
    return T.UiApply.Result(
        state,
        edit_route and L {
            submit_edit(T, edit_route, T.UiIntent.InsertText(text))
        } or L()
    )
end

local function apply_window_focus(T, state, focused)
    local next_state = U.with(state, {
        window_focused = focused,
        pointer_in_bounds = focused and state.pointer_in_bounds or false,
        hovered = focused and state.hovered or nil,
        captured = focused and state.captured or nil,
        pressed = focused and state.pressed or L(),
    })

    return T.UiApply.Result(
        next_state,
        focused and L() or chain_lists {
            state.hovered and L { T.UiIntent.Hover(nil, nil, nil) } or L(),
            state.focused and L { T.UiIntent.Focus(nil, nil) } or L(),
        }
    )
end

function Apply.install(T)
    T.UiSession.State.apply = U.transition(function(state, routed, input)
        return U.match(input, {
            PointerMoved = function(v)
                return apply_hover(T, state, routed, v.position)
            end,
            PointerPressed = function(v)
                return apply_pointer_press(T, state, routed, v.position, v.button)
            end,
            PointerReleased = function(v)
                return apply_pointer_release(T, state, v.position, v.button)
            end,
            PointerExited = function()
                return apply_pointer_exit(T, state, routed)
            end,
            WheelScrolled = function(v)
                return apply_wheel(T, state, routed, v.position, v.dx, v.dy)
            end,
            KeyChanged = function(v)
                return apply_key(T, state, routed, v.when, v.chord)
            end,
            TextEntered = function(v)
                return apply_text(T, state, routed, v.text)
            end,
            FocusChanged = function(v)
                return apply_window_focus(T, state, v.focused)
            end,
            ViewportResized = function(v)
                return T.UiApply.Result(U.with(state, { viewport = v.viewport }), L())
            end,
        })
    end)
end

return Apply
