local asdl = require("asdl")
local bit = require("bit")
local List = asdl.List

local Backend = require("examples.ui.backend_sdl_gl")
local RawText = require("examples.ui.backend_text_sdl_ttf")
local Bridge = require("examples.tasks.tasks_ui_bridge")
local Schema = require("examples.tasks.tasks_schema")

local T = Schema.ctx
local C = Backend.headers()
local PROFILE = os.getenv("TERRA_TASKS_PROFILE") == "1"

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

local function now_ns()
    return tonumber(Backend.FFI.SDL_GetTicksNS())
end

local function ms(ns)
    return (ns or 0) / 1000000.0
end

local function stat()
    return { count = 0, total = 0, max = 0 }
end

local function sample(s, value)
    if not PROFILE then return end
    s.count = s.count + 1
    s.total = s.total + value
    if value > s.max then s.max = value end
end

local function avg(s)
    return s.count == 0 and 0 or (s.total / s.count)
end

local function churn_stat()
    return { count = 0, total_nodes = 0, reused_nodes = 0 }
end

local function is_asdl_node(v)
    local mt = type(v) == "table" and getmetatable(v) or nil
    return mt and type(mt.__fields) == "table"
end

local function node_size(node, memo)
    if not is_asdl_node(node) then return 0 end
    memo = memo or {}
    if memo[node] then return memo[node] end

    local mt = getmetatable(node)
    local total = 1
    for _, field in ipairs(mt.__fields) do
        local value = node[field.name]
        if field.list then
            for _, item in ipairs(value or {}) do
                total = total + node_size(item, memo)
            end
        else
            total = total + node_size(value, memo)
        end
    end

    memo[node] = total
    return total
end

