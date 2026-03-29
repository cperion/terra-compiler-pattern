local bit = require("bit")
local U = require("unit")
local List = require("asdl").List

local Backend = require("examples.ui.backends.terra_sdl_gl")
local RawText = require("examples.ui.backends.text_sdl_ttf")
local Bridge = require("examples.tasks.tasks_ui_bridge")
local Schema = require("examples.tasks.tasks_schema")

local T = Schema.ctx
local C = Backend.headers()
local TARGET = { backend = Backend }

local SDL_KMOD_CTRL = 0x0040 + 0x0080
local SDL_KMOD_ALT = 0x0100 + 0x0200
local SDL_KMOD_SHIFT = 0x0001 + 0x0002
local SDL_KMOD_GUI = 0x0400 + 0x0800

local function pointer_button(button)
    if button == C.SDL_BUTTON_LEFT then return T.UiCore.Primary() end
    if button == C.SDL_BUTTON_MIDDLE then return T.UiCore.Middle() end
    if button == C.SDL_BUTTON_RIGHT then return T.UiCore.Secondary() end
    if button == 4 then return T.UiCore.Button4() end
    if button == 5 then return T.UiCore.Button5() end
    return T.UiCore.Primary()
end

local function key_event(kind)
    if kind == "KeyDown" then return T.UiCore.KeyDown() end
    if kind == "KeyRepeat" then return T.UiCore.KeyRepeat() end
    return T.UiCore.KeyUp()
end

local function key_chord(mod, key)
    return T.UiCore.KeyChord(
        bit.band(mod, SDL_KMOD_CTRL) ~= 0,
        bit.band(mod, SDL_KMOD_ALT) ~= 0,
        bit.band(mod, SDL_KMOD_SHIFT) ~= 0,
        bit.band(mod, SDL_KMOD_GUI) ~= 0,
        key
    )
end

local function ui_input_from_native(event)
    if event.kind == "PointerMoved" then
        return T.UiInput.PointerMoved(T.UiCore.Point(event.x, event.y))
    end
    if event.kind == "PointerPressed" then
        return T.UiInput.PointerPressed(T.UiCore.Point(event.x, event.y), pointer_button(event.button))
    end
    if event.kind == "PointerReleased" then
        return T.UiInput.PointerReleased(T.UiCore.Point(event.x, event.y), pointer_button(event.button))
    end
    if event.kind == "WheelScrolled" then
        return T.UiInput.WheelScrolled(T.UiCore.Point(event.x, event.y), event.dx, event.dy)
    end
    if event.kind == "KeyDown" or event.kind == "KeyUp" or event.kind == "KeyRepeat" then
        return T.UiInput.KeyChanged(key_event(event.kind), key_chord(event.mod, event.key))
    end
    if event.kind == "TextEntered" then
        return T.UiInput.TextEntered(event.text)
    end
    if event.kind == "FocusChanged" then
        return T.UiInput.FocusChanged(event.focused)
    end
    if event.kind == "WindowResized" then
        return T.UiInput.ViewportResized(T.UiCore.Size(event.w, event.h))
    end
    return nil
end

local function ensure_unit_state(unit)
    if unit.state_t == U.EMPTY then return nil end
    if unit.__state == nil then
        unit.__state = terralib.new(unit.state_t)
        if unit.init then unit.init(unit.__state) end
    end
    return unit.__state
end

local function compile_app(runtime, app_state, assets)
    Backend.sync_window_size(runtime)
    local view_w, view_h = Backend.window_size(runtime)
    local viewport = T.UiCore.Size(view_w, view_h)

    local screen = app_state:project_view()
    local document = screen:lower()
    local bound = document:bind(assets)
    local flat = bound:flatten(viewport)
    local demand = flat:prepare_demands(assets)
    local solved = demand:solve(assets)
    local plan = solved:plan()
    local render = plan:specialize_kernel()
    local machine = render:define_machine()
    local unit = machine.gen:compile(TARGET)
    local unit_state = ensure_unit_state(unit)
    if unit_state ~= nil then
        unit.__payload_keep = machine:materialize(TARGET, assets, unit_state)
    end

    return {
        viewport = viewport,
        screen = screen,
        document = document,
        bound = bound,
        flat = flat,
        demand = demand,
        solved = solved,
        plan = plan,
        render = render,
        machine = machine,
        unit = unit,
    }
