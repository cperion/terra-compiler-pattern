local asdl = require("asdl")
local U = require("unit")
local List = asdl.List

return function(T, Backend)
    local C = Backend.headers()

    local DEMO_DOMAIN = 700
    local TARGET_CODES = {
        select_title = 1,
        select_image = 2,
        select_custom = 3,
        select_overlay = 4,
    }
    local TARGET_NAMES = {
        [1] = "title-card",
        [2] = "image-placeholder",
        [3] = "custom-card",
        [4] = "overlay-card",
    }

    local function L(xs)
        return List(xs or {})
    end

    local function eid(n)
        return T.UiCore.ElementId(n)
    end

    local function solid(r, g, b, a)
        return T.UiCore.Solid(T.UiCore.Color(r, g, b, a))
    end

    local function insets(t, r, b, l)
        return T.UiCore.Insets(t, r, b, l)
    end

    local function fill_size()
        return T.UiCore.SizeSpec(
            T.UiCore.Auto(),
            T.UiCore.Percent(1),
            T.UiCore.Percent(1)
        )
    end

    local function auto_size()
        return T.UiCore.SizeSpec(
            T.UiCore.Auto(),
            T.UiCore.Auto(),
            T.UiCore.Auto()
        )
    end

    local function command_ref(key)
        return T.UiCore.CommandRef(TARGET_CODES[key])
    end

    local function semantic_ref(key)
        return T.UiCore.SemanticRef(DEMO_DOMAIN, TARGET_CODES[key])
    end

    local function target_name_from_command(ref)
        return ref and TARGET_NAMES[ref.value] or nil
    end

    local function target_name_from_semantic(ref)
        if not ref or ref.domain ~= DEMO_DOMAIN then return "none" end
        return TARGET_NAMES[ref.value] or "unknown"
    end

    local function apply_intents(intents, state)
        local next = {
            selected = state.selected,
            focused = state.focused,
        }

        for _, intent in ipairs(intents) do
            U.match(intent, {
                Command = function(v)
                    local selected = target_name_from_command(v.command)
                    if selected then next.selected = selected end
                end,
                Toggle = function(v)
                    local selected = v.command and target_name_from_command(v.command) or nil
                    if selected then next.selected = selected end
                end,
                Focus = function(v)
                    next.focused = target_name_from_semantic(v.semantic_ref)
                end,
                Hover = function(_) end,
                Scroll = function(_) end,
                Edit = function(_) end,
            })
        end

        return next
    end

    local custom_handler = terra(rt : &Backend.runtime_t(), payload : double)
        C.glDisable(C.GL_TEXTURE_2D)
        C.glColor4d(0.22, 0.95, 0.58, 0.25 * rt.opacity)
        C.glBegin(C.GL_QUADS)
        C.glVertex2d(20.0 + payload, 18.0 + payload)
        C.glVertex2d(72.0 + payload, 18.0 + payload)
        C.glVertex2d(72.0 + payload, 38.0 + payload)
        C.glVertex2d(20.0 + payload, 38.0 + payload)
        C.glEnd()
    end
    custom_handler:compile()

    local function pointer_button(button)
        if button == C.SDL_BUTTON_LEFT then return T.UiCore.Primary() end
        if button == C.SDL_BUTTON_MIDDLE then return T.UiCore.Middle() end
        if button == C.SDL_BUTTON_RIGHT then return T.UiCore.Secondary() end
        if button == 4 then return T.UiCore.Button4() end
        if button == 5 then return T.UiCore.Button5() end
        return T.UiCore.Primary()
    end

    local function ui_input_from_native(event)
        -- KISS demo policy:
        --   ignore raw pointer-move traffic.
        -- The current demo has no hover visuals, and press/scroll routing still
        -- resolves from the explicit event position, so motion events only add
        -- hot-path churn here.
        if event.kind == "PointerPressed" then
            return T.UiInput.PointerPressed(T.UiCore.Point(event.x, event.y), pointer_button(event.button))
        end
        if event.kind == "PointerReleased" then
            return T.UiInput.PointerReleased(T.UiCore.Point(event.x, event.y), pointer_button(event.button))
        end
        if event.kind == "WheelScrolled" then
            return T.UiInput.WheelScrolled(T.UiCore.Point(event.x, event.y), event.dx, event.dy)
        end
        if event.kind == "FocusChanged" then
            return T.UiInput.FocusChanged(event.focused)
        end
        if event.kind == "WindowResized" then
            return T.UiInput.ViewportResized(T.UiCore.Size(event.w, event.h))
        end
        return nil
    end

    return {
        L = L,
        eid = eid,
        solid = solid,
        insets = insets,
        fill_size = fill_size,
        auto_size = auto_size,
        command_ref = command_ref,
        semantic_ref = semantic_ref,
        apply_intents = apply_intents,
        initial_state = function()
            return {
                selected = "none",
                focused = "none",
            }
        end,
        ui_input_from_native = ui_input_from_native,
        target = {
            backend = Backend,
            custom = {
                [7] = custom_handler,
            },
        },
    }
end