local function compare_reuse(old_node, new_node, memo)
    memo = memo or {}
    if not is_asdl_node(new_node) then
        return { total = 0, reused = 0 }
    end
    if old_node == new_node then
        local size = node_size(new_node, memo)
        return { total = size, reused = size }
    end
    if not is_asdl_node(old_node) then
        return { total = node_size(new_node, memo), reused = 0 }
    end

    local old_mt = getmetatable(old_node)
    local new_mt = getmetatable(new_node)
    if old_mt ~= new_mt then
        return { total = node_size(new_node, memo), reused = 0 }
    end

    local total = 1
    local reused = 0
    for _, field in ipairs(new_mt.__fields) do
        local a = old_node[field.name]
        local b = new_node[field.name]
        if field.list then
            local n = math.max(#(a or {}), #(b or {}))
            for i = 1, n do
                local s = compare_reuse((a or {})[i], (b or {})[i], memo)
                total = total + s.total
                reused = reused + s.reused
            end
        else
            local s = compare_reuse(a, b, memo)
            total = total + s.total
            reused = reused + s.reused
        end
    end
    return { total = total, reused = reused }
end

local function sample_churn(slot, old_root, new_root)
    if not PROFILE then return end
    local s = compare_reuse(old_root, new_root)
    slot.count = slot.count + 1
    slot.total_nodes = slot.total_nodes + s.total
    slot.reused_nodes = slot.reused_nodes + s.reused
end

local function churn_pct(slot)
    return slot.total_nodes == 0 and 0 or (100.0 * slot.reused_nodes / slot.total_nodes)
end

local profiler = PROFILE and {
    since_print_ns = now_ns(),
    changed_batches = 0,
    queue_delay = stat(),
    ui_apply = stat(),
    bridge = stat(),
    project_view = stat(),
    lower = stat(),
    bind = stat(),
    flat = stat(),
    demand = stat(),
    resolve = stat(),
    plan = stat(),
    compile = stat(),
    render = stat(),
    input_to_present = stat(),
    screen_churn = churn_stat(),
    document_churn = churn_stat(),
    bound_churn = churn_stat(),
    flat_churn = churn_stat(),
    demand_churn = churn_stat(),
    resolved_churn = churn_stat(),
    plan_churn = churn_stat(),
} or nil

local function record_compile_profile(phases)
    if not PROFILE then return end
    sample(profiler.project_view, phases.project_view)
    sample(profiler.lower, phases.lower)
    sample(profiler.bind, phases.bind)
    sample(profiler.flat, phases.flat)
    sample(profiler.demand, phases.demand)
    sample(profiler.resolve, phases.resolve)
    sample(profiler.plan, phases.plan)
    sample(profiler.compile, phases.compile)
end

local function maybe_print_profile(force)
    if not PROFILE then return end
    local t = now_ns()
    if not force and t - profiler.since_print_ns < 2000000000 then
        return
    end
    profiler.since_print_ns = t
    if profiler.input_to_present.count == 0 then return end

    print((
        "profile changed=%d queue=%.2f/%.2fms ui=%.2f/%.2f bridge=%.2f/%.2f project=%.2f lower=%.2f bind=%.2f flat=%.2f demand=%.2f resolve=%.2f plan=%.2f compile=%.2f render=%.2f input->present=%.2f/%.2fms churn screen=%.1f%% doc=%.1f%% bound=%.1f%% flat=%.1f%% demand=%.1f%% resolved=%.1f%% plan=%.1f%%"
    ):format(
        profiler.changed_batches,
        ms(avg(profiler.queue_delay)), ms(profiler.queue_delay.max),
        ms(avg(profiler.ui_apply)), ms(profiler.ui_apply.max),
        ms(avg(profiler.bridge)), ms(profiler.bridge.max),
        ms(avg(profiler.project_view)),
        ms(avg(profiler.lower)),
        ms(avg(profiler.bind)),
        ms(avg(profiler.flat)),
        ms(avg(profiler.demand)),
        ms(avg(profiler.resolve)),
        ms(avg(profiler.plan)),
        ms(avg(profiler.compile)),
        ms(avg(profiler.render)),
        ms(avg(profiler.input_to_present)), ms(profiler.input_to_present.max),
        churn_pct(profiler.screen_churn),
        churn_pct(profiler.document_churn),
        churn_pct(profiler.bound_churn),
        churn_pct(profiler.flat_churn),
        churn_pct(profiler.demand_churn),
        churn_pct(profiler.resolved_churn),
        churn_pct(profiler.plan_churn)
    ))
end


local function compile_state(runtime, state, assets)
    Backend.sync_window_size(runtime)
    local view_w, view_h = Backend.window_size(runtime)
    local viewport = T.UiCore.Size(view_w, view_h)
    if not PROFILE then
        local screen = state:project_view()
        local document = screen:lower()
        local bound = document:bind()
        local flat = bound:flat(viewport)
        local demand = flat:demand(assets)
        local resolved = demand:resolve()
        local plan = resolved:plan(assets)
        local compiled = plan:compile(assets)
        return compiled.route_queries, compiled, nil, nil
    end

    local t0 = now_ns()
    local screen = state:project_view()
    local t1 = now_ns()
    local document = screen:lower()
    local t2 = now_ns()
    local bound = document:bind()
    local t3 = now_ns()
    local flat = bound:flat(viewport)
    local t4 = now_ns()
    local demand = flat:demand(assets)
    local t5 = now_ns()
    local resolved = demand:resolve()
    local t6 = now_ns()
    local plan = resolved:plan(assets)
    local t7 = now_ns()
    local compiled = plan:compile(assets)
    local t8 = now_ns()
    return compiled.route_queries, compiled, {
        project_view = t1 - t0,
        lower = t2 - t1,
        bind = t3 - t2,
        flat = t4 - t3,
        demand = t5 - t4,
        resolve = t6 - t5,
        plan = t7 - t6,
        compile = t8 - t7,
    }, {
        screen = screen,
        document = document,
        bound = bound,
        flat = flat,
        demand = demand,
        resolved = resolved,
        plan = plan,
    }
end

local function settle_startup_window(runtime)
    local deadline = now_ns() + 250000000

    while now_ns() < deadline do
        Backend.present_clear(runtime)
        for _ = 1, 128 do
            local native = Backend.poll_native_event(runtime)
            if native == nil then break end
            if native.kind == "Quit" then
                return false
            elseif native.kind == "WindowResized" then
                Backend.sync_window_size(runtime)
            end
        end
        Backend.FFI.SDL_Delay(8)
    end

    return true
end

local runtime = Backend.init_window("terra tasks demo", 1100, 760)
RawText.init(runtime)
Backend.sync_window_size(runtime)
if not settle_startup_window(runtime) then
    RawText.shutdown(runtime)
    Backend.shutdown_window(runtime)
    return
end
local initial_view_w, initial_view_h = Backend.window_size(runtime)

local font = T.UiCore.FontRef(1)
local assets = T.UiAsset.Catalog(
    font,
    List {
        T.UiAsset.FontAsset(font, "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf")
    },
    List()
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

local state = T.TaskApp.State(
    workspace,
    T.TaskSession.State(
        T.TaskSession.TaskSelected(T.TaskCore.ProjectRef(1), T.TaskCore.TaskRef(10)),
        T.TaskSession.Filter("", List(), List(), true),
        T.TaskCore.ManualOrder(),
        T.TaskSession.NoEditor()
    ),
    true
)

local ui_session = T.UiSession.State(
    T.UiCore.Size(initial_view_w, initial_view_h),
    T.UiCore.Point(0, 0),
    false,
    false,
    List(),
    nil,
    nil,
    nil,
    nil
)

local route_queries, unit, _, prev_trees = compile_state(runtime, state, assets)
Backend.render_unit(runtime, unit)

while state.running do
    local compile_dirty = false
    local first_compile_event_ns = nil
    local processed_events = 0

    while processed_events < 128 do
        local native = Backend.poll_native_event(runtime)
        if native == nil then break end
        processed_events = processed_events + 1
        if native.kind == "Quit" then
            state = state:apply(T.TaskEvent.Quit())
            compile_dirty = true
            first_compile_event_ns = first_compile_event_ns or native.timestamp_ns or now_ns()
            break
        elseif native.kind ~= "Ignored" then
            local input = ui_input_from_native(native)
            if input then
                local t0 = PROFILE and now_ns() or nil
                local ui_apply = ui_session:apply(route_queries, input)
                local t1 = PROFILE and now_ns() or nil
                local next_ui_session = ui_apply.session
                local next_state = Bridge.apply_ui(state, ui_apply)
                local t2 = PROFILE and now_ns() or nil
                local state_changed = (next_state ~= state)
                local layout_changed = (native.kind == "WindowResized")

                if PROFILE then
                    local queue_delay = t0 - (native.timestamp_ns or t0)
                    sample(profiler.queue_delay, queue_delay)
                    sample(profiler.ui_apply, t1 - t0)
                    sample(profiler.bridge, t2 - t1)
                end

                if state_changed or layout_changed then
                    compile_dirty = true
                    first_compile_event_ns = first_compile_event_ns or native.timestamp_ns or t0 or now_ns()
                end

                ui_session = next_ui_session
                state = next_state

                if compile_dirty then
                    break
                end
            end
        end
    end

    if compile_dirty and state.running then
        local phases, trees
        route_queries, unit, phases, trees = compile_state(runtime, state, assets)
        if PROFILE then
            record_compile_profile(phases)
            if prev_trees and trees then
                sample_churn(profiler.screen_churn, prev_trees.screen, trees.screen)
                sample_churn(profiler.document_churn, prev_trees.document, trees.document)
                sample_churn(profiler.bound_churn, prev_trees.bound, trees.bound)
                sample_churn(profiler.flat_churn, prev_trees.flat, trees.flat)
                sample_churn(profiler.demand_churn, prev_trees.demand, trees.demand)
                sample_churn(profiler.resolved_churn, prev_trees.resolved, trees.resolved)
                sample_churn(profiler.plan_churn, prev_trees.plan, trees.plan)
            end
            prev_trees = trees or prev_trees
        end
        local render_t0 = PROFILE and now_ns() or nil
        Backend.render_unit(runtime, unit)
        local render_t1 = PROFILE and now_ns() or nil
        if PROFILE then
            sample(profiler.render, render_t1 - render_t0)
            profiler.changed_batches = profiler.changed_batches + 1
            if first_compile_event_ns then
                sample(profiler.input_to_present, render_t1 - first_compile_event_ns)
            end
            maybe_print_profile(false)
        end
    elseif processed_events == 0 then
        Backend.FFI.SDL_Delay(1)
    end
end

maybe_print_profile(true)
RawText.shutdown(runtime)
Backend.shutdown_window(runtime)
