local selected_backend = os.getenv("UI2_BACKEND")
    or (rawget(_G, "terralib") and "terra" or "luajit")

local U = require("unit")
local Backend = selected_backend == "terra"
    and require("examples.ui.backends.terra_sdl_gl")
    or require("examples.ui.backends.luajit_sdl_gl")
local RawText = require("examples.ui.backends.text_sdl_ttf")
local Schema = require("examples.ui2.ui2_schema")
local Demo = selected_backend == "terra"
    and require("examples.ui2.backends.terra_demo_support")
    or require("examples.ui2.backends.luajit_demo_support")

local T = Schema.ctx
local D = Demo(T, Backend)

local L = D.L
local eid = D.eid
local solid = D.solid
local insets = D.insets
local fill_size = D.fill_size
local auto_size = D.auto_size

local function element(id, semantic_ref, debug_name, role, layout, paint, content, behavior, accessibility, children)
    return T.UiDecl.Element(
        eid(id),
        semantic_ref,
        debug_name,
        role,
        T.UiDecl.Flags(true, true),
        layout,
        paint,
        content,
        behavior,
        accessibility,
        children or L {}
    )
end

local function no_accessibility()
    return T.UiDecl.Accessibility(T.UiCore.AccNone(), nil, nil, true, 0)
end

local function group_accessibility(label, priority)
    return T.UiDecl.Accessibility(T.UiCore.AccGroup(), label, nil, false, priority or 0)
end

local function no_behavior()
    return T.UiDecl.Behavior(
        T.UiDecl.HitNone(),
        T.UiDecl.NotFocusable(),
        L {},
        nil,
        L {},
        nil,
        L {}
    )
end

local function clickable_behavior(command_key)
    return T.UiDecl.Behavior(
        T.UiDecl.HitSelf(),
        T.UiDecl.Focusable(T.UiCore.TabFocus(), nil),
        L {
            T.UiDecl.Hover(nil, nil, nil),
            T.UiDecl.Press(T.UiCore.Primary(), 1, D.command_ref(command_key)),
        },
        nil,
        L {},
        nil,
        L {}
    )
end

local function scroll_behavior()
    return T.UiDecl.Behavior(
        T.UiDecl.HitSelfAndChildren(),
        T.UiDecl.NotFocusable(),
        L {},
        T.UiDecl.ScrollRule(T.UiCore.Vertical(), nil),
        L {},
        nil,
        L {}
    )
end

local function root_layout()
    return T.UiDecl.Layout(
        fill_size(),
        fill_size(),
        T.UiCore.InFlow(),
        T.UiCore.Column(),
        nil,
        nil,
        T.UiCore.Start(),
        T.UiCore.CrossStart(),
        insets(24, 24, 24, 24),
        insets(0, 0, 0, 0),
        16,
        T.UiCore.Visible(),
        T.UiCore.Visible(),
        nil
    )
end

local function card_layout()
    return T.UiDecl.Layout(
        auto_size(),
        auto_size(),
        T.UiCore.InFlow(),
        T.UiCore.Column(),
        nil,
        nil,
        T.UiCore.Start(),
        T.UiCore.CrossStart(),
        insets(16, 16, 16, 16),
        insets(0, 0, 0, 0),
        10,
        T.UiCore.Visible(),
        T.UiCore.Visible(),
        nil
    )
end

local function fill_card_layout()
    return T.UiDecl.Layout(
        fill_size(),
        auto_size(),
        T.UiCore.InFlow(),
        T.UiCore.Column(),
        nil,
        nil,
        T.UiCore.Start(),
        T.UiCore.CrossStart(),
        insets(14, 14, 14, 14),
        insets(0, 0, 0, 0),
        8,
        T.UiCore.Visible(),
        T.UiCore.Visible(),
        nil
    )
end

local function overlay_layout()
    return T.UiDecl.Layout(
        auto_size(),
        auto_size(),
        T.UiCore.Absolute(
            T.UiCore.EdgePx(520),
            T.UiCore.EdgePx(48),
            T.UiCore.Unset(),
            T.UiCore.Unset()
        ),
        T.UiCore.None(),
        nil,
        nil,
        T.UiCore.Start(),
        T.UiCore.CrossStart(),
        insets(12, 12, 12, 12),
        insets(0, 0, 0, 0),
        0,
        T.UiCore.Visible(),
        T.UiCore.Visible(),
        nil
    )
end

local function title_text(text)
    return T.UiDecl.Text(
        T.UiCore.TextValue(text),
        T.UiCore.TextStyle(T.UiCore.FontRef(1), 28, nil, nil, nil, 32, T.UiCore.Color(0.97, 0.98, 1.0, 1.0)),
        T.UiCore.TextLayout(T.UiCore.NoWrap(), T.UiCore.ClipText(), T.UiCore.TextStart(), 1)
    )
end

local function body_text(text)
    return T.UiDecl.Text(
        T.UiCore.TextValue(text),
        T.UiCore.TextStyle(T.UiCore.FontRef(1), 18, nil, nil, nil, 22, T.UiCore.Color(0.90, 0.93, 0.98, 1.0)),
        T.UiCore.TextLayout(T.UiCore.WrapWord(), T.UiCore.ClipText(), T.UiCore.TextStart(), 4)
    )