end

local runtime = Backend.init_window("terra tasks demo (ui2)", 1100, 760)
RawText.init(runtime)
Backend.sync_window_size(runtime)

local font = T.UiCore.FontRef(1)
local assets = T.UiAsset.Catalog(
    font,
    List {
        T.UiAsset.FontAsset(font, "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf")
    },
    List {}
)

local workspace = T.TaskDoc.Workspace(
    1,
    "Terra Tasks",
    List {
        T.TaskDoc.Project(
            T.TaskCore.ProjectRef(1),
            "Inbox",
            false,
            List {
                T.TaskDoc.Task(T.TaskCore.TaskRef(10), "Finish UI pipeline", "Implement layout, routing, batching, and decode path.", T.TaskCore.InProgress(), T.TaskCore.High(), List { T.TaskCore.TagRef(1) }),
                T.TaskDoc.Task(T.TaskCore.TaskRef(11), "Audit DS apply", "Make recipe application explicit via DesignApply.Env.", T.TaskCore.Todo(), T.TaskCore.Medium(), List { T.TaskCore.TagRef(2) }),
                T.TaskDoc.Task(T.TaskCore.TaskRef(12), "Run integration demo", "Open a window and render the task screen end-to-end.", T.TaskCore.Done(), T.TaskCore.Low(), List { T.TaskCore.TagRef(1), T.TaskCore.TagRef(3) })
            }
        ),
        T.TaskDoc.Project(
            T.TaskCore.ProjectRef(2),
            "Later",
            false,
            List {
                T.TaskDoc.Task(T.TaskCore.TaskRef(20), "Image backend", "Replace placeholder image rendering with real textures.", T.TaskCore.Blocked(), T.TaskCore.Medium(), List { T.TaskCore.TagRef(3) })
            }
        )
    },
    List {
        T.TaskDoc.Tag(T.TaskCore.TagRef(1), "ui", T.UiCore.Color(0.46, 0.67, 0.95, 1.0)),
        T.TaskDoc.Tag(T.TaskCore.TagRef(2), "ds", T.UiCore.Color(0.58, 0.83, 0.54, 1.0)),
        T.TaskDoc.Tag(T.TaskCore.TagRef(3), "backend", T.UiCore.Color(0.95, 0.63, 0.34, 1.0))
    }
)

local app_state = T.TaskApp.State(
    workspace,
    T.TaskSession.State(
        T.TaskSession.TaskSelected(T.TaskCore.ProjectRef(1), T.TaskCore.TaskRef(10)),
        T.TaskSession.Filter("", List(), List(), true),
        T.TaskCore.ManualOrder(),
        T.TaskSession.NoEditor()
    ),
    true
)

local width, height = Backend.window_size(runtime)
local ui_session = T.UiSession.State.initial(T.UiCore.Size(width, height))
local compiled = compile_app(runtime, app_state, assets)
Backend.render_unit(runtime, compiled.unit)

while app_state.running do
    local dirty = false
    local event = Backend.poll_native_event(runtime)

    while event do
        if event.kind == "Quit" then
            app_state = app_state:apply(T.TaskEvent.Quit())
            dirty = false
            break
        end

        local input = ui_input_from_native(event)
        if input then
            local prev_viewport = ui_session.viewport
            local applied = ui_session:apply_with_intents(compiled.plan, input)
            ui_session = applied.session

            local next_app_state = Bridge.apply_ui(app_state, applied)
            if next_app_state ~= app_state or ui_session.viewport ~= prev_viewport then
                app_state = next_app_state
                dirty = true
            else
                app_state = next_app_state
            end
        end

        event = Backend.poll_native_event(runtime)
    end

    if not app_state.running then
        break
    end

    if dirty then
        compiled = compile_app(runtime, app_state, assets)
        Backend.render_unit(runtime, compiled.unit)
    else
        Backend.FFI.SDL_Delay(1)
    end
end

RawText.shutdown(runtime)
Backend.shutdown_window(runtime)
