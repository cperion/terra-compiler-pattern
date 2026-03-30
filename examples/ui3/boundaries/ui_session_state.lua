local U = require("unit")
local F = require("fun")

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
end

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function point(T, x, y)
    return T.UiCore.Point(x, y)
end

local function default_viewport(T)
    return T.UiCore.Size(1280, 720)
end

local function chain_lists(lists)
    local out = {}
    local i = 1
    while i <= #lists do
        local xs = lists[i]
        local j = 1
        while xs ~= nil and j <= #xs do
            out[#out + 1] = xs[j]
            j = j + 1
        end
        i = i + 1
    end
    return L(out)
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
    local out = {}
    local i = 1
    while i <= #state.pressed do
        local press = state.pressed[i]
        if not same_button(press.button, button) then
            out[#out + 1] = press
        end
        i = i + 1
    end
    return L(out)
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

local function region_hit(input, region, p)
    local start_ix = region.hit_start + 1
    local end_ix = region.hit_start + region.hit_count

    for i = end_ix, start_ix, -1 do
        local hit = input.hits[i]
        if point_in_shape(hit.shape, p) then
            return hit
        end
    end

    return nil
end

local function top_hit(input, p)
    for region_ix = #input.regions, 1, -1 do
        local region = input.regions[region_ix]
        local hit = region_hit(input, region, p)
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

local function hit_item_for(input, element_id)
    return F.iter(input.hits)
        :filter(function(item) return same_element_id(item.id, element_id) end)
        :nth(1)
end

local function focus_item_for(input, element_id)
    return F.iter(input.focus)
        :filter(function(item) return same_element_id(item.id, element_id) end)
        :nth(1)
end

local function edit_host_for(input, element_id)
    return F.iter(input.edit_hosts)
        :filter(function(item) return same_element_id(item.id, element_id) end)
        :nth(1)
end

local function key_routes_for(input, focused, chord, when)
    local routes = {}
    local i = 1
    while i <= #input.key_buckets do
        local bucket = input.key_buckets[i]
        if same_key_chord(bucket.chord, chord) and bucket.when.kind == when.kind then
            local is_global = bucket.scope.kind == "GlobalScope"
            local route_start = bucket.route_start + 1
            local route_end = bucket.route_start + bucket.route_count
            local j = route_start
            while j <= route_end do
                local route = input.key_routes[j]
                if is_global or same_element_id(route.id, focused) then
                    routes[#routes + 1] = {
                        command = route.command,
                        element = is_global and nil or route.id,
                    }
                end
                j = j + 1
            end
        end
        i = i + 1
    end
    return routes
end

local function focus_order_items(input)
    local items = {}
    local i = 1
    while i <= #input.focus_order do
        local entry = input.focus_order[i]
        items[#items + 1] = input.focus[entry.focus_index + 1]
        i = i + 1
    end
    return items
end

local function next_focus_target(input, current, backwards)
    local items = focus_order_items(input)
    if #items == 0 then return nil, nil end

    local current_ix = nil
    local i = 1
    while i <= #items do
        if same_element_id(items[i].id, current) then
            current_ix = i
            break
        end
        i = i + 1
    end

    local next_ix = nil
    if current_ix == nil then
        next_ix = backwards and #items or 1
    elseif backwards then
        next_ix = (current_ix == 1) and #items or (current_ix - 1)
    else
        next_ix = (current_ix == #items) and 1 or (current_ix + 1)
    end

    local target = items[next_ix]
    return target and target.id or nil, target and target.semantic_ref or nil
end

local function with_pointer_target(T, state, p)
    return with_state(T, state, {
        pointer = p,
        pointer_in_bounds = true,
    })
end

local function with_hover_from_point(T, state, input, p)
    local hit = top_hit(input, p)
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

local function hover_intents(T, state, input, hit)
    local old_hover = state.hovered
    local new_hover = hit and hit.id or nil
    if same_element_id(old_hover, new_hover) then return L() end

    local old_hit = old_hover and hit_item_for(input, old_hover) or nil
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
    if chord.keycode == 8 then return C(T.UiIntent.Backspace) end
    if chord.keycode == 127 then return C(T.UiIntent.Delete) end
    if chord.keycode == 13 then return C(T.UiIntent.Submit) end
    if chord.ctrl and chord.keycode == 97 then return C(T.UiIntent.SelectAll) end
    if chord.keycode == 37 then return T.UiIntent.MoveCaret(C(T.UiIntent.MoveLeft), chord.shift) end
    if chord.keycode == 39 then return T.UiIntent.MoveCaret(C(T.UiIntent.MoveRight), chord.shift) end
    if chord.keycode == 38 then return T.UiIntent.MoveCaret(C(T.UiIntent.MoveUp), chord.shift) end
    if chord.keycode == 40 then return T.UiIntent.MoveCaret(C(T.UiIntent.MoveDown), chord.shift) end
    return nil
end

local function apply_hover_result(T, state, query_ir, p)
    local input = query_ir.input
    local next_state, hit = with_hover_from_point(T, state, input, p)
    return T.UiApply.Result(next_state, hover_intents(T, state, input, hit))
end

local function apply_pointer_press_result(T, state, query_ir, p, button)
    local input = query_ir.input
    local hover_result = apply_hover_result(T, state, query_ir, p)
    local hit = top_hit(input, p)
    if not hit then return hover_result end

    local focus = focus_item_for(input, hit.id)
    local next_focus = focus and focus.id or hover_result.session.focused
    local next_pressed = {}
    local filtered = pressed_without(state, button)
    local i = 1
    while i <= #filtered do
        next_pressed[#next_pressed + 1] = filtered[i]
        i = i + 1
    end
    next_pressed[#next_pressed + 1] = T.UiSession.PointerPress(button, hit.id, 1)

    local next_state = with_state(T, hover_result.session, {
        pressed = L(next_pressed),
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

local function apply_pointer_release_result(T, state, query_ir, p, button)
    local input = query_ir.input
    local next_state, hit = with_hover_from_point(T, state, input, p)
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
        hover_intents(T, state, input, hit)
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

local function apply_wheel_result(T, state, query_ir, p, dx, dy)
    local input = query_ir.input
    local next_state, hit = with_hover_from_point(T, state, input, p)
    return T.UiApply.Result(
        next_state,
        chain_lists {
            hover_intents(T, state, input, hit),
            scroll_intents(T, hit, dx, dy),
        }
    )
end

local function apply_key_result(T, state, query_ir, when, chord)
    local input = query_ir.input

    if (when.kind == "KeyDown" or when.kind == "KeyRepeat") and chord.keycode == 9 then
        local next_focus, semantic_ref = next_focus_target(input, state.focused, chord.shift)
        local next_state = with_state(T, state, { focused = next_focus })
        return T.UiApply.Result(
            next_state,
            focus_intent(T, state, next_focus, semantic_ref)
        )
    end

    local commands = L(F.iter(key_routes_for(input, state.focused, chord, when)):map(function(route)
        return T.UiIntent.Command(route.command, route.element, nil)
    end):totable())

    local edit_host = state.focused and edit_host_for(input, state.focused) or nil
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

local function normalize_input_text(text)
    if type(text) == "string" then return text end
    return tostring(text)
end

local function apply_text_result(T, state, query_ir, text)
    local input = query_ir.input
    local edit_host = state.focused and edit_host_for(input, state.focused) or nil
    return T.UiApply.Result(
        state,
        edit_host and L {
            T.UiIntent.Edit(
                edit_host.model,
                T.UiIntent.InsertText(normalize_input_text(text)),
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
        focused and state.focused or nil,
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

    T.UiSession.State.apply_with_intents = U.transition(function(state, query_ir, event)
        return U.match(event, {
            PointerMoved = function(v)
                return apply_hover_result(T, state, query_ir, v.position)
            end,
            PointerPressed = function(v)
                return apply_pointer_press_result(T, state, query_ir, v.position, v.button)
            end,
            PointerReleased = function(v)
                return apply_pointer_release_result(T, state, query_ir, v.position, v.button)
            end,
            PointerExited = function()
                return apply_pointer_exit_result(T, state)
            end,
            WheelScrolled = function(v)
                return apply_wheel_result(T, state, query_ir, v.position, v.dx, v.dy)
            end,
            KeyChanged = function(v)
                return apply_key_result(T, state, query_ir, v.when, v.chord)
            end,
            TextEntered = function(v)
                return apply_text_result(T, state, query_ir, v.text)
            end,
            FocusChanged = function(v)
                return apply_window_focus_result(T, state, v.focused)
            end,
            ViewportResized = function(v)
                return T.UiApply.Result(with_state(T, state, { viewport = v.viewport }), L())
            end,
        })
    end)

    T.UiSession.State.apply = U.transition(function(state, query_ir, event)
        return state:apply_with_intents(query_ir, event).session
    end)
end