end

local function panel_paint()
    return T.UiDecl.Paint(L {
        T.UiDecl.Box(solid(0.15, 0.20, 0.31, 0.98), solid(0.35, 0.44, 0.60, 1.0), 1, T.UiCore.CenterStroke(), T.UiCore.Corners(0, 0, 0, 0)),
        T.UiDecl.Shadow(solid(0.00, 0.00, 0.00, 0.24), 6, 0, 0, 2, T.UiCore.DropShadow(), T.UiCore.Corners(0, 0, 0, 0)),
    })
end

local function custom_panel_paint(payload)
    return T.UiDecl.Paint(L {
        T.UiDecl.Box(solid(0.10, 0.12, 0.16, 0.92), solid(0.24, 0.78, 0.52, 1.0), 2, T.UiCore.CenterStroke(), T.UiCore.Corners(0, 0, 0, 0)),
        T.UiDecl.CustomPaint(7, payload),
    })
end

local function image_content()
    return T.UiDecl.Image(
        T.UiCore.ImageRef(2),
        T.UiCore.ImageStyle(T.UiCore.StretchImage(), T.UiCore.Linear(), 1.0, T.UiCore.Corners(0, 0, 0, 0))
    )
end

local function build_document()
    local root = element(
        100,
        nil,
        "root",
        T.UiCore.View(),
        root_layout(),
        T.UiDecl.Paint(L {}),
        T.UiDecl.NoContent(),
        no_behavior(),
        no_accessibility(),
        L {
            element(
                110,
                D.semantic_ref("select_title"),
                "title-card",
                T.UiCore.View(),
                card_layout(),
                panel_paint(),
                title_text("ui2: compiler-pattern UI kernel"),
                clickable_behavior("select_title"),
                group_accessibility("title-card", 10),
                L {}
            ),
            element(
                120,
                nil,
                "body-card",
                T.UiCore.View(),
                fill_card_layout(),
                panel_paint(),
                body_text("This demo exercises the full ui2 pipeline: bind, flatten, prepare_demands, solve, plan, specialize_kernel, compile, and materialize. Resize the window to trigger recompilation."),
                scroll_behavior(),
                group_accessibility("body-card", 20),
                L {
                    element(
                        121,
                        D.semantic_ref("select_image"),
                        "image-placeholder",
                        T.UiCore.ImageRole(),
                        card_layout(),
                        T.UiDecl.Paint(L {
                            T.UiDecl.Box(solid(0.18, 0.18, 0.22, 1.0), solid(0.55, 0.55, 0.62, 1.0), 1, T.UiCore.CenterStroke(), T.UiCore.Corners(0, 0, 0, 0)),
                        }),
                        image_content(),
                        clickable_behavior("select_image"),
                        group_accessibility("image-placeholder", 30),
                        L {}
                    ),
                    element(
                        122,
                        D.semantic_ref("select_custom"),
                        "custom-content-card",
                        T.UiCore.CustomRole(7),
                        card_layout(),
                        custom_panel_paint(11),
                        T.UiDecl.CustomContent(7, 12),
                        clickable_behavior("select_custom"),
                        group_accessibility("custom-card", 40),
                        L {}
                    )
                }
            )
        }
    )

    local overlay = element(
        200,
        D.semantic_ref("select_overlay"),
        "overlay-card",
        T.UiCore.OverlayHost(),
        overlay_layout(),
        custom_panel_paint(21),
        T.UiDecl.Text(
            T.UiCore.TextValue("custom overlay"),
            T.UiCore.TextStyle(T.UiCore.FontRef(1), 18, nil, nil, nil, 22, T.UiCore.Color(0.90, 1.0, 0.96, 1.0)),
            T.UiCore.TextLayout(T.UiCore.NoWrap(), T.UiCore.ClipText(), T.UiCore.TextCenter(), 1)
        ),
        clickable_behavior("select_overlay"),
        group_accessibility("overlay", 100),
        L {}
    )

    return T.UiDecl.Document(
        1,
        L {
            T.UiDecl.Root(eid(1), "main", root)
        },
        L {
            T.UiDecl.Overlay(eid(2), "overlay", overlay, 100, true, true)
        }
    )
end

local function ensure_unit_state(unit)
    if unit.state_t == U.EMPTY then return nil end
    if unit.__state == nil then
        if selected_backend == "terra" then
            unit.__state = terralib.new(unit.state_t)
        else
            unit.__state = unit.state_t.alloc()
        end
        if unit.init then unit.init(unit.__state) end
    end
    return unit.__state
end

local function lower_to_render(bound, viewport, assets)
    local flat = bound:flatten(viewport)
    local demand = flat:prepare_demands(assets)
    local solved = demand:solve(assets)
    local plan = solved:plan()
    local render = plan:specialize_kernel()
    local machine = render:define_machine()
    return flat, demand, solved, plan, render, machine
end

