local U = require("unit")
local F = require("fun")
local Codec = require("examples.ui2.ui2_demo_codec")

return function(T)
    local function L(xs)
        return terralib.newlist(xs or {})
    end

    local function same_target(a, b)
        if a == b then return true end
        if a == nil or b == nil then return false end
        return a.kind == b.kind
    end

    local function append_log(state, entry)
        local out = F.iter(state.log):totable()
        out[#out + 1] = entry
        if #out <= 12 then return L(out) end
        return L(F.iter(out):drop(#out - 12):totable())
    end

    local function event_for_command(T, command)
        return U.match(command, {
            SelectTarget = function(v)
                return T.DemoEvent.SelectTarget(v.target)
            end,
        })
    end

    local function decoded_target(T, semantic_ref)
        return Codec.decode_target(T, semantic_ref)
    end

    local decode_demo = U.transition(function(intent)
        return U.match(intent, {
            Command = function(v)
                local command = Codec.decode_command(T, v.command)
                return T.DemoDecode.Result(command and L { event_for_command(T, command) } or L())
            end,
            Toggle = function(v)
                local command = v.command and Codec.decode_command(T, v.command) or nil
                return T.DemoDecode.Result(command and L { event_for_command(T, command) } or L())
            end,
            Hover = function(v)
                return T.DemoDecode.Result(L {
                    T.DemoEvent.HoverTarget(decoded_target(T, v.semantic_ref))
                })
            end,
            Focus = function(v)
                return T.DemoDecode.Result(L {
                    T.DemoEvent.FocusTarget(decoded_target(T, v.semantic_ref))
                })
            end,
            Scroll = function(v)
                local target = decoded_target(T, v.semantic_ref)
                return T.DemoDecode.Result(target and L {
                    T.DemoEvent.ScrollTarget(target, v.dx, v.dy)
                } or L())
            end,
            Edit = function(_)
                return T.DemoDecode.Result(L())
            end,
        })
    end)

    T.UiIntent.Event.decode_demo = decode_demo
    T.UiIntent.Command.decode_demo = decode_demo
    T.UiIntent.Toggle.decode_demo = decode_demo
    T.UiIntent.Hover.decode_demo = decode_demo
    T.UiIntent.Focus.decode_demo = decode_demo
    T.UiIntent.Scroll.decode_demo = decode_demo
    T.UiIntent.Edit.decode_demo = decode_demo

    T.DemoApp.State.initial = U.transition(function()
        return T.DemoApp.State(nil, nil, nil, nil, L())
    end)

    T.DemoApp.State.apply = U.transition(function(state, event)
        return U.match(event, {
            SelectTarget = function(v)
                return T.DemoApp.State(
                    state.hovered,
                    state.focused,
                    v.target,
                    state.last_scroll,
                    append_log(state, T.DemoApp.SelectedTarget(v.target))
                )
            end,
            HoverTarget = function(v)
                if same_target(state.hovered, v.target) then return state end
                return T.DemoApp.State(
                    v.target,
                    state.focused,
                    state.selected,
                    state.last_scroll,
                    append_log(state, T.DemoApp.HoveredTarget(v.target))
                )
            end,
            FocusTarget = function(v)
                if same_target(state.focused, v.target) then return state end
                return T.DemoApp.State(
                    state.hovered,
                    v.target,
                    state.selected,
                    state.last_scroll,
                    append_log(state, T.DemoApp.FocusedTarget(v.target))
                )
            end,
            ScrollTarget = function(v)
                return T.DemoApp.State(
                    state.hovered,
                    state.focused,
                    state.selected,
                    T.DemoApp.ScrollSample(v.target, v.dx, v.dy),
                    append_log(state, T.DemoApp.ScrolledTarget(v.target, v.dx, v.dy))
                )
            end,
        })
    end)

    T.DemoApp.State.apply_ui = U.transition(function(state, ui_apply_result)
        return F.iter(ui_apply_result.intents)
            :map(function(intent)
                return intent:decode_demo().events
            end)
            :reduce(function(app_state, batch)
                return F.iter(batch):reduce(function(inner_state, event)
                    return inner_state:apply(event)
                end, app_state)
            end, state)
    end)
end
