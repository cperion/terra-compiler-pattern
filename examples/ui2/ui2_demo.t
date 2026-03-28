local Backend = require("examples.ui.backend_sdl_gl")
local RawText = require("examples.ui.backend_text_sdl_ttf")
local Schema = require("examples.ui2.ui2_schema")
local Demo = require("examples.ui2.ui2_demo_support")

local T = Schema.ctx
local D = Demo(T, Backend)

local L = D.L
local eid = D.eid
local solid = D.solid
local insets = D.insets
local fill_size = D.fill_size
local auto_size = D.auto_size

-- ============================================================================
-- ui2 demo
-- ----------------------------------------------------------------------------
-- Small direct end-to-end demo for the new ui2 pipeline.
--
-- What it exercises:
--   - full source -> bound -> flat -> demand -> solved -> plan -> kernel path
--   - built-in box / shadow / text / image placeholder rendering
--   - first-class custom family rendering
--   - viewport-driven recompilation on window resize
--   - reducer + intent emission without extra app/demo layers in the hot path
-- ============================================================================

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

local function compile_ui(viewport, assets)
    local document = build_document()
    local bound = document:bind(assets)
    local flat = bound:flatten(viewport)
    local demand = flat:prepare_demands(assets)
    local solved = demand:solve(assets)
    local plan = solved:plan()
    local render = plan:specialize_kernel()
    local unit = render:compile(D.target, assets)
    return {
        document = document,
        plan = plan,
        render = render,
        unit = unit,
    }
end

local runtime = Backend.init_window("ui2 demo", 800, 600)
RawText.init(runtime)

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

local session = T.UiSession.State.initial(T.UiCore.Size(runtime.state.width, runtime.state.height))
local demo_state = D.initial_state()
local compiled = compile_ui(session.viewport, assets)
local dirty = true

local running = true
while running do
    local event = Backend.poll_native_event(runtime)
    while event do
        if event.kind == "Quit" then
            running = false
            break
        end

        local input = D.ui_input_from_native(event)
        if input then
            local prev_viewport = session.viewport
            local applied = session:apply_with_intents(compiled.plan, input)
            session = applied.session
            dirty = true

            local prev_demo_state = demo_state
            demo_state = D.apply_intents(applied.intents, demo_state)

            if demo_state.selected ~= prev_demo_state.selected then
                print("ui2 demo selected -> " .. demo_state.selected)
            end
            if demo_state.focused ~= prev_demo_state.focused then
                print("ui2 demo focused -> " .. demo_state.focused)
            end

            if session.viewport ~= prev_viewport then
                compiled = compile_ui(session.viewport, assets)
                print(("ui2 demo: viewport %dx%d")
                    :format(session.viewport.w, session.viewport.h))
            end
        end
        event = Backend.poll_native_event(runtime)
    end

    if dirty then
        Backend.render_unit(runtime, compiled.unit)
        dirty = false
    else
        Backend.FFI.SDL_Delay(1)
    end
end

RawText.shutdown(runtime)
Backend.shutdown_window(runtime)