local function lower_ui(bound, viewport, assets)
    local _, _, _, plan, render, machine = lower_to_render(bound, viewport, assets)
    local unit = machine.gen:compile(D.target)
    local state = ensure_unit_state(unit)
    if state ~= nil then
        unit.__payload_keep = machine:materialize(D.target, assets, state)
    end
    return {
        plan = plan,
        render = render,
        machine = machine,
        unit = unit,
    }
end

local function now()
    return os.clock()
end

local function ms(seconds)
    return seconds * 1000.0
end

local function print_metric(name, value)
    print(string.format("METRIC %s %.6f", name, value))
end

local backend_name = selected_backend

local runtime = Backend.init_window("ui2 bench", 800, 600)
RawText.init(runtime)
if Backend.FFI and Backend.FFI.SDL_GL_SetSwapInterval then
    pcall(function() Backend.FFI.SDL_GL_SetSwapInterval(0) end)
end

local font = T.UiCore.FontRef(1)
local image = T.UiCore.ImageRef(2)
local assets = T.UiAsset.Catalog(
    font,
    L {
        T.UiAsset.FontAsset(font, "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf")
    },
    L {
        T.UiAsset.ImageAsset(image, "/tmp/ui2-demo-placeholder.png")
    }
)

local document = build_document()
local t0 = now()
local bound = document:bind(assets)
local bind_ms = ms(now() - t0)

collectgarbage("collect")

local lower_iters = tonumber(os.getenv("UI2_BENCH_LOWER_ITERS") or "50")
local render_iters = tonumber(os.getenv("UI2_BENCH_RENDER_ITERS") or "400")

for i = 1, 5 do
    lower_ui(bound, T.UiCore.Size(700 + i * 3, 500 + i * 2), assets)
end

collectgarbage("collect")
local stage_totals = {
    flatten = 0,
    prepare_demands = 0,
    solve = 0,
    plan = 0,
    specialize_kernel = 0,
    define_machine = 0,
    compile = 0,
    materialize = 0,
}
local lower_total_ms = 0
local compiled
for i = 1, lower_iters do
    local w = 320 + (i * 17) % 900
    local h = 240 + (i * 11) % 500
    local viewport = T.UiCore.Size(w, h)

    local t_flat = now()
    local flat = bound:flatten(viewport)
    stage_totals.flatten = stage_totals.flatten + ms(now() - t_flat)

    local t_demand = now()
    local demand = flat:prepare_demands(assets)
    stage_totals.prepare_demands = stage_totals.prepare_demands + ms(now() - t_demand)

    local t_solve = now()
    local solved = demand:solve(assets)
    stage_totals.solve = stage_totals.solve + ms(now() - t_solve)

    local t_plan = now()
    local plan = solved:plan()
    stage_totals.plan = stage_totals.plan + ms(now() - t_plan)

    local t_kernel = now()
    local render = plan:specialize_kernel()
    stage_totals.specialize_kernel = stage_totals.specialize_kernel + ms(now() - t_kernel)

    local t_machine = now()
    local machine = render:define_machine()
    stage_totals.define_machine = stage_totals.define_machine + ms(now() - t_machine)

    local t_compile = now()
    local unit = machine.gen:compile(D.target)
    local state = ensure_unit_state(unit)
    stage_totals.compile = stage_totals.compile + ms(now() - t_compile)

    local t_materialize = now()
    if state ~= nil then
        unit.__payload_keep = machine:materialize(D.target, assets, state)
    end
    stage_totals.materialize = stage_totals.materialize + ms(now() - t_materialize)

    compiled = {
        plan = plan,
        render = render,
        machine = machine,
        unit = unit,
    }
end
for _, v in pairs(stage_totals) do
    lower_total_ms = lower_total_ms + v
end
local lower_avg_ms = lower_total_ms / lower_iters

Backend.render_unit(runtime, compiled.unit)
collectgarbage("collect")
local start_render = now()
for _ = 1, render_iters do
    Backend.render_unit(runtime, compiled.unit)
end
local render_total_ms = ms(now() - start_render)
local render_avg_ms = render_total_ms / render_iters

print(string.format("METRIC backend %s", backend_name))
print_metric("bind_ms", bind_ms)
print_metric("resize_relower_total_ms", lower_total_ms)
print_metric("resize_relower_avg_ms", lower_avg_ms)
print_metric("flatten_avg_ms", stage_totals.flatten / lower_iters)
print_metric("prepare_demands_avg_ms", stage_totals.prepare_demands / lower_iters)
print_metric("solve_avg_ms", stage_totals.solve / lower_iters)
print_metric("plan_avg_ms", stage_totals.plan / lower_iters)
print_metric("specialize_kernel_avg_ms", stage_totals.specialize_kernel / lower_iters)
print_metric("define_machine_avg_ms", stage_totals.define_machine / lower_iters)
print_metric("compile_avg_ms", stage_totals.compile / lower_iters)
print_metric("materialize_avg_ms", stage_totals.materialize / lower_iters)
print_metric("render_total_ms", render_total_ms)
print_metric("render_avg_ms", render_avg_ms)
print(string.format("METRIC lower_iters %d", lower_iters))
print(string.format("METRIC render_iters %d", render_iters))

RawText.shutdown(runtime)
Backend.shutdown_window(runtime)
